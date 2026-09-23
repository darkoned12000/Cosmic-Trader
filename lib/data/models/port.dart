import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/port_defense_config.dart';

/// Represents a space port within a sector.
class Port {
  final String name;
  final PortClass portClass;
  final String? portType;
  final Map<String, double> buyPrices;
  final Map<String, double> sellPrices;
  final Map<String, int> supply;
  final Map<String, int> demand;
  final Map<String, int> maxSupply;
  final Map<String, int> maxDemand;
  final int defenseLevel;
  final double portCredits;
  final String? owner;

  /// The faction affiliation of the port owner (null if unowned or federal).
  final FactionClass? ownerFaction;

  /// The credit level the port "wants" to maintain — used as the baseline
  /// for dynamic pricing. Set during universe generation to match the
  /// port's initial credits (which cover its demand + 20-50% buffer).
  /// When [portCredits] deviates from [desiredCredits], prices adjust to
  /// self-correct (discounts when low, premiums when high).
  final double desiredCredits;

  /// Milliseconds since epoch when supply/demand were last touched
  /// (either modified by trade or regenerated). Used to calculate
  /// timed regeneration back to maxSupply/maxDemand.
  final int lastRegenTime;

  // ── Ownership & Upgrades ──────────────────────────────────────

  /// Number of storage upgrades purchased.
  /// Each level multiplies effective maxSupply/maxDemand by 1.5×.
  final int storageLevel;

  /// Credits earned from owner trade fees, awaiting collection.
  final double accumulatedRevenue;

  /// Port owner's cut of each transaction (0.0 – 0.15, default 0.05).
  final double ownerTaxRate;

  /// Per-commodity price multiplier override (null = use cash-based pricing).
  /// Keys: commodity name, values: multiplier (e.g. 0.8 = 20% discount).
  final Map<String, double>? pricingOverride;

  // ── Port Combat State ─────────────────────────────────────────

  /// Current port shields (initialized to max from defense config).
  final int currentShields;

  /// Whether a combat encounter is currently active.
  final bool isUnderAttack;

  /// Whether the port has been destroyed.
  final bool isDestroyed;

  /// ID of the current attacker (player or NPC).
  final String? attackerId;

  /// Mode of the current attack: "capture" or "destroy".
  final String? attackMode;

  const Port({
    required this.name,
    required this.portClass,
    this.portType,
    required this.buyPrices,
    required this.sellPrices,
    this.supply = const {},
    this.demand = const {},
    this.maxSupply = const {},
    this.maxDemand = const {},
    this.defenseLevel = 0,
    this.portCredits = 0.0,
    this.desiredCredits = 0.0,
    this.owner,
    this.ownerFaction,
    this.lastRegenTime = 0,
    this.storageLevel = 0,
    this.accumulatedRevenue = 0.0,
    this.ownerTaxRate = 0.05,
    this.pricingOverride,
    this.currentShields = 0,
    this.isUnderAttack = false,
    this.isDestroyed = false,
    this.attackerId,
    this.attackMode,
  });

  bool buys(String commodity) => buyPrices.containsKey(commodity);
  bool sells(String commodity) => sellPrices.containsKey(commodity);

  bool get isOwned => owner != null && owner!.isNotEmpty;

  bool get isHardwareEmporium => portClass == PortClass.hardwareEmporium;

  // ── Port Combat Derived Getters ───────────────────────────────

  /// Max shields from defense config based on defense level.
  int get maxShields =>
      PortDefenseConfig.defenseStats(defenseLevel).shieldCapacity;

  /// Capture threshold (5% of max shields).
  int get captureThreshold => (maxShields * 0.05).round();

  /// Can port surrender? (shields <= 5% and under attack)
  bool get canSurrender => currentShields <= captureThreshold && isUnderAttack;

  /// Can port still defend? (shields > 5% and not destroyed)
  bool get canDefend => currentShields > captureThreshold && !isDestroyed;

