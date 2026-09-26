import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

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

/// Runs the attacker's turn to emit a real distress signal (unfair fight
/// executes on the first tick). Returns the updated roster.
List<NpcShip> _emitSignal(List<Sector> sectors, List<NpcShip> npcs) {
  final out = List<NpcShip>.from(npcs);
  out[0] = out[0].copyWith(
    currentGoal: NpcGoal(
      type: NpcGoalType.attack,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {'targetSectorId': 11, 'targetId': out[1].id},
    ),
  );
  out[0] = NpcAiService.processTurn(out[0], sectors, [], out);
  return out;
}

void main() {
  setUp(() => NpcAiService.clearSignalsForTest());
  tearDown(() => NpcAiService.clearSignalsForTest());

  test('at most three ships answer one distress call', () {
    final sectors = _sectors();
    // Attacker (pirate, strong) + defender (trader, tanky but unarmed).
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 101),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 102,
          hull: 5000,
          weapons: const {}),
      // Four would-be responders, same sector, full tanks.
      for (int i = 0; i < 4; i++)
        _ship(
            faction: FactionClass.trader,
            personality: NpcPersonality.traderMerchant,
            sector: 11,
            seed: 200 + i),
    ];
    npcs = _emitSignal(sectors, npcs);

    var responders = 0;
    for (int i = 2; i < npcs.length; i++) {
      npcs[i] = NpcAiService.processTurn(npcs[i], sectors, [], npcs);
      if (npcs[i].currentGoal?.type == NpcGoalType.attack) responders++;
    }
    expect(responders, NpcAiService.maxDistressResponders);
  });

  test('responders stand down when the signal clears en route', () {
    final sectors = _sectors();
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 111),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 112,
          hull: 5000,
          weapons: const {}),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 12,
          seed: 113),
    ];
    npcs = _emitSignal(sectors, npcs);

    // Responder commits while the signal is live…
    npcs[2] = NpcAiService.processTurn(npcs[2], sectors, [], npcs);
    expect(npcs[2].currentGoal?.type, NpcGoalType.attack);

    // …then the call resolves (defender death clears it) and the
    // responder stands down instead of flying to nowhere.
    NpcAiService.clearSignalsForTest();
    npcs[2] = NpcAiService.processTurn(npcs[2], sectors, [], npcs);
    expect(npcs[2].currentGoal?.type, isNot(NpcGoalType.attack));
  });

  test('broke responder cannot afford the trip and sits out', () {
    final sectors = _sectors();
    var npcs = [
      _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 121),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 122,
          hull: 5000,
          weapons: const {}),
      _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 12,
          seed: 123,
          energy: 1),
    ];
    npcs = _emitSignal(sectors, npcs);

    npcs[2] = NpcAiService.processTurn(npcs[2], sectors, [], npcs);
    expect(npcs[2].currentGoal?.type, isNot(NpcGoalType.attack));
  });
}
