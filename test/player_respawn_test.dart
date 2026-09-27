import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';

// Clone reissue: pilots don't permadeath, ships do. Death swaps the
// wreck for the faction starter with starter fittings and settings
// money/holds/drones/energy; identity and assets survive.
Player _pilot({
  FactionClass faction = FactionClass.trader,
  int credits = 12345,
  int bank = 99999,
  Map<String, int>? cargo,
  int cargoUsed = 7,
}) {
  return Player(
    name: 'Pilot',
    currentSectorId: 99,
    hull: 0,
    maxHull: 500,
    shields: 0,
    maxShields: 300,
    cargoUsed: cargoUsed,
    maxCargo: 200,
    cargoSize: 200,
    credits: credits,
    researchPoints: 3.5,
    faction: faction,
    shipDefinitionName: 'Big Boat',
    shipClass: ShipClassType.battleship,
    weaponSlots: const {'main_forward': 5},
    hullEquipmentLevel: 4,
    shieldEquipmentLevel: 4,
    engineEquipmentLevel: 4,
    installedModules: const {'scanner': 2},
    cargo: cargo ?? const {'minerals': 7},
    bankBalance: bank,
    notoriety: 42.0,
  );
}

void main() {
  test('respawn swaps wreck for starter, keeps identity and assets', () {
    final settings = GameSettings.defaults();
    final dead = _pilot();
    final alive = dead.respawned(settings);

    final starter = ShipDefinition.getDefaultInterceptor(dead.faction);
    expect(alive.shipDefinitionName, starter.name);
    expect(alive.shipClass, ShipClassType.interceptor);
    expect(alive.hull, starter.maxHullCapacity);
    expect(alive.maxHull, starter.maxHullCapacity);
    expect(alive.shields, starter.shields);
    expect(alive.maxShields, starter.maxShields);
    expect(alive.credits, settings.initCredits);
    expect(alive.maxCargo, starter.maxCargo);
    expect(alive.cargoSize, starter.maxCargo);
    expect(alive.cargo, isEmpty);
    expect(alive.cargoUsed, 0);
    expect(alive.drones, settings.initDrones);
    expect(alive.maxDrones, settings.initDrones);
    expect(alive.energy, settings.initEnergy);
    expect(alive.maxEnergy, settings.initEnergy);
    expect(alive.hullEquipmentLevel, 1);
    expect(alive.shieldEquipmentLevel, 1);
    expect(alive.engineEquipmentLevel, 1);
    expect(alive.installedModules, isEmpty);
    expect(alive.currentSectorId, 1);

    // Identity and assets survive.
    expect(alive.id, dead.id);
    expect(alive.name, dead.name);
    expect(alive.faction, dead.faction);
    expect(alive.bankBalance, 99999);
    expect(alive.notoriety, 42.0);
    expect(alive.researchPoints, 3.5);
  });

  test('respawn works per faction starter', () {
    final settings = GameSettings.defaults();
    for (final faction in [
      FactionClass.duran,
      FactionClass.vinari,
      FactionClass.trader
    ]) {
      final alive = _pilot(faction: faction).respawned(settings);
      expect(alive.shipDefinitionName,
          ShipDefinition.getDefaultInterceptor(faction).name);
    }
  });
}
