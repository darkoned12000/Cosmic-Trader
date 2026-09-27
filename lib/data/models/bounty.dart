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
  final DateTime createdAt;

  /// Wall-clock expiry for escrow (bounty review): unclaimed marks lapse
  /// and the poster's credits refund instead of evaporating.
  final DateTime expiresAt;

  /// Standard mark lifetime. Long enough to be huntable, short enough
  /// that dead targets stop squatting the board.
  static const Duration ttl = Duration(days: 7);

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
    required this.createdAt,
    required this.expiresAt,
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
        'createdAt': createdAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
      };

  factory Bounty.fromJson(Map<String, dynamic> json) {
    DateTime createdAt;
    try {
      createdAt = json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now();
    } catch (_) {
      createdAt = DateTime.now();
    }
    DateTime expiresAt;
    try {
      expiresAt = json['expiresAt'] != null
          ? DateTime.parse(json['expiresAt'] as String)
          // Legacy rows predate expiry: full TTL from creation.
          : createdAt.add(Bounty.ttl);
    } catch (_) {
      expiresAt = createdAt.add(Bounty.ttl);
    }
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
      createdAt: createdAt,
      expiresAt: expiresAt,
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
