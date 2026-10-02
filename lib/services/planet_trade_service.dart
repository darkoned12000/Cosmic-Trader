import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';

/// One share of an order, filled by one port.
class TradeAllocation {
  const TradeAllocation({
    required this.portSectorId,
    required this.units,
    required this.hops,
    required this.ticksPerRun,
    required this.unitPrice,
  });

  final int portSectorId;
  final int units;
  final int hops;
  final int ticksPerRun;
  final int unitPrice;
}

/// The result of [PlanetTradeService.plan]: nearest-first shares plus what
/// the galaxy could not absorb.
class TradePlan {
  const TradePlan({
    required this.allocations,
    required this.unitsRequested,
    required this.unitsAllocated,
  });

  final List<TradeAllocation> allocations;
  final int unitsRequested;
  final int unitsAllocated;

  int get shortfall => unitsRequested - unitsAllocated;
}

/// One verb, one owner for planet trade jobs.
///
/// A job is a bulk order placed against a port. It takes several ticks to
/// deliver, and the countdown is driven here so the tick and the screen
/// cannot disagree about when goods arrive.
///
/// The tick owns the *world*, the screen owns the *pilot*: a buy delivery
/// lands in the planet's store (via [Planet.deposit], so overflow spills to
/// the shipment pool exactly as production does), and a sell delivery earns
/// into the world's `accumulatedRevenue`, which the owner withdraws. The tick
/// never touches a player, so there is no read-modify-write clobber.
class PlanetTradeService {
  const PlanetTradeService._();

  /// Ticks per hop of a cargo run. One hop is a minute of play at the 30s
  /// tick, so the median four-hop port is a four-minute run. Distance sets
  /// the cadence; order size sets the number of runs; the two do not interact.
  static const int ticksPerHop = 2;

  /// Base failure chance for a run to a same-sector port (0%).
  ///
  /// Failure is distance-driven: a run across the same sector cannot be
  /// intercepted, so the floor is zero and the rate climbs with each hop.
  static const double failureChanceBase = 0.0;

  /// Additional failure chance per hop beyond the first.
  ///
  /// Tuned so a median four-hop run is ~2.4%: the doc's 16-run 80,000-unit
  /// Citadel order then loses at least one run about a third of the time —
  /// a real decision pressure, not a tax, and the reason a player splits a
  /// large order into smaller ones. The rate is on the *run*, so order size
  /// (run count) drives total exposure while each individual loss stays one
  /// run's worth of value; per-run value in credits scales with the
  /// commodity's price, which is what T8's insurance would cover.
  static const double failureChancePerHop = 0.006;

  /// Failure chance for a single run [hops] sectors away, 0.0 to 1.0.
  ///
  /// Deterministic given the distance, which is the point: the *risk* is
  /// knowable before the order is placed, so the player can see it on the
  /// quote and decide, while the *roll* is injected.
  static double failureChanceForHops(int hops) {
    if (hops <= 0) return 0.0;
    return (failureChanceBase + failureChancePerHop * hops).clamp(0.0, 1.0);
  }

  /// Credits owed per pilot for insured runs that were destroyed, drained by
  /// the shell.
  ///
  /// **A tally, not a write.** The tick resolves runs and has no player, and the
  /// one rule about tick-driven money is that the tick must not write one — the
  /// read-modify-write window that ate colonist recruits. So the service counts,
  /// the tick leaves it here, and the shell drains it and credits the pilot —
  /// the same split the citadel-completion reward uses.
  ///
  /// Keyed by **player id** rather than faction, because unlike a reputation
  /// award the indemnity belongs to the pilot who placed the order and to nobody
  /// else; a single shared pot would credit whichever player happened to render
  /// next.
  static final Map<String, int> indemnityOwed = {};

  /// Takes and clears what is owed to [playerId].
  ///
  /// Draining rather than reading is load-bearing. A getter that only reads
  /// would let the same refund be credited on every poll for as long as the app
  /// ran, which is the per-tick-getter trap in a new costume: the number looks
  /// right and the side effect is the bug.
  static int takeIndemnityFor(String playerId) {
    final owed = indemnityOwed.remove(playerId) ?? 0;
    return owed;
  }

  /// Chance that at least one run of [plan] is lost: `1 - Π(1 - p)`.
  ///
  /// **One rule, in the service.** This arithmetic used to live in the market
  /// panel's quote line, and insurance needs the same figure to price itself. Two
  /// copies of a probability is two chances for the premium to be priced off a
  /// different risk than the one the player was shown — and the player would
  /// have no way to tell, because the quote would still read correctly.
  static double orderRiskFraction(TradePlan plan) {
    var survive = 1.0;
    for (final a in plan.allocations) {
      final runs = (a.units / freighterHold).ceil();
      for (var r = 0; r < runs; r++) {
        survive *= 1 - failureChanceForHops(a.hops);
      }
    }
    return (1 - survive).clamp(0.0, 1.0);
  }

  /// How much the house charges over the expected loss.
  ///
  /// One constant, so the two coverage tiers cannot disagree about what cover
  /// costs — a per-tier table is a second place for the margin to drift, and the
  /// relationship the player can see ("risk 2%, cover 3%") is worth more than
  /// tuning each tier separately.
  ///
  /// Deliberately not 1.0. At exactly the expected loss a policy is a fair bet
  /// with no edge and no reason to exist; this is the player's money to lose
  /// either way, so the premium has to be worth paying for the peace of mind.
  static const double insuranceMargin = 1.6;

