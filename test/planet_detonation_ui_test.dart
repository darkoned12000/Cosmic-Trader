import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// Faithful storage: it re-parses on every read and actually writes.
///
/// `planet_colony_ui_test.dart`'s fake hands back one shared `List<Sector>` and
/// no-ops `saveSectors`, which is precisely why a missing write there can hide
/// itself — with one shared list the screen's and the tick's mutations are
/// always the same objects, so an unsaved mutation is structurally impossible
/// to observe. This one counts writes and re-reads from a blob, like the real
/// thing.
///
/// `saveSectors` is **not** overridden, so the real merge-and-write path runs and
/// `saveUniverse` is the only seam. Overriding the merge instead would replace
/// the mechanism under test with the test double.

/// The detonation is the only irreversible control in the game, and it shipped
/// with a dialog that could not be closed.
///
/// Two facts, one cause. `_DetonationSequence` ran its animation and stopped —
/// no `Navigator.pop`, no button, `barrierDismissible: false`. The caller then
/// `await`ed that dialog **before** `onPlayerUpdate` and `_persist`, so the
/// await never returned and the entire destruction was discarded: no write, no
/// spent detonator, and a full-screen overlay whose only exit was killing the
/// process. On the next login the world was exactly where it had been.
///
/// The ordering is the thing worth guarding. An existence test on the rule
/// passes either way, because the rule was always correct — the defect lived in
/// what the screen did with the rule's result.
/// True when the destroyed world's name is still rendered anywhere.
///
/// Reads the rendered text rather than a widget type, because the assertion is
/// about what a player can see and click on — the reported bug was a world still
/// *offered* in Sector Contents, not merely still present in a model.
bool worldStillRendered(WidgetTester tester) =>
    find.text('XANDOR').evaluate().isNotEmpty;

