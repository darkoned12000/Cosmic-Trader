// NPC movement, threat sensing, flee. Refuel planning and the array-stranding entry point stay on the service (external callers).
part of 'npc_ai_service.dart';

/// Hop path to the nearest *discovered* Hardware Emporium that will
/// actually serve this NPC, or null when none is known, reachable, or
/// friendly. Hostile emporiums (standing ≤ −50) are skipped like
/// undiscovered ones — the NPC roams instead of flying into a refusal.
/// Single hop-list source for both [shouldRefuel] and [createRefuelGoal].
List<int>? nearestEmporiumPath(
  NpcShip npc,
  List<Sector> sectors,
) {
  final known = NpcAiService.knownEmporiumSectors(npc);
  if (known.isEmpty) return null;
  bool serves(int sectorId, Port? port) {
    if (port == null || !port.isHardwareEmporium) return false;
    if (!known.contains(sectorId)) return false;
    final standing = FactionStanding.resolveFor(
      npc.faction,
      port.ownerFaction,
      npc.memory.factionStandings,
    );
    return !port.deniesServiceTo(standing);
  }

  if (known.contains(npc.currentSectorId)) {
    final here = NpcAiService._findSector(sectors, npc.currentSectorId);
    if (serves(npc.currentSectorId, here?.port)) {
      return [npc.currentSectorId];
    }
  }
  final target = PathfindingService.findNearestWhere(
    sectors,
    npc.currentSectorId,
    (s) => serves(s.id, s.port),
  );
  if (target == null) return null;
  return PathfindingService.findPath(
    sectors,
    npc.currentSectorId,
    target,
  );
}

// ────────────────────────────────────────────────────────────────
// Step 3 — Threat evaluation
// ────────────────────────────────────────────────────────────────

bool _evaluateThreat(
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  // Aggressive NPCs never flee
  if (npc.personalityConfig.aggression > 0.7) return false;

  final enemies = _findLocalEnemies(npc, players, allNpcs);
  if (enemies.isEmpty) return false;

  final myPower = _calculatePower(npc);
  for (final enemy in enemies) {
    var theirPower = _calculatePower(enemy);
    // Fear: notoriety inflates perceived power. Infamous pilots clear
    // sectors by reputation — weaker ships leave rather than provoke.
    theirPower = (theirPower * (1 + _notorietyOf(enemy) / 200)).round();
    if (theirPower > myPower * 1.3) return true;
  }
  return false;
}

double _notorietyOf(dynamic entity) {
  if (entity is NpcShip) return entity.notoriety;
  if (entity is Player) return entity.notoriety;
  return 0;
}

List<dynamic> _findLocalEnemies(
  NpcShip npc,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  final enemies = <dynamic>[];

  for (final player in players) {
    if (player.currentSectorId == npc.currentSectorId &&
        NpcAiService._isHostileFaction(npc.faction, player.faction)) {
      enemies.add(player);
    }
  }
  // Co-located candidates from the tick index when present (P2).
  final locals =
      NpcAiService.npcsBySector?[npc.currentSectorId] ?? allNpcs;
  for (final other in locals) {
    if (other.id != npc.id &&
        other.currentSectorId == npc.currentSectorId &&
        !other.isDestroyed &&
        NpcAiService._isHostileFaction(npc.faction, other.faction)) {
      enemies.add(other);
    }
  }

  return enemies;
}

int _calculatePower(dynamic entity) {
  if (entity is NpcShip) {
    return CombatService.calculateFirepower(entity);
  }
  if (entity is Player) {
    return CombatService.calculatePlayerFirepower(entity);
  }
  return 0;
}

NpcShip _setFleeGoal(NpcShip npc, List<Sector> sectors) {
  final current = NpcAiService._findSector(sectors, npc.currentSectorId);
  if (current == null || current.warpRoutes.isEmpty) return npc;

  final targetId =
      current.warpRoutes[NpcAiService._rng.nextInt(current.warpRoutes.length)];

  GameEventLog.global.goal('[${npc.pilotName}] Flee: Evading threat in Sector '
      '${npc.currentSectorId} → Sector $targetId');

  return npc.copyWith(
    currentGoal: NpcGoal(
      type: NpcGoalType.flee,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': targetId},
    ),
  );
}

