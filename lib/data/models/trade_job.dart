import 'dart:math' as math;

import 'package:uuid/uuid.dart';

/// A bulk goods order placed against a port, fulfilled over multiple ticks.
///
/// A run takes `ticksPerRun` ticks (hops-scaled) and carries up to
/// `unitsPerRun` units (the freighter hold), so distance sets the cadence
/// and order size sets the run count: a 3,700-unit order against a 3-hop
/// port is one run taking 6 ticks. The countdown advances once per game
/// tick, driven by `PlanetTradeService`.
class TradeJob {
  TradeJob({
    String? id,
    required this.playerId,
    required this.planetId,
    required this.portSectorId,
    required this.commodity,
    required this.direction,
    required this.unitsTotal,
    required int ticksPerRun,
    this.unitPrice = 0,
    int? unitsPerRun,
    String? orderId,
    this.escrowed,
    int? unitsRemaining,
    int? ticksRemaining,
  })  : id = id ?? const Uuid().v4(),
        unitsRemaining = unitsRemaining ?? unitsTotal,
        ticksRemaining = ticksRemaining ?? ticksPerRun,
        // Floors, not validations. A rule enforced only at `create()` is a
        // rule a save-file edit bypasses: an explicit `"ticksPerRun": 0`
        // delivers a full hold every tick (distance cadence deleted by hand),
        // and a zero/negative `unitsPerRun` stalls forever — or worse, a
        // negative one grows `unitsRemaining` without bound while `advanceAll`
        // drops the negative delivery on the floor. Clamp here so every
        // construction site, present and future, gets the same floor.
        // NOTE: `ticksPerRun` on the right-hand side is the raw parameter,
        // not the clamped field — parameters shadow fields throughout the
        // initializer list — so the hold default clamps it explicitly.
        ticksPerRun = math.max(1, ticksPerRun),
        // Pre-hold saves carry no run size: they keep the original pacing of
        // one run per `ticksPerRun` ticks delivering `ticksPerRun` units.
        // Anything created since carries the freighter hold instead.
        unitsPerRun = math.max(1, unitsPerRun ?? math.max(1, ticksPerRun)),
        orderId = orderId ?? '';

  /// Stable identity, so a cancel can name one job out of several.
  final String id;

  /// The pilot who placed the order.
  final String playerId;

  /// The world that ordered, by [Planet.id]. Stored rather than inferred from
  /// the list that holds the job, so a job survives a reload on its own terms.
  final String planetId;

  /// The sector whose port fills the order.
  final int portSectorId;

  final String commodity;
  final TradeDirection direction;

  /// Units ordered. Fixed at creation.
  final int unitsTotal;

  /// Ticks per run. Fixed at creation.
  final int ticksPerRun;

  /// Agreed price per unit, fixed at creation. A buy job paid
  /// `unitsTotal * unitPrice` up front; a sell job earns it into the world's
  /// `accumulatedRevenue` as runs land.
  final int unitPrice;

  /// Credits actually taken from the port's pool when a sell share was
  /// reserved. Null for buys (the port receives; nothing is escrowed) and
  /// for pre-accounting saves.
  ///
  /// The pool can hold less than the order is worth, in which case the
  /// reservation escrows what is there (clamped at 0, the player-port sell
  /// convention). Releasing the *nominal* value instead of this recorded one
  /// mints the difference out of nothing on every reserve-then-cancel
  /// against a cash-poor port — repeatable without limit, and it feeds the
  /// price multiplier. The release path restores exactly this.
  final int? escrowed;

  /// Units one freighter run carries. Fixed at creation.
  ///
  /// Distance sets the *cadence* (`ticksPerRun`) and the hold sets the
  /// *size*: a 3,700-unit order against a 3-hop port is one 3,700-unit run
  /// taking 6 ticks, not 617 runs of 6. Coupling the two made far ports
  /// slower per unit rather than slower per run — a 31-hour order the
  /// quote had priced as minutes.
  final int unitsPerRun;

  /// Which request this share belongs to. One tap on Buy/Sell is one order,
  /// possibly split across ports; the screen groups rows by this so a split
  /// order reads as one job with one Cancel rather than N unrelated rows.
  /// Empty for pre-grouping saves, which group alone.
  final String orderId;

  /// Units still to be delivered.
  int unitsRemaining;

