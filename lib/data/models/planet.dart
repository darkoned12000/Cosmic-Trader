/// Represents a planet within a sector.
class Planet {
  final String name;
  final PlanetClass planetClass;
  final double productionEfficiency;

  const Planet({
    required this.name,
    required this.planetClass,
    required this.productionEfficiency,
  });

  /// Returns the dominant commodity for this planet class.
  String getDominantCommodity() {
    switch (planetClass) {
      case PlanetClass.mammat:
        return 'minerals';
      case PlanetClass.kron:
        return 'industrial';
      case PlanetClass.slyland:
        return 'organics';
      case PlanetClass.human:
        return 'industrial';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'planetClass': planetClass.name,
      'productionEfficiency': productionEfficiency,
    };
  }

  factory Planet.fromJson(Map<String, dynamic> json) {
    return Planet(
      name: json['name'] as String? ?? 'Unknown Planet',
      planetClass: _parsePlanetClass(json['planetClass'] as String?),
      productionEfficiency:
          (json['productionEfficiency'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Planet classification based on dominant faction/control.
enum PlanetClass {
  mammat, // M-class
  kron, // K-class
  slyland, // L-class
  human, // H-class
}

PlanetClass _parsePlanetClass(String? name) {
  if (name == null) return PlanetClass.human;
  try {
    return PlanetClass.values.byName(name);
  } on ArgumentError {
    return PlanetClass.human;
  }
}
