import 'dart:io' as io;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// T6: the priced `Collect` button is retired.
///
/// The shipment pool is overflow, not a sale, so sweeping it into the stores
/// is free and priceless — the flat payout table (`_shipmentUnitValue`) is
/// deleted, not retuned. Guard both halves: the sweep moves real units
/// bounded by room, and the invented price cannot return to the two files
/// that used to quote it.

Planet _world({int pendingMinerals = 2000}) {
  final planet = Planet(
    id: 'w1',
    name: 'Xandor',
    planetType: 'Terran',
    owner: FactionClass.trader,
    scanned: true,
  );
  planet.pendingMinerals = pendingMinerals;
  return planet;
}

Player _player() => Player(
      id: 'p1',
      name: 'Tester',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 50,
      maxShields: 50,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: 1000,
      researchPoints: 0,
    );

void main() {
  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  group('sweep model', () {
    test('moves the pool into the store bounded by room', () {
      final planet = _world(pendingMinerals: 0);
      final room = planet.capFor('minerals') - planet.storedFor('minerals');
      planet.pendingMinerals = room + 500;
      final moved = planet.sweepShipmentPool();
      expect(moved['minerals'], room);
      expect(planet.storedMinerals, planet.capFor('minerals'));
      expect(planet.pendingMinerals, 500);
    });

    test('sweeps every commodity including drones, emptying a fitting pool',
        () {
      final planet = _world(pendingMinerals: 100)
        ..pendingOrganics = 50
        ..pendingIndustrial = 25
        ..pendingDrones = 10;
      final moved = planet.sweepShipmentPool();
      expect(moved.length, 4);
      expect(planet.pendingTotal, 0);
      expect(planet.storedDrones, 10);
    });

    test('an empty pool moves nothing', () {
      final planet = _world(pendingMinerals: 0);
      expect(planet.sweepShipmentPool(), isEmpty);
    });
  });

  group('sweep UI', () {
    testWidgets('the pool sweeps for free: stores up, pool down, no credits',
        (WidgetTester tester) async {
      var player = _player();
      final store = FaithfulUniverse([
        Sector(
            id: 1,
            name: 'Home',
            x: 0,
            y: 0,
            warpRoutes: const [],
            planets: [_world()]),
      ]);
      UniverseStorage.instanceForTest = store;
      await tester.pumpWidget(MaterialApp(
        home: PlanetScreen(
          player: player,
          onPlayerUpdate: (p) => player = p,
          planetTradingEnabled: true,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // The priced button is gone; the free sweep is in its place.
      expect(find.textContaining('Collect'), findsNothing);
      final sweep = find.text('Move to store');
      expect(sweep, findsOneWidget);
      await tester.scrollUntilVisible(sweep, 200);
      await tester.pumpAndSettle();
      await tester.tap(sweep);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 2,000 pooled minerals are now stored; the wallet never moved.
      expect(player.credits, 1000);
      final reloaded = await store.loadUniverse();
      final world = reloaded.single.planets.single;
      expect(world.pendingMinerals, 0);
      expect(world.storedMinerals, 2000);
      expect(tester.takeException(), isNull);
    });
  });

  group('one price (structural)', () {
    Future<String> readLib(String path) => io.File(path).readAsString();

    test('no flat pool price in the screen or the resources card', () async {
      // A source scan is the documented exception for exactly this question:
      // the guard is that a deleted button stays deleted, and no behavior
      // test can observe an absence. Same shape as gravity_wiring_test.
      for (final path in [
        'lib/screens/planet_screen.dart',
        'lib/widgets/planet/planet_resources_card.dart',
        'lib/data/models/planet.dart',
      ]) {
        final content = await readLib(path);
        expect(content, isNot(contains('shipmentValue')),
            reason: '$path must not price the pool');
        expect(content, isNot(contains('_shipmentUnitValue')),
            reason: '$path must not carry the flat table');
      }
    });
  });
}
