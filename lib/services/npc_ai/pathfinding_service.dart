import 'package:cosmic_trader/data/models/sector.dart';

class _PathNode {
  final int sectorId;
  final List<int> path;
  _PathNode(this.sectorId, this.path);
}

class PathfindingService {
  /// BFS shortest path from [startId] to [targetId].
  /// Returns list of sector IDs forming the path (inclusive), or null if
  /// unreachable.
  static List<int>? findPath(List<Sector> sectors, int startId, int targetId) {
    if (startId == targetId) return [startId];

    final visited = <int>{startId};
    final queue = <_PathNode>[
      _PathNode(startId, [startId])
    ];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final s = sectors[current.sectorId - 1];

      for (final nId in s.warpRoutes) {
        if (nId == targetId) {
          return [...current.path, nId];
        }
        if (!visited.contains(nId)) {
          visited.add(nId);
          queue.add(_PathNode(nId, [...current.path, nId]));
        }
      }
    }

    return null;
  }

  /// Distance in hops between two sectors.
  static int distance(List<Sector> sectors, int a, int b) {
    final path = findPath(sectors, a, b);
    return path != null ? path.length - 1 : 9999;
  }

  /// Find nearest sector matching a predicate, starting from [startId].
  static int? findNearestWhere(
      List<Sector> sectors, int startId, bool Function(Sector) predicate) {
    final visited = <int>{startId};
    final queue = [startId];

    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final s = sectors[current - 1];

      if (predicate(s) && s.id != startId) return s.id;

      for (final nId in s.warpRoutes) {
        if (visited.add(nId)) queue.add(nId);
      }
    }
    return null;
  }
}
