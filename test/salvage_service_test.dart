import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/salvage_service.dart';

NpcShip _npc(ShipDefinition shipDef) {
  return NpcShip.create(
    faction: FactionClass.trader,
    shipDef: shipDef,
    currentSectorId: 1,
    startingCredits: 1000,
    seed: 1,
  );
}

Player _player() {
  return Player(
    name: 'Test Pilot',
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
}

void main() {
  test('destroyed NPCs drop usable scrap metal and tech', () {
    final interceptor = _npc(
      ShipDefinition.getDefaultInterceptor(FactionClass.trader),
    );
    final capitalShip = _npc(
      ShipDefinition.getShipByFactionAndClass(
        FactionClass.trader,
        ShipClassType.capitalShip,
      )!,
    );

    for (var seed = 0; seed < 25; seed++) {
      final small = SalvageService.rollForNpc(
        interceptor,
        rng: math.Random(seed),
      );
      expect(small.scrapMetal, greaterThanOrEqualTo(12));
      expect(small.scrapMetal, lessThanOrEqualTo(28));
      expect(small.scrapTech, greaterThanOrEqualTo(2));
      expect(small.scrapTech, lessThanOrEqualTo(6));

      final large = SalvageService.rollForNpc(
        capitalShip,
        rng: math.Random(seed),
      );
      expect(large.scrapMetal, greaterThanOrEqualTo(54));
      expect(large.scrapMetal, lessThanOrEqualTo(126));
      expect(large.scrapTech, greaterThanOrEqualTo(8));
      expect(large.scrapTech, lessThanOrEqualTo(23));
    }
  });

  test('three interceptor kills are enough for a level-1 module', () {
    final npc = _npc(ShipDefinition.getDefaultInterceptor(FactionClass.trader));
    var player = _player();

    for (var i = 0; i < 3; i++) {
      player = SalvageService.applyToPlayer(
        player,
        SalvageService.rollForNpc(npc, rng: math.Random(i)),
      );
    }

    // Solar Array Lv.1 costs 30 scrap metal + 5 scrap tech.
    expect(player.scrapMetal, greaterThanOrEqualTo(30));
    expect(player.scrapTech, greaterThanOrEqualTo(5));
  });

  test('NPCs with explicit scrap loot use their carried values', () {
    final npc = _npc(ShipDefinition.getDefaultInterceptor(FactionClass.trader))
        .copyWith(scrapMetal: 77, scrapTech: 9);

    final reward = SalvageService.rollForNpc(npc, rng: math.Random(123));
    expect(reward.scrapMetal, 77);
    expect(reward.scrapTech, 9);
  });
}
