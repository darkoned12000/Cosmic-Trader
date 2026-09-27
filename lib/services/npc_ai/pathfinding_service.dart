import 'package:cosmic_trader/data/models/sector.dart';

class _PathNode {
  final int sectorId;
  final List<int> path;
  _PathNode(this.sectorId, this.path);
}

class PathfindingService {
  /// Shared sector index for tick-scoped work (P2 scaling batch). Set by
  /// `NpcAiService.beginTick`, cleared by `endTick`. Every lookup below
  /// prefers it and falls back to a locally built map, so direct callers
  /// (tests, one-off UI paths) behave identically without setup.
  static Map<int, Sector>? sharedIndex;

  static Map<int, Sector> _indexOf(List<Sector> sectors) =>
      sharedIndex ?? {for (final s in sectors) s.id: s};

  /// BFS shortest path from [startId] to [targetId].
  /// Returns list of sector IDs forming the path (inclusive), or null if
  /// unreachable. Looks sectors up by id (not list position) so sparse or
  /// unordered lists work.
  static List<int>? findPath(List<Sector> sectors, int startId, int targetId) {
    if (startId == targetId) return [startId];

    final byId = _indexOf(sectors);
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

    final byId = _indexOf(sectors);
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
    final byId = _indexOf(sectors);
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

  /// BFS parent map from [startId] (P2 scaling batch): one O(n) pass
  /// answers every distance/path query out of the source, replacing the
  /// O(m²) pairwise `findPath` loops in trade evaluation and border-hold
  /// search. Maps each reachable sector to its BFS predecessor; the
  /// source maps to itself. Unreachable sectors are absent.
  static Map<int, int> bfsParents(List<Sector> sectors, int startId) {
    final byId = _indexOf(sectors);
    final parents = <int, int>{};
    if (!byId.containsKey(startId)) return parents;
    parents[startId] = startId;
    final queue = [startId];
    var queueIdx = 0;
    while (queueIdx < queue.length) {
      final current = queue[queueIdx++];
      for (final nId in byId[current]?.warpRoutes ?? const <int>[]) {
        if (!parents.containsKey(nId) && byId.containsKey(nId)) {
          parents[nId] = current;
          queue.add(nId);
        }
      }
    }
    return parents;
  }

  /// Hops from a [bfsParents] tree, or null when unreachable.
  static int? distanceInTree(Map<int, int> parents, int targetId) {
    if (!parents.containsKey(targetId)) return null;
    var hops = 0;
    var node = targetId;
    while (parents[node] != node) {
      node = parents[node]!;
      hops++;
    }
    return hops;
  }

  /// Path from a [bfsParents] tree (inclusive), or null when unreachable.
  static List<int>? pathInTree(
      Map<int, int> parents, int startId, int targetId) {
    if (!parents.containsKey(targetId)) return null;
    final path = [targetId];
    var node = targetId;
    while (node != startId) {
      node = parents[node]!;
      path.add(node);
    }
    return path.reversed.toList();
  }
}
