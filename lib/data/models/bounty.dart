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
      };

  factory Bounty.fromJson(Map<String, dynamic> json) => Bounty(
        id: json['id'] as String? ?? '',
        targetId: json['targetId'] as String? ?? '',
        targetName: json['targetName'] as String? ?? 'Unknown',
        targetFaction: json['targetFaction'] as String? ?? 'pirate',
        targetIsPlayer: json['targetIsPlayer'] as bool? ?? false,
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        posterId: json['posterId'] as String? ?? '',
        posterName: json['posterName'] as String? ?? 'Anonymous',
        posterFaction: json['posterFaction'] as String? ?? '',
        reason: json['reason'] as String? ?? '',
        createdAt: json['createdAt'] != null
            ? DateTime.parse(json['createdAt'] as String)
            : DateTime.now(),
      );
}

/// A paid-out bounty, kept for the board's recent history.
class PaidBounty {
  final String targetName;
  final String killerName;
  final int amount;
  final DateTime paidAt;

  const PaidBounty({
    required this.targetName,
    required this.killerName,
    required this.amount,
    required this.paidAt,
  });

  Map<String, dynamic> toJson() => {
        'targetName': targetName,
        'killerName': killerName,
        'amount': amount,
        'paidAt': paidAt.toIso8601String(),
      };

  factory PaidBounty.fromJson(Map<String, dynamic> json) => PaidBounty(
        targetName: json['targetName'] as String? ?? 'Unknown',
        killerName: json['killerName'] as String? ?? 'Unknown',
        amount: (json['amount'] as num?)?.toInt() ?? 0,
        paidAt: json['paidAt'] != null
            ? DateTime.parse(json['paidAt'] as String)
            : DateTime.now(),
      );
}
