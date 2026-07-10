import 'dart:math' as math;

/// Configuration for universe generation and game economy.
class GameSettings {
  // --- Universe generation ---
  final int totalSectors;
  final int seed;

  /// Raw text the user typed (preserved so the seed field shows the original string instead of the hashed integer after regeneration).
  final String rawSeed;
  final double portDensity;
  final double planetDensity;
  final double traderDensity;
  final double duranDensity;
  final double vinariDensity;
  final double pirateDensity;
  final int npcStartingCredits;
  final double anomalyDensity;
  final double hardwareEmporiumDensity;

  // --- FedSpace ---
  final int fedSpaceEnd;

  // --- Warp distribution (must sum to 1.0) ---
  final double pct1Warp;
  final double pct2Warp;
  final double pct3Warp;
  final double pct4Warp;
  final double pct5Warp;
  final double pct6Warp;
  final double pct7Warp;

  // --- Clustering / bubbles ---
  final double bubbleChance;
  final int maxBubbleSize;

  // --- Content lists ---

  final List<String> anomalyTypes;

  // --- Economy ---
  final double mineralPriceMin;
  final double mineralPriceMax;
  final double organicsPriceMin;
  final double organicsPriceMax;
  final double industrialPriceMin;
  final double industrialPriceMax;
  final int mineralQtyMin;
  final int mineralQtyMax;
  final int organicsQtyMin;
  final int organicsQtyMax;
  final int industrialQtyMin;
  final int industrialQtyMax;

  // --- Player initial values ---
  final int initTurns;
  final int initCredits;
  final int initHolds;
  final int initDrones;

  // --- Dead ends ---

  /// When true, regenerating the universe resets all players to sector 1.
  final bool resetPlayersOnRegen;

  /// When true, regenerating the universe deletes all player accounts (full wipe for testing).
  final bool deleteAllPlayersOnRegen;

  /// When false, only the default ship is selectable on account creation (others locked behind milestones).
  final bool unlockAllShips;

  /// Animation speed multiplier for tactical display effects (ping ripple, data scroll).
  final double tacticalDisplaySpeed;

  // --- Video ---
  final bool fullscreen;
  final double windowScale;
  final int resolutionWidth;
  final int resolutionHeight;

  // --- Font ---
  final String fontFamily;
  final double fontSize;

  // --- Audio ---
  final double musicVolume;
  final double sfxVolume;
  final String musicFolderPath;

  const GameSettings({
    required this.totalSectors,
    this.seed = 0,
    this.rawSeed = '',
    required this.portDensity,
    required this.planetDensity,
    required this.traderDensity,
    required this.duranDensity,
    required this.vinariDensity,
    required this.anomalyDensity,
    this.hardwareEmporiumDensity = 0.05,
    required this.fedSpaceEnd,
    required this.bubbleChance,
    required this.maxBubbleSize,
    required this.anomalyTypes,
    this.mineralPriceMin = 5,
    this.mineralPriceMax = 25,
    this.organicsPriceMin = 10,
    this.organicsPriceMax = 50,
    this.industrialPriceMin = 20,
    this.industrialPriceMax = 100,
    this.mineralQtyMin = 10000,
    this.mineralQtyMax = 50000,
    this.organicsQtyMin = 5000,
    this.organicsQtyMax = 40000,
    this.industrialQtyMin = 3000,
    this.industrialQtyMax = 3000,
    this.pct1Warp = 0.10,
    this.pct2Warp = 0.30,
    this.pct3Warp = 0.28,
    this.pct4Warp = 0.15,
    this.pct5Warp = 0.10,
    this.pct6Warp = 0.05,
    this.pct7Warp = 0.02,
    this.initTurns = 1000,
    this.initCredits = 1000000,
    this.initHolds = 50,
    this.initDrones = 100,
    this.resetPlayersOnRegen = true,
    this.deleteAllPlayersOnRegen = false,
    this.unlockAllShips = true,
    this.pirateDensity = 0.05,
    this.npcStartingCredits = 10000,
    this.tacticalDisplaySpeed = 0.5,
    this.fullscreen = false,
    this.windowScale = 0.75,
    this.resolutionWidth = 1280,
    this.resolutionHeight = 720,
    this.fontFamily = '',
    this.fontSize = 14,
    this.musicVolume = 0.5,
    this.sfxVolume = 0.7,
    this.musicFolderPath = 'assets/music',
  });

