import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'support/storage_fakes.dart';

/// Storage that re-parses on every read and actually writes, because both guards
/// below depend on the screen's mutation being observable outside itself \u2014 a
/// shared-list fake makes an unwritten change indistinguishable from a written one.

/// Two defects on the Planet screen that a *widget* guard is the only thing that
/// can see, because both produce a perfectly plausible-looking screen.
void main() {
  late FaithfulUniverse storage;

  Planet world({int level = 3}) => Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: 'Jungle',
        owner: FactionClass.trader,
        scanned: true,
        level: level,
        population: 100000,
        storedMinerals: 1000,
        storedOrganics: 1000,
        storedIndustrial: 1000,
        hull: 40000,
        maxHull: 40000,
      );

  Player pilot({Map<String, int> cargo = const {'minerals': 500}}) => Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 1000,
        maxHull: 1000,
        shields: 500,
        maxShields: 500,
        cargoUsed: cargo.values.fold(0, (a, b) => a + b),
        maxCargo: 1000,
        cargoSize: 1000,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.trader,
        cargo: cargo,
      );

  Future<void> pump(WidgetTester tester, Planet planet, Player player) async {
    storage = FaithfulUniverse([
      Sector(
          id: 7,
          name: 'Kronos Reach',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [planet])
    ]);
    UniverseStorage.instanceForTest = storage;
    addTearDown(() => UniverseStorage.instanceForTest = null);
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // A **fresh key per pump**, so each iteration gets a fresh `State`.
    //
    // The screen loads the universe once, in `initState`, and deliberately never
    // re-reads: storage hands out one shared graph, so there is nothing stale to
    // re-read. `pumpWidget` with a structurally identical tree **reuses the
    // existing `State`**, so `initState` did not run again and the screen kept
    // serving the *previous* iteration's world. That used to be masked because
    // the old `_syncFromDisk` re-parsed the file every second and quietly
    // picked up the new store.
    //
    // Worth stating as its own trap: a refactor that removes needless re-reading
    // also removes an accidental source of test freshness, and the failure reads
    // as "the feature is broken" rather than "the fixture is stale".
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(
          key: UniqueKey(), player: player, onPlayerUpdate: (_) {}),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  group('the transfer log line prints the number, not the function', () {
    // `'Unloaded $_format(movedFits) $type to ...'` interpolates the *identifier*
    // `$_format` and then prints `(movedFits)` as literal text, so the log said
    // `Unloaded Closure: (int) => String(movedFits) minerals to Xandor`. It
    // compiles, the action works, the log renders \u2014 and it is nonsense.
    testWidgets('a deposit logs the formatted quantity', (tester) async {
      // Cleared first: this is a process-wide ring that outlives the test which
      // filled it, so reading it without clearing would find some earlier line.
      ActionLogProvider.global.clear();
      await pump(tester, world(), pilot());

      await tester.tap(find.text('Unload').first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final log = ActionLogProvider.global.entries
          .map((e) => e.message)
          .where((m) => m.contains('Unloaded'))
          .join(' | ');
      expect(log, isNotEmpty, reason: 'the deposit was logged at all');
      expect(log, isNot(contains('Closure')),
          reason: 'Dart interpolated the function reference');
      expect(log, isNot(contains('(movedFits)')),
          reason: 'and printed the argument name as literal text');
      // A real quantity, in the guide's own compact format.
      expect(log, matches(RegExp(r'Unloaded [\d.,]+[KM]? minerals')));
    });

    testWidgets('and so does a withdrawal', (tester) async {
      ActionLogProvider.global.clear();
      await pump(tester, world(), pilot(cargo: const {'minerals': 10}));

      await tester.tap(find.text('Load').first);
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      final log = ActionLogProvider.global.entries
          .map((e) => e.message)
          .where((m) => m.contains('Loaded'))
          .join(' | ');
      expect(log, isNotEmpty);
      expect(log, isNot(contains('Closure')));
      expect(log, isNot(contains('(movedFits)')));
    });
  });

  group('the level preview opens for every tier a world can still reach', () {
    // `levelTitles.length` is 6 and the highest *level* is also 6, so the old
    // `if (to >= length) return` rejected the 5->6 preview \u2014 a real upgrade with a
    // real cost, blocked silently with no error and nothing on screen to explain
    // why the button did nothing.
    testWidgets('a level 5 world can preview the jump to Citadel',
        (tester) async {
      await pump(tester, world(level: 5), pilot());

      // The button is live \u2014 the failure mode was the dialog never appearing.
      await tester.tap(find.text('What does this give me?'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.text('Planetary Base -> Citadel'), findsOneWidget,
          reason: 'the final upgrade has a real cost and needs a real preview');
    });

    testWidgets('and every earlier tier, one at a time', (tester) async {
      // Looped *and* re-pumped in the first version, which left a dialog on the
      // root navigator for the next iteration — and tapping a control behind an
      // open dialog silently does nothing in `flutter_test`. It reported the tier
      // as unreachable rather than the test as broken. One fresh pump per tier,
      // with the button asserted present before it is tapped.
      for (final level in [1, 2, 3, 4]) {
        await pump(tester, world(level: level), pilot());
        final button = find.text('What does this give me?');
        expect(button, findsOneWidget,
            reason: 'level $level has an upgrade button');
        await tester.tap(button);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        final from = Planet.levelTitles[level - 1];
        final to = Planet.levelTitles[level];
        expect(find.text('$from -> $to'), findsOneWidget,
            reason: 'level $level should preview $from -> $to');

        // Dismiss before the next iteration. `pumpWidget` with a structurally
        // identical tree **reuses the existing State**, so the dialog route
        // survives the re-pump — and a tap on a control behind an open dialog
        // silently does nothing in `flutter_test`, which reports the *tier* as
        // unreachable rather than the test as broken.
        await tester.tapAt(const Offset(5, 5));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 60));
        }
        expect(find.byType(AlertDialog), findsNothing,
            reason: 'the preview for level $level was dismissed');
      }
    });

    test('and the model agrees the preview exists for exactly those tiers', () {
      // The gate now asks `levelUpCost`, so the contract is worth pinning at the
      // model: null only at the cap.
      for (var level = 1; level <= Planet.levelTitles.length; level++) {
        final probe = Planet(name: 'X', planetType: 'Terran', level: level);
        final hasNext = probe.levelUpCost != null;
        expect(hasNext, level < Planet.levelTitles.length,
            reason: 'level $level ${hasNext ? 'has' : 'has no'} next tier');
      }
    });

    testWidgets('a maximum world is not offered a further tier',
        (tester) async {
      // Level 6 is the cap, so there is nothing to preview and **no button**.
      // The first version of this test tapped the button and got
      // `WidgetController._getElementPoint` on an empty finder — which reads as
      // a crash in the screen rather than the truth, which is that the control
      // correctly does not exist.
      //
      // This also means the gate inside `_showLevelPreview` is now unreachable
      // from the UI. It is kept because the method is a valid thing to call, but
      // the contract worth pinning is the one a player can observe.
      await pump(tester, world(level: 6), pilot());
      expect(find.text('What does this give me?'), findsNothing,
          reason:
              'a Citadel cannot be upgraded further, so it offers no preview');
      expect(tester.takeException(), isNull);
    });
  });
}
