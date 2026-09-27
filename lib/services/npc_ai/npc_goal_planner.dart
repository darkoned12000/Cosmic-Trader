// Goal selection and every goal creator: trade, explore, attack, patrol, convoy, wolf-pack, border holds, distress, vendettas, intercepts, plus the hunter census.
part of 'npc_ai_service.dart';

class DistressSignal {
  final int sectorId;
  final String targetId;
  final String targetName;
  final String aggressorId;
  final String aggressorName;
  final DateTime createdAt;

  static const Duration ttl = Duration(minutes: 5);

  bool get isExpired => DateTime.now().difference(createdAt) > ttl;

  const DistressSignal({
    required this.sectorId,
    required this.targetId,
    required this.targetName,
    required this.aggressorId,
    required this.aggressorName,
    required this.createdAt,
  });
}

/// Active distress signals keyed by the defender's NPC id.
final Map<String, DistressSignal> _activeDistressSignals = {};

/// Max escorts trailing one convoy leader (C3). Leader plus two is a
/// wing: visible on the map, meaningful in a fight, not a migration.
const int maxConvoyEscorts = 2;

/// Shared target-convergence cap (review batch 1): EVERY hunt path —
/// distress, wolf-pack, vendetta, and bounty targeting — counts hulls
/// already holding attack goals on a candidate (whatever created them)
/// and stands down past this many. Without it, notorious targets
/// (stacked grudges, stacked bounties, fresh heroes) attract unbounded
/// independent swarms: the stampede pattern, rediscovered.
const int maxHuntersPerTarget = 3;

/// Full hunter census, built once per selection call (review batch 3,
/// P2): calling [huntersOnTarget] per candidate is O(N) per candidate.
Map<String, int> _huntersByTarget(List<NpcShip> allNpcs) {
  final hunters = <String, int>{};
  for (final n in allNpcs) {
    final target = n.currentGoal?.targetId;
    if (!n.isDestroyed &&
        n.currentGoal?.type == NpcGoalType.attack &&
        target != null) {
      hunters[target] = (hunters[target] ?? 0) + 1;
    }
  }
  return hunters;
}

/// C2 vendetta pursuit bounds. A grudge at or above
/// [vendettaGrievanceThreshold] (one witnessed kin-kill) funds a hunt
/// when the pilot is otherwise idle — never by overwriting a committed
/// goal. The hunt itself is budgeted: [vendettaPursuitTtl] caps its age
/// (trail goes cold), the trip must fit the tank plus a one-hop
/// reserve, weaker targets only (grudges don't make NPCs suicidal),
/// and each dry hole eases the grudge by [vendettaDryHoleEase].
const int vendettaGrievanceThreshold = 40;

const Duration vendettaPursuitTtl = Duration(minutes: 30);

const int vendettaDryHoleEase = 10;

/// Last-seen intel stays exact while fresh, then goes probabilistic
/// (C3): a stale sighting fans out to a random warp neighbor of where
/// the target was seen. Hunts chase the scent, not a pin.
const Duration intelFreshTtl = Duration(minutes: 15);

// ────────────────────────────────────────────────────────────────
// Step 5 — Goal selection
// ────────────────────────────────────────────────────────────────

bool _needsNewGoal(NpcShip npc) {
  final goal = npc.currentGoal;
  return goal == null ||
      goal.status == NpcGoalStatus.complete ||
      goal.status == NpcGoalStatus.failed;
}

NpcGoal? _selectGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  final config = npc.personalityConfig;

  // C2: grudge before greed — an idle pilot with a fresh, actionable
  // vendetta hunts first. Selection only runs when a new goal is needed,
  // so this never hijacks a committed goal (memory → intent → goal).
  final vendetta = _createVendettaGoal(npc, sectors, allNpcs);
  if (vendetta != null) return vendetta;

  // C3: fly together before flying rich — escorts and packmates join
  // live runs (idle pilots only, same no-hijack guarantee as above),
  // Duran post border holds. All bounded, all revalidated at execution.
  final convoy = _createConvoyGoal(npc, sectors, allNpcs);
  if (convoy != null) return convoy;
  final wolfpack = _createWolfpackGoal(npc, sectors, allNpcs);
  if (wolfpack != null) return wolfpack;
  final borderHold = _createBorderHoldGoal(npc, sectors, allNpcs);
  if (borderHold != null) return borderHold;

  // Collect viable goal types with their weights
  final candidates = <NpcGoalType>[];
  final weights = <double>[];

  for (final entry in config.goalWeights.entries) {
    if (_isGoalViable(entry.key, npc, sectors)) {
      candidates.add(entry.key);
      weights.add(entry.value);
    }
  }

  if (candidates.isEmpty) {
    return _createExploreGoal(npc, sectors);
  }

  // Weighted pick, but a picked type may still fail to instantiate
  // (no targets in range, no emporium known, no route). Walk the pool
  // in weighted order until one materializes instead of giving up on
  // the first null — a single unreachable pick must not waste the tick.
  final totalWeight = weights.fold(0.0, (a, b) => a + b);
  if (totalWeight <= 0) return _createExploreGoal(npc, sectors);

  final picks = <NpcGoalType>[];
  final remaining = List<double>.from(weights);
  final remainingTypes = List<NpcGoalType>.from(candidates);
  while (remainingTypes.isNotEmpty) {
    final total = remaining.fold(0.0, (a, b) => a + b);
    if (total <= 0) break;
    var roll = NpcAiService._rng.nextDouble() * total;
    var pick = 0;
    for (int i = 0; i < remaining.length; i++) {
      roll -= remaining[i];
      if (roll <= 0) {
        pick = i;
        break;
      }
    }
    picks.add(remainingTypes.removeAt(pick));
    remaining.removeAt(pick);
  }

  for (final type in picks) {
    final goal = _instantiateGoal(type, npc, sectors, players, allNpcs);
    if (goal != null) return goal;
  }
  return _createExploreGoal(npc, sectors);
}

