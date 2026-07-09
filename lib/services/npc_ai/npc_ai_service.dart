import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/npc_ship.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/sector.dart';
import 'package:tradewars_2050/services/npc_ai/banking_ai.dart';
import 'package:tradewars_2050/services/npc_ai/combat_service.dart';
import 'package:tradewars_2050/services/npc_ai/npc_death_cries.dart';
import 'package:tradewars_2050/services/npc_ai/npc_goal.dart';
import 'package:tradewars_2050/services/npc_ai/npc_memory.dart';
import 'package:tradewars_2050/services/npc_ai/pathfinding_service.dart';
import 'package:tradewars_2050/services/npc_ai/port_combat_service.dart';
import 'package:tradewars_2050/services/npc_ai/trade_evaluator.dart';
import 'package:tradewars_2050/widgets/sector_view_widgets/action_log_provider.dart';

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

  /// Sectors 1-10 are safe zones (no attacks allowed).
  static bool _isSafeZone(int sectorId) => sectorId <= 10;

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
    if (npc.turns <= 0 || npc.isDestroyed) return npc;

    var updated = npc;

    // 1 — Scan the current sector
    updated = _scanSector(updated, sectors, players, allNpcs);

    // 2 — Execute the current goal (trade, bank, explore, etc.)
    updated = _executeGoal(updated, sectors, allNpcs);

    if (updated.isDestroyed) {
      debugPrint(
          '[${updated.pilotName}] Destroyed in Sector ${updated.currentSectorId}');
      return updated;
    }

    // 3 — Evaluate threats → flee immediately if outmatched
    if (updated.turns > 0 &&
        _evaluateThreat(updated, sectors, players, allNpcs)) {
      updated = _setFleeGoal(updated, sectors);
    }

    // 3b — Respond to nearby distress signals (override current goal)
    if (updated.turns > 0 &&
        updated.currentGoal?.type != NpcGoalType.flee) {
      final distressGoal = _respondToDistress(updated, sectors, allNpcs);
      if (distressGoal != null) {
        updated = updated.copyWith(currentGoal: distressGoal);
      }
    }

    // 4 — Evaluate banking needs
    if (updated.turns > 0 &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        BankingAi.shouldDeposit(updated)) {
      final goal = BankingAi.createDepositGoal(updated, sectors);
      if (goal != null) {
        debugPrint('[${updated.pilotName}] Banking: Heading to deposit '
            '${goal.params['depositAmount']} cr');
        updated = updated.copyWith(currentGoal: goal);
      }
    }
    if (updated.turns > 0 &&
        updated.currentGoal?.type != NpcGoalType.flee &&
        BankingAi.shouldWithdraw(updated)) {
      final goal = BankingAi.createWithdrawGoal(updated, sectors);
      if (goal != null) {
        debugPrint('[${updated.pilotName}] Banking: Heading to withdraw cr');
        updated = updated.copyWith(currentGoal: goal);
      }
    }

    // 5 — Select a new goal if none is active
    if (updated.turns > 0 && _needsNewGoal(updated)) {
      final goal = _selectGoal(updated, sectors, players, allNpcs);
      if (goal != null) {
        updated = updated.copyWith(currentGoal: goal);
        final targetStr = goal.targetSectorId != null
            ? '→ Sector ${goal.targetSectorId}'
            : '';
        debugPrint('[${updated.pilotName}] Goal: ${goal.type.name} $targetStr');
      }
    }

    // 6 — Move one hop towards the goal
    if (updated.turns > 0) {
      updated = _move(updated, sectors);
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
    }
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
      return npc.copyWith(currentGoal: null);
    }

    final phase = goal.params['phase'] as String? ?? 'travel_to_buy';
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    // ── Phase: arrived at buy port ──
    if (phase == 'travel_to_buy' && npc.currentSectorId == buyPortId) {
      final sector = _findSector(sectors, buyPortId);
      if (sector == null) return npc.copyWith(currentGoal: null);
      var port = sector.port;
      if (port == null) return npc.copyWith(currentGoal: null);

      // Regen before reading
      port = port.regen(now: nowMs);
      sector.port = port;

      final sellPrice = port.getEffectiveSellPrice(commodity);
      if (sellPrice <= 0) return npc.copyWith(currentGoal: null);

      final availableHolds = npc.cargoHoldCapacity - npc.cargoUsed;
      if (availableHolds <= 0) return npc.copyWith(currentGoal: null);

      final availableSupply = port.getSupply(commodity);
      if (availableSupply <= 0) return npc.copyWith(currentGoal: null);

      final maxBuyable = (npc.credits / sellPrice)
          .floor()
          .clamp(1, availableHolds.clamp(0, availableSupply));
      if (maxBuyable <= 0) {
        debugPrint(
            '[${npc.pilotName}] Trade: Not enough credits for $commodity at ${port.name}');
        return npc.copyWith(currentGoal: null);
      }

      final newCargo = Map<String, int>.from(npc.cargo);
      newCargo[commodity] = (newCargo[commodity] ?? 0) + maxBuyable;
      final cost = (maxBuyable * sellPrice).round();

      // Mutate port: decrement supply, add credits (port earns from selling)
      final newSupply = Map<String, int>.from(port.supply);
      newSupply[commodity] = availableSupply - maxBuyable;
      final ownerSurcharge = port.isOwned
          ? (cost * port.ownerTaxRate).round()
          : 0;
      sector.port = port.copyWith(
        supply: newSupply,
        portCredits: port.portCredits + cost,
        accumulatedRevenue: port.accumulatedRevenue + ownerSurcharge,
        lastRegenTime: nowMs,
      );

      debugPrint(
          '[${npc.pilotName}] Trade: Bought $maxBuyable $commodity at '
          '${port.name} (${sellPrice.toStringAsFixed(0)} cr)'
          '${ownerSurcharge > 0 ? ' [+${ownerSurcharge}cr owner fee]' : ''}');

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
      if (sector == null) return npc.copyWith(currentGoal: null);
      var port = sector.port;
      if (port == null) return npc.copyWith(currentGoal: null);

      // Regen before reading
      port = port.regen(now: nowMs);
      sector.port = port;

      final buyPrice = port.getEffectiveBuyPrice(commodity);
      if (buyPrice <= 0) return npc.copyWith(currentGoal: null);

      var quantity = npc.cargo[commodity] ?? 0;
      if (quantity <= 0) return npc.copyWith(currentGoal: null);

      // Cap by available demand
      final availableDemand = port.getDemand(commodity);
      if (availableDemand <= 0) return npc.copyWith(currentGoal: null);
      quantity = quantity.clamp(1, availableDemand);

      // Cap by port credits
      final grossRevenue = (quantity * buyPrice).round();
      final actualRevenue = grossRevenue.clamp(0, port.portCredits.floor());
      if (actualRevenue <= 0) {
        debugPrint('[${npc.pilotName}] Trade: Port ${port.name} has '
            'insufficient credits to buy $quantity $commodity');
        return npc.copyWith(currentGoal: null);
      }

      // Recompute quantity if port is short on credits
      final actualQuantity =
          (actualRevenue / buyPrice).floor().clamp(1, quantity);

      final cost = goal.buyPrice != null
          ? (actualQuantity * goal.buyPrice!).round()
          : 0;
      final profit = actualRevenue - cost;
      final newCargo = Map<String, int>.from(npc.cargo);
      newCargo[commodity] = newCargo[commodity]! - actualQuantity;
      if (newCargo[commodity]! <= 0) newCargo.remove(commodity);

      // Mutate port: decrement demand, deduct credits, owner collects transaction fee
      final newDemand = Map<String, int>.from(port.demand);
      newDemand[commodity] = availableDemand - actualQuantity;
      final ownerTax = port.isOwned
          ? (actualRevenue * port.ownerTaxRate).round()
          : 0;
      final npcReceives = actualRevenue - ownerTax;
      sector.port = port.copyWith(
        demand: newDemand,
        portCredits: port.portCredits - actualRevenue,
        accumulatedRevenue: port.accumulatedRevenue + ownerTax,
        lastRegenTime: nowMs,
      );

      debugPrint(
          '[${npc.pilotName}] Trade: Sold $actualQuantity $commodity at '
          '${port.name} (${buyPrice.toStringAsFixed(0)} cr) '
          '— ${profit >= 0 ? "profit" : "loss"} ${profit.abs()} cr'
          '${ownerTax > 0 ? ' [-${ownerTax}cr owner fee]' : ''}');

      return npc.copyWith(
        credits: npc.credits + npcReceives,
        cargo: newCargo,
        cargoUsed: npc.cargoUsed - actualQuantity,
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
  ///   1. Be from a hostile faction
  ///   2. Have sufficient aggression (pirates: ≥0.3, others: ≥0.7)
  ///   3. Have enough hull (≥30%)
  ///   4. Have a firepower advantage scaled by its caution
  ///
  ///   power threshold = 1.2 + caution × 0.8  →  range 1.2× (reckless)
  ///   to 2.0× (cautious). A cautious NPC needs to be twice as strong
  ///   before it picks a fight.
  static bool shouldAttackPlayer(NpcShip npc, Player player) {
    if (npc.isDestroyed) return false;
    if (npc.hull < npc.maxHull * 0.3) return false;
    if (!_isHostileFaction(npc.faction, player.faction)) return false;

    final aggression = npc.personalityConfig.aggression;
    final caution = npc.personalityConfig.caution;

    // Pirates are naturally aggressive; other factions need higher aggression
    final minAggression =
        npc.faction == FactionClass.pirate ? 0.3 : 0.7;
    if (aggression < minAggression) return false;

    final npcPower = CombatService.calculateFirepower(npc);
    final playerPower = CombatService.calculatePlayerFirepower(player);
    if (playerPower <= 0) return true;

    // Higher caution = needs bigger power advantage
    final powerThreshold = 1.2 + caution * 0.8;
    return npcPower > playerPower * powerThreshold;
  }

  static NpcShip _executeBankDepositGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final result = BankingAi.executeDeposit(npc, goal);
    if (!result.executed) {
      return npc.copyWith(currentGoal: null);
    }

    final deposited = (npc.credits - result.npc.credits).abs();
    debugPrint('[${result.npc.pilotName}] Banking: Deposited $deposited cr '
        '(bank: ${result.npc.bankBalance} cr)');

    return result.npc.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcShip _executeBankWithdrawGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    final result = BankingAi.executeWithdraw(npc, goal);
    if (!result.executed) {
      return npc.copyWith(currentGoal: null);
    }

    final withdrawn = (result.npc.credits - npc.credits).abs();
    debugPrint('[${result.npc.pilotName}] Banking: Withdrew $withdrawn cr');

    return result.npc.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }

  static NpcShip _executeExploreGoal(
    NpcShip npc,
    List<Sector> sectors,
    NpcGoal goal,
  ) {
    if (npc.currentSectorId == goal.targetSectorId) {
      debugPrint(
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
    if (npc.currentSectorId != goal.targetSectorId) return npc;

    // Safe zone check — no attacks allowed
    if (_isSafeZone(npc.currentSectorId)) {
      debugPrint('[${npc.pilotName}] Attack: Cannot attack in safe zone '
          'Sector ${npc.currentSectorId}');
      return npc.copyWith(currentGoal: null);
    }

    final targetId = goal.targetId;
    if (targetId == null) {
      // No specific NPC target — player-targeting goal arrived at sector.
      // Player attack is handled separately by GameTickService.
      debugPrint('[${npc.pilotName}] Attack: Arrived in Sector '
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
      debugPrint('[${npc.pilotName}] Attack: Target $targetId not found in '
          'Sector ${npc.currentSectorId}');
      return npc.copyWith(currentGoal: null);
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
      log.combat(
          '[${result.attacker.pilotName}] Destroyed ${target.pilotName} '
          '(${target.shipName}) in Sector ${npc.currentSectorId}');
      log.combat(NpcDeathCries.formatDeathCry(target.pilotName, target.faction));
      debugPrint(
          '[${result.attacker.pilotName}] Combat: Destroyed ${target.pilotName} '
          'in Sector ${npc.currentSectorId}');
    } else {
      log.combat(
          '[${result.attacker.pilotName}] Engaged ${target.pilotName} '
          '(dealt ${result.result.damageToDefender}, '
          'took ${result.result.damageToAttacker})');
      debugPrint(
          '[${result.attacker.pilotName}] Combat: Engaged ${target.pilotName} '
          '(dealt ${result.result.damageToDefender}, '
          'took ${result.result.damageToAttacker})');
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
    if (port == null) return npc.copyWith(currentGoal: null);

    // Safe zone check
    if (_isSafeZone(sector!.id)) {
      debugPrint('[${npc.pilotName}] Raid: Cannot attack port in safe zone '
          'Sector ${sector.id}');
      return npc.copyWith(currentGoal: null);
    }

    // NPC owner defense response
    var ownerDefenseDamage = 0;
    if (port.owner != null) {
      NpcShip? owner;
      for (final n in allNpcs) {
        if (n.pilotName == port.owner &&
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
          debugPrint('[${npc.pilotName}] Raid: Port owner ${effectiveOwner.pilotName} '
              'joins defense!');
        } else {
          final adjSectorId = _findAdjacentSector(sectors, npc.currentSectorId);
          if (adjSectorId != null) {
            final idx = allNpcs.indexWhere((n) => n.id == effectiveOwner.id);
            if (idx != -1) {
              allNpcs[idx] = effectiveOwner.copyWith(currentSectorId: adjSectorId);
            }
            debugPrint('[${npc.pilotName}] Raid: Port owner ${effectiveOwner.pilotName} '
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
        );
        updatedNpc = updatedNpc.copyWith(
          currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
          notoriety: (updatedNpc.notoriety + 10).clamp(0, 100),
        );
        debugPrint('[${npc.pilotName}] Raid: Captured ${port.name}');
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
        debugPrint('[${npc.pilotName}] Raid: Destroyed ${port.name}');
        ActionLogProvider.global.error(
          '${npc.pilotName} destroyed ${port.name} in Sector ${sector.id}',
        );
      }
    } else if (result.attackerDefeated) {
      sector.port = PortCombatService.endCombatRetreat(sector.port!);
      updatedNpc = updatedNpc.copyWith(currentGoal: null);
      debugPrint('[${npc.pilotName}] Raid: Defeated by ${port.name} defenses');
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
    if (npc.currentSectorId == goal.targetSectorId) {
      // Placeholder: upgrade logic deferred
      debugPrint('[${npc.pilotName}] Upgrade: Arrived for equipment upgrade '
          '(deferred)');
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }
    return npc;
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
      final theirPower = _calculatePower(enemy);
      if (theirPower > myPower * 1.3) return true;
    }
    return false;
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

    debugPrint('[${npc.pilotName}] Flee: Evading threat in Sector '
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

    // Weighted random pick
    final totalWeight = weights.fold(0.0, (a, b) => a + b);
    if (totalWeight <= 0) return _createExploreGoal(npc, sectors);

    double roll = _rng.nextDouble() * totalWeight;
    int pick = candidates.length - 1;
    for (int i = 0; i < candidates.length; i++) {
      roll -= weights[i];
      if (roll <= 0) {
        pick = i;
        break;
      }
    }

    return _instantiateGoal(candidates[pick], npc, sectors, players, allNpcs);
  }

  static bool _isGoalViable(
    NpcGoalType type,
    NpcShip npc,
    List<Sector> sectors,
  ) {
    switch (type) {
      case NpcGoalType.tradeRoute:
        return npc.memory.discoveredPorts.length >= 2 &&
            npc.credits > 100 &&
            npc.cargoUsed < npc.cargoHoldCapacity;
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
        return npc.credits + npc.bankBalance > 100000;
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
    }
  }

  static NpcGoal? _createTradeRouteGoal(
    NpcShip npc,
    List<Sector> sectors,
  ) {
    final route = TradeEvaluator.findBestTradeRoute(
      npc.currentSectorId,
      npc.memory.discoveredPorts,
      sectors,
      npc.personalityConfig.maxTravelDistance,
    );
    if (route == null) return null;

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
        sectors, npc.currentSectorId, signal.sectorId,
      );
      if (path == null) continue;
      final dist = path.length - 1;
      if (dist < bestDist) {
        bestDist = dist;
        bestSignal = signal;
      }
    }

    if (bestSignal == null) return null;

    debugPrint('[${npc.pilotName}] Responding to distress call from '
        '${bestSignal.targetName} in Sector ${bestSignal.sectorId}');

    return NpcGoal(
      type: NpcGoalType.attack,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': bestSignal.sectorId,
        'targetId': bestSignal.aggressorId,
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

    // 1 — Check same sector for hostile NPCs
    NpcShip? bestTarget;
    int? bestTargetSectorId;
    for (final other in allNpcs) {
      if (other.id == npc.id || other.isDestroyed) continue;
      if (other.currentSectorId != npc.currentSectorId) continue;
      if (!_isHostileFaction(npc.faction, other.faction)) continue;
      final otherPower = CombatService.calculateFirepower(other);
      if (otherPower >= myPower) continue; // only attack weaker targets
      if (bestTarget == null || otherPower < CombatService.calculateFirepower(bestTarget)) {
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
            if (bestTarget == null || otherPower < CombatService.calculateFirepower(bestTarget)) {
              bestTarget = other;
              bestTargetSectorId = warp;
            }
          }
          queue.add((sector: warp, dist: current.dist + 1));
        }
      }
    }

    // 3 — Check for hostile players nearby (skip safe zones)
    if (bestTarget == null) {
      for (final player in players) {
        if (_isSafeZone(player.currentSectorId)) continue;
        if (!_isHostileFaction(npc.faction, player.faction)) continue;
        final playerPower = CombatService.calculatePlayerFirepower(player);
        if (playerPower >= myPower) continue;
        if (player.currentSectorId == npc.currentSectorId) {
          bestTargetSectorId = npc.currentSectorId;
          break;
        }
        // BFS from current to player sector
        final path = PathfindingService.findPath(
          sectors, npc.currentSectorId, player.currentSectorId,
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
    // Find a reachable port with weak defenses, outside safe zones
    final portSectorId = PathfindingService.findNearestWhere(
      sectors,
      npc.currentSectorId,
      (s) =>
          s.hasPort &&
          (s.port?.defenseLevel ?? 4) < 2 &&
          !_isSafeZone(s.id),
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
    // Find nearest port with a Hardware Emporium
    final hwSectorId = PathfindingService.findNearestWhere(
      sectors,
      npc.currentSectorId,
      (s) => s.port?.isHardwareEmporium == true,
    );
    if (hwSectorId == null) return null;

    return NpcGoal(
      type: NpcGoalType.upgradeEquipment,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': hwSectorId},
    );
  }

  // ────────────────────────────────────────────────────────────────
  // Step 6 — Movement
  // ────────────────────────────────────────────────────────────────

  static NpcShip _move(NpcShip npc, List<Sector> sectors) {
    if (npc.turns <= 0) return npc;

    final goal = npc.currentGoal;

    // If we have a goal with a target, pathfind towards it
    if (goal != null &&
        goal.targetSectorId != null &&
        goal.targetSectorId != npc.currentSectorId) {
      final path = PathfindingService.findPath(
        sectors,
        npc.currentSectorId,
        goal.targetSectorId!,
      );
      if (path != null && path.length > 1) {
        final next = path[1];
        debugPrint('[${npc.pilotName}] ${goal.type.name}: Sector '
            '${npc.currentSectorId} → Sector $next');
        return npc.copyWith(
          currentSectorId: next,
          turns: npc.turns - 1,
        );
      }
    }

    // No goal or unreachable target — wander randomly
    final current = _findSector(sectors, npc.currentSectorId);
    if (current == null || current.warpRoutes.isEmpty) return npc;

    final next = current.warpRoutes[_rng.nextInt(current.warpRoutes.length)];
    debugPrint(
        '[${npc.pilotName}] Wander: Sector ${npc.currentSectorId} → Sector $next');
    return npc.copyWith(
      currentSectorId: next,
      turns: npc.turns - 1,
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
