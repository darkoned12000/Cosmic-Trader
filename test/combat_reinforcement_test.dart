import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// C1c: reinforcements-as-joins — arrival revalidation clears stale
// signals, and kills record retaliation intent in witnesses' memory
// (goals/pursuit arrive in C2; nothing here touches currentGoal).
NpcShip _ship({
  required FactionClass faction,
  required NpcPersonality personality,
  required int sector,
  required int seed,
  int hull = 100,
  int energy = 1000,
  Map<String, int>? weapons,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: 10000,
    seed: seed,
  ).copyWith(
    personality: personality,
    hull: hull,
    maxHull: hull,
    energy: energy,
    weaponSlots: weapons ?? {'main_forward': 3},
  );
}

List<Sector> _sectors() => [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
    ];

/// Attacker with a live attack goal vs [defenderId] in sector 11, run for
/// one turn. Returns the updated roster (defender updated in place).
List<NpcShip> _strike(
    List<Sector> sectors, List<NpcShip> npcs, String defenderId) {
  final out = List<NpcShip>.from(npcs);
  out[0] = out[0].copyWith(
    currentGoal: NpcGoal(
      type: NpcGoalType.attack,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': 11, 'targetId': defenderId},
    ),
  );
  out[0] = NpcAiService.processTurn(out[0], sectors, [], out);
  return out;
}

void main() {
  setUp(() => NpcAiService.clearSignalsForTest());
  tearDown(() => NpcAiService.clearSignalsForTest());

  test('responder arriving to an empty fight clears signal and stands down',
      () {
    final sectors = _sectors();
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 301),
      // Tanky but unarmed: guarantees the strike emits a distress signal
      // (attacker power > 0), and survives it (5000 hull).
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 302,
          hull: 5000,
          weapons: const {}),
      // Responder already on station with a distress goal.
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 303),
    ];
    npcs = _strike(sectors, npcs, npcs[1].id);

    // Both combatants leave before the responder's turn: aggressor and
    // defender warp to sector 12 (defender survived: 5000 hull).
    npcs[0] = npcs[0].copyWith(currentSectorId: 12);
    npcs[1] = npcs[1].copyWith(currentSectorId: 12);
    npcs[2] = npcs[2].copyWith(
      currentGoal: NpcGoal(
        type: NpcGoalType.attack,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {
          'targetSectorId': 11,
          'targetId': npcs[0].id,
          'distressFor': npcs[1].id,
        },
      ),
    );

    npcs[2] = NpcAiService.processTurn(npcs[2], sectors, [], npcs);
    // Stood down: whatever goal step-5 selection picked next (usually
    // explore), it is NOT a distress answer — the signal died here.
    expect(npcs[2].currentGoal?.params.containsKey('distressFor') ?? false,
        isFalse);

    // Proof the signal died with the empty sector: a fresh pilot in
    // sector 11 finds no distress call to answer (a spontaneous attack
    // pick would carry no distressFor either).
    var fresh = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 304);
    final roster = [...npcs, fresh];
    fresh = NpcAiService.processTurn(fresh, sectors, [], roster);
    expect(
        fresh.currentGoal?.params.containsKey('distressFor') ?? false, isFalse);
  });

  test('defender presence alone does not clear a live signal', () {
    final sectors = _sectors();
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 311),
      // Unarmed like above: strike emits a live distress signal.
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 312,
          hull: 5000,
          weapons: const {}),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 313),
    ];
    npcs = _strike(sectors, npcs, npcs[1].id);

    // Only the aggressor leaves; the defender holds sector 11.
    npcs[0] = npcs[0].copyWith(currentSectorId: 12);
    npcs[2] = npcs[2].copyWith(
      currentGoal: NpcGoal(
        type: NpcGoalType.attack,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {
          'targetSectorId': 11,
          'targetId': npcs[0].id,
          'distressFor': npcs[1].id,
        },
      ),
    );

    npcs[2] = NpcAiService.processTurn(npcs[2], sectors, [], npcs);
    // Target gone → the stale leg is dropped, but the live defender keeps
    // the signal alive: step-3b re-answers it in the same turn, so the
    // responder still holds a distress attack goal.
    expect(npcs[2].currentGoal?.type, NpcGoalType.attack);
    expect(npcs[2].currentGoal?.params['distressFor'], npcs[1].id);

    var fresh = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 314);
    final roster = [...npcs, fresh];
    fresh = NpcAiService.processTurn(fresh, sectors, [], roster);
    // Fresh pilot answers the still-live call.
    expect(fresh.currentGoal?.type, NpcGoalType.attack);
    expect(fresh.currentGoal?.params['distressFor'], npcs[1].id);
  });

  test('kill records retaliation intent in same-faction witnesses only', () {
    final sectors = _sectors();
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 321),
      // Doomed defender: hull 1, no shields.
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 322,
          hull: 1),
      // Same-faction witness.
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 323),
      // Other-faction bystander.
      _ship(
          faction: FactionClass.vinari,
          personality: NpcPersonality.vinariExplorer,
          sector: 11,
          seed: 324),
    ];
    // Defender starts with no shields so the kill lands.
    npcs[1] = npcs[1].copyWith(shields: 0, maxShields: 0);
    npcs = _strike(sectors, npcs, npcs[1].id);

    final aggressorId = npcs[0].id;
    final witness = npcs[2];
    final record = witness.memory.vendettas[aggressorId];
    expect(record, isNotNull);
    expect(record!.grievance, 40);
    expect(record.sectorId, 11);

    final bystander = npcs[3];
    expect(bystander.memory.vendettas, isEmpty);

    // The aggressor records no grudge against itself.
    expect(npcs[0].memory.vendettas.containsKey(aggressorId), isFalse);

    // The dead defender carries no grudges either.
    expect(npcs[1].isDestroyed, isTrue);

    // Witness kept its committed state otherwise: memory-only change,
    // no goal hijack.
    expect(witness.currentGoal, isNull);
  });
}