  /// Units destroyed or stolen in transit — they never arrive and are gone.
  ///
  /// **Separate from [unitsRemaining] on purpose.** `unitsTotal -
  /// unitsRemaining` is what the order has *finished with*, which counts a
  /// lost run as delivered; the row that reads "4.0K / 10.0K" after a run was
  /// destroyed is a number that overstates what the player received, which is
  /// worse than showing none. Delivered is derived from the four figures, so
  /// they partition the order exactly.
  ///
  /// Persisted, because a loss survives a reload and a counter that resets
  /// would under-report one — the production-remainder lesson again.
  int unitsLost = 0;

  /// Units impounded by customs. Arrived nowhere near destroyed: the run
  /// *delivered*, just less of it.
  ///
  /// Tracked apart from [unitsLost] so the report can say which happened. They
  /// are the same for arithmetic — both are units the player paid for and does
  /// not have — and different for everything the player reads.
  int unitsSeized = 0;

  /// How much of [escrowed] has already been handed back to the port.
  ///
  /// A run that never delivers releases its slice of the reservation, and a
  /// share can lose several runs before it completes — so [releaseShare] cannot
  /// keep refunding `escrowed` in full or a cancel on top of two losses
  /// mints the escrow twice. The slice release records what it gave back here
  /// and cancel refunds the remainder. Tracked rather than recomputed from
  /// units, because the escrow is *clamped* to the port's pool: the nominal
  /// figure and the recorded one differ by design, and only the recorded one
  /// splits correctly.
  int escrowedReleased = 0;

  /// Units of this share still owed back to the port's reservation.
  int get escrowOutstanding => math.max(0, (escrowed ?? 0) - escrowedReleased);

  /// What this order is indemnified for. Fixed at creation, like the price.
  TradeInsurance insurance = TradeInsurance.none;

  /// Credits charged for [insurance] at order time, in both directions.
  ///
  /// Stored rather than recomputed on payout because the premium is a function
  /// of the **order's risk**, which is a function of the hops and run count as
  /// they were when the order was placed — and the universe is re-parsed every
  /// tick, so a later recalculation could read a different route. A premium that
  /// drifts from the quote the player accepted is worse than no premium at all.
  int premiumPaid = 0;

  /// Whether this share carries any cover. Read more often than the enum
  /// comparison, because the payout branch keys on it.
  bool get isInsured => insurance != TradeInsurance.none;

  /// Ticks left in the current run.
  int ticksRemaining;

  /// True when the order has fully landed.
  bool get isComplete => unitsRemaining <= 0;

  /// Whether the run in flight has been lost to a failure roll.
  ///
  /// Set by `PlanetTradeService` when the roll comes up bad, cleared the next
  /// time a run lands cleanly. Transient by design: a failure is an event, and
  /// the job carries on with its remainder — the loss is the delivered units
  /// that never arrived plus the credits already spent on them, both of which
  /// the *screen* reports at the moment it happens.
  bool lastRunFailed = false;

  /// Advances the order by one tick, landing a run when it comes due.
  ///
  /// Returns the units that landed this tick (0 if the run is still in flight).
  /// A run fires when [ticksRemaining] reaches 0, delivering [unitsPerRun]
  /// units (or whatever is left, if the order is nearly complete).
  int advance() {
    if (isComplete) return 0;

    ticksRemaining--;
    if (ticksRemaining > 0) return 0;

    final delivered =
        unitsPerRun < unitsRemaining ? unitsPerRun : unitsRemaining;
    unitsRemaining -= delivered;
    ticksRemaining = ticksPerRun;
    return delivered;
  }

  /// Runs the whole order needs at the current hold size.
  int get runsTotal {
    if (unitsPerRun <= 0) return 1;
    return (unitsTotal + unitsPerRun - 1) ~/ unitsPerRun;
  }

  /// Runs already fully landed.
  int get runsDone {
    if (unitsPerRun <= 0) return 0;
    return (unitsTotal - unitsRemaining) ~/ unitsPerRun;
  }

