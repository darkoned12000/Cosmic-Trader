import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/tow_service.dart';

Port _port(String name, PortClass portClass) {
  return Port(
    name: name,
    portClass: portClass,
    buyPrices: const {},
    sellPrices: const {},
  );
}

Sector _sector(int id, List<int> warps, {Port? port}) {
  return Sector(
    id: id,
    name: 'Sector $id',
    x: id.toDouble(),
    y: 0,
    warpRoutes: warps,
    hasPort: port != null,
    port: port,
  );
}

Player _player({
  int energy = 0,
  int currentSectorId = 1,
  int credits = 10000,
  bool solarArrayDeployed = false,
}) {
  return Player(
    name: 'Test Pilot',
    currentSectorId: currentSectorId,
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
    maxEnergy: 1000,
    solarArrayDeployed: solarArrayDeployed,
  );
}

void main() {
  final sectors = [
    _sector(1, [2]),
    _sector(2, [1, 3], port: _port('Local Dock', PortClass.independent)),
    _sector(3, [2, 4]),
    _sector(4, [3],
        port: _port('Emporium Station', PortClass.hardwareEmporium)),
  ];

  test('stranded detection uses warp affordability', () {
    expect(TowService.needsTow(_player(energy: 0)), isTrue);
    expect(TowService.needsTow(_player(energy: 5)), isFalse);
  });

  test('tow prefers the nearest refuel-capable Hardware Emporium', () {
    final plan = TowService.findTowPlan(sectors, 1);

    expect(plan, isNotNull);
    expect(plan!.targetSectorId, 4);
    expect(plan.targetPortName, 'Emporium Station');
    expect(plan.hops, 3);
    expect(plan.isRefuelStation, isTrue);
  });

  test('tow falls back to the nearest port when no emporium is reachable', () {
    final fallbackSectors = [
      _sector(1, [2]),
      _sector(2, [1, 3], port: _port('Local Dock', PortClass.independent)),
      _sector(3, [2]),
    ];

    final plan = TowService.findTowPlan(fallbackSectors, 1);

    expect(plan, isNotNull);
    expect(plan!.targetSectorId, 2);
    expect(plan.isRefuelStation, isFalse);
  });

  test('tow cost never exceeds available credits', () {
    final plan = TowService.findTowPlan(sectors, 1)!;
    final broke = _player(credits: 100);

    expect(TowService.towCost(broke, plan), 100);
    expect(TowService.towCost(_player(credits: 10000), plan), 4750);
  });

  test('calling a tow moves, charges, retracts array, and restores energy', () {
    final plan = TowService.findTowPlan(sectors, 1)!;
    final stranded =
        _player(energy: 0, credits: 10000, solarArrayDeployed: true);

    final result = TowService.tow(stranded, plan);

    expect(result.player.currentSectorId, 4);
    expect(result.player.credits, 10000 - result.creditsSpent);
    expect(result.player.solarArrayDeployed, isFalse);
    expect(result.player.energy, greaterThan(0));
    expect(result.player.hasEnergy(2), isTrue);
    expect(result.arrivedAtRefuelStation, isTrue);
  });
}