  /// Default settings matching original TW2052 behavior.
  factory GameSettings.defaults() {
    return GameSettings(
      totalSectors: 50,
      seed: 0,
      portDensity: 0.35,
      planetDensity: 0.25,
      traderDensity: 0.12,
      duranDensity: 0.10,
      vinariDensity: 0.08,
      anomalyDensity: 0.1,
      hardwareEmporiumDensity: 0.05,
      fedSpaceEnd: 9,
      bubbleChance: 0.15,
      maxBubbleSize: 6,
      resetPlayersOnRegen: true,
      anomalyTypes: [
        'Asteroid Field',
        'Nebula',
        'Debris Field',
        'Gravity Well',
        'Radiation Storm',
        'Dark Matter Cloud',
      ],
      pirateDensity: 0.05,
      npcStartingCredits: 10000,
      tacticalDisplaySpeed: 0.5,
      fullscreen: false,
      windowScale: 0.75,
      resolutionWidth: 1280,
      resolutionHeight: 720,
      fontFamily: '',
      fontSize: 14,
      musicVolume: 0.5,
      sfxVolume: 0.7,
      musicFolderPath: 'assets/music',
    );
  }

  /// Seeded random generator. Seed 0 uses a time-based seed.
  math.Random getRng() {
    return seed == 0 ? math.Random() : math.Random(seed);
  }

