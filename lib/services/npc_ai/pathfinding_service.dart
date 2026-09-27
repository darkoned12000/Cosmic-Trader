import 'package:cosmic_trader/data/models/sector.dart';

class _PathNode {
  final int sectorId;
  final List<int> path;
  _PathNode(this.sectorId, this.path);
}

class PathfindingService {
  /// BFS shortest path from [startId] to [targetId].
  /// Returns list of sector IDs forming the path (inclusive), or null if
  /// unreachable. Looks sectors up by id (not list position) so sparse or
  /// unordered lists work.
  static List<int>? findPath(List<Sector> sectors, int startId, int targetId) {
    if (startId == targetId) return [startId];

    final byId = {for (final s in sectors) s.id: s};
    if (!byId.containsKey(startId) || !byId.containsKey(targetId)) {
      return null;
    }

    final visited = <int>{startId};
    final queue = <_PathNode>[
      _PathNode(startId, [startId])
    ];

    // Index pointer, not removeAt(0) (review batch 3, P2): draining
    // from the front is O(n) per pop.
    var queueIdx = 0;
    while (queueIdx < queue.length) {
      final current = queue[queueIdx++];
      final s = byId[current.sectorId];
      if (s == null) continue;

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

  /// BFS shortest path that avoids [avoid] sectors (C2c avoidance
  /// reroutes). Endpoints are never avoided — a goal inside a feared
  /// sector still terminates there; only the transit bends around.
  /// Falls back to the plain shortest path when every route crosses
  /// feared space, so avoidance never strands an NPC that could move.
  static List<int>? findPathAvoiding(
    List<Sector> sectors,
    int startId,
    int targetId,
    Set<int> avoid,
  ) {
    if (avoid.isEmpty) return findPath(sectors, startId, targetId);
    if (startId == targetId) return [startId];

    final byId = {for (final s in sectors) s.id: s};
    if (!byId.containsKey(startId) || !byId.containsKey(targetId)) {
      return null;
    }

    final visited = <int>{startId};
    final queue = <_PathNode>[
      _PathNode(startId, [startId])
    ];

    // Index pointer, not removeAt(0) (review batch 3, P2).
    var queueIdx = 0;
    while (queueIdx < queue.length) {
      final current = queue[queueIdx++];
      final s = byId[current.sectorId];
      if (s == null) continue;

      for (final nId in s.warpRoutes) {
        if (nId == targetId) {
          return [...current.path, nId];
        }
        if (avoid.contains(nId)) continue;
        if (!visited.contains(nId)) {
          visited.add(nId);
          queue.add(_PathNode(nId, [...current.path, nId]));
        }
      }
    }

    return findPath(sectors, startId, targetId);
  }

  /// Find nearest sector matching a predicate, starting from [startId].
  static int? findNearestWhere(
      List<Sector> sectors, int startId, bool Function(Sector) predicate) {
    final byId = {for (final s in sectors) s.id: s};
    if (!byId.containsKey(startId)) return null;
    final visited = <int>{startId};
    final queue = [startId];

    var queueIdx = 0;
    while (queueIdx < queue.length) {
      final current = queue[queueIdx++];
      final s = byId[current];
      if (s == null) continue;

      if (predicate(s) && s.id != startId) return s.id;

      for (final nId in s.warpRoutes) {
        if (visited.add(nId)) queue.add(nId);
      }
    }
    return null;
  }
}
