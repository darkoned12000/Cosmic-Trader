import 'package:cosmic_trader/data/models/faction.dart';

class FactionStanding {
  final Map<FactionClass, int> standings;

  const FactionStanding({required this.standings});

  static const Map<FactionClass, Map<FactionClass, int>> defaults = {
    FactionClass.duran: {
      FactionClass.duran: 50,
      FactionClass.vinari: -60,
      FactionClass.trader: -10,
      FactionClass.pirate: -40,
    },
    FactionClass.vinari: {
      FactionClass.vinari: 50,
      FactionClass.duran: -60,
      FactionClass.trader: 30,
      FactionClass.pirate: -50,
    },
    FactionClass.trader: {
      FactionClass.trader: 30,
      FactionClass.duran: -10,
      FactionClass.vinari: 30,
      FactionClass.pirate: -60,
    },
    FactionClass.pirate: {
      FactionClass.pirate: -20,
      FactionClass.duran: -40,
      FactionClass.vinari: -50,
      FactionClass.trader: -60,
    },
  };

  factory FactionStanding.defaultFor(FactionClass faction) {
    return FactionStanding(
      standings: Map.from(defaults[faction] ?? const {}),
    );
  }

  static bool isHostile(FactionClass a, FactionClass b, int standing) {
    return standing < -30;
  }

  static int modifyStanding(int current, int delta) {
    return (current + delta).clamp(-100, 100);
  }

  FactionStanding withModification(FactionClass faction, int delta) {
    final updated = Map<FactionClass, int>.from(standings);
    updated[faction] = modifyStanding(
      updated[faction] ?? 0,
      delta,
    );
    return FactionStanding(standings: updated);
  }

  Map<String, dynamic> toJson() {
    return standings.map((k, v) => MapEntry(k.name, v));
  }

  factory FactionStanding.fromJson(Map<String, dynamic> json) {
    return FactionStanding(
      standings: json.map(
        (k, v) => MapEntry(
          FactionClass.values.firstWhere(
            (e) => e.name == k,
            orElse: () => FactionClass.trader,
          ),
          (v as num).toInt(),
        ),
      ),
    );
  }
}
