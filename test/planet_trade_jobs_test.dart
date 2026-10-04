import 'dart:io' as io;
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';

import 'support/storage_fakes.dart';

/// A generator whose `nextDouble` never drops below any failure chance, so
/// the existing landing-path tests keep reaching their completion branches.
/// The T-1..T-6 tests are about delivery, not risk; the risk branches have
/// their own forced generators below.
class _NeverFailRandom implements math.Random {
  @override
  double nextDouble() => 1.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => max - 1;
}

/// A generator that always drops below any failure chance (returns 0.0), so
/// every run that comes due fails. Reaches the loss branch on every cadence.
class _AlwaysFailRandom implements math.Random {
  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

final _rng = _NeverFailRandom();

Planet _world({String id = 'w1', String type = 'Terran'}) {
  return Planet(
    id: id,
    name: 'Xandor',
    planetType: type,
    owner: null,
  );
}

Sector _sectorWith(Planet planet) {
  return Sector(
    id: 1,
    name: 'Sol',
    x: 0,
    y: 0,
    warpRoutes: const [],
    planets: [planet],
  );
}

/// A generator that always fails the run *and* picks the **last positive-weight
/// cause** in enum order, by returning the top of the roll's range.
///
/// This is the lever that makes each outcome class reachable without a second
/// injected decision. `nextInt(max) => max - 1` lands in the final occupied
/// band of [PlanetTradeService.pickCause], so the *route* chooses the cause:
///
/// | route | last positive cause | outcome |
/// |---|---|---|
/// | free port, no anomaly | `rerouted` | delayed |
/// | federal port, no anomaly | `customsSeizure` | seized |
/// | free port, anomaly at destination | `anomalyStorm` | lost |
///
/// Hand-rolling a generator that returns a computed offset into a weight table
/// would have meant recomputing the table in the test — a second
/// implementation of the rule, which vouches only for itself. Deriving the
/// choice from the route instead means the test asserts the *rule* (a federal
/// port can seize, an anomaly can throw storms) rather than a transcription of
/// it.
class _LastCauseRandom implements math.Random {
  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => max - 1;
}

/// Every guard for the four outcome classes, run from [main].
///
/// A wrapper rather than more top-level [group] calls: the helpers this
/// group leans on already live at file scope, and the file's other groups
/// are declared inside `main`.
void _t8OutcomeClasses() {
  group('T8 outcome classes', () {
    /// A world [hops] from a port, with the destination's route context set.
    ///
    /// `anomaly` and `pirates` live on the **destination** sector because that is
    /// where the service reads them — see `_buildRoutesByJob`. Building the wrong
    /// sector's context is the fixture trap that makes a contextual rule look
    /// inert.
    (Planet, List<Sector>) route({
      int hops = 3,
      PortClass port = PortClass.free,
      bool anomaly = false,
      int pirates = 0,
      int stock = 0,
      int portSupply = 50000,
    }) {
      final planet = _world()..storedMinerals = stock;
      final universe = <Sector>[
        Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2, 9],
          planets: [planet],
        ),
      ];
      // A traversable chain. `warpRoutes` are **directed**, so a chain built as
      // `[prev]` dead-ends BFS and every run prices as same-sector — which reads
      // as "the risk rule is broken" rather than as a broken fixture.
      for (final id in [2, 3, 4, 5]) {
        universe.add(Sector(
          id: id,
          name: 'Hop$id',
          x: id.toDouble(),
          y: 0,
          warpRoutes: [id < 5 ? id + 1 : id - 1, id - 1],
          pirateCount: id == 1 + hops ? pirates : 0,
          anomaly: id == 1 + hops && anomaly ? 'rift' : null,
        ));
      }
      final dest = universe.firstWhere((s) => s.id == 1 + hops);
      dest.port = Port(
        name: 'Dest',
        portClass: port,
        buyPrices: const {'minerals': 50},
        sellPrices: const {'minerals': 50},
        supply: {'minerals': portSupply},
        demand: {'minerals': portSupply},
        maxSupply: {'minerals': portSupply},
        maxDemand: {'minerals': portSupply},
        portCredits: 1000000,
        desiredCredits: 1000000,
      );
      return (planet, universe);
    }

    /// Places one real order — through [PlanetTradeService.createOrder], so the
    /// reservation actually happens — and snapshots the port's books.
    ///
    /// The reservations matter rather than being incidental: several guards below
    /// are about who ends up holding the port's credits, and a helper built on
    /// `create()` alone leaves `escrowed` null, making every one of them pass
    /// without asserting anything.
    ({
      TradeJob job,
      String orderId,
      Planet planet,
      List<Sector> universe,
      Sector portSector,
      double creditsBefore,
      int demandBefore,
      int supplyBefore,
    }) place(
      (Planet, List<Sector>) r, {
      required TradeDirection direction,
      int units = 4000,
    }) {
      final (planet, universe) = r;
      final portSector = universe.lastWhere((s) => s.port != null);
      final creditsBefore = portSector.port!.portCredits;
      final demandBefore = portSector.port!.getDemand('minerals');
      final supplyBefore = portSector.port!.getSupply('minerals');
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: direction,
        volume: units,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(1),
          reason: 'the fixture must place exactly one share, or the accounting '
              'assertions below are about more than one');
      return (
        job: result.jobs.single,
        orderId: result.orderId,
        planet: planet,
        universe: universe,
        portSector: portSector,
        creditsBefore: creditsBefore,
        demandBefore: demandBefore,
        supplyBefore: supplyBefore,
      );
    }

    /// Advances until a run actually resolves, and returns its ledger entry.
    ///
    /// **The cadence is hops-derived** (`hops * ticksPerHop`), so a three-hop order
    /// needs six passes before its first run fires. A test that advances once and
    /// reads the result is testing the countdown, not the outcome — and it fails
    /// with `No element`, naming the fixture rather than the rule.
    ///
    /// Returns the **incident** rather than `advanceAll`'s record, so the guards
    /// read the fact the player reads. The return value is the same fact; the
    /// ledger is the durable one.
    TradeIncident resolve(Planet planet, List<Sector> universe, math.Random rng,
        {int maxPasses = 60}) {
      final before = planet.tradeIncidents.length;
      for (var i = 0; i < maxPasses; i++) {
        PlanetTradeService.advanceAll(universe, rng: rng);
        if (planet.tradeIncidents.length > before) {
          return planet.tradeIncidents.last;
        }
      }
      fail('no run resolved in $maxPasses passes');
    }

    /// Runs every order out, for the guards about what happens *after* the last
    /// run rather than on it.
    void settle(Planet planet, List<Sector> universe, math.Random rng) {
      for (var i = 0; i < 80 && planet.tradeJobs.isNotEmpty; i++) {
        PlanetTradeService.advanceAll(universe, rng: rng);
      }
    }