  /// Whether the port is in a safe zone (sectors 1-10).
  /// Safe zones cannot be attacked by players or NPCs.
  static bool isInSafeZone(int sectorId) => sectorId <= 10;

  double getBuyPrice(String commodity) => buyPrices[commodity] ?? 0;
  double getSellPrice(String commodity) => sellPrices[commodity] ?? 0;

  int getSupply(String commodity) => supply[commodity] ?? 0;
  int getDemand(String commodity) => demand[commodity] ?? 0;

  int getMaxSupply(String commodity) => maxSupply[commodity] ?? 0;
  int getMaxDemand(String commodity) => maxDemand[commodity] ?? 0;

  /// Ratio of current credits to desired credits, clamped to [0.1, 3.0].
  /// Used to drive dynamic pricing: < 1.0 = cash-strapped, > 1.0 = flush.
  double get cashRatio {
    if (desiredCredits <= 0) return 1.0;
    return (portCredits / desiredCredits).clamp(0.1, 3.0);
  }

  /// Price multiplier driven by [cashRatio]:
  ///   multiplier = 0.5 + 0.5 * cashRatio
  /// Range: 0.55x (desperate) → 1.0x (healthy) → 2.0x (wealthy).
  double get priceMultiplier => 0.5 + 0.5 * cashRatio;

  /// Defense value in credits based on defense level.
  /// Level 0 = 0, Level 1 = 250000, Level 2 = 500000,
  /// Level 3 = 750000, Level 4 = 1000000.
  double get defenseValue => defenseLevel * 250000.0;

  /// Total net worth: resources on hand + port credits + defense value.
  double get netWorth {
    double resourceValue = 0;
    for (final entry in supply.entries) {
      final price = getSellPrice(entry.key);
      if (price > 0) {
        resourceValue += entry.value * price;
      }
    }
    return resourceValue + portCredits + defenseValue;
  }

  // ── Upgrade Helpers ───────────────────────────────────────────

  /// Effective maxSupply after storage level multiplier (1.5× per level).
  int effectiveMaxSupply(String commodity) {
    final base = maxSupply[commodity] ?? 0;
    return (base * math.pow(1.5, storageLevel)).round();
  }

  /// Effective maxDemand after storage level multiplier (1.5× per level).
  int effectiveMaxDemand(String commodity) {
    final base = maxDemand[commodity] ?? 0;
    return (base * math.pow(1.5, storageLevel)).round();
  }

  /// Cost in credits to upgrade defense from [defenseLevel] to the next level.
  double get defenseUpgradeCost => (defenseLevel + 1) * 250000.0;

  /// Cost in credits to upgrade storage from [storageLevel] to the next level.
  double get storageUpgradeCost {
    if (storageLevel >= 10) return double.infinity;
    return 100000.0 * math.pow(2, storageLevel);
  }

  /// Whether the next defense level can be purchased (max 4).
  bool get canUpgradeDefense => defenseLevel < 4;

  /// Whether the next storage level can be purchased (max 10).
  bool get canUpgradeStorage => storageLevel < 10;

  /// Get the effective price multiplier for a commodity, considering both
  /// cash-driven pricing and any owner pricing override.
  double getEffectivePriceMultiplier(String? commodity) {
    if (commodity != null && pricingOverride?.containsKey(commodity) == true) {
      return pricingOverride![commodity]!;
    }
    return priceMultiplier;
  }

  double getEffectiveSellPrice(String commodity) =>
      getSellPrice(commodity) * getEffectivePriceMultiplier(commodity);

  double getEffectiveBuyPrice(String commodity) =>
      getBuyPrice(commodity) * getEffectivePriceMultiplier(commodity);

