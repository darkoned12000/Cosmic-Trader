import 'package:cosmic_trader/data/models/faction.dart';

/// Decodes a persisted faction name, tolerating one that no longer exists.
///
/// Uses `byName` rather than `firstWhere` **deliberately**: `firstWhere` with no
/// match throws `StateError`, not `ArgumentError`, so an `on ArgumentError`
/// clause silently never fires and a save naming a since-removed faction takes
/// the whole planet decode — and therefore the whole sector file — down with
/// it. `byName` throws `ArgumentError`, which is what the `on` clause expects.
///
/// This is the same idiom as `port.dart`'s `_parseFactionClass`; keep the two
/// in step. `FactionStanding`, `NpcShip`, and `Player` use `orElse` instead,
/// which is also correct.
FactionClass? _parseFactionClass(String? name) {
  if (name == null) return null;
  try {
    return FactionClass.values.byName(name);
  } on ArgumentError {
    return null;
  }
}

class Planet {
  final String name;
  final String planetType;
  final String atmosphere;

  // Ownership
  FactionClass? owner;
  bool isHomeworld;
  FactionClass? homeworldOf;

  /// Cold-standby capital (C4b): produces only while no live primary
  /// homeworld of the same faction exists. Recapture of the primary
  /// idles the backup again — capitals move back, they don't duplicate.
  bool isBackupHomeworld;

  /// Planet-killer path (C4b): a destroyed world is permanently out of
  /// play — no colony, no production, no homeworld status. Set via
  /// [destroy]; combat triggers arrive with the invasion system.
  bool isDestroyed;

  // Colony
  int population;
  int colonistsMinerals;
  int colonistsOrganics;
  int colonistsIndustrial;

  /// Drones, not fighters: ships field drones throughout the game
  /// (`Player.drones`). The old `colonistsFighters` name survived the
  /// planet screen already being labelled "Drones", which made the model
  /// the odd one out.
  int colonistsDrones;
  double productionEfficiency;

  // Storage
  int storedMinerals;
  int storedOrganics;
  int storedIndustrial;
  int storedDrones;

  /// Output that has overflowed the working store and is waiting to be
  /// collected. **This is the "no waste" answer.**
  ///
  /// The first version of colony production discarded anything that did not fit
  /// the store, which made a busy colony actively harmful: a 5,400-population
  /// Lava world filled 5,000 minerals in 1.6 ticks and then threw away ~98% of
  /// everything it made from then on. Storage became a waste bin rather than a
  /// buffer.
  ///
  /// Now a full store pushes output into here instead, up to a much larger
  /// [pendingCap]. Nothing is destroyed and the colony keeps earning while you
  /// are elsewhere — the same shape as the classic system, where a world turns
  /// out its daily output continuously and you collect it in batches. Collecting
  /// for credits is a placeholder until planets can actually supply a port.
  int pendingMinerals;
  int pendingOrganics;
  int pendingIndustrial;
  int pendingDrones;

  // Level / Citadel (1-6)
  int level;

  /// Ticks left on the current build, or 0 when idle.
  ///
  /// Counted in **game ticks, not wall-clock time**, and that is the entire
  /// reason offline time costs nothing. The classic game this is drawn from was
  /// an online world where a 43-day build was fine because every other colony
  /// was decaying while you slept. This is single-player, so a wall-clock
  /// deadline would mean quitting for a week silently finishing every build and
  /// nothing else: the player would advance and the galaxy would stand still.
  /// Counting ticks means a build only progresses while the game is running,
  /// which keeps the player and the NPCs on the same clock.
  ///
  /// This is deliberately the same mechanism as the homeworld yards'
  /// [productionTimer] countdown.
  int constructionTicksRemaining;

  /// The level this build will produce when it finishes. 0 when idle.
  int constructionTarget;
  int requiredMinerals;
  int requiredOrganics;
  int requiredIndustrial;
  int requiredColonists;

  // Defense
  int defenseLevel;
  double shield;
  double maxShield;
  double hull;
  double maxHull;

  // NPC spawning (homeworld only)
  int productionTimer;
  int spawnInterval;

  // Visual
  String? imagePath;

  // Scanning
  bool scanned;

  Planet({
    required this.name,
    required this.planetType,
    this.atmosphere = 'Unknown',
    this.owner,
    this.isHomeworld = false,
    this.homeworldOf,
    this.population = 0,
    this.colonistsMinerals = 0,
    this.colonistsOrganics = 0,
    this.colonistsIndustrial = 0,
    this.colonistsDrones = 0,
    this.productionEfficiency = 1.0,
    this.storedMinerals = 0,
    this.storedOrganics = 0,
    this.storedIndustrial = 0,
    this.storedDrones = 0,
    this.pendingMinerals = 0,
    this.pendingOrganics = 0,
    this.pendingIndustrial = 0,
    this.pendingDrones = 0,
    this.level = 1,
    this.constructionTicksRemaining = 0,
    this.constructionTarget = 0,
    this.requiredMinerals = 500,
    this.requiredOrganics = 300,
    this.requiredIndustrial = 200,
    this.requiredColonists = 1000,
    this.defenseLevel = 0,
    this.shield = 0,
    this.maxShield = 0,
    this.hull = 1000,
    this.maxHull = 1000,
    this.productionTimer = 0,
    this.spawnInterval = 10,
    this.isBackupHomeworld = false,
    this.isDestroyed = false,
    this.imagePath,
    this.scanned = false,
  });

  /// Renders the world permanently uninhabitable (C4b planet-killer
  /// path): colony zeroed, homeworld status and ownership cleared,
  /// defenses gone. Regeneration tied to this world never resumes —
  /// backup homeworlds (if any) take over via the usual control rules.
  void destroy() {
    isDestroyed = true;
    isHomeworld = false;
    homeworldOf = null;
    isBackupHomeworld = false;
    owner = null;
    population = 0;
    colonistsMinerals = 0;
    colonistsOrganics = 0;
    colonistsIndustrial = 0;
    colonistsDrones = 0;
    storedMinerals = 0;
    storedOrganics = 0;
    storedIndustrial = 0;
    storedDrones = 0;
    defenseLevel = 0;
    shield = 0;
    maxShield = 0;
    hull = 0;
    maxHull = 0;
    // Review batch 2: stale timers on a corpse invite any future reader
    // that forgets the isDestroyed check to schedule ghosts.
    productionTimer = 0;
    spawnInterval = 0;
    // Same reasoning for a build: a corpse with a running construction timer
    // would quietly finish an upgrade the tick then granted to a dead world.
    constructionTicksRemaining = 0;
    constructionTarget = 0;
  }