bool _isGoalViable(
  NpcGoalType type,
  NpcShip npc,
  List<Sector> sectors,
) {
  switch (type) {
    case NpcGoalType.tradeRoute:
      // Full holds are fine when the NPC carries sellable cargo — it
      // becomes a sell-first route (see _createTradeRouteGoal). Without
      // this, full holds deadlocked all future trading: no new route
      // could start, and nothing else empties cargo. Same for broke
      // NPCs with room but cargo aboard (review batch 3, P1): credits
      // gate only the buy leg, and creation routes them sell-first.
      final hasSpace = npc.cargoUsed < npc.cargoHoldCapacity;
      final hasCargo = npc.cargo.values.any((q) => q > 0);
      return npc.memory.discoveredPorts.length >= 2 &&
          (hasCargo || (hasSpace && npc.credits > 100));
    case NpcGoalType.explore:
      return _hasUnvisitedSectors(npc, sectors);
    case NpcGoalType.bankDeposit:
      return BankingAi.shouldDeposit(npc);
    case NpcGoalType.bankWithdraw:
      return BankingAi.shouldWithdraw(npc);
    case NpcGoalType.attack:
      return npc.personalityConfig.aggression > 0.5 && npc.totalWeaponPower > 0;
    case NpcGoalType.raidPort:
      return npc.personalityConfig.aggression > 0.6 &&
          _hasPortSectorReachable(npc, sectors);
    case NpcGoalType.patrol:
      return true;
    case NpcGoalType.flee:
      return false;
    case NpcGoalType.upgradeEquipment:
      // Mid-wealth threshold: cheapest upgrades run ~15k, so NPCs start
      // outfitting (repairs + level 2) well before array money (75k+).
      return npc.credits + npc.bankBalance > 25000;
    case NpcGoalType.buyPort:
      // Serious money only; affordability re-checked at execution.
      return npc.credits + npc.bankBalance > 100000;
    case NpcGoalType.refuelEnergy:
      return NpcAiService._hasEnergy(npc) || npc.credits + npc.bankBalance > 0;
  }
}

bool _hasUnvisitedSectors(NpcShip npc, List<Sector> sectors) {
  // Quick check: if visited count is far below total, there's
  // likely an unvisited sector reachable
  if (npc.memory.visitedSectors.length < sectors.length * 0.9) {
    return true;
  }
  // Exhaustive check: BFS from current position
  final visited = <int>{npc.currentSectorId};
  final queue = [npc.currentSectorId];
  while (queue.isNotEmpty) {
    final c = queue.removeAt(0);
    if (!npc.memory.visitedSectors.contains(c)) return true;
    final sector = NpcAiService._findSector(sectors, c);
    if (sector != null) {
      for (final w in sector.warpRoutes) {
        if (visited.add(w)) queue.add(w);
      }
    }
  }
  return false;
}

bool _hasPortSectorReachable(NpcShip npc, List<Sector> sectors) {
  return PathfindingService.findNearestWhere(
        sectors,
        npc.currentSectorId,
        (s) => s.hasPort,
      ) !=
      null;
}

