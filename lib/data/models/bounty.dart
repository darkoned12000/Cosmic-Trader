import 'package:cosmic_trader/services/game_clock.dart';

/// A bounty posted on a pilot's head.
class Bounty {
  final String id;
  final String targetId;
  final String targetName;
  final String targetFaction;
  final bool targetIsPlayer;
  final int amount;
  final String posterId;
  final String posterName;
  final String posterFaction;
  final String reason;

  /// Game tick this bounty was posted. See `GameClock`.
  ///
  /// Ticks rather than a timestamp: this field existed only to derive the
  /// expiry, and its one display use is an "age ago" label, which is
  /// tick-derived anyway. Keeping a second clock in the model that nothing
  /// reads is how the wall-clock version of this rule came to disagree with
  /// the tick version in the first place.
  final int createdAtTick;

  /// Wall-clock expiry for escrow (bounty review): unclaimed marks lapse
  /// and the poster's credits refund instead of evaporating.
  /// Game tick at which this bounty lapses.
  final int expiresAtTick;

  /// Standard mark lifetime. Long enough to be huntable, short enough
  /// that dead targets stop squatting the board.
  /// One week, in ticks: 7 x 2,880 = 20,160.
  ///
  /// Was `Duration(days: 7)` against a wall-clock stamp, so a bounty lapsed
  /// during a week the game was closed and could be sat on indefinitely while
  /// shut — the same defect as the hack ban, in a place nobody had looked.
  static const int ttlTicks = GameClock.ticksPerDay * 7;

  const Bounty({
    required this.id,
    required this.targetId,
    required this.targetName,
    required this.targetFaction,
    this.targetIsPlayer = false,
    required this.amount,
    required this.posterId,
    required this.posterName,
    this.posterFaction = '',
    required this.reason,
    required this.createdAtTick,
    required this.expiresAtTick,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'targetId': targetId,
        'targetName': targetName,
        'targetFaction': targetFaction,
        'targetIsPlayer': targetIsPlayer,
        'amount': amount,
        'posterId': posterId,
        'posterName': posterName,
        'posterFaction': posterFaction,
        'reason': reason,
        'createdAtTick': createdAtTick,
        'expiresAtTick': expiresAtTick,
      };

  factory Bounty.fromJson(Map<String, dynamic> json) {
    // Read the tick keys, and fall back to *now* rather than trying to convert a
    // wall-clock timestamp.
    //
    // The obvious migration — turn `createdAt` into "one second ago" — was
    // rejected: it would silently re-stamp every pre-existing bounty as brand new,
    // resetting both its age label and its remaining life, and a player with a
    // week-old bounty would see it as freshly posted. Reading the legacy key as
    // absent means the same thing for the expiry (a full TTL from load) but is at
    // least honest about it: the row's age is unknown, so it is treated as
    // starting now. Bounties are paid by players who posted them deliberately,
    // so losing a little elapsed time is the cheap direction.
    final createdAtTick =
        (json['createdAtTick'] as num?)?.toInt() ?? GameClock.tick;
    // Legacy rows that predate expiry get a full TTL from load, as before.
    final expiresAtTick = (json['expiresAtTick'] as num?)?.toInt() ??
        createdAtTick + Bounty.ttlTicks;
    return Bounty(
      id: json['id'] as String? ?? '',
      targetId: json['targetId'] as String? ?? '',
      targetName: json['targetName'] as String? ?? 'Unknown',
      targetFaction: json['targetFaction'] as String? ?? '',
      targetIsPlayer: json['targetIsPlayer'] as bool? ?? false,
      amount: (json['amount'] as num?)?.toInt() ?? 0,
      posterId: json['posterId'] as String? ?? '',
      posterName: json['posterName'] as String? ?? 'Anonymous',
      posterFaction: json['posterFaction'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      createdAtTick: createdAtTick,
      expiresAtTick: expiresAtTick,
    );
  }
}

/// One board target with its stacked marks, richest-group-first from
/// [BountyBoard.groupedTargets]. Read-only view over live bounties.
class BountyTargetGroup {
  final String targetId;
  final String targetName;
  final String targetFaction;
  final int total;
  final List<Bounty> marks;

  const BountyTargetGroup({
    required this.targetId,
    required this.targetName,
    required this.targetFaction,
    required this.total,
    required this.marks,
  });
}

/// A paid-out bounty, kept for the board's recent history.
class PaidBounty {
  final String targetName;
  final String targetFaction;
  final String killerName;
  final String killerFaction;
  final int amount;
  final DateTime paidAt;

  const PaidBounty({
    required this.targetName,
    this.targetFaction = '',
    required this.killerName,
    this.killerFaction = '',
    required this.amount,
    required this.paidAt,
  });

  Map<String, dynamic> toJson() => {
        'targetName': targetName,
        'targetFaction': targetFaction,
        'killerName': killerName,
        'killerFaction': killerFaction,
        'amount': amount,
        'paidAt': paidAt.toIso8601String(),
      };

  factory PaidBounty.fromJson(Map<String, dynamic> json) => PaidBounty(
        targetName: json['targetName'] as String? ?? 'Unknown',
        targetFaction: json['targetFaction'] as String? ?? '',
        killerName: json['killerName'] as String? ?? 'Unknown',
        killerFaction: json['killerFaction'] as String? ?? '',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        paidAt: json['paidAt'] != null
            ? DateTime.parse(json['paidAt'] as String)
            : DateTime.now(),
      );
}