// ────────────────────────────────────────────────────────────────
// Step 6 — Movement
// ────────────────────────────────────────────────────────────────

NpcShip _move(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
) {
  if (!NpcAiService._hasEnergy(npc)) return npc;

  final cost = EnergyService.npcWarpCost(npc);

  // Solar Array retract (review batch 3, P0): a deployed array locks
  // the ship, and nothing ever furled it again — array owners with
  // energy sat at full tanks forever. Charged enough to warp means
  // fly; the trickle resumes next stranding.
  if (npc.solarArrayDeployed) {
    if (!npc.hasEnergy(cost)) return NpcAiService._handleStranded(npc);
    GameEventLog.global
        .energy('NPC_ENERGY event=array_retract pilot=${npc.pilotName}');
    return _move(npc.copyWith(solarArrayDeployed: false), sectors, allNpcs);
  }

  // Deployed Solar Array locks the ship (mirrors Player.canMove).
  if (!npc.canMove) return npc;

  if (!npc.hasEnergy(cost)) return NpcAiService._handleStranded(npc);

  // Only travelling goals steer movement. Following a complete/failed
  // goal ping-pongs the NPC at a dead target forever (refused refuel
  // looped two sectors until this guard).
  final goal = npc.currentGoal;
  final steering =
      goal != null && goal.status == NpcGoalStatus.travelling ? goal : null;

  // Arrived under a live goal (border holds standing their post):
  // hold position instead of wandering off. Every other arrival
  // either completes or retargets at execution, so only holds wait.
  if (steering != null && steering.targetSectorId == npc.currentSectorId) {
    return npc;
  }

  // If we have a goal with a target, pathfind towards it
  if (steering != null &&
      steering.targetSectorId != null &&
      steering.targetSectorId != npc.currentSectorId) {
    var path = PathfindingService.findPath(
      sectors,
      npc.currentSectorId,
      steering.targetSectorId!,
    );
    // C2c avoidance: bend transit around feared sectors when the bend
    // actually changes the next hop (no log spam for identical routes).
    final fear = NpcAiService.fearedSectors(npc, allNpcs);
    if (fear.isNotEmpty) {
      final bent = PathfindingService.findPathAvoiding(
        sectors,
        npc.currentSectorId,
        steering.targetSectorId!,
        fear,
      );
      if (bent != null &&
          bent.length > 1 &&
          (path == null || path.length < 2 || bent[1] != path[1])) {
        final dodged = (path ?? const <int>[])
            .where((s) => fear.contains(s) && s != steering.targetSectorId)
            .toList();
        if (dodged.isNotEmpty) {
          GameEventLog.global.movement(
              '[${npc.pilotName}] Giving Sector ${dodged.join(', ')} a '
              'wide berth');
        }
        path = bent;
      }
    }
    if (path != null && path.length > 1) {
      final next = path[1];
      GameEventLog.global
          .movement('[${npc.pilotName}] ${steering.type.name}: Sector '
              '${npc.currentSectorId} → Sector $next');
      return npc.spendEnergy(cost).copyWith(
            currentSectorId: next,
          );
    }
  }

  // No goal or unreachable target — wander randomly
  final current = NpcAiService._findSector(sectors, npc.currentSectorId);
  if (current == null || current.warpRoutes.isEmpty) return npc;

  final next =
      current.warpRoutes[NpcAiService._rng.nextInt(current.warpRoutes.length)];
  GameEventLog.global.movement(
      '[${npc.pilotName}] Wander: Sector ${npc.currentSectorId} → Sector $next');
  return npc.spendEnergy(cost).copyWith(
        currentSectorId: next,
      );
}
