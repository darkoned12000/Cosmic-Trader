import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
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
  /// Routes in [avoidRoutes] ("buyId>sellId:commodity" keys from recent
  /// failures) are skipped so NPCs don't spin on doomed stale-price routes.
  /// When [credits] is given, routes whose buy leg costs more than the
  /// whole bankroll for a single unit are filtered out (root-cause guard
  /// for buy-phase debt).
  /// Sectors in [dangerSectors] (C2c: last-seen sectors of stronger
  /// vendetta targets) discount ranking — a route touching danger at
  /// either end scores half, both ends a quarter — so pilots prefer safe
  /// money without ever refusing the only money on the table.
  /// [preferredRoutes] (C2d: route keys with past profitable runs) boost
  /// ranking +5% per remembered win (capped at +25%): pilots learn what
  /// works, the positive mirror of the failed-route cooldown.
  static TradeRoute? findBestTradeRoute(
    int currentSectorId,
    Map<int, PortInfo> knownPorts,
    List<Sector> universe,
    int maxTravelDistance, {
    Set<String> avoidRoutes = const {},
    double? credits,
    FactionClass? actorFaction,
    Map<String, int> standings = const {},
    Set<int> dangerSectors = const {},
    Map<String, int> preferredRoutes = const {},
  }) {
    if (knownPorts.length < 2) return null;

    final routes = <TradeRoute>[];
    final ports = knownPorts.entries.toList();

    // Paths hoisted out of the inner loops (P2): toBuy costs one BFS per
    // buy port, and each buy port fans out ONE BFS tree answering every
    // buy→sell distance — m + m BFS passes, not m + m² findPath calls.
    // Trees are per-call locals: the universe mutates between ticks, so
    // nothing is shared across selections.
    final toBuyHops = <int, int>{};
    for (final buySector in ports) {
      final toBuy =
          PathfindingService.findPath(universe, currentSectorId, buySector.key);
      if (toBuy == null) continue;
      toBuyHops[buySector.key] = toBuy.length - 1;
    }
    final sellTrees = <int, Map<int, int>>{};

    for (int i = 0; i < ports.length; i++) {
      for (int j = 0; j < ports.length; j++) {
        if (i == j) continue;

        final buySector = ports[i];
        final sellSector = ports[j];
        final toBuy = toBuyHops[buySector.key];
        if (toBuy == null) continue;

        final tree = sellTrees.putIfAbsent(
          buySector.key,
          () => PathfindingService.bfsParents(universe, buySector.key),
        );
        final toSell = PathfindingService.distanceInTree(tree, sellSector.key);
        if (toSell == null) continue;

        final buyPort = buySector.value;
        final sellPort = sellSector.value;

        for (final commodity in commodities) {
          if (!buyPort.sellPrices.containsKey(commodity)) continue;
          if (!sellPort.buyPrices.containsKey(commodity)) continue;
          if (avoidRoutes
              .contains('${buySector.key}>${sellSector.key}:$commodity')) {
            continue;
          }

          final buyStanding = actorFaction == null
              ? 0
              : FactionStanding.resolveFor(
                  actorFaction, buyPort.ownerFaction, standings);
          final sellStanding = actorFaction == null
              ? 0
              : FactionStanding.resolveFor(
                  actorFaction, sellPort.ownerFaction, standings);
          final buyPrice =
              buyPort.getEffectiveSellPrice(commodity, standing: buyStanding);
          final sellPrice =
              sellPort.getEffectiveBuyPrice(commodity, standing: sellStanding);
          final profitPerUnit = sellPrice - buyPrice;

          if (profitPerUnit <= 0) continue;
          if (credits != null && buyPrice > credits) continue;

          final totalHops = toBuy + toSell;
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

    double score(TradeRoute r) {
      var s = r.profitPerHop;
      if (dangerSectors.contains(r.buySectorId)) s *= 0.5;
      if (dangerSectors.contains(r.sellSectorId)) s *= 0.5;
      final wins = preferredRoutes[
          NpcMemory.routeKey(r.buySectorId, r.sellSectorId, r.commodity)];
      if (wins != null && wins > 0) {
        s *= 1 + 0.05 * wins.clamp(1, 5);
      }
      return s;
    }

    routes.sort((a, b) => score(b).compareTo(score(a)));
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
