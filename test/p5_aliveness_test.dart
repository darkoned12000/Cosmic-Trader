import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// P5 aliveness: co-located barter, directional flee, limp-home
// repairs, loss-triggered distress, combat taunts.
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

List<Sector> _sectors() => [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11, 14]),
      Sector(id: 14, name: 'D', x: 2, y: 0, warpRoutes: const [12]),
    ];

void main() {
  setUp(() {
    NpcAiService.clearSignalsForTest();
    EconomyMetrics.resetForTest();
    GameEventLog.resetForTest();
  });
  tearDown(() {
    NpcAiService.clearSignalsForTest();
    EconomyMetrics.resetForTest();
    GameEventLog.resetForTest();
  });

  group('co-located barter', () {
    test('holds meet holds at mid-price, both sides recorded', () {
      final sectors = _sectors();
      var seller = _npc(FactionClass.trader, 11, 1101, credits: 5000)
          .copyWith(cargo: const {'minerals': 10}, cargoUsed: 10);
      final cap = seller.cargoHoldCapacity;
      var buyer = _npc(FactionClass.trader, 11, 1102, credits: 5000);
      // Buyer room: other-cargo holds leave exactly 5 open, and no
      // minerals aboard (bulk holders never bulk up — soak fix).
      buyer = buyer.copyWith(cargo: {'food': cap - 5}, cargoUsed: cap - 5);

      final roster = [seller, buyer];
      seller = NpcAiService.processTurn(seller, sectors, [], roster);

      // minerals split-point (10+75)/2 = 42.5 → 43 per unit;
      // 5 units move into the 5 open holds.
      final moved = roster[1].cargo['minerals'] ?? 0;
      expect(moved, 5);
      expect(roster[1].credits, lessThan(5000));
      expect(roster[0].credits, greaterThan(5000));
      expect(roster[0].cargoUsed, 10 - moved);
      final lines = GameEventLog.global
          .query(query: 'Bartered')
          .map((e) => e.message)
          .toList();
      expect(lines, hasLength(1));
      expect(lines[0], contains('minerals'));
    });

    test('bulk holders never bulk up (churn governor)', () {
      final sectors = _sectors();
      var seller = _npc(FactionClass.trader, 11, 1106, credits: 5000)
          .copyWith(cargo: const {'minerals': 10}, cargoUsed: 10);
      final cap = seller.cargoHoldCapacity;
      // Buyer sits on a bulk pile of the same good with room to spare.
      final buyer = _npc(FactionClass.trader, 11, 1107, credits: 5000)
          .copyWith(cargo: {'minerals': cap - 5}, cargoUsed: cap - 5);

      final roster = [seller, buyer];
      seller = NpcAiService.processTurn(seller, sectors, [], roster);
      expect(roster[0].cargo['minerals'], 10);
      expect(roster[1].cargo['minerals'], cap - 5);
      expect(GameEventLog.global.query(query: 'Bartered').map((e) => e.message),
          isEmpty);
    });

    test('one barter per cooldown window', () {
      final sectors = _sectors();
      var seller = _npc(FactionClass.trader, 11, 1108, credits: 5000).copyWith(
          cargo: const {'minerals': 10},
          cargoUsed: 10,
          memory: const NpcMemory().copyWith(lastTradeTime: DateTime.now()));
      final buyer = _npc(FactionClass.trader, 11, 1109, credits: 5000);

      final roster = [seller, buyer];
      seller = NpcAiService.processTurn(seller, sectors, [], roster);
      expect(roster[0].cargo['minerals'], 10);
      expect(GameEventLog.global.query(query: 'Bartered').map((e) => e.message),
          isEmpty);
    });

    test('hostiles do not trade', () {
      final sectors = _sectors();
      var seller = _npc(FactionClass.trader, 11, 1111, credits: 5000)
          .copyWith(cargo: const {'minerals': 10}, cargoUsed: 10);
      final buyer = _npc(FactionClass.pirate, 11, 1112, credits: 5000);

      final roster = [seller, buyer];
      seller = NpcAiService.processTurn(seller, sectors, [], roster);
      expect(roster[0].cargo['minerals'], 10);
      expect(roster[1].cargo['minerals'] ?? 0, 0);
      expect(GameEventLog.global.query(query: 'Bartered').map((e) => e.message),
          isEmpty);
    });

    test('broke buyers window-shop only', () {
      final sectors = _sectors();
      var seller = _npc(FactionClass.trader, 11, 1121, credits: 0)
          .copyWith(cargo: const {'minerals': 10}, cargoUsed: 10);
      final buyer = _npc(FactionClass.trader, 11, 1122, credits: 0);

      final roster = [seller, buyer];
      seller = NpcAiService.processTurn(seller, sectors, [], roster);
      expect(roster[0].cargo['minerals'], 10);
    });
  });

  group('directional flee', () {
    test('flees from where the threat is going, not standing', () {
      // 11—12—14 line: threat in 12 heading to 14. Fleeing to 11 puts
      // 2 hops between; fleeing to 14 walks into its guns.
      final sectors = _sectors();
      final threat = _npc(FactionClass.pirate, 12, 1131,
          weapons: const {'main_forward': 9}).copyWith(
        currentGoal: NpcGoal(
            type: NpcGoalType.attack,
            status: NpcGoalStatus.travelling,
            createdAt: DateTime.now(),
            params: const {'targetSectorId': 14, 'targetId': 'prey'}),
      );
      var holder = _npc(FactionClass.trader, 12, 1132);

      final roster = [holder, threat];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      expect(holder.currentGoal?.type, NpcGoalType.flee);
      expect(holder.currentGoal?.targetSectorId, 11);
      expect(holder.currentSectorId, 11);
    });
  });

  group('limp-home repairs', () {
    List<Sector> yardSectors() => [
          Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
          Sector(
            id: 12,
            name: 'B',
            x: 1,
            y: 0,
            warpRoutes: const [11, 14],
            hasPort: true,
            port: const Port(
              name: 'Yards',
              portClass: PortClass.hardwareEmporium,
              buyPrices: {},
              sellPrices: {},
            ),
          ),
          Sector(id: 14, name: 'D', x: 2, y: 0, warpRoutes: const [12]),
        ];

    NpcMemory chartedMemory() => const NpcMemory().copyWith(
          visitedSectors: {11, 12, 14},
          discoveredPorts: {
            12: PortInfo(
              name: 'Yards',
              portClass: PortClass.hardwareEmporium,
              buyPrices: {},
              sellPrices: {},
            ),
          },
        );

    test('battered hulls with repair money seek the yards', () {
      final sectors = yardSectors();
      NpcShip hurt() => _npc(FactionClass.vinari, 11, 1141,
              personality: NpcPersonality.vinariProtector, credits: 20000)
          .copyWith(hull: 40, maxHull: 100, memory: chartedMemory());
      NpcShip? upgraded;
      for (var i = 0; i < 40 && upgraded == null; i++) {
        var cand = hurt();
        cand = NpcAiService.processTurn(cand, sectors, [], [cand]);
        if (cand.currentGoal?.type == NpcGoalType.upgradeEquipment) {
          upgraded = cand;
        }
      }
      expect(upgraded, isNotNull,
          reason: 'hurt pilot never sought repairs in 40 draws');
    });

    test('healthy hulls below the wealth gate do not', () {
      final sectors = yardSectors();
      var npc = _npc(FactionClass.vinari, 11, 1142,
              personality: NpcPersonality.vinariProtector, credits: 20000)
          .copyWith(memory: chartedMemory());
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(npc.currentGoal?.type, isNot(NpcGoalType.upgradeEquipment));
    });
  });

  group('loss-triggered distress', () {
    test('bleeding defenders call for help at even odds', () {
      final sectors = _sectors();
      var attacker = _npc(FactionClass.pirate, 11, 1151);
      var defender = _npc(FactionClass.trader, 11, 1152,
              weapons: const {'main_forward': 3})
          .copyWith(hull: 30, maxHull: 100, shields: 100, maxShields: 100);
      var responder = _npc(FactionClass.trader, 12, 1153,
          personality: NpcPersonality.traderExplorer);
      attacker = attacker.copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': defender.id},
        ),
      );
      final roster = [attacker, defender, responder];
      roster[0] = NpcAiService.processTurn(roster[0], sectors, [], roster);
      // Equal guns: the old 2× rule stays silent; the bleeding hull
      // calls it in.
      roster[2] = NpcAiService.processTurn(roster[2], sectors, [], roster);
      expect(roster[2].currentGoal?.type, NpcGoalType.attack);
      expect(roster[2].currentGoal?.params['distressFor'], defender.id);
    });
  });

  group('combat taunts', () {
    test('hot blood talks, cool heads stay silent', () {
      String fightWith(NpcPersonality aggression) {
        GameEventLog.global.clear();
        var attacker =
            _npc(FactionClass.pirate, 11, 1161, personality: aggression);
        var defender = _npc(FactionClass.trader, 11, 1162, hull: 5000);
        attacker = attacker.copyWith(
          currentGoal: NpcGoal(
            type: NpcGoalType.attack,
            status: NpcGoalStatus.travelling,
            createdAt: DateTime.now(),
            params: {'targetSectorId': 11, 'targetId': defender.id},
          ),
        );
        final roster = [attacker, defender];
        NpcAiService.processTurn(roster[0], _sectors(), [], roster);
        return GameEventLog.global
            .query(query: 'snarls')
            .map((e) => e.message)
            .join('\n');
      }

      expect(fightWith(NpcPersonality.pirateHunter), contains('snarls'));
      // traderSmuggler aggression is low: no taunt line.
      expect(fightWith(NpcPersonality.traderSmuggler), isEmpty);
    });
  });
}