    /// A plan only — no reservation, no job. The premium guards are about
    /// arithmetic over a plan, and placing an order to get one would make the
    /// fixture depend on the reservation path too.
    TradePlan planFor(
        (Planet, List<Sector>) r, TradeDirection dir, int volume) {
      final (planet, universe) = r;
      return PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: dir,
        volume: volume,
      );
    }

    test('every cause declares a non-delivered outcome', () {
      // The rule lives on the enum so the weights and the consequence cannot
      // drift apart — a reroute that also destroyed the cargo would be a lie in
      // the report. This guards that placement: a cause claiming `delivered`
      // would make the service's `switch` consume its units *and* pay out.
      for (final cause in TradeFailureCause.values) {
        expect(cause.outcome, isNot(TradeRunOutcome.delivered),
            reason: '$cause cannot both disrupt and deliver');
      }
      // All three non-delivered classes are reachable from the enum, so the
      // four-way split is not three causes and one empty label.
      expect(
          TradeFailureCause.values.map((c) => c.outcome).toSet(),
          containsAll(<TradeRunOutcome>[
            TradeRunOutcome.lost,
            TradeRunOutcome.delayed,
            TradeRunOutcome.seized,
          ]));
      // And a diversion must cost time, or `delayed` is just `lost` with better
      // manners — a run that is "diverted" and arrives on time was not diverted.
      for (final cause in TradeFailureCause.values
          .where((c) => c.outcome == TradeRunOutcome.delayed)) {
        expect(cause.delayTicks, greaterThan(0),
            reason: '$cause costs no time');
      }
    });

    test('DELAYED: nothing is lost, nothing consumed, the run is just later',
        () {
      // A free port with no anomaly makes `rerouted` the last positive cause, so
      // the forced generator reaches the diversion deterministically.
      final r = place(route(stock: 4000), direction: TradeDirection.sell);
      expect(r.job.escrowed, greaterThan(0),
          reason: 'a sell escrows, or the assertions below are vacuous');

      final run = resolve(r.planet, r.universe, _LastCauseRandom());
      expect(run.outcome, TradeRunOutcome.delayed);
      expect(run.cause, TradeFailureCause.rerouted);

      // **The whole point of the class:** the units are still on the order.
      expect(r.job.unitsRemaining, 4000,
          reason: 'a diverted run consumed units');
      expect(r.job.unitsLost, 0);
      expect(r.job.unitsSeized, 0);
      // And the quoted arrival has actually moved.
      expect(r.job.ticksRemaining, greaterThan(r.job.ticksPerRun));
      expect(run.delayTicks, TradeFailureCause.rerouted.delayTicks);
      // The world's goods and the port's books are untouched: a diversion costs
      // time and nothing else, which is the entire difference from a loss.
      expect(r.planet.accumulatedRevenue, 0);
      // The reservation **stands**: the run is still owed, merely later. Asserting
      // the pre-order figure here would pass against a diversion that quietly
      // released the order, which is the opposite of what the class means.
      expect(r.portSector.port!.getDemand('minerals'), r.demandBefore - 4000);
    });

    test('DELAYED: the order still finishes rather than stalling forever', () {
      // A guard on "just later" rather than "later, forever". The units go back, so
      // the job must complete once the added ticks elapse — a diverted run that
      // was never re-attempted would leave the order open indefinitely, and
      // nothing else in the suite would notice.
      final r = place(route(hops: 1), direction: TradeDirection.buy);
      expect(resolve(r.planet, r.universe, _LastCauseRandom()).outcome,
          TradeRunOutcome.delayed);
      expect(r.planet.tradeJobs, hasLength(1), reason: 'the job must survive');

      settle(r.planet, r.universe, _rng);
      expect(r.planet.tradeJobs, isEmpty);
      expect(r.planet.storedMinerals, 4000);
    });

    test('SEIZED: most of the run arrives and the rest is impounded', () {
      // A federal port makes `customsSeizure` the last positive cause.
      final r = place(route(port: PortClass.federal, stock: 4000),
          direction: TradeDirection.sell);
      final run = resolve(r.planet, r.universe, _LastCauseRandom());
      expect(run.outcome, TradeRunOutcome.seized);
      expect(run.cause, TradeFailureCause.customsSeizure);

      // A **partial delivery**, not a total loss: the point is that most of the
      // run is sold.
      expect(run.deliveredUnits, 3000);
      expect(run.seizedUnits, 1000);
      expect(r.job.unitsSeized, 1000);
      expect(r.job.unitsLost, 0, reason: 'an impoundment is not a destruction');
      // Priced at what the plan reserved, not a typed rate: the planner quotes the
      // port's *effective* price, so a fixed figure would break on a retune rather
      // than report a real change.
      expect(r.planet.accumulatedRevenue, 3000 * r.job.unitPrice);
      expect(r.planet.storedMinerals, 0);
    });

    test('SEIZED on a BUY: the goods are delivered, the shortfall is recorded',
        () {
      final r =
          place(route(port: PortClass.federal), direction: TradeDirection.buy);
      resolve(r.planet, r.universe, _LastCauseRandom());
      // Three quarters of the run lands, and the world is told so.
      expect(r.planet.storedMinerals, 3000);
      expect(r.job.unitsSeized, 1000);
      expect(r.job.unitsDelivered, 3000);
      // The four figures partition the order exactly.
      expect(
          r.job.unitsDelivered +
              r.job.unitsLost +
              r.job.unitsSeized +
              r.job.unitsRemaining,
          r.job.unitsTotal);
    });

    test('the seizure share is readable and never a whole multi-unit run', () {
      // "Customs takes about a quarter" is the player-facing contract, so the
      // fraction is a **rule**, not an implementation detail: it is what makes a
      // repeated seizure actionable rather than mysterious.
      final r =
          place(route(port: PortClass.federal), direction: TradeDirection.buy);
      final run = resolve(r.planet, r.universe, _LastCauseRandom());
      expect(run.seizedUnits,
          (run.units * PlanetTradeService.seizureFraction).round());
      // Something is always delivered on a multi-unit seizure, or "partly seized"
      // is a total loss wearing a kinder hat.
      expect(run.deliveredUnits, greaterThan(0));

      // A one-unit run cannot be *partly* delivered at all.
      final tiny = place(route(port: PortClass.federal, hops: 1),
          direction: TradeDirection.buy, units: 1);
      final tinyRun = resolve(tiny.planet, tiny.universe, _LastCauseRandom());
      expect(tinyRun.deliveredUnits, 0);
      expect(tiny.planet.storedMinerals, 0);
    });

    group('reservation accounting on a failed SELL', () {
      // This is the leak the review found and the original code documented as
      // "bounded, therefore accepted". It was four-way: the world lost the goods,
      // the port lost the demand slot *and* the escrow, and nobody received
      // anything. Bounded is an argument about magnitude, not correctness.
      test('a lost sell hands the port back the demand and the escrow', () {
        // An anomaly at the destination makes `anomalyStorm` the last positive
        // cause, so the run is destroyed rather than diverted.
        final r = place(route(anomaly: true, stock: 4000),
            direction: TradeDirection.sell);
        expect(r.job.escrowed, greaterThan(0));
        expect(
            r.portSector.port!.getDemand('minerals'), lessThan(r.demandBefore),
            reason: 'the reservation must have taken demand off the book');

        resolve(r.planet, r.universe, _LastCauseRandom());
        expect(r.job.unitsLost, 4000);
        expect(r.planet.accumulatedRevenue, 0);

        // Both halves of the port's side restored, as **equalities with the
        // pre-order figures**. A magnitude check would pass a release that
        // returned the demand but not the credits — which is half the leak.
        expect(r.portSector.port!.getDemand('minerals'), r.demandBefore);
        expect(r.portSector.port!.portCredits, r.creditsBefore);
        expect(r.job.escrowOutstanding, 0);
      });

      test('a lost sell releases a proportional slice, not the whole escrow',
          () {
        // Two runs, one lost. Releasing the whole escrow on each loss would
        // refund twice over — minting the port's credits — and leave the final run
        // with nothing to unwind. `place` uses the real freighter hold, so an
        // 8,000-unit sell is two 4,000-unit runs.
        final r = place(route(anomaly: true, stock: 10000),
            direction: TradeDirection.sell, units: 10000);
        final job = r.job;
        final escrowed = job.escrowed!;
        final creditsAfterOrder = r.portSector.port!.portCredits;
        expect(job.runsTotal, 2, reason: 'the fixture must be two runs');

        resolve(r.planet, r.universe, _LastCauseRandom());
        expect(job.unitsLost, PlanetTradeService.freighterHold);
        expect(job.unitsRemaining, PlanetTradeService.freighterHold,
            reason: 'the second run is still owed');
        // Part of the escrow, and definitely not all of it.
        expect(job.escrowedReleased, greaterThan(0));
        expect(job.escrowedReleased, lessThan(escrowed));
        expect(job.escrowOutstanding, escrowed - job.escrowedReleased);
        // Measured from **after** the reservation, which had already debited the
        // port: comparing against the pre-order figure reads as a whole-escrow
        // hole when it is the slice correctly going back.
        expect(r.portSector.port!.portCredits,
            closeTo(creditsAfterOrder + job.escrowedReleased, 0.001));
      });

      test('loss then cancel refunds the escrow exactly once', () {
        // The failure mode the slice release exists to prevent: releasing the
        // full `escrowed` on cancel hands back more than was ever taken once a
        // loss has already returned a slice. This is the conservation check —
        // after a loss *and* a cancel the port's credits must equal its credits
        // before the order, to the credit.
        final r = place(route(anomaly: true, stock: 10000),
            direction: TradeDirection.sell, units: 10000);
        final job = r.job;
        final creditsAfterOrder = r.portSector.port!.portCredits;

        resolve(r.planet, r.universe, _LastCauseRandom());
        expect(job.unitsLost, PlanetTradeService.freighterHold);
        expect(job.escrowedReleased, greaterThan(0));

        PlanetTradeService.cancelOrder(r.planet, r.universe, r.orderId);

        // Exact in both directions. A double refund shows as credits *above* the
        // starting figure, which is why this is an equality and not a bound.
        expect(r.portSector.port!.portCredits, r.creditsBefore);
        expect(job.escrowedReleased, job.escrowed);
        expect(job.escrowOutstanding, 0);
        // Sanity on the fixture: the order really did move money, so the equality
        // above is not passing because nothing happened.
        expect(creditsAfterOrder, lessThan(r.creditsBefore));
      });

      test('a lost BUY keeps the reservation — the asymmetry is deliberate',
          () {
        // In a buy the port had already taken the credits and the goods had left
        // its shelf, so its side of the deal completed before the freight existed.
        // Releasing here would hand back both stock and payment for goods that no
        // longer exist, and make failure free.
        final r = place(route(anomaly: true), direction: TradeDirection.buy);
        resolve(r.planet, r.universe, _LastCauseRandom());
        expect(r.job.unitsLost, 4000);
        expect(r.planet.storedMinerals, 0);
        expect(r.portSector.port!.getSupply('minerals'), r.supplyBefore - 4000);
        // Stock stays down and the payment stays made: the port sold, and its side
        // of the deal completed before the freight existed.
        expect(r.portSector.port!.portCredits,
            closeTo(r.creditsBefore + 4000 * r.job.unitPrice, 0.001));
      });
    });

    test('an order closes once, with totals that survive its jobs', () {
      final r = place(route(hops: 1, anomaly: true),
          direction: TradeDirection.buy, units: 10000);
      expect(r.job.runsTotal, 2, reason: 'the fixture must be two runs');
      // Run 1 lost, run 2 clean.
      resolve(r.planet, r.universe, _LastCauseRandom());
      settle(r.planet, r.universe, _rng);

      // The order has left the in-flight list...
      expect(r.planet.tradeJobs, isEmpty);
      // ...and is in the history, with the loss counted rather than smoothed away.
      expect(r.planet.tradeOrders, hasLength(1));
      final rec = r.planet.tradeOrders.single;
      expect(rec.orderId, r.orderId);
      expect(rec.unitsTotal, 10000);
      expect(rec.unitsLost, PlanetTradeService.freighterHold);
      expect(rec.unitsDelivered, PlanetTradeService.freighterHold);
      expect(rec.runs, 2);
      expect(rec.status, 'PARTIALLY LOST');
      expect(rec.ports, [r.portSector.id]);
    });

    test('a split order closes as ONE order, not one per port', () {
      // The whole reason `orderId` is stamped on every incident: an order split
      // across ports is one request, and recording four 20,000-unit orders would
      // make the history disagree with the row the player was watching.
      final (planet, universe) = route(hops: 1);
      // A second port, deliberately **short of stock**. A second port with a full
      // shelf would never be reached — the planner fills nearest-first — so the
      // order would not split and "one order, not two" would be trivially true.
      final nearSector = universe.lastWhere((s) => s.port != null);
      // Both ports are **short of the order**. A second port with a full shelf is
      // never reached — the planner fills nearest-first — so the order would not
      // split and "one order, not two" would be trivially true.
      const shelf = 4000;
      // `Sector` has no `copyWith`, so the near port is mutated through its own
      // `copyWith` and reassigned on the sector — which is how the rest of the
      // codebase replaces it.
      nearSector.port = nearSector.port!.copyWith(
        supply: const {'minerals': shelf},
        maxSupply: const {'minerals': shelf},
      );
      universe.add(Sector(
        id: 9,
        name: 'Other',
        x: 9,
        y: 9,
        warpRoutes: const [1],
        pirateCount: 0,
        port: nearSector.port!.copyWith(
          name: 'Second',
          supply: const {'minerals': shelf},
          maxSupply: const {'minerals': shelf},
        ),
      ));
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 6000,
        actorFaction: 'trader',
      );
      expect(result.jobs.length, greaterThan(1),
          reason: 'the fixture must actually split');
      expect(planet.tradeJobs.length, greaterThan(1));

      settle(planet, universe, _rng);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.tradeOrders, hasLength(1),
          reason: 'a split order is one order');
      final rec = planet.tradeOrders.single;
      expect(rec.ports.length, greaterThan(1),
          reason: 'and it names every port it touched');
      expect(rec.unitsTotal, 6000);
      expect(rec.unitsDelivered, 6000);
    });

    test('the order history is bounded and JSON round-trips', () {
      // A deep enough shelf for 14 orders. A port that runs dry partway through
      // places no job, so the ledger would hold fewer orders than the test placed
      // and the trim assertion would pass for the wrong reason.
      final (planet, universe) = route(hops: 1, portSupply: 1000000);
      final ids = <String>[];
      for (var n = 0; n < 14; n++) {
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 4000,
          actorFaction: 'trader',
        );
        expect(placed.jobs, hasLength(1), reason: 'every order must place');
        ids.add(placed.orderId);
        settle(planet, universe, _rng);
      }
      expect(planet.tradeOrders.length, Planet.tradeOrderHistory);
      expect(planet.tradeOrders.last.orderId, ids.last,
          reason: 'the newest must survive the trim');

      final revived = Planet.fromJson(planet.toJson());
      expect(revived.tradeOrders.length, Planet.tradeOrderHistory);
      expect(revived.tradeOrders.last.unitsDelivered, 4000);
      expect(revived.tradeOrders.last.status, 'COMPLETE');

      // A destroyed world takes its commerce with it, like every other ghost entry.
      revived.destroy();
      expect(revived.tradeOrders, isEmpty);
    });

    test('a legacy incident with only `delivered: false` reads as a loss', () {
      // Read forward, not optimistically. A save written before the four classes
      // has the boolean only; dropping it would silently improve the player's
      // history, and defaulting an *unknown* outcome name to `delivered` is the
      // same failure in a new place.
      final legacy = TradeIncident.fromJson({
        'id': 'x',
        'tick': 5,
        'commodity': 'minerals',
        'direction': 'buy',
        'units': 500,
        'portSectorId': 3,
        'delivered': false,
        'cause': 'piratesDestroyed',
      });
      expect(legacy.outcome, TradeRunOutcome.lost);
      expect(legacy.lostUnits, 500);
      expect(legacy.deliveredUnits, 0);

      expect(
          TradeIncident.fromJson({
            'outcome': 'somethingNew',
            'units': 10,
          }).outcome,
          TradeRunOutcome.lost);

      // A seizure cannot claim a negative delivery from a corrupt save.
      expect(
          TradeIncident.fromJson({
            'outcome': 'seized',
            'units': 10,
            'seizedUnits': 999,
          }).deliveredUnits,
          0);
    });

    group('T10 freight cover', () {
      test('the premium is derived from the order\'s own risk', () {
        // Same coverage, two routes: a near port and a far one. If cover were a
        // flat rate these would be equal, and the player would have no reason to
        // read the distance as the thing worth paying for.
        final near = planFor(route(hops: 1), TradeDirection.buy, 4000);
        final far = planFor(route(hops: 4), TradeDirection.buy, 4000);
        expect(PlanetTradeService.orderRiskFraction(near),
            lessThan(PlanetTradeService.orderRiskFraction(far)));
        expect(PlanetTradeService.premiumFor(near, TradeInsurance.full),
            lessThan(PlanetTradeService.premiumFor(far, TradeInsurance.full)));
        // No cover, no premium — and no risk, no cost. A same-sector run cannot be
        // lost, so insuring it must be free or the premium is lying about the risk.
        final sameSector = planFor(
            route(hops: 0, port: PortClass.free), TradeDirection.buy, 4000);
        expect(PlanetTradeService.orderRiskFraction(sameSector), 0.0);
        expect(
            PlanetTradeService.premiumFor(sameSector, TradeInsurance.full), 0);
      });

      test(
          'the premium covers more than the expected loss, or it is not a policy',
          () {
        // At exactly the expected loss a policy is a fair bet with no edge and no
        // reason to exist. This pins the *relationship* rather than the number, so
        // a retune of the margin does not break it and a margin of 0 does.
        final plan = planFor(route(hops: 4), TradeDirection.buy, 10000);
        var value = 0;
        for (final a in plan.allocations) {
          value += a.units * a.unitPrice;
        }
        final risk = PlanetTradeService.orderRiskFraction(plan);
        expect(risk, greaterThan(0.0));
        final premium =
            PlanetTradeService.premiumFor(plan, TradeInsurance.full);
        expect(premium, greaterThan((value * risk).round()));
        // And coverage scales the premium monotonically, so Half is never dearer
        // than Full — the obvious relation, and one a bad table could invert.
        final none = PlanetTradeService.premiumFor(plan, TradeInsurance.none);
        final half = PlanetTradeService.premiumFor(plan, TradeInsurance.half);
        expect(none, 0);
        expect(half, lessThan(premium));
        expect(half, greaterThan(0));
      });

      test('cover pays out on a destroyed run, in the right currency', () {
        // A **buy** is indemnified in credits: the pilot prepaid for goods that no
        // longer exist.
        // **Not** `place()`: that helper already places an order, and the second
        // one below would then resolve *after* it — or, on a sell, never be created
        // at all because the store was already drained. Either way the guard would
        // read the uninsured job's incident and pass on `insuredUnits == 0`. That is
        // exactly what happened: fault injection passed against this test with the
        // payout deleted.
        final (planet, universe) = route(anomaly: true);
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 4000,
          actorFaction: 'trader',
          insurance: TradeInsurance.full,
        );
        final job = placed.jobs.single;
        expect(job.insurance, TradeInsurance.full);
        expect(job.premiumPaid, greaterThan(0));

        final before = PlanetTradeService.indemnityOwed['p1'] ?? 0;
        final run = resolve(planet, universe, _LastCauseRandom());
        expect(run.outcome, TradeRunOutcome.lost);
        expect(run.insuredUnits, run.units,
            reason: 'full cover returns the whole destroyed run');
        // **The tally is owed, not paid**: the tick resolves runs and must never
        // write a player, so the credit is queued for the shell to drain.
        expect(PlanetTradeService.takeIndemnityFor('p1') - before,
            run.units * job.unitPrice);
        expect(planet.storedMinerals, 0);
        // Nothing was deposited: a buy's indemnity is credits, not goods, and
        // putting them in the store would double-count the loss as a delivery.
        expect(planet.storedMinerals, 0);
      });

      test('a sell is indemnified in GOODS, not revenue', () {
        // The price was never the world's to collect. Paying out the sale value
        // would be paying for a sale that did not happen, and it would make a sell
        // strictly better than a buy.
        final (sell, universe) = route(anomaly: true, stock: 4000);
        final placed = PlanetTradeService.createOrder(
          planet: sell,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.sell,
          volume: 4000,
          actorFaction: 'trader',
          insurance: TradeInsurance.full,
        );
        // The fixture has to actually place, or the payout branch is never reached
        // and every assertion below reads zero against zero.
        expect(placed.jobs, hasLength(1));
        expect(placed.jobs.single.isInsured, isTrue);
        final run = resolve(sell, universe, _LastCauseRandom());
        expect(run.outcome, TradeRunOutcome.lost);
        // The goods come back to the store...
        expect(sell.storedMinerals, run.insuredUnits);
        // ...and no credits are owed, because nothing was ever sold.
        expect(PlanetTradeService.takeIndemnityFor('p1'), 0);
        expect(sell.accumulatedRevenue, 0);
      });

      test('cover does NOT pay on a seizure', () {
        // The one exclusion that gives the policy a decision in it. Customs is a
        // legal consequence of the route; a policy that covered it would be a flat
        // refund with a premium attached.
        final (r, universe) = route(port: PortClass.federal);
        PlanetTradeService.createOrder(
          planet: r,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 4000,
          actorFaction: 'trader',
          insurance: TradeInsurance.full,
        );
        final run = resolve(r, universe, _LastCauseRandom());
        expect(run.outcome, TradeRunOutcome.seized);
        expect(run.insuredUnits, 0);
        expect(PlanetTradeService.takeIndemnityFor('p1'), 0);
      });

      test('an uncovered order behaves exactly as before', () {
        // The default has to be a genuine no-op, or every existing order silently
        // gains a benefit. `none` means coverage 0, so the payout branch is dead.
        final r = place(route(anomaly: true), direction: TradeDirection.buy);
        final placed = PlanetTradeService.createOrder(
          planet: r.planet,
          universe: r.universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 4000,
          actorFaction: 'trader',
        );
        expect(placed.premium, 0);
        expect(placed.jobs.single.premiumPaid, 0);
        expect(placed.jobs.single.isInsured, isFalse);
        final run = resolve(r.planet, r.universe, _LastCauseRandom());
        expect(run.outcome, TradeRunOutcome.lost);
        expect(run.insuredUnits, 0);
        expect(PlanetTradeService.takeIndemnityFor('p1'), 0);
      });

      test('a split order pays one premium, split exactly across its shares',
          () {
        // Per-share pricing would make the cost depend on how the planner happened
        // to split the order, so two identical orders could cost different amounts
        // for the same cover. The parts must sum to the whole, including rounding.
        final (planet, universe) = route(hops: 1);
        final near = universe.lastWhere((s) => s.port != null);
        const shelf = 4000;
        near.port = near.port!.copyWith(
          supply: const {'minerals': shelf},
          maxSupply: const {'minerals': shelf},
        );
        universe.add(Sector(
          id: 9,
          name: 'Other',
          x: 9,
          y: 9,
          warpRoutes: const [1],
          pirateCount: 0,
          port: near.port!.copyWith(
            name: 'Second',
            supply: const {'minerals': shelf},
            maxSupply: const {'minerals': shelf},
          ),
        ));
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 6000,
          actorFaction: 'trader',
          insurance: TradeInsurance.full,
        );
        expect(placed.jobs.length, greaterThan(1));
        expect(placed.premium, greaterThan(0));
        // The invariant: the shares' premiums sum to the order's, to the credit.
        expect(placed.jobs.fold<int>(0, (a, j) => a + j.premiumPaid),
            placed.premium);
        expect(placed.jobs.every((j) => j.insurance == TradeInsurance.full),
            isTrue);
      });

      test('the indemnity tally drains, and only for its own pilot', () {
        // Two facts in one: draining is destructive (a second read is zero), and
        // the pot is keyed by player. A shared pot would credit whichever pilot
        // happened to render next.
        PlanetTradeService.indemnityOwed['a'] = 500;
        PlanetTradeService.indemnityOwed['b'] = 700;
        expect(PlanetTradeService.takeIndemnityFor('a'), 500);
        expect(PlanetTradeService.takeIndemnityFor('a'), 0,
            reason:
                'a read that does not drain pays the same refund every poll');
        expect(PlanetTradeService.takeIndemnityFor('b'), 700);
        expect(PlanetTradeService.indemnityOwed, isEmpty);
        expect(PlanetTradeService.takeIndemnityFor('nobody'), 0);
      });

      test('cover survives a reload', () {
        final (planet, universe) = route(hops: 2);
        PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 4000,
          actorFaction: 'trader',
          insurance: TradeInsurance.half,
        );
        final back = Planet.fromJson(planet.toJson()).tradeJobs.single;
        expect(back.insurance, TradeInsurance.half);
        expect(back.isInsured, isTrue);
        expect(back.premiumPaid, greaterThan(0));
        // A pre-cover save reads as uncovered, which is the honest reading: the
        // order was placed when cover did not exist.
        final legacy = TradeJob.fromJson(const {
          'playerId': 'p1',
          'planetId': 'w1',
          'portSectorId': 2,
          'unitsTotal': 100,
        });
        expect(legacy.insurance, TradeInsurance.none);
        expect(legacy.premiumPaid, 0);
      });

      test('an order record remembers its policy and what the cover cost', () {
        // Two facts the player cannot recover from anywhere else. The row shows
        // the policy while the order is open; the moment it closes, the only
        // thing that still exists is the record — and before this, a premium
        // appeared once in a quote and then nowhere at all, which reads as having
        // been free.
        final (planet, universe) = route(hops: 2);
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 20000,
          actorFaction: 'trader',
          insurance: TradeInsurance.half,
        );
        expect(placed.premium, greaterThan(0));
        settle(planet, universe, _rng);

        expect(planet.tradeOrders, hasLength(1));
        final rec = planet.tradeOrders.single;
        expect(rec.insurance, TradeInsurance.half);
        expect(rec.premium, placed.premium,
            reason: 'the record must carry exactly what was charged');
      });

      test('a split order does not charge the cover once per run', () {
        // **The trap this guards.** `premiumPaid` is a per-*share* figure stamped
        // on every *run* of that share, so the record has to de-duplicate by job
        // id. A plain sum multiplies the premium by the run count — an order that
        // paid 10,000 would report 40,000, and the Report would show the player
        // paying four times the price they were quoted.
        final (planet, universe) = route(hops: 2);
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 20000,
          actorFaction: 'trader',
          insurance: TradeInsurance.full,
        );
        // More than one run, or the multiplier cannot show up at all.
        expect(placed.jobs.single.runsTotal, greaterThan(1),
            reason: 'the fixture must have several runs');
        final runs = placed.jobs.single.runsTotal;
        settle(planet, universe, _rng);

        final rec = planet.tradeOrders.single;
        expect(rec.runs, runs, reason: 'every run should be in the ledger');
        expect(rec.premium, placed.premium);
        // And the naive sum really would have been wrong — so the guard is not
        // passing because both numbers happen to be small.
        final naive =
            planet.tradeIncidents.fold<int>(0, (a, i) => a + i.premiumPaid);
        expect(naive, greaterThan(placed.premium));
      });

      test('the split-order premium is counted once per share, not per order',
          () {
        // The same de-duplication across a **split** order, where two shares each
        // carry their own slice of the premium.
        final (planet, universe) = route(hops: 1);
        final near = universe.lastWhere((s) => s.port != null);
        const shelf = 4000;
        near.port = near.port!.copyWith(
          supply: const {'minerals': shelf},
          maxSupply: const {'minerals': shelf},
        );
        universe.add(Sector(
          id: 9,
          name: 'Other',
          x: 9,
          y: 9,
          warpRoutes: const [1],
          pirateCount: 0,
          port: near.port!.copyWith(
            name: 'Second',
            supply: const {'minerals': shelf},
            maxSupply: const {'minerals': shelf},
          ),
        ));
        final placed = PlanetTradeService.createOrder(
          planet: planet,
          universe: universe,
          playerId: 'p1',
          commodity: 'minerals',
          direction: TradeDirection.buy,
          volume: 6000,
          actorFaction: 'trader',
          insurance: TradeInsurance.half,
        );
        expect(placed.jobs.length, greaterThan(1));
        settle(planet, universe, _rng);

        final rec = planet.tradeOrders.single;
        expect(rec.premium, placed.premium);
        expect(rec.insurance, TradeInsurance.half);
      });

      test('the shell drains the indemnity every tick', () async {
        // A source scan, which is normally the wrong tool — and the right one here,
        // for a structural fact: that the credit is settled somewhere at all. No
        // behaviour test can see the *absence* of a call, and a refund that is
        // counted and never paid is exactly that: correct arithmetic that silently
        // vanishes, with no error anywhere.
        //
        // Driving `GameShell` would be the alternative, and it is a large fixture
        // for a one-line question. Same shape and same precedent as
        // `gravity_wiring_test.dart`.
        final file = await _File('lib/screens/game_shell.dart').readAsString();
        expect(file, contains('takeIndemnityFor'),
            reason:
                'nothing credits the pilot, so a refund is computed and lost');
        // **Called, not merely declared.** The first version asserted
        // `contains('_applyFreightIndemnity()')`, which the *definition* satisfies
        // on its own — so commenting out the call site left it green. Fault
        // injection is the only reason that is known. Counting occurrences is the
        // cheapest way to say "a declaration and a call", and the count is
        // asserted rather than the string so a rename cannot quietly satisfy it.
        expect('_applyFreightIndemnity()'.allMatches(file).length,
            greaterThanOrEqualTo(2),
            reason: 'the drain must be declared *and* called from the tick');
        // And the shell must not touch the tally directly — one place owns it.
        expect(file, isNot(contains('indemnityOwed')));
      });
    });
  });
}