  /// Ticks until the final run lands, assuming the tick keeps advancing.
  int get ticksLeft {
    final remainingRuns = runsTotal - runsDone;
    if (remainingRuns <= 0) return 0;
    return ticksRemaining + (remainingRuns - 1) * ticksPerRun;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'playerId': playerId,
        'planetId': planetId,
        'portSectorId': portSectorId,
        'commodity': commodity,
        'direction': direction.name,
        'unitsTotal': unitsTotal,
        'ticksPerRun': ticksPerRun,
        'unitPrice': unitPrice,
        'escrowed': escrowed,
        'unitsPerRun': unitsPerRun,
        'orderId': orderId,
        'unitsRemaining': unitsRemaining,
        'unitsLost': unitsLost,
        'unitsSeized': unitsSeized,
        'escrowedReleased': escrowedReleased,
        'insurance': insurance.name,
        'premiumPaid': premiumPaid,
        'ticksRemaining': ticksRemaining,
      };

  /// Total from a legacy save. Missing fields default to a finished order,
  /// except the run size, which defaults to the old coupled pacing so an
  /// in-flight order keeps the rhythm it was quoted at.
  factory TradeJob.fromJson(Map<String, dynamic> json) {
    final ticksPerRun = (json['ticksPerRun'] as num?)?.toInt() ?? 1;
    return TradeJob(
      id: json['id'] as String?,
      playerId: json['playerId'] as String? ?? '',
      planetId: json['planetId'] as String? ?? '',
      portSectorId: (json['portSectorId'] as num?)?.toInt() ?? 0,
      commodity: json['commodity'] as String? ?? 'minerals',
      direction: TradeDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TradeDirection.buy,
      ),
      unitsTotal: (json['unitsTotal'] as num?)?.toInt() ?? 0,
      ticksPerRun: ticksPerRun,
      unitPrice: (json['unitPrice'] as num?)?.toInt() ?? 0,
      escrowed: (json['escrowed'] as num?)?.toInt(),
      unitsPerRun: (json['unitsPerRun'] as num?)?.toInt() ?? ticksPerRun,
      orderId: json['orderId'] as String? ?? '',
      unitsRemaining: (json['unitsRemaining'] as num?)?.toInt(),
      ticksRemaining: (json['ticksRemaining'] as num?)?.toInt(),
    )
      // All three are T8-era counters, absent from every older save, and every
      // one defaults to zero because zero is the correct reading: an order from
      // a save that predates losses has lost nothing.
      ..unitsLost = (json['unitsLost'] as num?)?.toInt() ?? 0
      ..unitsSeized = (json['unitsSeized'] as num?)?.toInt() ?? 0
      ..escrowedReleased = (json['escrowedReleased'] as num?)?.toInt() ?? 0
      // Absent in every pre-insurance save, and `none` is the correct reading: an
      // order placed before cover existed was not covered.
      ..insurance = TradeInsurance.fromName(json['insurance'] as String?)
      ..premiumPaid = (json['premiumPaid'] as num?)?.toInt() ?? 0;
  }

  /// Units that actually reached the world.
  ///
  /// `unitsTotal - unitsRemaining` counts lost and impounded runs as
  /// delivered, so this subtracts them: the four figures (delivered, lost,
  /// seized, remaining) always sum to the order.
  ///
  /// Clamped rather than trusted: a hand-edited save can hold
  /// `unitsLost + unitsSeized > unitsTotal`, and a *negative* delivered figure
  /// is a worse lie than a wrong positive one — it would render as a store that
  /// owes the player goods.
  int get unitsDelivered => (unitsTotal -
          unitsRemaining -
          unitsLost -
          unitsSeized)
      .clamp(0, unitsTotal)
      // `int.clamp` is declared to return `num`, so without this the getter is
      // `num` and every `someInt += job.unitsDelivered` in the UI fails to
      // compile. Casting once here beats six casts at the call sites, and the
      // value is an integer by construction.
      .toInt();

  /// Units the player paid for and does not have, either way.
  ///
  /// The number the row's red figure is really about: it is the shortfall, and
  /// reporting it as one figure is why the row can say "5.0K short" without the
  /// player caring whether pirates or customs took it.
  int get unitsShortfall => unitsLost + unitsSeized;
}

/// How much of a lost run an order is indemnified for, bought at order time.
///
/// **Indemnity, not prevention.** Insurance refunds a run that is destroyed; it
/// does not make the run safer. That distinction is the whole design: if it
/// lowered the failure chance instead, the `N% run risk` the player accepted
/// would no longer be the risk they got, and the quote would have to recompute
/// itself with the premium attached. A number that changes meaning when you buy
/// something is a number nobody can reason about.
enum TradeInsurance {
  none('None', 0.0),
  half('Half', 0.5),
  full('Full', 1.0);

