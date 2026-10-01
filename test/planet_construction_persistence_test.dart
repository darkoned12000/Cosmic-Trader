import 'dart:io';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/storage_fakes.dart';

/// A universe storage fake that behaves like the real one: **a fresh object
/// graph on every load**, and a write that actually persists.
///
/// The previous fake returned the same `List<Sector>` every time and made
/// `saveSectors` a no-op. That made it structurally incapable of catching the
/// construction bug this file exists for: with one shared list, the screen's
/// mutations and the tick's mutations were always the *same objects*, so a
/// missing save could not possibly be observed. The real storage re-parses the
/// file on every call, which is precisely what makes an unsaved mutation
/// disappear.

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

  setUp(() {
    planet = Planet(
      name: 'Xandor',
      planetType: 'Lava',
      owner: FactionClass.trader,
      population: 2000,
      colonistsMinerals: 1000,
      colonistsOrganics: 500,
      colonistsIndustrial: 300,
      colonistsDrones: 200,
      storedMinerals: 5000,
      storedOrganics: 5000,
      storedIndustrial: 5000,
      storedDrones: 1000,
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
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  Player player() => Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 10,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.trader,
      );

  Future<void> mount(
    WidgetTester tester, {
    Size size = const Size(1400, 2600),
    double constructionTimeScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: PlanetScreen(
          player: player(),
          onPlayerUpdate: (_) {},
          constructionTimeScale: constructionTimeScale,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Destroys the screen's State and builds a fresh one.
  ///
  /// `pumpWidget` with an identical tree **reuses the existing State**, so
  /// `initState` — and therefore `_loadUniverse` — does not run again. A
  /// "remount" that skips the dummy frame silently asserts against the previous
  /// screen's in-memory list, which is how this file first reported level 1 on
  /// a world that was level 2 on disk.
  Future<void> remount(
    WidgetTester tester, {
    Size size = const Size(1400, 2600),
    double constructionTimeScale = 1.0,
  }) async {
    await tester
        .pumpWidget(const MaterialApp(home: Scaffold(body: Text('...'))));
    await tester.pumpAndSettle();
    await mount(tester,
        size: size, constructionTimeScale: constructionTimeScale);
  }

  /// Puts the fixture in a state where it can pay for the next level.
  void readyToBuild() {
    final cost = Planet.levelUpCosts.first;
    planet
      ..population = cost.requiredColonists
      ..storedMinerals = cost.requiredMinerals + 2000
      ..storedOrganics = cost.requiredOrganics + 2000
      ..storedIndustrial = cost.requiredIndustrial + 2000;
    store.saveSectors([sector]);
  }

  /// One game tick, exactly as the service performs it against storage.
  Future<void> gameTick() async {
    final loaded = await store.loadUniverse();
    PlanetProductionService.process(loaded);
    await store.saveSectors(loaded);
  }

  group('a running build survives leaving the screen', () {
    testWidgets('the build and the spent resources reach disk', (tester) async {
      readyToBuild();
      await mount(tester);

      expect(find.text('Level Up'), findsOneWidget);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      // The bar is on screen, so the action was accepted...
      expect(find.textContaining('Building'), findsOneWidget);

      // ...and it was written. This is the assertion that was missing: the
      // countdown lived only in the screen's copy, so the tick never saw a
      // build to advance and the tab change threw the whole thing away.
      final onDisk = (await store.loadUniverse()).first.planets.first;
      expect(onDisk.isUnderConstruction, isTrue,
          reason: 'the build was never persisted, so nothing can progress it');
      expect(onDisk.constructionTarget, 2);
      expect(onDisk.constructionTicksRemaining, greaterThan(0));
      // Resources are spent, and the spend is durable.
      expect(onDisk.storedMinerals, 2000);
    });

    testWidgets('remounting the screen still shows the build running',
        (tester) async {
      readyToBuild();
      await mount(tester);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      // Navigate away and back: the exact thing the player did. A new State
      // means a fresh loadUniverse, so only what reached disk can survive.
      await remount(tester);

      expect(find.textContaining('Building'), findsOneWidget,
          reason:
              'the build vanished on tab change and the gate came back armed');
      expect(find.text('Level Up'), findsNothing,
          reason: 'a second build could be started on top of a running one');
    });

    testWidgets('the level is still the old one after remounting',
        (tester) async {
      readyToBuild();
      await mount(tester);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();
      await remount(tester);

      final onDisk = (await store.loadUniverse()).first.planets.first;
      expect(onDisk.level, 1, reason: 'a build in progress has not completed');
      expect(onDisk.canStartConstruction, isFalse,
          reason: 'the gate must be closed while a build runs');
    });
  });

  group('the player can see the build progress without leaving', () {
    testWidgets('the bar advances as the tick runs', (tester) async {
      readyToBuild();
      await mount(tester);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      final start = (await store.loadUniverse())
          .first
          .planets
          .first
          .constructionTicksRemaining;

      // The screen polls once a second; a tick is 30s of game time but the
      // service is what decrements it, so drive the service directly and let
      // the poll pick the change up.
      await gameTick();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pumpAndSettle();

      final after = (await store.loadUniverse())
          .first
          .planets
          .first
          .constructionTicksRemaining;
      expect(after, start - 1, reason: 'the tick did not advance the build');

      // And the screen is showing the *decreased* number, not its own stale
      // copy. Before the fix the screen held a private graph that nothing else
      // mutated, so the bar sat at its starting value forever.
      // The row shows **elapsed**, not remaining, so the expected string is
      // built from the elapsed count. Asserting on `$after /` would be
      // asserting the wrong number and would not compile against the UI.
      final elapsed = start - after;
      expect(find.textContaining('$elapsed / $start ticks'), findsOneWidget,
          reason: 'the screen is still rendering its own stale countdown');
      expect(find.textContaining('0 / $start ticks'), findsNothing,
          reason: 'the bar never moved off zero');
    });

    testWidgets('the build completes and the level lands', (tester) async {
      readyToBuild();
      await mount(tester);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      final total = (await store.loadUniverse())
          .first
          .planets
          .first
          .constructionTicksRemaining;
      for (var i = 0; i < total; i++) {
        await gameTick();
      }

      final onDisk = (await store.loadUniverse()).first.planets.first;
      expect(onDisk.level, 2, reason: 'the final tick did not grant the level');
      expect(onDisk.isUnderConstruction, isFalse);
      expect(onDisk.defenseLevel, Planet.levelDefense[2],
          reason: 'completing a build is what grants the tier');

      await remount(tester);
      // The header row reads "2 Settlement", not "Level 2".
      expect(find.text('2 ${Planet.levelTitles[1]}'), findsOneWidget,
          reason: 'the completed level is not shown after a remount');
    });
  });

  group('instant construction still works', () {
    testWidgets('scale 0 completes immediately and persists', (tester) async {
      readyToBuild();
      await mount(tester, constructionTimeScale: 0.0);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      final onDisk = (await store.loadUniverse()).first.planets.first;
      expect(onDisk.level, 2);
      expect(onDisk.isUnderConstruction, isFalse);

      await remount(tester, constructionTimeScale: 0.0);
      expect(find.text('2 ${Planet.levelTitles[1]}'), findsOneWidget);
    });
  });
}