void main() {
  _t8OutcomeClasses();
  group('T1 model + service', () {
    test('buy advances one run per interval and lands cargo exactly once', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 6,
        ticksPerRun: 2,
      )!;
      expect(planet.tradeJobs, contains(job));

      final universe = [_sectorWith(planet)];

      // Tick 1: countdown, nothing lands.
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      expect(planet.tradeJobs, contains(job));

      // Tick 2: first run lands 2 of 6; job stays (multi-run, not complete).
      final first = PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(first[job.id]!.units, 2);
      expect(planet.tradeJobs, contains(job));
      expect(planet.storedMinerals, 2);

      // Ticks 3-4: second run; ticks 5-6: final run completes and removes.
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(planet.tradeJobs, contains(job));
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      final last = PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(last[job.id]!.units, 2);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 6);
    });

    test('sell deducts at order and earns revenue on landing', () {
      final planet = _world()..storedMinerals = 100;
      expect(
        PlanetTradeService.create(
          planet: planet,
          playerId: 'p1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.sell,
          units: 10,
          ticksPerRun: 10,
          unitPrice: 5,
        ),
        isNotNull,
      );
      // Goods leave at order time (reservation).
      expect(planet.storedMinerals, 90);

      for (var i = 0; i < 9; i++) {
        expect(PlanetTradeService.advanceAll([_sectorWith(planet)], rng: _rng),
            isEmpty);
      }
      final landed =
          PlanetTradeService.advanceAll([_sectorWith(planet)], rng: _rng);
      expect(landed.values.single.units, 10);
      expect(planet.accumulatedRevenue, 50);
      expect(planet.tradeJobs, isEmpty);
    });

    test('sell refuses when the store cannot fill the order', () {
      final planet = _world()..storedMinerals = 5;
      expect(
        PlanetTradeService.create(
          planet: planet,
          playerId: 'p1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.sell,
          units: 10,
          ticksPerRun: 2,
        ),
        isNull,
      );
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 5);
    });

    test('cancel removes and returns unsold goods to the store', () {
      final planet = _world()..storedMinerals = 100;
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        units: 10,
        ticksPerRun: 10,
      )!;
      expect(planet.storedMinerals, 90);
      expect(PlanetTradeService.cancel(planet, job.id), isTrue);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 100);
      expect(PlanetTradeService.cancel(planet, job.id), isFalse);
    });

    test('hold-size runs: distance sets cadence, not shipment size', () {
      // The playtest order: 3,700 units against a 3-hop port (6 ticks/run).
      // Coupled pacing delivered 6/run over 617 runs and 31 hours; hold
      // pacing delivers one 3,700-unit run in 6 ticks.
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 3700,
        ticksPerRun: 6,
        unitsPerRun: PlanetTradeService.freighterHold,
      )!;
      expect(job.runsTotal, 1);
      final universe = [_sectorWith(planet)];
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      final landed = PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(landed[job.id]!.units, 3700);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 3700);
    });

    test('a share larger than the hold takes several full runs', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 12000,
        ticksPerRun: 8,
        unitsPerRun: PlanetTradeService.freighterHold,
      )!;
      expect(job.runsTotal, 3);
      final universe = [_sectorWith(planet)];
      var landedTotal = 0;
      for (var i = 0; i < 8; i++) {
        final landed = PlanetTradeService.advanceAll(universe, rng: _rng);
        for (final e in landed.values) {
          landedTotal += e.units;
        }
      }
      expect(landedTotal, 5000);
      expect(planet.tradeJobs, contains(job));
    });
  });

  group('T7 failure rolls', () {
    /// A world four hops from its port, so runs carry the distance premium.
    ///
    /// A chain 1→2→3→4→5. `warpRoutes` are **directed** (BFS walks them
    /// one-way), so a correct chain has each sector listing the next: the
    /// first version built `warpRoutes: [prev]` and so dead-ended at sector 2,
    /// which priced every run as same-sector and the failure guard could not
    /// reach its own subject. A fixture that cannot produce the condition is
    /// the trap this comment exists to prevent.
    (Planet, List<Sector>) distantWorld() {
      final planet = _world();
      final universe = <Sector>[
        Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2],
          planets: [planet],
        ),
      ];
      for (final id in [2, 3, 4, 5]) {
        universe.add(Sector(
          id: id,
          name: 'Hop$id',
          x: id.toDouble(),
          y: 0,
          // Forward, and back to the previous so the chain is traversable
          // from either end.
          warpRoutes: id < 5 ? [id + 1, id - 1] : [id - 1],
        ));
      }
      return (planet, universe);
    }

    test('risk is distance-driven and deterministic given hops', () {
      expect(PlanetTradeService.failureChanceForHops(0), 0.0,
          reason: 'a same-sector run cannot be intercepted');
      expect(PlanetTradeService.failureChanceForHops(-3), 0.0);
      // Climb with distance, never above certainty.
      expect(PlanetTradeService.failureChanceForHops(4),
          greaterThan(PlanetTradeService.failureChanceForHops(1)));
      expect(PlanetTradeService.failureChanceForHops(4), lessThan(1.0));
      // Same input, same number: the risk is knowable on the quote.
      expect(PlanetTradeService.failureChanceForHops(4),
          PlanetTradeService.failureChanceForHops(4));
    });

    test('a failed run consumes its units and lands nothing', () {
      final (planet, universe) = distantWorld();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 100,
        ticksPerRun: 4,
        unitsPerRun: 50,
      )!;
      expect(PlanetTradeService.failureChanceForHops(4), greaterThan(0));

      // Four ticks, then the run comes due and the forced roll loses it.
      for (var i = 0; i < 3; i++) {
        expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      }
      final lost =
          PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      final entry = lost[job.id]!;
      expect(entry.outcome, TradeRunOutcome.lost);
      expect(entry.units, 50);
      // Nothing landed, and the job carries on with the remainder.
      expect(planet.storedMinerals, 0);
      expect(job.unitsRemaining, 50);
      expect(planet.tradeJobs, contains(job));
      expect(job.lastRunFailed, isTrue);
    });

    test('the remainder of a failed order still delivers', () {
      final (planet, universe) = distantWorld();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 100,
        ticksPerRun: 4,
        unitsPerRun: 50,
      )!;

      // First run lost...
      for (var i = 0; i < 3; i++) {
        PlanetTradeService.advanceAll(universe, rng: _rng);
      }
      PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      expect(planet.storedMinerals, 0);

      // ...second run survives and the order completes.
      for (var i = 0; i < 3; i++) {
        PlanetTradeService.advanceAll(universe, rng: _rng);
      }
      final ok = PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(ok[job.id]!.outcome, TradeRunOutcome.delivered);
      expect(planet.storedMinerals, 50);
      expect(planet.tradeJobs, isEmpty);
      expect(job.lastRunFailed, isFalse);
    });

    test('a same-sector run is never lost, whatever the generator says', () {
      final planet = _world();
      // One run of ten: the hold carries the whole order so the run is the
      // order, and a lost run would be the whole 10. (Defaulting
      // unitsPerRun to ticksPerRun would make it two runs of two.)
      // A 1:1 fixture: world and port share sector 1.
      final universe = [
        Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [planet],
          hasPort: true,
          port: Port(
            name: 'Local',
            portClass: PortClass.free,
            buyPrices: const {},
            sellPrices: const {'minerals': 50},
            supply: const {'minerals': 5000},
            demand: const {},
            maxSupply: const {'minerals': 5000},
            maxDemand: const {},
          ),
        ),
      ];
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 1,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 10,
        ticksPerRun: 2,
        unitsPerRun: 10,
      );
      // Cadence is 2, so the first advance only counts down; the second is
      // the run, and it is the one given to the always-fail generator.
      expect(PlanetTradeService.advanceAll(universe, rng: _rng), isEmpty);
      final landed =
          PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      // A generator that always "loses" still cannot beat a zero chance.
      expect(landed.values.single.outcome, TradeRunOutcome.delivered);
      expect(planet.storedMinerals, 10);
    });

    test('a failed sell run earns nothing and the remainder still pays', () {
      final (planet, universe) = distantWorld();
      // Put the buying port on the far end of the existing chain.
      universe.firstWhere((s) => s.id == 5).port = Port(
        name: 'Buyer',
        portClass: PortClass.free,
        buyPrices: const {'minerals': 50},
        sellPrices: const {},
        supply: const {},
        demand: const {'minerals': 5000},
        maxSupply: const {},
        maxDemand: const {'minerals': 5000},
        portCredits: 100000,
        desiredCredits: 100000,
      );
      // A sell commits goods at order time, so the world must hold them
      // first — `create` returns null otherwise (the store cannot promise
      // what it has not made).
      planet.storedMinerals = 100;
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        units: 100,
        ticksPerRun: 4,
        unitsPerRun: 50,
        unitPrice: 50,
      )!;

      // Cadence 4: three counts down, the fourth is the run.
      for (var i = 0; i < 3; i++) {
        PlanetTradeService.advanceAll(universe, rng: _rng);
      }
      final lost =
          PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      expect(lost[job.id]!.outcome, TradeRunOutcome.lost);
      // The lost run earns nothing.
      expect(planet.accumulatedRevenue, 0);
      expect(job.unitsRemaining, 50);

      for (var i = 0; i < 3; i++) {
        PlanetTradeService.advanceAll(universe, rng: _rng);
      }
      PlanetTradeService.advanceAll(universe, rng: _rng);
      // The surviving remainder paid in full.
      expect(planet.accumulatedRevenue, 2500);
      expect(planet.tradeJobs, isEmpty);
    });
  });

  group('T7b loss accounting and the freight report', () {
    /// A world [hops] from a port at the far end of a chain. `stock` preloads
    /// the store, which only a *sell* needs (a sell commits goods at order
    /// time); a buy starts empty, so "nothing arrived" is a plain zero rather
    /// than a delta against a fixture.
    (Planet, List<Sector>) routed(
        {int hops = 4, int stock = 0, PortClass port = PortClass.free}) {
      final planet = _world()..storedMinerals = stock;
      final universe = <Sector>[
        Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2],
          planets: [planet],
        ),
      ];
      for (final id in [2, 3, 4, 5]) {
        universe.add(Sector(
          id: id,
          name: 'Hop$id',
          x: id.toDouble(),
          y: 0,
          warpRoutes: [id < 5 ? id + 1 : id - 1, id - 1],
        ));
      }
      universe.firstWhere((s) => s.id == 1 + hops).port = Port(
        name: 'Dest',
        portClass: port,
        buyPrices: const {},
        sellPrices: const {'minerals': 50},
        supply: const {'minerals': 50000},
        demand: const {},
        maxSupply: const {'minerals': 50000},
        maxDemand: const {},
        portCredits: 100000,
        desiredCredits: 100000,
      );
      return (planet, universe);
    }

    test('a lost run does not count toward delivered', () {
      final (planet, universe) = routed();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 100,
        ticksPerRun: 1,
        unitsPerRun: 50,
      )!;

      // First run lost, second delivered.
      PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      expect(job.unitsRemaining, 50);
      expect(job.unitsLost, 50);
      // **The bug this fixes:** `unitsTotal - unitsRemaining` reads 50 here,
      // claiming half the order arrived when the store gained nothing.
      expect(job.unitsTotal - job.unitsRemaining, 50);
      expect(job.unitsDelivered, 0);
      expect(planet.storedMinerals, 0);

      PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(job.unitsDelivered, 50);
      // The three figures partition the order exactly.
      expect(job.unitsDelivered + job.unitsLost + job.unitsRemaining,
          job.unitsTotal);
    });

    test('lost units survive a reload', () {
      final (planet, universe) = routed();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 100,
        ticksPerRun: 1,
        unitsPerRun: 50,
      );
      PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      final revived = Planet.fromJson(planet.toJson());
      expect(revived.tradeJobs.single.unitsLost, 50);
      expect(revived.tradeJobs.single.unitsDelivered, 0);
    });

    test(
        'every resolved run lands one ledger entry, with a cause only on a loss',
        () {
      final (planet, universe) = routed();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 100,
        ticksPerRun: 1,
        unitsPerRun: 50,
      );
      final lost =
          PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      expect(lost.values.single.outcome, TradeRunOutcome.lost);
      expect(lost.values.single.cause, isNotNull,
          reason: 'a loss must be able to explain itself');

      final ok = PlanetTradeService.advanceAll(universe, rng: _rng);
      expect(ok.values.single.outcome, TradeRunOutcome.delivered);
      expect(ok.values.single.cause, isNull);

      expect(planet.tradeIncidents, hasLength(2));
      expect(planet.tradeIncidents.first.outcome, TradeRunOutcome.lost);
      expect(planet.tradeIncidents.first.cause, isNotNull);
      expect(planet.tradeIncidents.last.outcome, TradeRunOutcome.delivered);
      expect(planet.tradeIncidents.last.cause, isNull);
    });

    test('the ledger is bounded and keeps the newest entries', () {
      final (planet, universe) = routed();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 1000,
        ticksPerRun: 1,
        unitsPerRun: 10,
      );
      // 100 runs at a 1-tick cadence, far past the ten-entry cap.
      for (var i = 0; i < 100; i++) {
        PlanetTradeService.advanceAll(universe, rng: _rng);
      }
      expect(planet.tradeIncidents, hasLength(Planet.tradeIncidentHistory));
    });

    test('causes are contextual: a cause that cannot fit is never drawn', () {
      // Same sector: no pirates in orbit of your own spaceport, so the pirate
      // causes have zero weight and cannot be picked — a promise, not a rarity.
      final sameSector = PlanetTradeService.causeWeightsFor(
        hops: 0,
        portClass: PortClass.free,
        piratesAtPort: 0,
        anomalyAtPort: false,
        navHazAtPort: false,
      );
      expect(sameSector[TradeFailureCause.piratesDestroyed], 0);
      expect(sameSector[TradeFailureCause.piratesHijacked], 0);

      // Federal customs exist; a free port has none to seize against.
      final federal = PlanetTradeService.causeWeightsFor(
        hops: 3,
        portClass: PortClass.federal,
        piratesAtPort: 0,
        anomalyAtPort: false,
        navHazAtPort: false,
      );
      final free = PlanetTradeService.causeWeightsFor(
        hops: 3,
        portClass: PortClass.free,
        piratesAtPort: 0,
        anomalyAtPort: false,
        navHazAtPort: false,
      );
      expect(federal[TradeFailureCause.customsSeizure], greaterThan(0));
      expect(free[TradeFailureCause.customsSeizure], 0);

      // Pirates in orbit make the pirate causes dominant.
      final hunted = PlanetTradeService.causeWeightsFor(
        hops: 4,
        portClass: PortClass.free,
        piratesAtPort: 3,
        anomalyAtPort: false,
        navHazAtPort: false,
      );
      final quiet = PlanetTradeService.causeWeightsFor(
        hops: 4,
        portClass: PortClass.free,
        piratesAtPort: 0,
        anomalyAtPort: false,
        navHazAtPort: false,
      );
      expect(hunted[TradeFailureCause.piratesDestroyed],
          greaterThan(quiet[TradeFailureCause.piratesDestroyed]!));

      // An anomaly only throws storms where there is one.
      final stormy = PlanetTradeService.causeWeightsFor(
        hops: 1,
        portClass: PortClass.free,
        piratesAtPort: 0,
        anomalyAtPort: true,
        navHazAtPort: false,
      );
      expect(stormy[TradeFailureCause.anomalyStorm], greaterThan(0));
      expect(quiet[TradeFailureCause.anomalyStorm], 0);
    });

    test('pickCause covers every cause and honours a zero total', () {
      // Sweep the whole weight space: every drawable cause must be reachable,
      // or a whole row of the enum is content the player will never read.
      final seen = <TradeFailureCause>{};
      for (var i = 0; i < 400; i++) {
        final cause = PlanetTradeService.pickCause(
          PlanetTradeService.causeWeightsFor(
            hops: 4,
            portClass: PortClass.federal,
            piratesAtPort: 5,
            anomalyAtPort: true,
            navHazAtPort: true,
          ),
          math.Random(i),
        );
        expect(cause, isNotNull);
        seen.add(cause!);
      }
      expect(seen, TradeFailureCause.values.toSet());

      // Every weight zero: null rather than a modulo-by-zero throw, which
      // would take the whole tick down from inside the trade pass.
      final empty = {
        for (final c in TradeFailureCause.values) c: 0,
      };
      expect(PlanetTradeService.pickCause(empty, math.Random(1)), isNull);
    });

    test('a zero weight is a promise: that cause is never drawn', () {
      // Asserting the *weights* are zero cannot catch a picker that ignores
      // them — the rule and the draw are separate facts, and only the draw
      // says whether the promise holds. So each cause is made the sole
      // candidate in turn and swept: with every other weight at zero, nothing
      // else may come back.
      for (final only in TradeFailureCause.values) {
        for (var i = 0; i < 50; i++) {
          final weights = {
            for (final c in TradeFailureCause.values) c: c == only ? 10 : 0,
          };
          expect(PlanetTradeService.pickCause(weights, math.Random(i)), only,
              reason: '$only was reachable alongside a zero-weight rival');
        }
      }
    });

    test('incidents round-trip and survive a world being destroyed', () {
      final (planet, universe) = routed();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 5,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 50,
        ticksPerRun: 1,
        unitsPerRun: 50,
      );
      PlanetTradeService.advanceAll(universe, rng: _AlwaysFailRandom());
      final entry = planet.tradeIncidents.single;

      final revived = Planet.fromJson(planet.toJson());
      expect(revived.tradeIncidents, hasLength(1));
      final back = revived.tradeIncidents.single;
      expect(back.units, entry.units);
      expect(back.outcome, TradeRunOutcome.lost);
      expect(back.cause, entry.cause);
      expect(back.tick, entry.tick);
      expect(back.portSectorId, 5);

      // A vaporised world has no shipments left to have lost.
      revived.destroy();
      expect(revived.tradeIncidents, isEmpty);
    });
  });

  group('order grouping and whole-order cancel', () {
    (Planet, List<Sector>) twoPortWorld() {
      final planet = _world();
      final universe = [
        Sector(
            id: 1,
            name: 'Home',
            x: 0,
            y: 0,
            warpRoutes: const [2, 3],
            planets: [planet]),
        Sector(
            id: 2,
            name: 'Near',
            x: 100,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: Port(
              name: 'Near Port',
              portClass: PortClass.free,
              buyPrices: const {},
              sellPrices: const {'minerals': 50},
              supply: const {'minerals': 3000},
              demand: const {},
              maxSupply: const {'minerals': 80000},
              maxDemand: const {},
              portCredits: 1000000,
              desiredCredits: 1000000,
            )),
        Sector(
            id: 3,
            name: 'Far',
            x: 200,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: Port(
              name: 'Far Port',
              portClass: PortClass.free,
              buyPrices: const {},
              sellPrices: const {'minerals': 50},
              supply: const {'minerals': 4000},
              demand: const {},
              maxSupply: const {'minerals': 80000},
              maxDemand: const {},
              portCredits: 1000000,
              desiredCredits: 1000000,
            )),
      ];
      return (planet, universe);
    }

    test('one tap is one order id across every share', () {
      final (planet, universe) = twoPortWorld();
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 6000,
        actorFaction: 'trader',
      );
      // 3,000 near + 3,000 far: two shares, one order, hold-size runs.
      expect(result.jobs, hasLength(2));
      expect(result.jobs[0].orderId, isNotEmpty);
      expect(result.jobs[1].orderId, result.jobs[0].orderId);
      expect(result.jobs[0].unitsPerRun, PlanetTradeService.freighterHold);
      expect(result.placedUnits, 6000);
      expect(result.shortfall, 0);
      expect(result.portSectorIds.toSet(), {2, 3});
      // Both shelves shrank: the reservation is real on both ports.
      expect(universe[1].port!.getSupply('minerals'), 0);
      expect(universe[2].port!.getSupply('minerals'), 1000);
    });

    test('cancelOrder unwinds every share and refunds the remainder', () {
      final (planet, universe) = twoPortWorld();
      // Restock above the hold so the first run lands only part of a share.
      universe[1].port = universe[1].port!.copyWith(
        supply: const {'minerals': 12000},
        maxSupply: const {'minerals': 80000},
      );
      universe[2].port = universe[2].port!.copyWith(
        supply: const {'minerals': 12000},
        maxSupply: const {'minerals': 80000},
      );
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 20000,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(2));
      // One run lands on each share (both 1 hop: 2 ticks, 5,000-unit runs).
      PlanetTradeService.advanceAll(universe, rng: _rng);
      PlanetTradeService.advanceAll(universe, rng: _rng);
      var landedRemainder = 0;
      for (final j in result.jobs) {
        expect(j.unitsRemaining, lessThan(j.unitsTotal));
        landedRemainder += j.unitsRemaining;
      }

      final beforeNear = universe[1].port!.getSupply('minerals');
      final cancel =
          PlanetTradeService.cancelOrder(planet, universe, result.orderId);
      expect(planet.tradeJobs, isEmpty);
      // Shelves grow back by exactly the unlanded remainder — delivered runs
      // stay delivered.
      expect(universe[1].port!.getSupply('minerals'),
          beforeNear + result.jobs[0].unitsRemaining);
      expect(landedRemainder, greaterThan(0));
      // Refund covers the unlanded remainder only.
      var expected = 0;
      for (final j in result.jobs) {
        expected += j.unitsRemaining * j.unitPrice;
      }
      expect(cancel.refund, expected);
      expect(cancel.portSectorIds.toSet(), {2, 3});
    });

    test('pre-grouping jobs carry no order id and group alone', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 6,
        ticksPerRun: 2,
      )!;
      expect(job.orderId, isEmpty);
      expect(
          PlanetTradeService.cancelOrder(planet, [_sectorWith(planet)], job.id)
              .refund,
          6 * job.unitPrice);
      expect(planet.tradeJobs, isEmpty);
    });
  });

  group('model floors', () {
    test('an explicit zero cadence clamps instead of quickening', () {
      final job = TradeJob.fromJson({
        'playerId': 'p1',
        'planetId': 'w1',
        'portSectorId': 2,
        'commodity': 'minerals',
        'direction': 'buy',
        'unitsTotal': 100,
        'ticksPerRun': 0,
        'unitsRemaining': 100,
        'ticksRemaining': 0,
      });
      // A hand-edited `"ticksPerRun": 0` used to deliver a full hold every
      // tick — distance cadence deleted by hand. Now the cadence is 1 and
      // the corrupt zero-countdown fires exactly once, for one unit, before
      // the standard rhythm takes over.
      expect(job.ticksPerRun, 1);
      expect(job.advance(), 1);
      expect(job.unitsRemaining, 99);
      expect(job.advance(), 1);
      expect(job.unitsRemaining, 98);
    });

    test('a zero or negative hold clamps instead of stalling or growing', () {
      for (final hold in [0, -50]) {
        final job = TradeJob(
          playerId: 'p1',
          planetId: 'w1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.buy,
          unitsTotal: 10,
          ticksPerRun: 2,
          unitsPerRun: hold,
        );
        expect(job.unitsPerRun, 1);
        // One full cadence lands exactly one unit: no stall, and the
        // remainder never climbs.
        expect(job.advance(), 0);
        expect(job.advance(), 1);
        expect(job.unitsRemaining, 9);
      }
    });

    test('escrow round-trips through JSON', () {
      final job = TradeJob(
        playerId: 'p1',
        planetId: 'w1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        unitsTotal: 100,
        ticksPerRun: 2,
        unitPrice: 50,
        escrowed: 100,
      );
      expect(TradeJob.fromJson(job.toJson()).escrowed, 100);
    });
  });

  group('escrow conservation', () {
    (Planet, List<Sector>) poorPortWorld() {
      final planet = _world()..storedMinerals = 100000;
      Port port({required int credits, required int demand}) => Port(
            name: 'Poor Port',
            portClass: PortClass.free,
            buyPrices: const {'minerals': 50},
            sellPrices: const {},
            supply: const {},
            demand: {'minerals': demand},
            maxSupply: const {},
            maxDemand: const {'minerals': 60000},
            portCredits: credits.toDouble(),
            desiredCredits: 1000000,
          );
      final universe = [
        Sector(
            id: 1,
            name: 'Home',
            x: 0,
            y: 0,
            warpRoutes: const [2, 3],
            planets: [planet]),
        Sector(
            id: 2,
            name: 'Poor',
            x: 100,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: port(credits: 100, demand: 10000)),
        Sector(
            id: 3,
            name: 'Rich',
            x: 200,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: port(credits: 1000000, demand: 10000)),
      ];
      return (planet, universe);
    }

    test('reserve-then-cancel on a cash-poor port mints nothing', () {
      final (planet, universe) = poorPortWorld();
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.sell,
        volume: 1000,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(1));
      // Worth 50,000 against a 100-credit pool: only 100 was ever taken.
      expect(result.jobs.single.escrowed, 100);
      expect(universe[1].port!.portCredits, 0);

      PlanetTradeService.cancelOrder(planet, universe, result.orderId);
      // Exactly what was taken comes back — the old code returned the full
      // 50,000 here, a repeatable 49,900-credit mint per cycle.
      expect(universe[1].port!.portCredits, 100);
      expect(planet.tradeJobs, isEmpty);
    });

    test('overlapping reservations balance to the credit', () {
      final (planet, universe) = poorPortWorld();
      // A buy that pays the poor port first: pool 100 + 500.
      universe[1].port = universe[1].port!.copyWith(
        buyPrices: const {'minerals': 60},
        sellPrices: const {'minerals': 50},
        supply: const {'minerals': 5000},
        maxSupply: const {'minerals': 80000},
      );
      final buyShare = TradeAllocation(
          portSectorId: 2, units: 500, hops: 1, ticksPerRun: 2, unitPrice: 1);
      final buyValue = PlanetTradeService.reserveShare(
        universe: universe,
        share: buyShare,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        actorFaction: 'trader',
      );
      expect(buyValue, isNotNull);
      expect(universe[1].port!.portCredits, 600);
      // A sell that escrows the whole pool: 600 of a larger nominal.
      final sellShare = TradeAllocation(
          portSectorId: 2, units: 600, hops: 1, ticksPerRun: 2, unitPrice: 10);
      final sellRes = PlanetTradeService.reserveShare(
        universe: universe,
        share: sellShare,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        actorFaction: 'trader',
      );
      expect(sellRes!.escrowed, 600);
      expect(universe[1].port!.portCredits, 0);
      // Unwind both in reverse: the buy release subtracts its exact 500 even
      // though the pool sits at 0 — the sell reservation is holding it.
      PlanetTradeService.releaseReservation(
        universe: universe,
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 500,
        unitPrice: 1,
        escrowed: 500,
      );
      expect(universe[1].port!.portCredits, -500);
      PlanetTradeService.releaseReservation(
        universe: universe,
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        units: 600,
        unitPrice: 10,
        escrowed: 600,
      );
      // To the credit: every movement reversed exactly.
      expect(universe[1].port!.portCredits, 100);
    });
  });

  group('T2 tick persistence', () {
    test('multi-run countdown survives save-reload-advance', () async {
      final planet = _world();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 4,
        ticksPerRun: 2,
      );
      final store = FaithfulUniverse([_sectorWith(planet)]);

      // Mutate (one tick of countdown), save, reload into a fresh graph.
      var loaded = await store.loadUniverse();
      PlanetTradeService.advanceAll(loaded, rng: _rng);
      await store.saveUniverse(loaded);

      // Reload from the **blob**, which is what models a restart. It used to
      // come from `loadUniverse()`, asserting the graph was a different object —
      // "must be a different object graph (the productionRemainder lesson)".
      //
      // That assertion is now inverted. Storage shares one graph for the
      // session, so a load *cannot* hand back a second copy: the production-
      // Remainder bug needed a re-parse to throw the carry away, and there is no
      // re-parse left to do it. The lesson underneath still holds — a counter
      // that is not persisted resets — but it is a claim about **durability**,
      // so the guard has to cross the durability boundary. `snapshot()` is that
      // boundary: a genuine decode of the stored JSON, exactly what a relaunched
      // app sees, and nothing like the in-memory reload it replaces.
      var reloaded = store.snapshot();
      final job = reloaded.first.planets.first.tradeJobs.single;
      expect(job.unitsRemaining, 4);
      expect(job.ticksRemaining, 1);

      // Advance to the first landing after the reload: proves the countdown
      // was carried, not reset to full.
      final landed = PlanetTradeService.advanceAll(reloaded, rng: _rng);
      expect(landed.values.single.units, 2);
      expect(reloaded.first.planets.first.storedMinerals, 2);
      // And the job is still in flight, not completed early.
      expect(reloaded.first.planets.first.tradeJobs, hasLength(1));
    });

    test('trade jobs round-trip through Planet JSON', () {
      final planet = _world();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'organics',
        direction: TradeDirection.buy,
        units: 8,
        ticksPerRun: 4,
        unitPrice: 7,
      );
      PlanetTradeService.advanceAll([_sectorWith(planet)], rng: _rng);

      final revived = Planet.fromJson(planet.toJson());
      final job = revived.tradeJobs.single;
      expect(job.planetId, planet.id);
      expect(job.commodity, 'organics');
      expect(job.unitPrice, 7);
      expect(job.unitsRemaining, 8);
      // One tick of countdown was consumed before the save.
      expect(job.ticksRemaining, 3);
    });

    test('tick saves unconditionally so a countdown cannot reset', () async {
      // Structural: the save must not be gated on a hand-maintained list of
      // counters (the colonist-transit lesson — a countdown nobody logs
      // resets to full every tick and the shipment never lands).
      final content = await UniverseStorageSavesUnconditionally.readTickBody();
      expect(content, contains('saveUniverse(sectors)'));
      expect(content, isNot(contains('if (portsRegened')));
    });
  });
}

/// Reads this repo's tick body to assert the save is ungated.
///
/// A source scan is the documented exception for exactly this question: a full
/// tick fixture is a large thing for "is there a call site", and only a scan
/// asks it (see gravity_wiring_test.dart for the precedent).
class UniverseStorageSavesUnconditionally {
  static Future<String> readTickBody() async {
    // Cheap and honest: the guard is about the tick file's own structure.
    final file = await _read('lib/services/game_tick_service.dart');
    final start = file.indexOf('Save the universe. **Unconditionally');
    return file.substring(start < 0 ? 0 : start);
  }

  static Future<String> _read(String path) async {
    // Tests run with the package root as cwd.
    final f = _File(path);
    return f.readAsString();
  }
}

// Minimal file reader without importing dart:io into the test zone twice.
class _File {
  _File(this.path);
  final String path;
  Future<String> readAsString() => io.File(path).readAsString();
}
