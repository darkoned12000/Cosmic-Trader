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

/// The colony workforce UI: assignment steppers, the reserve, and the
/// colony supply and the workforce lock.
class _FakeUniverse extends UniverseStorage {
  _FakeUniverse(this.sectors);
  final List<Sector> sectors;
  @override
  Future<List<Sector>> loadUniverse() async => sectors;
  @override
  Future<bool> saveSectors(List<Sector> updated) async => true;
}

/// Mirrors `PlanetScreen._formatNumber`, so an expectation is written the way a
/// player reads the number rather than as a raw integer.
String compact(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '\$n';
}

/// The tooltip on the **colonists** transfer row.
///
/// Scoped rather than "the only Tooltip on screen". The workforce steppers are
/// tooltipped too \u2014 they move colonists between the reserve and a track, and
/// a bare +/- pair does not say so \u2014 so `find.byType(Tooltip)` stopped being
/// unique and threw "Too many elements". A finder that happens to be unique is a
/// finder that will silently find a *different* tooltip the day someone adds
/// another; this one names the row it means.
Tooltip _colonistTooltip(WidgetTester tester) {
  final matches = tester
      .widgetList<Tooltip>(find.byType(Tooltip))
      .where((t) => '${t.message}'.contains('ship from'))
      .toList();
  expect(matches, hasLength(1),
      reason: 'expected exactly one colonist-supply tooltip; the workforce '
          'steppers are tooltipped as well and are not this one');
  return matches.single;
}