  /// Credits to buy [insurance] on [plan], 0 when uncovered.
  ///
  /// **Derived from the order's own risk rather than a flat rate.** Two
  /// consequences, both wanted: a same-sector order (0% risk) is free to insure,
  /// which is honest and teaches the risk system, and a long haul is expensive,
  /// so the premium is itself a statement about the route. A flat rate would
  /// overcharge short runs and make cover a bargain on exactly the routes where
  /// the player most needs to think.
  ///
  /// The premium is quoted against the order's **face value**, in both
  /// directions: for a sell that is the revenue the world would have earned.
  static int premiumFor(TradePlan plan, TradeInsurance insurance) {
    if (insurance == TradeInsurance.none || plan.allocations.isEmpty) return 0;
    var value = 0;
    for (final a in plan.allocations) {
      value += a.units * a.unitPrice;
    }
    final fraction =
        orderRiskFraction(plan) * insurance.coverage * insuranceMargin;
    return (value * fraction).round();
  }

  /// What an insurer pays back for [units] destroyed on an insured [job].
  ///
  /// Returns credits for a **buy** — the pilot prepaid for goods that no longer
  /// exist — and **units** for a sell, because indemnity restores the asset, not
  /// the market price. A seller whose cargo is destroyed gets their minerals
  /// back, not the credits they would have earned: the price was never theirs to
  /// collect, and paying it out would be paying for a sale that did not happen.
  static int indemnityUnits(TradeJob job, int units) {
    if (!job.isInsured) return 0;
    return (units * job.insurance.coverage).round();
  }

  /// How much weight each cause carries on a route, so a loss can explain
  /// *itself*.
  ///
  /// Contextual by design: pirates dominate where pirates are and on long
  /// hauls, a federal port seizes and a free port does not, an anomaly sector
  /// throws storms, and a same-sector run can only ever fail mechanically. A
  /// reason drawn from the same pool everywhere would tell the player nothing
  /// about the route they chose — which is the one thing they would change
  /// after reading it.
  ///
  /// **Deterministic given the context**, exactly like
  /// [failureChanceForHops]: the weights are a rule (so a test can assert a
  /// cause is *unreachable* on a route), and the pick is the injected roll.
  /// A zero weight is therefore a promise, not a rarity.
  static Map<TradeFailureCause, int> causeWeightsFor({
    required int hops,
    required PortClass portClass,
    required int piratesAtPort,
    required bool anomalyAtPort,
    required bool navHazAtPort,
  }) {
    final span = hops.clamp(0, 4);
    final pirates = piratesAtPort > 0;
    return {
      // No pirates in orbit of your own sector: a same-sector run is a
      // mechanical failure or nothing.
      TradeFailureCause.piratesDestroyed:
          (span <= 0 ? 0 : 30) + 25 * span + (pirates ? 40 : 0),
      TradeFailureCause.piratesHijacked:
          (span <= 0 ? 0 : 15) + 12 * span + (pirates ? 30 : 0),
      TradeFailureCause.fuelContainment: 12 + 6 * span + (navHazAtPort ? 8 : 0),
      TradeFailureCause.rerouted: 10 + 5 * span,
      // Federal only: an independent or free port has no customs to seize
      // against.
      TradeFailureCause.customsSeizure: portClass == PortClass.federal ? 18 : 0,
      TradeFailureCause.anomalyStorm: anomalyAtPort ? 30 : 0,
    };
  }

  /// Picks a cause from [weights] using [rng].
  ///
  /// Returns null when every weight is zero. That cannot happen for a real
  /// route — the mechanical cause always carries something — but it is
  /// handled rather than assumed, because a zero total with a modulo throws
  /// inside the tick and takes the whole pass down with it.
  ///
  /// **A zero weight is a promise, and the arithmetic keeps it — not the
  /// guard.** `roll < 0` is never true and `roll -= 0` is a no-op, so
  /// deleting the zero-weight `continue` changes no outcome at all. That was
  /// measured (fault-injected, nothing failed), so the line is kept for
  /// clarity rather than credited with enforcing anything: the guarantee is
  /// the subtraction, and a sign flip there *is* caught — by the sweep in
  /// `test/planet_trade_jobs_test.dart`, not by this comment.
  static TradeFailureCause? pickCause(
      Map<TradeFailureCause, int> weights, math.Random rng) {
    final total = weights.values.fold<int>(0, (a, b) => a + b);
    if (total <= 0) return null;
    var roll = rng.nextInt(total);
    for (final entry in weights.entries) {
      if (entry.value <= 0) continue;
      if (roll < entry.value) return entry.key;
      roll -= entry.value;
    }
    // Unreachable: the loop consumed `total` exactly. Named rather than
    // asserted so a future edit that changes the arithmetic degrades to "the
    // last cause" instead of throwing.
    return weights.entries.lastWhere((e) => e.value > 0).key;
  }

  /// Records one resolved run on the world's history, trimmed to
  /// [Planet.tradeIncidentHistory].
  ///
  /// Newest last, so the report reads oldest-to-newest like a ledger.
  static void recordIncident(Planet planet, TradeIncident incident) {
    planet.tradeIncidents.add(incident);
    while (planet.tradeIncidents.length > Planet.tradeIncidentHistory) {
      planet.tradeIncidents.removeAt(0);
    }
  }

