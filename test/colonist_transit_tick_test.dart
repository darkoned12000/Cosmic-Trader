import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';
import 'support/storage_fakes.dart';

/// A live NPC, because the tick returns early on an empty roster.
NpcShip _stubNpc(String id) => NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 7,
      startingCredits: 200000,
      seed: 99,
    ).copyWith(id: id);

/// The whole chain, end to end: **screen recruits -> real tick runs -> screen
/// repaints**.
///
/// Every earlier guard for this feature stopped one layer short. The unit tests
/// drove `PlanetProductionService.process` and saved by hand; the screen tests
/// never ran a tick. Neither could see what actually breaks: whether the tick
/// *persists* the arrival, and whether the screen then shows it. Reported as
/// "waited ten minutes and the colonists never turned up".
void main() {
  late FaithfulUniverse store;
  late Player live;
  late Planet world;

  Player pilot() => Player(
        id: 'me',
        username: 'Vex',
        name: 'Vex',
        passwordHash: 'x',
        currentSectorId: 7,
        hull: 1000,
        maxHull: 1000,
        shields: 500,
        maxShields: 500,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 100,
        credits: 5000000,
        energy: 500,
        maxEnergy: 500,
        researchPoints: 0,
        faction: FactionClass.trader,
      );

  List<Sector> galaxy() => [
        Sector(
          id: 1,
          name: 'Vionis',
          x: 0,
          y: 0,
          warpRoutes: const [7],
          planets: [
            Planet(
              id: 'hw-1',
              name: 'Vionis',
              planetType: 'Terran',
              owner: FactionClass.trader,
              isHomeworld: true,
              homeworldOf: FactionClass.trader,
              scanned: true,
              level: 4,
              population: 12000,
              hull: 40000,
              maxHull: 40000,
            )
          ],
        ),
        Sector(
            id: 7,
            name: 'Kronos Reach',
            x: 0,
            y: 0,
            warpRoutes: const [1],
            planets: [world]),
      ];

  Future<Planet> onDisk() async =>
      (await store.loadUniverse()).firstWhere((s) => s.id == 7).planets.first;

  setUp(() {
    world = Planet(
      id: 'w-1',
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      scanned: true,
      level: 3,
      population: 1000,
      hull: 40000,
      maxHull: 40000,
    );
    store = FaithfulUniverse(galaxy());
    UniverseStorage.instanceForTest = store;
    // A roster with at least one live NPC: the tick returns *early* when the
    // roster is empty, before colony production runs at all.
    NpcStorage.instanceForTest = FakeNpcStorage([
      _stubNpc('npc-1'),
    ]);
    PlayerStorage.instanceForTest = FakePlayerStorage([pilot()]);
    live = pilot();
    addTearDown(() {
      UniverseStorage.instanceForTest = null;
      NpcStorage.instanceForTest = null;
      PlayerStorage.instanceForTest = null;
    });
  });

  testWidgets('recruit -> real tick -> arrival visible on the card',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(player: live, onPlayerUpdate: (p) => live = p),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Queued on disk, and the card is telling the player so.
    expect((await onDisk()).colonistsInTransit, greaterThan(0));
    expect(find.textContaining('colonists en route'), findsOneWidget,
        reason: 'the pending shipment must be visible the moment it is bought');
    expect(find.byKey(const ValueKey('colonist-transit-bar')), findsOneWidget);

    final queued = (await onDisk()).colonistsInTransit;

    // Two real ticks. `GameTickService.processTickNow` is the game\'s own entry
    // point — the same call the 30s timer makes.
    final tick = GameTickService();
    await tester.runAsync(() async {
      for (var i = 0; i < 2; i++) {
        await tick.processTickNow();
      }
    });

    // ARRIVED AND DURABLE. The assertion that matters is the one after a
    // *reload*: the tick re-parses the universe every pass, so an arrival that
    // was only ever true in the tick\'s object graph is gone by the next read.
    final landed = await onDisk();
    expect(landed.colonistsInTransit, 0,
        reason: 'the tick advanced the countdown but did not persist it');
    expect(landed.population, 1000 + queued,
        reason:
            'the colonists must exist on disk, not just in the tick\'s copy');

    // And the card repaints to say so.
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.textContaining('colonists en route'), findsNothing);
    expect(find.byKey(const ValueKey('colonist-transit-bar')), findsNothing);
  });

  testWidgets('an empty NPC roster must not stop colonists arriving',
      (tester) async {
    // The tick opens with:
    //
    //     if (sectors.isEmpty || npcs.isEmpty) { ...; return; }
    //
    // which returns **before** `PlanetProductionService.process`, so an empty
    // roster silently switches off every colony in the galaxy: production, the
    // supply bill, construction advance, and arrivals. The check exists for an
    // empty *sector list* (nothing to simulate); `npcs.isEmpty` was bolted onto
    // the same guard and quietly made the colonies a casualty of it.
    //
    // This is reachable, not theoretical: a pilot working the bounty board kills
    // ships faster than the homeworld yards replace them, and the roster can be
    // driven to zero. A queued shipment then waits forever on a tick that never
    // runs the code that would deliver it.
    NpcStorage.instanceForTest = FakeNpcStorage([]);

    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(player: live, onPlayerUpdate: (p) => live = p),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final queued = (await onDisk()).colonistsInTransit;
    expect(queued, greaterThan(0));

    // Twenty ticks is ten minutes at the real 30s cadence \u2014 what the player
    // actually waited.
    final tick = GameTickService();
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        await tick.processTickNow();
      }
    });

    final landed = await onDisk();
    expect(landed.colonistsInTransit, 0,
        reason: 'an empty roster must not park a paid-for shipment forever');
    expect(landed.population, 1000 + queued);
  });

  testWidgets('an arrival is persisted even when NOTHING else changed',
      (tester) async {
    // The save gate is `portsRegened > 0 || processed > 0 || collided > 0 ||
    // colonistsArrived > 0`, and every other term is a trap: a port restocks
    // almost every tick, and `processed` is non-zero on any populated galaxy, so
    // the universe was written by luck and the arrival term was never exercised.
    // This fixture removes the other three: the sectors carry no port at all
    // (so `portsRegened` stays 0), there are no NPCs (`processed` stays 0), and
    // nothing is over-stacked (`collided` stays 0). The only thing the tick
    // mutates is the arriving colonists.
    store = FaithfulUniverse(galaxy());
    UniverseStorage.instanceForTest = store;
    NpcStorage.instanceForTest = FakeNpcStorage([]);

    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(player: live, onPlayerUpdate: (p) => live = p),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final queued = (await onDisk()).colonistsInTransit;
    expect(queued, greaterThan(0));

    final tick = GameTickService();
    await tester.runAsync(() async {
      for (var i = 0; i < 2; i++) {
        await tick.processTickNow();
      }
    });

    final landed = await onDisk();
    expect(landed.population, 1000 + queued,
        reason: 'the arrival existed in the tick\'s object graph and was never '
            'written, so the next load resurrected the shipment');
    expect(landed.colonistsInTransit, 0);
  });
}
