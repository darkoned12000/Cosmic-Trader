import 'package:cosmic_trader/data/models/faction.dart';

FactionClass? _parseFactionClass(String? name) {
  if (name == null) return null;
  try {
    return FactionClass.values.firstWhere((e) => e.name == name);
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

  // Colony
  int population;
  int colonistsMinerals;
  int colonistsOrganics;
  int colonistsIndustrial;
  int colonistsFighters;
  double productionEfficiency;

  // Storage
  int storedMinerals;
  int storedOrganics;
  int storedIndustrial;
  int storedFighters;
  int maxStorage;

  // Level / Citadel (1-6)
  int level;
  int levelProgress;
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
    this.colonistsFighters = 0,
    this.productionEfficiency = 1.0,
    this.storedMinerals = 0,
    this.storedOrganics = 0,
    this.storedIndustrial = 0,
    this.storedFighters = 0,
    this.maxStorage = 5000,
    this.level = 1,
    this.levelProgress = 0,
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
    this.imagePath,
    this.scanned = false,
  });

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
      'colonistsFighters': colonistsFighters,
      'productionEfficiency': productionEfficiency,
      'storedMinerals': storedMinerals,
      'storedOrganics': storedOrganics,
      'storedIndustrial': storedIndustrial,
      'storedFighters': storedFighters,
      'maxStorage': maxStorage,
      'level': level,
      'levelProgress': levelProgress,
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
      colonistsFighters: json['colonistsFighters'] as int? ?? 0,
      productionEfficiency:
          (json['productionEfficiency'] as num?)?.toDouble() ?? 1.0,
      storedMinerals: json['storedMinerals'] as int? ?? 0,
      storedOrganics: json['storedOrganics'] as int? ?? 0,
      storedIndustrial: json['storedIndustrial'] as int? ?? 0,
      storedFighters: json['storedFighters'] as int? ?? 0,
      maxStorage: json['maxStorage'] as int? ?? 5000,
      level: json['level'] as int? ?? 1,
      levelProgress: json['levelProgress'] as int? ?? 0,
      requiredMinerals: json['requiredMinerals'] as int? ?? 500,
      requiredOrganics: json['requiredOrganics'] as int? ?? 300,
      requiredIndustrial: json['requiredIndustrial'] as int? ?? 200,
      requiredColonists: json['requiredColonists'] as int? ?? 100,
      defenseLevel: json['defenseLevel'] as int? ?? 0,
      shield: (json['shield'] as num?)?.toDouble() ?? 0,
      maxShield: (json['maxShield'] as num?)?.toDouble() ?? 0,
      hull: (json['hull'] as num?)?.toDouble() ?? 1000,
      maxHull: (json['maxHull'] as num?)?.toDouble() ?? 1000,
      productionTimer: json['productionTimer'] as int? ?? 0,
      spawnInterval: json['spawnInterval'] as int? ?? 10,
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
  static const List<LevelUpCost> levelUpCosts = [
    LevelUpCost(1000, 500, 300, 200), // 1→2
    LevelUpCost(10000, 2500, 1500, 1000), // 2→3
    LevelUpCost(100000, 10000, 6000, 4000), // 3→4
    LevelUpCost(500000, 50000, 30000, 20000), // 4→5
    LevelUpCost(1000000, 250000, 150000, 100000), // 5→6
  ];

  static const List<String> levelTitles = [
    'Outpost',
    'Settlement',
    'Colony',
    'Fortified Colony',
    'Planetary Base',
    'Citadel',
  ];

  int get colonistMax => colonistMaxByType[planetType] ?? 100000;
  LevelUpCost? get levelUpCost => level < 6 ? levelUpCosts[level - 1] : null;

  /// Whether this planet can be levelled up.
  bool get canLevelUp {
    final cost = levelUpCost;
    if (cost == null) return false;
    if (population < cost.requiredColonists) return false;
    if (storedMinerals < cost.requiredMinerals) return false;
    if (storedOrganics < cost.requiredOrganics) return false;
    if (storedIndustrial < cost.requiredIndustrial) return false;
    return true;
  }

  /// Consumes resources and increases level by 1.
  /// Returns true if the level-up succeeded.
  bool levelUp() {
    final cost = levelUpCost;
    if (cost == null) return false;
    if (!canLevelUp) return false;
    storedMinerals -= cost.requiredMinerals;
    storedOrganics -= cost.requiredOrganics;
    storedIndustrial -= cost.requiredIndustrial;
    level++;
    levelProgress = 0;
    // Set next level's requirements
    final nextCost = levelUpCost;
    if (nextCost != null) {
      requiredMinerals = nextCost.requiredMinerals;
      requiredOrganics = nextCost.requiredOrganics;
      requiredIndustrial = nextCost.requiredIndustrial;
      requiredColonists = nextCost.requiredColonists;
    }
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
  final double fighters;
  const TypeMultipliers(
      this.minerals, this.organics, this.industrial, this.fighters);
}

class LevelUpCost {
  final int requiredColonists;
  final int requiredMinerals;
  final int requiredOrganics;
  final int requiredIndustrial;
  const LevelUpCost(this.requiredColonists, this.requiredMinerals,
      this.requiredOrganics, this.requiredIndustrial);
}
