import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// Review batch 3: deadlock regressions, trade-gate corrections,
// memory caps, and model hardening.
Sector _plain(int id, [List<int> warps = const []]) => Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: warps,
    );

NpcShip _npc(
  FactionClass faction,
  int sector,
  int seed, {
  NpcPersonality? personality,
  Map<String, int>? weapons,
  int credits = 0,
  int hull = 100,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: credits,
    seed: seed,
  ).copyWith(
    personality: personality ??
        (faction == FactionClass.pirate
            ? NpcPersonality.pirateHunter
            : NpcPersonality.traderMerchant),
    hull: hull,
    maxHull: hull,
    energy: 1000,
    weaponSlots: weapons ?? {'main_forward': 3},
  );
}

NpcGoal _travelTrade({
  required int buy,
  required int sell,
  required String phase,
  String? convoyLeader,
}) =>
    NpcGoal(
      type: NpcGoalType.tradeRoute,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': phase == 'travel_to_sell' ? sell : buy,
        'buyPortId': buy,
        'sellPortId': sell,
        'commodity': 'minerals',
        'phase': phase,
        if (convoyLeader != null) 'convoyLeader': convoyLeader,
      },
    );

void main() {
  setUp(() {
    NpcAiService.clearSignalsForTest();
    BountyBoard.resetForTest();
  });
  tearDown(() {
    NpcAiService.clearSignalsForTest();
    BountyBoard.resetForTest();
  });

  group('P0 solar array retract', () {
    test('charged array furled and ship moves', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 910).copyWith(
        solarArrayLevel: 1,
        solarArrayDeployed: true,
        currentGoal: NpcGoal(
          type: NpcGoalType.patrol,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {'targetSectorId': 12},
        ),
      );
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(npc.solarArrayDeployed, isFalse);
      expect(npc.currentSectorId, 12);
    });

    test('stranded array deploys, trickles, then flies', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.vinari, 11, 911).copyWith(
        personality: NpcPersonality.vinariExplorer,
        solarArrayLevel: 1,
        energy: 0,
        currentGoal: NpcGoal(
          type: NpcGoalType.patrol,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {'targetSectorId': 12},
        ),
      );
      var moved = false;
      for (var i = 0; i < 40 && !moved; i++) {
        npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
        moved = npc.currentSectorId != 11;
      }
      expect(moved, isTrue, reason: 'array never recovered');
      expect(npc.solarArrayDeployed, isFalse);
    });
  });

  group('P0 convoy sell-phase join', () {
    test('escorts aim at the sell port and never strand', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11, 13]),
        _plain(13, [12]),
      ];
      final leader = _npc(FactionClass.trader, 12, 921, credits: 5000).copyWith(
          currentGoal: _travelTrade(
        buy: 12,
        sell: 13,
        phase: 'travel_to_sell',
      ));
      var escort = _npc(FactionClass.trader, 11, 922, credits: 5000);

      var roster = [leader, escort];
      escort = NpcAiService.processTurn(escort, sectors, [], roster);
      // Joined toward the SELL port, not the buy port.
      expect(escort.currentGoal?.params['convoyLeader'], leader.id);
      expect(escort.currentGoal?.params['targetSectorId'], 13);

      // Run to arrival: the escort reaches 13 and the leg resolves
      // (fail-fast on empty holds) instead of sitting at 12 forever.
      for (var i = 0; i < 3; i++) {
        roster = [leader, escort];
        escort = NpcAiService.processTurn(escort, sectors, [], roster);
      }
      expect(escort.currentSectorId, 13);
      final goal = escort.currentGoal;
      final stuck = goal != null &&
          goal.type == NpcGoalType.tradeRoute &&
          goal.status == NpcGoalStatus.travelling &&
          goal.targetSectorId == 12;
      expect(stuck, isFalse);
    });
  });

  group('P1 broke-with-cargo trades', () {
    Map<int, PortInfo> ports() => {
          12: const PortInfo(
            name: 'Buyer',
            portClass: PortClass.free,
            buyPrices: {'minerals': 100.0},
            sellPrices: {},
          ),
          13: const PortInfo(
            name: 'Other',
            portClass: PortClass.free,
            buyPrices: {},
            sellPrices: {'minerals': 10.0},
          ),
        };

    test('broke carrier goes sell-first', () {
      final sectors = [
        _plain(11, [12, 13]),
        _plain(12, [11]),
        _plain(13, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 931, credits: 0);
      final cap = npc.cargoHoldCapacity;
      // Half-full holds with room: old gate said "no trade".
      npc = npc.copyWith(
        cargo: {'minerals': cap ~/ 2},
        cargoUsed: cap ~/ 2,
        memory: npc.memory.copyWith(
          discoveredPorts: ports(),
          visitedSectors: {11, 12, 13},
        ),
      );
      // Force selection deterministically: run until a trade goal lands
      // (patrol may win some lotteries).
      NpcGoal? trade;
      for (var i = 0; i < 20 && trade == null; i++) {
        var cand = npc.copyWith(clearGoal: true);
        cand = NpcAiService.processTurn(cand, sectors, [], [cand]);
        if (cand.currentGoal?.type == NpcGoalType.tradeRoute) {
          npc = cand;
          trade = cand.currentGoal;
        }
      }
      expect(trade, isNotNull);
      final won = trade!;
      expect(won.params['phase'], 'travel_to_sell');
      expect(won.buyPortId, won.sellPortId);
    });
  });

  group('P1 owned-port revenue', () {
    Port ownedPort(String name, int defense) => Port(
          name: name,
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 10.0},
          supply: const {'minerals': 100},
          demand: const {},
          maxSupply: const {'minerals': 100},
          maxDemand: const {},
          portCredits: 1000000,
          desiredCredits: 1000000,
          defenseLevel: defense,
          storageLevel: 10,
          accumulatedRevenue: 5000,
        );

    test('upgrade on port one does not eat port two revenue', () {
      var owner = _npc(FactionClass.trader, 11, 941, credits: 10000000);
      final sectors = [
        Sector(
            id: 11,
            name: 'A',
            x: 0,
            y: 0,
            warpRoutes: const [12],
            hasPort: true,
            port: ownedPort('P1', 0)),
        Sector(
            id: 12,
            name: 'B',
            x: 1,
            y: 0,
            warpRoutes: const [11],
            hasPort: true,
            port: ownedPort('P2', 4)),
      ];
      sectors[0].port =
          sectors[0].port!.copyWith(owner: owner.pilotName, ownerId: owner.id);
      sectors[1].port =
          sectors[1].port!.copyWith(owner: owner.pilotName, ownerId: owner.id);

      owner = NpcAiService.processTurn(owner, sectors, [], [owner]);
      // P1 upgraded AND P2 still collected (old code broke after P1).
      expect(sectors[0].port!.defenseLevel, 1);
      expect(sectors[1].port!.accumulatedRevenue, 0);
    });
  });

  group('P1 trade service guards', () {
    Sector wreckedBuyer() => Sector(
          id: 11,
          name: 'A',
          x: 0,
          y: 0,
          warpRoutes: const [12],
          hasPort: true,
          port: const Port(
            name: 'Wreck',
            portClass: PortClass.free,
            buyPrices: {'minerals': 100.0},
            sellPrices: {},
            supply: {},
            demand: {'minerals': 100},
            maxSupply: {},
            maxDemand: {'minerals': 100},
            portCredits: 1000000,
            desiredCredits: 1000000,
            isDestroyed: true,
          ),
        );

    test('wrecked ports do not trade', () {
      final sectors = [
        wreckedBuyer(),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 951, credits: 5000).copyWith(
        cargo: const {'minerals': 10},
        cargoUsed: 10,
        memory: NpcMemory.empty().copyWith(
          discoveredPorts: {
            11: const PortInfo(
              name: 'Wreck',
              portClass: PortClass.free,
              buyPrices: {'minerals': 100.0},
              sellPrices: {},
            ),
            12: const PortInfo(
              name: 'Other',
              portClass: PortClass.free,
              buyPrices: {},
              sellPrices: {},
            ),
          },
          visitedSectors: {11, 12},
        ),
        currentGoal: _travelTrade(
          buy: 12,
          sell: 11,
          phase: 'travel_to_sell',
        ),
      );
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      // Failed, not transacted: cargo intact, credits untouched.
      expect(npc.cargo['minerals'], 10);
      expect(npc.credits, 5000);
      expect(npc.currentGoal?.type, isNot(NpcGoalType.tradeRoute));
    });

    test('refusing ports do not trade', () {
      final sectors = [
        Sector(
          id: 11,
          name: 'A',
          x: 0,
          y: 0,
          warpRoutes: const [12],
          hasPort: true,
          port: const Port(
            name: 'Snub',
            portClass: PortClass.free,
            buyPrices: {'minerals': 100.0},
            sellPrices: {},
            supply: {},
            demand: {'minerals': 100},
            maxSupply: {},
            maxDemand: {'minerals': 100},
            portCredits: 1000000,
            desiredCredits: 1000000,
            ownerFaction: FactionClass.pirate,
          ),
        ),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 952, credits: 5000).copyWith(
        cargo: const {'minerals': 10},
        cargoUsed: 10,
        memory: NpcMemory.empty().copyWith(
          discoveredPorts: {
            11: const PortInfo(
              name: 'Snub',
              portClass: PortClass.free,
              buyPrices: {'minerals': 100.0},
              sellPrices: {},
              ownerFaction: FactionClass.pirate,
            ),
            12: const PortInfo(
              name: 'Other',
              portClass: PortClass.free,
              buyPrices: {},
              sellPrices: {},
            ),
          },
          visitedSectors: {11, 12},
          factionStandings: const {'pirate': -100},
        ),
        currentGoal: _travelTrade(
          buy: 12,
          sell: 11,
          phase: 'travel_to_sell',
        ),
      );
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(npc.cargo['minerals'], 10);
      expect(npc.credits, 5000);
      expect(npc.currentGoal?.type, isNot(NpcGoalType.tradeRoute));
    });

    // Both tests above drive the SELL leg only — a goal in travel_to_sell
    // arriving at the offending port. The buy leg was unguarded, and
    // deleting `deniesServiceTo(buyStanding)` from the buy phase passed
    // this whole file. A port that refuses service has to refuse *both*
    // sides: an NPC that cannot sell to pirates must equally not buy from
    // them, and the standing rule is the only thing enforcing that.
    Sector seller(int id, {bool destroyed = false, bool pirate = true}) {
      return Sector(
        id: id,
        name: 'S$id',
        x: 0,
        y: 0,
        warpRoutes: const [12],
        hasPort: true,
        port: Port(
          name: 'Shop',
          portClass: PortClass.free,
          buyPrices: const {},
          sellPrices: const {'minerals': 10.0},
          supply: const {'minerals': 500},
          demand: const {},
          maxSupply: const {'minerals': 500},
          maxDemand: const {},
          portCredits: 1000000,
          desiredCredits: 1000000,
          ownerFaction: pirate ? FactionClass.pirate : null,
          isDestroyed: destroyed,
        ),
      );
    }

    NpcShip buyer() =>
        _npc(FactionClass.trader, 11, 953, credits: 5000).copyWith(
          memory: const NpcMemory().copyWith(
            factionStandings: {'pirate': -100},
            visitedSectors: {11, 12},
          ),
          currentGoal: _travelTrade(
            buy: 11,
            sell: 12,
            phase: 'travel_to_buy',
          ),
        );

    test('a refusing port does not sell to the NPC either', () {
      // One sector instance, used by the turn. An earlier version built the
      // sector twice — passing `destroyed: true` to a throwaway copy while
      // `processTurn` was handed a fresh, live one — so the test asserted
      // nothing about destruction and deleting the guard changed nothing.
      final shop = seller(11);
      final npc = buyer();
      final after = NpcAiService.processTurn(npc, [
        shop,
        _plain(12, [11])
      ], [], [
        npc
      ]);

      // The transaction is the evidence, not the goal. A refused leg fails
      // and clears, and step 5 then legitimately picks a fresh goal, so
      // asserting on `currentGoal` measures selection rather than the guard.
      expect(after.credits, 5000, reason: 'no credits left the wallet');
      expect(after.cargo['minerals'] ?? 0, 0, reason: 'nothing was loaded');
      expect(after.memory.failedRoutes.keys, isNotEmpty,
          reason: 'the refusal is recorded so the route cools instead of '
              'being re-picked every tick');
    });

    test('a wrecked port does not sell to the NPC either', () {
      final shop = seller(11, pirate: false, destroyed: true);
      expect(shop.port!.isDestroyed, isTrue,
          reason: 'the fixture must actually be the thing under test');
      final npc = buyer();
      final after = NpcAiService.processTurn(npc, [
        shop,
        _plain(12, [11])
      ], [], [
        npc
      ]);

      expect(after.credits, 5000);
      expect(after.cargo['minerals'] ?? 0, 0);
      expect(after.memory.failedRoutes.keys, isNotEmpty);
    });
  });

  group('P1 scan no-ops and threat prune', () {
    test('repeat scans return identical memory', () {
      const memory = NpcMemory();
      final m1 = memory.withVisitedSector(11);
      expect(identical(m1.withVisitedSector(11), m1), isTrue);
      expect(identical(m1.withThreat('x').withThreat('x'), m1.withThreat('x')),
          isFalse);
      final threatened = m1.withThreat('x');
      expect(identical(threatened.withThreat('x'), threatened), isTrue);
      const port = PortInfo(
        name: 'P',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {},
      );
      final withPort = m1.withDiscoveredPort(11, port);
      expect(
          identical(
              withPort.withDiscoveredPort(
                  11,
                  const PortInfo(
                    name: 'P',
                    portClass: PortClass.free,
                    buyPrices: {},
                    sellPrices: {},
                  )),
              withPort),
          isTrue);
      // Changed snapshot still writes.
      expect(
          identical(
              withPort.withDiscoveredPort(
                  11,
                  const PortInfo(
                    name: 'Q',
                    portClass: PortClass.free,
                    buyPrices: {},
                    sellPrices: {},
                  )),
              withPort),
          isFalse);
    });

    test('dead threats prune on scan', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 961);
      npc = npc.copyWith(
        memory: npc.memory.withThreat('gone-pilot'),
      );
      // 'gone-pilot' is in nobody's roster: pruned, not kept.
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(npc.memory.knownThreatIds, isNot(contains('gone-pilot')));
    });
  });

  group('P1 death before gossip, dead-attacker bounty', () {
    test('corpses share no sightings and earn no bounties', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final now = DateTime.now().millisecondsSinceEpoch;
      // A: frail attacker holding a grudge, co-located mate C.
      var a = _npc(FactionClass.trader, 11, 971,
          weapons: const {'main_forward': 1}, hull: 1, credits: 0);
      a = a.copyWith(
        shields: 0,
        maxShields: 0,
        memory: a.memory.withVendetta(
          targetId: 'far-killer',
          sectorId: 5,
          grievanceBump: 60,
          nowMs: now - 1000,
        ),
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {'targetSectorId': 11},
        ),
      );
      // B: strong defender (kills A), rich enough to post bounties.
      var b = _npc(FactionClass.pirate, 11, 972,
          weapons: const {'main_forward': 9}, hull: 5000, credits: 20000);
      final c = _npc(FactionClass.trader, 11, 973, credits: 0);

      final roster = [a, b, c];
      // Wire A's goal at B now that ids exist.
      roster[0] = a.copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': b.id},
        ),
      );
      // X keeps A's grudge off the prune (living, far away).
      final x = _npc(FactionClass.pirate, 12, 974, credits: 0);
      roster.add(x);
      a = NpcAiService.processTurn(roster[0], sectors, [], roster);

      expect(a.isDestroyed, isTrue);
      // Mate learned nothing from the corpse...
      expect(roster[2].memory.vendettas.containsKey('far-killer'), isFalse);
      // ...and no bounty was posted on it.
      expect(BountyBoard.global.totalFor(a.id), 0);
    });
  });

  group('P1 sell-only route keys', () {
    test('sell-only failures cool; completions teach nothing', () {
      final sectors = [
        Sector(
          id: 11,
          name: 'A',
          x: 0,
          y: 0,
          warpRoutes: const [12],
          hasPort: true,
          port: const Port(
            name: 'NoBuyer',
            portClass: PortClass.free,
            buyPrices: {},
            sellPrices: {'minerals': 10.0},
            supply: {'minerals': 100},
            demand: {},
            maxSupply: {'minerals': 100},
            maxDemand: {},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        ),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 981, credits: 0).copyWith(
        cargo: const {'minerals': 10},
        cargoUsed: 10,
        memory: NpcMemory.empty().copyWith(
          discoveredPorts: {
            11: const PortInfo(
              name: 'NoBuyer',
              portClass: PortClass.free,
              buyPrices: {},
              sellPrices: {'minerals': 10.0},
            ),
            12: const PortInfo(
              name: 'Other',
              portClass: PortClass.free,
              buyPrices: {},
              sellPrices: {},
            ),
          },
          visitedSectors: {11, 12},
        ),
        currentGoal: _travelTrade(
          buy: 11,
          sell: 11,
          phase: 'travel_to_sell',
        ),
      );
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      // 'no longer buys' fail under the sell> namespace (never N>N).
      expect(npc.memory.failedRoutes.keys, ['sell>11:minerals']);
      expect(npc.memory.profitableRoutes, isEmpty);
    });

    // The test above is a FAILURE path, so on its own it cannot see the
    // learning half: the run dies at "no longer buys" and the learning
    // code is never reached, leaving `profitableRoutes` empty whether or
    // not sell-only runs are excluded from it — deleting the
    // `buyPortId != sellPortId` guard passed the whole file. This port
    // actually BUYS, so the leg completes with profit > 0 and the only
    // thing between it and a recorded "11>11:minerals" win is the guard.
    test('a completing sell-only run still teaches nothing', () {
      final sectors = [
        Sector(
          id: 11,
          name: 'Buyer',
          x: 0,
          y: 0,
          warpRoutes: const [12],
          hasPort: true,
          port: const Port(
            name: 'Buyer',
            portClass: PortClass.free,
            buyPrices: {'minerals': 100.0},
            sellPrices: {},
            supply: {},
            demand: {'minerals': 50},
            maxSupply: {},
            maxDemand: {'minerals': 50},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        ),
        _plain(12, [11]),
      ];
      var npc = _npc(FactionClass.trader, 11, 982, credits: 0).copyWith(
        cargo: const {'minerals': 10},
        cargoUsed: 10,
        currentGoal: _travelTrade(
          buy: 11,
          sell: 11,
          phase: 'travel_to_sell',
        ),
      );
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);

      // The leg really did complete, and really was profitable —
      // otherwise the assertions below are asserting nothing. The goal
      // itself is NOT evidence: step 5 legitimately replaces a completed
      // goal with a freshly selected one, so the durable proof is the
      // transaction — credits paid out, holds emptied, demand consumed.
      expect(npc.credits, greaterThan(0), reason: 'port paid the seller');
      expect(npc.cargo['minerals'], isNull, reason: 'holds emptied');
      expect(sectors.first.port!.demand['minerals'], 40,
          reason: 'port demand decremented by the 10 units sold');

      // A sell-only self-loop is a key shape TradeEvaluator can never
      // produce, so remembering it is pure noise in the route book.
      expect(npc.memory.profitableRoutes, isEmpty);
      expect(
          npc.memory.profitableRoutes.containsKey('11>11:minerals'), isFalse);
    });
  });

  group('P1 PortInfo overrides', () {
    test('snapshots price owner overrides outright', () {
      const info = PortInfo(
        name: 'P',
        portClass: PortClass.free,
        buyPrices: {'minerals': 100.0},
        sellPrices: {'minerals': 10.0},
        pricingOverride: {'minerals': 2.0},
      );
      expect(info.getEffectiveBuyPrice('minerals'), 200.0);
      expect(info.getEffectiveSellPrice('minerals'), 20.0);
      final restored = PortInfo.fromJson(info.toJson().cast<String, dynamic>());
      expect(restored.pricingOverride, {'minerals': 2.0});
      expect(restored, info);
    });
  });

  group('P3 caps and hardening', () {
    test('port book caps at maxDiscoveredPorts', () {
      var memory = const NpcMemory();
      for (var i = 0; i < NpcMemory.maxDiscoveredPorts + 5; i++) {
        memory = memory.withDiscoveredPort(
          i,
          PortInfo(
            name: 'P$i',
            portClass: PortClass.free,
            buyPrices: const {},
            sellPrices: const {},
          ),
        );
      }
      expect(memory.discoveredPorts.length, NpcMemory.maxDiscoveredPorts);
      // Newest survives; stalest evicted.
      expect(
          memory.discoveredPorts.containsKey(NpcMemory.maxDiscoveredPorts + 4),
          isTrue);
      expect(memory.discoveredPorts.containsKey(0), isFalse);
    });

    test('failed routes prune expired on write and cap', () {
      const now = 1000000;
      var memory = const NpcMemory().withFailedRoute('old', nowMs: 0);
      memory = memory.withFailedRoute('fresh', nowMs: now);
      expect(memory.failedRoutes.containsKey('old'), isFalse);
      expect(memory.isRouteCooling('fresh', nowMs: now), isTrue);
      for (var i = 0; i < NpcMemory.maxFailedRoutes + 5; i++) {
        memory = memory.withFailedRoute('k$i', nowMs: now + i);
      }
      expect(memory.failedRoutes.length, NpcMemory.maxFailedRoutes);
    });

    test('profitable route keys cap', () {
      var memory = const NpcMemory();
      for (var i = 0; i < NpcMemory.maxProfitableRoutes + 5; i++) {
        memory = memory.withProfitableRoute('1>$i:minerals');
      }
      expect(memory.profitableRoutes.length, NpcMemory.maxProfitableRoutes);
    });

    test('bounty board caps active marks (cheapest evicted)', () {
      for (var i = 0; i < BountyBoard.maxActiveBounties + 5; i++) {
        BountyBoard.global.post(
          targetId: 't$i',
          targetName: 'T$i',
          targetFaction: 'pirate',
          amount: 100,
          posterId: 'tester$i',
          posterName: 'Tester$i',
          reason: 'cap',
        );
      }
      expect(BountyBoard.global.active.length, BountyBoard.maxActiveBounties);
    });

    test('malformed goals degrade instead of throwing', () {
      final goal = NpcGoal.fromJson({
        'type': 'nope',
        'status': 'nope',
        'createdAt': 'garbage',
        'params': 'nope',
      });
      expect(goal.type, NpcGoalType.explore);
      expect(goal.status, NpcGoalStatus.planning);
      expect(goal.params, isEmpty);
    });
  });
}