NpcGoal? _instantiateGoal(
  NpcGoalType type,
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  switch (type) {
    case NpcGoalType.tradeRoute:
      return _createTradeRouteGoal(npc, sectors, allNpcs);
    case NpcGoalType.explore:
      return _createExploreGoal(npc, sectors);
    case NpcGoalType.bankDeposit:
      return BankingAi.createDepositGoal(npc, sectors);
    case NpcGoalType.bankWithdraw:
      return BankingAi.createWithdrawGoal(npc, sectors);
    case NpcGoalType.patrol:
      return _createPatrolGoal(npc, sectors);
    case NpcGoalType.attack:
      return _createAttackGoal(npc, sectors, players, allNpcs);
    case NpcGoalType.raidPort:
      return _createRaidPortGoal(npc, sectors);
    case NpcGoalType.flee:
      return null;
    case NpcGoalType.upgradeEquipment:
      return _createUpgradeGoal(npc, sectors);
    case NpcGoalType.refuelEnergy:
      return NpcAiService.createRefuelGoal(npc, sectors);
    case NpcGoalType.buyPort:
      return _createBuyPortGoal(npc, sectors);
  }
}

NpcGoal? _createTradeRouteGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  // Sell-first whenever there is no economical buy leg: full holds,
  // mere nibs (< 25% of capacity) not worth topping up with a fresh buy,
  // or broke pilots (credits gate the buy leg only — review batch 3).
  // Aborted routes leave partial cargo that would otherwise ride along
  // unsold forever while new commodities pile on top.
  final hasSpace = npc.cargoUsed < npc.cargoHoldCapacity;
  final hasCargo = npc.cargo.values.any((q) => q > 0);
  final nibs = hasCargo && npc.cargoUsed < npc.cargoHoldCapacity * 0.25;
  final broke = hasCargo && npc.credits <= 100;
  if ((!hasSpace || nibs || broke) && hasCargo) {
    return _createSellOnlyGoal(npc, sectors, allNpcs);
  }
  final danger = NpcAiService.fearedSectors(npc, allNpcs);
  final route = TradeEvaluator.findBestTradeRoute(
    npc.currentSectorId,
    npc.memory.discoveredPorts,
    sectors,
    npc.personalityConfig.maxTravelDistance,
    avoidRoutes: npc.memory.coolingRoutes(),
    credits: npc.credits.toDouble(),
    actorFaction: npc.faction,
    standings: npc.memory.factionStandings,
    dangerSectors: danger,
    preferredRoutes: npc.memory.profitableRoutes,
  );
  if (route == null) {
    GameEventLog.global.goal(
      '[${npc.pilotName}] Goal: trade wanted but no route from '
      '${npc.memory.discoveredPorts.length} known ports',
    );
    return null;
  }
  if (danger.contains(route.buySectorId) ||
      danger.contains(route.sellSectorId)) {
    GameEventLog.global.goal(
      '[${npc.pilotName}] Goal: no safe trade route — flying dangerous '
      'for ${route.commodity} ${route.buySectorId}>${route.sellSectorId}',
    );
  }

  return NpcGoal(
    type: NpcGoalType.tradeRoute,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {
      'targetSectorId': route.buySectorId,
      'buyPortId': route.buySectorId,
      'sellPortId': route.sellSectorId,
      'commodity': route.commodity,
      'buyPrice': route.buyPrice,
      'phase': 'travel_to_buy',
    },
  );
}

/// Sell-first route for full holds: best known buyer for carried cargo.
/// Returns null (with a log line) when nothing on board has a reachable
/// buyer — the NPC keeps exploring instead of idling on dead inventory.
/// Dangerous buyers (C2c feared sectors) lose to safe ones at any price;
/// only the last buyer standing gets the cargo.
NpcGoal? _createSellOnlyGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  final maxTravel = npc.personalityConfig.maxTravelDistance;
  final danger = NpcAiService.fearedSectors(npc, allNpcs);
  String? bestCommodity;
  int? bestPortId;
  var bestPrice = 0.0;
  String? dangerCommodity;
  int? dangerPortId;
  var dangerPrice = 0.0;

  npc.cargo.forEach((commodity, qty) {
    if (qty <= 0) return;
    for (final entry in npc.memory.discoveredPorts.entries) {
      // Skip buyers on cooldown (review batch 3, P1): a failed sell
      // keys `sell>port:commodity`, so dead buyers rest instead of
      // re-selecting every cycle.
      if (npc.memory.isRouteCooling('sell>${entry.key}:$commodity')) {
        continue;
      }
      final price = entry.value.getEffectiveBuyPrice(
        commodity,
        standing: FactionStanding.resolveFor(
          npc.faction,
          entry.value.ownerFaction,
          npc.memory.factionStandings,
        ),
      );
      if (price <= 0) continue;
      final path = PathfindingService.findPath(
        sectors,
        npc.currentSectorId,
        entry.key,
      );
      if (path == null || path.length - 1 > maxTravel) continue;
      if (danger.contains(entry.key)) {
        if (price > dangerPrice) {
          dangerPrice = price;
          dangerCommodity = commodity;
          dangerPortId = entry.key;
        }
        continue;
      }
      if (price > bestPrice) {
        bestPrice = price;
        bestCommodity = commodity;
        bestPortId = entry.key;
      }
    }
  });

  if (bestCommodity == null || bestPortId == null) {
    if (dangerCommodity != null && dangerPortId != null) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Goal: only dangerous buyers for on-board '
        'cargo — flying dangerous to $dangerPortId',
      );
      bestCommodity = dangerCommodity;
      bestPortId = dangerPortId;
    } else {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Goal: holds full but no buyer known for '
        'on-board cargo',
      );
      return null;
    }
  }
  return NpcGoal(
    type: NpcGoalType.tradeRoute,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {
      'targetSectorId': bestPortId,
      'buyPortId': bestPortId,
      'sellPortId': bestPortId,
      'commodity': bestCommodity,
      'phase': 'travel_to_sell',
    },
  );
}