void main() {
  // The default test font draws every glyph as a full-width box, so text
  // measures roughly 2x too wide and a layout assertion at 430px fails for
  // reasons that have nothing to do with the layout. Load a real typeface
  // first. Audiowide is wider than the UI default, which makes the width
  // checks below slightly conservative - the right direction to err.
  setUpAll(() async {
    final bytes = File('assets/fonts/Audiowide.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  late Planet planet;
  late Sector sector;

  setUp(() {
    planet = Planet(
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      population: 10000,
      colonistsMinerals: 2000,
      colonistsOrganics: 2000,
      colonistsIndustrial: 1000,
      colonistsDrones: 1000,
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
      planet: planet,
    );
  });

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

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(1400, 2400)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(player: player(), onPlayerUpdate: (_) {}),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() {
    UniverseStorage.instanceForTest = _FakeUniverse([sector]);
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  group('layout', () {
    // A RenderFlex overflow is reported as a test failure by the framework, so
    // simply pumping at these widths is the assertion. Two real overflows were
    // found this way and neither was visible in the code: the transfers/level-up
    // row at 430px, and the shared StatBar readout beside a long label.
    for (final width in [430.0, 600.0, 900.0, 1400.0]) {
      testWidgets('lays out without overflow at ${width.toInt()}px',
          (tester) async {
        await pump(tester, size: Size(width, 2400));
        expect(find.text('Colony'), findsWidgets);
      });
    }

    testWidgets('lays out while unsupplied, at phone width', (tester) async {
      planet.storedMinerals = 0;
      planet.storedOrganics = 0;
      planet.storedIndustrial = 0;
      await pump(tester, size: const Size(430, 2400));
      // The warning is the longest string on the card and the most likely to
      // wrap. A RenderFlex overflow fails the test, so pumping is the assertion.
      expect(find.textContaining('Stores empty'), findsOneWidget);
    });
  });

  group('colonist supply tooltip', () {
    // The hops/source sentence used to live in the price cell, which made the
    // row read "5.4K / 200.0K  405cr - 9 hops from Vionis" and ellipsised the
    // part that explains *why* the price is what it is. It belongs in a bubble.
    testWidgets('the price cell is just the price', (tester) async {
      await pump(tester);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(text, isNot(contains('hops from')),
          reason:
              'the hop/source sentence belongs in the tooltip, not the row');
    });

    testWidgets('an info bubble sits beside the colonists label',
        (tester) async {
      await pump(tester);
      // Was `findsOneWidget`, reasoned as "only the colonists row has a
      // non-flat price to explain". The Supply draw row now has one too, so the
      // count is no longer the property — and it never was the right property:
      // a count cannot tell *which* row grew a bubble. The colonists bubble is
      // identified by its content instead, which is what the sibling tests below
      // already do.
      expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
      expect(_colonistTooltip(tester).message, isNotNull,
          reason: 'the colonists row must still carry its own explanation');
    });

    testWidgets(
        'the bubble explains the source, the distance and the fuel cost',
        (tester) async {
      await pump(tester);
      final tooltip = _colonistTooltip(tester);
      final message = tooltip.message as String;
      expect(message, contains('ship from'),
          reason: 'where colonists come from is the headline fact');
      expect(message, contains('cr each'));
      expect(message, contains('hops away'));
      expect(message, contains('energy'),
          reason: 'the per-shipment fuel cost is the non-obvious part');
    });

    testWidgets('the bubble names the exile rate when a capital is lost',
        (tester) async {
      // The fixture universe has no homeworlds, so the faction is an exile.
      await pump(tester);
      final message = _colonistTooltip(tester).message as String;
      expect(message, contains('exile'));
      expect(message, contains('Recapture your homeworld'),
          reason: 'the tooltip should say how to make the rate go away');
    });
  });

  group('resource readouts', () {
    // The quantity alone did not tell a player how much room a world had left,
    // which is the number their next decision depends on: a full store spills
    // the surplus into the shipment pool, so the choice is collect or reassign.
    // Asserted on the rendered text, since a `value/max` format is exactly the
    // sort of thing a refactor can quietly drop.
    testWidgets('each store shows quantity against its own cap',
        (tester) async {
      // Empty the stores so the expected figure is unambiguous; the setUp
      // fixture deliberately starts part-full.
      planet
        ..storedMinerals = 0
        ..storedOrganics = 0
        ..storedIndustrial = 0
        ..storedDrones = 0;
      await pump(tester);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      // The three production rows carry two decimals now, so an empty store
      // reads `0.00` rather than `0`. Asserted as exact row strings rather than
      // substrings: `0.00/80.0K` *contains* `0/80.0K`, so a substring check
      // cannot tell the minerals row from a row that borrowed the wrong cap.
      final rows = text.split('|').toSet();
      expect(rows, contains('0.00/${compact(planet.maxMinerals)}'));
      expect(rows, contains('0.00/${compact(planet.maxOrganics)}'));
      expect(rows, contains('0.00/${compact(planet.maxIndustrial)}'));
      expect(rows, contains('0/${compact(planet.maxDrones)}'));
    });

    testWidgets('drones are shown against the drone cap, not the mineral one',
        (tester) async {
      planet.storedDrones = 0;
      await pump(tester);
      expect(planet.maxDrones, planet.maxMinerals ~/ 4);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      final rows = text.split('|').toSet();
      expect(rows, contains('0/${compact(planet.maxDrones)}'));
      // Exact row, not a substring: the minerals row reads `0.00/80.0K`, which
      // *contains* `0/80.0K`, so a substring form of this assertion failed for a
      // reason that had nothing to do with the drone row.
      expect(rows, isNot(contains('0/${compact(planet.maxMinerals)}')),
          reason: 'the drone row must not borrow the mineral cap');
      expect(rows, isNot(contains('0.00/${compact(planet.maxDrones)}')),
          reason: 'nor may a production row borrow the drone cap');
    });

    testWidgets('a partially filled store shows both numbers', (tester) async {
      planet.storedMinerals = 12345;
      await pump(tester);
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      // Two decimals and grouping, which is the point of the change: a slow
      // track must be visibly moving, and `12.3K` hid every change at this size.
      expect(text, contains('12,345.00/${compact(planet.maxMinerals)}'));
    });
  });

  group('assignment', () {
    testWidgets('the reserve is what is not on a track', (tester) async {
      await pump(tester);
      // 6,000 assigned across the three production tracks. The fixture still
      // sets `colonistsDrones`, and it is deliberately *ignored*: drones stopped
      // being a workforce track and are derived from output, so colonists on
      // that track are in the reserve and available for real work.
      expect(planet.assignedColonists, 5000);
      expect(planet.reserveColonists, 5000);
      expect(
          planet.assignedColonists + planet.reserveColonists, planet.population,
          reason: 'the two must always account for every colonist');
    });

    testWidgets('a non-owner cannot reassign the workforce', (tester) async {
      planet.owner = FactionClass.duran;
      await pump(tester);
      // The rival faction's steppers are not offered at all.
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.textContaining('not yours to reassign'), findsOneWidget);
    });

    testWidgets('a full reserve disables the add stepper', (tester) async {
      // 5,000 colonists, all 5,000 committed across the three production tracks.
      // The population drops from 6,000 because drones are no longer a track, so
      // the fixture's old 1,000 drone colonists are in the reserve and would
      // leave room to assign. The point of the test is a *full* reserve, so the
      // population has to actually be fully committed.
      planet
        ..population = 5000
        ..colonistsMinerals = 2000
        ..colonistsOrganics = 2000
        ..colonistsIndustrial = 1000;
      expect(planet.reserveColonists, 0);
      await pump(tester);

      // Every add stepper must be rendered but disabled.
      final adds = find.byIcon(Icons.add);
      expect(adds, findsNWidgets(3),
          reason:
              'one add stepper per production track — three, because drones '
              'are derived rather than staffed');
      final inks =
          find.ancestor(of: adds.first, matching: find.byType(InkWell));
      expect(inks.first, findsOneWidget, reason: 'the stepper is a button');
      final ink = tester.widget<InkWell>(inks.first);
      expect(ink.onTap, isNull,
          reason: 'a full reserve means no colonists left to assign, so the '
              'add stepper must be dead rather than accepting a no-op tap');
    });

    testWidgets('tapping add moves colonists out of the reserve',
        (tester) async {
      await pump(tester);
      final before = planet.colonistsMinerals;
      final reserveBefore = planet.reserveColonists;

      // The first add button belongs to the Minerals row.
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      expect(planet.colonistsMinerals, greaterThan(before));
      expect(planet.reserveColonists, lessThan(reserveBefore));
      expect(
        planet.assignedColonists + planet.reserveColonists,
        planet.population,
        reason: 'assignment must never invent or destroy colonists',
      );
    });

    testWidgets('the workforce can never exceed the population',
        (tester) async {
      await pump(tester);
      // Hammer the add button past the reserve.
      for (var i = 0; i < 40; i++) {
        await tester.tap(find.byIcon(Icons.add).first, warnIfMissed: false);
      }
      await tester.pumpAndSettle();

      expect(planet.assignedColonists, lessThanOrEqualTo(planet.population));
      expect(planet.reserveColonists, greaterThanOrEqualTo(0));
    });
  });

  group('construction panel', () {
    /// Puts the fixture planet in a state where it can pay for the next level.
    void readyToBuild() {
      final cost = Planet.levelUpCosts[planet.level - 1];
      planet
        ..population = cost.requiredColonists
        ..storedMinerals = cost.requiredMinerals + 1000
        ..storedOrganics = cost.requiredOrganics + 1000
        ..storedIndustrial = cost.requiredIndustrial + 1000;
    }

    testWidgets('offers the level gate when the world can pay', (tester) async {
      readyToBuild();
      await pump(tester);
      expect(find.text('Level Up'), findsOneWidget);
      expect(find.textContaining('Building'), findsNothing);
    });

    testWidgets('starting a build replaces the gate with progress',
        (tester) async {
      readyToBuild();
      await pump(tester);

      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      // The gate must go away, not sit beside the progress bar: it describes
      // work that has already been paid for, and leaving it up invites the
      // player to think they still have a choice.
      expect(find.text('Level Up'), findsNothing);
      expect(find.textContaining('Building'), findsOneWidget);
      expect(find.textContaining('ticks'), findsWidgets);
    });

    testWidgets('a running build cannot be started again', (tester) async {
      readyToBuild();
      await pump(tester);
      await tester.tap(find.text('Level Up'));
      await tester.pumpAndSettle();

      expect(planet.isUnderConstruction, isTrue);
      expect(find.text('Level Up'), findsNothing);
    });

    testWidgets('lays out the progress panel at phone width', (tester) async {
      // A RenderFlex overflow fails the test, so simply pumping is the check.
      // The panel is a different widget tree from the gate it replaces, so it
      // needs its own pass at 430px.
      readyToBuild();
      planet.startConstruction();
      await pump(tester, size: const Size(430, 2400));
      expect(find.textContaining('Building'), findsOneWidget);
    });

    testWidgets('lays out the progress panel at desktop width', (tester) async {
      readyToBuild();
      planet.startConstruction();
      await pump(tester, size: const Size(1400, 2400));
      expect(find.textContaining('Building'), findsOneWidget);
    });

    testWidgets('the countdown is reported in ticks, not an ETA',
        (tester) async {
      // An "ETA" in hours would quietly lie every time the player closed the
      // game, because nothing ticks while they are away. Ticks are what the
      // player can actually affect.
      readyToBuild();
      planet.startConstruction();
      await pump(tester);
      expect(find.textContaining('game tick'), findsOneWidget);
      expect(find.textContaining('while you are'), findsOneWidget);
    });
  });

  group('level preview', () {
    void readyToBuild() {
      final cost = Planet.levelUpCosts[planet.level - 1];
      planet
        ..population = cost.requiredColonists
        ..storedMinerals = cost.requiredMinerals + 1000
        ..storedOrganics = cost.requiredOrganics + 1000
        ..storedIndustrial = cost.requiredIndustrial + 1000;
    }

    testWidgets('a link sits under the Level Up button', (tester) async {
      readyToBuild();
      await pump(tester);
      expect(find.text('What does this give me?'), findsOneWidget);
    });

    testWidgets('opens on the next tier, not the whole table', (tester) async {
      // The design decision: a player at a gate wants the *change*, which a
      // six-row table cannot show. Asserting the current tier is named and the
      // top tier is not keeps the popup from quietly growing into a reference
      // screen that duplicates the Planet Guide.
      readyToBuild();
      await pump(tester);
      await tester.tap(find.text('What does this give me?'));
      await tester.pumpAndSettle();

      expect(find.text('Outpost -> Settlement'), findsOneWidget);
      expect(find.textContaining('Citadel'), findsNothing);
    });

    testWidgets('shows the benefit as a before -> after delta', (tester) async {
      readyToBuild();
      await pump(tester);
      await tester.tap(find.text('What does this give me?'));
      await tester.pumpAndSettle();

      expect(find.text('Defence'), findsOneWidget);
      // A level-1 Outpost has no defence and no shields; Settlement grants
      // light. Two 'none' values, one per row that starts from nothing.
      expect(find.text('none'), findsNWidgets(2));
      expect(find.text('light'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_right_alt_rounded), findsNWidgets(5),
          reason: 'one arrow per delta row, and a row without a "before" would '
              'not need one');
    });

    testWidgets('puts the new population cap beside the gate it must clear',
        (tester) async {
      // This pairing is the reason the popup exists: a multiplier means nothing
      // without the number, and the number means nothing without the gate.
      readyToBuild();
      await pump(tester);
      await tester.tap(find.text('What does this give me?'));
      await tester.pumpAndSettle();

      expect(find.text('New population cap'), findsOneWidget);
      expect(find.text('Needed for this level'), findsOneWidget);
    });

    testWidgets('points at the Planet Guide for the full table',
        (tester) async {
      readyToBuild();
      await pump(tester);
      await tester.tap(find.text('What does this give me?'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Planet Guide'), findsWidgets);
    });

    testWidgets('lays out the dialog at phone width', (tester) async {
      readyToBuild();
      await pump(tester, size: const Size(430, 2400));
      await tester.tap(find.text('What does this give me?'));
      await tester.pumpAndSettle();
      // A RenderFlex overflow fails the test, so pumping is the assertion.
      expect(find.text('What does this give me?'), findsOneWidget);
    });

    testWidgets('is absent while a build is running', (tester) async {
      // The gate is gone during a build, so its help link goes with it: a
      // "what do I get" dialog for a level already paid for is noise.
      readyToBuild();
      planet.startConstruction();
      await pump(tester);
      expect(find.text('What does this give me?'), findsNothing);
    });
  });

  group('world selector', () {
    /// Replaces the single-world fixture with a multi-world sector.
    void useThreeWorlds() {
      planet = Planet(
        name: 'Marek',
        planetType: 'Lava',
        owner: FactionClass.trader,
        population: 40000,
        colonistsMinerals: 20000,
        storedMinerals: 5100,
        storedOrganics: 5000,
        storedIndustrial: 5000,
        scanned: true,
      );
      final second = Planet(
        name: 'Thalassa',
        planetType: 'Ocean',
        owner: FactionClass.trader,
        population: 120000,
        colonistsMinerals: 60000,
        storedMinerals: 6200,
        storedOrganics: 5000,
        storedIndustrial: 5000,
        scanned: true,
      );
      final third = Planet(
        name: 'Aurelia',
        planetType: 'Terran',
        owner: FactionClass.trader,
        population: 250000,
        colonistsMinerals: 125000,
        storedMinerals: 7300,
        storedOrganics: 5000,
        storedIndustrial: 5000,
        scanned: true,
      );
      sector = Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [planet, second, third],
      );
      // The fake universe captured the original sector in setUp, so replacing
      // the local is not enough — the screen loads from the fake.
      UniverseStorage.instanceForTest = _FakeUniverse([sector]);
    }

    testWidgets('lists every world in the sector', (tester) async {
      useThreeWorlds();
      await pump(tester);
      expect(find.text('Worlds in this sector'), findsOneWidget);
      expect(find.text('Marek'), findsWidgets);
      expect(find.text('Thalassa'), findsOneWidget);
      expect(find.text('Aurelia'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('tapping a chip switches the whole screen to that world',
        (tester) async {
      useThreeWorlds();
      await pump(tester);
      expect(find.text('Thalassa'), findsOneWidget);

      // Each world has a distinct mineral store (5.1K / 6.2K / 7.3K), so the
      // body can be identified by a value only one world produces. Asserting
      // a tap changed *something* is not enough — the chip and the body both
      // show the name, so a name assertion cannot tell them apart.
      // Populations render as standalone text (40.0K / 120.0K / 250.0K).
      // The stores do **not**: the resources card concatenates them into
      // "5.1K/1.0M", so a `find.text('5.1K')` would never match and the
      // assertion would fail for a formatting reason rather than a layout one.
      expect(find.text('40.0K'), findsWidgets,
          reason: 'first world is showing');
      expect(find.text('250.0K'), findsNothing,
          reason: 'a body field from a world that is not selected');

      await tester.tap(find.text('Aurelia'));
      await tester.pumpAndSettle();

      expect(find.text('250.0K'), findsWidgets,
          reason: 'the body is still showing the first world');
      expect(find.text('40.0K'), findsNothing,
          reason: 'the old world is still on screen alongside the new one');
    });

    testWidgets('a tap on an off-screen chip does not silently pass',
        (tester) async {
      // The selector is a horizontal scroller, so at a narrow width a later
      // chip can be off-screen and its tap is a no-op. Asserting the content
      // changed is the only way to know the tap landed.
      useThreeWorlds();
      await pump(tester, size: const Size(320, 2400));
      await tester.ensureVisible(find.text('Aurelia'));
      await tester.tap(find.text('Aurelia'));
      await tester.pumpAndSettle();
      expect(find.text('250.0K'), findsWidgets,
          reason: 'the chip tap did not reach the third world');
    });

    testWidgets('is absent in a single-world sector', (tester) async {
      // A one-chip selector that can only select what is already selected is
      // pure noise. Its absence is the assertion.
      await pump(tester);
      expect(find.text('Worlds in this sector'), findsNothing);
    });

    testWidgets('a destroyed world is struck through and unselectable',
        (tester) async {
      useThreeWorlds();
      sector.planets[1].destroy();
      await pump(tester);

      // Still listed, so the chips do not shift under the player's finger.
      expect(find.text('Thalassa'), findsOneWidget);
      expect(find.text('2 / 3'), findsOneWidget,
          reason: 'living count excludes the corpse');

      await tester.tap(find.text('Thalassa'));
      await tester.pumpAndSettle();
      // Selecting a corpse must not blank the screen or throw.
      expect(find.byType(FilledButton), findsWidgets);
    });

    testWidgets('lays out the selector at phone width', (tester) async {
      useThreeWorlds();
      await pump(tester, size: const Size(430, 2400));
      expect(find.text('Worlds in this sector'), findsOneWidget);
    });
  });
}