  const TradeInsurance(this.label, this.coverage);

  final String label;

  /// Fraction of a destroyed run's units that comes back. Never covers a
  /// [TradeRunOutcome.seized] run: customs is a legal consequence of the
  /// route, not an accident of the transit, and covering it would make the
  /// policy a flat 100% refund with a premium attached. That one exclusion is
  /// what gives the choice anything to decide.
  final double coverage;

  static TradeInsurance fromName(String? name) => TradeInsurance.values
      .firstWhere((i) => i.name == name, orElse: () => TradeInsurance.none);
}

/// Which way goods move for a [TradeJob].
enum TradeDirection {
  /// The player buys from the port (port sells, player receives).
  buy,

  /// The player sells to the port (port buys, player delivers).
  sell,
}

/// What a resolved run actually did with the units it carried.
///
/// The four classes are the whole point of [TradeFailureCause] existing: a
/// cause that always ends in "the cargo is gone" makes the reason cosmetic,
/// because the player's response to all six is identical and there is nothing
/// to decide. With these classes, "diverted for fuel" and "confiscated" are
/// *not* the same event as "destroyed" and the player can tell them apart at a
/// glance.
enum TradeRunOutcome {
  /// Arrived whole. The only outcome with no cause.
  delivered,

  /// Destroyed or stolen. The units never arrive and are gone.
  lost,

  /// Diverted. Nothing is lost and no units are consumed — the run simply
  /// happens later than quoted.
  delayed,

  /// Partly confiscated. Most of the run arrives; the rest is impounded, and
  /// the shipment is reported as a partial delivery rather than a total loss.
  seized,
}

/// Why a run of freight did not arrive intact.
///
/// **Contextual, not flavour.** The weights that pick one live in
/// `PlanetTradeService`, and they read the route: pirates dominate where
/// pirates are and on long hauls, a federal port seizes and a free one does
/// not, an anomaly sector throws storms. A reason that could appear anywhere
/// tells the player nothing about the route they chose, which is the thing
/// they would change.
///
/// [outcome] lives **on the enum**, not in a switch inside the service. The
/// weights and the outcome have to agree — a reroute that also destroyed the
/// cargo would be a lie in the report — and a switch is a second place for
/// that to drift. One row of this table is the whole rule, so a new cause
/// cannot be added without declaring what it does.
enum TradeFailureCause {
  piratesDestroyed('Pirates destroyed the freighter', TradeRunOutcome.lost),
  piratesHijacked('Pirates hijacked the freighter', TradeRunOutcome.lost),
  fuelContainment(
      'Fuel containment failure — freight diverted', TradeRunOutcome.delayed),
  rerouted('A hacker re-routed the shipment', TradeRunOutcome.delayed),
  customsSeizure(
      'Port customs impounded part of the shipment', TradeRunOutcome.seized),
  anomalyStorm('An anomaly storm scattered the shipment', TradeRunOutcome.lost);

  const TradeFailureCause(this.label, this.outcome);

  /// Player-facing sentence. Not interpolated with numbers, so it composes
  /// with a separate units/port line without grammar surprises.
  final String label;

  /// What this cause does to the run. See [TradeRunOutcome].
  final TradeRunOutcome outcome;

  /// Extra ticks a [TradeRunOutcome.delayed] run costs.
  ///
  /// A quote is a promise about *arrival*, and a diversion is the one failure
  /// that does not cost the player goods — only patience. Four ticks is a
  /// third of a typical hop-cadence run: enough to be felt on the countdown
  /// bar, not enough to strand an order the player is watching.
  int get delayTicks => this == rerouted ? 4 : 3;
}

/// One resolved run, kept as a short history on the world.
///
/// A **record, not state**: nothing reads it to decide anything, it exists so
/// the player can ask what happened to their freight. It lives on the planet
/// (bounded, persisted) rather than on the player because the tick owns the
/// world and must never write a player — the same reason
/// `Planet.accumulatedRevenue` exists.
class TradeIncident {
  TradeIncident({
    String? id,
    this.orderId = '',
    required this.tick,
    required this.commodity,
    required this.direction,
    required this.units,
    required this.portSectorId,
    required this.outcome,
    this.cause,
    this.seizedUnits = 0,
    this.delayTicks = 0,
    this.insuredUnits = 0,
  }) : id = id ?? const Uuid().v4();

