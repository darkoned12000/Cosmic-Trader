import 'package:tradewars_2050/data/models/port.dart';

class PortInfo {
  final String name;
  final PortClass portClass;
  final Map<String, double> buyPrices;
  final Map<String, double> sellPrices;
  final int defenseLevel;
  final double portCredits;
  final double desiredCredits;
  final String? owner;

  const PortInfo({
    required this.name,
    required this.portClass,
    required this.buyPrices,
    required this.sellPrices,
    this.defenseLevel = 0,
    this.portCredits = 0,
    this.desiredCredits = 0,
    this.owner,
  });

  double get cashRatio {
    if (desiredCredits <= 0) return 1.0;
    return (portCredits / desiredCredits).clamp(0.1, 3.0);
  }

  double get priceMultiplier => 0.5 + 0.5 * cashRatio;

  double getEffectiveSellPrice(String commodity) =>
      (sellPrices[commodity] ?? 0) * priceMultiplier;

  double getEffectiveBuyPrice(String commodity) =>
      (buyPrices[commodity] ?? 0) * priceMultiplier;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'portClass': portClass.name,
      'buyPrices': buyPrices,
      'sellPrices': sellPrices,
      'defenseLevel': defenseLevel,
      'portCredits': portCredits,
      'desiredCredits': desiredCredits,
      'owner': owner,
    };
  }

  factory PortInfo.fromJson(Map<String, dynamic> json) {
    return PortInfo(
      name: json['name'] as String? ?? 'Unknown Port',
      portClass: PortClass.values.firstWhere(
        (e) => e.name == json['portClass'],
        orElse: () => PortClass.free,
      ),
      buyPrices: Map<String, double>.from(
        (json['buyPrices'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ) ??
            {},
      ),
      sellPrices: Map<String, double>.from(
        (json['sellPrices'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ) ??
            {},
      ),
      defenseLevel: json['defenseLevel'] as int? ?? 0,
      portCredits: (json['portCredits'] as num?)?.toDouble() ?? 0.0,
      desiredCredits: (json['desiredCredits'] as num?)?.toDouble() ?? 0.0,
      owner: json['owner'] as String?,
    );
  }
}

class HazardInfo {
  final bool navHaz;
  final String? anomaly;

  const HazardInfo({this.navHaz = false, this.anomaly});

  Map<String, dynamic> toJson() {
    return {
      'navHaz': navHaz,
      'anomaly': anomaly,
    };
  }

  factory HazardInfo.fromJson(Map<String, dynamic> json) {
    return HazardInfo(
      navHaz: json['navHaz'] as bool? ?? false,
      anomaly: json['anomaly'] as String?,
    );
  }
}

class NpcMemory {
  final Set<int> visitedSectors;
  final Map<int, PortInfo> discoveredPorts;
  final Map<int, HazardInfo> knownHazards;
  final Set<String> knownThreatIds;
  final Map<String, int> factionStandings;
  final DateTime? lastTradeTime;
  final DateTime? lastBankTime;

  const NpcMemory({
    this.visitedSectors = const {},
    this.discoveredPorts = const {},
    this.knownHazards = const {},
    this.knownThreatIds = const {},
    this.factionStandings = const {},
    this.lastTradeTime,
    this.lastBankTime,
  });

  factory NpcMemory.empty() => const NpcMemory();

  NpcMemory copyWith({
    Set<int>? visitedSectors,
    Map<int, PortInfo>? discoveredPorts,
    Map<int, HazardInfo>? knownHazards,
    Set<String>? knownThreatIds,
    Map<String, int>? factionStandings,
    DateTime? lastTradeTime,
    DateTime? lastBankTime,
  }) {
    return NpcMemory(
      visitedSectors: visitedSectors ?? this.visitedSectors,
      discoveredPorts: discoveredPorts ?? this.discoveredPorts,
      knownHazards: knownHazards ?? this.knownHazards,
      knownThreatIds: knownThreatIds ?? this.knownThreatIds,
      factionStandings: factionStandings ?? this.factionStandings,
      lastTradeTime: lastTradeTime ?? this.lastTradeTime,
      lastBankTime: lastBankTime ?? this.lastBankTime,
    );
  }

  NpcMemory withVisitedSector(int sectorId) {
    final updated = Set<int>.from(visitedSectors);
    updated.add(sectorId);
    return copyWith(visitedSectors: updated);
  }

  NpcMemory withDiscoveredPort(int sectorId, PortInfo port) {
    final updated = Map<int, PortInfo>.from(discoveredPorts);
    updated[sectorId] = port;
    return copyWith(discoveredPorts: updated);
  }

  NpcMemory withKnownHazard(int sectorId, HazardInfo hazard) {
    final updated = Map<int, HazardInfo>.from(knownHazards);
    updated[sectorId] = hazard;
    return copyWith(knownHazards: updated);
  }

  NpcMemory withThreat(String threatId) {
    final updated = Set<String>.from(knownThreatIds);
    updated.add(threatId);
    return copyWith(knownThreatIds: updated);
  }

  NpcMemory removeThreat(String threatId) {
    final updated = Set<String>.from(knownThreatIds);
    updated.remove(threatId);
    return copyWith(knownThreatIds: updated);
  }

  NpcMemory withFactionStanding(String faction, int standing) {
    final updated = Map<String, int>.from(factionStandings);
    updated[faction] = standing;
    return copyWith(factionStandings: updated);
  }

  Map<String, dynamic> toJson() {
    return {
      'visitedSectors': visitedSectors.toList(),
      'discoveredPorts': discoveredPorts.map(
        (k, v) => MapEntry(k.toString(), v.toJson()),
      ),
      'knownHazards': knownHazards.map(
        (k, v) => MapEntry(k.toString(), v.toJson()),
      ),
      'knownThreatIds': knownThreatIds.toList(),
      'factionStandings': factionStandings,
      'lastTradeTime': lastTradeTime?.toIso8601String(),
      'lastBankTime': lastBankTime?.toIso8601String(),
    };
  }

  factory NpcMemory.fromJson(Map<String, dynamic> json) {
    return NpcMemory(
      visitedSectors: (json['visitedSectors'] as List?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          const {},
      discoveredPorts: (json['discoveredPorts'] as Map?)?.map(
            (k, v) => MapEntry(
              int.parse(k as String),
              PortInfo.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          const {},
      knownHazards: (json['knownHazards'] as Map?)?.map(
            (k, v) => MapEntry(
              int.parse(k as String),
              HazardInfo.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          const {},
      knownThreatIds:
          (json['knownThreatIds'] as List?)?.map((e) => e as String).toSet() ??
              const {},
      factionStandings: (json['factionStandings'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          const {},
      lastTradeTime: json['lastTradeTime'] != null
          ? DateTime.parse(json['lastTradeTime'] as String)
          : null,
      lastBankTime: json['lastBankTime'] != null
          ? DateTime.parse(json['lastBankTime'] as String)
          : null,
    );
  }
}
