// Goal execution: dispatcher plus every _execute* leg, trade failure handling, port management, upgrades.
part of 'npc_ai_service.dart';

// ────────────────────────────────────────────────────────────────
// Step 2 — Goal execution
// ────────────────────────────────────────────────────────────────

NpcShip _executeGoal(
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
      return _executeTradeGoal(npc, sectors, goal, allNpcs);
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

NpcShip _executeRefuelGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;
  // Memory can go stale (port destroyed/captured) — fail cleanly so the
  // NPC re-plans instead of drinking from an empty pump.
  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
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

/// Logs a dead trade route, starts its cooldown, and clears the goal so
/// reselection can run. Every terminal failure below is visible in the
/// trade log — silent kills were how live trade volume dropped to zero
/// unnoticed.
///
/// Sell-only runs (buyPortId == sellPortId) cool under a `sell>` key
/// namespace (review batch 3, P1): the evaluator only ever produces
/// `buy>sell` keys with distinct sectors, so shared keys would pile up
/// unmatched forever.
NpcShip _failTrade(NpcShip npc, NpcGoal goal, String reason) {
  GameEventLog.global.trade(
    '[${npc.pilotName}] Trade: route failed ($reason)',
  );
  final key = goal.buyPortId == goal.sellPortId
      ? 'sell>${goal.sellPortId}:${goal.commodity}'
      : NpcMemory.routeKey(goal.buyPortId, goal.sellPortId, goal.commodity);
  return npc.copyWith(
    clearGoal: true,
    memory: npc.memory.withFailedRoute(key),
  );
}

NpcShip _executeTradeGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
  List<NpcShip> allNpcs,
) {
  final buyPortId = goal.buyPortId;
  final sellPortId = goal.sellPortId;
  final commodity = goal.commodity;
  if (buyPortId == null || sellPortId == null || commodity == null) {
    return npc.copyWith(clearGoal: true);
  }

  // Convoy muster (C3): escorts scatter when the leader is gone, and
  // fly solo when the leader's run is done or diverged. Leaders are
  // traders flying their own route; the escort's legs stay valid alone.
  final convoyLeader = goal.params['convoyLeader'] as String?;
  var liveGoal = goal;
  if (convoyLeader != null) {
    NpcShip? leader;
    for (final n in allNpcs) {
      if (n.id == convoyLeader) {
        leader = n;
        break;
      }
    }
    final leaderGoal = leader?.currentGoal;
    if (leader == null || leader.isDestroyed) {
      GameEventLog.global
          .goal('[${npc.pilotName}] Convoy scattered — leader gone');
      return npc.copyWith(clearGoal: true);
    }
    final sameRoute = leaderGoal != null &&
        leaderGoal.type == NpcGoalType.tradeRoute &&
        leaderGoal.status == NpcGoalStatus.travelling &&
        leaderGoal.buyPortId == buyPortId &&
        leaderGoal.sellPortId == sellPortId &&
        leaderGoal.commodity == commodity;
    if (!sameRoute) {
      GameEventLog.global
          .goal('[${npc.pilotName}] Convoy run over — flying solo');
      final soloParams = Map<String, dynamic>.from(goal.params)
        ..remove('convoyLeader');
      liveGoal = goal.copyWith(params: soloParams);
      npc = npc.copyWith(currentGoal: liveGoal);
    }
  }

  final phase = liveGoal.params['phase'] as String? ?? 'travel_to_buy';
  // From here the (possibly de-convoyed) goal is the live one.
  goal = liveGoal;
  final nowMs = DateTime.now().millisecondsSinceEpoch;

  // ── Phase: arrived at buy port ──
  if (phase == 'travel_to_buy' && npc.currentSectorId == buyPortId) {
    final sector = NpcAiService._findSector(sectors, buyPortId);
    if (sector == null) {
      return _failTrade(npc, goal, 'buy sector $buyPortId vanished');
    }
    var port = sector.port;
    if (port == null) {
      return _failTrade(npc, goal, '${sector.name} lost its port');
    }

    // Service check (review batch 3, P1): refused or wrecked ports
    // don't trade, same as refuel/upgrade already enforce.
    final buyStanding = FactionStanding.resolveFor(
      npc.faction,
      port.ownerFaction,
      npc.memory.factionStandings,
    );
    if (port.isDestroyed) {
      return _failTrade(npc, goal, '${port.name} destroyed');
    }
    if (port.deniesServiceTo(buyStanding)) {
      return _failTrade(npc, goal, '${port.name} refuses service');
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
    var ownerSurcharge = port.isOwned ? (cost * port.ownerTaxRate).round() : 0;
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

    GameEventLog.global
        .trade('[${npc.pilotName}] Trade: Bought $maxBuyable $commodity at '
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
    final sector = NpcAiService._findSector(sectors, sellPortId);
    if (sector == null) {
      return _failTrade(npc, goal, 'sell sector $sellPortId vanished');
    }
    var port = sector.port;
    if (port == null) {
      return _failTrade(npc, goal, '${sector.name} lost its port');
    }

    // Service check (review batch 3, P1): refused or wrecked ports
    // don't buy either.
    final sellStanding = FactionStanding.resolveFor(
      npc.faction,
      port.ownerFaction,
      npc.memory.factionStandings,
    );
    if (port.isDestroyed) {
      return _failTrade(npc, goal, '${port.name} destroyed');
    }
    if (port.deniesServiceTo(sellStanding)) {
      return _failTrade(npc, goal, '${port.name} refuses service');
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

    // Route learning (C2d): profitable runs teach; losses don't.
    // Mirrors the failed-route cooldown with a positive signal.
    // Sell-only self-loops (buyPortId == sellPortId) teach nothing
    // the evaluator could ever match (review batch 3, P1). First wins
    // log one line per route ever (soak instrumentation).
    final routeKey =
        NpcMemory.routeKey(goal.buyPortId, goal.sellPortId, commodity);
    final teachable = profit > 0 && goal.buyPortId != goal.sellPortId;
    if (teachable && !npc.memory.profitableRoutes.containsKey(routeKey)) {
      GameEventLog.global
          .trade('[${npc.pilotName}] Learned profitable route $routeKey');
    }
    return npc.copyWith(
      credits: npc.credits + npcReceives,
      cargo: newCargo,
      cargoUsed: npc.cargoUsed - actualQuantity,
      memory:
          (teachable ? npc.memory.withProfitableRoute(routeKey) : npc.memory)
              .copyWith(lastTradeTime: DateTime.now()),
      currentGoal: goal.copyWith(
        status: NpcGoalStatus.complete,
        params: {...goal.params, 'profit': profit},
      ),
    );
  }

  return npc;
}

/// Owner paperwork: collect accumulated revenue from owned ports and
/// buy one defense or storage upgrade when flush (50k operating reserve
/// kept). Turns ownership from a flag into the income engine.
NpcShip _manageOwnedPorts(NpcShip npc, List<Sector> sectors) {
  var updated = npc;

  for (final sector in NpcAiService._ownedSectors(npc, sectors)) {
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

    // One upgrade per tick max: defense first, then storage. A spent
    // upgrade must not eat sibling ports' revenue (review batch 3, P1):
    // the old break exited the whole sector loop, so ports after the
    // upgraded one skipped collection that tick.
    var upgraded = false;
    final live = sector.port!;
    if (!upgraded && live.defenseLevel < 4) {
      final cost = live.defenseUpgradeCost.round();
      if (updated.credits - cost >= 50000) {
        sector.port = live.copyWith(defenseLevel: live.defenseLevel + 1);
        updated = updated.copyWith(credits: updated.credits - cost);
        GameEventLog.global.goal(
          '[${npc.pilotName}] Port upgrade: ${port.name} defenses → '
          'level ${live.defenseLevel + 1} for $cost cr',
        );
        upgraded = true;
      }
    } else if (!upgraded && live.storageLevel < 10) {
      final cost = live.storageUpgradeCost;
      if (cost.isFinite && updated.credits - cost.round() >= 50000) {
        sector.port = live.copyWith(storageLevel: live.storageLevel + 1);
        updated = updated.copyWith(credits: updated.credits - cost.round());
        GameEventLog.global.goal(
          '[${npc.pilotName}] Port upgrade: ${port.name} storage → '
          'level ${live.storageLevel + 1}',
        );
        upgraded = true;
      }
    }
  }
  return updated;
}

NpcShip _executeBankDepositGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;

  // Destination must still be a live port — memory goes stale when
  // ports are captured/destroyed en route (same rule as refuel/trade).
  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
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

NpcShip _executeBankWithdrawGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;

  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
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

NpcShip _executeExploreGoal(
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

NpcShip _executePatrolGoal(
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
    if (legs >= NpcAiService.maxPatrolLegs) {
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }
    // Border holds (C3) sit: the post is the patrol, not a waypoint.
    // Hostile pressure is re-checked at the next selection cycle, so
    // holds are sticky for a few legs, then re-evaluated, never eternal.
    if (goal.params['borderHold'] != null) {
      return npc.copyWith(
        currentGoal: goal.copyWith(
          params: {...goal.params, 'legs': legs},
        ),
      );
    }
    // Pick a new random patrol target
    final current = NpcAiService._findSector(sectors, npc.currentSectorId);
    if (current == null || current.warpRoutes.isEmpty) {
      return npc.copyWith(
        currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
      );
    }
    final next = current
        .warpRoutes[NpcAiService._rng.nextInt(current.warpRoutes.length)];
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

NpcShip _executeFleeGoal(
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

NpcShip _executeAttackGoal(
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
      GameEventLog.global
          .combat('[${npc.pilotName}] Standing down — distress call resolved');
      return npc.copyWith(clearGoal: true);
    }
  }

  // Vendetta pursuit budget in time (C2a): a grudge funds a hunt, not
  // an eternity. Expired hunts stand down; the memory (with its own
  // 6h decay) decides whether a fresh hunt starts later.
  final vendettaFor = goal.params['vendettaFor'] as String?;
  if (vendettaFor != null &&
      DateTime.now().difference(goal.createdAt) > vendettaPursuitTtl) {
    GameEventLog.global
        .combat('[${npc.pilotName}] Calling off the hunt for $vendettaFor — '
            'trail gone cold');
    return npc.copyWith(clearGoal: true);
  }

  if (npc.currentSectorId != goal.targetSectorId) return npc;

  // Safe zone check — no attacks allowed
  if (NpcAiService._isSafeZone(npc.currentSectorId)) {
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
    // Distress responder arriving to an empty sector: if the defender
    // is gone too (fled, or cleared by another responder), the fight is
    // over — clear the signal so no further wings converge on nowhere,
    // then stand down. (Defender death already clears it at kill time.)
    if (distressFor != null) {
      final defenderPresent = allNpcs.any((n) =>
          n.id == distressFor &&
          n.currentSectorId == npc.currentSectorId &&
          !n.isDestroyed);
      if (!defenderPresent) {
        _activeDistressSignals.remove(distressFor);
        GameEventLog.global
            .combat('[${npc.pilotName}] Arrived to an empty fight in Sector '
                '${npc.currentSectorId} — distress call cleared');
      }
    }
    GameEventLog.global
        .combat('[${npc.pilotName}] Attack: Target $targetId not found in '
            'Sector ${npc.currentSectorId}');
    // Dry hole on a vendetta hunt (C2a): the trail cools but the
    // memory keeps its window — no sighting refresh, so camping can't
    // hold a grudge open. Easing to zero drops the grudge outright.
    // A live grudge widens the search (C3): intel moves next door,
    // decay untouched — checking nearby is searching, not sighting.
    if (vendettaFor != null) {
      final before = npc.memory.vendettas[vendettaFor]?.grievance ?? 0;
      var eased = npc.copyWith(
        memory: npc.memory.withVendettaEased(vendettaFor, vendettaDryHoleEase),
        clearGoal: true,
      );
      final after = eased.memory.vendettas[vendettaFor]?.grievance;
      GameEventLog.global
          .combat('[${npc.pilotName}] Hunt for $vendettaFor came up empty in '
              'Sector ${npc.currentSectorId} (grudge $before → ${after ?? 0})');
      if ((after ?? 0) >= vendettaGrievanceThreshold) {
        final options = NpcAiService._findSector(sectors, npc.currentSectorId)
                ?.warpRoutes ??
            const <int>[];
        if (options.isNotEmpty) {
          final spread = options[NpcAiService._rng.nextInt(options.length)];
          eased = eased.copyWith(
            memory: eased.memory.withVendettaRelocated(vendettaFor, spread),
          );
          GameEventLog.global
              .combat('[${npc.pilotName}] Widening the search for $vendettaFor '
                  'to Sector $spread');
        }
      }
      return eased;
    }
    return npc.copyWith(clearGoal: true);
  }

  final myPower = CombatService.calculateFirepower(npc);
  final targetPower = CombatService.calculateFirepower(target);
  final log = ActionLogProvider.global;

  // ── Distress call: unfair fight, or any fight the defender is
  // losing badly (P5: hull under 40% calls for help regardless of the
  // opening odds — reinforcements reuse the capped responder path).
  final defenderBleeding =
      target.maxHull > 0 && target.hull < target.maxHull * 0.4;
  if (myPower > targetPower * 2.0 || defenderBleeding) {
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

  // C5 measurement: every resolution counts, at this single choke
  // point, whatever the outcome (kills, retreats, surrenders).
  CombatMetrics.global.recordNpc(
    attackerFaction: npc.faction.name,
    defenderFaction: target.faction.name,
    outcome: result.result.outcome,
    attackerHullFraction:
        CombatMetrics.fractionOf(result.attacker.hull, result.attacker.maxHull),
    defenderHullFraction:
        CombatMetrics.fractionOf(result.defender.hull, result.defender.maxHull),
    tribute: result.result.parleyCostCredits,
  );

  // Update defender in-place in the list. Survivors grow warier
  // (C4d drift) — living through someone's guns teaches caution,
  // wreckage notwithstanding (the dead don't spend it). Milestone
  // lines per tier crossed (soak instrumentation).
  final idx = allNpcs.indexWhere((n) => n.id == targetId);
  if (idx != -1) {
    final survived = result.defender.driftedForSurvival();
    allNpcs[idx] = survived;
    if (NpcShip.driftTierCrossed(
        result.defender.driftCaution, survived.driftCaution)) {
      GameEventLog.global
          .combat('[${survived.pilotName}] Veteran warier: caution '
              '${survived.driftCaution.toStringAsFixed(2)}');
    }
  }

  if (result.result.defenderDestroyed) {
    // Clear distress signal if defender had one
    _activeDistressSignals.remove(target.id);
    log.combat('[${result.attacker.pilotName}] Destroyed ${target.pilotName} '
        '(${target.shipName}) in Sector ${npc.currentSectorId}');
    log.combat(NpcDeathCries.formatDeathCry(target.pilotName, target.faction));
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
      killerFaction: result.attacker.faction.name,
      targetFaction: target.faction.name,
    );
    // Post-kill retaliation intent (C1c): same-faction witnesses in
    // this sector record the killer. Memory only — vendetta goals and
    // pursuit arrive in C2, and goal changes still go through the
    // interruption policy, so this never hijacks a committed goal.
    // Runs on every kill, independent of any bounty payout.
    var witnesses = 0;
    for (int i = 0; i < allNpcs.length; i++) {
      final witness = allNpcs[i];
      if (witness.id == target.id ||
          witness.id == npc.id ||
          witness.isDestroyed ||
          witness.faction != target.faction ||
          witness.currentSectorId != npc.currentSectorId) {
        continue;
      }
      allNpcs[i] = witness.copyWith(
        memory: witness.memory.withVendetta(
          targetId: npc.id,
          sectorId: npc.currentSectorId,
          grievanceBump: 40,
        ),
      );
      witnesses++;
    }
    if (witnesses > 0) {
      GameEventLog.global
          .combat('$witnesses ${target.faction.name} witness(es) recorded '
              '${npc.pilotName} over Sector ${npc.currentSectorId}');
    }
    // Vengeance satisfied (C2b): a vendetta against the dead target
    // resolves regardless of any bounty payout. Memory only.
    // Killers grow bolder (C4d drift) on the same occasion — a
    // milestone line per tier crossed (soak instrumentation).
    var resolvedAttacker = result.attacker.driftedForKill();
    if (NpcShip.driftTierCrossed(
        result.attacker.driftAggression, resolvedAttacker.driftAggression)) {
      GameEventLog.global
          .combat('[${resolvedAttacker.pilotName}] Veteran bolder: aggression '
              '${resolvedAttacker.driftAggression.toStringAsFixed(2)}');
    }
    // Legends earn their price (review batch 1): a hero's kill posts
    // the Guild bounty when none is active — never at spawn, so
    // newborn legends aren't beelined before doing anything legendary.
    if (result.attacker.heroName != null &&
        BountyBoard.global.totalFor(result.attacker.id) <= 0) {
      BountyBoard.global.post(
        targetId: result.attacker.id,
        targetName: result.attacker.heroName!,
        targetFaction: result.attacker.faction.name,
        amount: RepopulationService.heroBounty,
        posterId: 'CHRONICLERS',
        posterName: 'Guild Chroniclers',
        posterFaction: FactionClass.trader.name,
        reason:
            'living legend — ${result.attacker.heroTitle ?? 'terror of the spacelanes'}',
      );
    }
    if (resolvedAttacker.memory.vendettas.containsKey(target.id)) {
      resolvedAttacker = resolvedAttacker.copyWith(
        memory: resolvedAttacker.memory.withVendettaResolved(target.id),
      );
      GameEventLog.global
          .combat('[${resolvedAttacker.pilotName}] Settled the score with '
              '${target.pilotName} in Sector ${npc.currentSectorId}');
    }
    if (paid > 0) {
      var enriched = resolvedAttacker.copyWith(
        credits: resolvedAttacker.credits + paid,
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
    return resolvedAttacker.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  } else {
    log.combat('[${result.attacker.pilotName}] Engaged ${target.pilotName} '
        '(dealt ${result.result.damageToDefender}, '
        'took ${result.result.damageToAttacker})');
    GameEventLog.global.combat(
        '[${result.attacker.pilotName}] Combat: Engaged ${target.pilotName} '
        '(dealt ${result.result.damageToDefender}, '
        'took ${result.result.damageToAttacker})');
    // Hot blood talks (P5): aggressive attackers taunt on contact.
    // Cool heads fight silent — one line per engagement, never spam.
    if (result.attacker.personalityConfig.aggression >= 0.6) {
      GameEventLog.global.combat(NpcTaunts.formatTaunt(
          result.attacker.pilotName, result.attacker.faction));
    }
    // Survivor posts a bounty on the aggressor from its own bankroll
    // (flat 5000 when affordable) — hits fund the board that pays hits.
    // Debit first: post() is infallible for validated amounts, so the
    // bounty can never exist unpaid-for. Skipped when the aggressor
    // died in the exchange (review batch 3, P1): a corpse can't earn,
    // so the bounty would sit unclaimable forever.
    final survivor = allNpcs[idx];
    if (survivor.credits >= 10000 && !result.attacker.isDestroyed) {
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
    // Fresh sighting on a vendetta hunt (C2b): crossed blades with the
    // target, so the trail is warm — refresh where they were seen with
    // a small bump, whether they stood or slipped away (retreats
    // resolve inside combat; the sighting is real either way).
    var engagedAttacker = result.attacker;
    if (goal.params['vendettaFor'] == target.id) {
      engagedAttacker = engagedAttacker.copyWith(
        memory: engagedAttacker.memory.withVendetta(
          targetId: target.id,
          sectorId: npc.currentSectorId,
          grievanceBump: 10,
        ),
      );
    }
    return engagedAttacker.copyWith(
      currentGoal: goal.copyWith(status: NpcGoalStatus.complete),
    );
  }
}

NpcShip _executeRaidPortGoal(
  NpcShip npc,
  List<Sector> sectors,
  List<NpcShip> allNpcs,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;

  final sector = NpcAiService._findSector(sectors, goal.targetSectorId!);
  final port = sector?.port;
  if (port == null) return npc.copyWith(clearGoal: true);

  // Safe zone check
  if (NpcAiService._isSafeZone(sector!.id)) {
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
        final adjSectorId =
            NpcAiService._findAdjacentSector(sectors, npc.currentSectorId);
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
  var result = PortCombatService.resolveNpcPortAttack(npc, sector.port!, mode);

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

NpcShip _executeUpgradeGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;

  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
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
      updated.credits >= NpcAiService.npcSolarArrayCostCredits &&
      (updated.personalityConfig.caution > 0.5 ||
          updated.personalityConfig.explorationDrive > 0.6)) {
    GameEventLog.global
        .energy('NPC_ENERGY event=array_buy pilot=${updated.pilotName} '
            'spent=$NpcAiService.npcSolarArrayCostCredits');
    ActionLogProvider.global.trade(
      '${updated.pilotName} installed a Solar Array',
    );
    return updated.copyWith(
      credits: updated.credits - NpcAiService.npcSolarArrayCostCredits,
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
NpcShip _repairShip(NpcShip npc) {
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

/// Single equipment purchase for [slot], or null when capped or
/// unaffordable (keeps 5k operating cash after the price).
NpcShip? _buyUpgrade(NpcShip npc, String slot) {
  int level;
  int price;
  switch (slot) {
    case 'hull':
      level = npc.hullEquipmentLevel;
      if (level >= NpcAiService._maxEquipmentLevel) return null;
      price = 15000 * level;
      break;
    case 'shields':
      level = npc.shieldEquipmentLevel;
      if (level >= NpcAiService._maxEquipmentLevel) return null;
      price = 15000 * level;
      break;
    case 'engine':
      level = npc.engineEquipmentLevel;
      if (level >= NpcAiService._maxEquipmentLevel) return null;
      price = 20000 * level;
      break;
    case 'weapons':
      if (npc.weaponSlots.isEmpty) return null;
      final weakest =
          npc.weaponSlots.entries.reduce((a, b) => a.value <= b.value ? a : b);
      if (weakest.value >= NpcAiService._maxWeaponLevel) return null;
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

NpcShip _executeBuyPortGoal(
  NpcShip npc,
  List<Sector> sectors,
  NpcGoal goal,
) {
  if (npc.currentSectorId != goal.targetSectorId) return npc;

  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
  final port = sector?.port;
  if (!_isPurchasable(port)) {
    // Sold, federalized, or gone while en route — move on.
    return npc.copyWith(clearGoal: true);
  }
  final price = NpcAiService.npcPortPrice(port!);
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

// ────────────────────────────────────────────────────────────────
// Step 2d — Co-located barter (P5 living economy)
// ────────────────────────────────────────────────────────────────

/// NPC↔NPC trade when hulls share a sector (P5): one deal per turn.
/// The NPC sells what it carries (registry order) to the first
/// non-hostile, living, co-located buyer with room and credits — or
/// buys when its own holds are the empty ones. Price is the registry
/// split-point midpoint: fair middle, zero-sum, no money printed.
/// Recorded on both sides in EconomyMetrics like port legs. Returns
/// the caller's live entry re-read by id (counterparties write back
/// in place; indexed copies go stale mid-tick).
NpcShip _barterWithNpc(NpcShip npc, List<NpcShip> allNpcs) {
  final mates = NpcAiService.npcsBySector?[npc.currentSectorId] ?? allNpcs;
  for (final mate in mates) {
    if (mate.id == npc.id || mate.isDestroyed) continue;
    if (mate.currentSectorId != npc.currentSectorId) continue;
    if (NpcAiService._isHostileFaction(npc.faction, mate.faction)) continue;
    // Direction 1: I sell, they buy.
    for (final name in CommodityRegistry.names) {
      if ((npc.cargo[name] ?? 0) <= 0) continue;
      if (_barterLeg(
          seller: npc, buyer: mate, commodity: name, allNpcs: allNpcs)) {
        return allNpcs.firstWhere((n) => n.id == npc.id, orElse: () => npc);
      }
    }
    // Direction 2: they sell, I buy (my holds were the empty ones).
    for (final name in CommodityRegistry.names) {
      if ((mate.cargo[name] ?? 0) <= 0) continue;
      if (_barterLeg(
          seller: mate, buyer: npc, commodity: name, allNpcs: allNpcs)) {
        return allNpcs.firstWhere((n) => n.id == npc.id, orElse: () => npc);
      }
    }
  }
  return npc;
}

/// One barter leg. Writes both sides back by id; true on success.
bool _barterLeg({
  required NpcShip seller,
  required NpcShip buyer,
  required String commodity,
  required List<NpcShip> allNpcs,
}) {
  final config = CommodityRegistry.defaultsMap[commodity];
  if (config == null) return false;
  final unitPrice = config.splitPoint.round();
  if (unitPrice <= 0) return false;
  final sellerQty = seller.cargo[commodity] ?? 0;
  final buyerRoom = buyer.cargoHoldCapacity - buyer.cargoUsed;
  final affordable = buyer.credits ~/ unitPrice;
  var units = sellerQty;
  if (buyerRoom < units) units = buyerRoom;
  if (affordable < units) units = affordable;
  if (seller.cargoUsed < units) units = seller.cargoUsed;
  if (units <= 0) return false;
  final total = units * unitPrice;

  final sellerCargo = Map<String, int>.from(seller.cargo);
  sellerCargo[commodity] = sellerQty - units;
  if (sellerCargo[commodity]! <= 0) sellerCargo.remove(commodity);
  final buyerCargo = Map<String, int>.from(buyer.cargo);
  buyerCargo[commodity] = (buyerCargo[commodity] ?? 0) + units;

  final now = DateTime.now();
  final si = allNpcs.indexWhere((n) => n.id == seller.id);
  final bi = allNpcs.indexWhere((n) => n.id == buyer.id);
  if (si == -1 || bi == -1) return false;
  allNpcs[si] = seller.copyWith(
    credits: seller.credits + total,
    cargo: sellerCargo,
    cargoUsed: seller.cargoUsed - units,
    memory: seller.memory.copyWith(lastTradeTime: now),
  );
  allNpcs[bi] = buyer.copyWith(
    credits: buyer.credits - total,
    cargo: buyerCargo,
    cargoUsed: buyer.cargoUsed + units,
    memory: buyer.memory.copyWith(lastTradeTime: now),
  );

  EconomyMetrics.global.recordTrade(
    commodity: commodity,
    units: units,
    credits: total,
    actorFaction: seller.faction.name,
    isPlayer: false,
    isBuy: false,
  );
  EconomyMetrics.global.recordTrade(
    commodity: commodity,
    units: units,
    credits: total,
    actorFaction: buyer.faction.name,
    isPlayer: false,
    isBuy: true,
  );
  GameEventLog.global.trade(
    '[${seller.pilotName}] Bartered $units $commodity to '
    '[${buyer.pilotName}] for $total cr',
  );
  return true;
}
