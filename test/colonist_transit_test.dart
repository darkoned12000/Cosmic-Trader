import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'support/storage_fakes.dart';

/// Re-parses on every load, exactly like the real storage. A fake that returns
/// one shared `List<Sector>` makes a write-through bug structurally impossible
/// to observe, which is precisely how the missing-save bug hid for a release.

/// A storage double whose **write fails**, the way the real one can: it refuses
/// to merge after a failed load, and it drops a sector it cannot find. Both used
/// to be silent, so a caller could not tell "written" from "quietly dropped".

void main() {
  late Player live;
  late FaithfulUniverse store;

  Planet target({int population = 0, int level = 3}) => Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: 'Jungle',
        owner: FactionClass.trader,
        scanned: true,
        level: level,
        population: population,
        hull: 40000,
        maxHull: 40000,
      );

  List<Sector> galaxy(Planet world) => [
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
          planets: [world],
        ),
      ];

  Player pilot() => Player(
        name: 'Tester',
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

  Future<void> pump(WidgetTester tester, Planet world) async {
    store = FaithfulUniverse(galaxy(world));
    UniverseStorage.instanceForTest = store;
    addTearDown(() => UniverseStorage.instanceForTest = null);
    live = pilot();
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
  }

  Future<Planet> onDisk() async =>
      (await store.loadUniverse()).firstWhere((s) => s.id == 7).planets.first;

  Future<void> tick() async {
    final sectors = await store.loadUniverse();
    PlanetProductionService.process(sectors,
        creditFaction: FactionClass.trader);
    await store.saveUniverse(sectors);
  }

  group('the colonists allocation panel is not gated on population', () {
    testWidgets('renders on a world with zero colonists', (tester) async {
      await pump(tester, target());
      expect(find.text('Colony'), findsOneWidget,
          reason: 'an empty colony must read as empty, not as a broken panel');
      expect(find.text('Recruit'), findsOneWidget);
      // and it says so, rather than silently showing zeros as if it were a bug
      expect(find.text('Population'), findsOneWidget);
    });
  });

  group('a purchase is a shipment, not an instant edit', () {
    testWidgets('debits at order, colonists land two ticks later',
        (tester) async {
      await pump(tester, target(population: 1000));
      final creditsBefore = live.credits;

      await tester.tap(find.text('Recruit'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // Charged immediately...
      expect(live.credits, lessThan(creditsBefore));
      // ...but not on the planet yet.
      final inTransit = await onDisk();
      final sent = inTransit.colonistsInTransit;
      expect(inTransit.population, 1000,
          reason: 'credits left but colonists must not have arrived yet');
      expect(sent, greaterThan(0));
      expect(inTransit.colonistTransitTicks, Planet.colonistTransitDelayTicks);

      // The panel tells the player what is coming and when. A **determinate
      // bar**, matching the citadel-build panel: the purchase is work already
      // paid for, and a plain text row did not read as anything happening.
      expect(find.textContaining('colonists en route'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('colonist-transit-bar')), findsOneWidget);
      expect(find.textContaining('1m'), findsWidgets);

      await tick();
      final afterOne = await onDisk();
      expect(afterOne.population, 1000,
          reason: 'one tick is not the whole delay');
      expect(afterOne.colonistsInTransit, greaterThan(0),
          reason: 'the shipment is still in the air');

      await tick();
      final landed = await onDisk();
      // The headcount is captured *before* the flight, because after landing
      // `colonistsInTransit` is 0 and re-reading it here would compare the
      // arrival against itself.
      expect(landed.population, 1000 + sent);
      expect(landed.colonistsInTransit, 0);
      expect(landed.colonistTransitTicks, 0);
    });

    testWidgets('the transit row counts down, then clears', (tester) async {
      await pump(tester, target(population: 1000));
      await tester.tap(find.text('Recruit'));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      // This first half is the guard that actually bites, and it is deliberately
      // NOT the arrival. `population` is already in `_fingerprintOf`, so the tick
      // that *lands* the colonists changes that hash and repaints no matter what
      // — a guard phrased as "the row goes away at the end" therefore passes
      // against a fingerprint that knows nothing about transit at all. What only
      // the two transit fields can drive is the countdown in between: on the
      // first tick the headcount and the population are both unchanged, so a
      // hash without them leaves the label reading "1m" while the shipment is
      // thirty seconds out, and the player watches a frozen timer.
      expect(find.textContaining('1m'), findsWidgets);

      await tick();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.textContaining('30s'), findsWidgets,
          reason: 'the countdown has to move while nothing else changes');
      expect(find.textContaining('colonists en route'), findsOneWidget,
          reason: 'and the shipment is still in the air');

      await tick(); // lands
      await tester.pump(const Duration(seconds: 2));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('In transit'), findsNothing,
          reason:
              'a landed shipment must not leave a row claiming it is coming');
    });
  });

  testWidgets('a large order goes through the stepper, not just the default',
      (tester) async {
    // Reported against 2,000 colonists while every earlier guard used the
    // stepper's default of 10. The large path has its own arithmetic — the price
    // is `amount * pricePerUnit` and the charge is `(cost * sending) ~/ amount` —
    // so "it works at 10" says nothing about it.
    await pump(tester, target(population: 12000));
    final plus = find.byIcon(Icons.add_rounded);
    for (var i = 0; i < 400; i++) {
      final amounts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => int.tryParse(t.data ?? ''))
          .whereType<int>();
      if (amounts.contains(2000)) break;
      await tester.tap(plus.last);
      await tester.pump(const Duration(milliseconds: 2));
    }
    final creditsBefore = live.credits;
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final d = await onDisk();
    expect(d.colonistsInTransit, 2000,
        reason: 'the whole order must be queued, not a clamped fragment');
    expect(d.colonistTransitTicks, Planet.colonistTransitDelayTicks);
    expect(live.credits, lessThan(creditsBefore));
    expect(find.textContaining('colonists en route'), findsOneWidget);

    await tick();
    await tick();
    expect((await onDisk()).population, 14000);
  });

  testWidgets('the bar moves between ticks, not in 30-second jumps',
      (tester) async {
    // Reported: "it does 30s (1 tick) half bar gets full, then the next tick
    // finishes the bar". A bar drawn straight from `colonistTransitProgress` sits
    // still until a tick lands, because that is when the truth changes — a
    // liveness indicator that reads as frozen for 29 seconds at a time.
    await pump(tester, target(population: 12000));
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    double drawn() => tester
        .widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('colonist-transit-bar')),
        )
        .value!;

    final atStart = drawn();
    // Advance five seconds of *display* time with **no tick** — the model's own
    // `colonistTransitTicks` is unchanged throughout, which is the whole point.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final later = drawn();

    expect(later, greaterThan(atStart),
        reason: 'the bar must advance on its own between ticks');
    expect(later, lessThan(0.5),
        reason: 'five seconds into a thirty-second step is not halfway');

    // And the model is untouched by any of it — this is a drawing, not state.
    final d = await onDisk();
    expect(d.colonistTransitTicks, Planet.colonistTransitDelayTicks,
        reason: 'animating the bar must not advance the shipment');
  });

  testWidgets('a FAILED write must not hide the purchase', (tester) async {
    // The reported symptom, in one assertion: credits deducted and nothing shown.
    // `setState` used to sit *below* `await _persist(...)`, so the screen's only
    // acknowledgement of a purchase depended on a disk write landing — and the
    // real `saveSectors` has two silent exits (refuses after a failed load,
    // drops an unknown sector id) plus a `catch` that only debugPrints. A
    // purchase that happened in memory must be visible in memory.
    UniverseStorage.instanceForTest = FailingUniverse(galaxy(target()));
    addTearDown(() => UniverseStorage.instanceForTest = null);
    live = pilot();
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
    final creditsBefore = live.credits;
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(live.credits, lessThan(creditsBefore),
        reason: 'the credits still leave \u2014 that half always worked');
    expect(find.textContaining('colonists en route'), findsOneWidget,
        reason: 'a purchase the player paid for must never be invisible just '
            'because the disk write did not land');
    expect(find.byKey(const ValueKey('colonist-transit-bar')), findsOneWidget);
  });

  group('the trap this feature is built around', () {
    test('a shipment to an EMPTY world still lands', () {
      // MODEL ONLY. This drives [Planet.advanceColonistTransit] directly, so it
      // is blind to *where the caller puts the call* — moving the advance behind
      // the service's `population <= 0` skip leaves this test green. The next
      // test is the one that owns the ordering, and it is the one that fails
      // when it is wrong (verified by moving the call and watching only that
      // test go red).
      final world = target(population: 0);
      world.dispatchColonists(2000);
      expect(world.colonistsInTransit, 2000);

      var lands = 0;
      for (var i = 0; i < 10; i++) {
        lands += world.advanceColonistTransit();
        if (lands > 0) break;
      }
      expect(lands, 2000);
      expect(world.population, 2000);
    });

    test('the service agrees: a 0-population world receives its shipment',
        () async {
      final world = target(population: 0);
      world.dispatchColonists(2000);
      final sectors = galaxy(world);

      // First pass counts down only.
      PlanetProductionService.process(sectors,
          creditFaction: FactionClass.trader);
      expect(world.population, 0);

      // Second lands it. Nothing about `summary.colonies` is asserted here: it
      // counts every producing world in the sectors passed in, so the
      // 12,000-strong capital in sector 1 is in it too and says nothing about
      // whether Xandor was skipped — which is the whole question.
      PlanetProductionService.process(sectors,
          creditFaction: FactionClass.trader);
      expect(world.population, 2000);
      expect(world.colonistsInTransit, 0);
    });

    test('an arrival is not swallowed by the "nothing happened" summary', () {
      // `isQuiet` gates the tick's own log line and keys off `colonies`. An
      // arrival on a world with no colony yet contributes nothing to `colonies`,
      // so a summary that ignored arrivals would report silence for the one
      // colony event the player spent money to cause.
      expect(const PlanetProductionSummary(colonistsArrived: 2000).isQuiet,
          isFalse);
      expect(const PlanetProductionSummary().isQuiet, isTrue,
          reason: 'a genuinely idle galaxy is still quiet');
    });

    test('a stuck countdown cannot strand a paid-for shipment', () {
      final world = target(population: 0);
      world.dispatchColonists(500);
      // A save caught mid-flight with the counter already spent.
      world.colonistTransitTicks = 0;
      expect(world.advanceColonistTransit(), 500);
      expect(world.population, 500);
    });

    test('two orders in flight cannot overrun the cap', () {
      final world = target(population: 0, level: 1);
      final cap = world.colonistMax;
      final first = world.dispatchColonists(cap);
      expect(first, cap);
      // The second order sees the first one's headcount as room taken.
      expect(world.dispatchColonists(10), 0);
      world.advanceColonistTransit();
      world.advanceColonistTransit();
      expect(world.population, cap);
      expect(world.colonistsInTransit, 0);
    });

    test('the price is charged on what was sent, not what was asked', () {
      final world = target(population: 0, level: 1);
      final cap = world.colonistMax;
      final asked = cap + 1000;
      final sent = world.dispatchColonists(asked);
      expect(sent, cap);
      expect(sent, lessThan(asked));
    });
  });

  group('destroying a world', () {
    test('does not leave a shipment owed to it', () {
      final world = target(population: 100);
      world.dispatchColonists(2000);
      world.destroy();
      expect(world.colonistsInTransit, 0);
      expect(world.colonistTransitTicks, 0);
    });
  });
}
