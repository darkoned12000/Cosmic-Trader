import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';

/// Represents a sector in the game universe.
class Sector {
  final int id;
  final String name;
  double x;
  double y;
  final List<int> warpRoutes;

  // Content fields are mutable so the generator can populate them
  bool hasPort;
  String? anomaly;
  int traderCount;
  int duranCount;
  int vinariCount;
  int pirateCount;

  bool navHaz;
  bool hasBeacon;
  String? beaconOwner;
  String? beaconText;

  // --- New structured content ---
  Port? port;

  /// Every world in this sector, up to the universe's `planetsPerSector`.
  ///
  /// Was a single `Planet?`. Three worlds per sector is the point: the
  /// complementarity loop (an Ocean feeding a Lava, an Earth feeding both) only
  /// feels good when the worlds are adjacent, and hauling organics to the next
  /// world in your own sector is trivial where hauling across the galaxy is a
  /// chore you route around.
  ///
  /// A world is never removed from this list, only marked `isDestroyed` — see
  /// [destroy] in `Planet` and the collision roll in the design doc. Removal from
  /// a list mid-iteration is a bug factory, and a destroyed world still has to be
  /// drawn, scanned and argued about.
  List<Planet> planets;

  /// Worlds still fit to colonise — everything in [planets] that is intact.
  List<Planet> get livingPlanets =>
      planets.where((p) => !p.isDestroyed).toList(growable: false);

  bool get hasPlanet => planets.isNotEmpty;

  /// The first world in the sector, for UI summaries that do not care which.
  ///
  /// **Never use this to find a homeworld or a capital.** A sector can hold a
  /// faction's capital *and* a frontier world, and `repopulation` and
  /// `colonist_supply` both need the capital specifically — reading slot 0 would
  /// silently pick a neighbour. Those go through `RepopulationService
  /// .homeworldSectors`, which searches every world in every sector.
  Planet? get primaryPlanet => planets.isEmpty ? null : planets.first;

  /// The world's homeworld if this sector holds one, else null.
  ///
  /// A convenience over `planets.firstWhereOrNull((p) => p.isHomeworld)`, which
  /// is the only correct way to ask the question now.
  Planet? get homeworld {
    for (final p in planets) {
      if (p.isHomeworld) return p;
    }
    return null;
  }

  Sector({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.warpRoutes,
    this.hasPort = false,
    this.anomaly,
    this.traderCount = 0,
    this.duranCount = 0,
    this.vinariCount = 0,
    this.pirateCount = 0,
    this.navHaz = false,
    this.hasBeacon = false,
    this.beaconOwner,
    this.beaconText,
    this.port,
    List<Planet>? planets,
    // Legacy single-world constructor argument. Still accepted so the generator
    // and every test fixture read naturally; folded into [planets] below.
    Planet? planet,
  }) : planets = planets ?? (planet == null ? <Planet>[] : <Planet>[planet]);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
      'warpRoutes': warpRoutes,
      'hasPort': hasPort,
      'anomaly': anomaly,
      'traderCount': traderCount,
      'duranCount': duranCount,
      'vinariCount': vinariCount,
      'pirateCount': pirateCount,
      'navHaz': navHaz,
      'hasBeacon': hasBeacon,
      'beaconOwner': beaconOwner,
      'beaconText': beaconText,
      if (port != null) 'port': port!.toJson(),
      if (planets.isNotEmpty)
        'planets': planets.map((p) => p.toJson()).toList(),
    };
  }

  factory Sector.fromJson(Map<String, dynamic> json) {
    return Sector(
      id: json['id'] as int,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      warpRoutes:
          (json['warpRoutes'] as List<dynamic>).map((e) => e as int).toList(),
      hasPort: json['hasPort'] as bool? ?? false,
      anomaly: json['anomaly'] as String?,
      traderCount: json['traderCount'] as int? ?? 0,
      duranCount: json['duranCount'] as int? ?? 0,
      vinariCount: json['vinariCount'] as int? ?? 0,
      pirateCount: json['pirateCount'] as int? ?? 0,
      navHaz: json['navHaz'] as bool? ?? false,
      hasBeacon: json['hasBeacon'] as bool? ?? false,
      beaconOwner: json['beaconOwner'] as String?,
      beaconText: json['beaconText'] as String?,
      port: json['port'] != null
          ? Port.fromJson(json['port'] as Map<String, dynamic>)
          : null,
      planets: _planetsFromJson(json),
    );
  }

  /// Reads the world list, migrating a pre-multi-planet save.
  ///
  /// A legacy sector has a single `planet` object and no `planets` array. It
  /// loads into a one-element list, which is exactly right: that save *did* have
  /// one world, and pretending otherwise would lose it.
  ///
  /// `hasPlanet` is deliberately ignored rather than trusted. It is a second
  /// source of truth for something [planets] already answers, and in a legacy
  /// save it can disagree with `planet` — a sector flagged `hasPlanet: true`
  /// with a missing `planet` object would otherwise lose its world silently.
  /// Deriving it from the list is the same lesson as `hasPlanet` becoming a
  /// getter: one source of truth for a fact that is stored twice.
  static List<Planet> _planetsFromJson(Map<String, dynamic> json) {
    final raw = json['planets'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Planet.fromJson)
          .toList(growable: true);
    }
    final legacy = json['planet'];
    if (legacy is Map<String, dynamic>) {
      return <Planet>[Planet.fromJson(legacy)];
    }
    return <Planet>[];
  }

  static const int _gridSize = 5;
  static const int _offset = 100;

  static String _colLetter(int n) {
    String result = '';
    int m = n;
    while (true) {
      result = String.fromCharCode(65 + m % 26) + result;
      m = m ~/ 26;
      if (m <= 0) break;
      m--;
    }
    return result;
  }

  /// Quadrant name derived from the coordinate grid.
  String get quadrant {
    int col = (x / _gridSize).floor();
    int row = (y / _gridSize).floor();
    return '${_colLetter(col + _offset)}${row + _offset}';
  }

  int get totalNpcs => traderCount + duranCount + vinariCount + pirateCount;
}
