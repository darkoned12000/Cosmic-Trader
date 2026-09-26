import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';

NpcShip _ship(FactionClass faction, {bool destroyed = false}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: 1,
    startingCredits: 10000,
    seed: faction.index + (destroyed ? 100 : 0),
  ).copyWith(isDestroyed: destroyed);
}

Sector _sector(int id) => Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: const [],
    );

void main() {
  test('extinct factions respawn at their homeworld', () {
    final homeworld = _sector(7)
      ..hasPlanet = true
      ..planet = Planet(
        name: 'Duran Prime',
        planetType: 'Terran',
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
      );
    final sectors = [homeworld, _sector(8)];
    // Duran wiped out, everyone else healthy.
    final npcs = [
      _ship(FactionClass.duran, destroyed: true),
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
      _ship(FactionClass.vinari),
      _ship(FactionClass.vinari),
      _ship(FactionClass.vinari),
      _ship(FactionClass.pirate),
      _ship(FactionClass.pirate),
    ];

    final spawned = RepopulationService.repopulate(
      sectors,
      npcs,
      rng: math.Random(5),
    );

    expect(spawned, hasLength(1));
    expect(spawned.first.faction, FactionClass.duran);
    expect(spawned.first.currentSectorId, 7);
    expect(spawned.first.isDestroyed, isFalse);
  });

  test('healthy populations spawn nothing', () {
    final sectors = [_sector(1)];
    final npcs = [
      for (int i = 0; i < 3; i++) _ship(FactionClass.trader),
      for (int i = 0; i < 3; i++) _ship(FactionClass.duran),
      for (int i = 0; i < 3; i++) _ship(FactionClass.vinari),
      for (int i = 0; i < 2; i++) _ship(FactionClass.pirate),
    ];
    expect(
      RepopulationService.repopulate(sectors, npcs, rng: math.Random(5)),
      isEmpty,
    );
  });

  test('factions without any homeworld cannot spawn (pirates excepted)',
      () {
    final sectors = [_sector(1), _sector(2)];
    final npcs = [
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
    ];
    // Duran/vinari have no homeworld anywhere: blocked. Pirates fall
    // back to random sectors (outposts later).
    final spawned = RepopulationService.repopulate(
      sectors,
      npcs,
      rng: math.Random(5),
    );
    expect(spawned, hasLength(1));
    expect(spawned.first.faction, FactionClass.pirate);
    expect([1, 2], contains(spawned.first.currentSectorId));
  });

  test('captured homeworld blocks regeneration (recapture restores)', () {
    final homeworld = _sector(7)
      ..hasPlanet = true
      ..planet = Planet(
        name: 'Duran Prime',
        planetType: 'Lava',
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        owner: FactionClass.vinari, // captured
      );
    final sectors = [homeworld, _sector(8)];
    final npcs = [
      _ship(FactionClass.duran, destroyed: true),
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
      _ship(FactionClass.trader),
      _ship(FactionClass.vinari),
      _ship(FactionClass.vinari),
      _ship(FactionClass.vinari),
      _ship(FactionClass.pirate),
      _ship(FactionClass.pirate),
    ];

    // Duran extinct and dispossessed: nothing spawns.
    expect(
      RepopulationService.repopulate(sectors, npcs, rng: math.Random(5)),
      isEmpty,
    );

    // Recaptured: spawning resumes at the homeworld.
    homeworld.planet!.owner = FactionClass.duran;
    final spawned = RepopulationService.repopulate(
      sectors,
      npcs,
      rng: math.Random(5),
    );
    expect(spawned, hasLength(1));
    expect(spawned.first.currentSectorId, 7);
  });
}