  /// Units one port-freighter run carries.
  ///
  /// The player's hold and engine are deliberately not involved — the job is
  /// a credit-and-time cost — so this is the port's hull, not the pilot's.
  /// Sized so the documented order (80,000 minerals across a median four-hop
  /// run) lands in 16 runs over about an hour, with a delivery every four
  /// minutes.
  static const int freighterHold = 5000;

  /// Places an order on [planet]. Returns the job, so the caller can report it.
  ///
  /// Sell goods leave the store at order time — a sell of goods still sitting
  /// in the store is a reservation the world cannot keep. Returns null when
  /// the order cannot be placed (nothing to sell, unknown commodity).
  static TradeJob? create({
    required Planet planet,
    required String playerId,
    required int portSectorId,
    required String commodity,
    required TradeDirection direction,
    required int units,
    required int ticksPerRun,
    int unitPrice = 0,
    int? unitsPerRun,
    String? orderId,
    int? escrowed,
    String? jobId,
  }) {
    if (units <= 0 || ticksPerRun <= 0) return null;
    if (direction == TradeDirection.sell) {
      if (!_takesFromStore(planet, commodity, units)) return null;
    }
    final job = TradeJob(
      id: jobId,
      playerId: playerId,
      planetId: planet.id,
      portSectorId: portSectorId,
      commodity: commodity,
      direction: direction,
      unitsTotal: units,
      ticksPerRun: ticksPerRun,
      unitPrice: unitPrice,
      unitsPerRun: unitsPerRun,
      orderId: orderId,
      escrowed: escrowed,
    );
    planet.tradeJobs.add(job);
    return job;
  }

  /// Cancels one in-flight job by id. A buy refund is the caller's business
  /// (it paid up front); a sell returns the undelivered remainder to the store.
  ///
  /// Returns true when a job was removed.
  static bool cancel(Planet planet, String jobId) {
    final index = planet.tradeJobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return false;
    final job = planet.tradeJobs.removeAt(index);
    if (job.direction == TradeDirection.sell && job.unitsRemaining > 0) {
      planet.deposit(job.commodity, job.unitsRemaining);
    }
    return true;
  }

