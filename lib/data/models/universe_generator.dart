import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';

/// Generates a connected universe of sectors using the classic
/// Classic BBS-era space-trading-inspired algorithm.
///
/// All warps are bidirectional and the graph is fully static after
/// generation (same seed = same universe, same paths).
///   1) Initialize all sectors with empty warps, port=null, planets=[], etc.
///   2) Place special Class 0 port at sector 1 (Terra Prime).
///   3) Assign NavHaz / Anomaly flags (outside FedSpace).
///   4) Build FedSpace hub.
///   5) General warp connections (distance‑weighted, at least 1 each).
///   6) Orphaned sector correction pass (every sector must have >= 1 warp).
///   7) Balance warp distribution to match the configured percentages.
///   8) Random port generation by class density.
///   9) Planet / NPC / alien assignment.
class UniverseGenerator {
  final GameSettings settings;

  /// Hard upper bound for warp connections per sector (matches pct7Warp).
  static const int _maxWarpCount = 7;

  UniverseGenerator(this.settings);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  List<Sector> generate() {
    final rng = settings.getRng();
    final sectors = <Sector>[];
    final npcs = <NpcShip>[];

    // === Phase 1: initialise all sectors with empty data ===
    _initSectors(sectors, rng);

    // === Phase 2: special Class 0 port at sector 1 ===
    _placeTerraPrime(sectors);

    // === Phase 3: NavHaz / Anomaly (outside FedSpace) ===
    _assignNavHazAnomaly(sectors, rng);

    // === Phase 4: FedSpace hub (sectors 1-7 fully connected; 8-10 → hub) ===
    _buildFedSpace(sectors, rng);

    // === Phase 5: general warp connections ===
    _buildGeneralWarps(sectors, rng);

    // === Phase 6: orphaned sector correction ===
    _fixOrphans(sectors, rng);

    // === Phase 6b: ensure the entire graph is one connected component ===
    _ensureConnected(sectors, rng);

    // === Phase 6c: balance warp distribution to match configured %s ===
    _balanceDistribution(sectors, rng);
    _ensureConnected(sectors, rng);

    // === Phase 7: port generation ===
    _assignPorts(sectors, rng);

    // === Phase 7b: Hardware Emporiums (~5% of ports) ===
    _assignHardwareEmporiums(sectors, rng);

    // === Phase 8: planets, NPCs, aliens ===
    _assignPlanets(sectors, rng);
    _assignNpcsAndAliens(sectors, rng);

    // === Phase 9: persistent NPC generation ===
    _generateNpcs(sectors, npcs, rng);

    return sectors;
  }

  // ---------------------------------------------------------------------------
  // Phase 1 – Init
  // ---------------------------------------------------------------------------