  final String id;

  /// The request this run belongs to. Empty for pre-grouping saves.
  ///
  /// This is what lets the report answer "how did *that* order end" rather than
  /// listing ten unrelated rows: an 80,000-unit order is sixteen runs, and
  /// without it the player has to reassemble the order in their head.
  final String orderId;

  /// The game tick the run resolved on. Game time, never a wall clock.
  final int tick;
  final String commodity;
  final TradeDirection direction;

  /// Units the run carried.
  final int units;
  final int portSectorId;

  /// What happened to [units]. See [TradeRunOutcome].
  final TradeRunOutcome outcome;

  /// Why it was not a clean delivery. Null exactly when
  /// [outcome] is [TradeRunOutcome.delivered], so "delivered with a reason" is
  /// not a representable state.
  final TradeFailureCause? cause;

  /// Units impounded, for a [TradeRunOutcome.seized] run. Zero otherwise.
  ///
  /// The run *did* arrive, minus this much, so the report shows a partial
  /// delivery rather than a total loss — which is the difference between a
  /// customs problem and a war.
  final int seizedUnits;

  /// Extra ticks bought, for a [TradeRunOutcome.delayed] run. Zero otherwise.
  final int delayTicks;

  /// Units an insurer paid back on a [TradeRunOutcome.lost] run. Zero otherwise,
  /// and **zero on a seizure by design** — customs is a legal consequence of the
  /// route, not an accident of the transit.
  ///
  /// Recorded because a credit that arrives without an explanation is the thing
  /// this whole ledger exists to prevent: the player would see a warning, then
  /// money, and no way to connect them.
  final int insuredUnits;

  /// Units that made it to the world.
  int get deliveredUnits => outcome == TradeRunOutcome.delivered
      ? units
      : outcome == TradeRunOutcome.seized
          ? units - seizedUnits
          : 0;

  /// Units destroyed or stolen.
  int get lostUnits => outcome == TradeRunOutcome.lost ? units : 0;