bool _isPurchasable(Port? port) {
  if (port == null) return false;
  if (port.isHardwareEmporium) return false;
  if (port.portClass == PortClass.federal) return false;
  if (port.owner != null && port.owner!.isNotEmpty) return false;
  return true;
}

NpcGoal? _createBuyPortGoal(NpcShip npc, List<Sector> sectors) {
  final portSectorId = PathfindingService.findNearestWhere(
    sectors,
    npc.currentSectorId,
    (s) =>
        s.hasPort && _isPurchasable(s.port) && !NpcAiService._isSafeZone(s.id),
  );
  if (portSectorId == null) return null;

  return NpcGoal(
    type: NpcGoalType.buyPort,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {'targetSectorId': portSectorId},
  );
}

NpcGoal _createExploreGoal(NpcShip npc, List<Sector> sectors) {
  final targetId = PathfindingService.findNearestWhere(
    sectors,
    npc.currentSectorId,
    (s) => !npc.memory.visitedSectors.contains(s.id),
  );

  if (targetId != null) {
    return NpcGoal(
      type: NpcGoalType.explore,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': targetId},
    );
  }

  // All visited — patrol instead
  return _createPatrolGoal(npc, sectors);
}

/// Convoy escort (C3): an idle trader falls in with a wingmate's live
/// trade run, copying its legs. Safety in numbers emerges — no
/// formation code, just shared destinations. Member leave-conditions
/// live in [_executeTradeGoal] (scatter on leader loss, solo on
/// divergence); leader death is the destroyed-leader case there.
NpcGoal? _createConvoyGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  if (npc.faction != FactionClass.trader) return null;
  final maxDist = npc.personalityConfig.maxTravelDistance;
  final legCost = EnergyService.npcWarpCost(npc);
  for (final leader in allNpcs) {
    if (leader.id == npc.id || leader.isDestroyed) continue;
    if (leader.faction != FactionClass.trader) continue;
    final run = leader.currentGoal;
    if (run == null ||
        run.type != NpcGoalType.tradeRoute ||
        run.status != NpcGoalStatus.travelling ||
        run.params.containsKey('convoyLeader') ||
        run.buyPortId == null) {
      continue;
    }
    // Room in the wing: leader plus fewer than maxConvoyEscorts.
    var escorts = 0;
    for (final n in allNpcs) {
      if (n.id != leader.id &&
          !n.isDestroyed &&
          n.currentGoal?.params['convoyLeader'] == leader.id) {
        escorts++;
      }
    }
    if (escorts >= maxConvoyEscorts) continue;
    // Review batch 3, P0: target the phase-appropriate port. The old
    // code always aimed at the buy port while copying the phase
    // wholesale — escorts joining a sell-leg run sat at the buy port
    // forever (arrival acts only at the sell port, movement holds on
    // arrival). Empty-hold escorts still fail fast at the sell port
    // ('hold empty'), which reselection handles normally.
    final joinTarget = run.params['phase'] == 'travel_to_sell'
        ? run.sellPortId
        : run.buyPortId;
    if (joinTarget == null) continue;
    final path =
        PathfindingService.findPath(sectors, npc.currentSectorId, joinTarget);
    if (path == null || path.length - 1 > maxDist) continue;
    if (npc.energy < (path.length - 1) * legCost + legCost) continue;
    GameEventLog.global
        .goal('[${npc.pilotName}] Falling in with ${leader.pilotName} convoy '
            '(${run.commodity} ${run.buyPortId}>${run.sellPortId})');
    return NpcGoal(
      type: NpcGoalType.tradeRoute,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        ...run.params,
        'targetSectorId': joinTarget,
        'convoyLeader': leader.id,
      },
    );
  }
  return null;
}

