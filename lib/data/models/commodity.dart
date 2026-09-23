/// Configuration for a single tradeable commodity.
class CommodityConfig {
  final String name;
  final String displayName;
  final double priceMin;
  final double priceMax;
  final int qtyMin;
  final int qtyMax;

  const CommodityConfig({
    required this.name,
    required this.displayName,
    required this.priceMin,
    required this.priceMax,
    required this.qtyMin,
    required this.qtyMax,
  });

  /// The guaranteed split point between sell and buy price ranges.
  /// Selling ports use [priceMin, splitPoint),
  /// buying ports use [splitPoint, priceMax].
  double get splitPoint => (priceMin + priceMax) / 2;

  Map<String, dynamic> toJson() => {
        'name': name,
        'displayName': displayName,
        'priceMin': priceMin,
        'priceMax': priceMax,
        'qtyMin': qtyMin,
        'qtyMax': qtyMax,
      };

  factory CommodityConfig.fromJson(Map<String, dynamic> json) =>
      CommodityConfig(
        name: json['name'] as String,
        displayName: json['displayName'] as String? ?? json['name'] as String,
        priceMin: (json['priceMin'] as num).toDouble(),
        priceMax: (json['priceMax'] as num).toDouble(),
        qtyMin: (json['qtyMin'] as num).toInt(),
        qtyMax: (json['qtyMax'] as num).toInt(),
      );
}

/// Central registry of all tradeable commodities.
/// Add a new entry here to introduce a new commodity to the game economy.
class CommodityRegistry {
  CommodityRegistry._();

  static const List<CommodityConfig> defaults = [
    CommodityConfig(
      name: 'minerals',
      displayName: 'Minerals',
      priceMin: 10,
      priceMax: 75,
      qtyMin: 10000,
      qtyMax: 80000,
    ),
    CommodityConfig(
      name: 'organics',
      displayName: 'Organics',
      priceMin: 80,
      priceMax: 150,
      qtyMin: 5000,
      qtyMax: 70000,
    ),
    CommodityConfig(
      name: 'industrial',
      displayName: 'Industrial',
      priceMin: 160,
      priceMax: 300,
      qtyMin: 3000,
      qtyMax: 60000,
    ),
  ];

  static List<String> get names =>
      defaults.map((c) => c.name).toList(growable: false);

  static const Map<String, CommodityConfig> defaultsMap = {
    'minerals': CommodityConfig(
      name: 'minerals',
      displayName: 'Minerals',
      priceMin: 10,
      priceMax: 75,
      qtyMin: 10000,
      qtyMax: 80000,
    ),
    'organics': CommodityConfig(
      name: 'organics',
      displayName: 'Organics',
      priceMin: 80,
      priceMax: 150,
      qtyMin: 5000,
      qtyMax: 70000,
    ),
    'industrial': CommodityConfig(
      name: 'industrial',
      displayName: 'Industrial',
      priceMin: 160,
      priceMax: 300,
      qtyMin: 3000,
      qtyMax: 60000,
    ),
  };

  /// Returns a mutable deep copy of the defaults map.
  static Map<String, CommodityConfig> freshDefaults() =>
      Map.fromEntries(defaultsMap.entries.map((e) => MapEntry(
          e.key,
          CommodityConfig(
            name: e.value.name,
            displayName: e.value.displayName,
            priceMin: e.value.priceMin,
            priceMax: e.value.priceMax,
            qtyMin: e.value.qtyMin,
            qtyMax: e.value.qtyMax,
          ))));
}