  /// Regenerate supply/demand toward maxSupply/maxDemand over a 24-hour
  /// cycle. Each call restores a fraction proportional to the time elapsed
  /// since [lastRegenTime] (up to 24h = full restoration).
  ///
  /// [now] defaults to [DateTime.now().millisecondsSinceEpoch].
  Port regen({int? now}) {
    final nowMs = now ?? DateTime.now().millisecondsSinceEpoch;
    if (lastRegenTime <= 0) return copyWith(lastRegenTime: nowMs);
    final elapsedMs = nowMs - lastRegenTime;
    if (elapsedMs <= 0) return this;

    const regenPeriodMs = 24 * 60 * 60 * 1000; // 24 hours
    final fraction = (elapsedMs / regenPeriodMs).clamp(0.0, 1.0);

    Map<String, int> newSupply = {...supply};
    Map<String, int> newDemand = {...demand};
    bool changed = false;

    for (final commodity in maxSupply.keys) {
      final currentQty = newSupply[commodity] ?? 0;
      final effectiveMax = effectiveMaxSupply(commodity);
      if (currentQty < effectiveMax) {
        final added = (effectiveMax * fraction).round();
        newSupply[commodity] = (currentQty + added).clamp(0, effectiveMax);
        changed = true;
      }
    }
    for (final commodity in maxDemand.keys) {
      final currentQty = newDemand[commodity] ?? 0;
      final effectiveMax = effectiveMaxDemand(commodity);
      if (currentQty < effectiveMax) {
        final added = (effectiveMax * fraction).round();
        newDemand[commodity] = (currentQty + added).clamp(0, effectiveMax);
        changed = true;
      }
    }

    if (!changed && fraction < 1.0) return this;

    return copyWith(
      supply: newSupply,
      demand: newDemand,
      lastRegenTime: nowMs,
    );
  }

  Port copyWith({
    String? name,
    PortClass? portClass,
    String? portType,
    Map<String, double>? buyPrices,
    Map<String, double>? sellPrices,
    Map<String, int>? supply,
    Map<String, int>? demand,
    Map<String, int>? maxSupply,
    Map<String, int>? maxDemand,
    int? defenseLevel,
    double? portCredits,
    double? desiredCredits,
    String? owner,
    FactionClass? ownerFaction,
    int? lastRegenTime,
    bool clearOwnerFaction = false,
    int? storageLevel,
    double? accumulatedRevenue,
    double? ownerTaxRate,
    Map<String, double>? pricingOverride,
    bool clearOwner = false,
    bool clearPricingOverride = false,
    int? currentShields,
    bool? isUnderAttack,
    bool? isDestroyed,
    String? attackerId,
    String? attackMode,
  }) {
    return Port(
      name: name ?? this.name,
      portClass: portClass ?? this.portClass,
      portType: portType ?? this.portType,
      buyPrices: buyPrices ?? this.buyPrices,
      sellPrices: sellPrices ?? this.sellPrices,
      supply: supply ?? this.supply,
      demand: demand ?? this.demand,
      maxSupply: maxSupply ?? this.maxSupply,
      maxDemand: maxDemand ?? this.maxDemand,
      defenseLevel: defenseLevel ?? this.defenseLevel,
      portCredits: portCredits ?? this.portCredits,
      desiredCredits: desiredCredits ?? this.desiredCredits,
      owner: clearOwner ? null : (owner ?? this.owner),
      ownerFaction:
          clearOwnerFaction ? null : (ownerFaction ?? this.ownerFaction),
      lastRegenTime: lastRegenTime ?? this.lastRegenTime,
      storageLevel: storageLevel ?? this.storageLevel,
      accumulatedRevenue: accumulatedRevenue ?? this.accumulatedRevenue,
      ownerTaxRate: ownerTaxRate ?? this.ownerTaxRate,
      pricingOverride: clearPricingOverride
          ? null
          : (pricingOverride ?? this.pricingOverride),
      currentShields: currentShields ?? this.currentShields,
      isUnderAttack: isUnderAttack ?? this.isUnderAttack,
      isDestroyed: isDestroyed ?? this.isDestroyed,
      attackerId: attackerId ?? this.attackerId,
      attackMode: attackMode ?? this.attackMode,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'portClass': portClass.name,
      'portType': portType,
      'buyPrices': buyPrices,
      'sellPrices': sellPrices,
      'supply': supply,
      'demand': demand,
      'maxSupply': maxSupply,
      'maxDemand': maxDemand,
      'defenseLevel': defenseLevel,
      'portCredits': portCredits,
      'desiredCredits': desiredCredits,
      'lastRegenTime': lastRegenTime,
      'owner': owner,
      'ownerFaction': ownerFaction?.name,
      'storageLevel': storageLevel,
      'accumulatedRevenue': accumulatedRevenue,
      'ownerTaxRate': ownerTaxRate,
      'pricingOverride': pricingOverride,
      'currentShields': currentShields,
      'isUnderAttack': isUnderAttack,
      'isDestroyed': isDestroyed,
      'attackerId': attackerId,
      'attackMode': attackMode,
    };
  }

