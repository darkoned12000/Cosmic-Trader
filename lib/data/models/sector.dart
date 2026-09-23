import 'package:tradewars_2050/data/models/planet.dart';
import 'package:tradewars_2050/data/models/port.dart';

/// Represents a sector in the game universe.
class Sector {
  final int id;
  final String name;
  double x;
  double y;
  final List<int> warpRoutes;

  // Content fields are mutable so the generator can populate them
  bool hasPort;
  bool hasPlanet;
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
  Planet? planet;

  Sector({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.warpRoutes,
    this.hasPort = false,
    this.hasPlanet = false,
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
    this.planet,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
      'warpRoutes': warpRoutes,
      'hasPort': hasPort,
      'hasPlanet': hasPlanet,
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
      if (planet != null) 'planet': planet!.toJson(),
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
      hasPlanet: json['hasPlanet'] as bool? ?? false,
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
      planet: json['planet'] != null
          ? Planet.fromJson(json['planet'] as Map<String, dynamic>)
          : null,
    );
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
