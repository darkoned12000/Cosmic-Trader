import 'dart:io';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/storage_fakes.dart';

/// Faithful storage: re-parses on every load and really writes, so a mutation
/// that is not saved cannot be observed by accident. The old fake returned one
/// shared list with a no-op `saveSectors`, which is why a printer masquerading
/// as a transfer went unnoticed.

void main() {
  setUpAll(() async {
    final bytes = File('assets/fonts/Audiowide.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  late FaithfulUniverse store;
  late Planet planet;
  late Sector sector;
  late List<Player> seen;

  setUp(() {
    planet = Planet(
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      population: 10000,
      colonistsMinerals: 4000,
      colonistsOrganics: 3000,
      colonistsIndustrial: 2000,
      colonistsDrones: 1000,
      storedMinerals: 1000,
      storedOrganics: 2000,
      storedIndustrial: 3000,
      storedDrones: 4000,
      scanned: true,
    );
    sector = Sector(
      id: 7,
      name: 'Kronos Reach',
      x: 0,
      y: 0,
      warpRoutes: const [],
      planets: [planet],
    );
    store = FaithfulUniverse([sector]);
    UniverseStorage.instanceForTest = store;
    seen = [];
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  Player playerWith({int cargoUsed = 0, Map<String, int> cargo = const {}}) =>
      Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargoUsed: cargoUsed,
        // A small hold on purpose: the old buttons ignored it entirely, and a
        // generous one would let that defect hide.
        maxCargo: 100,
        cargoSize: 100,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.trader,
        cargo: cargo,
      );

  Future<void> pump(WidgetTester tester, Player player) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: PlanetScreen(
          player: player,
          onPlayerUpdate: seen.add,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The planet as it now stands on disk, which is the only state that counts.
  Future<Planet> onDisk() async =>
      (await store.loadUniverse()).first.planets.first;

  group('unloading moves goods out of the hold and onto the world', () {
    testWidgets('the hold empties and the store fills by the same amount',
        (tester) async {
      final player = playerWith(
        cargoUsed: 40,
        cargo: const {'minerals': 40},
      );
      await pump(tester, player);

      await tester.tap(find.text('Unload').first);
      await tester.pumpAndSettle();

      // The hold is the source of truth for what arrived. Before the fix this
      // credited 10 minerals to the world and left all 40 in the hold, i.e.
      // created them.
      final after = seen.last;
      expect(after.cargo['minerals'] ?? 0, 30,
          reason: '10 units should have left the hold');
      expect(after.cargoUsed, 30);
      expect((await onDisk()).storedMinerals, 1010,
          reason: 'the world gained exactly what the hold lost');
    });

    testWidgets('credits do not change hands', (tester) async {
      final player = playerWith(
        cargoUsed: 40,
        cargo: const {'minerals': 40},
      );
      await pump(tester, player);
      await tester.tap(find.text('Unload').first);
      await tester.pumpAndSettle();
      expect(seen.last.credits, player.credits,
          reason: 'a haul is not a purchase');
    });

    testWidgets('nothing is deposited when the hold is empty', (tester) async {
      final player = playerWith();
      await pump(tester, player);
      // The button is disabled, so a tap must be inert rather than minting goods.
      await tester.tap(find.text('Unload').first);
      await tester.pumpAndSettle();
      expect(seen, isEmpty,
          reason: 'an inert button must not produce a player update at all');
      expect((await onDisk()).storedMinerals, 1000);
    });
  });

  group('loading moves goods off the world and into the hold', () {
    testWidgets('the store empties and the hold fills by the same amount',
        (tester) async {
      await pump(tester, playerWith());
      await tester.tap(find.text('Load').first);
      await tester.pumpAndSettle();

      final after = seen.last;
      expect(after.cargo['minerals'], 10);
      expect(after.cargoUsed, 10);
      expect((await onDisk()).storedMinerals, 990);
    });

    testWidgets('the hold is a hard bound', (tester) async {
      // The whole point of a hauler. The old code had no `maxCargo` check at
      // all, so this was the one assertion that could not have existed before.
      final player = playerWith(cargoUsed: 95); // 5 slots free
      await pump(tester, player);
      await tester.tap(find.text('Load').first);
      await tester.pumpAndSettle();

      final after = seen.last;
      expect(after.cargoUsed, lessThanOrEqualTo(100),
          reason: 'loading must never exceed the hold');
      expect(after.cargo['minerals'], 5,
          reason: 'only the 5 free slots should have loaded');
      expect((await onDisk()).storedMinerals, 995);
    });

    testWidgets('drones can be loaded to be fielded, and earn nothing',
        (tester) async {
      await pump(tester, playerWith());
      // Rows are minerals, organics, industrial, drones, colonists — so the
      // drones row is the fourth `Load`.
      final loadButtons = find.text('Load');
      await tester.tap(loadButtons.at(3));
      await tester.pumpAndSettle();

      expect(seen.last.cargo['drones'], greaterThan(0),
          reason: 'drones must reach a hold to be usable in combat');
      expect(seen.last.credits, 500000,
          reason: 'drones have no cash value — they are not a commodity');
    });
  });

  group('the buttons cannot lie about the state', () {
    testWidgets('a deposit needs room on the world', (tester) async {
      // A full store must refuse an unload rather than silently spilling.
      planet.storedMinerals = planet.capFor('minerals');
      await store.saveSectors([sector]);
      await pump(
          tester, playerWith(cargoUsed: 40, cargo: const {'minerals': 40}));

      await tester.tap(find.text('Unload').first);
      await tester.pumpAndSettle();

      expect(seen, isEmpty, reason: 'a full store must refuse the unload');
      expect((await onDisk()).storedMinerals, planet.capFor('minerals'));
    });

    testWidgets('the hold count is shown on the row', (tester) async {
      // The price cell used to read "5cr" for a haul that costs nothing. It now
      // reports the hold, which is the number that bounds a deposit.
      await pump(
          tester, playerWith(cargoUsed: 25, cargo: const {'minerals': 25}));
      expect(find.textContaining('hold 25.0K'), findsNothing,
          reason: '25 formats as 25, not 25.0K');
      expect(find.textContaining('hold'), findsWidgets);
    });
  });
}