/// Wolf-pack join (C3): an idle pirate piles onto a wingmate's live
/// attack run. Packs share the convergence cap ([maxHuntersPerTarget],
/// counted across mechanisms by [huntersOnTarget]) and dissolve through
/// the normal arrival paths — kills, dry holes, and stand-downs all
/// clear legs.
NpcGoal? _createWolfpackGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  if (npc.faction != FactionClass.pirate) return null;
  if (npc.totalWeaponPower <= 0) return null;
  final maxDist = npc.personalityConfig.maxTravelDistance;
  final legCost = EnergyService.npcWarpCost(npc);
  for (final attacker in allNpcs) {
    if (attacker.id == npc.id || attacker.isDestroyed) continue;
    if (attacker.faction != FactionClass.pirate) continue;
    final hunt = attacker.currentGoal;
    final targetId = hunt?.targetId;
    if (hunt == null ||
        hunt.type != NpcGoalType.attack ||
        hunt.status != NpcGoalStatus.travelling ||
        targetId == null ||
        hunt.targetSectorId == null) {
      continue;
    }
    if (NpcAiService._isSafeZone(npc.currentSectorId) ||
        NpcAiService._isSafeZone(hunt.targetSectorId!)) {
      continue;
    }
    if (NpcAiService.huntersOnTarget(allNpcs, targetId) >= maxHuntersPerTarget) {
      continue;
    }
    final path = PathfindingService.findPath(
        sectors, npc.currentSectorId, hunt.targetSectorId!);
    if (path == null || path.length - 1 > maxDist) continue;
    if (npc.energy < (path.length - 1) * legCost + legCost) continue;
    GameEventLog.global
        .combat('[${npc.pilotName}] Joining the pack on $targetId in Sector '
            '${hunt.targetSectorId}');
    return NpcGoal(
      type: NpcGoalType.attack,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': hunt.targetSectorId,
        'targetId': targetId,
      },
    );
  }
  return null;
}

/// Duran border hold (C3): an idle armed Duran posts at the nearest
/// sector neighboring live hostiles (Vinari or pirates). A patrol that
/// sits — the post is held for [NpcAiService.maxPatrolLegs], then re-evaluated, so
/// holds track pressure instead of fossilizing.
///
/// Capped per sector (soak fix): uncapped holds starved the whole
/// Duran faction — every idle Duran near hostiles held instead of
/// entering the lottery, so 45 ships produced 0 attacks and ~0 trades
/// in 36 minutes. Past [maxBorderHoldersPerSector], idle pilots fall
/// through to trade/attack.
const int maxBorderHoldersPerSector = 2;

NpcGoal? _createBorderHoldGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  if (npc.faction != FactionClass.duran) return null;
  if (npc.totalWeaponPower <= 0) return null;
  if (NpcAiService._isSafeZone(npc.currentSectorId)) return null;
  final maxDist = npc.personalityConfig.maxTravelDistance;
  final legCost = EnergyService.npcWarpCost(npc);
  final hostileSectors = <int>{};
  for (final n in allNpcs) {
    if (n.id == npc.id || n.isDestroyed) continue;
    if (!NpcAiService._isHostileFaction(FactionClass.duran, n.faction)) {
      continue;
    }
    hostileSectors.add(n.currentSectorId);
  }
  if (hostileSectors.isEmpty) return null;

  // One BFS tree from the holder (P2): distances to every candidate
  // instead of a findPath per sector.
  final tree = PathfindingService.bfsParents(sectors, npc.currentSectorId);
  int? bestHold;
  var bestDist = 1 << 30;
  for (final s in sectors) {
    if (NpcAiService._isSafeZone(s.id)) continue;
    if (!s.warpRoutes.any(hostileSectors.contains)) continue;
    final dist = PathfindingService.distanceInTree(tree, s.id);
    if (dist == null || dist > maxDist) continue;
    if (npc.energy < dist * legCost + legCost) continue;
    if (dist < bestDist) {
      bestDist = dist;
      bestHold = s.id;
    }
  }
  if (bestHold == null) return null;
  // Per-sector cap (soak fix): a fully-manned post frees the rest of
  // the faction for trade and war instead of stacking holders.
  final hold = bestHold;
  final holders = allNpcs.where((n) =>
      !n.isDestroyed &&
      n.currentGoal?.type == NpcGoalType.patrol &&
      n.currentGoal?.params['borderHold'] == hold);
  if (holders.length >= maxBorderHoldersPerSector) return null;
  final threat = hostileSectors.length == 1 ? hostileSectors.first : -1;
  GameEventLog.global.goal(
      '[${npc.pilotName}] Holding the border at Sector $bestHold '
      '(${threat == -1 ? 'hostiles next door' : 'hostiles in Sector $threat'})');
  return NpcGoal(
    type: NpcGoalType.patrol,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {
      'targetSectorId': bestHold,
      'homeSector': npc.currentSectorId,
      'borderHold': bestHold,
    },
  );
}