  /// Advances every job in [universe] by one tick, rolling each run that
  /// comes due for failure.
  ///
  /// [rng] is the generator the failure rolls draw from. **Required, not
  /// optional**: a probability tested against a real `Random` is a test of the
  /// weather, and a caller that forgot to inject would silently get a
  /// different game. The tick passes its own shared `_tickRng`; tests pass a
  /// fixed one and reach both branches. [rng] is also seeded per run off the
  /// job, so a re-dispatched share does not re-roll a fixed generator's
  /// history.
  ///
  /// Each job's risk is priced by its own BFS distance to its port (built
  /// lazily, only for planets that actually have jobs), so a same-sector run
  /// is risk-free and a four-hop run carries the distance premium. See
  /// [failureChanceForHops].
  ///
  /// Returns the runs that resolved this tick keyed by job id. A job stays
  /// listed until its final run resolves; a lost run consumes its units (they
  /// are gone), so the job advances and the remainder continues.
  ///
  /// **The cause decides what happens, not just why.** The roll only says
  /// "something went wrong"; [TradeFailureCause.outcome] says what — lost,
  /// delayed or seized — so a diverted freighter costs patience and not goods,
  /// and a customs impoundment delivers most of the run. Collapsing all three
  /// into "the cargo is gone" is what made the reason cosmetic.
  static Map<
      String,
      ({
        Planet planet,
        TradeJob job,
        int units,
        int deliveredUnits,
        int seizedUnits,
        int delayTicks,
        int insuredUnits,
        TradeRunOutcome outcome,
        TradeFailureCause? cause,
        TradeDirection direction
      })> advanceAll(List<Sector> universe, {required math.Random rng}) {
    final landed = <String,
        ({
      Planet planet,
      TradeJob job,
      int units,
      int deliveredUnits,
      int seizedUnits,
      int delayTicks,
      int insuredUnits,
      TradeRunOutcome outcome,
      TradeFailureCause? cause,
      TradeDirection direction
    })>{};

    // job id -> route context, built once per planet-with-jobs per tick.
    final routesByJob = _buildRoutesByJob(universe);
    final tick = GameClock.tick;
    // Orders that became final this pass, closed after the walk rather than
    // from inside it — the walk removes the last share, and a split order is
    // only finished once *every* share has gone.
    final finished = <Planet, Set<String>>{};

    for (final sector in universe) {
      for (final planet in sector.planets) {
        if (planet.tradeJobs.isEmpty) continue;

        // Iterate a copy: a job that completes is removed from the planet,
        // and mutating a list while walking it skips entries.
        for (final job in List<TradeJob>.from(planet.tradeJobs)) {
          final units = job.advance();
          if (units <= 0) continue;

          // The roll, on the run that just came due.
          final route = routesByJob[job.id];
          final hops = route?.hops ?? 0;
          final failed = rng.nextDouble() < failureChanceForHops(hops);

          var outcome = TradeRunOutcome.delivered;
          TradeFailureCause? cause;
          var deliveredUnits = units;
          var seizedUnits = 0;
          var delayTicks = 0;
          var insuredUnits = 0;

          if (!failed) {
            _applyLanding(planet, job, units);
          } else {
            cause = pickCause(
              causeWeightsFor(
                hops: hops,
                portClass: route?.portClass ?? PortClass.free,
                piratesAtPort: route?.piratesAtPort ?? 0,
                anomalyAtPort: route?.anomalyAtPort ?? false,
                navHazAtPort: route?.navHazAtPort ?? false,
              ),
              rng,
            );
            // A null cause is unreachable in practice — the mechanical one
            // always carries weight — but it is treated as the *worst* case
            // rather than as a clean delivery, so a future edit that can return
            // null costs the player goods instead of handing them out.
            outcome = cause?.outcome ?? TradeRunOutcome.lost;

            switch (outcome) {
              case TradeRunOutcome.delivered:
                // Unreachable via a non-null cause: every cause declares a
                // non-delivered outcome. Handled anyway, because a future cause
                // added with the wrong value would otherwise consume the units
                // *and* pay out for them.
                _applyLanding(planet, job, units);
              case TradeRunOutcome.delayed:
                // Nothing is lost and nothing is consumed: `advance()` already
                // took the units off `unitsRemaining`, so they go back and the
                // run is attempted again later. The reservation is untouched,
                // which is what makes a diversion cost time and nothing else.
                job.unitsRemaining += units;
                delayTicks = cause?.delayTicks ?? 0;
                job.ticksRemaining += delayTicks;
                deliveredUnits = 0;
              case TradeRunOutcome.seized:
                // A partial delivery: most of the run arrives, the rest is
                // impounded. The two halves are accounted separately so the
                // row and the order record can say which happened.
                seizedUnits = _seizedUnits(units);
                deliveredUnits = units - seizedUnits;
                job.unitsSeized += seizedUnits;
                if (deliveredUnits > 0) {
                  _applyLanding(planet, job, deliveredUnits);
                }
                // The impounded share of the reservation goes back: the port
                // never received those goods.
                releaseRunSlice(universe, job, seizedUnits);
              case TradeRunOutcome.lost:
                job.unitsLost += units;
                deliveredUnits = 0;
                // Indemnity, on the **lost** branch only. A seizure is not
                // covered: customs is a legal consequence of the route, not an
                // accident of the transit, and a policy that paid out on both
                // would be a flat refund with a premium attached.
                insuredUnits = indemnityUnits(job, units);
                if (insuredUnits > 0) {
                  if (job.direction == TradeDirection.buy) {
                    // The pilot prepaid for goods that no longer exist. Owed, not
                    // paid: see [indemnityOwed].
                    indemnityOwed[job.playerId] =
                        (indemnityOwed[job.playerId] ?? 0) +
                            insuredUnits * job.unitPrice;
                  } else {
                    // A sell is indemnified in **goods**, not revenue: the price
                    // was never the world's to collect, and paying it out would
                    // be paying for a sale that never happened.
                    planet.deposit(job.commodity, insuredUnits);
                  }
                }
                // The reservation slice comes back to the port. Previously the
                // whole thing stayed consumed, which leaked on every loss: the
                // world lost the goods, the port lost the demand slot *and* the
                // escrow, and nobody received anything.
                //
                // Only for a **sell**, and the asymmetry is deliberate. In a
                // sell the port is the buyer: it set goods and money aside
                // pending arrival, they never arrived, so it is made whole and
                // the world eats the freight. In a buy the port had already
                // taken the credits and the goods had left its shelf — its side
                // of the deal completed before the freight existed — so
                // releasing there too would hand back both stock and payment
                // for goods that no longer exist, and make failure free.
                if (job.direction == TradeDirection.sell) {
                  releaseRunSlice(universe, job, units);
                }
            }
          }

          job.lastRunFailed = outcome == TradeRunOutcome.lost;

          // One ledger entry per resolved run, whatever became of it, so the
          // Report can answer "what happened to my freight" long after the log
          // line has rolled off its 200-entry ring.
          recordIncident(
            planet,
            TradeIncident(
              orderId: job.orderId,
              tick: tick,
              commodity: job.commodity,
              direction: job.direction,
              units: units,
              portSectorId: job.portSectorId,
              outcome: outcome,
              cause: cause,
              seizedUnits: seizedUnits,
              delayTicks: delayTicks,
              insuredUnits: insuredUnits,
              jobId: job.id,
              insurance: job.insurance,
              premiumPaid: job.premiumPaid,
            ),
          );

          if (job.isComplete) {
            planet.tradeJobs.remove(job);
            if (job.orderId.isNotEmpty) {
              finished.putIfAbsent(planet, () => <String>{}).add(job.orderId);
            }
          }
          landed[job.id] = (
            planet: planet,
            job: job,
            units: units,
            deliveredUnits: deliveredUnits,
            seizedUnits: seizedUnits,
            delayTicks: delayTicks,
            insuredUnits: insuredUnits,
            outcome: outcome,
            cause: cause,
            direction: job.direction,
          );
        }
      }
    }

    // A split order across four ports records one 80,000-unit order, not four
    // 20,000-unit ones.
    finished.forEach((planet, orderIds) {
      for (final orderId in orderIds) {
        if (planet.tradeJobs.any((j) => j.orderId == orderId)) continue;
        closeOrder(planet, orderId, tick: tick);
      }
    });

    return landed;
  }

  /// Units customs impound out of a run that [TradeRunOutcome.seized] names.
  ///
  /// A **deterministic quarter**, not a roll. Two reasons, and the second is
  /// the one that matters: it is readable ("customs takes about a quarter"), so
  /// a player seized repeatedly knows what to do about it; and it keeps the
  /// injected generator meaning exactly one thing — *whether* the run went
  /// wrong — so a test does not have to satisfy two rolls to reach the branch
  /// it is about.
  ///
  /// Floors at one unit so a multi-unit "seizure" always leaves something on
  /// the ship, and takes the whole run when it is a single unit: a one-unit
  /// shipment is not partially delivered, and reporting it as a seizure would
  /// be a loss wearing a kinder hat.
  static int _seizedUnits(int units) {
    if (units <= 1) return units;
    return (units * seizureFraction).round().clamp(1, units - 1);
  }

