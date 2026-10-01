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

/// Threat vector for directional fleeing (P5): the sector of the first
/// overwhelming enemy plus where THEY are headed, if anywhere. Null
/// when nothing outmatches the pilot (aggressors never flee).
({int sector, int? heading})? _threatVector(
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  // Aggressive NPCs never flee
  if (npc.personalityConfig.aggression > 0.7) return null;

  final enemies = _findLocalEnemies(npc, players, allNpcs);
  if (enemies.isEmpty) return null;

  final myPower = CombatService.calculateFirepower(npc);
  for (final enemy in enemies) {
    // Fear: notoriety inflates perceived power. Infamous pilots clear
    // sectors by reputation — weaker ships leave rather than provoke.
    final theirPower = (enemy.power * (1 + enemy.notoriety / 200)).round();
    if (theirPower > myPower * 1.3) {
      return (sector: enemy.sector, heading: enemy.heading);
    }
  }
  return null;
}

/// A local hostile reduced to exactly the four facts threat-avoidance
/// reads. A record rather than `dynamic` (review batch 4): the old
/// `_calculatePower`/`_notorietyOf` pair type-tested the same object on
/// every call, once per enemy per turn, and a type slip there would
/// have silently scored power 0 — i.e. "nothing here is scary".
///
/// [heading] is the sector the enemy is *travelling* towards, resolved
/// here while the object is in hand, so the flee decision never needs to
/// re-acquire (or re-type-test) the ship. Null for players, who hold no
/// NpcGoal.
typedef _LocalEnemy = ({
  int sector,
  int? heading,
  double notoriety,
  int power,
});

List<_LocalEnemy> _findLocalEnemies(
  NpcShip npc,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  final enemies = <_LocalEnemy>[];

  for (final player in players) {
    if (player.currentSectorId == npc.currentSectorId &&
        NpcAiService._isHostileFaction(npc.faction, player.faction)) {
      enemies.add((
        sector: player.currentSectorId,
        heading: null,
        notoriety: player.threatRating,
        power: CombatService.calculatePlayerFirepower(player),
      ));
    }
  }
  // Co-located candidates from the tick index when present (P2).
  final locals = NpcAiService.npcsBySector?[npc.currentSectorId] ?? allNpcs;
  for (final other in locals) {
    if (other.id != npc.id &&
        other.currentSectorId == npc.currentSectorId &&
        !other.isDestroyed &&
        NpcAiService._isHostileFaction(npc.faction, other.faction)) {
      final goal = other.currentGoal;
      final enRoute = goal != null &&
          goal.status == NpcGoalStatus.travelling &&
          goal.targetSectorId != null &&
          goal.targetSectorId != other.currentSectorId;
      enemies.add((
        sector: other.currentSectorId,
        heading: enRoute ? goal.targetSectorId : null,
        notoriety: other.notoriety,
        power: CombatService.calculateFirepower(other),
      ));
    }
  }

  return enemies;
}

NpcShip _setFleeGoal(
  NpcShip npc,
  List<Sector> sectors, {
  required int threatSector,
  int? threatHeading,
}) {
  final current = NpcAiService._findSector(sectors, npc.currentSectorId);
  if (current == null || current.warpRoutes.isEmpty) return npc;

  // Directional flee (P5): run from where the threat is GOING, not
  // where it stands — everything adjacent is 1 hop from here, so
  // raw distance-from-threat can't discriminate. Ties break
  // safe-zone-ward (sanctuary), then random.
  final awayFrom = threatHeading ?? threatSector;
  var best = -2;
  final top = <int>[];
  for (final w in current.warpRoutes) {
    final d = PathfindingService.distance(sectors, w, awayFrom);
    final dd = d >= 9999 ? -1 : d;
    if (dd > best) {
      best = dd;
      top
        ..clear()
        ..add(w);
    } else if (dd == best) {
      top.add(w);
    }
  }
  final pool = top.isEmpty ? current.warpRoutes : top;
  final sanctuary = pool.where((w) {
    final s = NpcAiService._findSector(sectors, w);
    return s != null && NpcAiService._isSafeZone(s.id);
  }).toList();
  final options = sanctuary.isNotEmpty ? sanctuary : pool;
  final targetId = options[NpcAiService._rng.nextInt(options.length)];

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
      _logHop(
          npc,
          '${steering.type.name}: Sector '
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
  _logHop(npc, 'Wander: Sector ${npc.currentSectorId} → Sector $next');
  return npc.spendEnergy(cost).copyWith(
        currentSectorId: next,
      );
}

/// One line of per-ship movement, for the world feed.
///
/// **Every NPC moves every tick**, so writing these unconditionally is two
/// string interpolations plus two ring inserts per ship per tick — 200 NPCs is
/// 400 lines a tick, and the 2,000-entry ring turns over completely every few
/// ticks, so the interesting entries (a kill, a port capture, a legend) are
/// evicted by pilots changing lanes. It also means the string is built whether
/// or not anyone is looking.
///
/// So a hop is written only when it is **newsworthy**, and "newsworthy" is
/// decided by distance rather than by a flag: inside a player's earshot (the
/// same 2-hop proximity the action log uses) a pilot visibly crosses the
/// sector, and anywhere else the position is already implied by the ship
/// being in that sector on the map. The interpolation only happens once the
/// ship is known to be near somebody.
///
/// Trade, combat, banking, goal and distress lines are untouched — those are
/// rare, and they are the content of the feed.
void _logHop(NpcShip npc, String detail) {
  if (!NpcAiService.isNearPlayer(npc.currentSectorId)) return;
  GameEventLog.global.movement('[${npc.pilotName}] $detail');
}