NpcGoal _createPatrolGoal(NpcShip npc, List<Sector> sectors) {
  final current = NpcAiService._findSector(sectors, npc.currentSectorId);
  final targetId = (current != null && current.warpRoutes.isNotEmpty)
      ? current.warpRoutes[NpcAiService._rng.nextInt(current.warpRoutes.length)]
      : npc.currentSectorId;

  return NpcGoal(
    type: NpcGoalType.patrol,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {'targetSectorId': targetId, 'homeSector': npc.currentSectorId},
  );
}

/// If a distress signal is active within range, set an attack goal
/// against the aggressor. Only NPCs with low aggression (helpers)
/// or same-faction loyalty respond.
NpcGoal? _respondToDistress(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  // Expired signal cleanup
  _activeDistressSignals.removeWhere((_, s) => s.isExpired);

  if (_activeDistressSignals.isEmpty) return null;

  // Determine if this NPC would respond
  final lowAggression = npc.personalityConfig.aggression < 0.3;

  DistressSignal? bestSignal;
  int bestDist = 999999;

  for (final signal in _activeDistressSignals.values) {
    // Skip if this NPC is the aggressor
    if (signal.aggressorId == npc.id) continue;
    // Low-aggression NPCs always respond; others only respond to same-faction
    if (!lowAggression) {
      final defender = NpcAiService._findNpcById(allNpcs, signal.targetId);
      if (defender == null) continue;
      if (defender.faction != npc.faction) continue;
    }
    final path = PathfindingService.findPath(
      sectors,
      npc.currentSectorId,
      signal.sectorId,
    );
    if (path == null) continue;
    final dist = path.length - 1;
    if (dist < bestDist) {
      bestDist = dist;
      bestSignal = signal;
    }
  }

  if (bestSignal == null) return null;

  // Cap the stampede (shared counter — review batch 1): ships already
  // converging on this aggressor count against the wing limit (visible
  // immediately — the tick loop writes each processed NPC back before
  // the next one runs).
  if (NpcAiService.huntersOnTarget(allNpcs, bestSignal.aggressorId) >=
      NpcAiService.maxDistressResponders) {
    return null;
  }

  // Energy gate: don't answer if the trip costs more than the tank
  // holds (plus one hop reserve). A responder that strands en route
  // helps nobody.
  final legCost = EnergyService.npcWarpCost(npc);
  if (npc.energy < bestDist * legCost + legCost) return null;

  GameEventLog.global
      .combat('[${npc.pilotName}] Responding to distress call from '
          '${bestSignal.targetName} in Sector ${bestSignal.sectorId}');

  return NpcGoal(
    type: NpcGoalType.attack,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {
      'targetSectorId': bestSignal.sectorId,
      'targetId': bestSignal.aggressorId,
      'distressFor': bestSignal.targetId,
    },
  );
}

NpcGoal? _createVendettaGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  // C2a reacquisition: memory → intent → goal. Only idle pilots get
  // here (the caller runs selection solely when a new goal is needed),
  // so a grudge never overwrites a committed goal.
  if (npc.memory.vendettas.isEmpty) return null;
  if (NpcAiService._isSafeZone(npc.currentSectorId)) return null;
  if (npc.totalWeaponPower <= 0) {
    // Unarmed pilots hold grudges, not hunts.
    return null;
  }
  final myPower = CombatService.calculateFirepower(npc);
  final maxDist = npc.personalityConfig.maxTravelDistance;
  final legCost = EnergyService.npcWarpCost(npc);

  final grudges = npc.memory.vendettas.entries.toList()
    ..sort((a, b) => b.value.grievance.compareTo(a.value.grievance));
  // Hunter census once per selection (P2): per-grudge scans are O(N)
  // each against a roster scanned every tick.
  final hunters = _huntersByTarget(allNpcs);
  for (final entry in grudges) {
    final record = entry.value;
    if (record.grievance < vendettaGrievanceThreshold) continue;
    // Target must be a living NPC in this roster. Player-id grudges
    // aren't recorded yet (C1c writes NPC killers only); absent from
    // the roster means gone, and C2b prunes those entries. Lookup via
    // the tick index when present (P2).
    final indexed = NpcAiService.npcById?[entry.key];
    final NpcShip? target;
    if (indexed != null && !indexed.isDestroyed) {
      target = indexed;
    } else if (NpcAiService.npcById != null) {
      target = null;
    } else {
      NpcShip? found;
      for (final n in allNpcs) {
        if (n.id == entry.key && !n.isDestroyed) {
          found = n;
          break;
        }
      }
      target = found;
    }
    if (target == null) continue;
    // Convergence cap (review batch 1): a magnet target with a full
    // wing already inbound waits — the grudge keeps for later.
    if ((hunters[target.id] ?? 0) >= maxHuntersPerTarget) {
      continue;
    }
    // Destination is the live heading when the target is underway
    // (soak fix: same cutoff logic as spontaneous hunts — chase where
    // they're going, wait there, engage on arrival), else the intel
    // (last-seen sector while fresh, probabilistic fan-out once stale)
    // — except under our nose: co-located ships see each other, so
    // engage in place instead of flying to stale intel.
    int dest;
    if (target.currentSectorId == npc.currentSectorId) {
      dest = npc.currentSectorId;
    } else {
      dest = NpcAiService.intelSearchSector(record, sectors);
      final heading = target.currentGoal;
      final hd = heading?.targetSectorId;
      if (heading != null &&
          heading.status == NpcGoalStatus.travelling &&
          hd != null &&
          hd != target.currentSectorId &&
          !NpcAiService._isSafeZone(hd)) {
        final cut =
            PathfindingService.findPath(sectors, npc.currentSectorId, hd);
        if (cut != null && cut.length - 1 <= maxDist) {
          dest = hd;
        }
      }
    }
    if (NpcAiService._isSafeZone(dest)) continue;
    final path =
        PathfindingService.findPath(sectors, npc.currentSectorId, dest);
    if (path == null || path.length - 1 > maxDist) continue;
    // Pursuit budget in energy: trip plus a one-hop reserve, or sit out.
    if (npc.energy < (path.length - 1) * legCost + legCost) continue;
    // Grudges don't make NPCs suicidal: weaker targets only.
    if (CombatService.calculateFirepower(target) >= myPower) continue;
    GameEventLog.global.combat(
        '[${npc.pilotName}] Hunting ${target.pilotName} over Sector $dest '
        '(grudge ${record.grievance})');
    return NpcGoal(
      type: NpcGoalType.attack,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': dest,
        'targetId': target.id,
        'vendettaFor': target.id,
      },
    );
  }
  return null;
}