  void _initSectors(List<Sector> sectors, math.Random rng) {
    for (int id = 1; id <= settings.totalSectors; id++) {
      sectors.add(Sector(
        id: id,
        name: _sectorName(id, rng),
        x: 0,
        y: 0,
        warpRoutes: [],
        hasPort: false,
        hasPlanet: false,
        navHaz: false,
      ));
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 2 – Special port at sector 1
  // ---------------------------------------------------------------------------

  void _placeTerraPrime(List<Sector> sectors) {
    final s1 = sectors[0];
    s1.hasPort = true;
    s1.port = _createPort(s1, math.Random(42),
        forceFederal: true, name: 'Terra Prime');
  }

  // ---------------------------------------------------------------------------
  // Phase 3 – NavHaz / Anomaly
  // ---------------------------------------------------------------------------

  void _assignNavHazAnomaly(List<Sector> sectors, math.Random rng) {
    for (final s in sectors) {
      // FedSpace sectors are safe
      if (s.id <= settings.fedSpaceEnd) continue;

      // NavHaz probability
      if (rng.nextDouble() < 0.15) {
        s.navHaz = true;
      }

      // Anomaly probability (independent of navHaz)
      if (rng.nextDouble() < settings.anomalyDensity) {
        s.anomaly =
            settings.anomalyTypes[rng.nextInt(settings.anomalyTypes.length)];
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 4 – FedSpace hub
  // ---------------------------------------------------------------------------

  void _buildFedSpace(List<Sector> sectors, math.Random rng) {
    final fedEnd = math.min(settings.fedSpaceEnd, sectors.length);
    if (fedEnd < 1) return;

    // Sectors 1-7: each connects to 2-3 other FedSpace sectors (NOT fully
    // connected), leaving room for external connections from the general warp
    // phase.
    final hubEnd = math.min(7, fedEnd);
    for (int i = 1; i <= hubEnd; i++) {
      final a = sectors[i - 1];
      final others = List<int>.generate(hubEnd, (idx) => idx + 1)
        ..remove(i)
        ..shuffle(rng);
      final target =
          2 + rng.nextInt(math.min(2, hubEnd - 1)); // 2-3 connections
      for (int k = 0; k < target && k < others.length; k++) {
        final b = sectors[others[k] - 1];
        if (!a.warpRoutes.contains(b.id)) a.warpRoutes.add(b.id);
        if (!b.warpRoutes.contains(a.id)) b.warpRoutes.add(a.id);
      }
    }

    // Sectors 8-fedEnd connect to 2-3 random hub sectors (existing behaviour)
    for (int i = hubEnd + 1; i <= fedEnd; i++) {
      final s = sectors[i - 1];
      final hubIds = List<int>.generate(hubEnd, (idx) => idx + 1);
      hubIds.shuffle(rng);
      final connections =
          hubIds.take(1 + rng.nextInt(math.min(2, hubIds.length))).toList();
      for (final h in connections) {
        final hub = sectors[h - 1];
        if (!s.warpRoutes.contains(hub.id)) s.warpRoutes.add(hub.id);
        if (!hub.warpRoutes.contains(s.id)) hub.warpRoutes.add(s.id);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 5 – General warp connections
  // ---------------------------------------------------------------------------

  void _buildGeneralWarps(List<Sector> sectors, math.Random rng) {
    // Assign coordinates first (we need distances)
    _assignCoordinates(sectors, rng);

    final n = sectors.length;

    for (int i = 0; i < n; i++) {
      final a = sectors[i];
      final currentWarps = a.warpRoutes.length;

      if (currentWarps >= _maxWarpCount) continue;

      // Build list of candidate sectors (not already connected, not self)
      final candidates = <_Candidate>[];
      for (int j = 0; j < n; j++) {
        if (i == j) continue;
        final b = sectors[j];
        if (a.warpRoutes.contains(b.id)) continue;
        // Avoid oversaturating b
        if (b.warpRoutes.length >= _maxWarpCount) continue;

        final dist = _distance(a.x, a.y, b.x, b.y);
        // Weight: closer is better. Use 1/(dist+1) as base weight.
        final weight = 1.0 / (dist + 1.0);
        candidates.add(_Candidate(b.id, weight));
      }

      // Give each sector at least 1 connection for basic connectivity.
      // The distribution-balancing phase fine-tunes to the exact targets.
      final want = math.max(0, 1 - currentWarps);
      if (want <= 0) continue;

      // Weighted random selection
      for (int w = 0; w < want && candidates.isNotEmpty; w++) {
        final totalWeight = candidates.fold(0.0, (sum, c) => sum + c.weight);
        if (totalWeight <= 0) break;

        double r = rng.nextDouble() * totalWeight;
        int pick = 0;
        for (int ci = 0; ci < candidates.length; ci++) {
          r -= candidates[ci].weight;
          if (r <= 0) {
            pick = ci;
            break;
          }
        }

        final chosen = candidates.removeAt(pick);
        final b = sectors[chosen.sectorId - 1];

        if (!a.warpRoutes.contains(b.id)) a.warpRoutes.add(b.id);
        if (!b.warpRoutes.contains(a.id)) b.warpRoutes.add(a.id);

        // Remove b from candidates (already connected)
        candidates.removeWhere((c) => c.sectorId == b.id);

        if (a.warpRoutes.length >= _maxWarpCount) break;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Coordinate assignment (grow from center with bubble clustering)
  // ---------------------------------------------------------------------------

  void _assignCoordinates(List<Sector> sectors, math.Random rng) {
    // Sector 1 at origin
    sectors[0].x = 0;
    sectors[0].y = 0;

    final placed = <int>{1};

    // Frontier: candidate positions adjacent to placed sectors
    final frontier = <_FrontierEntry>[];
    _expandFrontierFrom(sectors, frontier, sectors[0], rng);

    int nextSectorId = 2;
    while (nextSectorId <= sectors.length && frontier.isNotEmpty) {
      // Bubble: prefer entries near recently placed sectors
      final pick = _pickFrontierIndex(frontier, rng, nextSectorId);
      final entry = frontier.removeAt(pick);

      final sector = sectors[nextSectorId - 1];
      sector.x = entry.x;
      sector.y = entry.y;
      placed.add(sector.id);

      _expandFrontierFrom(sectors, frontier, sector, rng);

      // Keep frontier bounded
      if (frontier.length > settings.totalSectors * 4) {
        frontier.removeRange(
          0,
          frontier.length - settings.totalSectors * 2,
        );
      }

      nextSectorId++;
    }

    // Any sectors that didn't get coords get random offset from origin
    for (final s in sectors) {
      if (s.x == 0 && s.y == 0 && s.id != 1) {
        s.x = rng.nextDouble() * 20 - 10;
        s.y = rng.nextDouble() * 20 - 10;
      }
    }
  }

  void _expandFrontierFrom(
    List<Sector> sectors,
    List<_FrontierEntry> frontier,
    Sector sector,
    math.Random rng, {
    int maxAttempts = 6,
  }) {
    const dirs = [
      _Dir(1, 0),
      _Dir(-1, 0),
      _Dir(0, 1),
      _Dir(0, -1),
      _Dir(1, 1),
      _Dir(1, -1),
      _Dir(-1, 1),
      _Dir(-1, -1),
    ];

    final shuffled = List<_Dir>.from(dirs);
    shuffled.shuffle(rng);

    int attempts = 0;
    for (final d in shuffled) {
      if (attempts++ >= maxAttempts) break;
      final nx = (sector.x + d.dx).roundToDouble();
      final ny = (sector.y + d.dy).roundToDouble();

      if (_frontierHas(frontier, nx, ny)) continue;
      if (_sectorAt(sectors, nx, ny) != null) continue;

      frontier.add(_FrontierEntry(nx, ny, sector.id));
    }
  }

  int _pickFrontierIndex(
    List<_FrontierEntry> frontier,
    math.Random rng,
    int currentSectorId,
  ) {
    // Bubble clustering: with bubbleChance, prefer entries adjacent to
    // recently placed sectors
    if (rng.nextDouble() < settings.bubbleChance && frontier.length > 1) {
      final recentIds = <int>{};
      final lookback = math.min(5, currentSectorId);
      for (int i = currentSectorId - lookback; i < currentSectorId; i++) {
        recentIds.add(i);
      }
      final recent = frontier
          .asMap()
          .entries
          .where((e) => recentIds.contains(e.value.adjacentTo))
          .toList();
      if (recent.isNotEmpty) {
        return recent[rng.nextInt(recent.length)].key;
      }
    }
    return rng.nextInt(frontier.length);
  }

  // ---------------------------------------------------------------------------
  // Phase 6 – Orphaned sector correction
  // ---------------------------------------------------------------------------

  void _fixOrphans(List<Sector> sectors, math.Random rng) {
    for (final a in sectors) {
      if (a.warpRoutes.isNotEmpty) continue;

      // Find nearest sector that isn't already maxed out
      _Candidate? best;
      for (final b in sectors) {
        if (a.id == b.id) continue;
        if (b.warpRoutes.length >= _maxWarpCount) continue;
        if (a.warpRoutes.contains(b.id)) continue;

        final dist = _distance(a.x, a.y, b.x, b.y);
        final weight = 1.0 / (dist + 1.0);
        if (best == null || weight > best.weight) {
          best = _Candidate(b.id, weight);
        }
      }

      if (best != null) {
        final b = sectors[best.sectorId - 1];
        a.warpRoutes.add(b.id);
        b.warpRoutes.add(a.id);
      } else {
        // Desperate: connect to ANY other sector
        for (final b in sectors) {
          if (a.id == b.id) continue;
          if (a.warpRoutes.contains(b.id)) continue;
          a.warpRoutes.add(b.id);
          b.warpRoutes.add(a.id);
          break;
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 6b – Ensure full-graph connectivity
  // ---------------------------------------------------------------------------

  /// After all warps are placed, verify that every sector is reachable from
  /// sector 1.  Any disconnected component is stitched to the main graph by
  /// adding a single nearest-neighbour warp.
  void _ensureConnected(List<Sector> sectors, math.Random rng) {
    // BFS reachable set from sector 1
    var reachable = _bfsReachable(sectors, 1);

    while (reachable.length < sectors.length) {
      _Candidate? best;
      Sector? bestUnreachable;

      for (final s in sectors) {
        if (reachable.contains(s.id)) continue;

        for (final rId in reachable) {
          final r = sectors[rId - 1];
          if (r.warpRoutes.length >= _maxWarpCount) continue;

          final dist = _distance(s.x, s.y, r.x, r.y);
          final weight = 1.0 / (dist + 1.0);
          if (best == null || weight > best.weight) {
            best = _Candidate(r.id, weight);
            bestUnreachable = s;
          }
        }
      }

      if (bestUnreachable != null && best != null) {
        final r = sectors[best.sectorId - 1];
        bestUnreachable.warpRoutes.add(r.id);
        r.warpRoutes.add(bestUnreachable.id);
        reachable = _bfsReachable(sectors, 1);
      } else {
        break;
      }
    }
  }

  Set<int> _bfsReachable(List<Sector> sectors, int startId) {
    final visited = <int>{startId};
    final queue = [startId];
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      for (final n in sectors[current - 1].warpRoutes) {
        if (visited.add(n)) queue.add(n);
      }
    }
    return visited;
  }

  // ---------------------------------------------------------------------------
  // Phase 6c – Balance warp distribution to match configured percentages
  // ---------------------------------------------------------------------------

  /// Adjust the graph so the number of sectors at each warp count (1…7)
  /// matches the target percentages from [GameSettings].
  ///
  /// FedSpace sectors (~2‑3 connections) are protected from demotion below
  /// their current level so the FedSpace hub stays intact.
  void _balanceDistribution(List<Sector> sectors, math.Random rng) {
    final n = sectors.length;

    // --- target counts per warp level ---
    final targets = <int, int>{
      1: (settings.pct1Warp * n).round(),
      2: (settings.pct2Warp * n).round(),
      3: (settings.pct3Warp * n).round(),
      4: (settings.pct4Warp * n).round(),
      5: (settings.pct5Warp * n).round(),
      6: (settings.pct6Warp * n).round(),
      7: (settings.pct7Warp * n).round(),
    };

    // Normalise so the sum equals n.
    var sum = targets.values.fold(0, (a, b) => a + b);
    if (sum != n) {
      final diff = n - sum;
      int bestW = 1, bestCnt = targets[1]!;
      for (int w = 2; w <= 7; w++) {
        if (targets[w]! > bestCnt) {
          bestCnt = targets[w]!;
          bestW = w;
        }
      }
      targets[bestW] = targets[bestW]! + diff;
    }

    Map<int, int> currentCount() {
      final c = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0, 6: 0, 7: 0};
      for (final s in sectors) {
        final k = s.warpRoutes.length.clamp(1, _maxWarpCount);
        c[k] = (c[k] ?? 0) + 1;
      }
      return c;
    }

    bool isBalanced(Map<int, int> cur) {
      for (int w = 1; w <= _maxWarpCount; w++) {
        if (cur[w] != targets[w]) return false;
      }
      return true;
    }

    bool isFedSpace(Sector s) => s.id <= settings.fedSpaceEnd;

    /// Demote one sector at [level] by removing a single connection.
    /// Returns true if a demotion happened.
    bool demoteOne(int level) {
      Sector? candidate;
      for (final s in sectors) {
        if (s.warpRoutes.length != level) continue;
        if (isFedSpace(s) && level <= 2) continue; // protect hub
        candidate = s;
        break;
      }
      if (candidate == null) return false;

      // Remove a connection whose neighbour has the fewest warps.
      int? bestConn;
      int? bestWc;
      for (final conn in candidate.warpRoutes.toList()) {
        final nbr = sectors[conn - 1];
        if (nbr.warpRoutes.length <= 1) continue; // don't orphan nbr
        if (isFedSpace(nbr) && nbr.warpRoutes.length <= 2) continue;
        if (bestConn == null || nbr.warpRoutes.length < bestWc!) {
          bestConn = conn;
          bestWc = nbr.warpRoutes.length;
        }
      }
      if (bestConn == null) return false;

      sectors[bestConn - 1].warpRoutes.remove(candidate.id);
      candidate.warpRoutes.remove(bestConn);
      return true;
    }

    /// Promote one sector one level up by adding a connection.
    /// Returns true if a promotion happened.
    bool promoteOne(int targetLevel) {
      final srcLevel = targetLevel - 1;

      Sector? candidate;
      for (final s in sectors) {
        if (s.warpRoutes.length == srcLevel) {
          candidate = s;
          break;
        }
      }
      if (candidate == null) return false;
      if (candidate.warpRoutes.length >= _maxWarpCount) return false;

      // Find a non‑adjacent, distance‑weighted partner.
      _Candidate? best;
      for (final b in sectors) {
        if (b.id == candidate.id) continue;
        if (candidate.warpRoutes.contains(b.id)) continue;
        if (b.warpRoutes.length >= _maxWarpCount) continue;
        final dist = _distance(candidate.x, candidate.y, b.x, b.y);
        final weight = 1.0 / (dist + 1.0);
        if (best == null || weight > best.weight) {
          best = _Candidate(b.id, weight);
        }
      }
      if (best == null) return false;

      final b = sectors[best.sectorId - 1];
      candidate.warpRoutes.add(b.id);
      b.warpRoutes.add(candidate.id);
      return true;
    }

    // ---- main loop ----
    for (int iter = 0; iter < 100; iter++) {
      var cur = currentCount();
      if (isBalanced(cur)) break;

      // ** Demote over‑represented levels (7 → 2) **
      for (int w = _maxWarpCount; w >= 2; w--) {
        while (cur[w]! > targets[w]!) {
          if (!demoteOne(w)) break;
          cur = currentCount();
        }
      }

      // ** Promote under‑represented levels (2 → 7) **
      for (int w = 2; w <= _maxWarpCount; w++) {
        while (cur[w]! < targets[w]!) {
          if (!promoteOne(w)) break;
          cur = currentCount();
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Phase 7 – Port generation
  // ---------------------------------------------------------------------------

  void _assignPorts(List<Sector> sectors, math.Random rng) {
    // Ensure FedSpace sectors have ports (except sector 1 which already has
    // Terra Prime)
    for (final s in sectors) {
      if (s.id > 1 && s.id <= settings.fedSpaceEnd) {
        if (!s.hasPort) {
          s.hasPort = true;
          s.port = _createPort(s, rng, forceFederal: true);
        }
      }
    }

    // Random port generation outside FedSpace
    for (final s in sectors) {
      if (s.hasPort) continue;
      if (s.id <= settings.fedSpaceEnd) continue;

      if (rng.nextDouble() < settings.portDensity) {
        s.hasPort = true;
        s.port = _createPort(s, rng);
      }
    }
  }

  /// Converts ~5% of existing ports (outside FedSpace) into
  /// Hardware Emporiums — violet-hued ports that sell ships,
  /// equipment, and weapons instead of regular commodities.
  void _assignHardwareEmporiums(List<Sector> sectors, math.Random rng) {
    for (final s in sectors) {
      if (!s.hasPort) continue;
      if (s.id <= settings.fedSpaceEnd) continue;
      if (rng.nextDouble() >= settings.hardwareEmporiumDensity) continue;

      final heOwner = _pickPortOwner(s, rng);
      s.port = Port(
        name: _hardwareEmporiumName(s.id, rng),
        portClass: PortClass.hardwareEmporium,
        portType: null,
        buyPrices: const {},
        sellPrices: const {},
        supply: const {},
        demand: const {},
        defenseLevel: _pickDefenseLevel(rng),
        portCredits: 100000 + rng.nextDouble() * 900000,
        owner: heOwner,
        ownerFaction:
            _pickOwnerFaction(heOwner, PortClass.hardwareEmporium, rng),
      );
    }
  }

  String _hardwareEmporiumName(int sectorId, math.Random rng) {
    const names = [
      'Aegis',
      'Forge',
      'Anvil',
      'Vertex',
      'Aether',
      'Helix',
      'Nexus',
      'Orion',
      'Pulsar',
      'Quantum',
      'Solaris',
      'Titan',
      'Void',
      'Warptech',
      'Xenith',
    ];
    return '${names[sectorId % names.length]} Hardware Emporium';
  }

  /// Dynamically generates a random port type string
  /// based on how many commodities are configured.
  /// Ensures at least one 'S' and one 'B' character.
  String _randomPortType(math.Random rng) {
    final count = settings.commodityConfigs.length;
    final chars = List<String>.generate(count, (_) => '');
    // Pick at which indices to place the mandatory S and B.
    final sIdx = rng.nextInt(count);
    var bIdx = rng.nextInt(count);
    while (bIdx == sIdx) {
      bIdx = rng.nextInt(count);
    }
    for (int i = 0; i < count; i++) {
      chars[i] = (i == sIdx)
          ? 'S'
          : (i == bIdx)
              ? 'B'
              : (rng.nextBool() ? 'S' : 'B');
    }
    return chars.join();
  }

  Port _createPort(Sector sector, math.Random rng,
      {bool forceFederal = false, String? name}) {
    final portClass = forceFederal ? PortClass.federal : _pickPortClass(rng);
    final portType = _randomPortType(rng);
    final prices = _generatePortPrices(portType, rng);
    final qty = _generatePortQuantities(portType, rng);
    final defenseLevel = _pickDefenseLevel(rng);
    final portCredits = _calculatePortCredits(portType, prices, qty, rng);
    final owner = _pickPortOwner(sector, rng);
    final ownerFaction = _pickOwnerFaction(owner, portClass, rng);

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return Port(
      name: name ?? _portName(sector.id, rng),
      portClass: portClass,
      portType: portType,
      buyPrices: prices.buyPrices,
      sellPrices: prices.sellPrices,
      supply: qty.supply,
      demand: qty.demand,
      maxSupply: qty.supply,
      maxDemand: qty.demand,
      defenseLevel: defenseLevel,
      portCredits: portCredits,
      desiredCredits: portCredits,
      owner: owner,
      ownerFaction: ownerFaction,
      lastRegenTime: nowMs,
    );
  }

  /// Picks a random NPC owner for a port.
  /// Federal ports (Terra Prime / FedSpace) have no owner.
  /// ~40% of non-FedSpace ports get an NPC owner.
  String? _pickPortOwner(Sector sector, math.Random rng) {
    if (sector.id <= settings.fedSpaceEnd) return null;
    if (rng.nextDouble() > 0.4) return null;
    return _npcOwnerNames[rng.nextInt(_npcOwnerNames.length)];
  }

  /// Picks a faction for an NPC port owner, weighted by port class.
  /// Free ports lean Trader, independents lean Pirate/Duran.
  FactionClass? _pickOwnerFaction(
      String? ownerName, PortClass portClass, math.Random rng) {
    if (ownerName == null) return null;
    final r = rng.nextDouble();
    switch (portClass) {
      case PortClass.free:
        if (r < 0.50) return FactionClass.trader;
        if (r < 0.70) return FactionClass.vinari;
        if (r < 0.85) return FactionClass.duran;
        return FactionClass.pirate;
      case PortClass.independent:
        if (r < 0.35) return FactionClass.pirate;
        if (r < 0.60) return FactionClass.duran;
        if (r < 0.80) return FactionClass.trader;
        return FactionClass.vinari;
      case PortClass.federal:
        return null;
      case PortClass.hardwareEmporium:
        return FactionClass.values[rng.nextInt(FactionClass.values.length)];
    }
  }

  static const _npcOwnerNames = [
    'Trader Vex',
    'Captain Rourke',
    'Mama Duran',
    'The Vinari Council',
    'Ironclad Syndicate',
    'Starhaven Consortium',
    'Pirate King Zorblax',
    'Merchant Prince Orlan',
    'The Free Traders Alliance',
    'Void Runner Collective',
    'Shadow Commerce Guild',
    'Nebula Trading Co.',
  ];

  /// Picks a defense level 0-4.
  /// Level 0 (no defenses) is most common.
  /// Higher levels are progressively rarer.
  int _pickDefenseLevel(math.Random rng) {
    final r = rng.nextDouble();
    if (r < 0.35) return 0;
    if (r < 0.60) return 1;
    if (r < 0.80) return 2;
    if (r < 0.93) return 3;
    return 4;
  }

  /// Calculates port credits based on buying capacity.
  /// Ports need enough credits to purchase what they advertise.
  double _calculatePortCredits(String portType, _PortPrices prices,
      _PortQuantities qty, math.Random rng) {
    double neededCredits = 0;
    final configs = settings.commodityConfigs.values.toList();

    for (int i = 0; i < configs.length; i++) {
      if (portType[i] == 'B') {
        final buyPrice = prices.buyPrices[configs[i].name] ?? 0;
        final demand = qty.demand[configs[i].name] ?? 0;
        neededCredits += buyPrice * demand;
      }
    }

    // Add 20-50% buffer for flexibility
    final buffer = 1.2 + rng.nextDouble() * 0.3;
    return (neededCredits * buffer).roundToDouble();
  }

  PortClass _pickPortClass(math.Random rng) {
    final r = rng.nextDouble();
    if (r < 0.3) return PortClass.federal;
    if (r < 0.7) return PortClass.free;
    return PortClass.independent;
  }

  /// Generates non-overlapping buy/sell prices per commodity.
  ///
  /// Sell prices (port sells → player buys) occupy the lower half
  /// of the price range: [priceMin, splitPoint).
  /// Buy prices (port buys → player sells) occupy the upper half:
  /// [splitPoint, priceMax].
  ///
  /// This guarantees that no matter which two ports a player trades
  /// between, the sell price they pay is always lower than the buy
  /// price they receive — every trade is profitable.
  _PortPrices _generatePortPrices(String portType, math.Random rng) {
    final configs = settings.commodityConfigs.values.toList();

    final buyPrices = <String, double>{};
    final sellPrices = <String, double>{};

    for (int i = 0; i < configs.length; i++) {
      final c = configs[i];
      final split = c.splitPoint;
      if (portType[i] == 'S') {
        // Port sells to player: pick from lower half [priceMin, splitPoint)
        final maxSell = split - 0.01;
        if (maxSell <= c.priceMin) {
          sellPrices[c.name] = c.priceMin;
        } else {
          sellPrices[c.name] =
              (c.priceMin + rng.nextDouble() * (maxSell - c.priceMin))
                  .roundToDouble();
        }
      } else {
        // Port buys from player: pick from upper half [splitPoint, priceMax]
        buyPrices[c.name] =
            (split + rng.nextDouble() * (c.priceMax - split)).roundToDouble();
      }
    }

    return _PortPrices(buyPrices, sellPrices);
  }

  _PortQuantities _generatePortQuantities(String portType, math.Random rng) {
    final configs = settings.commodityConfigs.values.toList();

    final supply = <String, int>{};
    final demand = <String, int>{};

    for (int i = 0; i < configs.length; i++) {
      final c = configs[i];
      final qty = c.qtyMin + rng.nextInt(c.qtyMax - c.qtyMin + 1);
      if (portType[i] == 'S') {
        supply[c.name] = qty;
      } else {
        demand[c.name] = qty;
      }
    }

    return _PortQuantities(supply, demand);
  }

  // ---------------------------------------------------------------------------
  // Phase 8 – Planets, NPCs, aliens
  // ---------------------------------------------------------------------------

  void _assignPlanets(List<Sector> sectors, math.Random rng) {
    // FedSpace: guarantee planets in a few sectors
    for (final s in sectors) {
      if (s.id <= settings.fedSpaceEnd) {
        if (!s.hasPlanet && rng.nextDouble() < 0.5) {
          s.hasPlanet = true;
          s.planet = _createPlanet(s, rng);
        }
      }
    }

    for (final s in sectors) {
      if (s.hasPlanet) continue;
      if (rng.nextDouble() < settings.planetDensity) {
        s.hasPlanet = true;
        s.planet = _createPlanet(s, rng);
      }
    }

    _assignHomeworlds(sectors, rng);
  }

  void _assignHomeworlds(List<Sector> sectors, math.Random rng) {
    // Assign one homeworld per major faction (excluding pirate)
    final factions = [
      FactionClass.duran,
      FactionClass.vinari,
      FactionClass.trader,
    ];

    for (final faction in factions) {
      // Faction homeworld type preferences
      final preferredTypes = _homeworldTypes(faction);
      final candidates = <Sector>[];
      for (final s in sectors) {
        if (s.id <= settings.fedSpaceEnd) continue;
        if (!s.hasPlanet || s.planet == null) continue;
        if (preferredTypes.contains(s.planet!.planetType)) {
          candidates.add(s);
        }
      }
      // Pick a random preferred sector, or any planet sector
      final pool = candidates.isNotEmpty
          ? candidates
          : sectors
              .where((s) => s.hasPlanet && s.id > settings.fedSpaceEnd)
              .toList();
      if (pool.isEmpty) {
        // Create a planet in a random non-FedSpace sector
        final nonFed =
            sectors.where((s) => s.id > settings.fedSpaceEnd).toList();
        if (nonFed.isEmpty) continue;
        final sector = nonFed[rng.nextInt(nonFed.length)];
        if (!sector.hasPlanet) {
          sector.hasPlanet = true;
          sector.planet = _createPlanet(sector, rng);
          final type = faction == FactionClass.duran
              ? 'Lava'
              : faction == FactionClass.vinari
                  ? 'Terran'
                  : 'Desert';
          sector.planet = _setupHomeworld(sector.planet!, faction, type, rng);
        }
        continue;
      }
      final chosen = pool[rng.nextInt(pool.length)];
      chosen.planet = _setupHomeworld(
          chosen.planet!, faction, chosen.planet!.planetType, rng);
    }
  }

  List<String> _homeworldTypes(FactionClass faction) {
    switch (faction) {
      case FactionClass.duran:
        return ['Lava', 'Toxic', 'Barren', 'Moon'];
      case FactionClass.vinari:
        return ['Terran', 'Jungle', 'Ocean'];
      case FactionClass.trader:
        return ['Terran', 'Desert', 'Moon'];
      default:
        return ['Terran'];
    }
  }

  Planet _setupHomeworld(
      Planet planet, FactionClass faction, String type, math.Random rng) {
    final homeworldName = _homeworldName(faction);
    return Planet(
      name: homeworldName ?? planet.name,
      planetType: type,
      atmosphere: Planet.planetAtmospheres[type]?.atmosphere ?? 'Unknown',
      owner: faction,
      isHomeworld: true,
      homeworldOf: faction,
      population: 10000 + rng.nextInt(5000),
      colonistsMinerals: 3000,
      colonistsOrganics: 3000,
      colonistsIndustrial: 2000,
      colonistsFighters: 2000,
      productionEfficiency: 1.0,
      storedMinerals: 5000,
      storedOrganics: 3000,
      storedIndustrial: 2000,
      storedFighters: 500,
      maxStorage: 250000,
      level: 4,
      levelProgress: 0,
      requiredMinerals: 50000,
      requiredOrganics: 30000,
      requiredIndustrial: 20000,
      requiredColonists: 500000,
      defenseLevel: 4,
      shield: 8000,
      maxShield: 8000,
      hull: 20000,
      maxHull: 20000,
      productionTimer: 8,
      spawnInterval: 10,
      imagePath: _randomPlanetImage(type, rng),
      scanned: true,
    );
  }

  String? _homeworldName(FactionClass faction) {
    switch (faction) {
      case FactionClass.duran:
        return 'Kravos';
      case FactionClass.vinari:
        return 'Celestara';
      case FactionClass.trader:
        return 'Vionis';
      default:
        return null;
    }
  }

  Planet _createPlanet(Sector sector, math.Random rng) {
    final type = _pickPlanetType(sector, rng);
    final efficiency = 0.5 + rng.nextDouble() * 1.0;
    final startingResources = 50 + rng.nextInt(200);
    final baseName = Planet.planetNames[sector.id % Planet.planetNames.length];
    final defenseLevel = rng.nextInt(3); // 0-2
    final baseArmor = 1000 + defenseLevel * 2000;
    final level = 1;
    final cost = Planet.levelUpCosts[level - 1];
    return Planet(
      name: Planet.generateVariantName(
          baseName, sector.id * 7 + rng.nextInt(9999)),
      planetType: type,
      atmosphere: Planet.planetAtmospheres[type]?.atmosphere ?? 'Unknown',
      productionEfficiency: (efficiency * 10).roundToDouble() / 10,
      storedMinerals: startingResources,
      storedOrganics: startingResources ~/ 2,
      storedIndustrial: startingResources ~/ 3,
      storedFighters: 10 + rng.nextInt(40),
      maxStorage: 5000,
      level: level,
      requiredMinerals: cost.requiredMinerals,
      requiredOrganics: cost.requiredOrganics,
      requiredIndustrial: cost.requiredIndustrial,
      requiredColonists: cost.requiredColonists,
      defenseLevel: defenseLevel,
      hull: baseArmor.toDouble(),
      maxHull: baseArmor.toDouble(),
      imagePath: _randomPlanetImage(type, rng),
      scanned: false,
    );
  }

  String _randomPlanetImage(String type, math.Random rng) {
    final pool = Planet.imagePool[type];
    if (pool == null || pool.isEmpty) return 'Unknown_World_1.gif';
    return 'assets/images/planets/${pool[rng.nextInt(pool.length)]}';
  }

  String _pickPlanetType(Sector sector, math.Random rng) {
    if (sector.id <= settings.fedSpaceEnd && rng.nextDouble() < 0.6) {
      return 'Terran';
    }
    const weightedTypes = [
      'Terran',
      'Terran',
      'Terran',
      'Jungle',
      'Jungle',
      'Desert',
      'Desert',
      'Ocean',
      'Ocean',
      'Ice',
      'Lava',
      'Lava',
      'Gas Giant',
      'Moon',
      'Moon',
      'Barren',
      'Toxic',
      'Toxic',
    ];
    return weightedTypes[rng.nextInt(weightedTypes.length)];
  }

  void _assignNpcsAndAliens(List<Sector> sectors, math.Random rng) {
    for (final s in sectors) {
      if (s.id <= settings.fedSpaceEnd) continue;
      s.traderCount = rng.nextDouble() < settings.traderDensity ? 1 : 0;
      s.duranCount = rng.nextDouble() < settings.duranDensity ? 1 : 0;
      s.vinariCount = rng.nextDouble() < settings.vinariDensity ? 1 : 0;
      s.pirateCount = rng.nextDouble() < settings.pirateDensity ? 1 : 0;
    }
  }

  void _generateNpcs(
    List<Sector> sectors,
    List<NpcShip> npcs,
    math.Random rng,
  ) {
    final factionDensities = {
      FactionClass.trader: settings.traderDensity,
      FactionClass.duran: settings.duranDensity,
      FactionClass.vinari: settings.vinariDensity,
      FactionClass.pirate: settings.pirateDensity,
    };

    for (final factionEntry in factionDensities.entries) {
      final density = factionEntry.value;
      if (density <= 0) continue;

      int factionCount = 0;
      final sectorsUsed = <int>{};
      for (final s in sectors) {
        if (s.id <= settings.fedSpaceEnd) continue;
        if (rng.nextDouble() >= density) continue;

        final seed = rng.nextInt(100000);
        final npc = NpcShip.create(
          faction: factionEntry.key,
          shipDef: ShipDefinition
              .allShips[rng.nextInt(ShipDefinition.allShips.length)],
          currentSectorId: s.id,
          startingCredits: settings.npcStartingCredits,
          seed: seed,
        );
        npcs.add(npc);
        factionCount++;
        sectorsUsed.add(s.id);
      }
      debugPrint(
          'Placed $factionCount ${factionEntry.key.name} NPCs across ${sectorsUsed.length} sectors');
    }

    NpcStorage().saveAll(npcs);
  }

  // ---------------------------------------------------------------------------
  // BFS pathfinding utility (public)
  // ---------------------------------------------------------------------------

  /// Breadth‑first search from [startId] to [targetId].
  /// Returns the shortest route (list of sector IDs) or null if unreachable.
  /// Delegates to [PathfindingService].
  List<int>? findPath(List<Sector> sectors, int startId, int targetId) {
    return PathfindingService.findPath(sectors, startId, targetId);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Sector? _sectorAt(List<Sector> sectors, double x, double y) {
    for (final s in sectors) {
      if (s.x == x && s.y == y) return s;
    }
    return null;
  }

  bool _frontierHas(List<_FrontierEntry> frontier, double x, double y) {
    for (final e in frontier) {
      if (e.x == x && e.y == y) return true;
    }
    return false;
  }

  double _distance(double x1, double y1, double x2, double y2) {
    return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1));
  }

  String _sectorName(int id, math.Random rng) {
    const prefixes = [
      'Alpha',
      'Beta',
      'Gamma',
      'Delta',
      'Epsilon',
      'Zeta',
      'Eta',
      'Theta',
      'Iota',
      'Kappa',
      'Lambda',
      'Mu',
      'Nu',
      'Xi',
      'Omicron',
      'Pi',
      'Rho',
      'Sigma',
      'Tau',
      'Upsilon',
      'Phi',
      'Chi',
      'Psi',
      'Omega',
      'Nova',
      'Astra',
      'Cygnus',
      'Draco',
      'Eridanus',
      'Fomalhaut',
      'Gienah',
      'Helios',
      'Icarus',
      'Jovian',
      'Kepler',
      'Lyra',
      'Mizar',
      'Nebula',
      'Orion',
      'Polaris',
      'Quasar',
      'Rigel',
      'Sirius',
      'Titan',
      'Ursa',
      'Vega',
      'Wraith',
      'Xenon',
      'Ymir',
      'Zephyr',
    ];
    return prefixes[id % prefixes.length];
  }

  String _portName(int sectorId, math.Random rng) {
    const names = [
      'Central',
      'Alpha',
      'Beta',
      'Gamma',
      'Delta',
      'Mercury',
      'Venus',
      'Mars',
      'Jupiter',
      'Saturn',
      'Uranus',
      'Neptune',
      'Pluto',
      'Eris',
      'Ceres',
      'Vesta',
      'Pallas',
      'Hygiea',
      'Interloper',
      'Waystation',
      'Outpost',
      'Haven',
      'Anchor',
      'Beacon',
      'Gateway',
      'Nexus',
      'Crossroads',
      'Junction',
      'Terminal',
      'Depot',
    ];
    return '${names[sectorId % names.length]} Station';
  }
}

// =============================================================================
// Private helper types
// =============================================================================

class _FrontierEntry {
  final double x;
  final double y;
  final int adjacentTo;
  _FrontierEntry(this.x, this.y, this.adjacentTo);
}

class _Dir {
  final int dx;
  final int dy;
  const _Dir(this.dx, this.dy);
}

class _Candidate {
  final int sectorId;
  final double weight;
  _Candidate(this.sectorId, this.weight);
}

class _PortPrices {
  final Map<String, double> buyPrices;
  final Map<String, double> sellPrices;
  _PortPrices(this.buyPrices, this.sellPrices);
}

class _PortQuantities {
  final Map<String, int> supply;
  final Map<String, int> demand;
  _PortQuantities(this.supply, this.demand);
}
