import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';

class TradeRoute {
  final int buySectorId;
  final int sellSectorId;
  final String commodity;
  final double buyPrice;
  final double sellPrice;
  final double profitPerUnit;
  final int totalHops;

  const TradeRoute({
    required this.buySectorId,
    required this.sellSectorId,
    required this.commodity,
    required this.buyPrice,
    required this.sellPrice,
    required this.profitPerUnit,
    required this.totalHops,
  });

  double get profitPerHop => profitPerUnit / (totalHops + 1);
}

class TradeEvaluator {
  /// Commodities in the game economy.
  static List<String> get commodities => CommodityRegistry.names;

  /// Find the best trade route from discovered ports.
  ///
  /// Returns null if no profitable route is reachable within [maxTravelDistance].
  static TradeRoute? findBestTradeRoute(
    int currentSectorId,
    Map<int, PortInfo> knownPorts,
    List<Sector> universe,
    int maxTravelDistance,
  ) {
    if (knownPorts.length < 2) return null;

    final routes = <TradeRoute>[];
    final ports = knownPorts.entries.toList();

    for (int i = 0; i < ports.length; i++) {
      for (int j = 0; j < ports.length; j++) {
        if (i == j) continue;

        final buySector = ports[i];
        final sellSector = ports[j];
        final buyPort = buySector.value;
        final sellPort = sellSector.value;

        for (final commodity in commodities) {
          if (!buyPort.sellPrices.containsKey(commodity)) continue;
          if (!sellPort.buyPrices.containsKey(commodity)) continue;

          final buyPrice = buyPort.getEffectiveSellPrice(commodity);
          final sellPrice = sellPort.getEffectiveBuyPrice(commodity);
          final profitPerUnit = sellPrice - buyPrice;

          if (profitPerUnit <= 0) continue;

          final toBuy = PathfindingService.findPath(
              universe, currentSectorId, buySector.key);
          if (toBuy == null) continue;

          final toSell = PathfindingService.findPath(
              universe, buySector.key, sellSector.key);
          if (toSell == null) continue;

          final totalHops = toBuy.length - 1 + toSell.length - 1;
          if (totalHops > maxTravelDistance) continue;

          routes.add(TradeRoute(
            buySectorId: buySector.key,
            sellSectorId: sellSector.key,
            commodity: commodity,
            buyPrice: buyPrice,
            sellPrice: sellPrice,
            profitPerUnit: profitPerUnit,
            totalHops: totalHops,
          ));
        }
      }
    }

    if (routes.isEmpty) return null;

    routes.sort((a, b) => b.profitPerHop.compareTo(a.profitPerHop));
    return routes.first;
  }

  /// Find the nearest port sector from [currentSectorId].
  static int? findNearestPort(
    int currentSectorId,
    List<Sector> universe,
  ) {
    return PathfindingService.findNearestWhere(
      universe,
      currentSectorId,
      (s) => s.hasPort,
    );
  }
}