void main() {
  setUpAll(() async {
    final bytes = File('assets/fonts/Audiowide.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  late FaithfulUniverse storage;
  late Planet world;

  Player pilot({int detonators = 1}) => Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 1000,
        maxHull: 1000,
        shields: 1000,
        maxShields: 1000,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 100,
        credits: 5000,
        researchPoints: 0,
        faction: FactionClass.trader,
        atomicDetonators: detonators,
      );

  setUp(() {
    world = Planet(
      id: 'w-1',
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      population: 250000,
      storedMinerals: 50000,
      scanned: true,
      level: 4,
      hull: 40000,
      maxHull: 40000,
    );
    storage = FaithfulUniverse([
      Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [world],
      )
    ]);
    UniverseStorage.instanceForTest = storage;
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  /// Bounded pumps. `PlanetScreen` polls on a `Timer.periodic` and the
  /// detonation overlay animates, so `pumpAndSettle` has no quiet frame.
  Future<void> settle(WidgetTester tester, {int frames = 14}) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 80));
    }
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    Player player, {
    VoidCallback? onExitToSector,
  }) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(
        player: player,
        onPlayerUpdate: (_) {},
        worldCap: 3,
        onExitToSector: onExitToSector,
      ),
    ));
    await settle(tester);
  }

  /// Taps Destroy Planet and confirms. Returns once the overlay is up.
  Future<void> detonate(WidgetTester tester) async {
    await tester.tap(find.text('Destroy Planet'));
    await settle(tester);
    await tester.tap(find.text('Launch Detonator'));
    await settle(tester, frames: 6);
  }

  /// The world's record in storage, or null if it is **gone**.
  ///
  /// Reads from storage, not from the fixture. The screen loaded its own copy of
  /// the universe at mount, so reading the fixture would report the screen's
  /// in-memory mutation and pass even when nothing was written — the two-copies
  /// problem reaching a guard.
  ///
  /// Null is a legitimate answer now: destruction removes the record outright, so
  /// the strong assertion is that the world is *absent from disk*, not that some
  /// surviving copy has `isDestroyed` set. A lookup returning null would have
  /// thrown before, which is why this helper had to change with the rule.
  Future<Planet?> worldOnDisk() async {
    final sectors = await storage.loadUniverse();
    final matches = sectors.first.planets.where((p) => p.id == 'w-1');
    return matches.isEmpty ? null : matches.first;
  }

  /// Live-world count as storage sees it.
  Future<int> worldCountOnDisk() async =>
      (await storage.loadUniverse()).first.planets.length;

  testWidgets('the destruction is durable while the overlay is still up',
      (tester) async {
    await pumpScreen(tester, pilot());
    await detonate(tester);

    // The overlay is showing.
    expect(find.textContaining('destroyed'), findsWidgets);

    // And yet the transaction is already committed. This is the assertion the
    // old ordering could not pass: everything it checks happens *before* the
    // player dismisses anything, so an undismissable dialog cannot cost them the
    // detonation.
    expect(storage.writes, greaterThan(0),
        reason: 'the sector was written while the overlay was still up');
    expect(await worldOnDisk(), isNull,
        reason: 'the world is gone from disk, not merely flagged on it');
    expect(await worldCountOnDisk(), 0,
        reason: 'and the sector holds nothing, so it can be claimed again');
  });

  testWidgets('the detonator is spent even if the overlay is never dismissed',
      (tester) async {
    var latest = pilot();
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(
        player: latest,
        onPlayerUpdate: (p) => latest = p,
        worldCap: 3,
      ),
    ));
    await settle(tester);
    await detonate(tester);

    expect(latest.atomicDetonators, 0,
        reason: 'the item was consumed before the animation played');
  });

  testWidgets('the overlay can be closed by hand', (tester) async {
    await pumpScreen(tester, pilot());
    await detonate(tester);

    expect(find.textContaining('destroyed'), findsWidgets);
    expect(find.text('CLOSE'), findsOneWidget,
        reason: 'there is always a way out, from the first frame');

    await tester.tap(find.text('CLOSE'));
    await settle(tester);
    expect(find.text('CLOSE'), findsNothing,
        reason: 'and the button actually leaves');
  });

  testWidgets('the overlay also closes itself when the animation ends',
      (tester) async {
    await pumpScreen(tester, pilot());
    await detonate(tester);
    expect(find.text('CLOSE'), findsOneWidget);

    // The sequence is 2.8s of animation plus a 1.1s hold — about 3.9s — so the
    // pump budget has to clear it with room to spare. This failed as soon as the
    // animation was slowed from 1.5s to 2.8s for legibility, which is the useful
    // failure: the timing is a *value* the test reads, not an implicit constant.
    await settle(tester, frames: 70);
    expect(find.text('CLOSE'), findsNothing);
  });

  testWidgets('with no detonators the control is present but inert',
      (tester) async {
    await pumpScreen(tester, pilot(detonators: 0));

    expect(find.text('Destroy Planet'), findsOneWidget,
        reason: 'greyed rather than hidden, so the item has a visible purpose');

    // Asserted against the button, not the label: a greyed *label* proves nothing
    // about whether the control can be pressed.
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Destroy Planet'),
    );
    expect(button.onPressed, isNull);

    // And tapping the label does nothing at all.
    await tester.tap(find.text('Destroy Planet'));
    await settle(tester);
    expect(find.text('Launch Detonator'), findsNothing);
    expect(storage.writes, 0);
  });

  testWidgets('aborting the warning costs the detonator nothing',
      (tester) async {
    await pumpScreen(tester, pilot());
    await tester.tap(find.text('Destroy Planet'));
    await settle(tester);
    await tester.tap(find.text('Abort'));
    await settle(tester);

    expect(await worldOnDisk(), isNotNull, reason: 'the world is untouched');
    expect(await worldCountOnDisk(), 1);
    expect(storage.writes, 0, reason: 'and nothing was written');
  });

  testWidgets('closing the overlay leaves for the Sector view', (tester) async {
    var exits = 0;
    await pumpScreen(tester, pilot(), onExitToSector: () => exits++);
    await detonate(tester);

    expect(exits, 0, reason: 'not while the report is still on screen');
    await tester.tap(find.text('CLOSE'));
    await settle(tester);
    expect(exits, 1,
        reason: 'the world is gone, so this tab has nothing left to show');
  });

  testWidgets('the auto-close navigates too, not only the button',
      (tester) async {
    var exits = 0;
    await pumpScreen(tester, pilot(), onExitToSector: () => exits++);
    await detonate(tester);
    await settle(tester, frames: 70);
    expect(exits, 1, reason: 'the common path must reach the sector as well');
  });

  testWidgets('a world destroyed this way cannot be claimed again',
      (tester) async {
    // The bug the player reported: the detonation ran, the slot freed, and the
    // world was still sitting in Sector Contents — landable, and claimable. So
    // “destroyed” freed the slot without destroying anything.
    await pumpScreen(tester, pilot());
    await detonate(tester);
    await settle(tester, frames: 8);

    expect(await worldOnDisk(), isNull, reason: 'the record is gone from disk');
    expect(await worldCountOnDisk(), 0);
    expect(worldStillRendered(tester), isFalse,
        reason: 'and it is not offered as somewhere to go');
  });
  testWidgets('the overlay does not need its animation to finish',
      (tester) async {
    // The exit must not depend on an `AnimationStatusListener`. `TickerMode`
    // suspends tickers for an offstage `IndexedStack` child, and this screen
    // *is* one, because a detonation leaves for the Sector tab — so a controller
    // that never completes means a listener that never fires and a player
    // stranded behind a modal with no working dismiss.
    //
    // Driven by a real widget here, so the assertion is behavioural: no frames
    // are pumped at all, which is exactly the suspended-ticker case. A `Timer`
    // still fires without one.
    await pumpScreen(tester, pilot());
    await tester.tap(find.text('Destroy Planet'));
    await settle(tester);
    await tester.tap(find.text('Launch Detonator'));
    await settle(tester, frames: 4);

    expect(find.text('CLOSE'), findsOneWidget,
        reason: 'the report is on screen');

    // One long jump and **no** frames in between: the tickers are as close to
    // suspended as a widget test can make them, so anything waiting on an
    // animation callback never hears about it. Then a few frames purely so the
    // route can finish animating out — the pop has happened by then, and
    // `Navigator.pop` needs a frame to start the reverse transition.
    await tester.pump(const Duration(milliseconds: 4500));
    await settle(tester, frames: 6);

    expect(find.text('CLOSE'), findsNothing,
        reason: 'dismissed without a single animation frame');
  });

  testWidgets('the overlay exits exactly once', (tester) async {
    // It used to fire the exit twice: once from the overlay's `onFinished` and
    // once from a bare `onExitToSector?.call()` after the `await`, with only a
    // local flag between them — and the flag was on one path and not the other.
    var exits = 0;
    await pumpScreen(tester, pilot(), onExitToSector: () => exits++);
    await tester.tap(find.text('Destroy Planet'));
    await settle(tester);
    await tester.tap(find.text('Launch Detonator'));
    await settle(tester, frames: 4);
    await tester.tap(find.text('CLOSE'));
    await settle(tester, frames: 90);

    expect(exits, 1, reason: 'one destruction, one departure');
  });
}
