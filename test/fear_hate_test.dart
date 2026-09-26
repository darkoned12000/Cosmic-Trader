import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// B3 slice 3: fear and hatred. Notorious pilots deter attacks unless the
// attacker is overwhelming; personal hatred (≤ −50) substitutes for lore
// hostility but demands a decisive edge. Weaker ships fear the infamous
// and leave rather than provoke.
Player _player({
  required FactionClass faction,
  required int sector,
  double notoriety = 0,
  Map<String, int> standings = const {},
  Map<String, String> weaponTypes = const {},
  Map<String, int> weaponSlots = const {'main_forward': 1},
}) {
  return Player(
    name: 'Pilot',
    currentSectorId: sector,
    hull: 100,
    maxHull: 100,
    shields: 50,
    maxShields: 50,
    cargoUsed: 0,
    maxCargo: 20,
    cargoSize: 20,
    credits: 10000,
    researchPoints: 0,
    faction: faction,
    notoriety: notoriety,
    factionStandings: standings,
    weaponTypes: weaponTypes,
    weaponSlots: weaponSlots,
  );
}

NpcShip _npc({
  required FactionClass faction,
  required NpcPersonality personality,
  required int sector,
  required int seed,
  Map<String, int> weapons = const {'main_forward': 1},
  int hullLevel = 1,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: 10000,
    seed: seed,
  ).copyWith(
    personality: personality,
    weaponSlots: weapons,
    hullEquipmentLevel: hullLevel,
  );
}

void main() {
  test('notoriety deters attacks below overwhelming odds', () {
    // pirateRaider (caution 0.2 → base threshold 1.36) with L1 plasmaLance
    // (35 + 5 hull bonus = 40) vs autoLaser player (25): ratio 1.6.
    final npc = _npc(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateRaider,
      sector: 11,
      seed: 201,
      hullLevel: 2,
    );
    final clean = _player(faction: FactionClass.trader, sector: 11);
    final notorious =
        _player(faction: FactionClass.trader, sector: 11, notoriety: 100);

    expect(NpcAiService.shouldAttackPlayer(npc, clean), isTrue);
    // 1.6× < 1.36 × 1.5 (fear multiplier): deterred.
    expect(NpcAiService.shouldAttackPlayer(npc, notorious), isFalse);

    // Overwhelming (L3: 105+5=110 vs 25 = 4.4×) attacks anyway.
    final hunter = _npc(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateRaider,
      sector: 11,
      seed: 202,
      weapons: const {'main_forward': 3},
      hullLevel: 2,
    );
    expect(NpcAiService.shouldAttackPlayer(hunter, notorious), isTrue);
  });

  test('hatred substitutes for hostility only with a decisive edge', () {
    // Trader vs trader: no lore hostility. Standing -60 enables hunting,
    // but the 1.5× decisiveness rule applies (threshold 2.04).
    final npc = _npc(
      faction: FactionClass.trader,
      personality: NpcPersonality.traderSmuggler,
      sector: 11,
      seed: 203,
      hullLevel: 2,
    );
    // traderSmuggler aggression 0.2 < min 0.7 for non-pirates!
    // Use a qualifying personality via duran? No — same-faction trader
    // test needs aggression ≥ 0.7, which no trader has. Instead verify
    // the gate blocks: peaceful traders never hunt, hated or not.
    final hated = _player(
        faction: FactionClass.trader,
        sector: 11,
        standings: const {'trader': -60});
    expect(NpcAiService.shouldAttackPlayer(npc, hated), isFalse);

    // Pirate (aggression clears) vs pirate player with -60 self-standing:
    // threshold 1.36 × 1.5 (no lore hostility within faction) = 2.04.
    final pirate = _npc(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateRaider,
      sector: 11,
      seed: 204,
      hullLevel: 2,
    );
    final disliked = _player(
        faction: FactionClass.pirate,
        sector: 11,
        standings: const {'pirate': -60});
    // Ratio 1.6 < 2.04: hate alone doesn't suffice.
    expect(NpcAiService.shouldAttackPlayer(pirate, disliked), isFalse);

    final strong = _npc(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateRaider,
      sector: 11,
      seed: 205,
      weapons: const {'main_forward': 3},
      hullLevel: 2,
    );
    expect(NpcAiService.shouldAttackPlayer(strong, disliked), isTrue);

    // Above the hate line (-49): never.
    final mild = _player(
        faction: FactionClass.pirate,
        sector: 11,
        standings: const {'pirate': -49});
    expect(NpcAiService.shouldAttackPlayer(strong, mild), isFalse);
  });

  test('weak ships flee infamous hostiles they would otherwise face', () {
    final sectors = [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
    ];
    NpcShip victim() => _npc(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 206,
        );
    // Player mounts the same plasmaLance (35 vs 35): no fear, no flee.
    Player pirate(int notoriety) => _player(
          faction: FactionClass.pirate,
          sector: 11,
          notoriety: notoriety.toDouble(),
          weaponTypes: const {'main_forward': 'plasmaLance'},
        );

    // Equal power (35 vs 35): no fear, no flee.
    var calm = NpcAiService.processTurn(
      victim(),
      sectors,
      [pirate(0)],
      [victim()],
    );
    expect(calm.currentGoal?.type, isNot(NpcGoalType.flee));

    // Same power, infamous pirate (×1.5 fear): leaves.
    var scared = NpcAiService.processTurn(
      victim(),
      sectors,
      [pirate(100)],
      [victim()],
    );
    expect(scared.currentGoal?.type, NpcGoalType.flee);
  });
}
