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

  /// Ticks left in the current run.
  int ticksRemaining;

  /// True when the order has fully landed.
  bool get isComplete => unitsRemaining <= 0;

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
    );
  }
}

/// Which way goods move for a [TradeJob].
enum TradeDirection {
  /// The player buys from the port (port sells, player receives).
  buy,

  /// The player sells to the port (port buys, player delivers).
  sell,
}
