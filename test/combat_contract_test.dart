import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

NpcShip _ship({
  required FactionClass faction,
  required int seed,
  int hull = 100,
  int credits = 1000,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: 1,
    startingCredits: credits,
    seed: seed,
  ).copyWith(
    personality: NpcPersonality.pirateHunter,
    hull: hull,
    maxHull: hull,
    shields: 0,
  );
}

void main() {
  group('CombatOutcome contract', () {
    test('outcomeFromDestruction maps flags, mutual kill scores attacker', () {
      expect(
        CombatResult.outcomeFromDestruction(
            defenderDestroyed: true, attackerDestroyed: false),
        CombatOutcome.attackerVictory,
      );
      expect(
        CombatResult.outcomeFromDestruction(
            defenderDestroyed: false, attackerDestroyed: true),
        CombatOutcome.defenderVictory,
      );
      expect(
        CombatResult.outcomeFromDestruction(
            defenderDestroyed: true, attackerDestroyed: true),
        CombatOutcome.attackerVictory,
      );
      expect(
        CombatResult.outcomeFromDestruction(
            defenderDestroyed: false, attackerDestroyed: false),
        CombatOutcome.ongoing,
      );
    });

    test('CombatResult defaults to ongoing with zero costs', () {
      const r = CombatResult(
        attackerWon: false,
        damageToDefender: 10,
        damageToAttacker: 5,
        defenderDestroyed: false,
        attackerDestroyed: false,
      );
      expect(r.outcome, CombatOutcome.ongoing);
      expect(r.escapeCostEnergy, 0);
      expect(r.parleyCostCredits, 0);
    });

    test('resolveCombat always sets an explicit outcome', () {
      final attacker = _ship(faction: FactionClass.pirate, seed: 1);
      final defender =
          _ship(faction: FactionClass.trader, seed: 2, hull: 1);
      final outcome = CombatService.resolveCombat(attacker, defender);
      expect(outcome.result.defenderDestroyed, isTrue);
      expect(outcome.result.outcome, CombatOutcome.attackerVictory);
      expect(outcome.attacker.kills, 1);
    });

    test('PlayerCombatResult defaults to ongoing', () {
      final player = Player(
        name: 'Tester',
        currentSectorId: 1,
        hull: 100,
        maxHull: 100,
        shields: 50,
        maxShields: 50,
        cargoUsed: 0,
        maxCargo: 20,
        cargoSize: 20,
        credits: 1000,
        researchPoints: 0,
      );
      final npc = _ship(faction: FactionClass.pirate, seed: 4);
      final result = PlayerCombatResult(
        damageDealt: 1,
        damageTaken: 1,
        npcDestroyed: false,
        loot: 0,
        updatedPlayer: player,
        updatedNpc: npc,
      );
      expect(result.outcome, CombatOutcome.ongoing);
      expect(player.name, 'Tester');
      expect(npc.id, isNotEmpty);
    });
  });

  group('VendettaRecord lifecycle', () {
    test('create, refresh bumps and preserves first sighting', () {
      var memory = const NpcMemory();
      memory = memory.withVendetta(
          targetId: 'pilot-9', sectorId: 12, nowMs: 1000);
      expect(memory.vendettas['pilot-9']!.grievance, 20);
      expect(memory.vendettas['pilot-9']!.firstSeenMs, 1000);

      memory = memory.withVendetta(
          targetId: 'pilot-9',
          sectorId: 30,
          grievanceBump: 50,
          nowMs: 2000);
      final v = memory.vendettas['pilot-9']!;
      expect(v.grievance, 70);
      expect(v.sectorId, 30);
      expect(v.firstSeenMs, 1000);
      expect(v.lastSeenMs, 2000);
    });

    test('grievance clamps at 100', () {
      var memory = const NpcMemory();
      memory = memory.withVendetta(
          targetId: 'pilot-9', sectorId: 1, grievanceBump: 999, nowMs: 0);
      expect(memory.vendettas['pilot-9']!.grievance, 100);
    });

    test('prune drops stale grudges, keeps fresh, skips saves when clean',
        () {
      var memory = const NpcMemory();
      memory = memory.withVendetta(
          targetId: 'old', sectorId: 1, nowMs: 0);
      memory = memory.withVendetta(
          targetId: 'fresh',
          sectorId: 2,
          nowMs: NpcMemory.vendettaMemory.inMilliseconds - 1);
      final pruned = memory.pruneVendettas(
          nowMs: NpcMemory.vendettaMemory.inMilliseconds + 1000);
      expect(pruned.vendettas.keys, ['fresh']);

      final clean = pruned.pruneVendettas(
          nowMs: NpcMemory.vendettaMemory.inMilliseconds + 1000);
      expect(identical(clean, pruned), isTrue);
    });

    test('vendettas survive JSON round-trip; legacy files default empty',
        () {
      var memory = const NpcMemory();
      memory = memory.withVendetta(
          targetId: 'pilot-9', sectorId: 12, nowMs: 1000);
      final restored = NpcMemory.fromJson(
          Map<String, dynamic>.from(memory.toJson()));
      expect(restored.vendettas['pilot-9']!.sectorId, 12);
      expect(restored.vendettas['pilot-9']!.grievance, 20);

      final legacy = Map<String, dynamic>.from(memory.toJson())
        ..remove('vendettas');
      expect(NpcMemory.fromJson(legacy).vendettas, isEmpty);
    });
  });
}

