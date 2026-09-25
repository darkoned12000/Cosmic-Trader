import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';

void main() {
  test('registry carries the B2 commodity roster', () {
    expect(
      CommodityRegistry.names,
      containsAll([
        'minerals',
        'organics',
        'industrial',
        'food',
        'ore',
        'crystalline',
        'munitions',
        'contraband',
      ]),
    );
    // Contraband commands a risk premium over every legal good.
    final contraband = CommodityRegistry.defaultsMap['contraband']!;
    for (final entry in CommodityRegistry.defaultsMap.entries) {
      if (entry.key == 'contraband') continue;
      expect(contraband.priceMin, greaterThan(entry.value.priceMax * 0.5));
    }
  });

  test('black market restricted to free/independent ports', () {
    expect(UniverseGenerator.isBlackMarketPort(PortClass.free, 0.0), isTrue);
    expect(UniverseGenerator.isBlackMarketPort(PortClass.independent, 0.29),
        isTrue);
    expect(UniverseGenerator.isBlackMarketPort(PortClass.independent, 0.3),
        isFalse);
    expect(
        UniverseGenerator.isBlackMarketPort(PortClass.federal, 0.0), isFalse);
    expect(UniverseGenerator.isBlackMarketPort(PortClass.hardwareEmporium, 0.0),
        isFalse);
  });

  test('old 3-good settings gain new commodities with defaults', () {
    final legacy = GameSettings.defaults().copyWith(
      commodityConfigs: {
        for (final name in ['minerals', 'organics', 'industrial'])
          name: CommodityRegistry.defaultsMap[name]!,
      },
    );
    final restored = GameSettings.fromJson(legacy.toJson());
    for (final name in CommodityRegistry.names) {
      expect(restored.commodityConfigs, contains(name));
    }
    expect(restored.commodityConfigs['contraband']!.priceMin, 300);
  });

  test('NPC victor takes victim cargo up to free holds', () {
    final attacker = NpcShip.create(
      faction: FactionClass.pirate,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 1000,
      seed: 51,
    );
    final freeHolds = attacker.cargoHoldCapacity - attacker.cargoUsed;
    expect(freeHolds, greaterThan(0));

    // Defenseless victim stuffed with contraband.
    final victim = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 1000,
      seed: 52,
    ).copyWith(
      hull: 1,
      shields: 0,
      cargo: const {'contraband': 100000, 'minerals': 5},
      cargoUsed: 100005,
    );

    final result = CombatService.resolveCombat(attacker, victim);
    expect(result.result.defenderDestroyed, isTrue);
    final updated = result.attacker;
    // Holds cap the take; contraband transfers like any other good.
    final taken = updated.cargo.values.fold(0, (a, b) => a + b);
    expect(taken, lessThanOrEqualTo(freeHolds));
    expect(taken, greaterThan(0));
    expect(updated.cargoUsed, attacker.cargoUsed + taken);
  });
}