  String get dominantCommodity {
    final mults = typeMultipliers[planetType];
    if (mults == null) return 'minerals';
    if (mults.minerals >= mults.organics &&
        mults.minerals >= mults.industrial) {
      return 'minerals';
    }
    if (mults.organics >= mults.minerals &&
        mults.organics >= mults.industrial) {
      return 'organics';
    }
    return 'industrial';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'planetType': planetType,
      'atmosphere': atmosphere,
      'owner': owner?.name,
      'isHomeworld': isHomeworld,
      'homeworldOf': homeworldOf?.name,
      'population': population,
      'colonistsMinerals': colonistsMinerals,
      'colonistsOrganics': colonistsOrganics,
      'colonistsIndustrial': colonistsIndustrial,
      'colonistsDrones': colonistsDrones,
      'productionEfficiency': productionEfficiency,
      'storedMinerals': storedMinerals,
      'storedOrganics': storedOrganics,
      'storedIndustrial': storedIndustrial,
      'storedDrones': storedDrones,
      'pendingMinerals': pendingMinerals,
      'pendingOrganics': pendingOrganics,
      'pendingIndustrial': pendingIndustrial,
      'pendingDrones': pendingDrones,
      'level': level,
      'constructionTicksRemaining': constructionTicksRemaining,
      'constructionTarget': constructionTarget,
      'requiredMinerals': requiredMinerals,
      'requiredOrganics': requiredOrganics,
      'requiredIndustrial': requiredIndustrial,
      'requiredColonists': requiredColonists,
      'defenseLevel': defenseLevel,
      'shield': shield,
      'maxShield': maxShield,
      'hull': hull,
      'maxHull': maxHull,
      'productionTimer': productionTimer,
      'spawnInterval': spawnInterval,
      'isBackupHomeworld': isBackupHomeworld,
      'isDestroyed': isDestroyed,
      'imagePath': imagePath,
      'scanned': scanned,
    };
  }

  factory Planet.fromJson(Map<String, dynamic> json) {
    return Planet(
      name: json['name'] as String? ?? 'Unknown Planet',
      planetType: json['planetType'] as String? ?? 'Terran',
      atmosphere: json['atmosphere'] as String? ?? 'Unknown',
      owner: _parseFactionClass(json['owner'] as String?),
      isHomeworld: json['isHomeworld'] as bool? ?? false,
      homeworldOf: _parseFactionClass(json['homeworldOf'] as String?),
      population: json['population'] as int? ?? 0,
      colonistsMinerals: json['colonistsMinerals'] as int? ?? 0,
      colonistsOrganics: json['colonistsOrganics'] as int? ?? 0,
      colonistsIndustrial: json['colonistsIndustrial'] as int? ?? 0,
      // Pre-rename migration: legacy 'colonistsFighters' seeds the drone
      // track, so existing saves keep their colony. Rewritten on next save.
      colonistsDrones:
          (json['colonistsDrones'] ?? json['colonistsFighters']) as int? ?? 0,
      productionEfficiency:
          (json['productionEfficiency'] as num?)?.toDouble() ?? 1.0,
      storedMinerals: json['storedMinerals'] as int? ?? 0,
      storedOrganics: json['storedOrganics'] as int? ?? 0,
      storedIndustrial: json['storedIndustrial'] as int? ?? 0,
      storedDrones:
          (json['storedDrones'] ?? json['storedFighters']) as int? ?? 0,
      pendingMinerals: json['pendingMinerals'] as int? ?? 0,
      pendingOrganics: json['pendingOrganics'] as int? ?? 0,
      pendingIndustrial: json['pendingIndustrial'] as int? ?? 0,
      pendingDrones: json['pendingDrones'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      constructionTicksRemaining:
          json['constructionTicksRemaining'] as int? ?? 0,
      constructionTarget: json['constructionTarget'] as int? ?? 0,
      requiredMinerals: json['requiredMinerals'] as int? ?? 500,
      requiredOrganics: json['requiredOrganics'] as int? ?? 300,
      requiredIndustrial: json['requiredIndustrial'] as int? ?? 200,
      // Matches the constructor (1000) and `levelUpCosts.first.requiredColonists`
      // (1000). This used to default to 100 here and 1000 in the constructor, so
      // the same missing key produced a different planet depending on how it was
      // built. Nothing reads the field today — all gating goes through the static
      // cost table — which is exactly why the drift went unnoticed.
      requiredColonists: json['requiredColonists'] as int? ?? 1000,
      defenseLevel: json['defenseLevel'] as int? ?? 0,
      shield: (json['shield'] as num?)?.toDouble() ?? 0,
      maxShield: (json['maxShield'] as num?)?.toDouble() ?? 0,
      hull: (json['hull'] as num?)?.toDouble() ?? 1000,
      maxHull: (json['maxHull'] as num?)?.toDouble() ?? 1000,
      productionTimer: json['productionTimer'] as int? ?? 0,
      spawnInterval: json['spawnInterval'] as int? ?? 10,
      isBackupHomeworld: json['isBackupHomeworld'] as bool? ?? false,
      isDestroyed: json['isDestroyed'] as bool? ?? false,
      imagePath: json['imagePath'] as String?,
      scanned: json['scanned'] as bool? ?? false,
    );
  }

  // ---------------------------------------------------------------------------
  // Colonist & level-up configuration
  // ---------------------------------------------------------------------------

  /// Maximum colonists by planet type (doubled from base values).
  static const Map<String, int> colonistMaxByType = {
    'Terran': 2000000,
    'Jungle': 1500000,
    'Ocean': 1000000,
    'Desert': 600000,
    'Ice': 400000,
    'Lava': 200000,
    'Moon': 200000,
    'Barren': 150000,
    'Gas Giant': 100000,
    'Toxic': 100000,
  };

  /// Resource & colonist gate for each level-up (index 0 = 1→2, …, 4 = 5→6).
  /// Colonists are a minimum requirement (not consumed); resources are consumed.
  ///
  /// **Re-derived.** The previous table was priced when colonists were a flat 20
  /// credits, which made a full 1→6 cost ~36.8M. Colonists are now priced by
  /// distance from the faction's homeworld at 15 x hops^1.5, so the same gates
  /// cost 28.7M at one hop, ~198M at the median four, and ~551M at eight. The
  /// last two steps were 94% of the total and read as a wall rather than a
  /// difficulty setting, and the resource half had stopped mattering — 3.65M of
  /// resources against 120M of colonists.
  ///
  /// The colonist requirements are cut so the arc is roughly 2, 12, 60 and 250
  /// times cheaper, landing a full 1→6 at ~4.9M / ~33M / ~92M by distance.
  /// Resources are kept in the same proportion to each other so the import
  /// decision still bites: a big colony genuinely needs organics shipped to it,
  /// because its own upkeep is proportional to population.
  static const List<LevelUpCost> levelUpCosts = [
    LevelUpCost(250, 250, 150, 100), // 1→2
    LevelUpCost(1000, 1000, 600, 400), // 2→3
    LevelUpCost(4000, 4000, 2500, 1500), // 3→4
    LevelUpCost(15000, 20000, 12000, 7000), // 4→5
    LevelUpCost(50000, 80000, 50000, 30000), // 5→6
  ];

  /// Ticks to complete a build from each level, at time scale 1.
  ///
  /// Sized for a single-player game rather than the classic 34-52 *days*: at the
  /// 30s game tick these run 7.5 minutes to 80 minutes, so a full 1→6 is about
  /// four hours of **actual play**, and nothing at all while the game is closed.
  /// That is the point — see [constructionTicksRemaining].
  static const Map<int, int> levelConstructionTicks = {
    1: 15, // 1→2   7.5 min
    2: 30, // 2→3  15 min
    3: 60, // 3→4  30 min
    4: 120, // 4→5   1 hr
    5: 160, // 5→6  80 min
  };

  /// Defence level conferred by reaching each tier.
  ///
  /// This is what a Citadel is *for*. Previously defence was set once at
  /// generation and never changed, so every tier defended identically and the
  /// six levels bought nothing but a slightly better yield multiplier.
  static const Map<int, int> levelDefense = {
    1: 0,
    2: 1,
    3: 2,
    4: 3,
    5: 4,
    6: 4,
  };

  /// Shield rating conferred by reaching each tier.
  static const Map<int, int> levelShield = {
    1: 0,
    2: 2000,
    3: 5000,
    4: 8000,
    5: 14000,
    6: 22000,
  };

  /// Hull (armour) rating conferred by reaching each tier.
  static const Map<int, int> levelArmour = {
    1: 1000,
    2: 4000,
    3: 10000,
    4: 20000,
    5: 40000,
    6: 70000,
  };

  /// How much larger a developed world's population ceiling is.
  ///
  /// The cap used to be a flat per-type number while the level gate demanded up
  /// to a million colonists, so **7 of the 10 planet types could never reach
  /// Citadel** and every Duran homeworld was capped below the 4→5 gate. The two
  /// numbers were mutually unsatisfiable.
  ///
  /// Deriving the cap from the level is the same fix as the storage floor: a
  /// single fixed number cannot serve both a small and a very large colony, so
  /// the gate grows with the colony and can never contradict the cap printed
  /// beside it. Every type can now reach every tier.
  static const Map<int, double> levelColonistScale = {
    1: 1.00,
    2: 1.60,
    3: 2.80,
    4: 5.00,
    5: 8.00,
    6: 12.00,
  };

  static const List<String> levelTitles = [
    'Outpost',
    'Settlement',
    'Colony',
    'Fortified Colony',
    'Planetary Base',
    'Citadel',
  ];

  /// Population ceiling: the type's figure, scaled by how developed the world
  /// is. See [levelColonistScale] for why this is not a flat number.
  int get colonistMax {
    final base = colonistMaxByType[planetType] ?? 100000;
    final scale =
        levelColonistScale[level.clamp(1, levelColonistScale.length)] ?? 1.0;
    return (base * scale).round();
  }

  /// The type's base cap before development, for display and tests.
  int get baseColonistMax => colonistMaxByType[planetType] ?? 100000;
  LevelUpCost? get levelUpCost => level < 6 ? levelUpCosts[level - 1] : null;

  // ---------------------------------------------------------------------------
  // Production
  //
  // This is the single source of truth for the production formula. It used to
  // live inline in the planet screen, written out four times, which meant the
  // number on screen and the number a tick applied could not be checked against
  // each other — and neither existed. `PlanetProductionService` calls
  // [produce]; the screen calls the [mineralOutput]-style getters. Same code.
  // ---------------------------------------------------------------------------

  /// Colonists consumed per unit of organics per tick.
  ///
  /// The design doc originally said 1 per 100. Measured against real production
  /// that is roughly 1% of output even on the worst organics planet, so upkeep
  /// could never bite and the "bigger isn't automatically better" tension the
  /// upkeep exists to create simply could not happen. 1 per 10 makes a colony
  /// need a real share of its workforce on organics to stand still.
  static const int organicsUpkeepDivisor = 10;

  /// Units of a commodity one colonist produces per tick, before type, world
  /// efficiency and level bonuses.
  ///
  /// This is a pure **scale** factor and it is the one number that makes the
  /// storage numbers mean anything. At 1.0 per colonist per tick a full Terran
  /// colony turned out 1,600,000 minerals a tick against a 200,000 store — it
  /// filled the store in 0.6 ticks and then overflowed the rest for the other
  /// 99.4% of the time. No storage cap, and no shipment pool on top of it, can
  /// make sense against an output that large.
  ///
  /// At 0.01 a mid-sized colony turns out a few hundred units a tick, and
  /// [minimumTicksOfOutput] guarantees its store is always sized to hold at
  /// least that much — so a colony can never out-produce its own infrastructure
  /// no matter how large it grows. The shipment pool then holds days rather
  /// than hours —
  /// which is the shape the classic game had, where a world quietly produced its
  /// daily output and you collected it in batches, and where ignoring a planet
  /// too long genuinely cost you the goods.
  ///
  /// Upkeep is divided by the same constant, so every ratio in the design (what
  /// fraction of a workforce must farm to feed the colony, which worlds are
  /// expensive to run) is unchanged. Only the absolute size of a tick's output
  /// moves.
  static const double baseOutputPerColonist = 0.01;

  /// Ceiling on the share of population that can starve in a single tick.
  ///
  /// Without it, a colony with no organics at all would lose everyone at once
  /// and the death would be unrecoverable. The bleed is deliberately slow
  /// enough to notice and answer: measured from 10,000 colonists, a colony
  /// starved and never fed loses 10% in 3 minutes, half in 17, nine tenths in
  /// an hour, and does not actually reach zero for about 170 minutes. The first
  /// few minutes are the ones that matter — that is the window in which
  /// delivering organics saves the colony.
  static const double maxStarvationRatePerTick = 0.02;

  /// Development multiplier by level — how much a colony's *workforce* is worth
  /// per colonist.
  ///
  /// Deliberately shallow. A steeper curve compounds with the type multiplier
  /// and the colonist caps into a ~110x spread between the best and worst
  /// possible colony, which erases planet identity: everything worth having
  /// would end up on one planet type. Level is instead meant to buy **capacity
  /// and defence**, which scale hard — `maxStorage` and `defenseLevel` are
  /// currently set once at generation and do not move with level, which is the
  /// next piece of work (planets.md, phase F). Extraction per colonist stays
  /// close to flat so an Ocean world remains the best food producer and a Lava
  /// world the best mineral source no matter how developed either gets.
  static const Map<int, double> levelDevelopment = {
    1: 1.00,
    2: 1.15,
    3: 1.30,
    4: 1.50,
    5: 1.70,
    6: 2.00,
  };

  double get developmentMultiplier =>
      levelDevelopment[level.clamp(1, levelDevelopment.length)] ?? 1.0;

  /// Combined per-colonist yield: type advantage x the planet's own efficiency
  /// x colony development.
  double get _yieldScale => productionEfficiency * developmentMultiplier;

  double _mult(String key) {
    final m = typeMultipliers[planetType];
    if (m == null) return 1.0;
    return switch (key) {
      'minerals' => m.minerals,
      'organics' => m.organics,
      'industrial' => m.industrial,
      'drones' => m.drones,
      _ => 1.0,
    };
  }

  int get mineralOutput => (colonistsMinerals *
          _mult('minerals') *
          _yieldScale *
          baseOutputPerColonist)
      .round();
  int get organicOutput => (colonistsOrganics *
          _mult('organics') *
          _yieldScale *
          baseOutputPerColonist)
      .round();
  int get industrialOutput => (colonistsIndustrial *
          _mult('industrial') *
          _yieldScale *
          baseOutputPerColonist)
      .round();
  int get droneOutput =>
      (colonistsDrones * _mult('drones') * _yieldScale * baseOutputPerColonist)
          .round();

  /// Output for a named track, before any storage limit is applied.
  int outputFor(String commodity) => switch (commodity) {
        'minerals' => mineralOutput,
        'organics' => organicOutput,
        'industrial' => industrialOutput,
        'drones' => droneOutput,
        _ => 0,
      };

  /// Mid-range unit value per commodity, used to pay out a collected shipment.
  ///
  /// [CommodityRegistry.splitPoint] is the midpoint of the buy/sell spread, so
  /// it is the neutral price: neither a bargain nor a rip-off. This is a
  /// placeholder for real planetary supply chains — once a colony can actually
  /// deliver to a port, the payout should use that port's live buy price with
  /// the player's standing applied, which is worth much more than a flat
  /// midpoint. Kept here rather than in the screen so the model's own tests can
  /// pin it.
  static const Map<String, double> _shipmentUnitValue = {
    'minerals': 42.5,
    'organics': 115.0,
    'industrial': 230.0,
    'drones': 10.0,
  };

  /// Credits owed for a collected shipment.
  ///
  /// Drones are paid at their own rate rather than the generic commodity
  /// midpoint, because a drone is equipment the player already pays to field
  /// rather than a bulk trade good.
  static int shipmentValue(Map<String, int> collected) {
    var total = 0.0;
    for (final entry in collected.entries) {
      final unit =
          _shipmentUnitValue[entry.key] ?? _shipmentUnitValue['minerals']!;
      total += unit * entry.value;
    }
    return total.round();
  }

  /// Puts one tick of a commodity somewhere useful.
  ///
  /// Working store fills first, then the surplus spills into the shipment pool
  /// rather than being discarded. The only genuine loss is a shipment pool that
  /// has itself been allowed to fill, which is reported so the tick can say so
  /// — that is a world left completely ignored, not normal operation.
  ///
  /// Returns what actually landed, and whether anything was lost.
  ({int stored, int spilled, int lost}) deposit(String commodity, int amount) {
    if (amount <= 0) return (stored: 0, spilled: 0, lost: 0);

    final cap = capFor(commodity);
    final current = storedFor(commodity);
    // An existing save can hold more than the new cap allows. Clamping the
    // store downward would destroy a player's goods, so the store is simply not
    // topped up and the surplus goes to pending instead.
    final room = cap - current;
    final intoStore = room <= 0 ? 0 : (amount < room ? amount : room);
    _setStored(commodity, current + intoStore);

    final overflow = amount - intoStore;
    if (overflow <= 0) return (stored: intoStore, spilled: 0, lost: 0);

    final pendingCap = capFor(commodity) * pendingCapMultiple;
    final currentPending = pendingFor(commodity);
    final roomPending = pendingCap - currentPending;
    final intoPending = roomPending <= 0
        ? 0
        : (overflow < roomPending ? overflow : roomPending);
    _setPending(commodity, currentPending + intoPending);

    return (
      stored: intoStore,
      spilled: intoPending,
      lost: overflow - intoPending,
    );
  }

  // ---------------------------------------------------------------------------
  // Storage
  //
  // Per commodity, and derived from planet type + level rather than stored.
  //
  // It was a single `maxStorage` shared by everything, which produced two
  // separate problems. It was far too small for the output a colony actually
  // makes (see [pendingMinerals]), and it was also *displayed* as a single
  // cap against a sum of three stores, so a perfectly legal planet read as
  // overfull — "10.7K / 5.0K" — purely because of how the row was written.
  //
  // The caps follow the classic game's shape: storage is a property of the
  // world and what it produces, so a Volcanic world is vast for minerals and
  // almost useless for organics, an Oceanic world is the reverse, and a
  // Glacial or Vaporous world is cramped across the board. A colony therefore
  // needs a reason to exist per commodity, not just a reason to exist.
  // ---------------------------------------------------------------------------

  /// Working store per commodity at level 1: minerals, organics, industrial.
  ///
  /// Modelled on the classic game's per-product limits, which are wildly
  /// differentiated (Volcanic 1,000,000 ore / 10,000 organics; Oceanic
  /// 1,000,000 organics / 50,000 equipment; Vaporous 10,000 of everything).
  /// Drones are not a classic product, so they are derived from the mineral
  /// store rather than given a hand-picked row.
  static const Map<String, List<int>> baseStorageByType = {
    'Terran': [100000, 100000, 100000],
    'Jungle': [80000, 600000, 60000],
    'Desert': [200000, 50000, 10000],
    'Ocean': [100000, 1000000, 50000],
    'Ice': [20000, 50000, 10000],
    'Lava': [1000000, 10000, 100000],
    'Gas Giant': [10000, 10000, 10000],
    'Moon': [30000, 15000, 25000],
    'Barren': [250000, 12000, 40000],
    'Toxic': [300000, 10000, 60000],
  };

  /// Storage growth by Citadel level. This is the storage half of what levelling
  /// is supposed to buy — the other half is development, and defence is still
  /// outstanding.
  static const Map<int, double> levelStorageScale = {
    1: 1.00,
    2: 1.40,
    3: 2.00,
    4: 3.00,
    5: 4.50,
    6: 6.50,
  };

  /// How much overflow the shipment pool holds, as a multiple of the working
  /// store. Generous on purpose: the pool exists so a colony keeps earning
  /// while you are elsewhere, so it should only ever fill on a world that has
  /// been completely ignored for a very long time.
  static const int pendingCapMultiple = 250;

  /// A store always holds at least this many ticks of its own output.
  ///
  /// This is what makes "no waste" structural rather than a matter of picking
  /// good numbers. A fixed per-type cap cannot serve a colony of a hundred and a
  /// colony of two million — the latter out-produced any fixed cap within
  /// seconds, and every scale constant I chose to paper over that just moved
  /// the problem. So the cap is `max(typeCap, outputPerTick x this)`.
  ///
  /// A small colony therefore keeps its type's character (an Ocean world really
  /// does hold a great deal of organics), and a very large one is automatically
  /// given infrastructure proportionate to what it is producing. Losing goods
  /// now requires ignoring a world for days, which is the intent.
  static const int minimumTicksOfOutput = 120;

  List<int> get _baseStorage {
    final row = baseStorageByType[planetType];
    if (row != null) return row;
    // Unknown type: a modest flat default rather than a crash.
    return const [50000, 50000, 50000];
  }

  double get storageScale =>
      levelStorageScale[level.clamp(1, levelStorageScale.length)] ?? 1.0;

  /// The working store for a commodity: the type's own figure, scaled by level,
  /// but never smaller than [minimumTicksOfOutput] of what the colony currently
  /// makes. See [minimumTicksOfOutput] for why the second half is not optional.
  int _cap(int baseIndex, String commodity) {
    final byType = (_baseStorage[baseIndex] * storageScale).round();
    final byOutput = outputFor(commodity) * minimumTicksOfOutput;
    return byOutput > byType ? byOutput : byType;
  }

  int get maxMinerals => _cap(0, 'minerals');
  int get maxOrganics => _cap(1, 'organics');
  int get maxIndustrial => _cap(2, 'industrial');

  /// Drones are a defence product, so their store tracks the mineral store
  /// rather than getting an invented row that could drift away from it.
  int get maxDrones => (maxMinerals * 0.25).round();

  int get pendingCapMinerals => maxMinerals * pendingCapMultiple;
  int get pendingCapOrganics => maxOrganics * pendingCapMultiple;
  int get pendingCapIndustrial => maxIndustrial * pendingCapMultiple;
  int get pendingCapDrones => maxDrones * pendingCapMultiple;

  int get pendingTotal =>
      pendingMinerals + pendingOrganics + pendingIndustrial + pendingDrones;

  /// Working store for a named commodity.
  int capFor(String commodity) => switch (commodity) {
        'minerals' => maxMinerals,
        'organics' => maxOrganics,
        'industrial' => maxIndustrial,
        'drones' => maxDrones,
        _ => 0,
      };

  int storedFor(String commodity) => switch (commodity) {
        'minerals' => storedMinerals,
        'organics' => storedOrganics,
        'industrial' => storedIndustrial,
        'drones' => storedDrones,
        _ => 0,
      };

  int pendingFor(String commodity) => switch (commodity) {
        'minerals' => pendingMinerals,
        'organics' => pendingOrganics,
        'industrial' => pendingIndustrial,
        'drones' => pendingDrones,
        _ => 0,
      };

  void _setStored(String commodity, int value) {
    switch (commodity) {
      case 'minerals':
        storedMinerals = value;
      case 'organics':
        storedOrganics = value;
      case 'industrial':
        storedIndustrial = value;
      case 'drones':
        storedDrones = value;
    }
  }

  void _setPending(String commodity, int value) {
    switch (commodity) {
      case 'minerals':
        pendingMinerals = value;
      case 'organics':
        pendingOrganics = value;
      case 'industrial':
        pendingIndustrial = value;
      case 'drones':
        pendingDrones = value;
    }
  }

  /// Empties the shipment pool. The caller pays for the goods; this only
  /// decides what was owed.
  Map<String, int> collectShipment() {
    final collected = <String, int>{
      if (pendingMinerals > 0) 'minerals': pendingMinerals,
      if (pendingOrganics > 0) 'organics': pendingOrganics,
      if (pendingIndustrial > 0) 'industrial': pendingIndustrial,
      if (pendingDrones > 0) 'drones': pendingDrones,
    };
    pendingMinerals = 0;
    pendingOrganics = 0;
    pendingIndustrial = 0;
    pendingDrones = 0;
    return collected;
  }

  /// Colonists currently on a production track. Never exceeds [population].
  int get assignedColonists =>
      colonistsMinerals +
      colonistsOrganics +
      colonistsIndustrial +
      colonistsDrones;

  /// Colonists in the colony but not on a track. They still eat, and they are
  /// the pool a player draws from when re-assigning the workforce.
  ///
  /// Clamped at zero because [population] can fall below [assignedColonists]
  /// after a starvation tick, and the track counts are only rebalanced at the
  /// end of [produce]. Showing a negative reserve in that window would be
  /// nonsense; a negative *workforce* is fixed before anything reads it.
  int get reserveColonists =>
      (population - assignedColonists).clamp(0, population);

  /// Organics this colony consumes per tick.
  int get organicsUpkeep => isDestroyed ? 0 : _upkeepUnits(population);

  /// Organics a colony of [population] eats per tick.
  ///
  /// Multiplied by [baseOutputPerColonist] as well as divided by the divisor,
  /// so output and upkeep shrink together and a colony that farms its own food
  /// is still exactly break-even. Scaling both by the same constant leaves every
  /// ratio in the design untouched; only the absolute size of a tick's output
  /// moves.
  ///
  /// (It was originally *divided* by the scale, which inflated upkeep a thousand
  /// fold and made food cost a million times what a colony could grow.)
  static int _upkeepUnits(int population) =>
      ((population / organicsUpkeepDivisor) * baseOutputPerColonist).ceil();

  /// Advances the colony by one tick: produces into storage, pays upkeep, and
  /// starves the population if it cannot feed itself.
  ///
  /// Order matters: production lands **before** upkeep is charged, so a colony
  /// that farms its own food stands still instead of spiralling. That is the
  /// equilibrium the upkeep rule is meant to produce.
  ///
  /// Mutates in place. Returns what happened, so the tick can log it and the
  /// screen can explain it.
  PlanetTickReport produce() {
    if (isDestroyed || population <= 0) return const PlanetTickReport();

    final gainedMinerals = deposit('minerals', mineralOutput);
    final gainedOrganics = deposit('organics', organicOutput);
    final gainedIndustrial = deposit('industrial', industrialOutput);
    final gainedDrones = deposit('drones', droneOutput);

    // Upkeep, then starvation for whatever could not be fed.
    //
    // Drawn from the working store first and the **shipment pool second**. Food
    // already produced and waiting to be collected is still food. Charging only
    // the working store meant a colony could starve on a working store of zero
    // while tens of thousands of organics sat in the shipment pool — which is
    // not a rare state, it is exactly what a busy poor-organics world looks
    // like. Barren worlds are expensive to feed by design; starving them while
    // their own harvest waited to be collected was not.
    final upkeep = organicsUpkeep;
    final fromStore = upkeep <= storedOrganics ? upkeep : storedOrganics;
    storedOrganics -= fromStore;
    final stillOwed = upkeep - fromStore;
    final fromPending =
        stillOwed <= pendingOrganics ? stillOwed : pendingOrganics;
    pendingOrganics -= fromPending;
    final shortfall = upkeep - fromStore - fromPending;
    final lost = _starvationLoss(shortfall, population);

    if (lost > 0) {
      population -= lost;
      // Shrink the workforce with the colony, proportionally, so the tracks
      // can never sum to more than the population that is left to fill them.
      _rebalanceWorkforce();
    }

    return PlanetTickReport(
      mineralsGained: gainedMinerals.stored,
      organicsGained: gainedOrganics.stored,
      industrialGained: gainedIndustrial.stored,
      dronesGained: gainedDrones.stored,
      shipmentQueued: gainedMinerals.spilled +
          gainedOrganics.spilled +
          gainedIndustrial.spilled +
          gainedDrones.spilled,
      organicsConsumed: fromStore + fromPending,
      organicsShortfall: shortfall,
      colonistsLost: lost,
      // Only a full *shipment pool* is real loss now. Overflowing the working
      // store is normal, expected operation and is not worth a warning.
      storageOverflowed: gainedMinerals.lost +
              gainedOrganics.lost +
              gainedIndustrial.lost +
              gainedDrones.lost >
          0,
      population: population,
    );
  }

  /// Colonists lost to a tick's unmet upkeep.
  ///
  /// Sized by how much food was missing — a shortfall of one organics feeds
  /// [organicsUpkeepDivisor] colonists — then capped at
  /// [maxStarvationRatePerTick] of the population. Note the cap is applied to a
  /// *remaining* population each tick, so the bleed compounds downward and is
  /// asymptotic; it never quite reaches zero on its own, which is what the floor
  /// below is for.
  ///
  /// The floor of **one** matters and was a real bug: `floor(population * 0.02)`
  /// is 0 for any population below 50, so a starving colony shrank to 49 and
  /// then stopped losing anyone — a permanent zombie world, starving forever,
  /// that no amount of emergency organics could revive because the tick had
  /// nothing left to take. Guaranteeing at least one loss per starving tick
  /// means an un-fed colony always finishes dying, while a large one still only
  /// bleeds at 2%.
  int _starvationLoss(int shortfall, int population) {
    if (shortfall <= 0 || population <= 0) return 0;
    final cap = (population * maxStarvationRatePerTick).floor();
    return (shortfall / organicsUpkeepDivisor / baseOutputPerColonist)
        .floor()
        .clamp(1, cap < 1 ? 1 : cap);
  }

  /// Scales the four track counts down so they sum to at most [population].
  /// Largest-remainder, so the biggest track absorbs the rounding and the four
  /// tracks never drift to a sum that is off by one from the population.
  void _rebalanceWorkforce() {
    if (population <= 0) {
      colonistsMinerals = 0;
      colonistsOrganics = 0;
      colonistsIndustrial = 0;
      colonistsDrones = 0;
      return;
    }
    final assigned = assignedColonists;
    if (assigned <= population) return;

    final exact = <double>[
      colonistsMinerals / assigned * population,
      colonistsOrganics / assigned * population,
      colonistsIndustrial / assigned * population,
      colonistsDrones / assigned * population,
    ];
    final floors = exact.map((v) => v.floor()).toList();
    var remainder = population - floors.fold<int>(0, (a, b) => a + b);
    // Hand the leftover units to the tracks with the biggest fractional part.
    final order = [0, 1, 2, 3]
      ..sort((a, b) => (exact[b] - floors[b]).compareTo(exact[a] - floors[a]));
    for (var i = 0; remainder > 0 && i < order.length; i++, remainder--) {
      floors[order[i]]++;
    }
    colonistsMinerals = floors[0];
    colonistsOrganics = floors[1];
    colonistsIndustrial = floors[2];
    colonistsDrones = floors[3];
  }

  /// Whether a build can be started: not already building, and able to pay.
  ///
  /// Colonists are a **minimum, not a cost** — a gate you satisfy by having
  /// enough people. Resources are the part you spend.
  bool get canStartConstruction {
    if (isUnderConstruction) return false;
    final cost = levelUpCost;
    if (cost == null) return false;
    if (population < cost.requiredColonists) return false;
    if (storedMinerals < cost.requiredMinerals) return false;
    if (storedOrganics < cost.requiredOrganics) return false;
    if (storedIndustrial < cost.requiredIndustrial) return false;
    return true;
  }

  /// True while a build is in progress.
  bool get isUnderConstruction => constructionTicksRemaining > 0;

  /// Ticks the current build started with, for a progress bar. 0 when idle.
  int get constructionTotalTicks =>
      isUnderConstruction ? constructionLengthFor(level) : 0;

  /// 0.0 to 1.0 through the current build.
  double get constructionProgress {
    if (!isUnderConstruction) return 0;
    final total = constructionTotalTicks;
    if (total <= 0) return 1;
    return (1 - (constructionTicksRemaining / total)).clamp(0.0, 1.0);
  }

  /// Ticks required to build from [from] up one level, scaled.
  ///
  /// The scale is applied **here, at the moment the build starts**, not when it
  /// finishes. A player who speeds construction up halfway through does not
  /// retroactively shorten it, and the tick loop stays free of any dependency on
  /// settings.
  static int constructionLengthFor(int from, {double timeScale = 1.0}) {
    final base = levelConstructionTicks[from];
    if (base == null) return 0;
    // A scale of 0 is the "I would rather not wait" preference and means instant.
    // Dividing by it instead would produce an enormous number, which is the
    // opposite of what the player asked for and reads as a bug rather than a
    // setting. One tick, not zero: a zero-length build would complete inside
    // the tick that started it and never show a frame of progress.
    if (timeScale <= 0) return 1;
    // Multiply, do not divide. A scale of 0.5 means "twice as fast as designed",
    // which is a *shorter* build; dividing here silently made the "faster"
    // setting twice as slow instead. The user-facing number and this arithmetic
    // have to read the same way round, which is what the guard below pins.
    final scaled = (base * timeScale).round();
    return scaled < 1 ? 1 : scaled;
  }

  /// Spends the resources and begins a build. Returns true if it started.
  ///
  /// Resources are consumed **at the start**, not on completion, and that is
  /// deliberate: it makes the build a commitment rather than a purchase. A world
  /// two hours into a Citadel upgrade is holding an investment an attacker can
  /// cost you, which is the point of the mechanic.
  bool startConstruction({double timeScale = 1.0}) {
    if (!canStartConstruction) return false;
    final cost = levelUpCost!;
    storedMinerals -= cost.requiredMinerals;
    storedOrganics -= cost.requiredOrganics;
    storedIndustrial -= cost.requiredIndustrial;
    constructionTarget = level + 1;
    constructionTicksRemaining =
        constructionLengthFor(level, timeScale: timeScale);
    return true;
  }

  /// Advances a build by one tick. Called by the game tick.
  ///
  /// Completing a build is what finally grants the level's benefits. Storage needs
  /// no code here because it is derived from `level`; defence and armour do,
  /// because the generator used to set them once and nothing ever changed them,
  /// so a level-6 Citadel defended exactly as well as a level-1 Outpost.
  void advanceConstruction() {
    if (!isUnderConstruction) return;
    constructionTicksRemaining--;
    if (constructionTicksRemaining > 0) return;

    level = constructionTarget;
    constructionTarget = 0;
    constructionTicksRemaining = 0;
    _applyLevelGrants();
  }

  /// Applies what a completed level confers.
  ///
  /// Locals are named `new*` rather than after the field they assign. Shadowing
  /// `shield` with a local `shield` made `shield = shield` a self-assignment on
  /// a final local, which the compiler caught — but the fix is a clearer name,
  /// not a cast.
  void _applyLevelGrants() {
    final newDefence = levelDefense[level] ?? defenseLevel;
    defenseLevel = newDefence;

    final newArmour = levelArmour[level] ?? 0;
    if (newArmour > 0) {
      maxHull = newArmour.toDouble();
      if (hull > newArmour) hull = newArmour.toDouble();
      if (hull <= 0) hull = newArmour.toDouble();
    }

    final newShield = levelShield[level] ?? 0;
    if (newShield > 0) {
      maxShield = newShield.toDouble();
      shield = newShield.toDouble();
    }
  }

  /// Instant level-up. Kept as a distinct path so the cost table and the grant
  /// table have exactly one implementation: a timed build is this, plus a wait.
  bool levelUp() {
    if (!canStartConstruction) return false;
    final cost = levelUpCost!;
    storedMinerals -= cost.requiredMinerals;
    storedOrganics -= cost.requiredOrganics;
    storedIndustrial -= cost.requiredIndustrial;
    level++;
    constructionTarget = 0;
    constructionTicksRemaining = 0;
    _applyLevelGrants();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Planet type configuration
  // ---------------------------------------------------------------------------

  static const Map<String, AtmosphereConfig> planetAtmospheres = {
    'Terran': AtmosphereConfig('N2-O2', 'Earth-like, habitable'),
    'Jungle': AtmosphereConfig('N2-O2', 'Dense vegetation'),
    'Desert': AtmosphereConfig('Thin', 'Arid, sandy'),
    'Ocean': AtmosphereConfig('N2-O2', 'Water world'),
    'Ice': AtmosphereConfig('Thin', 'Frozen wasteland'),
    'Lava': AtmosphereConfig('CO2', 'Volcanic, molten'),
    'Gas Giant': AtmosphereConfig('Dense', 'Massive, gaseous'),
    'Moon': AtmosphereConfig('None', 'Small rocky body'),
    'Barren': AtmosphereConfig('None', 'Rocky, lifeless'),
    'Toxic': AtmosphereConfig('Acid', 'Corrosive atmosphere'),
  };

  static const Map<String, TypeMultipliers> typeMultipliers = {
    'Terran': TypeMultipliers(1.0, 1.0, 1.2, 1.0),
    'Jungle': TypeMultipliers(0.6, 1.8, 0.6, 0.8),
    'Desert': TypeMultipliers(1.4, 0.4, 0.8, 1.2),
    'Ocean': TypeMultipliers(0.4, 2.0, 0.6, 0.6),
    'Ice': TypeMultipliers(0.8, 0.4, 0.6, 0.8),
    'Lava': TypeMultipliers(2.0, 0.2, 1.4, 1.4),
    'Gas Giant': TypeMultipliers(0.6, 0.6, 0.4, 1.0),
    'Moon': TypeMultipliers(1.0, 0.4, 0.6, 0.8),
    'Barren': TypeMultipliers(1.2, 0.2, 0.8, 1.0),
    'Toxic': TypeMultipliers(1.6, 0.3, 1.0, 1.2),
  };

  static const List<String> allTypes = [
    'Terran',
    'Jungle',
    'Desert',
    'Ocean',
    'Ice',
    'Lava',
    'Gas Giant',
    'Moon',
    'Barren',
    'Toxic',
  ];

  static const Map<String, List<String>> imagePool = {
    'Terran': [
      'Terran_World_1.gif',
      'Terran_World_2.gif',
      'Terran_World_3.gif'
    ],
    'Jungle': [
      'Jungle_World_1.gif',
      'Jungle_World_2.gif',
      'Jungle_World_3.gif'
    ],
    'Desert': [
      'Desert_World_1.gif',
      'Desert_World_2.gif',
      'Desert_World_3.gif'
    ],
    'Ocean': ['Ocean_World_1.gif', 'Ocean_World_2.gif', 'Ocean_World_3.gif'],
    'Ice': ['Ice_World_1.gif', 'Ice_World_2.gif', 'Ice_world_3.gif'],
    'Lava': ['Lava_World_1.gif', 'Lava_World_2.gif', 'Lava_World_3.gif'],
    'Gas Giant': ['Gas_Giant_1.gif', 'Gas_Giant_2.gif', 'Gas_Giant_3.gif'],
    'Moon': ['Moon_1.gif', 'Moon_2.gif', 'Moon_3.gif'],
    'Barren': ['Moon_1.gif', 'Moon_2.gif', 'Moon_3.gif'],
    'Toxic': ['Toxic_World_1.gif', 'Toxic_World_2.gif', 'Toxic_World_3.gif'],
  };

  static const List<String> planetNames = [
    'Xandor',
    'Elara',
    'Sygnara',
    'Voryn',
    'Celestara',
    'Rynara',
    'Thalys',
    'Orwyn',
    'Glavara',
    'Zephyron',
    'Tyria',
    'Axion',
    'Nebulon',
    'Valthor',
    'Saronis',
    'Elyx',
    'Corvus',
    'Zantara',
    'Oberyn',
    'Krythos',
    'Selara',
    'Phaeton',
    'Ecliptor',
    'Astralis',
    'Vionis',
    'Nexilon',
    'Caelum',
    'Sypher',
    'Galeth',
    'Xeridia',
    'Lumora',
    'Tychon',
    'Velara',
    'Myriad',
    'Arctura',
    'Novex',
    'Zephyris',
    'Calyx',
    'Orithyia',
    'Sylvara',
    'Aetherion',
    'Draconis',
    'Quasys',
    'Solara',
    'Erebos',
    'Thalara',
    'Kryon',
    'Vylis',
    'Nexara',
    'Zorath',
    'Ilythar',
    'Vexalon',
    'Synthera',
    'Auralis',
    'Zypheron',
    'Tarsys',
    'Elion',
    'Gravara',
    'Nyxara',
    'Corynth',
    'Xylara',
    'Praxon',
    'Vionara',
    'Zelthar',
    'Astron',
    'Kytheris',
    'Sylion',
    'Eryndor',
    'Valthys',
    'Orythia',
    'Nebula',
    'Xerath',
    'Tylara',
    'Cygnara',
    'Aethys',
    'Zorwyn',
    'Vexara',
    'Sylthara',
    'Klyon',
    'Ecthara',
    'Rynther',
    'Galara',
    'Zyron',
    'Velithor',
    'Naxara',
    'Thalith',
    'Orionis',
    'Clythera',
    'Voryth',
    'Aelara',
    'Xynara',
    'Krylara',
    'Zentara',
    'Elythar',
    'Sovara',
    'Nyxion',
    'Tethys',
    'Vionth',
    'Astrara',
  ];

  static const List<String> romanNumerals = [
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
  ];

  static const List<String> greekPrefixes = [
    'Alpha',
    'Beta',
    'Delta',
    'Gamma',
  ];

  /// Generates a varied planet name from a base name, optionally appending
  /// Roman numeral and/or Greek prefix for variety.
  /// Formats: "Lumora", "Lumora III", "Lumora Alpha", "Lumora Alpha V"
  static String generateVariantName(String baseName, int seed) {
    final rng = int.parse(
        (seed.abs() % 100000).toString().padLeft(5, '0').substring(0, 3));
    final variant = rng % 4;
    switch (variant) {
      case 1: // name + numeral
        return '$baseName ${romanNumerals[rng % romanNumerals.length]}';
      case 2: // name + prefix
        return '$baseName ${greekPrefixes[rng % greekPrefixes.length]}';
      case 3: // name + prefix + numeral
        return '$baseName ${greekPrefixes[(rng + 2) % greekPrefixes.length]} ${romanNumerals[(rng + 3) % romanNumerals.length]}';
      default: // 0 — plain name
        return baseName;
    }
  }
}

class AtmosphereConfig {
  final String atmosphere;
  final String description;
  const AtmosphereConfig(this.atmosphere, this.description);
}

class TypeMultipliers {
  final double minerals;
  final double organics;
  final double industrial;
  final double drones;
  const TypeMultipliers(
      this.minerals, this.organics, this.industrial, this.drones);
}

/// What one production tick did to a colony.
///
/// Returned rather than merely logged so the tick can summarise it, the action
/// log can report it, and a test can assert on it without reaching into four
/// storage fields and hoping it checked all of them.
class PlanetTickReport {
  final int mineralsGained;
  final int organicsGained;
  final int industrialGained;
  final int dronesGained;

  /// Output that overflowed the working store and is now waiting in the
  /// shipment pool. Not a loss — it is still owed to the player.
  final int shipmentQueued;

  /// Organics actually charged against upkeep. Less than the upkeep figure when
  /// the colony could not feed itself.
  final int organicsConsumed;

  /// Upkeep that went unmet. Non-zero means colonists are dying.
  final int organicsShortfall;

  final int colonistsLost;

  /// Some output did not fit in storage and was discarded.
  final bool storageOverflowed;

  /// Population after the tick, so a caller can report a loss without
  /// re-reading the planet.
  final int population;

  const PlanetTickReport({
    this.mineralsGained = 0,
    this.organicsGained = 0,
    this.industrialGained = 0,
    this.dronesGained = 0,
    this.shipmentQueued = 0,
    this.organicsConsumed = 0,
    this.organicsShortfall = 0,
    this.colonistsLost = 0,
    this.storageOverflowed = false,
    this.population = 0,
  });

  /// True when the tick changed anything a player would want told about.
  bool get isInteresting =>
      mineralsGained > 0 ||
      organicsGained > 0 ||
      industrialGained > 0 ||
      dronesGained > 0 ||
      colonistsLost > 0 ||
      storageOverflowed;

  /// True when the colony is starving. Worth its own log line: it is the one
  /// outcome a player must act on rather than merely enjoy.
  bool get isStarving => organicsShortfall > 0;
}

class LevelUpCost {
  final int requiredColonists;
  final int requiredMinerals;
  final int requiredOrganics;
  final int requiredIndustrial;
  const LevelUpCost(this.requiredColonists, this.requiredMinerals,
      this.requiredOrganics, this.requiredIndustrial);
}
