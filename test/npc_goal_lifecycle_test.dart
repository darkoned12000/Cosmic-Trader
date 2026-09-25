import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

// Regression: two stall bugs that froze all NPC trade/combat/banking live.
// 1. copyWith(currentGoal: null) silently KEPT the old goal (?? fallback),
//    so every failed goal blocked reselection forever.
// 2. Patrol goals never completed (absorbing), so _needsNewGoal never fired
//    again once a patrol was adopted.
void main() {
  NpcShip spawn({NpcGoal? goal}) {
    return NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 10000,
      seed: 9,
    ).copyWith(currentGoal: goal);
  }

  NpcGoal patrolAt(int sector, {int legs = 0}) => NpcGoal(
        type: NpcGoalType.patrol,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {'targetSectorId': sector, 'legs': legs},
      );

  test('clearGoal:true clears, omitted keeps', () {
    final withGoal = spawn(
      goal: patrolAt(2),
    );
    expect(withGoal.currentGoal, isNotNull);

    // Plain copyWith keeps the goal.
    expect(withGoal.copyWith(credits: 5).currentGoal, isNotNull);

    // Explicit clear works.
    final cleared = withGoal.copyWith(clearGoal: true);
    expect(cleared.currentGoal, isNull);
  });

  test('failed trade goal clears instead of sticking', () {
    // Buy port with zero supply for the wanted commodity.
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [2],
        hasPort: true,
        port: const Port(
          name: 'Empty',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 10.0},
          supply: {'minerals': 0},
          demand: {'minerals': 100},
        ),
      ),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];
    final npc = spawn(
      goal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {
          'targetSectorId': 1,
          'buyPortId': 1,
          'sellPortId': 2,
          'commodity': 'minerals',
          'phase': 'travel_to_buy',
        },
      ),
    );

    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // Supply is zero → buy fails → goal must clear so reselection can run.
    // (Before the fix the stale travel_to_buy goal stuck forever.)
    expect(
      after.currentGoal == null ||
          after.currentGoal!.type != NpcGoalType.tradeRoute ||
          after.currentGoal!.status == NpcGoalStatus.complete,
      isTrue,
    );
  });

  test('patrol completes after maxPatrolLegs arrivals', () {
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];

    // 4 legs done, arriving at target → 5th leg hits the cap → the patrol
    // completes, and the same tick selects a fresh goal (which may itself
    // be a new patrol — so assert the expired counter is gone, not the type).
    var npc = spawn(goal: patrolAt(1, legs: 4));
    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    final g = npc.currentGoal;
    expect(
      g == null ||
          g.status == NpcGoalStatus.complete ||
          (g.params['legs'] as int? ?? 0) < 4,
      isTrue,
      reason: 'expired patrol must complete or be replaced, got $g',
    );

    // Fresh patrol keeps going and counts legs.
    npc = spawn(goal: patrolAt(1));
    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.currentGoal?.status, NpcGoalStatus.travelling);
    expect(npc.currentGoal?.params['legs'], 1);
  });

  test('peaceful NPC outfits defense first, aggressive buys weapons', () {
    List<Sector> emporium() => [
          Sector(
            id: 1,
            name: 'A',
            x: 0,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: const Port(
              name: 'Emporium',
              portClass: PortClass.hardwareEmporium,
              buyPrices: {},
              sellPrices: {},
            ),
          ),
        ];
    NpcGoal upgradeGoal() => NpcGoal(
          type: NpcGoalType.upgradeEquipment,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {'targetSectorId': 1},
        );

    // Peaceful trader (aggression 0.1): shields first.
    var peaceful = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 50000,
      seed: 21,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      solarArrayLevel: 1, // skip the array branch, test equipment
      currentGoal: upgradeGoal(),
    );
    final shieldsBefore = peaceful.maxShields;
    peaceful = NpcAiService.processTurn(peaceful, emporium(), [], [peaceful]);
    expect(peaceful.shieldEquipmentLevel, 2);
    expect(peaceful.maxShields, shieldsBefore + 20);
    // Upgrade completed, so the same tick selects a fresh goal.
    expect(peaceful.currentGoal?.type, isNot(NpcGoalType.upgradeEquipment));

    // Aggressive pirate (aggression 0.8): weapons first.
    var pirate = NpcShip.create(
      faction: FactionClass.pirate,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 50000,
      seed: 22,
    ).copyWith(
      personality: NpcPersonality.pirateRaider,
      solarArrayLevel: 1,
      currentGoal: upgradeGoal(),
    );
    final weaponsBefore = Map<String, int>.from(pirate.weaponSlots);
    pirate = NpcAiService.processTurn(pirate, emporium(), [], [pirate]);
    expect(
      pirate.weaponSlots.values.fold(0, (a, b) => a + b),
      weaponsBefore.values.fold(0, (a, b) => a + b) + 1,
    );
  });

  test('damaged NPC repairs before upgrading', () {
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Emporium',
          portClass: PortClass.hardwareEmporium,
          buyPrices: {},
          sellPrices: {},
        ),
      ),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 20000,
      seed: 23,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      solarArrayLevel: 1,
      hull: 10,
      shields: 0,
      currentGoal: NpcGoal(
        type: NpcGoalType.upgradeEquipment,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {'targetSectorId': 1},
      ),
    );
    final hullBefore = npc.hull;
    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // 20k covers full repair ((maxHull-10)*2 + maxShields) with cash left,
    // so hull/shields rise and the ship keeps operating reserves.
    expect(npc.hull, greaterThan(hullBefore));
    expect(npc.shields, greaterThan(0));
  });

  test('full holds become a sell-first route instead of deadlocking trade', () {
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [2],
      ),
      Sector(
        id: 2,
        name: 'B',
        x: 1,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Buyer',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
          supply: {},
          demand: {'minerals': 5000},
          maxSupply: {},
          maxDemand: {'minerals': 5000},
          portCredits: 1000000,
          desiredCredits: 1000000,
        ),
      ),
    ];
    var memory = const NpcMemory();
    memory = memory.withVisitedSector(1).withVisitedSector(2);
    memory = memory.withDiscoveredPort(
      2,
      const PortInfo(
        name: 'Buyer',
        portClass: PortClass.free,
        buyPrices: {'minerals': 200.0},
        sellPrices: {},
      ),
    );
    // Second port so the viability gate (>= 2 known) passes.
    memory = memory.withDiscoveredPort(
      1,
      const PortInfo(
        name: 'Nowhere',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {},
      ),
    );
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 5000,
      seed: 41,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      memory: memory,
      cargo: const {'minerals': 20},
      cargoUsed: 20,
    );
    expect(npc.cargoUsed, npc.cargoHoldCapacity);

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // Travels to the buyer with a sell-first route...
    expect(npc.currentSectorId, 2);
    expect(npc.currentGoal?.params['phase'], 'travel_to_sell');

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // ...and unloads for cash, freeing the holds.
    expect(npc.cargoUsed, lessThan(20));
    expect(npc.credits, greaterThan(5000));
  });

  test('banking no longer clobbers a travelling trade route', () {
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];
    // Rich enough to trigger BankingAi.shouldDeposit mid-route.
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 200000,
      seed: 61,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      bankBalance: 0,
      currentGoal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 2,
          'buyPortId': 2,
          'sellPortId': 1,
          'commodity': 'minerals',
          'phase': 'travel_to_buy',
        },
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // Trade survives the banking step now (pre-fix: replaced by deposit).
    expect(npc.currentGoal?.type, NpcGoalType.tradeRoute);
  });

  test('broke NPC with full holds can still sell', () {
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(
        id: 2,
        name: 'B',
        x: 1,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Buyer',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
          supply: {},
          demand: {'minerals': 5000},
          maxSupply: {},
          maxDemand: {'minerals': 5000},
          portCredits: 1000000,
          desiredCredits: 1000000,
        ),
      ),
    ];
    var memory = const NpcMemory();
    memory = memory.withVisitedSector(1).withVisitedSector(2);
    memory = memory.withDiscoveredPort(
      2,
      const PortInfo(
        name: 'Buyer',
        portClass: PortClass.free,
        buyPrices: {'minerals': 200.0},
        sellPrices: {},
      ),
    );
    memory = memory.withDiscoveredPort(
      1,
      const PortInfo(
        name: 'Nowhere',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {},
      ),
    );
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 0,
      seed: 62,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      memory: memory,
      credits: 0,
      cargo: const {'minerals': 20},
      cargoUsed: 20,
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.currentSectorId, 2);
    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.credits, greaterThan(0));
  });

  test('failed routes cool down then recover', () {
    const key = '1>2:minerals';
    var memory = const NpcMemory().withFailedRoute(key, nowMs: 1000);
    expect(memory.isRouteCooling(key, nowMs: 1000 + 60 * 1000), isTrue);
    expect(
      memory.isRouteCooling(key,
          nowMs: 1000 + NpcMemory.routeCooldown.inMilliseconds + 1),
      isFalse,
    );
    expect(memory.coolingRoutes(nowMs: 1000 + 60 * 1000), {key});

    // Evaluator skips the cooling route…
    final knownPorts = {
      1: const PortInfo(
        name: 'P1',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {'minerals': 10.0},
      ),
      2: const PortInfo(
        name: 'P2',
        portClass: PortClass.free,
        buyPrices: {'minerals': 200.0},
        sellPrices: {},
      ),
    };
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];
    final skipped = TradeEvaluator.findBestTradeRoute(
      1,
      knownPorts,
      sectors,
      30,
      avoidRoutes: {key},
    );
    expect(skipped, isNull);

    // …and picks it up again with no avoid set.
    final picked =
        TradeEvaluator.findBestTradeRoute(1, knownPorts, sectors, 30);
    expect(picked, isNotNull);
    expect(picked!.buySectorId, 1);
  });

  test('every personality has a config entry', () {
    for (final p in NpcPersonality.values) {
      expect(PersonalityConfig.all.containsKey(p), isTrue,
          reason: 'missing config for $p');
    }
  });

  test('broke NPC cannot buy on credit (credits never negative)', () {
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Expensive',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'munitions': 500.0},
          supply: {'munitions': 100},
          demand: {},
          maxSupply: {'munitions': 100},
          maxDemand: {},
          portCredits: 1000000,
          desiredCredits: 1000000,
        ),
      ),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 50,
      seed: 71,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      credits: 50,
      currentGoal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 1,
          'buyPortId': 1,
          'sellPortId': 1,
          'commodity': 'munitions',
          'phase': 'travel_to_buy',
        },
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // 50cr cannot cover 1 unit at 500cr: no purchase, no debt.
    expect(npc.credits, greaterThanOrEqualTo(0));
    expect(npc.cargoUsed, 0);
  });

  test('evaluator filters routes the bankroll cannot start', () {
    final knownPorts = {
      1: const PortInfo(
        name: 'P1',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {'munitions': 500.0},
      ),
      2: const PortInfo(
        name: 'P2',
        portClass: PortClass.free,
        buyPrices: {'munitions': 700.0},
        sellPrices: {},
      ),
    };
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];
    // 50cr bankroll: 500cr buy leg filtered out.
    expect(
      TradeEvaluator.findBestTradeRoute(1, knownPorts, sectors, 30,
          credits: 50),
      isNull,
    );
    // Funded: route found.
    final route = TradeEvaluator.findBestTradeRoute(1, knownPorts, sectors, 30,
        credits: 10000);
    expect(route, isNotNull);
    expect(route!.commodity, 'munitions');
  });

  test('bank goal at a vanished port aborts instead of transacting', () {
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [1]),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 200000,
      seed: 72,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      bankBalance: 0,
      currentGoal: NpcGoal(
        type: NpcGoalType.bankDeposit,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {'targetSectorId': 1, 'depositAmount': 140000},
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // No port in sector 1: no deposit, goal cleared for replan.
    expect(npc.bankBalance, 0);
    expect(npc.credits, 200000);
  });

  test('withdraw does not clobber an in-progress upgrade trip', () {
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(
        id: 2,
        name: 'B',
        x: 1,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Emporium',
          portClass: PortClass.hardwareEmporium,
          buyPrices: {},
          sellPrices: {},
        ),
      ),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 1000,
      seed: 73,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      credits: 1000,
      bankBalance: 60000,
      currentGoal: NpcGoal(
        type: NpcGoalType.upgradeEquipment,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {'targetSectorId': 2},
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    // Withdraw conditions met, but the upgrade trip survives and advances.
    expect(npc.currentGoal?.type, NpcGoalType.upgradeEquipment);
    expect(npc.currentSectorId, 2);
  });

  test('completed sale and deposit stamp memory timestamps', () {
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Buyer',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
          supply: {},
          demand: {'minerals': 5000},
          maxSupply: {},
          maxDemand: {'minerals': 5000},
          portCredits: 1000000,
          desiredCredits: 1000000,
        ),
      ),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 5000,
      seed: 74,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      cargo: const {'minerals': 10},
      cargoUsed: 10,
      currentGoal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 1,
          'buyPortId': 1,
          'sellPortId': 1,
          'commodity': 'minerals',
          'phase': 'travel_to_sell',
        },
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.memory.lastTradeTime, isNotNull);
  });

  test('owner surcharge cannot push a purchase negative (live Sarek bug)', () {
    // Owned port: 5% fee on top. Bankroll sized so cost alone fits but
    // cost + fee does not — pre-fix this went negative and tripped the
    // credits assert every tick, aborting the whole tick.
    final sectors = [
      Sector(
        id: 1,
        name: 'A',
        x: 0,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: const Port(
          name: 'Owned',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 100.0},
          supply: {'minerals': 5000},
          demand: {},
          maxSupply: {'minerals': 5000},
          maxDemand: {},
          portCredits: 1000000,
          desiredCredits: 1000000,
          owner: 'Some Owner',
        ),
      ),
    ];
    var npc = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 10000,
      seed: 75,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      credits: 10050,
      currentGoal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 1,
          'buyPortId': 1,
          'sellPortId': 1,
          'commodity': 'minerals',
          'phase': 'travel_to_buy',
        },
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.credits, greaterThanOrEqualTo(0));
  });
}
