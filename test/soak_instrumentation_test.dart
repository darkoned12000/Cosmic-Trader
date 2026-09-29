import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';

// Soak instrumentation: drift milestones, first-win route lines,
// backup-yard launch tags. Log assertions use unique pilot/sector
// markers with a cleared ring per test.
NpcShip _npc(
  FactionClass faction,
  int sector,
  int seed, {
  NpcPersonality? personality,
  Map<String, int>? weapons,
  int hull = 100,
  int credits = 0,
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

List<Sector> _arena() => [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
    ];

Sector _yard({
  required int id,
  required FactionClass faction,
  bool backup = false,
}) =>
    Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: const [],
      planet: Planet(
        name: backup ? 'HW$id (Reserve)' : 'HW$id',
        planetType: 'Terran',
        owner: faction,
        isHomeworld: true,
        homeworldOf: faction,
        isBackupHomeworld: backup,
        productionTimer: 1,
        spawnInterval: 10,
      ),
    );

void main() {
  setUp(() {
    GameEventLog.global.clear();
    NpcAiService.clearSignalsForTest();
  });
  tearDown(() {
    GameEventLog.global.clear();
    NpcAiService.clearSignalsForTest();
  });

  group('drift milestones', () {
    test('tierCrossed fires per 0.05 tier only', () {
      expect(NpcShip.driftTierCrossed(0.0, 0.02), isFalse);
      expect(NpcShip.driftTierCrossed(0.04, 0.06), isTrue);
      expect(NpcShip.driftTierCrossed(0.05, 0.05), isFalse);
      expect(NpcShip.driftTierCrossed(0.14, 0.15), isTrue);
      expect(NpcShip.driftTierCrossed(0.06, 0.04), isFalse);
    });

    test('killer milestone logs on tier cross, silent otherwise', () {
      NpcShip strike(double preset) {
        var killer = _npc(FactionClass.pirate, 11, 1001).copyWith(
          driftAggression: preset,
        );
        var victim = _npc(FactionClass.trader, 11, 1002,
            weapons: const {'main_forward': 1}, hull: 1);
        victim = victim.copyWith(shields: 0, maxShields: 0);
        final out = [killer, victim];
        out[0] = out[0].copyWith(
          currentGoal: NpcGoal(
            type: NpcGoalType.attack,
            status: NpcGoalStatus.travelling,
            createdAt: DateTime.now(),
            params: {'targetSectorId': 11, 'targetId': victim.id},
          ),
        );
        return NpcAiService.processTurn(out[0], _arena(), [], out);
      }

      strike(0.0);
      expect(
          GameEventLog.global
              .query(query: 'Veteran bolder')
              .map((e) => e.message),
          isEmpty);

      strike(0.04);
      final lines = GameEventLog.global
          .query(query: 'Veteran bolder')
          .map((e) => e.message)
          .toList();
      expect(lines, hasLength(1));
      expect(lines[0], contains('0.06'));
    });

    test('survivor milestone logs on tier cross', () {
      var killer = _npc(FactionClass.pirate, 11, 1011);
      var survivor = _npc(FactionClass.trader, 11, 1012,
          weapons: const {'main_forward': 1}, hull: 5000);
      survivor = survivor.copyWith(driftCaution: 0.04);
      killer = killer.copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': survivor.id},
        ),
      );
      final roster = [killer, survivor];
      NpcAiService.processTurn(roster[0], _arena(), [], roster);

      final lines = GameEventLog.global
          .query(query: 'Veteran warier')
          .map((e) => e.message)
          .toList();
      expect(lines, hasLength(1));
      expect(roster[1].driftCaution, closeTo(0.06, 1e-9));
    });
  });

  group('first-win route lines', () {
    Sector market() => Sector(
          id: 11,
          name: 'A',
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
            demand: {'minerals': 100},
            maxSupply: {},
            maxDemand: {'minerals': 100},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        );

    NpcShip seller({required Map<String, int> wins}) {
      return _npc(FactionClass.trader, 11, 1021).copyWith(
        cargo: const {'minerals': 10},
        cargoUsed: 10,
        memory: NpcShip.create(
          faction: FactionClass.trader,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: 11,
          startingCredits: 0,
          seed: 1,
        ).memory.copyWith(profitableRoutes: wins),
        currentGoal: NpcGoal(
          type: NpcGoalType.tradeRoute,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {
            'targetSectorId': 11,
            'buyPortId': 12,
            'sellPortId': 11,
            'commodity': 'minerals',
            'buyPrice': 5.0,
            'phase': 'travel_to_sell',
          },
        ),
      );
    }

    test('first win logs once; repeats stay quiet', () {
      final sectors = [
        market(),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
      ];
      var npc = seller(wins: {});
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(npc.memory.profitableRoutes['12>11:minerals'], 1);
      expect(
          GameEventLog.global
              .query(query: 'Learned profitable route')
              .map((e) => e.message),
          hasLength(1));

      // Same route again: taught already, no second line.
      GameEventLog.global.clear();
      npc = seller(wins: const {'12>11:minerals': 1});
      npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
      expect(
          GameEventLog.global
              .query(query: 'Learned profitable route')
              .map((e) => e.message),
          isEmpty);
    });
  });

  group('backup-yard launch tags', () {
    test('backup launches are tagged, primaries are not', () {
      final primary = _yard(id: 11, faction: FactionClass.trader);
      primary.primaryPlanet!.owner = FactionClass.duran;
      final sectors = [
        primary,
        _yard(id: 12, faction: FactionClass.trader, backup: true),
      ];
      final built = RepopulationService.produce(sectors, []);
      expect(built, hasLength(1));
      expect(built[0].currentSectorId, 12);
      final lines = GameEventLog.global
          .query(query: 'backup yards')
          .map((e) => e.message)
          .toList();
      expect(lines, hasLength(1));
      expect(lines[0], contains('sector #12'));

      // Primary live again: untagged launch from 11.
      GameEventLog.global.clear();
      primary.primaryPlanet!.owner = FactionClass.trader;
      primary.primaryPlanet!.productionTimer = 1;
      final rebuilt = RepopulationService.produce(sectors, built);
      expect(rebuilt.map((n) => n.currentSectorId), [11]);
      expect(
          GameEventLog.global
              .query(query: 'backup yards')
              .map((e) => e.message),
          isEmpty);
    });
  });
}
