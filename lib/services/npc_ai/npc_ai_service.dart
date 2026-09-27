import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/combat_metrics.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/banking_ai.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_death_cries.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';
import 'package:cosmic_trader/services/npc_ai/port_combat_service.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
part 'npc_goal_planner.dart';
part 'npc_goal_executor.dart';
part 'npc_movement.dart';
part 'npc_scanner.dart';

class NpcAiService {
  static final math.Random _rng = math.Random();

  /// Max responders converging on one distress call. A 10–20 ship
  /// stampede burns everyone's tanks to arrive at an empty sector;
  /// 1–3 is a wing, not a migration.
  static const int maxDistressResponders = 3;

  /// Hulls with live attack goals on [targetId] (destroyed excluded).
  /// Counts across mechanisms — distress, pack, vendetta, and bounty
  /// hunters all see each other here.
  static int huntersOnTarget(List<NpcShip> allNpcs, String targetId) =>
      _huntersByTarget(allNpcs)[targetId] ?? 0;

  /// Where to look for a remembered target: the sighting while fresh, a
  /// random neighboring sector once the trail ages. Unknown ground
  /// returns the sighting itself.
  static int intelSearchSector(
    VendettaRecord record,
    List<Sector> sectors, {
    int? nowMs,
    math.Random? rng,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if (now - record.lastSeenMs < intelFreshTtl.inMilliseconds) {
      return record.sectorId;
    }
    Sector? at;
    for (final s in sectors) {
      if (s.id == record.sectorId) {
        at = s;
        break;
      }
    }
    final options = at?.warpRoutes ?? const <int>[];
    if (options.isEmpty) return record.sectorId;
    return options[(rng ?? _rng).nextInt(options.length)];
  }

  @visibleForTesting
  static void clearSignalsForTest() => _activeDistressSignals.clear();

  /// Sectors at or below this id are safe zones (no attacks allowed).
  /// Mirrors [GameSettings.fedSpaceEnd]; the shell syncs it at startup
  /// because universe size can move the real boundary (a hardcoded 10
  /// policed the wrong sectors on any other setting).
  static int safeZoneEnd = 10;

  static bool _isSafeZone(int sectorId) => sectorId <= safeZoneEnd;

  /// Credits charged to an NPC for a level-1 Solar Array. NPCs have no
  /// scrap economy, so only credits are charged (player price is 75k cr +
  /// 30 scrap at level 1 — see hardware_data.dart module generation).
  static const int npcSolarArrayCostCredits = 75000;

  /// Reserve (in warp hops) an NPC keeps above its trip home, added on top
  /// of the real path cost to the nearest Hardware Emporium.
  static const int npcRefuelReserveHops = 2;

  /// Patrol legs before the goal completes and re-enters selection.
  static const int maxPatrolLegs = 5;

  /// Fraction of tank below which an NPC always seeks refuel, regardless
  /// of distance.
  static const double npcRefuelFloorFraction = 0.10;

  /// Fraction of tank above which the distance check is skipped (cheap
  /// gate so full-tank NPCs never pay for a BFS — matters at 5000 sectors).
  static const double npcRefuelCheckFraction = 0.25;

  static bool _hasEnergy(NpcShip npc) => npc.energy > 0;

  /// Owner key → owned sectors, rebuilt by GameTickService before every
  /// NPC loop (O(sectors) once per tick instead of per NPC per tick —
  /// 5000 sectors × hundreds of NPCs made the naive scan brutal).
  /// Keyed by ownerId with name fallback, mirroring [Port.isOwnedById].
  /// Null outside ticks (tests, direct calls) → linear-scan fallback.
  static Map<String, List<Sector>>? ownedPortIndex;

  /// Per-tick roster indices (P2 scaling batch), built once by
  /// [beginTick] and cleared by [endTick]. All NPC-loop candidacy reads
  /// prefer them; null (tests, direct calls) falls back to scans, so
  /// behavior is identical with or without setup.
  ///
  /// Staleness contract: topology ([sectorById]) never goes stale
  /// mid-tick. Roster views ([npcsBySector], [npcById], [livingIds]) can
  /// lag one NPC-turn (immutable copies replace list entries as turns
  /// run) — safe because indices only nominate CANDIDATES; every write
  /// path and every combat resolution re-resolves the live object from
  /// [allNpcs] by id, and the death-prune re-checks liveness against
  /// the live list before dropping anything.
  static Map<int, Sector>? sectorById;
  static Map<int, List<NpcShip>>? npcsBySector;
  static Map<String, NpcShip>? npcById;
  static Set<String>? livingIds;

  /// Builds the per-tick indices ([sectorById], [npcsBySector],
  /// [npcById], [livingIds]) plus the shared pathfinding map. Call once
  /// before the NPC loop, [endTick] after.
  static void beginTick(List<Sector> sectors, List<NpcShip> allNpcs) {
    final byId = {for (final s in sectors) s.id: s};
    sectorById = byId;
    PathfindingService.sharedIndex = byId;
    final bySector = <int, List<NpcShip>>{};
    final byNpcId = <String, NpcShip>{};
    final alive = <String>{};
    for (final n in allNpcs) {
      (bySector[n.currentSectorId] ??= []).add(n);
      byNpcId[n.id] = n;
      if (!n.isDestroyed) alive.add(n.id);
    }
    npcsBySector = bySector;
    npcById = byNpcId;
    livingIds = alive;
  }

  /// Clears the per-tick indices (nulls restore scan fallbacks).
  static void endTick() {
    sectorById = null;
    npcsBySector = null;
    npcById = null;
    livingIds = null;
    PathfindingService.sharedIndex = null;
  }

  static List<Sector> _ownedSectors(NpcShip npc, List<Sector> sectors) {
    final index = ownedPortIndex;
    if (index == null) {
      return [
        for (final s in sectors)
          if (s.port?.isOwnedById(npc.id, npc.pilotName) ?? false) s,
      ];
    }
    final seen = <int>{};
    final out = <Sector>[];
    for (final key in [npc.id, npc.pilotName]) {
      for (final s in index[key] ?? const <Sector>[]) {
        if (seen.add(s.id) &&
            (s.port?.isOwnedById(npc.id, npc.pilotName) ?? false)) {
          out.add(s);
        }
      }
    }
    return out;
  }

  /// Goals cheap to interrupt when something more urgent (banking, refuel,
  /// distress) comes up. Trade/attack/raid carry multi-leg state in
  /// goal.params — clobbering them mid-route strands cargo and wastes trips,
  /// so they run to completion unless fleeing or bone-dry (see below).
  ///
  /// Goal-interruption policy (locked 2026-09-26, Phase C contract):
  ///
  /// | Current state              | Incoming event                    | Behavior              |
  /// |----------------------------|-------------------------------------|-----------------------|
  /// | Idle / exploring           | vendetta / distress / banking       | may take new goal     |
  /// | Patrol (interruptible)     | any                                 | may redirect          |
  /// | Trading (committed route)  | any                                 | preserve unless floor |
  /// | Refueling (critical)       | any                                 | never abandon         |
  /// | Fleeing                    | any, incl. revenge target visible   | keep escaping         |
  /// | Actively fighting          | reinforcement request               | combat rules, no swap |
  /// | Dead/completed/failed goal | any                                 | clear/resolve first   |
  ///
  /// Vendettas (see [NpcMemory.vendettas]) influence selection through
  /// this policy — they never overwrite a committed goal directly.
  static bool _isInterruptible(NpcShip npc) {
    final type = npc.currentGoal?.type;
    return type == null ||
        type == NpcGoalType.explore ||
        type == NpcGoalType.patrol;
  }

  // ────────────────────────────────────────────────────────────────
  // Public entry point
  // ────────────────────────────────────────────────────────────────

  /// Process one turn for [npc].
  ///
  /// Returns the updated NPC. If combat occurred against another NPC,
  /// that NPC is updated in-place in [allNpcs].
  static NpcShip processTurn(
    NpcShip npc,
    List<Sector> sectors,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    if (npc.isDestroyed) return npc;

    var updated = npc;

    // 0 — Solar Array trickle-charge (deployed arrays regen, lock movement).
    final recharge = EnergyService.npcSolarRecharge(updated);
    if (recharge.unitsAdded > 0) {
      GameEventLog.global
          .energy('NPC_ENERGY event=solar_recharge pilot=${updated.pilotName} '
              'units=${recharge.unitsAdded} energy=${recharge.npc.energy}');
      updated = recharge.npc;
    }

    // 1 — Scan the current sector
    updated = _scanSector(updated, sectors, players, allNpcs);

    // 1b — Drop grudges whose targets are gone from the world (C2b):
    // absent from both the NPC roster and the player list, or flying
    // as wreckage. Vengeance needs a living target.
    updated = _pruneDeadVendettas(updated, players, allNpcs);

    // 2 — Execute the current goal (trade, bank, explore, etc.)
    updated = _executeGoal(updated, sectors, allNpcs);

    if (updated.isDestroyed) {
      GameEventLog.global.combat(
          '[${updated.pilotName}] Destroyed in Sector ${updated.currentSectorId}');
      return updated;
    }

    // 2c — Wingmate gossip (C2d): co-located allies trade sightings.
    // Runs only for the living (review batch 3, P1): a ship killed in
    // its own execution has no death rattle to share.
    updated = _shareIntel(updated, allNpcs);

    // 2d — Co-located barter (P5): holds meet holds, one deal per turn.
    updated = _barterWithNpc(updated, allNpcs);

    // 2b — Manage owned ports: collect revenue, buy upgrades. Runs
    // independent of the active goal (paperwork needs no travel).
    updated = _manageOwnedPorts(updated, sectors);

    // 3 — Evaluate threats → flee directionally if outmatched
    final threat = _threatVector(updated, sectors, players, allNpcs);
    if (_hasEnergy(updated) && threat != null) {
      updated = _setFleeGoal(updated, sectors,
          threatSector: threat.sector, threatHeading: threat.heading);
    }

    // 3b — Respond to nearby distress signals (override interruptible
    // goals only; never yank a trade/attack/raid mid-leg). Unarmed NPCs
    // sit out — sending power-0 responders into fights is pointless.
    if (_hasEnergy(updated) &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        _isInterruptible(updated) &&
        updated.totalWeaponPower > 0) {
      final distressGoal = _respondToDistress(updated, sectors, allNpcs);
      if (distressGoal != null) {
        updated = updated.copyWith(currentGoal: distressGoal);
      }
    }

    // 4 — Evaluate banking needs (interruptible goals only; a travelling
    // trade keeps its buy/sell legs instead of being clobbered right
    // after buying).
    if (_hasEnergy(updated) &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        _isInterruptible(updated) &&
        BankingAi.shouldDeposit(updated)) {
      final goal = BankingAi.createDepositGoal(updated, sectors);
      if (goal != null) {
        GameEventLog.global
            .banking('[${updated.pilotName}] Banking: Heading to deposit '
                '${goal.params['depositAmount']} cr');
        updated = updated.copyWith(currentGoal: goal);
      }
    }
    if (_hasEnergy(updated) &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        _isInterruptible(updated) &&
        BankingAi.shouldWithdraw(updated)) {
      final goal = BankingAi.createWithdrawGoal(updated, sectors);
      if (goal != null) {
        GameEventLog.global
            .banking('[${updated.pilotName}] Banking: Heading to withdraw cr');
        updated = updated.copyWith(currentGoal: goal);
      }
    }

    // 4b — Evaluate energy needs. Interruptible goals yield immediately;
    // committed multi-leg goals only yield below the emergency floor
    // (stranding mid-route wastes the trip, but running dry is worse —
    // and post-buy cargo converts to a sell-first route on replan).
    final energyCritical =
        updated.energy < (updated.maxEnergy * npcRefuelFloorFraction).ceil();
    if (_hasEnergy(updated) &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        updated.currentGoal?.type != NpcGoalType.refuelEnergy &&
        (_isInterruptible(updated) || energyCritical) &&
        shouldRefuel(updated, sectors)) {
      final goal = createRefuelGoal(updated, sectors);
      if (goal != null) {
        GameEventLog.global
            .energy('NPC_ENERGY event=refuel_goal pilot=${updated.pilotName} '
                'energy=${updated.energy} target=${goal.targetSectorId}');
        updated = updated.copyWith(currentGoal: goal);
      } else {
        // Fuel low but no emporium discovered yet — roam to find one, but
        // only when nothing committed is running. Firing this every tick
        // while energy sits under 25% permanently suppressed step-5 goal
        // selection (trade/bank/attack never ran); a travelling trade
        // keeps draining toward stranded reserves instead, which recover.
        if (_needsNewGoal(updated) || _isInterruptible(updated)) {
          GameEventLog.global.energy(
              'NPC_ENERGY event=refuel_unknown pilot=${updated.pilotName} '
              'energy=${updated.energy}');
          updated = updated.copyWith(
              currentGoal: _createExploreGoal(updated, sectors));
        }
      }
    }

    // 5 — Select a new goal if none is active
    if (_hasEnergy(updated) && _needsNewGoal(updated)) {
      final goal = _selectGoal(updated, sectors, players, allNpcs);
      if (goal != null) {
        updated = updated.copyWith(currentGoal: goal);
        final targetStr = goal.targetSectorId != null
            ? '→ Sector ${goal.targetSectorId}'
            : '';
        GameEventLog.global
            .goal('[${updated.pilotName}] Goal: ${goal.type.name} $targetStr');
      }
    }

    // 6 — Move one hop towards the goal
    if (_hasEnergy(updated)) {
      updated = _move(updated, sectors, allNpcs);
    } else if (!updated.isDestroyed) {
      updated = _handleStranded(updated);
    }

    return updated;
  }

  // ────────────────────────────────────────────────────────────────
  // Energy — refuel, solar, stranded
  // ────────────────────────────────────────────────────────────────

  /// True when [npc] should interrupt its plan to refuel.
  ///
  /// Distance-aware: the trigger is the real trip cost to the nearest
  /// Hardware Emporium (hops × per-hop cost for this NPC's engine, plus a
  /// reserve), so thirsty-engine ships and far-flung sectors both head home
  /// earlier. Below a flat 10% floor the NPC always seeks refuel; above 25%
  /// it never does (cheap gate, no pathfinding).
  ///
  /// Like human players, NPCs must *discover* emporiums first — only ports
  /// recorded in [NpcMemory.discoveredPorts] (via sector scans) count. An
  /// NPC that needs fuel but knows no emporium also returns true so the
  /// caller can send it exploring instead of sitting still.
  static bool shouldRefuel(NpcShip npc, List<Sector> sectors) {
    if (npc.isDestroyed) return false;
    if (npc.energy >= (npc.maxEnergy * npcRefuelCheckFraction).ceil()) {
      return false;
    }
    if (npc.energy < (npc.maxEnergy * npcRefuelFloorFraction).ceil()) {
      return true;
    }
    final path = nearestEmporiumPath(npc, sectors);
    if (path == null) return true; // fuel low, no known emporium — go find one
    final legCost = EnergyService.npcWarpCost(npc);
    final tripCost =
        (path.length - 1) * legCost + legCost * npcRefuelReserveHops;
    return npc.energy < tripCost;
  }

  /// Sector IDs of Hardware Emporiums this NPC has actually discovered.
  static Set<int> knownEmporiumSectors(NpcShip npc) {
    return {
      for (final entry in npc.memory.discoveredPorts.entries)
        if (entry.value.portClass == PortClass.hardwareEmporium) entry.key,
    };
  }

  /// Goal targeting the nearest Hardware Emporium for refuel.
  static NpcGoal? createRefuelGoal(NpcShip npc, List<Sector> sectors) {
    final path = nearestEmporiumPath(npc, sectors);
    if (path == null || path.isEmpty) return null;
    return NpcGoal(
      type: NpcGoalType.refuelEnergy,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': path.last},
    );
  }

  /// Zero-energy fallback: withdraw-backed emergency reserve, then idle.
  /// NPCs never hard-lock a human session, so no tow teleport is needed —
  /// they wait for regen or their next reserve. The reserve is ALWAYS
  /// granted, even when broke (deducting only what exists): a penniless NPC
  /// that idles forever is a dead NPC, and live universes showed Vinari
  /// explorers spiraling to exactly 0cr and freezing for good.
  static NpcShip _handleStranded(NpcShip npc) {
    if (npc.solarArrayLevel > 0 && !npc.solarArrayDeployed) {
      GameEventLog.global
          .energy('NPC_ENERGY event=array_deploy pilot=${npc.pilotName}');
      return npc.copyWith(solarArrayDeployed: true);
    }
    final reserve = EnergyService.npcEmergencyEnergy(npc);
    final fromBank = npc.credits >= reserve
        ? 0
        : (reserve - npc.credits).clamp(0, npc.bankBalance);
    final fromCredits = (reserve - fromBank).clamp(0, npc.credits);
    GameEventLog.global
        .energy('NPC_ENERGY event=emergency_reserve pilot=${npc.pilotName} '
            'units=$reserve fromBank=$fromBank');
    return npc
        .copyWith(
          credits: npc.credits - fromCredits,
          bankBalance: npc.bankBalance - fromBank,
        )
        .refuelEnergy(reserve);
  }

  /// Evaluate whether [npc] should initiate combat against [player].
  /// The NPC must:
  ///   1. Be from a hostile faction (or personally hate the player, below)
  ///   2. Have sufficient aggression (pirates: ≥0.3, others: ≥0.7)
  ///   3. Have enough hull (≥30%)
  ///   4. Have a firepower advantage scaled by its caution — and larger
  ///      against notorious players (fear cuts both ways: the fearsome
  ///      are attacked only by the confident)
  ///   5. Personal hatred (standing ≤ −50) substitutes for faction
  ///      hostility, but demands a decisive 1.5× edge — grudges don't
  ///      make NPCs suicidal.
  ///
  ///   power threshold = (1.2 + caution × 0.8) × (1 + notoriety / 200)
  static bool shouldAttackPlayer(NpcShip npc, Player player) {
    if (npc.isDestroyed) return false;
    if (npc.hull < npc.maxHull * 0.3) return false;

    final aggression = npc.personalityConfig.aggression;
    final caution = npc.personalityConfig.caution;

    // Pirates are naturally aggressive; other factions need higher aggression
    final minAggression = npc.faction == FactionClass.pirate ? 0.3 : 0.7;
    if (aggression < minAggression) return false;

    final hostile = _isHostileFaction(npc.faction, player.faction);
    final hatred = player.factionStandingWith(npc.faction) <= -50;
    if (!hostile && !hatred) return false;

    final npcPower = CombatService.calculateFirepower(npc);
    final playerPower = CombatService.calculatePlayerFirepower(player);
    if (playerPower <= 0) return true;

    // Higher caution = needs bigger power advantage; notoriety inflates
    // the requirement (fear); personal hatred without lore hostility
    // demands a decisive edge.
    var powerThreshold = (1.2 + caution * 0.8) * (1 + player.notoriety / 200);
    if (!hostile) powerThreshold *= 1.5;
    return npcPower > playerPower * powerThreshold;
  }

  static const int _maxEquipmentLevel = 5;
  static const int _maxWeaponLevel = 3;

  /// Last-seen sectors of vendetta targets stronger than [npc] (C2c).
  /// Intel, not radar: sectors come from memory, but strength is checked
  /// against the live roster — a grudge against a rust-bucket nobody
  /// fears. Feeds danger-weighted trade and movement avoidance.
  static Set<int> fearedSectors(NpcShip npc, List<NpcShip> allNpcs) {
    if (npc.memory.vendettas.isEmpty) return const {};
    final myPower = CombatService.calculateFirepower(npc);
    final feared = <int>{};
    // O(1) id lookups via the tick index when present (P2).
    final index = NpcAiService.npcById;
    for (final entry in npc.memory.vendettas.entries) {
      if (index != null) {
        final n = index[entry.key];
        if (n != null &&
            !n.isDestroyed &&
            CombatService.calculateFirepower(n) >= myPower) {
          feared.add(entry.value.sectorId);
        }
        continue;
      }
      for (final n in allNpcs) {
        if (n.id != entry.key || n.isDestroyed) continue;
        if (CombatService.calculateFirepower(n) >= myPower) {
          feared.add(entry.value.sectorId);
        }
        break;
      }
    }
    return feared;
  }

  /// Asking price for an NPC port purchase. Set at 10% of net worth
  /// (floor 25k): half-net-worth priced every NPC out forever (ports hold
  /// millions in credits alone), so economic conquest never fired and only
  /// raiders ever took ports. Unowned non-federal ports only — federal,
  /// emporium, player, and NPC-owned ports are never for sale to NPCs.
  static int npcPortPrice(Port port) =>
      math.max(25000, (port.netWorth * 0.1).round());

  // ────────────────────────────────────────────────────────────────
  // Faction hostility
  // ────────────────────────────────────────────────────────────────

  static bool _isHostileFaction(FactionClass a, FactionClass b) {
    if (a == b) return false;
    if (a == FactionClass.pirate || b == FactionClass.pirate) return true;
    // Duran vs Vinari are always hostile
    if (a == FactionClass.duran && b == FactionClass.vinari) return true;
    if (a == FactionClass.vinari && b == FactionClass.duran) return true;
    return false;
  }

  // ────────────────────────────────────────────────────────────────
  // Helpers
  // ────────────────────────────────────────────────────────────────

  static Sector? _findSector(List<Sector> sectors, int id) {
    final index = sectorById;
    if (index != null) return index[id];
    for (final s in sectors) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Find a random adjacent sector (non-self) for NPC owner flee.
  static int? _findAdjacentSector(List<Sector> sectors, int sectorId) {
    final sector = _findSector(sectors, sectorId);
    if (sector == null || sector.warpRoutes.isEmpty) return null;
    final adj = sector.warpRoutes[_rng.nextInt(sector.warpRoutes.length)];
    return adj;
  }

  static NpcShip? _findNpcById(List<NpcShip> npcs, String id) {
    for (final n in npcs) {
      if (n.id == id && !n.isDestroyed) return n;
    }
    return null;
  }
}