  /// Units still in flight — diverted, not gone.
  int get deferredUnits => outcome == TradeRunOutcome.delayed ? units : 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'orderId': orderId,
        'tick': tick,
        'commodity': commodity,
        'direction': direction.name,
        'units': units,
        'portSectorId': portSectorId,
        'outcome': outcome.name,
        'cause': cause?.name,
        'seizedUnits': seizedUnits,
        'delayTicks': delayTicks,
        'insuredUnits': insuredUnits,
      };

  factory TradeIncident.fromJson(Map<String, dynamic> json) {
    // An older save wrote `delivered: true|false` with no outcome. Read it
    // forward: the flag becomes the outcome rather than being discarded,
    // because a lost run from a save that predates the four classes is still a
    // lost run and dropping it would silently improve the player's history.
    final legacyDelivered = json['delivered'] as bool?;
    final outcome = (json['outcome'] as String?) == null
        ? (legacyDelivered == false
            ? TradeRunOutcome.lost
            : TradeRunOutcome.delivered)
        : TradeRunOutcome.values.firstWhere(
            (o) => o.name == json['outcome'],
            // Unknown name: treat as lost, not delivered. Defaulting to
            // delivered is the optimistic reading, and an optimistic reading of
            // a corruption is how a lost shipment gets reported as a sale.
            orElse: () => TradeRunOutcome.lost,
          );
    return TradeIncident(
      id: json['id'] as String?,
      orderId: json['orderId'] as String? ?? '',
      tick: (json['tick'] as num?)?.toInt() ?? 0,
      commodity: json['commodity'] as String? ?? 'minerals',
      direction: TradeDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => TradeDirection.buy,
      ),
      units: (json['units'] as num?)?.toInt() ?? 0,
      portSectorId: (json['portSectorId'] as num?)?.toInt() ?? 0,
      outcome: outcome,
      cause: json['cause'] == null
          ? null
          : TradeFailureCause.values.firstWhere(
              (c) => c.name == json['cause'],
              // An unrecognised name reads as the generic mechanical cause
              // rather than crashing the world load — the same tolerance
              // `Planet.fromJson` shows for a removed faction.
              orElse: () => TradeFailureCause.fuelContainment,
            ),
      // A seizure implies at least one unit impounded; clamping to the run
      // stops a corrupt save claiming a *negative* delivery.
      seizedUnits: outcome == TradeRunOutcome.seized
          ? ((json['seizedUnits'] as num?)?.toInt() ?? 0)
              .clamp(0, (json['units'] as num?)?.toInt() ?? 0)
          : 0,
      delayTicks: (json['delayTicks'] as num?)?.toInt() ?? 0,
      insuredUnits: (json['insuredUnits'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A finished order, kept so a completed one does not vanish.
///
/// Without this the last run lands, the job leaves `planet.tradeJobs`, and the
/// row the player has been watching for an hour disappears — leaving no answer
/// to "what did that 80,000-mineral order actually get me?" except the run
/// ledger, which is truncated to ten entries and says nothing about totals.
///
/// Bounded and on the world for the same reason as [TradeIncident]: the tick
/// closes orders and must not write a player. Aggregating every world into one
/// ledger is a **read** over the player's worlds and needs no tick change, so
/// the cross-world view is a later screen rather than a later data model.
class TradeOrderRecord {
  TradeOrderRecord({
    String? orderId,
    required this.tick,
    required this.commodity,
    required this.direction,
    required this.unitsTotal,
    this.unitsDelivered = 0,
    this.unitsLost = 0,
    this.unitsSeized = 0,
    this.unitsCancelled = 0,
    this.revenue = 0,
    this.spend = 0,
    this.runs = 0,
    List<int>? ports,
  })  : orderId = orderId ?? const Uuid().v4(),
        ports = ports ?? const <int>[];

  final String orderId;
  final int tick;
  final String commodity;
  final TradeDirection direction;

  /// Units the order was placed for, summed across every port share.
  final int unitsTotal;

  final int unitsDelivered;
  final int unitsLost;
  final int unitsSeized;

  /// Units handed back when the player cancelled the remainder.
  final int unitsCancelled;

  /// Credits the world earned (a sell) or was charged (a buy), for this order
  /// only. The world's [Planet.accumulatedRevenue] cannot answer "which order
  /// paid for the citadel", and a split order across four ports cannot be
  /// read off a per-share figure either.
  final int revenue;
  final int spend;

  /// Runs it took, delivered and not.
  final int runs;

  /// Every port it was split across, nearest first.
  final List<int> ports;

  /// Whether anything went wrong, in the words the player cares about.
  ///
  /// Three states, not a count: a shortfall that happens on one run out of
  /// sixteen reads very differently from the same shortfall spread evenly, and
  /// only the totals survive to here.
  String get status {
    if (unitsCancelled > 0 && unitsDelivered == 0) return 'CANCELLED';
    if (unitsLost > 0 || unitsSeized > 0) return 'PARTIALLY LOST';
    return 'COMPLETE';
  }

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'tick': tick,
        'commodity': commodity,
        'direction': direction.name,
        'unitsTotal': unitsTotal,
        'unitsDelivered': unitsDelivered,
        'unitsLost': unitsLost,
        'unitsSeized': unitsSeized,
        'unitsCancelled': unitsCancelled,
        'revenue': revenue,
        'spend': spend,
        'runs': runs,
        'ports': ports,
      };

  factory TradeOrderRecord.fromJson(Map<String, dynamic> json) =>
      TradeOrderRecord(
        orderId: json['orderId'] as String?,
        tick: (json['tick'] as num?)?.toInt() ?? 0,
        commodity: json['commodity'] as String? ?? 'minerals',
        direction: TradeDirection.values.firstWhere(
          (d) => d.name == json['direction'],
          orElse: () => TradeDirection.buy,
        ),
        unitsTotal: (json['unitsTotal'] as num?)?.toInt() ?? 0,
        unitsDelivered: (json['unitsDelivered'] as num?)?.toInt() ?? 0,
        unitsLost: (json['unitsLost'] as num?)?.toInt() ?? 0,
        unitsSeized: (json['unitsSeized'] as num?)?.toInt() ?? 0,
        unitsCancelled: (json['unitsCancelled'] as num?)?.toInt() ?? 0,
        revenue: (json['revenue'] as num?)?.toInt() ?? 0,
        spend: (json['spend'] as num?)?.toInt() ?? 0,
        runs: (json['runs'] as num?)?.toInt() ?? 0,
        ports: (json['ports'] as List?)
            ?.map((e) => (e as num).toInt())
            .toList(growable: false),
      );
}
