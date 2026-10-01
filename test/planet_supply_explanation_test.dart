import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// The Supply draw explanation must describe the mechanic the model implements.
///
/// The Planet Guide carried this text and had drifted: it said the bill was a
/// share of "one tick's own output" when `supplyDraw` charges a share of one
/// **day's** — wrong by a factor of `Planet.supplyInterval` (2,880). The guard
/// that existed pinned the interval and the percentage and not the base, so two
/// of three numbers were checked and the wrong one got through.
///
/// The fix is not a better sentence, it is a sentence whose numbers are read
/// from the model. These tests assert the model facts the text is built from, so
/// a retune breaks the sentence's inputs rather than leaving prose behind.
void main() {
  group('the model facts the explanation is built from', () {
    test('the interval is one game day', () {
      expect(Planet.supplyInterval, 2880);
      expect(Planet.supplyInterval, PlanetClock.ticksPerDay);
    });

    test('the bill really is a share of a DAY of output, not a tick of it', () {
      // The claim the guide got wrong. Built so the two candidates differ by
      // the interval: if `supplyDraw` were ever changed to a per-tick base, this
      // fails and the sentence beside it has to change with it.
      final p = Planet(
        id: 'w',
        name: 'Xandor',
        planetType: 'Jungle',
        scanned: true,
        level: 3,
        population: 20000,
        colonistsMinerals: 5000,
        colonistsOrganics: 5000,
        colonistsIndustrial: 5000,
        productionEfficiency: 1.0,
      );
      final perDay = p.outputPerDayFor('minerals') +
          p.outputPerDayFor('organics') +
          p.outputPerDayFor('industrial');
      final perTick = p.perTickFor('minerals') +
          p.perTickFor('organics') +
          p.perTickFor('industrial');

      expect(
          p.supplyDraw,
          (perDay * Planet.supplyShareOfOutput)
              .round()
              .clamp(1, perDay.round()),
          reason: 'the bill is a share of the DAY');
      expect(p.supplyDraw,
          greaterThan((perTick * Planet.supplyShareOfOutput * 100).round()),
          reason: 'and is nowhere near a share of one TICK — the factor the '
              'guide used to be wrong by');
    });

    test('the drawn commodities are the three the text names', () {
      expect(Planet.supplyCommodities, ['minerals', 'organics', 'industrial']);
    });

    test('an unpaid bill does not kill anyone', () {
      // "Nothing dies" is the part of the explanation a player most needs to
      // trust, and the part that is easiest to make false later. A colony with
      // nothing in store is billed, comes up short, and keeps its people.
      final p = Planet(
        id: 'w',
        name: 'Xandor',
        planetType: 'Jungle',
        scanned: true,
        level: 3,
        population: 12000,
        colonistsMinerals: 4000,
        hull: 40000,
        maxHull: 40000,
      );
      final before = p.population;
      for (var i = 0; i < Planet.supplyInterval * 2; i++) {
        p.produce();
      }
      expect(p.population, before,
          reason: 'the supply bill must never reduce the population');
      expect(p.population, greaterThan(0));
    });

    test('a colony with no output at all still has a finite, tiny bill', () {
      // The fallback branch, which the text implies ("not a fixed amount per
      // colonist") but does not state. Worth pinning: it is the branch that
      // would divide by zero if someone removed it.
      final p = Planet(
        id: 'w',
        name: 'Barren Rock',
        planetType: 'Barren',
        scanned: true,
        level: 1,
        population: 1000,
      );
      expect(p.supplyDraw, greaterThan(0));
      expect(p.supplyDraw, lessThanOrEqualTo(p.population));
    });
  });

  group('the screen text', () {
    testWidgets('the Supply draw row carries an (i) that explains it',
        (tester) async {
      await _pumpPlanet(tester);
      // The icon is the affordance the request asked for; the message is what
      // makes it worth having.
      expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
      final tips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => t.message ?? '')
          .toList();
      final supply =
          tips.firstWhere((m) => m.contains('game day'), orElse: () => '');
      expect(supply, isNotEmpty,
          reason: 'the Supply draw row needs a bubble; found '
              '${tips.map((t) => t.split('\n').first).toList()}');
      // It must state the same facts as the model.
      expect(supply, contains('${Planet.supplyInterval} ticks'));
      expect(
          supply, contains('${(Planet.supplyShareOfOutput * 100).round()}%'));
      expect(supply, contains('Nothing dies'));
      expect(supply, isNot(contains("one tick's own output")),
          reason: 'the stale claim must not survive in either surface');
    });

    testWidgets('opens on TAP, not only on hover', (tester) async {
      // The request was "hover or click". `Tooltip` shows on mouse hover for
      // free, but its default gesture trigger is a long press — so on a touch
      // screen the bubble was reachable only by a gesture nobody would guess at.
      // `TooltipTriggerMode.tap` fixes the gesture without touching hover.
      await _pumpPlanet(tester);

      // The Supply draw bubble is the first info icon on the card.
      final icon = find.byIcon(Icons.info_outline_rounded);
      expect(icon, findsWidgets);

      // **`find.textContaining`, not `find.byType(Text)`.** A shown tooltip
      // renders its message as a `RichText` in the overlay, so a `Text`-based
      // assertion reports "no tooltip" for a tooltip that is plainly open — it
      // cost a debugging round here, and the failure looked exactly like the
      // gesture not working.
      await tester.tap(icon.first);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('Nothing dies'), findsWidgets,
          reason: 'tapping the (i) must reveal the explanation, or the control '
              'is decorative on touch');
    });
  });
}

Future<void> _pumpPlanet(WidgetTester tester) async {
  final world = Planet(
    id: 'w-1',
    name: 'Xandor',
    planetType: 'Jungle',
    owner: FactionClass.trader,
    scanned: true,
    level: 3,
    population: 20000,
    colonistsMinerals: 5000,
    colonistsOrganics: 5000,
    colonistsIndustrial: 5000,
    hull: 40000,
    maxHull: 40000,
  );
  UniverseStorage.instanceForTest = FaithfulUniverse([
    Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [world]),
  ]);
  addTearDown(() => UniverseStorage.instanceForTest = null);
  tester.view.physicalSize = const Size(1400, 4000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: PlanetScreen(
      player: Player(
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
        credits: 9000000,
        energy: 500,
        maxEnergy: 500,
        researchPoints: 0,
        faction: FactionClass.trader,
      ),
      onPlayerUpdate: (_) {},
    ),
  ));
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}
