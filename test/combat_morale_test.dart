import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// C1a: morale at resolution — trigger (willingness), eligibility (engine +
// energy), resolution (costs, tribute, survival). Damage rolls are random,
// so every scenario sizes hull/shields to survive any roll; willingness
// itself is fully deterministic (pre-round state only).
NpcShip _ship({
  required FactionClass faction,
  required NpcPersonality personality,
  required int seed,
  int hull = 100,
  int maxHull = 100,
  int shields = 1000,
  int maxShields = 1000,
  int energy = 1000,
  int credits = 1000,
  int engineLevel = 1,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: 1,
    startingCredits: credits,
    seed: seed,
  ).copyWith(
    personality: personality,
    hull: hull,
    maxHull: maxHull,
    shields: shields,
    maxShields: maxShields,
    energy: energy,
    credits: credits,
    engineEquipmentLevel: engineLevel,
  );
}

void main() {
  group('assessMorale (willingness + eligibility)', () {
    test('outmatched unshelled ship retreats even at full hull', () {
      final vinari = _ship(
        faction: FactionClass.vinari,
        personality: NpcPersonality.vinariExplorer,
        seed: 1,
        shields: 10,
        maxShields: 1000,
      );
      final decision = CombatService.assessMorale(
        self: vinari,
        selfPower: 10,
        foePower: 100,
        foeHullFraction: 1.0,
        isDefender: true,
      );
      expect(decision.outcome, CombatOutcome.defenderRetreat);
      expect(decision.escapeCost, greaterThan(0));
    });

    test('even fight at full hull fights on', () {
      final duran = _ship(
        faction: FactionClass.duran,
        personality: NpcPersonality.duranConqueror,
        seed: 2,
      );
      final decision = CombatService.assessMorale(
        self: duran,
        selfPower: 50,
        foePower: 50,
        foeHullFraction: 1.0,
        isDefender: true,
      );
      expect(decision.outcome, isNull);
    });
  });

  group('resolveCombat morale', () {
    test('vinari defender breaks off, pays energy, keeps cargo', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 10,
      );
      final defender = _ship(
        faction: FactionClass.vinari,
        personality: NpcPersonality.vinariExplorer,
        seed: 11,
        hull: 30,
      );
      final beforeEnergy = defender.energy;
      final outcome = CombatService.resolveCombat(attacker, defender);

      expect(outcome.result.outcome, CombatOutcome.defenderRetreat);
      expect(outcome.defender.isDestroyed, isFalse);
      expect(outcome.attacker.kills, 0);
      expect(outcome.result.lootCredits, 0);
      expect(outcome.defender.energy, lessThan(beforeEnergy));
    });

    test('duran in the same state fights on', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 20,
      );
      final defender = _ship(
        faction: FactionClass.duran,
        personality: NpcPersonality.duranConqueror,
        seed: 21,
        hull: 30,
      );
      final outcome = CombatService.resolveCombat(attacker, defender);
      expect(outcome.result.outcome, isNot(CombatOutcome.defenderRetreat));
      expect(outcome.result.outcome,
          isNot(CombatOutcome.defenderSurrender));
    });

    test('trader defender surrenders tribute without exchange', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 30,
        credits: 500,
      );
      final defender = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        seed: 31,
        hull: 30,
        credits: 1000,
      );
      final outcome = CombatService.resolveCombat(attacker, defender);

      expect(outcome.result.outcome, CombatOutcome.defenderSurrender);
      expect(outcome.result.parleyCostCredits, 100);
      expect(outcome.attacker.credits, 600);
      expect(outcome.defender.credits, 900);
      // No blows exchanged: hulls untouched, no kills, no loot.
      expect(outcome.defender.hull, 30);
      expect(outcome.attacker.kills, 0);
      expect(outcome.result.lootCredits, 0);
      expect(outcome.defender.isDestroyed, isFalse);
    });

    test('willing but stranded ship fights on (no energy)', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 40,
      );
      final defender = _ship(
        faction: FactionClass.vinari,
        personality: NpcPersonality.vinariExplorer,
        seed: 41,
        hull: 30,
        energy: 0,
      );
      final outcome = CombatService.resolveCombat(attacker, defender);
      expect(outcome.result.outcome, isNot(CombatOutcome.defenderRetreat));
    });

    test('pirate pressing a dying foe never breaks off', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 50,
        hull: 15,
      );
      final defender = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        seed: 51,
        hull: 10,
        shields: 1000,
        maxShields: 1000,
      );
      final outcome = CombatService.resolveCombat(attacker, defender);
      expect(outcome.result.outcome, isNot(CombatOutcome.attackerRetreat));
      expect(outcome.result.outcome,
          isNot(CombatOutcome.defenderRetreat));
    });

    test('losing attacker breaks off when it can escape', () {
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 60,
        hull: 15,
        shields: 1000,
        maxShields: 1000,
      );
      final defender = _ship(
        faction: FactionClass.duran,
        personality: NpcPersonality.duranConqueror,
        seed: 61,
      );
      final beforeEnergy = attacker.energy;
      final outcome = CombatService.resolveCombat(attacker, defender);

      expect(outcome.result.outcome, CombatOutcome.attackerRetreat);
      expect(outcome.attacker.isDestroyed, isFalse);
      expect(outcome.attacker.energy, lessThan(beforeEnergy));
      expect(outcome.result.lootCredits, 0);
      expect(outcome.defender.kills, 0);
    });

    test('retreat fails when the round kills anyway', () {
      // Attacker wants out (hull 1/100 < pirate limit) but any return
      // fire is lethal (damage floor is always >= 1): destruction stands,
      // retreat does not save.
      final attacker = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateRaider,
        seed: 70,
        hull: 1,
        shields: 0,
        maxShields: 0,
      );
      final defender = _ship(
        faction: FactionClass.duran,
        personality: NpcPersonality.duranConqueror,
        seed: 71,
      );
      final outcome = CombatService.resolveCombat(attacker, defender);
      // Destruction stands: a corpse is never recorded as retreated.
      expect(outcome.attacker.isDestroyed, isTrue);
      expect(outcome.result.outcome, CombatOutcome.defenderVictory);
    });
  });

  group('resolveRetreat (escape resolution)', () {
    test('better engines always escape; worse need luck', () {
      final sure = CombatService.resolveRetreat(
        escapeeEngineLevel: 3,
        pursuerEngineLevel: 1,
      );
      expect(sure.escaped, isTrue);
      expect(sure.energyCost, 6);

      // Equal engines: seeded coin flip, both outcomes reachable.
      var wins = 0;
      for (int i = 0; i < 20; i++) {
        final r = CombatService.resolveRetreat(
          escapeeEngineLevel: 2,
          pursuerEngineLevel: 2,
          rng: math.Random(i),
        );
        if (r.escaped) wins++;
        expect(r.energyCost, 8);
      }
      expect(wins, greaterThan(0));
      expect(wins, lessThan(20));
    });

    test('outclassed engines usually fail, cost paid anyway', () {
      var wins = 0;
      for (int i = 0; i < 50; i++) {
        final r = CombatService.resolveRetreat(
          escapeeEngineLevel: 1,
          pursuerEngineLevel: 5,
          rng: math.Random(1000 + i),
        );
        if (r.escaped) wins++;
        expect(r.energyCost, 10);
      }
      // 10% luck rate: expect a few, far from half.
      expect(wins, lessThan(15));
    });

    test('tractor beam blocks escape (future hook, always on today)', () {
      final r = CombatService.resolveRetreat(
        escapeeEngineLevel: 9,
        pursuerEngineLevel: 1,
        tractorBeam: true,
        rng: math.Random(0),
      );
      expect(r.escaped, isFalse);
      expect(r.energyCost, greaterThan(0));
    });

    test('escape cost tiers by engine level', () {
      expect(CombatService.escapeEnergyCost(1), 10);
      expect(CombatService.escapeEnergyCost(3), 6);
      expect(CombatService.escapeEnergyCost(5), 2);
      expect(CombatService.escapeEnergyCost(9), 1);
    });

    test('surrender tribute is 10%, floored, capped', () {
      expect(CombatService.surrenderTribute(1000), 100);
      expect(CombatService.surrenderTribute(0), 0);
      expect(CombatService.surrenderTribute(-50), 0);
    });
  });
}