  /// The share of an impounded run customs takes. See [_seizedUnits].
  static const double seizureFraction = 0.25;

  /// Hands back the reservation slice covering [units] that never arrived.
  ///
  /// The whole reservation is unwound on cancel, so a slice per loss means
  /// cancel has to know what is left — [TradeJob.escrowOutstanding] is for
  /// that. Slicing by the *nominal* unit price would be wrong on a sell: the
  /// escrow is what the port's pool actually moved, clamped and possibly less
  /// than the order's face value, so a nominal share of it is not the recorded
  /// share. This takes the recorded figure, and the **final** slice takes
  /// whatever is outstanding so integer rounding cannot strand credits on a job
  /// that then completes.
  static void releaseRunSlice(
    List<Sector> universe,
    TradeJob job,
    int units,
  ) {
    if (units <= 0) return;
    final outstanding = job.escrowOutstanding;
    if (outstanding <= 0) return;

    // **The last slice is the one where nothing is left owed** — `unitsRemaining`
    // was already decremented by `advance()` before this runs. Comparing against
    // it as if it still counted the current run (`units >= unitsRemaining`)
    // makes every *equal-sized* run look final: an 8,000-unit order in two
    // 4,000-unit runs released the whole escrow on the first loss, and the
    // second loss then released it again — minting the port's credits out of
    // nothing. The guard is the loss-then-cancel conservation check.
    final isFinalSlice = job.unitsRemaining <= 0;
    final slice = isFinalSlice
        ? outstanding
        : math.min(
            outstanding,
            (outstanding * units / math.max(1, job.unitsTotal)).round(),
          );
    if (slice <= 0) return;

    releaseReservation(
      universe: universe,
      portSectorId: job.portSectorId,
      commodity: job.commodity,
      direction: job.direction,
      units: units,
      unitPrice: job.unitPrice,
      // Only a sell escrowed anything, and `escrowOutstanding` is 0 for a buy
      // — so the recorded figure is what moves, which is nothing on a buy.
      escrowed: slice,
    );
    job.escrowedReleased += slice;
  }

  /// What the order's cover cost, counting each share once.
  ///
  /// Groups by [TradeIncident.jobId] rather than summing. Legacy incidents
  /// carry no job id and all collapse into one bucket, which is harmless: they
  /// predate cover, so every one of them has a premium of zero.
  static int _premiumFor(List<TradeIncident> runs) {
    final seen = <String, int>{};
    for (final r in runs) {
      seen.putIfAbsent(r.jobId, () => r.premiumPaid);
    }
    return seen.values.fold<int>(0, (a, b) => a + b);
  }

  /// Writes a finished order into the world's history.
  ///
  /// Totals come from the **incident ledger**, not from the jobs: by the time
  /// this runs the last share has left `tradeJobs`, so the job objects are gone.
  /// That is why `orderId` is stamped on every incident — it is the only thing
  /// that still ties a run back to the request that created it.
  ///
  /// No-op when the order's runs have already been evicted from the ten-entry
  /// ledger. A record of zeroes would be worse than no record, because it reads
  /// as "you received nothing" rather than "we no longer know".
  static void closeOrder(Planet planet, String orderId, {int? tick}) {
    if (orderId.isEmpty) return;
    if (planet.tradeOrders.any((o) => o.orderId == orderId)) return;

    final runs = planet.tradeIncidents
        .where((i) => i.orderId == orderId)
        .toList(growable: false);
    if (runs.isEmpty) return;

    final first = runs.first;
    planet.tradeOrders.add(TradeOrderRecord(
      orderId: orderId,
      tick: tick ?? first.tick,
      commodity: first.commodity,
      direction: first.direction,
      unitsTotal: runs.fold<int>(0, (a, r) => a + r.units),
      unitsDelivered: runs.fold<int>(0, (a, r) => a + r.deliveredUnits),
      unitsLost: runs.fold<int>(0, (a, r) => a + r.lostUnits),
      unitsSeized: runs.fold<int>(0, (a, r) => a + r.seizedUnits),
      runs: runs.length,
      insurance: first.insurance,
      // **Each share counted once.** `premiumPaid` is a per-share figure held
      // on every run of that share, so a plain sum would multiply it by the run
      // count — an eight-run order would report eight times what it paid. The
      // distinct-share grouping is the whole reason the incident carries
      // `jobId`.
      premium: _premiumFor(runs),
      ports: runs.map((r) => r.portSectorId).toSet().toList(growable: false),
    ));
    while (planet.tradeOrders.length > Planet.tradeOrderHistory) {
      planet.tradeOrders.removeAt(0);
    }
  }