NpcGoal? _createAttackGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  // Don't create attack goals from safe zones or against safe zones
  if (NpcAiService._isSafeZone(npc.currentSectorId)) return null;

  final myPower = CombatService.calculateFirepower(npc);
  final maxDist = npc.personalityConfig.maxTravelDistance;
  // Greedy hunters (greed ≥ 0.7) prefer marked targets: highest active
  // bounty first, weakest as tie-break. Everyone else takes the weakest.
  final greedy = npc.personalityConfig.greed >= 0.7;
  // Per-call memos (review batch 3, P2): bounty totals and hunter
  // counts are roster-wide scans — pay once per selection, not per
  // candidate comparison.
  final bountyCache = <String, int>{};
  int bountyOf(String id) =>
      bountyCache.putIfAbsent(id, () => BountyBoard.global.totalFor(id));
  final hunters = _huntersByTarget(allNpcs);
  bool prefers(NpcShip candidate, int candidatePower, NpcShip? current) {
    if (current == null) return true;
    if (greedy) {
      final bounty = bountyOf(candidate.id);
      final best = bountyOf(current.id);
      if (bounty != best) return bounty > best;
    }
    return candidatePower < CombatService.calculateFirepower(current);
  }

  // 1 — Check same sector for hostile NPCs. Co-located candidates
  // come from the tick index when present (P2); power is read off the
  // indexed copy, but execution re-resolves the live object by id.
  NpcShip? bestTarget;
  int? bestTargetSectorId;
  final locals =
      NpcAiService.npcsBySector?[npc.currentSectorId] ?? allNpcs;
  for (final other in locals) {
    if (other.id == npc.id || other.isDestroyed) continue;
    if (other.currentSectorId != npc.currentSectorId) continue;
    if (!NpcAiService._isHostileFaction(npc.faction, other.faction)) continue;
    final otherPower = CombatService.calculateFirepower(other);
    if (otherPower >= myPower) continue; // only attack weaker targets
    // Convergence cap (review batch 1): magnet targets wait their turn.
    if ((hunters[other.id] ?? 0) >= maxHuntersPerTarget) {
      continue;
    }
    if (prefers(other, otherPower, bestTarget)) {
      bestTarget = other;
      bestTargetSectorId = npc.currentSectorId;
    }
  }

  // 2 — BFS for hostile NPCs in nearby sectors (skip safe zones)
  if (bestTarget == null) {
    final visited = <int>{npc.currentSectorId};
    final queue = [(sector: npc.currentSectorId, dist: 0)];
    int queueIdx = 0;
    while (queueIdx < queue.length) {
      final current = queue[queueIdx++];
      if (current.dist >= maxDist) continue;
      final sector = NpcAiService._findSector(sectors, current.sector);
      if (sector == null) continue;
      for (final warp in sector.warpRoutes) {
        if (!visited.add(warp)) continue;
        if (NpcAiService._isSafeZone(warp)) continue; // skip safe zones
        // Check for hostile NPCs in this sector (index when present).
        final remotes = NpcAiService.npcsBySector?[warp] ?? allNpcs;
        for (final other in remotes) {
          if (other.id == npc.id || other.isDestroyed) continue;
          if (other.currentSectorId != warp) continue;
          if (!NpcAiService._isHostileFaction(npc.faction, other.faction)) {
            continue;
          }
          final otherPower = CombatService.calculateFirepower(other);
          if (otherPower >= myPower) continue;
          if ((hunters[other.id] ?? 0) >= maxHuntersPerTarget) {
            continue;
          }
          if (prefers(other, otherPower, bestTarget)) {
            bestTarget = other;
            bestTargetSectorId = warp;
          }
        }
        queue.add((sector: warp, dist: current.dist + 1));
      }
    }
  }

  // 3 — Check for hostile players nearby (skip safe zones).
  // Uses shouldAttackPlayer's full margin (caution/fear/hatred), so NPCs
  // don't cross the map for fights the trigger would refuse on arrival.
  if (bestTarget == null) {
    for (final player in players) {
      if (NpcAiService._isSafeZone(player.currentSectorId)) continue;
      if (!NpcAiService._isHostileFaction(npc.faction, player.faction) &&
          player.factionStandingWith(npc.faction) > -50) {
        continue;
      }
      if (!NpcAiService.shouldAttackPlayer(npc, player)) continue;
      if (player.currentSectorId == npc.currentSectorId) {
        bestTargetSectorId = npc.currentSectorId;
        break;
      }
      // BFS from current to player sector
      final path = PathfindingService.findPath(
        sectors,
        npc.currentSectorId,
        player.currentSectorId,
      );
      if (path != null && path.length <= maxDist + 1) {
        bestTargetSectorId = player.currentSectorId;
        break;
      }
    }
  }

  if (bestTarget == null && bestTargetSectorId == null) return null;

  // Heading cutoff (C3 generalized, soak fix): pursue where an underway
  // target is GOING, not where it was seen. Symmetric 1-hop movement
  // means chasing current positions almost never connects — arrivals
  // lag one hop behind forever. Cutoff hunters arrive early, hold
  // (arrived-live goals don't wander), and engage when the mark walks
  // in; stale cutoffs dissolve through the normal dry-hole paths.
  // Falls back to the sighting when unreachable, safe-zoned, or the
  // mark is stationary. Bounty preference stays in prefers(); the
  // destination no longer needs a bounty or greed to cut off.
  if (bestTarget != null && bestTargetSectorId != null) {
    final heading = bestTarget.currentGoal;
    final dest = heading?.targetSectorId;
    if (heading != null &&
        heading.status == NpcGoalStatus.travelling &&
        dest != null &&
        dest != bestTarget.currentSectorId &&
        !NpcAiService._isSafeZone(dest)) {
      final cut =
          PathfindingService.findPath(sectors, npc.currentSectorId, dest);
      if (cut != null && cut.length - 1 <= maxDist) {
        GameEventLog.global
            .combat('[${npc.pilotName}] Cutting off ${bestTarget.pilotName} '
                'at Sector $dest');
        bestTargetSectorId = dest;
      }
    }
  }

  return NpcGoal(
    type: NpcGoalType.attack,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {
      'targetSectorId': bestTargetSectorId,
      if (bestTarget != null) 'targetId': bestTarget.id,
    },
  );
}

