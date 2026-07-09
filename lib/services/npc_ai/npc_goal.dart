enum NpcGoalType {
  tradeRoute,
  explore,
  attack,
  bankDeposit,
  bankWithdraw,
  patrol,
  flee,
  upgradeEquipment,
  raidPort,
}

enum NpcGoalStatus {
  planning,
  travelling,
  executing,
  complete,
  failed,
}

class NpcGoal {
  final NpcGoalType type;
  final NpcGoalStatus status;
  final DateTime createdAt;
  final Map<String, dynamic> params;

  const NpcGoal({
    required this.type,
    required this.status,
    required this.createdAt,
    this.params = const {},
  });

  int? get targetSectorId => params['targetSectorId'] as int?;
  int? get buyPortId => params['buyPortId'] as int?;
  int? get sellPortId => params['sellPortId'] as int?;
  String? get targetId => params['targetId'] as String?;
  String? get commodity => params['commodity'] as String?;
  double? get buyPrice => params['buyPrice'] as double?;
  double? get sellPrice => params['sellPrice'] as double?;

  NpcGoal copyWith({
    NpcGoalType? type,
    NpcGoalStatus? status,
    DateTime? createdAt,
    Map<String, dynamic>? params,
  }) {
    return NpcGoal(
      type: type ?? this.type,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      params: params ?? this.params,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
      'params': params,
    };
  }

  factory NpcGoal.fromJson(Map<String, dynamic> json) {
    return NpcGoal(
      type: NpcGoalType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NpcGoalType.explore,
      ),
      status: NpcGoalStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => NpcGoalStatus.planning,
      ),
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
      params: Map<String, dynamic>.from(json['params'] ?? {}),
    );
  }
}