  /// What a failure roll needs to know about a job's route: distance, the
  /// destination port's class, and whether pirates, an anomaly or nav hazards
  /// sit at the far end.
  ///
  /// Recorded per job id, built once per planet-with-jobs per tick — a handful
  /// of O(sectors) passes against the tick's NPC work. A job whose port is
  /// unreachable gets hops 0 and a free-port context, the safe direction: an
  /// unreachable port cannot deliver, so its failures are not the player's
  /// problem to insure.
  static Map<
      String,
      ({
        int hops,
        PortClass portClass,
        int piratesAtPort,
        bool anomalyAtPort,
        bool navHazAtPort
      })> _buildRoutesByJob(List<Sector> universe) {
    final out = <String,
        ({
      int hops,
      PortClass portClass,
      int piratesAtPort,
      bool anomalyAtPort,
      bool navHazAtPort
    })>{};
    final byId = {for (final s in universe) s.id: s};
    for (final sector in universe) {
      for (final planet in sector.planets) {
        if (planet.tradeJobs.isEmpty) continue;
        final parents = PathfindingService.bfsParents(universe, sector.id);
        for (final job in planet.tradeJobs) {
          final at = byId[job.portSectorId];
          out[job.id] = (
            hops:
                PathfindingService.distanceInTree(parents, job.portSectorId) ??
                    0,
            portClass: at?.port?.portClass ?? PortClass.free,
            piratesAtPort: at?.pirateCount ?? 0,
            anomalyAtPort: at?.anomaly != null,
            navHazAtPort: at?.navHaz ?? false,
          );
        }
      }
    }
    return out;
  }

  /// Pure port selection: nearest first, split across ports when one cannot
  /// absorb the order.
  ///
  /// No mutation — no jobs, no port stock, no credits. The caller decides
  /// what to do with the shares ([createOrder] is the order path). Pure so
  /// the Port Report and the order path cannot disagree about who can trade.
  ///
  /// A port qualifies only when it actually trades the commodity in the
  /// needed direction with stock on the shelf: a buy needs `sells()` plus
  /// `supply`, a sell needs `buys()` plus `demand`. Capacity is the live
  /// quantity, not the max — a reservation against a cap nobody holds is a
  /// promise the port cannot keep.
  static TradePlan plan({
    required List<Sector> universe,
    required Planet planet,
    required String commodity,
    required TradeDirection direction,
    required int volume,
  }) {
    if (volume <= 0) {
      return TradePlan(
          allocations: const [], unitsRequested: volume, unitsAllocated: 0);
    }
    final homeId = _sectorOf(universe, planet.id);
    if (homeId == null) {
      return TradePlan(
          allocations: const [], unitsRequested: volume, unitsAllocated: 0);
    }

    // One BFS pass answers every distance query out of the world's sector.
    final parents = PathfindingService.bfsParents(universe, homeId);
    final candidates = <({int sectorId, int hops, int capacity, int price})>[];
    for (final sector in universe) {
      final port = sector.port;
      if (port == null || port.isDestroyed) continue;
      final int capacity;
      final int price;
      if (direction == TradeDirection.buy) {
        if (!port.sells(commodity)) continue;
        capacity = port.getSupply(commodity);
        if (capacity <= 0) continue;
        price = port.getEffectiveSellPrice(commodity).round();
      } else {
        if (!port.buys(commodity)) continue;
        capacity = port.getDemand(commodity);
        if (capacity <= 0) continue;
        price = port.getEffectiveBuyPrice(commodity).round();
      }
      final hops = sector.id == homeId
          ? 0
          : PathfindingService.distanceInTree(parents, sector.id);
      if (hops == null) continue;
      candidates.add(
          (sectorId: sector.id, hops: hops, capacity: capacity, price: price));
    }

    // Nearest first; sector id breaks ties so the order is deterministic
    // rather than input-order dependent.
    candidates.sort((a, b) {
      final byHops = a.hops.compareTo(b.hops);
      return byHops != 0 ? byHops : a.sectorId.compareTo(b.sectorId);
    });

    var remaining = volume;
    var allocated = 0;
    final shares = <TradeAllocation>[];
    for (final c in candidates) {
      if (remaining <= 0) break;
      final take = c.capacity < remaining ? c.capacity : remaining;
      if (take <= 0) continue;
      shares.add(TradeAllocation(
        portSectorId: c.sectorId,
        units: take,
        hops: c.hops,
        ticksPerRun: c.hops <= 0 ? 1 : c.hops * ticksPerHop,
        unitPrice: c.price,
      ));
      remaining -= take;
      allocated += take;
    }
    return TradePlan(
        allocations: shares, unitsRequested: volume, unitsAllocated: allocated);
  }

