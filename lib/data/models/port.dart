import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/services/game_clock.dart';
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

  /// Stable owner identity (NPC id or player id). Names collide across
  /// seeded generators, so all ownership matching keys off this first
  /// and falls back to the display name only for legacy saves.
  final String? ownerId;

  /// The faction affiliation of the port owner (null if unowned or federal).
  final FactionClass? ownerFaction;

  /// The credit level the port "wants" to maintain — used as the baseline
  /// for dynamic pricing. Set during universe generation to match the
  /// port's initial credits (which cover its demand + 20-50% buffer).
  /// When [portCredits] deviates from [desiredCredits], prices adjust to
  /// self-correct (discounts when low, premiums when high).
  final double desiredCredits;

  /// Sub-unit **numerator** carried between ticks, per commodity.
  ///
  /// A full store refills over [PlanetClock.ticksPerDay] ticks, so one tick is
  /// `max / 2880` units — and for a 1,000-unit commodity that is 0.347 of a
  /// unit, which truncates to nothing. Regenerating per tick without a carry
  /// loses ~38% of a small port's stock a day and it would effectively never
  /// restock.
  ///
  /// Held as an integer count of `1 / ticksPerDay` of a unit rather than a
  /// `double` fraction, because a `double` carry accumulated over 2,880 ticks
  /// landed a 50,000-unit port on 49,999. That shortfall is permanent once the
  /// port clamps at its cap, so it is drift rather than a rounding curiosity.
  /// Integers make the computation exact at any horizon.
  ///
  /// Persisted, because a port that reloaded its carry from zero every time the
  /// game was opened would lose a unit per commodity per *load* — a
  /// save-scumming hole rather than a rounding artefact.
  final Map<String, int> regenRemainder;

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

  /// Per-commodity random-walk drift factors (B2). Random walk ±3% per game
  /// tick with mean reversion toward 1.0, clamped to [0.7, 1.4]. Multiplied
  /// into effective prices so quiet ports still move. Owner overrides win.
  final Map<String, double> priceDrift;

  /// Homeworld premium on goods this port buys (B2 regionals): set at
  /// universe generation from BFS distance to faction homeworlds
  /// (1.30/1.20/1.10 at 0/1/2 hops for the faction's preferred good).
  /// Absent keys read 1.0.
  final Map<String, double> regionalBuyBonus;

  /// Anomaly market modifier (B2 regionals, all goods, buy side).
  /// Boom 1.10 / bust 0.90 in or adjacent to an anomaly sector, else 1.0.
  /// Whole-economy effect by design (unlike per-good homeworld premiums).
  /// Overlapping anomaly fields compose multiplicatively at generation.
  final double anomalyBuyBonus;

  /// Timestamp until which a successful sabotage has weakened this port's
  /// combat defenses. Null means no active sabotage.
  /// Game tick at which the sabotage expires.
  ///
  /// **Ticks, not milliseconds** — see `GameClock` and the note on
  /// `Player.portHackBannedUntilTick`. A 30-minute debuff that expires while
  /// the game is closed is a debuff with no cost to the player.
  final int? securityCompromisedUntilTick;

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
    this.ownerId,
    this.ownerFaction,
    this.regenRemainder = const {},
    this.storageLevel = 0,
    this.accumulatedRevenue = 0.0,
    this.ownerTaxRate = 0.05,
    this.pricingOverride,
    this.priceDrift = const {},
    this.regionalBuyBonus = const {},
    this.anomalyBuyBonus = 1.0,
    this.currentShields = 0,
    this.isUnderAttack = false,
    this.isDestroyed = false,
    this.attackerId,
    this.attackMode,
    this.securityCompromisedUntilTick,
  });

  bool buys(String commodity) => buyPrices.containsKey(commodity);
  bool sells(String commodity) => sellPrices.containsKey(commodity);

  bool get isOwned => owner != null && owner!.isNotEmpty;

  /// Ownership match for an NPC id + display name pair. Keys off [ownerId]
  /// when present; pre-ownerId saves fall back to the display name.
  bool isOwnedById(String id, String name) {
    if (!isOwned) return false;
    if (ownerId != null) return ownerId == id;
    return owner == name;
  }

  bool get isHardwareEmporium => portClass == PortClass.hardwareEmporium;

  /// True while a sabotage is in effect.
  ///
  /// Compared against `GameClock`, so it expires after 180 ticks of **play**
  /// rather than 30 minutes of the player's evening.
  bool get isSecurityCompromised =>
      GameClock.isActive(securityCompromisedUntilTick);

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

  /// Whether the port is in a safe zone. Boundary mirrors
  /// [GameSettings.fedSpaceEnd] (synced by the shell); defaults to 10.
  /// Safe zones cannot be attacked by players or NPCs.
  static int safeZoneEnd = 10;
  static bool isInSafeZone(int sectorId) => sectorId <= safeZoneEnd;

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

  /// Get the effective price multiplier for a commodity, considering cash-
  /// driven pricing and any owner pricing override (which wins outright).
  double getEffectivePriceMultiplier(String? commodity) {
    if (commodity != null && pricingOverride?.containsKey(commodity) == true) {
      return pricingOverride![commodity]!;
    }
    return priceMultiplier;
  }

  /// Scarcity premium on goods the port sells: full shelves read 0.75x
  /// (glut discount), bare shelves 1.25x. Neutral 1.0x at half stock.
  /// Returns 1.0 when the port carries no stock line for [commodity].
  double supplyPriceMultiplier(String commodity) {
    final max = effectiveMaxSupply(commodity);
    if (max <= 0) return 1.0;
    final ratio = (supply[commodity] ?? 0) / max;
    return (1.25 - 0.5 * ratio.clamp(0.0, 1.0));
  }

  /// Demand premium on goods the port buys: desperate (full demand book)
  /// reads 1.25x, satisfied 0.75x. Neutral 1.0x at half book.
  /// Returns 1.0 when the port has no demand line for [commodity].
  double demandPriceMultiplier(String commodity) {
    final max = effectiveMaxDemand(commodity);
    if (max <= 0) return 1.0;
    final ratio = (demand[commodity] ?? 0) / max;
    return (0.75 + 0.5 * ratio.clamp(0.0, 1.0));
  }

  /// Current drift factor for [commodity] (1.0 when never drifted).
  double driftFor(String commodity) => priceDrift[commodity] ?? 1.0;

  /// One tick of random-walk drift for every traded commodity: ±3% uniform
  /// step plus 15% mean reversion toward 1.0, clamped to [0.7, 1.4].
  /// Returns an updated Port (this unchanged).
  Port applyDrift(math.Random rng) {
    final traded = <String>{...buyPrices.keys, ...sellPrices.keys};
    if (traded.isEmpty) return this;
    final drift = Map<String, double>.from(priceDrift);
    for (final commodity in traded) {
      final current = drift[commodity] ?? 1.0;
      final stepped =
          current + (1.0 - current) * 0.15 + (rng.nextDouble() * 0.06 - 0.03);
      drift[commodity] = stepped.clamp(0.7, 1.4);
    }
    return copyWith(priceDrift: drift);
  }

  double getEffectiveSellPrice(String commodity) =>
      getEffectiveSellPriceFor(commodity);

  double getEffectiveBuyPrice(String commodity) =>
      getEffectiveBuyPriceFor(commodity);

  /// Standing at or below which a port refuses service (B3): no refuel,
  /// no emporium trade, hostile banking. Unowned ports serve everyone
  /// (check ownerFaction before calling).
  static const int hostileServiceThreshold = -50;

  /// True when [standing] gets this port's doors slammed shut.
  bool deniesServiceTo(int standing) => standing <= hostileServiceThreshold;

  /// Buy-side price with faction standing applied (B3): +100 standing →
  /// 20% cheaper, −100 → 20% markup. Clamped to [0.8, 1.25].
  /// This is the price a buyer PAYS the port.
  static double standingBuyMultiplier(int standing) =>
      (1 - standing * 0.002).clamp(0.8, 1.25);

  /// Sell-side price with faction standing applied (B3): +100 standing →
  /// 20% richer payout, −100 → 20% docked. Clamped to [0.8, 1.25].
  /// This is what the port PAYS the seller.
  static double standingSellMultiplier(int standing) =>
      (1 + standing * 0.002).clamp(0.8, 1.25);

  /// Hard ceiling/floor on the composed effective-price multiplier (B2).
  /// Six multiplicative layers can otherwise stack to ~6.25× or crash to
  /// ~0.23× — far outside arbitrage bounds. Individual layers keep their
  /// ranges; the product clamps here.
  static const double minEffectiveMultiplier = 0.25;
  static const double maxEffectiveMultiplier = 4.0;

  double getEffectiveSellPriceFor(String commodity, {int standing = 0}) {
    final base = getSellPrice(commodity);
    if (base <= 0) return 0;
    if (pricingOverride?.containsKey(commodity) == true) {
      return base * getEffectivePriceMultiplier(commodity);
    }
    final mult = (getEffectivePriceMultiplier(commodity) *
            supplyPriceMultiplier(commodity) *
            driftFor(commodity) *
            standingBuyMultiplier(standing))
        .clamp(minEffectiveMultiplier, maxEffectiveMultiplier);
    return base * mult;
  }

  double getEffectiveBuyPriceFor(String commodity, {int standing = 0}) {
    final base = getBuyPrice(commodity);
    if (base <= 0) return 0;
    if (pricingOverride?.containsKey(commodity) == true) {
      return base * getEffectivePriceMultiplier(commodity);
    }
    final mult = (getEffectivePriceMultiplier(commodity) *
            demandPriceMultiplier(commodity) *
            driftFor(commodity) *
            (regionalBuyBonus[commodity] ?? 1.0) *
            anomalyBuyBonus *
            standingSellMultiplier(standing))
        .clamp(minEffectiveMultiplier, maxEffectiveMultiplier);
    return base * mult;
  }

  /// Advance supply/demand by [ticks] game ticks, toward [effectiveMaxSupply]
  /// and [effectiveMaxDemand].
  ///
  /// A store refills over [PlanetClock.ticksPerDay] ticks, driven by the
  /// **tick** and by nothing else. There is no wall-clock input anywhere in this
  /// path, deliberately: the game can be shut off, so a port that sold out
  /// while the app was closed is still sold out when it reopens. Refilling on
  /// `DateTime.now()` would quietly hand the player a full market every time
  /// they closed the game, which is the same shape of bug as a colony that
  /// produced while nobody was playing.
  ///
  /// The per-commodity fraction in [regenRemainder] is what makes a per-tick
  /// rate exact; see that field for why truncating each tick is not good enough.
  ///
  /// Returns the identical instance when no stored integer moved, so the tick's
  /// `regenerated != sector.port` dirty-check does not flag an unchanged sector
  /// for a save.
  Port regenTick({int ticks = 1}) {
    if (ticks <= 0) return this;

    Map<String, int> newSupply = {...supply};
    Map<String, int> newDemand = {...demand};
    Map<String, int> newRemainder = {...regenRemainder};
    bool changed = false;

    /// Fills [bucket] by [ticks] of [maxFor]'s cap, carrying the sub-unit
    /// remainder.
    ///
    /// Shared by supply and demand so the two cannot drift — they were two
    /// near-identical loops, and a fix to one was not automatically a fix to the
    /// other.
    void fill(Map<String, int> bucket, int Function(String) maxFor) {
      for (final commodity in bucket.keys) {
        final currentQty = bucket[commodity] ?? 0;
        final effectiveMax = maxFor(commodity);
        // Already full: stop accruing entirely rather than banking the
        // remainder, so a port sitting at its cap all day does not bank a
        // surprise restock for the first tick after it is drained.
        if (currentQty >= effectiveMax) continue;
        // Exact integer arithmetic — see [regenRemainder].
        final numerator = ticks * effectiveMax + (newRemainder[commodity] ?? 0);
        final whole = numerator ~/ PlanetClock.ticksPerDay;
        final carry = numerator % PlanetClock.ticksPerDay;
        if (whole <= 0) {
          newRemainder[commodity] = carry;
          continue;
        }
        final next = (currentQty + whole).clamp(0, effectiveMax);
        newRemainder[commodity] = carry;
        if (next == currentQty) continue;
        bucket[commodity] = next;
        changed = true;
      }
    }

    fill(newSupply, effectiveMaxSupply);
    fill(newDemand, effectiveMaxDemand);

    if (!changed) {
      // No stored integer moved, but the carry still advanced. Return a copy in
      // that case, or a port sitting just under a whole unit would hold the same
      // remainder forever and never cross it.
      var remainderMoved = false;
      for (final e in newRemainder.entries) {
        if ((regenRemainder[e.key] ?? 0) != e.value) {
          remainderMoved = true;
          break;
        }
      }
      if (!remainderMoved) return this;
      return copyWith(regenRemainder: newRemainder);
    }
    return copyWith(
      supply: newSupply,
      demand: newDemand,
      regenRemainder: newRemainder,
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
    String? ownerId,
    FactionClass? ownerFaction,
    Map<String, int>? regenRemainder,
    bool clearOwnerFaction = false,
    int? storageLevel,
    double? accumulatedRevenue,
    double? ownerTaxRate,
    Map<String, double>? pricingOverride,
    bool clearOwner = false,
    bool clearPricingOverride = false,
    Map<String, double>? priceDrift,
    Map<String, double>? regionalBuyBonus,
    double? anomalyBuyBonus,
    int? currentShields,
    bool? isUnderAttack,
    bool? isDestroyed,
    String? attackerId,
    String? attackMode,
    int? securityCompromisedUntilTick,
    bool clearSecurityCompromised = false,
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
      ownerId: clearOwner ? null : (ownerId ?? this.ownerId),
      ownerFaction:
          clearOwnerFaction ? null : (ownerFaction ?? this.ownerFaction),
      regenRemainder: regenRemainder ?? this.regenRemainder,
      storageLevel: storageLevel ?? this.storageLevel,
      accumulatedRevenue: accumulatedRevenue ?? this.accumulatedRevenue,
      ownerTaxRate: ownerTaxRate ?? this.ownerTaxRate,
      pricingOverride: clearPricingOverride
          ? null
          : (pricingOverride ?? this.pricingOverride),
      priceDrift: priceDrift ?? this.priceDrift,
      regionalBuyBonus: regionalBuyBonus ?? this.regionalBuyBonus,
      anomalyBuyBonus: anomalyBuyBonus ?? this.anomalyBuyBonus,
      currentShields: currentShields ?? this.currentShields,
      isUnderAttack: isUnderAttack ?? this.isUnderAttack,
      isDestroyed: isDestroyed ?? this.isDestroyed,
      attackerId: attackerId ?? this.attackerId,
      attackMode: attackMode ?? this.attackMode,
      securityCompromisedUntilTick: clearSecurityCompromised
          ? null
          : (securityCompromisedUntilTick ?? this.securityCompromisedUntilTick),
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
      'regenRemainder': regenRemainder,
      'owner': owner,
      'ownerId': ownerId,
      'ownerFaction': ownerFaction?.name,
      'storageLevel': storageLevel,
      'accumulatedRevenue': accumulatedRevenue,
      'ownerTaxRate': ownerTaxRate,
      'pricingOverride': pricingOverride,
      'priceDrift': priceDrift,
      'regionalBuyBonus': regionalBuyBonus,
      'anomalyBuyBonus': anomalyBuyBonus,
      'currentShields': currentShields,
      'isUnderAttack': isUnderAttack,
      'isDestroyed': isDestroyed,
      'attackerId': attackerId,
      'attackMode': attackMode,
      'securityCompromisedUntilTick': securityCompromisedUntilTick,
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
      // A legacy save carries the old wall-clock key. It is read as nothing
      // on purpose: the whole point of the change is that no port refills on
      // elapsed real time, so there is no correct way to convert those
      // milliseconds into ticks. A port resumes from whatever quantity it had
      // and carries on from there — which is the behaviour that was asked
      // for, not a migration gap.
      regenRemainder: (json['regenRemainder'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const {},
      owner: json['owner'] as String?,
      ownerId: json['ownerId'] as String?,
      ownerFaction: _parseFactionClass(json['ownerFaction'] as String?),
      storageLevel: (json['storageLevel'] as int?) ?? 0,
      accumulatedRevenue:
          (json['accumulatedRevenue'] as num?)?.toDouble() ?? 0.0,
      ownerTaxRate: (json['ownerTaxRate'] as num?)?.toDouble() ?? 0.05,
      pricingOverride: (json['pricingOverride'] as Map<String, dynamic>?)
          ?.cast<String, double>(),
      priceDrift: (json['priceDrift'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
      regionalBuyBonus: (json['regionalBuyBonus'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
      anomalyBuyBonus: (json['anomalyBuyBonus'] as num?)?.toDouble() ?? 1.0,
      currentShields: (json['currentShields'] as int?) ?? 0,
      isUnderAttack: (json['isUnderAttack'] as bool?) ?? false,
      isDestroyed: (json['isDestroyed'] as bool?) ?? false,
      attackerId: json['attackerId'] as String?,
      attackMode: json['attackMode'] as String?,
      // A pre-tick save holds epoch milliseconds. Dropped, as for the hack
      // ban: not comparable, and clearing a debuff on migration costs the
      // player nothing they earned.
      securityCompromisedUntilTick:
          (json['securityCompromisedUntilTick'] as num?)?.toInt(),
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
