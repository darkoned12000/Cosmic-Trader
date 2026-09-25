import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/services/energy_service.dart';

Player _player({
  int energy = 1000,
  int maxEnergy = 1000,
  int credits = 10000,
  String engine = 'juryRiggedFusion',
  int engineLevel = 1,
  Map<String, int> installedModules = const {},
  bool solarArrayDeployed = false,
}) {
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
    credits: credits,
    researchPoints: 0,
    energy: energy,
    maxEnergy: maxEnergy,
    engineEquipment: engine,
    engineEquipmentLevel: engineLevel,
    installedModules: installedModules,
    solarArrayDeployed: solarArrayDeployed,
  );
}

void main() {
  test('legacy turns populate energy on old save files', () {
    final legacyJson = _player(energy: 777).toJson();
    legacyJson.remove('energy');
    legacyJson.remove('maxEnergy');
    legacyJson['turns'] = 432;
    legacyJson['maxTurns'] = 654;

    final restored = Player.fromJson(legacyJson);
    expect(restored.energy, 432);
    expect(restored.maxEnergy, 654);
  });

  test('warp cost scales with distance and engine efficiency', () {
    final standard = _player();
    final efficient = _player(engine: 'celestialFlow');

    expect(EnergyService.warpCost(standard), 2);
    expect(EnergyService.warpCost(efficient), 2);

    // Two hops cost more for everyone, and less for efficient engines.
    expect(EnergyService.warpCost(standard, hops: 2), 4);
    expect(EnergyService.warpCost(efficient, hops: 2), 3);
  });

  test('spending and refueling clamp to the energy bounds', () {
    var player = _player(energy: 5, maxEnergy: 10);

    player = player.spendEnergy(99);
    expect(player.energy, 0);

    player = player.refuelEnergy(99);
    expect(player.energy, 10);
  });

  test('refuel buys only what the tank needs and credits afford', () {
    final player = _player(energy: 990, credits: 5);

    expect(EnergyService.missingEnergy(player), 10);
    expect(EnergyService.refuelCost(player), 10);

    // Only 5 credits available → 5 units added.
    final result = EnergyService.refuel(player);
    expect(result.unitsAdded, 5);
    expect(result.creditsSpent, 5);
    expect(result.player.energy, 995);
    expect(result.player.credits, 0);
  });

  test('solar array only recharges while installed and deployed', () {
    final noArray = _player(energy: 100);
    expect(EnergyService.solarArrayLevel(noArray), 0);
    expect(EnergyService.solarRechargePerTick(noArray), 0);
    expect(EnergyService.solarRecharge(noArray).unitsAdded, 0);

    final installedRetracted = _player(
      energy: 100,
      maxEnergy: 200,
      installedModules: const {'solarArray': 2},
    );

    expect(EnergyService.solarArrayLevel(installedRetracted), 2);
    expect(EnergyService.solarRechargePerTick(installedRetracted), 4);

    // Retracted arrays do not recharge.
    expect(EnergyService.solarRecharge(installedRetracted).unitsAdded, 0);

    final deployed = EnergyService.setSolarArrayDeployed(
      installedRetracted,
      true,
    );
    expect(deployed.solarArrayDeployed, isTrue);
    expect(EnergyService.canMove(deployed), isFalse);

    final charged = EnergyService.solarRecharge(deployed);
    expect(charged.unitsAdded, 4);
    expect(charged.player.energy, 104);

    final nearFull = deployed.copyWith(energy: 199);
    final clamped = EnergyService.solarRecharge(nearFull);
    expect(clamped.unitsAdded, 1);
    expect(clamped.player.energy, 200);

    // Retracting restores movement and stops the trickle.
    final retracted = EnergyService.setSolarArrayDeployed(deployed, false);
    expect(EnergyService.canMove(retracted), isTrue);
    expect(EnergyService.solarRecharge(retracted).unitsAdded, 0);
  });

  test('action affordability checks use energy costs', () {
    final rich = _player(energy: 100);
    final poor = _player(energy: 0);

    expect(EnergyService.canScanPlanet(rich), isTrue);
    expect(EnergyService.canScanPlanet(poor), isFalse);
    expect(EnergyService.canWarp(rich), isTrue);
    expect(EnergyService.canWarp(poor), isFalse);
  });
}