  GameSettings copyWith({
    int? totalSectors,
    int? seed,
    String? rawSeed,
    double? portDensity,
    double? planetDensity,
    double? traderDensity,
    double? duranDensity,
    double? vinariDensity,
    double? anomalyDensity,
    double? hardwareEmporiumDensity,
    int? fedSpaceEnd,
    double? bubbleChance,
    int? maxBubbleSize,
    List<String>? anomalyTypes,
    double? mineralPriceMin,
    double? mineralPriceMax,
    double? organicsPriceMin,
    double? organicsPriceMax,
    double? industrialPriceMin,
    double? industrialPriceMax,
    int? mineralQtyMin,
    int? mineralQtyMax,
    int? organicsQtyMin,
    int? organicsQtyMax,
    int? industrialQtyMin,
    int? industrialQtyMax,
    int? initTurns,
    int? initCredits,
    int? initHolds,
    int? initDrones,
    double? pct1Warp,
    double? pct2Warp,
    double? pct3Warp,
    double? pct4Warp,
    double? pct5Warp,
    double? pct6Warp,
    double? pct7Warp,
    bool? resetPlayersOnRegen,
    bool? deleteAllPlayersOnRegen,
    bool? unlockAllShips,
    double? pirateDensity,
    int? npcStartingCredits,
    double? tacticalDisplaySpeed,
    bool? fullscreen,
    double? windowScale,
    int? resolutionWidth,
    int? resolutionHeight,
    String? fontFamily,
    double? fontSize,
    double? musicVolume,
    double? sfxVolume,
    String? musicFolderPath,
  }) {
    return GameSettings(
      totalSectors: totalSectors ?? this.totalSectors,
      seed: seed ?? this.seed,
      rawSeed: rawSeed ?? this.rawSeed,
      portDensity: portDensity ?? this.portDensity,
      planetDensity: planetDensity ?? this.planetDensity,
      traderDensity: traderDensity ?? this.traderDensity,
      duranDensity: duranDensity ?? this.duranDensity,
      vinariDensity: vinariDensity ?? this.vinariDensity,
      anomalyDensity: anomalyDensity ?? this.anomalyDensity,
      hardwareEmporiumDensity:
          hardwareEmporiumDensity ?? this.hardwareEmporiumDensity,
      fedSpaceEnd: fedSpaceEnd ?? this.fedSpaceEnd,
      bubbleChance: bubbleChance ?? this.bubbleChance,
      maxBubbleSize: maxBubbleSize ?? this.maxBubbleSize,
      anomalyTypes: anomalyTypes ?? this.anomalyTypes,
      mineralPriceMin: mineralPriceMin ?? this.mineralPriceMin,
      mineralPriceMax: mineralPriceMax ?? this.mineralPriceMax,
      organicsPriceMin: organicsPriceMin ?? this.organicsPriceMin,
      organicsPriceMax: organicsPriceMax ?? this.organicsPriceMax,
      industrialPriceMin: industrialPriceMin ?? this.industrialPriceMin,
      industrialPriceMax: industrialPriceMax ?? this.industrialPriceMax,
      mineralQtyMin: mineralQtyMin ?? this.mineralQtyMin,
      mineralQtyMax: mineralQtyMax ?? this.mineralQtyMax,
      organicsQtyMin: organicsQtyMin ?? this.organicsQtyMin,
      organicsQtyMax: organicsQtyMax ?? this.organicsQtyMax,
      industrialQtyMin: industrialQtyMin ?? this.industrialQtyMin,
      industrialQtyMax: industrialQtyMax ?? this.industrialQtyMax,
      pct1Warp: pct1Warp ?? this.pct1Warp,
      pct2Warp: pct2Warp ?? this.pct2Warp,
      pct3Warp: pct3Warp ?? this.pct3Warp,
      pct4Warp: pct4Warp ?? this.pct4Warp,
      pct5Warp: pct5Warp ?? this.pct5Warp,
      pct6Warp: pct6Warp ?? this.pct6Warp,
      pct7Warp: pct7Warp ?? this.pct7Warp,
      initTurns: initTurns ?? this.initTurns,
      initCredits: initCredits ?? this.initCredits,
      initHolds: initHolds ?? this.initHolds,
      initDrones: initDrones ?? this.initDrones,
      pirateDensity: pirateDensity ?? this.pirateDensity,
      npcStartingCredits: npcStartingCredits ?? this.npcStartingCredits,
      resetPlayersOnRegen: resetPlayersOnRegen ?? this.resetPlayersOnRegen,
      deleteAllPlayersOnRegen:
          deleteAllPlayersOnRegen ?? this.deleteAllPlayersOnRegen,
      unlockAllShips: unlockAllShips ?? this.unlockAllShips,
      tacticalDisplaySpeed:
          tacticalDisplaySpeed ?? this.tacticalDisplaySpeed,
      fullscreen: fullscreen ?? this.fullscreen,
      windowScale: windowScale ?? this.windowScale,
      resolutionWidth: resolutionWidth ?? this.resolutionWidth,
      resolutionHeight: resolutionHeight ?? this.resolutionHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      musicVolume: musicVolume ?? this.musicVolume,
      sfxVolume: sfxVolume ?? this.sfxVolume,
      musicFolderPath: musicFolderPath ?? this.musicFolderPath,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'totalSectors': totalSectors,
      'seed': seed,
      'rawSeed': rawSeed,
      'portDensity': portDensity,
      'planetDensity': planetDensity,
      'traderDensity': traderDensity,
      'duranDensity': duranDensity,
      'vinariDensity': vinariDensity,
      'anomalyDensity': anomalyDensity,
      'hardwareEmporiumDensity': hardwareEmporiumDensity,
      'fedSpaceEnd': fedSpaceEnd,
      'bubbleChance': bubbleChance,
      'maxBubbleSize': maxBubbleSize,
      'pct1Warp': pct1Warp,
      'pct2Warp': pct2Warp,
      'pct3Warp': pct3Warp,
      'pct4Warp': pct4Warp,
      'pct5Warp': pct5Warp,
      'pct6Warp': pct6Warp,
      'pct7Warp': pct7Warp,
      'resetPlayersOnRegen': resetPlayersOnRegen,
      'deleteAllPlayersOnRegen': deleteAllPlayersOnRegen,
      'unlockAllShips': unlockAllShips,
      'anomalyTypes': anomalyTypes,
      'mineralPriceMin': mineralPriceMin,
      'mineralPriceMax': mineralPriceMax,
      'organicsPriceMin': organicsPriceMin,
      'organicsPriceMax': organicsPriceMax,
      'industrialPriceMin': industrialPriceMin,
      'industrialPriceMax': industrialPriceMax,
      'mineralQtyMin': mineralQtyMin,
      'mineralQtyMax': mineralQtyMax,
      'organicsQtyMin': organicsQtyMin,
      'organicsQtyMax': organicsQtyMax,
      'industrialQtyMin': industrialQtyMin,
      'industrialQtyMax': industrialQtyMax,
      'initTurns': initTurns,
      'initCredits': initCredits,
      'initHolds': initHolds,
      'initDrones': initDrones,
      'pirateDensity': pirateDensity,
      'npcStartingCredits': npcStartingCredits,
      'tacticalDisplaySpeed': tacticalDisplaySpeed,
      'fullscreen': fullscreen,
      'windowScale': windowScale,
      'resolutionWidth': resolutionWidth,
      'resolutionHeight': resolutionHeight,
      'fontFamily': fontFamily,
      'fontSize': fontSize,
      'musicVolume': musicVolume,
      'sfxVolume': sfxVolume,
      'musicFolderPath': musicFolderPath,
    };
  }