NpcGoal? _createRaidPortGoal(NpcShip npc, List<Sector> sectors) {
  // Nearest WEAK port the NPC can actually beat — blindly sieging
  // strong defenses is how pirates went 0-for-history while Duran
  // (bigger guns) captured everything.
  final portSectorId = PathfindingService.findNearestWhere(
    sectors,
    npc.currentSectorId,
    (s) =>
        s.hasPort &&
        (s.port?.defenseLevel ?? 4) < 2 &&
        !NpcAiService._isSafeZone(s.id) &&
        s.port != null &&
        CombatService.canRaidPort(npc, s.port!.defenseLevel),
  );
  if (portSectorId == null) return null;

  return NpcGoal(
    type: NpcGoalType.raidPort,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {'targetSectorId': portSectorId},
  );
}

NpcGoal? _createUpgradeGoal(NpcShip npc, List<Sector> sectors) {
  // Discovered emporiums only — same rule as refuel. Null when none
  // known; the goal selector treats null as "pick something else".
  final path = nearestEmporiumPath(npc, sectors);
  if (path == null || path.isEmpty) return null;

  return NpcGoal(
    type: NpcGoalType.upgradeEquipment,
    status: NpcGoalStatus.travelling,
    createdAt: DateTime.now(),
    params: {'targetSectorId': path.last},
  );
}
