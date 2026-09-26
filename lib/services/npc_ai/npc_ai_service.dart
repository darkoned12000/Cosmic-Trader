import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
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

class NpcAiService {
  static final math.Random _rng = math.Random();

  /// Active distress signals keyed by the defender's NPC id.
  static final Map<String, DistressSignal> _activeDistressSignals = {};

  /// Max responders converging on one distress call. A 10–20 ship
  /// stampede burns everyone's tanks to arrive at an empty sector;
  /// 1–3 is a wing, not a migration.
  static const int maxDistressResponders = 3;

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

    // 2 — Execute the current goal (trade, bank, explore, etc.)
    updated = _executeGoal(updated, sectors, allNpcs);

    if (updated.isDestroyed) {
      GameEventLog.global.combat(
          '[${updated.pilotName}] Destroyed in Sector ${updated.currentSectorId}');
      return updated;
    }

    // 2b — Manage owned ports: collect revenue, buy upgrades. Runs
    // independent of the active goal (paperwork needs no travel).
    updated = _manageOwnedPorts(updated, sectors);

    // 3 — Evaluate threats → flee immediately if outmatched
    if (_hasEnergy(updated) &&
        _evaluateThreat(updated, sectors, players, allNpcs)) {
      updated = _setFleeGoal(updated, sectors);
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
      updated = _move(updated, sectors);
    } else if (!updated.isDestroyed) {
      updated = _handleStranded(updated);
    }