  factory Port.fromJson(Map<String, dynamic> json) {
    return Port(
      name: json['name'] as String? ?? 'Unknown Port',
      portClass: _parsePortClass(json['portClass'] as String?),
      portType: json['portType'] as String?,
      buyPrices: (json['buyPrices'] as Map?)?.cast<String, double>() ?? {},
      sellPrices: (json['sellPrices'] as Map?)?.cast<String, double>() ?? {},
      supply:
          (json['supply'] as Map<String, dynamic>?)?.cast<String, int>() ?? {},
      demand:
          (json['demand'] as Map<String, dynamic>?)?.cast<String, int>() ?? {},
      maxSupply:
          (json['maxSupply'] as Map<String, dynamic>?)?.cast<String, int>() ??
              (json['supply'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {},
      maxDemand:
          (json['maxDemand'] as Map<String, dynamic>?)?.cast<String, int>() ??
              (json['demand'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {},
      defenseLevel: (json['defenseLevel'] as int?) ?? 0,
      portCredits: (json['portCredits'] as num?)?.toDouble() ?? 0.0,
      desiredCredits: (json['desiredCredits'] as num?)?.toDouble() ??
          (json['portCredits'] as num?)?.toDouble() ??
          0.0,
      lastRegenTime: (json['lastRegenTime'] as int?) ?? 0,
      owner: json['owner'] as String?,
      ownerFaction: _parseFactionClass(json['ownerFaction'] as String?),
      storageLevel: (json['storageLevel'] as int?) ?? 0,
      accumulatedRevenue:
          (json['accumulatedRevenue'] as num?)?.toDouble() ?? 0.0,
      ownerTaxRate: (json['ownerTaxRate'] as num?)?.toDouble() ?? 0.05,
      pricingOverride: (json['pricingOverride'] as Map<String, dynamic>?)
          ?.cast<String, double>(),
      currentShields: (json['currentShields'] as int?) ?? 0,
      isUnderAttack: (json['isUnderAttack'] as bool?) ?? false,
      isDestroyed: (json['isDestroyed'] as bool?) ?? false,
      attackerId: json['attackerId'] as String?,
      attackMode: json['attackMode'] as String?,
    );
  }
}

/// Port classification determines port appearance and reputation.
enum PortClass {
  federal,
  free,
  independent,
  hardwareEmporium,
}

extension PortClassX on PortClass {
  bool get isHardwareEmporium => this == PortClass.hardwareEmporium;
}

PortClass _parsePortClass(String? name) {
  if (name == null) return PortClass.free;
  try {
    return PortClass.values.byName(name);
  } on ArgumentError {
    return PortClass.free;
  }
}

FactionClass? _parseFactionClass(String? name) {
  if (name == null) return null;
  try {
    return FactionClass.values.byName(name);
  } on ArgumentError {
    return null;
  }
}