  /// Plans, reserves, and places a paid order: the full T5 transaction in one
  /// call, so the screen cannot half-implement it.
  ///
  /// Each share is reserved at its port ([reserveShare]) and then created;
  /// a share whose reservation fails is shortfall, not a job. Sell volume is
  /// clamped to the store first, so creation cannot fail mid-loop and strand
  /// a reservation. Returns the order id (one request, one row), the jobs,
  /// the credits that changed hands with ports, the units placed, the
  /// shortfall, and every port sector touched (for the caller's write-back).
  ///
  /// This replaced `planAndCreate`, which is deleted rather than kept beside
  /// it: that path created sell jobs (spending planet goods) without ever
  /// reserving the port side, manufacturing value from nothing, and two order
  /// paths sharing `create` is how they disagree. One seam.
  static ({
    String orderId,
    List<TradeJob> jobs,
    int spent,
    int premium,
    int placedUnits,
    int shortfall,
    List<int> portSectorIds,
  }) createOrder({
    required Planet planet,
    required List<Sector> universe,
    required String playerId,
    required String commodity,
    required TradeDirection direction,
    required int volume,
    required String actorFaction,
    TradeInsurance insurance = TradeInsurance.none,
  }) {
    final clamped = direction == TradeDirection.sell
        ? (volume < planet.storedFor(commodity)
            ? volume
            : planet.storedFor(commodity))
        : volume;
    final planResult = plan(
        universe: universe,
        planet: planet,
        commodity: commodity,
        direction: direction,
        volume: clamped);
    final orderId = const Uuid().v4();
    final jobs = <TradeJob>[];
    final touched = <int>{};
    var spent = 0;
    var placedUnits = 0;

    // One premium for the **order**, split across its shares by face value.
    //
    // Per-share pricing would make the total depend on how the planner happened
    // to split it — two identical orders split differently would cost different
    // amounts for the same cover, which is the kind of thing a player notices and
    // cannot explain. The last share takes the rounding remainder so the parts
    // always sum to the whole.
    final premiumTotal = premiumFor(planResult, insurance);
    var planValue = 0;
    for (final a in planResult.allocations) {
      planValue += a.units * a.unitPrice;
    }
    var premiumAllocated = 0;

    final shares = planResult.allocations;
    for (var shareIndex = 0; shareIndex < shares.length; shareIndex++) {
      final share = shares[shareIndex];
      final reservation = reserveShare(
        universe: universe,
        share: share,
        commodity: commodity,
        direction: direction,
        actorFaction: actorFaction,
      );
      if (reservation == null) continue;
      final job = create(
        planet: planet,
        playerId: playerId,
        portSectorId: share.portSectorId,
        commodity: commodity,
        direction: direction,
        units: share.units,
        ticksPerRun: share.ticksPerRun,
        unitPrice: share.unitPrice,
        unitsPerRun: freighterHold,
        orderId: orderId,
        escrowed: reservation.escrowed,
      );
      if (job == null) {
        // Unreachable: sell volume was clamped to the store above and buy
        // creation cannot fail — but a stranded reservation (paid for, no
        // job) is worse than dead code, so release rather than trust it.
        releaseReservation(
          universe: universe,
          portSectorId: share.portSectorId,
          commodity: commodity,
          direction: direction,
          units: share.units,
          unitPrice: share.unitPrice,
          escrowed: reservation.escrowed,
        );
        continue;
      }
      final isLastShare = shareIndex == shares.length - 1;
      job.insurance = insurance;
      job.premiumPaid = isLastShare
          ? premiumTotal - premiumAllocated
          : (premiumTotal *
                  (share.units * share.unitPrice) /
                  (planValue <= 0 ? 1 : planValue))
              .round();
      premiumAllocated += job.premiumPaid;
      spent += reservation.value;
      placedUnits += share.units;
      touched.add(share.portSectorId);
      jobs.add(job);
    }
    return (
      orderId: orderId,
      jobs: jobs,
      spent: spent,
      premium: premiumTotal,
      placedUnits: placedUnits,
      shortfall: clamped - placedUnits,
      portSectorIds: touched.toList(),
    );
  }

  /// Cancels a whole order — every share placed by one request — by order id
  /// (or, for pre-grouping jobs with none, by job id).
  ///
  /// Releases each share's unlanded remainder to its port, returns sell goods
  /// to the store, and reports the buy refund owed to the pilot plus every
  /// port sector touched. Delivered runs stay delivered on both sides.
  static ({int refund, List<int> portSectorIds}) cancelOrder(
    Planet planet,
    List<Sector> universe,
    String orderId,
  ) {
    final group = planet.tradeJobs
        .where((j) => j.orderId == orderId || j.id == orderId)
        .toList();
    var refund = 0;
    final touched = <int>{};
    for (final job in group) {
      refund += refundFor(job);
      releaseShare(universe, job);
      touched.add(job.portSectorId);
      cancel(planet, job.id);
    }
    return (refund: refund, portSectorIds: touched.toList());
  }

  static int? _sectorOf(List<Sector> universe, String planetId) {
    for (final sector in universe) {
      for (final world in sector.planets) {
        if (world.id == planetId) return sector.id;
      }
    }
    return null;
  }

