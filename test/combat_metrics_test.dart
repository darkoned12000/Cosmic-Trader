import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/combat_metrics.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// C5: combat measurement — outcomes per faction, retreat hull, failed
// escapes, player endings, population samples, and the NPC hook.
void main() {
  setUp(() {
    CombatMetrics.resetForTest();
    NpcAiService.clearSignalsForTest();
  });
  tearDown(() {
    CombatMetrics.resetForTest();
    NpcAiService.clearSignalsForTest();
  });

  test('kill, retreat, and surrender tallies per faction', () {
    final m = CombatMetrics.global;
    m.recordNpc(
      attackerFaction: 'pirate',
      defenderFaction: 'trader',
      outcome: CombatOutcome.attackerVictory,
      attackerHullFraction: 0.8,
      defenderHullFraction: 0.0,
    );
    m.recordNpc(
      attackerFaction: 'duran',
      defenderFaction: 'vinari',
      outcome: CombatOutcome.defenderRetreat,
      attackerHullFraction: 0.9,
      defenderHullFraction: 0.34,
    );
    m.recordNpc(
      attackerFaction: 'pirate',
      defenderFaction: 'trader',
      outcome: CombatOutcome.defenderSurrender,
      attackerHullFraction: 1.0,
      defenderHullFraction: 0.5,
      tribute: 100,
    );

    expect(m.engagements, 3);
    final pirates = m.perFaction['pirate']!;
    expect(pirates.attacks, 2);
    expect(pirates.kills, 1);
    final traders = m.perFaction['trader']!;
    expect(traders.deaths, 1);
    expect(traders.surrenders, 1);
    expect(traders.tributePaid, 100);
    final vinari = m.perFaction['vinari']!;
    expect(vinari.retreats, 1);
    // Only the retreating hull counts toward the average.
    expect(m.retreatHullCount, 1);
    expect(m.avgRetreatHull, closeTo(0.34, 1e-9));
  });

  test('failed escapes, player endings, and yields', () {
    final m = CombatMetrics.global;
    m.recordFailedEscape('duran');
    m.recordFailedEscape('duran');
    m.recordPlayerKill();
    m.recordPlayerDeath();
    m.recordPlayerFlee();
    m.recordNpcYield(retreated: true, parleyed: false);
    m.recordNpcYield(retreated: false, parleyed: true);

    expect(m.perFaction['duran']!.escapesFailed, 2);
    expect(m.playerKills, 1);
    expect(m.playerDeaths, 1);
    expect(m.playerFlees, 1);
    expect(m.npcRetreatsVsPlayer, 1);
    expect(m.parleysAccepted, 1);
  });

  test('population samples cap and summarize', () {
    final m = CombatMetrics.global;
    for (var i = 0; i < CombatMetrics.maxPopulationSamples + 10; i++) {
      m.samplePopulation({FactionClass.duran: 8, FactionClass.pirate: 2});
    }
    expect(m.population.length, CombatMetrics.maxPopulationSamples);
    final text = m.summary();
    expect(text, contains('Population duran: now 8'));
    expect(text, contains('Player: kills 0'));
    expect(m.perFaction, isEmpty);
    expect(text, isNot(contains('no census samples yet')));
  });

  test('summary composes loot passed by the caller', () {
    final m = CombatMetrics.global;
    m.recordNpc(
      attackerFaction: 'pirate',
      defenderFaction: 'trader',
      outcome: CombatOutcome.attackerVictory,
      attackerHullFraction: 1.0,
      defenderHullFraction: 0.0,
    );
    final text = m.summary(lootByFaction: {'pirate': 2500});
    expect(text, contains('loot 2500'));
    expect(text, contains('Retreat hull avg: 0% (n=0)'));
  });

  test('reset clears everything', () {
    final m = CombatMetrics.global;
    m.recordPlayerKill();
    m.samplePopulation({FactionClass.trader: 3});
    m.reset();
    expect(m.engagements, 0);
    expect(m.perFaction, isEmpty);
    expect(m.playerKills, 0);
    expect(m.population, isEmpty);
  });

  group('NPC hook', () {
    NpcShip ship({
      required FactionClass faction,
      required NpcPersonality personality,
      required int sector,
      required int seed,
      int hull = 100,
    }) {
      return NpcShip.create(
        faction: faction,
        shipDef: ShipDefinition.allShips.first,
        currentSectorId: sector,
        startingCredits: 0,
        seed: seed,
      ).copyWith(
        personality: personality,
        hull: hull,
        maxHull: hull,
        energy: 1000,
        weaponSlots: const {'main_forward': 3},
      );
    }

    List<Sector> sectors() => [
          Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
          Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
        ];

    test('a kill resolution records attacker victory', () {
      final roster = [
        ship(
            faction: FactionClass.pirate,
            personality: NpcPersonality.pirateHunter,
            sector: 11,
            seed: 901),
        ship(
            faction: FactionClass.trader,
            personality: NpcPersonality.traderMerchant,
            sector: 11,
            seed: 902,
            hull: 1),
      ];
      roster[1] = roster[1].copyWith(shields: 0, maxShields: 0);
      roster[0] = roster[0].copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': roster[1].id},
        ),
      );
      roster[0] =
          NpcAiService.processTurn(roster[0], sectors(), [], roster);

      final m = CombatMetrics.global;
      expect(m.engagements, 1);
      expect(m.perFaction['pirate']!.kills, 1);
      expect(m.perFaction['trader']!.deaths, 1);
    });

    test('a non-lethal exchange records the engagement', () {
      final roster = [
        ship(
            faction: FactionClass.pirate,
            personality: NpcPersonality.pirateHunter,
            sector: 11,
            seed: 911),
        ship(
            faction: FactionClass.trader,
            personality: NpcPersonality.traderMerchant,
            sector: 11,
            seed: 912,
            hull: 5000),
      ];
      roster[0] = roster[0].copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': roster[1].id},
        ),
      );
      roster[0] =
          NpcAiService.processTurn(roster[0], sectors(), [], roster);

      // Counted however it ended (exchange, retreat, or surrender) —
      // the choke point never misses a resolution.
      expect(CombatMetrics.global.engagements, 1);
    });
  });
}