  factory GameSettings.fromJson(Map<String, dynamic> json) {
    return GameSettings(
      totalSectors: json['totalSectors'] as int? ?? 50,
      seed: json['seed'] as int? ?? 0,
      rawSeed: json['rawSeed'] as String? ?? '',
      portDensity: (json['portDensity'] as num?)?.toDouble() ?? 0.35,
      planetDensity: (json['planetDensity'] as num?)?.toDouble() ?? 0.25,
      traderDensity: (json['traderDensity'] as num?)?.toDouble() ?? 0.12,
      duranDensity: (json['duranDensity'] as num?)?.toDouble() ?? 0.10,
      vinariDensity: (json['vinariDensity'] as num?)?.toDouble() ?? 0.08,
      anomalyDensity: (json['anomalyDensity'] as num?)?.toDouble() ?? 0.1,
      hardwareEmporiumDensity:
          (json['hardwareEmporiumDensity'] as num?)?.toDouble() ?? 0.05,
      fedSpaceEnd: json['fedSpaceEnd'] as int? ?? 9,
      bubbleChance: (json['bubbleChance'] as num?)?.toDouble() ?? 0.15,
      maxBubbleSize: json['maxBubbleSize'] as int? ?? 6,
      pct1Warp: (json['pct1Warp'] as num?)?.toDouble() ?? 0.10,
      pct2Warp: (json['pct2Warp'] as num?)?.toDouble() ?? 0.30,
      pct3Warp: (json['pct3Warp'] as num?)?.toDouble() ?? 0.28,
      pct4Warp: (json['pct4Warp'] as num?)?.toDouble() ?? 0.15,
      pct5Warp: (json['pct5Warp'] as num?)?.toDouble() ?? 0.10,
      pct6Warp: (json['pct6Warp'] as num?)?.toDouble() ?? 0.05,
      pct7Warp: (json['pct7Warp'] as num?)?.toDouble() ?? 0.02,
      resetPlayersOnRegen: json['resetPlayersOnRegen'] as bool? ?? true,
      deleteAllPlayersOnRegen:
          json['deleteAllPlayersOnRegen'] as bool? ?? false,
      unlockAllShips: json['unlockAllShips'] as bool? ?? true,
      anomalyTypes: (json['anomalyTypes'] as List?)?.cast<String>() ??
          _defaultAnomalies(),
      mineralPriceMin: (json['mineralPriceMin'] as num?)?.toDouble() ?? 5,
      mineralPriceMax: (json['mineralPriceMax'] as num?)?.toDouble() ?? 25,
      organicsPriceMin: (json['organicsPriceMin'] as num?)?.toDouble() ?? 10,
      organicsPriceMax: (json['organicsPriceMax'] as num?)?.toDouble() ?? 50,
      industrialPriceMin:
          (json['industrialPriceMin'] as num?)?.toDouble() ?? 20,
      industrialPriceMax:
          (json['industrialPriceMax'] as num?)?.toDouble() ?? 100,
      mineralQtyMin: json['mineralQtyMin'] as int? ?? 10000,
      mineralQtyMax: json['mineralQtyMax'] as int? ?? 50000,
      organicsQtyMin: json['organicsQtyMin'] as int? ?? 5000,
      organicsQtyMax: json['organicsQtyMax'] as int? ?? 40000,
      industrialQtyMin: json['industrialQtyMin'] as int? ?? 3000,
      industrialQtyMax: json['industrialQtyMax'] as int? ?? 3000,
      initTurns: json['initTurns'] as int? ?? 1000,
      initCredits: json['initCredits'] as int? ?? 1000000,
      initHolds: json['initHolds'] as int? ?? 50,
      initDrones: json['initDrones'] as int? ?? 100,
      pirateDensity: (json['pirateDensity'] as num?)?.toDouble() ?? 0.05,
      npcStartingCredits: json['npcStartingCredits'] as int? ?? 10000,
      tacticalDisplaySpeed:
          (json['tacticalDisplaySpeed'] as num?)?.toDouble() ?? 0.5,
      fullscreen: json['fullscreen'] as bool? ?? false,
      windowScale: (json['windowScale'] as num?)?.toDouble() ?? 0.75,
      resolutionWidth: json['resolutionWidth'] as int? ?? 1280,
      resolutionHeight: json['resolutionHeight'] as int? ?? 720,
      fontFamily: json['fontFamily'] as String? ?? '',
      fontSize: (json['fontSize'] as num?)?.toDouble() ?? 14,
      musicVolume: (json['musicVolume'] as num?)?.toDouble() ?? 0.5,
      sfxVolume: (json['sfxVolume'] as num?)?.toDouble() ?? 0.7,
      musicFolderPath: json['musicFolderPath'] as String? ?? 'assets/music',
    );
  }

  static List<String> _defaultAnomalies() => [
        'Asteroid Field',
        'Nebula',
        'Debris Field',
        'Gravity Well',
        'Radiation Storm',
        'Dark Matter Cloud',
      ];
}