  /// Reserves one planned share against its port: the paid order owns the
  /// goods, not the race for them.
  ///
  /// Buy takes `supply` off the shelf and pays the port; sell takes `demand`
  /// off the book and escrows the payout from `portCredits` (clamped at 0,
  /// the player-port sell convention — a port can go broke paying). The
  /// port's object is replaced via `copyWith`; the sector list itself is the
  /// caller's to save. Records the trade in the session metrics at the live
  /// price, like a player-port trade does.
  ///
  /// Returns the nominal value plus what the pool actually moved, or null
  /// when the port can no longer honor the share (gone, destroyed, or stock
  /// moved since the plan). The caller skips null shares — a reservation
  /// that cannot be made is shortfall, not a job.
  ///
  /// `value` and `escrowed` differ exactly when the pool cannot cover the
  /// order: the pilot still pays (buy) or earns (sell landing) the nominal
  /// price — the player-port convention — but only `escrowed` left the pool,
  /// and only `escrowed` comes back on release. Releasing the nominal figure
  /// instead mints the difference on every reserve-then-cancel against a
  /// cash-poor port.
  static ({int value, int escrowed})? reserveShare({
    required List<Sector> universe,
    required TradeAllocation share,
    required String commodity,
    required TradeDirection direction,
    required String actorFaction,
  }) {
    Sector? sector;
    for (final s in universe) {
      if (s.id == share.portSectorId) {
        sector = s;
        break;
      }
    }
    final port = sector?.port;
    if (sector == null || port == null || port.isDestroyed) return null;
    final value = share.units * share.unitPrice;
    if (direction == TradeDirection.buy) {
      if (!port.sells(commodity) || port.getSupply(commodity) < share.units) {
        return null;
      }
      sector.port = port.copyWith(
        supply: {
          ...port.supply,
          commodity: port.getSupply(commodity) - share.units
        },
        portCredits: port.portCredits + value,
      );
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: share.units,
        credits: value,
        actorFaction: actorFaction,
        isPlayer: true,
        isBuy: true,
      );
      return (value: value, escrowed: value);
    } else {
      if (!port.buys(commodity) || port.getDemand(commodity) < share.units) {
        return null;
      }
      // What actually left the pool: the rest was never there to escrow.
      final escrowed =
          value < port.portCredits ? value : port.portCredits.toInt();
      sector.port = port.copyWith(
        demand: {
          ...port.demand,
          commodity: port.getDemand(commodity) - share.units
        },
        portCredits: port.portCredits - escrowed,
      );
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: share.units,
        credits: value,
        actorFaction: actorFaction,
        isPlayer: true,
        isBuy: false,
      );
      return (value: value, escrowed: escrowed);
    }
  }

  /// Credits the pilot is owed for cancelling [job]: the undelivered remainder
  /// of a buy (paid up front). A sell refunds goods, not credits — see
  /// [cancel], which returns those to the store.
  static int refundFor(TradeJob job) => job.direction == TradeDirection.buy
      ? job.unitsRemaining * job.unitPrice
      : 0;

  /// Releases a cancelled job's reservation back to its port: stock returns
  /// to the shelf and escrowed credits move back.
  ///
  /// Only the *unlanded* remainder is released — delivered runs already left
  /// the port for good. Restores the recorded `escrowed` amount exactly and
  /// unclamped: the clamp belongs to the reservation (a pool cannot pay what
  /// it does not hold), not to the release, where re-clamping mints or eats
  /// the difference whenever another reservation moved the pool meanwhile.
  /// A negative pool after a buy release means other reservations are holding
  /// its money, not that money vanished — the books balance across the port,
  /// and the next purchase refills it. No-op when the port is gone.
  ///
  /// Pre-accounting jobs carry no recorded escrow and fall back to the
  /// nominal remainder, which is the pre-fix behavior (and its mint risk,
  /// confined to jobs already in flight).
  static void releaseShare(List<Sector> universe, TradeJob job) {
    if (job.unitsRemaining <= 0) return;
    final outstanding = job.escrowOutstanding;
    releaseReservation(
      universe: universe,
      portSectorId: job.portSectorId,
      commodity: job.commodity,
      direction: job.direction,
      units: job.unitsRemaining,
      unitPrice: job.unitPrice,
      // **What is still owed, not what was taken.** A run that never arrived
      // has already handed a slice back (see [releaseRunSlice]), so refunding
      // `escrowed` in full on cancel returns more than was ever escrowed —
      // minting the port's credits, once per loss. `escrowOutstanding` is the
      // remainder, and it is also the pre-accounting fallback (0 on a buy,
      // where nothing was escrowed) that keeps this from re-introducing the
      // mint the recorded figure was added to fix.
      escrowed: outstanding,
    );
    // Recorded, so a *second* unwind on the same share cannot refund it again.
    // `releaseRunSlice` does this for a lost run; a cancel is the other way in,
    // and without it the job's own ledger still claimed the whole escrow was
    // outstanding after it had been handed back.
    job.escrowedReleased += outstanding;
  }

  /// Returns a raw reservation to its port without needing the job object.
  ///
  /// The primitive [releaseShare] and the order-creation fallback share, so
  /// there is exactly one place that knows how a reservation unwinds. A null
  /// `escrowed` is the legacy path: the nominal value, unclamped, as before.
  static void releaseReservation({
    required List<Sector> universe,
    required int portSectorId,
    required String commodity,
    required TradeDirection direction,
    required int units,
    required int unitPrice,
    int? escrowed,
  }) {
    Sector? sector;
    for (final s in universe) {
      if (s.id == portSectorId) {
        sector = s;
        break;
      }
    }
    final port = sector?.port;
    if (sector == null || port == null || port.isDestroyed) return;
    if (units <= 0) return;
    final giveBack = (escrowed ?? units * unitPrice).toDouble();
    if (direction == TradeDirection.buy) {
      sector.port = port.copyWith(
        supply: {...port.supply, commodity: port.getSupply(commodity) + units},
        portCredits: port.portCredits - giveBack,
      );
    } else {
      sector.port = port.copyWith(
        demand: {...port.demand, commodity: port.getDemand(commodity) + units},
        portCredits: port.portCredits + giveBack,
      );
    }
  }

  static void _applyLanding(Planet planet, TradeJob job, int units) {
    if (job.direction == TradeDirection.buy) {
      planet.deposit(job.commodity, units);
    } else {
      planet.accumulatedRevenue += units * job.unitPrice;
    }
  }

  /// Deducts sell goods from the store at order time. Unknown commodities
  /// (drones have no market row) cannot be sold.
  static bool _takesFromStore(Planet planet, String commodity, int units) {
    // takeStored clamps; an order must be fillable in full or not at all.
    if (planet.storedFor(commodity) < units) return false;
    return planet.takeStored(commodity, units) == units;
  }
}