    return updated;
  }

  // ────────────────────────────────────────────────────────────────
  // Step 1 — Sector scanner
  // ────────────────────────────────────────────────────────────────

  static NpcShip _scanSector(
    NpcShip npc,
    List<Sector> sectors,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    var memory = npc.memory;

    // Find the sector
    final sector = _findSector(sectors, npc.currentSectorId);
    if (sector == null) return npc;

    // Mark visited
    memory = memory.withVisitedSector(sector.id);

    // Discover port
    if (sector.hasPort && sector.port != null) {
      final p = sector.port!;
      memory = memory.withDiscoveredPort(
        sector.id,
        PortInfo(
          name: p.name,
          portClass: p.portClass,
          buyPrices: Map.from(p.buyPrices),
          sellPrices: Map.from(p.sellPrices),
          defenseLevel: p.defenseLevel,
          portCredits: p.portCredits,
          desiredCredits: p.desiredCredits,
          owner: p.owner,
          ownerFaction: p.ownerFaction,
          sellFactors: {
            for (final c in p.sellPrices.keys)
              c: p.supplyPriceMultiplier(c) * p.driftFor(c),
          },
          buyFactors: {
            for (final c in p.buyPrices.keys)
              c: p.demandPriceMultiplier(c) *
                  p.driftFor(c) *
                  (p.regionalBuyBonus[c] ?? 1.0) *
                  p.anomalyBuyBonus,
          },
        ),
      );
    }

    // Record hazards
    if (sector.navHaz || sector.anomaly != null) {
      memory = memory.withKnownHazard(
        sector.id,
        HazardInfo(navHaz: sector.navHaz, anomaly: sector.anomaly),
      );
    }

    // Detect threats (other factions in the same sector)
    for (final player in players) {
      if (player.currentSectorId == sector.id &&
          _isHostileFaction(npc.faction, player.faction)) {
        memory = memory.withThreat(player.id);
      }
    }
    for (final other in allNpcs) {
      if (other.id != npc.id &&
          other.currentSectorId == sector.id &&
          !other.isDestroyed &&
          _isHostileFaction(npc.faction, other.faction)) {
        memory = memory.withThreat(other.id);
      }
    }

    return npc.copyWith(memory: memory);
  }

  // ────────────────────────────────────────────────────────────────
  // Step 2 — Goal execution
  // ────────────────────────────────────────────────────────────────

  static NpcShip _executeGoal(
    NpcShip npc,
    List<Sector> sectors,
    List<NpcShip> allNpcs,
  ) {
    final goal = npc.currentGoal;
    if (goal == null ||
        goal.status == NpcGoalStatus.complete ||
        goal.status == NpcGoalStatus.failed) {
      return npc;
    }

    switch (goal.type) {
      case NpcGoalType.tradeRoute:
        return _executeTradeGoal(npc, sectors, goal);
      case NpcGoalType.bankDeposit:
        return _executeBankDepositGoal(npc, sectors, goal);
      case NpcGoalType.bankWithdraw:
        return _executeBankWithdrawGoal(npc, sectors, goal);
      case NpcGoalType.explore:
        return _executeExploreGoal(npc, sectors, goal);
      case NpcGoalType.patrol:
        return _executePatrolGoal(npc, sectors, goal);
      case NpcGoalType.flee:
        return _executeFleeGoal(npc, sectors, goal);
      case NpcGoalType.attack:
        return _executeAttackGoal(npc, sectors, allNpcs, goal);
      case NpcGoalType.raidPort:
        return _executeRaidPortGoal(npc, sectors, allNpcs, goal);
      case NpcGoalType.upgradeEquipment:
        return _executeUpgradeGoal(npc, sectors, goal);
      case NpcGoalType.refuelEnergy:
        return _executeRefuelGoal(npc, sectors, goal);
      case NpcGoalType.buyPort:
        return _executeBuyPortGoal(npc, sectors, goal);
    }
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

  /// Hop path to the nearest *discovered* Hardware Emporium that will
  /// actually serve this NPC, or null when none is known, reachable, or
  /// friendly. Hostile emporiums (standing ≤ −50) are skipped like
  /// undiscovered ones — the NPC roams instead of flying into a refusal.
  /// Single hop-list source for both [shouldRefuel] and [createRefuelGoal].
  static List<int>? nearestEmporiumPath(
    NpcShip npc,
    List<Sector> sectors,
  ) {
    final known = knownEmporiumSectors(npc);
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
      final here = _findSector(sectors, npc.currentSectorId);
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

  static NpcShip _executeRefuelGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;
    // Memory can go stale (port destroyed/captured) — fail cleanly so the
    // NPC re-plans instead of drinking from an empty pump.
    final sector = _findSector(sectors, npc.currentSectorId);
    if (sector?.port?.isHardwareEmporium != true) {
      GameEventLog.global
          .energy('NPC_ENERGY event=refuel_stale pilot=${npc.pilotName} '
              'sector=${npc.currentSectorId}');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.failed),
      );
    }
    final emporiumStanding = FactionStanding.resolveFor(
      npc.faction,
      sector!.port!.ownerFaction,
      npc.memory.factionStandings,
    );
    if (sector.port!.deniesServiceTo(emporiumStanding)) {
      GameEventLog.global
          .energy('NPC_ENERGY event=refuel_refused pilot=${npc.pilotName} '
              'standing=$emporiumStanding');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.failed),
      );
    }
    final result = EnergyService.npcRefuel(npc);
    if (result.unitsAdded <= 0) {
      // Broke or full — don't loop on the pump; try banking next tick.
      GameEventLog.global
          .energy('NPC_ENERGY event=refuel_empty pilot=${npc.pilotName} '
              'energy=${npc.energy} credits=${npc.credits}');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.failed),
      );
    }
    GameEventLog.global
        .energy('NPC_ENERGY event=refuel_buy pilot=${npc.pilotName} '
            'units=${result.unitsAdded} spent=${result.creditsSpent} '
            'energy=${result.npc.energy}');
    ActionLogProvider.global.trade(
      '${npc.pilotName} refueled ${result.unitsAdded} energy '
      '(${result.creditsSpent} cr)',
    );
    return result.npc.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
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

  /// Logs a dead trade route, starts its cooldown, and clears the goal so
  /// reselection can run. Every terminal failure below is visible in the
  /// trade log — silent kills were how live trade volume dropped to zero
  /// unnoticed.
  static NpcShip _failTrade(NpcShip npc, NpcGoal goal, String reason) {
    GameEventLog.global.trade(
      '[${npc.pilotName}] Trade: route failed ($reason)',
    );
    final key =
        NpcMemory.routeKey(goal.buyPortId, goal.sellPortId, goal.commodity);
    return npc.copyWith(
      clearGoal: true,
      memory: npc.memory.withFailedRoute(key),
    );
  }

  static NpcShip _executeTradeGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    final buyPortId = goal.buyPortId;
    final sellPortId = goal.sellPortId;
    final commodity = goal.commodity;
    if (buyPortId == null || sellPortId == null || commodity == null) {
      return npc.copyWith(clearGoal: true);
    }

    final phase = goal.params['phase'] as String? ?? 'travel_to_buy';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ── Phase: arrived at buy port ──
    if (phase == 'travel_to_buy' && npc.currentSectorId == buyPortId) {
      final sector = _findSector(sectors, buyPortId);
      if (sector == null) {
        return _failTrade(npc, goal, 'buy sector $buyPortId vanished');
      }
      var port = sector.port;
      if (port == null) {
        return _failTrade(npc, goal, '${sector.name} lost its port');
      }

      // Regen before reading
      port = port.regen(now: nowMs);
      sector.port = port;

      final sellPrice = port.getEffectiveSellPriceFor(
        commodity,
        standing: FactionStanding.resolveFor(
          npc.faction,
          port.ownerFaction,
          npc.memory.factionStandings,
        ),
      );
      if (sellPrice <= 0) {
        return _failTrade(npc, goal, '${port.name} no longer sells $commodity');
      }

      final availableHolds = npc.cargoHoldCapacity - npc.cargoUsed;
      if (availableHolds <= 0) {
        return _failTrade(npc, goal, 'holds full');
      }

      final availableSupply = port.getSupply(commodity);
      if (availableSupply <= 0) {
        return _failTrade(npc, goal, '${port.name} out of $commodity supply');
      }

      // Affordability includes the owner surcharge (omitting it drove
      // credits negative whenever cost landed within 5% of the bankroll —
      // caught live by the credits>=0 assert).
      final taxRate = port.isOwned ? port.ownerTaxRate : 0.0;
      final unitCost = sellPrice * (1 + taxRate);
      final affordable = unitCost <= 0
          ? availableHolds.clamp(0, availableSupply)
          : (npc.credits / unitCost).floor();
      if (affordable <= 0) {
        return _failTrade(
            npc, goal, 'cannot afford 1 $commodity at ${port.name}');
      }
      var maxBuyable =
          affordable.clamp(1, availableHolds.clamp(0, availableSupply));
      var cost = (maxBuyable * sellPrice).round();
      var ownerSurcharge =
          port.isOwned ? (cost * port.ownerTaxRate).round() : 0;
      // Rounding guard: never let cost + fee exceed the bankroll.
      while (maxBuyable > 0 && cost + ownerSurcharge > npc.credits) {
        maxBuyable--;
        cost = (maxBuyable * sellPrice).round();
        ownerSurcharge = port.isOwned ? (cost * port.ownerTaxRate).round() : 0;
      }
      if (maxBuyable <= 0) {
        GameEventLog.global.trade(
            '[${npc.pilotName}] Trade: Not enough credits for $commodity at ${port.name}');
        return npc.copyWith(clearGoal: true);
      }

      final newCargo = Map<String, int>.from(npc.cargo);
      newCargo[commodity] = (newCargo[commodity] ?? 0) + maxBuyable;

      // Mutate port: decrement supply, add credits (port earns from selling)
      final newSupply = Map<String, int>.from(port.supply);
      newSupply[commodity] = availableSupply - maxBuyable;
      sector.port = port.copyWith(
        supply: newSupply,
        portCredits: port.portCredits + cost,
        accumulatedRevenue: port.accumulatedRevenue + ownerSurcharge,
        lastRegenTime: nowMs,
      );

      GameEventLog.global.trade(
          '[${npc.pilotName}] Trade: Bought $maxBuyable $commodity at '
          '${port.name} (${sellPrice.toStringAsFixed(0)} cr)'
          '${ownerSurcharge > 0 ? ' [+${ownerSurcharge}cr owner fee]' : ''}');
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: maxBuyable,
        credits: cost + ownerSurcharge,
        actorFaction: npc.faction.name,
        isPlayer: false,
        isBuy: true,
      );

      return npc.copyWith(
        credits: npc.credits - cost - ownerSurcharge,
        cargo: newCargo,
        cargoUsed: npc.cargoUsed + maxBuyable,
        currentGoal: goal.copyWith(
          params: {
            ...goal.params,
            'targetSectorId': sellPortId,
            'phase': 'travel_to_sell',
            'buyPrice': sellPrice,
          },
        ),
      );
    }

    // ── Phase: arrived at sell port ──
    if (phase == 'travel_to_sell' && npc.currentSectorId == sellPortId) {
      final sector = _findSector(sectors, sellPortId);
      if (sector == null) {
        return _failTrade(npc, goal, 'sell sector $sellPortId vanished');
      }
      var port = sector.port;
      if (port == null) {
        return _failTrade(npc, goal, '${sector.name} lost its port');
      }

      // Regen before reading
      port = port.regen(now: nowMs);
      sector.port = port;

      final buyPrice = port.getEffectiveBuyPriceFor(
        commodity,
        standing: FactionStanding.resolveFor(
          npc.faction,
          port.ownerFaction,
          npc.memory.factionStandings,
        ),
      );
      if (buyPrice <= 0) {
        return _failTrade(npc, goal, '${port.name} no longer buys $commodity');
      }

      var quantity = npc.cargo[commodity] ?? 0;
      if (quantity <= 0) {
        return _failTrade(npc, goal, 'hold empty of $commodity');
      }

      // Cap by available demand
      final availableDemand = port.getDemand(commodity);
      if (availableDemand <= 0) {
        return _failTrade(npc, goal, '${port.name} has no $commodity demand');
      }
      quantity = quantity.clamp(1, availableDemand);

      // Cap by port credits
      final grossRevenue = (quantity * buyPrice).round();
      final actualRevenue = grossRevenue.clamp(0, port.portCredits.floor());
      if (actualRevenue <= 0) {
        GameEventLog.global
            .trade('[${npc.pilotName}] Trade: Port ${port.name} has '
                'insufficient credits to buy $quantity $commodity');
        return npc.copyWith(clearGoal: true);
      }

      // Recompute quantity if port is short on credits. Floor first —
      // clamping a zero affordable quantity up to 1 would force a
      // below-value sale, so bail out instead.
      final affordableQty = (actualRevenue / buyPrice).floor();
      if (affordableQty <= 0) {
        return _failTrade(npc, goal, '${port.name} cannot cover 1 $commodity');
      }
      final actualQuantity = affordableQty.clamp(1, quantity);

      final cost =
          goal.buyPrice != null ? (actualQuantity * goal.buyPrice!).round() : 0;
      final profit = actualRevenue - cost;
      final newCargo = Map<String, int>.from(npc.cargo);
      newCargo[commodity] = newCargo[commodity]! - actualQuantity;
      if (newCargo[commodity]! <= 0) newCargo.remove(commodity);

      // Mutate port: decrement demand, deduct credits, owner collects transaction fee
      final newDemand = Map<String, int>.from(port.demand);
      newDemand[commodity] = availableDemand - actualQuantity;
      final ownerTax =
          port.isOwned ? (actualRevenue * port.ownerTaxRate).round() : 0;
      final npcReceives = actualRevenue - ownerTax;
      sector.port = port.copyWith(
        demand: newDemand,
        portCredits: port.portCredits - actualRevenue,
        accumulatedRevenue: port.accumulatedRevenue + ownerTax,
        lastRegenTime: nowMs,
      );

      GameEventLog.global.trade(
          '[${npc.pilotName}] Trade: Sold $actualQuantity $commodity at '
          '${port.name} (${buyPrice.toStringAsFixed(0)} cr) '
          '${goal.buyPrice != null ? '— ${profit >= 0 ? "profit" : "loss"} ${profit.abs()} cr' : '— cleared holds for $actualRevenue cr'}'
          '${ownerTax > 0 ? ' [-${ownerTax}cr owner fee]' : ''}');
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: actualQuantity,
        credits: npcReceives,
        actorFaction: npc.faction.name,
        isPlayer: false,
        isBuy: false,
      );

      return npc.copyWith(
        credits: npc.credits + npcReceives,
        cargo: newCargo,
        cargoUsed: npc.cargoUsed - actualQuantity,
        memory: npc.memory.copyWith(lastTradeTime: DateTime.now()),
        currentGoal: goal.copyWith(
          status: NpcGoalStatus.complete,
          params: {...goal.params, 'profit': profit},
        ),
      );
    }

    return npc;
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

  /// Owner paperwork: collect accumulated revenue from owned ports and
  /// buy one defense or storage upgrade when flush (50k operating reserve
  /// kept). Turns ownership from a flag into the income engine.
  static NpcShip _manageOwnedPorts(NpcShip npc, List<Sector> sectors) {
    var updated = npc;

    for (final sector in _ownedSectors(npc, sectors)) {
      final port = sector.port;
      if (port == null) continue;

      // Collect revenue.
      final revenue = port.accumulatedRevenue.floor();
      if (revenue > 0) {
        if (revenue >= 10000) {
          GameEventLog.global.trade(
            '[${npc.pilotName}] Port income: collected $revenue cr '
            'from ${port.name}',
          );
        }
        sector.port = port.copyWith(accumulatedRevenue: 0.0);
        updated = updated.copyWith(credits: updated.credits + revenue);
      }

      // One upgrade per tick max: defense first, then storage.
      final live = sector.port!;
      if (live.defenseLevel < 4) {
        final cost = live.defenseUpgradeCost.round();
        if (updated.credits - cost >= 50000) {
          sector.port = live.copyWith(defenseLevel: live.defenseLevel + 1);
          updated = updated.copyWith(credits: updated.credits - cost);
          GameEventLog.global.goal(
            '[${npc.pilotName}] Port upgrade: ${port.name} defenses → '
            'level ${live.defenseLevel + 1} for $cost cr',
          );
          break;
        }
      } else if (live.storageLevel < 10) {
        final cost = live.storageUpgradeCost;
        if (cost.isFinite && updated.credits - cost.round() >= 50000) {
          sector.port = live.copyWith(storageLevel: live.storageLevel + 1);
          updated = updated.copyWith(credits: updated.credits - cost.round());
          GameEventLog.global.goal(
            '[${npc.pilotName}] Port upgrade: ${port.name} storage → '
            'level ${live.storageLevel + 1}',
          );
          break;
        }
      }
    }
    return updated;
  }

  static NpcShip _executeBankDepositGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    // Destination must still be a live port — memory goes stale when
    // ports are captured/destroyed en route (same rule as refuel/trade).
    final sector = _findSector(sectors, npc.currentSectorId);
    if (sector?.port == null) {
      GameEventLog.global.banking(
          '[${npc.pilotName}] Banking: port at Sector ${npc.currentSectorId} '
          'gone — deposit aborted');
      return npc.copyWith(clearGoal: true);
    }

    final result = BankingAi.executeDeposit(npc, goal);
    if (!result.executed) {
      return npc.copyWith(clearGoal: true);
    }

    final deposited = (npc.credits - result.npc.credits).abs();
    GameEventLog.global
        .banking('[${result.npc.pilotName}] Banking: Deposited $deposited cr '
            '(bank: ${result.npc.bankBalance} cr)');

    return result.npc.copyWith(
      memory: result.npc.memory.copyWith(lastBankTime: DateTime.now()),
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcShip _executeBankWithdrawGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final sector = _findSector(sectors, npc.currentSectorId);
    if (sector?.port == null) {
      GameEventLog.global.banking(
          '[${npc.pilotName}] Banking: port at Sector ${npc.currentSectorId} '
          'gone — withdrawal aborted');
      return npc.copyWith(clearGoal: true);
    }

    final result = BankingAi.executeWithdraw(npc, goal);
    if (!result.executed) {
      return npc.copyWith(clearGoal: true);
    }

    final withdrawn = (result.npc.credits - npc.credits).abs();
    GameEventLog.global
        .banking('[${result.npc.pilotName}] Banking: Withdrew $withdrawn cr');

    return result.npc.copyWith(
      memory: result.npc.memory.copyWith(lastBankTime: DateTime.now()),
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcShip _executeExploreGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId == goal.targetSectorId) {
      GameEventLog.global.goal(
          '[${npc.pilotName}] Explore: Reached Sector ${goal.targetSectorId}');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }
    return npc;
  }

  static NpcShip _executePatrolGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId == goal.targetSectorId) {
      // Patrols expire after a few legs so the NPC re-enters goal selection
      // (trade/attack/bank) instead of wandering forever. An absorbing
      // patrol was a live stall bug: once adopted, _needsNewGoal never fired
      // again and all trade/combat/banking stopped.
      final legs = (goal.params['legs'] as int? ?? 0) + 1;
      if (legs >= maxPatrolLegs) {
        return npc.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
        );
      }
      // Pick a new random patrol target
      final current = _findSector(sectors, npc.currentSectorId);
      if (current == null || current.warpRoutes.isEmpty) {
        return npc.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
        );
      }
      final next = current.warpRoutes[_rng.nextInt(current.warpRoutes.length)];
      return npc.copyWith(
        currentGoal: goal.copyWith(
          params: {
            'targetSectorId': next,
            'homeSector': goal.params['homeSector'] ?? npc.currentSectorId,
            'legs': legs,
          },
        ),
      );
    }
    return npc;
  }

  static NpcShip _executeFleeGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    // Arrived at flee destination — clear the goal.
    // Threat re-check will happen in step 3 next tick.
    if (npc.currentSectorId == goal.targetSectorId) {
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }
    return npc;
  }

  static NpcShip _executeAttackGoal(
    NpcShip npc,
    List<Sector> sectors,
    List<NpcShip> allNpcs,
    NpcGoal goal,
  ) {
    // Distress responses re-validate en route: if the signal cleared
    // (defender died and was cleared, or it expired), stand down instead
    // of flying to an empty sector like the old stampedes did.
    final distressFor = goal.params['distressFor'] as String?;
    if (distressFor != null) {
      _activeDistressSignals.removeWhere((_, s) => s.isExpired);
      if (!_activeDistressSignals.containsKey(distressFor)) {
        GameEventLog.global.combat(
            '[${npc.pilotName}] Standing down — distress call resolved');
        return npc.copyWith(clearGoal: true);
      }
    }

    if (npc.currentSectorId != goal.targetSectorId) return npc;

    // Safe zone check — no attacks allowed
    if (_isSafeZone(npc.currentSectorId)) {
      GameEventLog.global
          .combat('[${npc.pilotName}] Attack: Cannot attack in safe zone '
              'Sector ${npc.currentSectorId}');
      return npc.copyWith(clearGoal: true);
    }

    final targetId = goal.targetId;
    if (targetId == null) {
      // No specific NPC target — player-targeting goal arrived at sector.
      // Player attack is handled separately by GameTickService.
      GameEventLog.global.combat('[${npc.pilotName}] Attack: Arrived in Sector '
          '${npc.currentSectorId} (hunting player)');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }

    // Find target NPC in this sector
    NpcShip? target;
    for (final n in allNpcs) {
      if (n.id == targetId &&
          n.currentSectorId == npc.currentSectorId &&
          !n.isDestroyed) {
        target = n;
        break;
      }
    }

    if (target == null) {
      GameEventLog.global
          .combat('[${npc.pilotName}] Attack: Target $targetId not found in '
              'Sector ${npc.currentSectorId}');
      return npc.copyWith(clearGoal: true);
    }

    final myPower = CombatService.calculateFirepower(npc);
    final targetPower = CombatService.calculateFirepower(target);
    final log = ActionLogProvider.global;

    // ── Distress call: unfair fight ──
    if (myPower > targetPower * 2.0) {
      log.info(
        '${target.pilotName} (${target.shipName}) sends a distress signal '
        'from sector #${npc.currentSectorId}!',
      );
      GameEventLog.global.combat(
        '[${target.pilotName}] Distress call from Sector '
        '${npc.currentSectorId} (attacked by ${npc.pilotName})',
      );
      _activeDistressSignals[target.id] = DistressSignal(
        sectorId: npc.currentSectorId,
        targetId: target.id,
        targetName: target.pilotName,
        aggressorId: npc.id,
        aggressorName: npc.pilotName,
        createdAt: DateTime.now(),
      );
    }

    // Resolve NPC-vs-NPC combat immediately
    final result = CombatService.resolveCombat(npc, target);

    // Update defender in-place in the list
    final idx = allNpcs.indexWhere((n) => n.id == targetId);
    if (idx != -1) {
      allNpcs[idx] = result.defender;
    }

    if (result.result.defenderDestroyed) {
      // Clear distress signal if defender had one
      _activeDistressSignals.remove(target.id);
      log.combat('[${result.attacker.pilotName}] Destroyed ${target.pilotName} '
          '(${target.shipName}) in Sector ${npc.currentSectorId}');
      log.combat(
          NpcDeathCries.formatDeathCry(target.pilotName, target.faction));
      GameEventLog.global.combat(
          '[${result.attacker.pilotName}] Combat: Destroyed ${target.pilotName} '
          'in Sector ${npc.currentSectorId}');
      // Bounty payout to the killer (underworld collects instantly),
      // plus +5 standing with each posting faction (B4: kills pay credits
      // AND standing).
      final posterFactions = BountyBoard.global.posterFactionsFor(target.id);
      final paid = BountyBoard.global.payKiller(
        targetId: target.id,
        killerName: result.attacker.pilotName,
        targetName: target.pilotName,
      );
      if (paid > 0) {
        var enriched = result.attacker.copyWith(
          credits: result.attacker.credits + paid,
        );
        for (final faction in posterFactions) {
          final current = enriched.memory.factionStandings[faction] ?? 0;
          enriched = enriched.copyWith(
            memory: enriched.memory.withFactionStanding(
              faction,
              (current + 5).clamp(-100, 100),
            ),
          );
        }
        return enriched.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
        );
      }
    } else {
      log.combat('[${result.attacker.pilotName}] Engaged ${target.pilotName} '
          '(dealt ${result.result.damageToDefender}, '
          'took ${result.result.damageToAttacker})');
      GameEventLog.global.combat(
          '[${result.attacker.pilotName}] Combat: Engaged ${target.pilotName} '
          '(dealt ${result.result.damageToDefender}, '
          'took ${result.result.damageToAttacker})');
      // Survivor posts a bounty on the aggressor from its own bankroll
      // (flat 5000 when affordable) — hits fund the board that pays hits.
      // Debit first: post() is infallible for validated amounts, so the
      // bounty can never exist unpaid-for.
      final survivor = allNpcs[idx];
      if (survivor.credits >= 10000) {
        allNpcs[idx] = survivor.copyWith(
          credits: survivor.credits - 5000,
        );
        BountyBoard.global.post(
          targetId: npc.id,
          targetName: npc.pilotName,
          targetFaction: npc.faction.name,
          amount: 5000,
          posterId: survivor.id,
          posterName: survivor.pilotName,
          posterFaction: survivor.faction.name,
          reason: 'unprovoked attack',
        );
      }
    }

    return result.attacker.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcShip _executeRaidPortGoal(
    NpcShip npc,
    List<Sector> sectors,
    List<NpcShip> allNpcs,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final sector = _findSector(sectors, goal.targetSectorId!);
    final port = sector?.port;
    if (port == null) return npc.copyWith(clearGoal: true);

    // Safe zone check
    if (_isSafeZone(sector!.id)) {
      GameEventLog.global
          .combat('[${npc.pilotName}] Raid: Cannot attack port in safe zone '
              'Sector ${sector.id}');
      return npc.copyWith(clearGoal: true);
    }

    // NPC owner defense response (matched by stable id, not name).
    var ownerDefenseDamage = 0;
    if (port.isOwned) {
      NpcShip? owner;
      for (final n in allNpcs) {
        if (port.isOwnedById(n.id, n.pilotName) &&
            n.currentSectorId == npc.currentSectorId &&
            !n.isDestroyed) {
          owner = n;
          break;
        }
      }
      if (owner != null) {
        final effectiveOwner = owner;
        if (effectiveOwner.personalityConfig.aggression > 0.5) {
          ownerDefenseDamage =
              (CombatService.calculateFirepower(effectiveOwner) * 0.5).round();
          GameEventLog.global.combat(
              '[${npc.pilotName}] Raid: Port owner ${effectiveOwner.pilotName} '
              'joins defense!');
        } else {
          final adjSectorId = _findAdjacentSector(sectors, npc.currentSectorId);
          if (adjSectorId != null) {
            final idx = allNpcs.indexWhere((n) => n.id == effectiveOwner.id);
            if (idx != -1) {
              allNpcs[idx] =
                  effectiveOwner.copyWith(currentSectorId: adjSectorId);
            }
            GameEventLog.global.combat(
                '[${npc.pilotName}] Raid: Port owner ${effectiveOwner.pilotName} '
                'flees to Sector $adjSectorId');
          }
        }
      }
    }

    // Decide attack mode based on NPC personality
    final mode = npc.personalityConfig.aggression > 0.7 ? 'destroy' : 'capture';

    // Initialize port shields if first time attacking
    if (port.currentShields <= 0 && !port.isUnderAttack) {
      sector.port = port.copyWith(
        currentShields: port.maxShields,
        isUnderAttack: true,
        attackerId: npc.id,
        attackMode: mode,
      );
    }

    // Resolve one round of combat
    var result =
        PortCombatService.resolveNpcPortAttack(npc, sector.port!, mode);

    // Apply owner defense damage to attacker
    if (ownerDefenseDamage > 0 && !result.portSurrendered) {
      var npcShields = result.updatedNpc!.shields;
      var npcHull = result.updatedNpc!.hull;
      if (npcShields >= ownerDefenseDamage) {
        npcShields -= ownerDefenseDamage;
      } else {
        ownerDefenseDamage -= npcShields;
        npcShields = 0;
        npcHull = (npcHull - ownerDefenseDamage).clamp(0, npc.maxHull);
      }
      // Re-check defeat after owner damage
      if (npcHull <= 0) {
        result = PortCombatResult(
          portSurrendered: false,
          portDestroyed: false,
          attackerDefeated: true,
          damageToPort: result.damageToPort,
          damageToAttacker: result.damageToAttacker + ownerDefenseDamage,
          updatedPort: result.updatedPort,
          updatedNpc: result.updatedNpc!.copyWith(
            shields: npcShields,
            hull: npcHull,
          ),
          outcome: 'attackerDefeated',
        );
      } else {
        result = PortCombatResult(
          portSurrendered: result.portSurrendered,
          portDestroyed: result.portDestroyed,
          attackerDefeated: result.attackerDefeated,
          damageToPort: result.damageToPort,
          damageToAttacker: result.damageToAttacker + ownerDefenseDamage,
          updatedPort: result.updatedPort,
          updatedNpc: result.updatedNpc!.copyWith(
            shields: npcShields,
            hull: npcHull,
          ),
          outcome: result.outcome,
        );
      }
    }

    // Update sector port
    sector.port = result.updatedPort;

    // Update NPC state
    var updatedNpc = result.updatedNpc!;

    if (result.portSurrendered) {
      if (mode == 'capture') {
        sector.port = PortCombatService.capturePort(
          sector.port!,
          npc.pilotName,
          npc.faction.name,
          ownerId: npc.id,
        );
        updatedNpc = updatedNpc.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
          notoriety: (updatedNpc.notoriety + 10).clamp(0, 100),
        );
        GameEventLog.global
            .combat('[${npc.pilotName}] Raid: Captured ${port.name}');
        ActionLogProvider.global.warning(
          '${npc.pilotName} captured ${port.name} in Sector ${sector.id}',
        );
      } else {
        sector.port = PortCombatService.destroyPort(sector.port!);
        sector.hasPort = false;
        updatedNpc = updatedNpc.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
          notoriety: (updatedNpc.notoriety + 20).clamp(0, 100),
        );
        GameEventLog.global
            .combat('[${npc.pilotName}] Raid: Destroyed ${port.name}');
        ActionLogProvider.global.error(
          '${npc.pilotName} destroyed ${port.name} in Sector ${sector.id}',
        );
      }
    } else if (result.attackerDefeated) {
      sector.port = PortCombatService.endCombatRetreat(sector.port!);
      updatedNpc = updatedNpc.copyWith(clearGoal: true);
      GameEventLog.global
          .combat('[${npc.pilotName}] Raid: Defeated by ${port.name} defenses');
      ActionLogProvider.global.info(
        '${npc.pilotName} was repelled from ${port.name} in Sector ${sector.id}',
      );
    } else {
      updatedNpc = updatedNpc.copyWith(
        notoriety: (updatedNpc.notoriety + 5).clamp(0, 100),
      );
    }

    return updatedNpc;
  }

  static NpcShip _executeUpgradeGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final sector = _findSector(sectors, npc.currentSectorId);
    final upgradeStanding = FactionStanding.resolveFor(
      npc.faction,
      sector?.port?.ownerFaction,
      npc.memory.factionStandings,
    );
    if (sector?.port == null ||
        (sector!.port!.isHardwareEmporium &&
            sector.port!.deniesServiceTo(upgradeStanding))) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Upgrade: refused (standing $upgradeStanding)',
      );
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.failed),
      );
    }

    var updated = npc;
    // 1 — Repairs first: hull and shields back to full when affordable.
    updated = _repairShip(updated);

    // 2 — Solar Array for qualifying personalities (existing behavior).
    if (updated.solarArrayLevel <= 0 &&
        updated.credits >= npcSolarArrayCostCredits &&
        (updated.personalityConfig.caution > 0.5 ||
            updated.personalityConfig.explorationDrive > 0.6)) {
      GameEventLog.global
          .energy('NPC_ENERGY event=array_buy pilot=${updated.pilotName} '
              'spent=$npcSolarArrayCostCredits');
      ActionLogProvider.global.trade(
        '${updated.pilotName} installed a Solar Array',
      );
      return updated.copyWith(
        credits: updated.credits - npcSolarArrayCostCredits,
        solarArrayLevel: 1,
        solarArrayDeployed: false,
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }

    // 3 — One equipment upgrade per visit, defense-first for peaceful
    // factions (aggression ≤ 0.5): shields → hull → engine → weapons.
    // Aggressive factions lead with weapons. Levels feed the combat
    // formulas automatically (firepower +5/hull level, durability +10;
    // engine level cuts warp cost); shield levels also raise maxShields
    // since nothing else reads that stat for NPCs.
    final defensive = updated.personalityConfig.aggression <= 0.5;
    final order = defensive
        ? const ['shields', 'hull', 'engine', 'weapons']
        : const ['weapons', 'hull', 'shields', 'engine'];
    for (final slot in order) {
      final bought = _buyUpgrade(updated, slot);
      if (bought != null) {
        updated = bought;
        break;
      }
    }
    if (identical(updated, npc)) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Upgrade: nothing affordable '
        '(credits=${npc.credits})',
      );
    }
    return updated.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  /// Hull/shield repairs at 2cr / 1cr per point. Never strands the ship:
  /// keeps at least a full-tank refuel in reserve.
  static NpcShip _repairShip(NpcShip npc) {
    final reserve = EnergyService.npcRefuelCost(
        npc.copyWith(energy: 0, maxEnergy: npc.maxEnergy));
    var hull = npc.hull;
    var shields = npc.shields;
    var spent = 0;

    final hullMissing = npc.maxHull - hull;
    final hullAffordable =
        (npc.credits - reserve - spent).clamp(0, hullMissing * 2) ~/ 2;
    hull += hullAffordable;
    spent += hullAffordable * 2;

    final shieldsMissing = npc.maxShields - shields;
    final shieldsAffordable =
        (npc.credits - reserve - spent).clamp(0, shieldsMissing);
    shields += shieldsAffordable;
    spent += shieldsAffordable;

    if (spent > 0) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Upgrade: repaired hull+$hullAffordable '
        'shields+$shieldsAffordable for ${spent}cr',
      );
      return npc.copyWith(
        hull: hull,
        shields: shields,
        credits: npc.credits - spent,
      );
    }
    return npc;
  }

  static const int _maxEquipmentLevel = 5;
  static const int _maxWeaponLevel = 3;

  /// Single equipment purchase for [slot], or null when capped or
  /// unaffordable (keeps 5k operating cash after the price).
  static NpcShip? _buyUpgrade(NpcShip npc, String slot) {
    int level;
    int price;
    switch (slot) {
      case 'hull':
        level = npc.hullEquipmentLevel;
        if (level >= _maxEquipmentLevel) return null;
        price = 15000 * level;
        break;
      case 'shields':
        level = npc.shieldEquipmentLevel;
        if (level >= _maxEquipmentLevel) return null;
        price = 15000 * level;
        break;
      case 'engine':
        level = npc.engineEquipmentLevel;
        if (level >= _maxEquipmentLevel) return null;
        price = 20000 * level;
        break;
      case 'weapons':
        if (npc.weaponSlots.isEmpty) return null;
        final weakest = npc.weaponSlots.entries
            .reduce((a, b) => a.value <= b.value ? a : b);
        if (weakest.value >= _maxWeaponLevel) return null;
        price = 15000 * weakest.value;
        if (npc.credits - price < 5000) return null;
        GameEventLog.global.goal(
          '[${npc.pilotName}] Upgrade: ${weakest.key} → level '
          '${weakest.value + 1} for ${price}cr',
        );
        final slots = Map<String, int>.from(npc.weaponSlots);
        slots[weakest.key] = weakest.value + 1;
        return npc.copyWith(
          credits: npc.credits - price,
          weaponSlots: slots,
        );
      default:
        return null;
    }
    if (npc.credits - price < 5000) return null;
    GameEventLog.global.goal(
      '[${npc.pilotName}] Upgrade: $slot → level ${level + 1} '
      'for ${price}cr',
    );
    final extraShields = slot == 'shields' ? 20 : 0;
    return npc.copyWith(
      credits: npc.credits - price,
      hullEquipmentLevel: slot == 'hull' ? level + 1 : npc.hullEquipmentLevel,
      shieldEquipmentLevel:
          slot == 'shields' ? level + 1 : npc.shieldEquipmentLevel,
      engineEquipmentLevel:
          slot == 'engine' ? level + 1 : npc.engineEquipmentLevel,
      maxShields: npc.maxShields + extraShields,
      shields: npc.shields + extraShields,
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Step 3 — Threat evaluation
  // ────────────────────────────────────────────────────────────────

  static bool _evaluateThreat(
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

  static double _notorietyOf(dynamic entity) {
    if (entity is NpcShip) return entity.notoriety;
    if (entity is Player) return entity.notoriety;
    return 0;
  }

  static List<dynamic> _findLocalEnemies(
    NpcShip npc,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    final enemies = <dynamic>[];

    for (final player in players) {
      if (player.currentSectorId == npc.currentSectorId &&
          _isHostileFaction(npc.faction, player.faction)) {
        enemies.add(player);
      }
    }
    for (final other in allNpcs) {
      if (other.id != npc.id &&
          other.currentSectorId == npc.currentSectorId &&
          !other.isDestroyed &&
          _isHostileFaction(npc.faction, other.faction)) {
        enemies.add(other);
      }
    }

    return enemies;
  }

  static int _calculatePower(dynamic entity) {
    if (entity is NpcShip) {
      return CombatService.calculateFirepower(entity);
    }
    if (entity is Player) {
      return CombatService.calculatePlayerFirepower(entity);
    }
    return 0;
  }

  static NpcShip _setFleeGoal(NpcShip npc, List<Sector> sectors) {
    final current = _findSector(sectors, npc.currentSectorId);
    if (current == null || current.warpRoutes.isEmpty) return npc;

    final targetId =
        current.warpRoutes[_rng.nextInt(current.warpRoutes.length)];

    GameEventLog.global
        .goal('[${npc.pilotName}] Flee: Evading threat in Sector '
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
  // Step 5 — Goal selection
  // ────────────────────────────────────────────────────────────────

  static bool _needsNewGoal(NpcShip npc) {
    final goal = npc.currentGoal;
    return goal == null ||
        goal.status == NpcGoalStatus.complete ||
        goal.status == NpcGoalStatus.failed;
  }

  static NpcGoal? _selectGoal(
    NpcShip npc,
    List<Sector> sectors,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    final config = npc.personalityConfig;

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
      var roll = _rng.nextDouble() * total;
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

  static bool _isGoalViable(
    NpcGoalType type,
    NpcShip npc,
    List<Sector> sectors,
  ) {
    switch (type) {
      case NpcGoalType.tradeRoute:
        // Full holds are fine when the NPC carries sellable cargo — it
        // becomes a sell-first route (see _createTradeRouteGoal). Without
        // this, full holds deadlocked all future trading: no new route
        // could start, and nothing else empties cargo.
        // Credits gate only the buy leg: a broke NPC sitting on sellable
        // cargo needs to trade most of all.
        final hasSpace = npc.cargoUsed < npc.cargoHoldCapacity;
        final hasCargo = npc.cargo.values.any((q) => q > 0);
        return npc.memory.discoveredPorts.length >= 2 &&
            (hasSpace ? npc.credits > 100 : hasCargo);
      case NpcGoalType.explore:
        return _hasUnvisitedSectors(npc, sectors);
      case NpcGoalType.bankDeposit:
        return BankingAi.shouldDeposit(npc);
      case NpcGoalType.bankWithdraw:
        return BankingAi.shouldWithdraw(npc);
      case NpcGoalType.attack:
        return npc.personalityConfig.aggression > 0.5 &&
            npc.totalWeaponPower > 0;
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
        return _hasEnergy(npc) || npc.credits + npc.bankBalance > 0;
    }
  }

  static bool _hasUnvisitedSectors(NpcShip npc, List<Sector> sectors) {
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
      final sector = _findSector(sectors, c);
      if (sector != null) {
        for (final w in sector.warpRoutes) {
          if (visited.add(w)) queue.add(w);
        }
      }
    }
    return false;
  }

  static bool _hasPortSectorReachable(NpcShip npc, List<Sector> sectors) {
    return PathfindingService.findNearestWhere(
          sectors,
          npc.currentSectorId,
          (s) => s.hasPort,
        ) !=
        null;
  }

  static NpcGoal? _instantiateGoal(
    NpcGoalType type,
    NpcShip npc,
    List<Sector> sectors,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    switch (type) {
      case NpcGoalType.tradeRoute:
        return _createTradeRouteGoal(npc, sectors);
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
        return createRefuelGoal(npc, sectors);
      case NpcGoalType.buyPort:
        return _createBuyPortGoal(npc, sectors);
    }
  }

  static NpcGoal? _createTradeRouteGoal(
    NpcShip npc,
    List<Sector> sectors,
  ) {
    // Sell-first whenever there is no economical buy leg: full holds, or
    // mere nibs (< 25% of capacity) not worth topping up with a fresh buy.
    // Aborted routes leave partial cargo that would otherwise ride along
    // unsold forever while new commodities pile on top.
    final hasSpace = npc.cargoUsed < npc.cargoHoldCapacity;
    final hasCargo = npc.cargo.values.any((q) => q > 0);
    final nibs = hasCargo && npc.cargoUsed < npc.cargoHoldCapacity * 0.25;
    if ((!hasSpace || nibs) && hasCargo) {
      return _createSellOnlyGoal(npc, sectors);
    }
    final route = TradeEvaluator.findBestTradeRoute(
      npc.currentSectorId,
      npc.memory.discoveredPorts,
      sectors,
      npc.personalityConfig.maxTravelDistance,
      avoidRoutes: npc.memory.coolingRoutes(),
      credits: npc.credits.toDouble(),
      actorFaction: npc.faction,
      standings: npc.memory.factionStandings,
    );
    if (route == null) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Goal: trade wanted but no route from '
        '${npc.memory.discoveredPorts.length} known ports',
      );
      return null;
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
        'sellPrice': route.sellPrice,
        'phase': 'travel_to_buy',
      },
    );
  }

  /// Sell-first route for full holds: best known buyer for carried cargo.
  /// Returns null (with a log line) when nothing on board has a reachable
  /// buyer — the NPC keeps exploring instead of idling on dead inventory.
  static NpcGoal? _createSellOnlyGoal(NpcShip npc, List<Sector> sectors) {
    final maxTravel = npc.personalityConfig.maxTravelDistance;
    String? bestCommodity;
    int? bestPortId;
    var bestPrice = 0.0;

    npc.cargo.forEach((commodity, qty) {
      if (qty <= 0) return;
      for (final entry in npc.memory.discoveredPorts.entries) {
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
        if (price > bestPrice) {
          bestPrice = price;
          bestCommodity = commodity;
          bestPortId = entry.key;
        }
      }
    });

    if (bestCommodity == null || bestPortId == null) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] Goal: holds full but no buyer known for '
        'on-board cargo',
      );
      return null;
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

  /// Asking price for an NPC port purchase. Set at 10% of net worth
  /// (floor 25k): half-net-worth priced every NPC out forever (ports hold
  /// millions in credits alone), so economic conquest never fired and only
  /// raiders ever took ports. Unowned non-federal ports only — federal,
  /// emporium, player, and NPC-owned ports are never for sale to NPCs.
  static int npcPortPrice(Port port) =>
      math.max(25000, (port.netWorth * 0.1).round());

  static bool _isPurchasable(Port? port) {
    if (port == null) return false;
    if (port.isHardwareEmporium) return false;
    if (port.portClass == PortClass.federal) return false;
    if (port.owner != null && port.owner!.isNotEmpty) return false;
    return true;
  }

  static NpcGoal? _createBuyPortGoal(NpcShip npc, List<Sector> sectors) {
    final portSectorId = PathfindingService.findNearestWhere(
      sectors,
      npc.currentSectorId,
      (s) => s.hasPort && _isPurchasable(s.port) && !_isSafeZone(s.id),
    );
    if (portSectorId == null) return null;

    return NpcGoal(
      type: NpcGoalType.buyPort,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': portSectorId},
    );
  }

  static NpcShip _executeBuyPortGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final sector = _findSector(sectors, npc.currentSectorId);
    final port = sector?.port;
    if (!_isPurchasable(port)) {
      // Sold, federalized, or gone while en route — move on.
      return npc.copyWith(clearGoal: true);
    }
    final price = npcPortPrice(port!);
    if (npc.credits < price) {
      GameEventLog.global.goal(
        '[${npc.pilotName}] BuyPort: ${port.name} costs $price cr '
        '(have ${npc.credits}) — saving up',
      );
      return npc.copyWith(clearGoal: true);
    }
    sector!.port = port.copyWith(
      owner: npc.pilotName,
      ownerId: npc.id,
      ownerFaction: npc.faction,
    );
    GameEventLog.global.goal(
      '[${npc.pilotName}] BuyPort: bought ${port.name} for $price cr',
    );
    ActionLogProvider.global.warning(
      '${npc.pilotName} bought ${port.name} in Sector ${sector.id}',
    );
    return npc.copyWith(
      credits: npc.credits - price,
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcGoal _createExploreGoal(NpcShip npc, List<Sector> sectors) {
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

  static NpcGoal _createPatrolGoal(NpcShip npc, List<Sector> sectors) {
    final current = _findSector(sectors, npc.currentSectorId);
    final targetId = (current != null && current.warpRoutes.isNotEmpty)
        ? current.warpRoutes[_rng.nextInt(current.warpRoutes.length)]
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
  static NpcGoal? _respondToDistress(
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
        final defender = _findNpcById(allNpcs, signal.targetId);
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

    // Cap the stampede: ships already converging on this aggressor count
    // against the wing limit (visible immediately — the tick loop writes
    // each processed NPC back before the next one runs).
    var committed = 0;
    for (final n in allNpcs) {
      if (n.id != npc.id &&
          !n.isDestroyed &&
          n.currentGoal?.type == NpcGoalType.attack &&
          n.currentGoal?.targetId == bestSignal.aggressorId) {
        committed++;
      }
    }
    if (committed >= maxDistressResponders) return null;

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

  static NpcGoal? _createAttackGoal(
    NpcShip npc,
    List<Sector> sectors,
    List<Player> players,
    List<NpcShip> allNpcs,
  ) {
    // Don't create attack goals from safe zones or against safe zones
    if (_isSafeZone(npc.currentSectorId)) return null;

    final myPower = CombatService.calculateFirepower(npc);
    final maxDist = npc.personalityConfig.maxTravelDistance;
    // Greedy hunters (greed ≥ 0.7) prefer marked targets: highest active
    // bounty first, weakest as tie-break. Everyone else takes the weakest.
    final greedy = npc.personalityConfig.greed >= 0.7;
    bool prefers(NpcShip candidate, int candidatePower, NpcShip? current) {
      if (current == null) return true;
      if (greedy) {
        final bounty = BountyBoard.global.totalFor(candidate.id);
        final best = BountyBoard.global.totalFor(current.id);
        if (bounty != best) return bounty > best;
      }
      return candidatePower < CombatService.calculateFirepower(current);
    }

    // 1 — Check same sector for hostile NPCs
    NpcShip? bestTarget;
    int? bestTargetSectorId;
    for (final other in allNpcs) {
      if (other.id == npc.id || other.isDestroyed) continue;
      if (other.currentSectorId != npc.currentSectorId) continue;
      if (!_isHostileFaction(npc.faction, other.faction)) continue;
      final otherPower = CombatService.calculateFirepower(other);
      if (otherPower >= myPower) continue; // only attack weaker targets
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
        final sector = _findSector(sectors, current.sector);
        if (sector == null) continue;
        for (final warp in sector.warpRoutes) {
          if (!visited.add(warp)) continue;
          if (_isSafeZone(warp)) continue; // skip safe zones
          // Check for hostile NPCs in this sector
          for (final other in allNpcs) {
            if (other.id == npc.id || other.isDestroyed) continue;
            if (other.currentSectorId != warp) continue;
            if (!_isHostileFaction(npc.faction, other.faction)) continue;
            final otherPower = CombatService.calculateFirepower(other);
            if (otherPower >= myPower) continue;
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
        if (_isSafeZone(player.currentSectorId)) continue;
        if (!_isHostileFaction(npc.faction, player.faction) &&
            player.factionStandingWith(npc.faction) > -50) {
          continue;
        }
        if (!shouldAttackPlayer(npc, player)) continue;
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

  static NpcGoal? _createRaidPortGoal(NpcShip npc, List<Sector> sectors) {
    // Nearest WEAK port the NPC can actually beat — blindly sieging
    // strong defenses is how pirates went 0-for-history while Duran
    // (bigger guns) captured everything.
    final portSectorId = PathfindingService.findNearestWhere(
      sectors,
      npc.currentSectorId,
      (s) =>
          s.hasPort &&
          (s.port?.defenseLevel ?? 4) < 2 &&
          !_isSafeZone(s.id) &&
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

  static NpcGoal? _createUpgradeGoal(NpcShip npc, List<Sector> sectors) {
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

  // ────────────────────────────────────────────────────────────────
  // Step 6 — Movement
  // ────────────────────────────────────────────────────────────────

  static NpcShip _move(NpcShip npc, List<Sector> sectors) {
    if (!_hasEnergy(npc)) return npc;

    // Deployed Solar Array locks the ship (mirrors Player.canMove).
    if (!npc.canMove) return npc;

    final cost = EnergyService.npcWarpCost(npc);
    if (!npc.hasEnergy(cost)) return _handleStranded(npc);

    // Only travelling goals steer movement. Following a complete/failed
    // goal ping-pongs the NPC at a dead target forever (refused refuel
    // looped two sectors until this guard).
    final goal = npc.currentGoal;
    final steering =
        goal != null && goal.status == NpcGoalStatus.travelling ? goal : null;

    // If we have a goal with a target, pathfind towards it
    if (steering != null &&
        steering.targetSectorId != null &&
        steering.targetSectorId != npc.currentSectorId) {
      final path = PathfindingService.findPath(
        sectors,
        npc.currentSectorId,
        steering.targetSectorId!,
      );
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
    final current = _findSector(sectors, npc.currentSectorId);
    if (current == null || current.warpRoutes.isEmpty) return npc;

    final next = current.warpRoutes[_rng.nextInt(current.warpRoutes.length)];
    GameEventLog.global.movement(
        '[${npc.pilotName}] Wander: Sector ${npc.currentSectorId} → Sector $next');
    return npc.spendEnergy(cost).copyWith(
          currentSectorId: next,
        );
  }

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
