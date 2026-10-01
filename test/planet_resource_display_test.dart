import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// The Resources card must show a track **working** even when its per-tick
/// output is a fraction of a unit.
///
/// Reported: "I have assigned 5000 colonists across the resources ... I
/// currently don't see the resource values moving at all and I want to make sure
/// resources are being gathered every tick even if the amount is small."
///
/// They were right, and it was not a bug in production — the production was
/// real. Per-tick output is a fraction of a unit, so `storedMinerals` moves by 1
/// only every few ticks, and `_formatNumber` compacts to one decimal so any
/// change above a thousand was invisible anyway. Measured on a Jungle world with
/// 5,000 colonists on a track: minerals 0.376/tick, organics 0.564/tick,
/// **industrial 0.075/tick**.

void main() {
  Planet colony({
    int staffed = 5000,
    double efficiency = 1.0,
    String type = 'Jungle',
  }) =>
      Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: type,
        scanned: true,
        level: 3,
        population: 20000,
        colonistsMinerals: staffed,
        colonistsOrganics: staffed,
        colonistsIndustrial: staffed,
        productionEfficiency: efficiency,
      );

  group('the measurement this was reported against', () {
    test('per-tick output really is a fraction of a unit', () {
      final p = colony();
      for (final t in ['minerals', 'organics', 'industrial']) {
        final perTick = p.perTickFor(t);
        expect(perTick, greaterThan(0),
            reason: '$t must actually be producing, or "slow" is a lie');
        expect(perTick, lessThan(1),
            reason: '$t at 5,000 colonists: the whole reason the integer '
                'figure appears frozen');
      }
      // Industrial is the worst case and worth pinning: it moves a whole unit
      // once every ~13 ticks, i.e. once every six and a half minutes.
      expect(p.perTickFor('industrial'), lessThan(0.1));
    });

    test('the integer store does not move on most ticks', () {
      final p = colony();
      var ticksWhereNothingBanked = 0;
      for (var i = 0; i < 30; i++) {
        final before = p.storedIndustrial;
        p.produce();
        if (p.storedIndustrial == before) ticksWhereNothingBanked++;
      }
      expect(ticksWhereNothingBanked, greaterThan(20),
          reason: 'if this ever stops being true the decimals are unnecessary '
              'and the display change should be reconsidered');
    });
  });

  group('storedPlusRemainder', () {
    test('moves on EVERY tick, which the integer store does not', () {
      final p = colony();
      final seen = <double>[];
      for (var i = 0; i < 10; i++) {
        p.produce();
        seen.add(p.storedPlusRemainder('industrial'));
      }
      // Strictly increasing across ten ticks — no plateaus.
      for (var i = 1; i < seen.length; i++) {
        expect(seen[i], greaterThan(seen[i - 1]),
            reason: 'tick $i did not move the displayed figure '
                '(${seen[i - 1]} -> ${seen[i]})');
      }
    });

    test('is READ-ONLY: displaying it must not bank production', () {
      // The trap this getter exists to avoid. `mineralOutput`-style getters
      // *consume* the remainder via `_drawProduction`, so a screen that used one
      // would bank production as a side effect of looking at the planet. The
      // non-consuming getter must leave the remainder untouched, and this is
      // asserted from both sides: the remainder is unchanged, AND a consuming
      // getter is shown to change it (so "nothing consumes anything" cannot make
      // this pass).
      final p = colony();
      p.produce();
      final remainderBefore = p.productionRemainder['minerals'];
      final storedBefore = p.storedMinerals;

      for (var i = 0; i < 20; i++) {
        p.storedPlusRemainder('minerals');
      }
      expect(p.productionRemainder['minerals'], remainderBefore,
          reason: 'reading the display value must not advance the carry');
      expect(p.storedMinerals, storedBefore);

      // The other half: a consuming getter DOES move it, so the assertion above
      // is not passing merely because nothing in this model consumes anything.
      final consuming = colony();
      consuming.produce();
      final before = consuming.productionRemainder['minerals'];
      for (var i = 0; i < 5; i++) {
        consuming.mineralOutput;
      }
      expect(consuming.productionRemainder['minerals'], isNot(before),
          reason: 'mineralOutput consumes the carry — if this ever stops being '
              'true, the read-only guard above is vacuous');
    });

    test('equals the stored figure plus the carried fraction', () {
      final p = colony();
      p.produce();
      for (final t in ['minerals', 'organics', 'industrial']) {
        expect(
          p.storedPlusRemainder(t),
          closeTo(p.storedFor(t) + (p.productionRemainder[t] ?? 0), 1e-9),
        );
      }
    });

    test('the fraction is always under one, so the display never double-counts',
        () {
      final p = colony();
      for (var i = 0; i < 200; i++) {
        p.produce();
        for (final t in ['minerals', 'organics', 'industrial']) {
          final frac = p.productionRemainder[t] ?? 0;
          expect(frac, greaterThanOrEqualTo(0));
          expect(frac, lessThan(1),
              reason: '$t carry must be banked before it reaches a whole unit');
        }
      }
    });
  });

  group('the formatter', () {
    // **The real formatter, not a copy.** This was a local mirror while the
    // function was private to the screen, which meant it vouched only for
    // itself: it stayed green with `_resourceBar` changed to drop the fraction
    // entirely. Consolidating the formatters into `core/number_format.dart`
    // made it importable, so the mirror is gone and the assertions below are now
    // about the shipped implementation.
    final formatStored = groupedDecimal;

    test('two decimals, always, and grouped', () {
      expect(formatStored(144), '144.00');
      expect(formatStored(1234.5), '1,234.50');
      // **Rounded, not truncated.** `144.376` is nearer `.38` than `.37`, and a
      // display that quietly floors reads as a hundredth behind at all times.
      expect(formatStored(144.376), '144.38');
      expect(formatStored(0.075), '0.08');
      // The float trap this formatter has to avoid: `1234567.99 - 1234567` is
      // `0.9899999…`, so subtracting the floor printed `1,234,567.98`. Integer
      // hundredths do not.
      expect(formatStored(1234567.99), '1,234,567.99');
    });

    test('a small track still shows movement tick to tick', () {
      final p = colony();
      final shown = <String>[];
      for (var i = 0; i < 6; i++) {
        p.produce();
        shown.add(formatStored(p.storedPlusRemainder('industrial')));
      }
      expect(shown.toSet().length, greaterThan(1),
          reason: 'six ticks of an industrial track must not render one value');
    });
  });

  group('the class table still agrees', () {
    test('every producible track has a per-tick figure under the cap', () {
      // Sanity: the fractions above are not an artefact of one world type.
      for (final type in Planet.allTypes) {
        final p = colony(type: type);
        for (final t in PlanetClassSpec.tracks) {
          final perTick = p.perTickFor(t);
          expect(perTick, greaterThanOrEqualTo(0),
              reason: '$type/$t must never be negative');
        }
      }
    });
  });

  group('the rendered card', () {
    testWidgets('does not overflow at phone width with the longer figures',
        (tester) async {
      // The two-decimal figure is roughly twice as long as the integer it
      // replaces (`144/160.0K` becomes `144.42/160.0K`), and `StatBar`'s stacked
      // layout has already had one overflow from two natural-width `Text`s in a
      // `Row` — found by rendering at 430px, not by reading the code. A long
      // store against a long cap is the worst case.
      final world = Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: 'Jungle',
        owner: FactionClass.trader,
        scanned: true,
        level: 3,
        population: 2000000,
        colonistsMinerals: 5000,
        storedMinerals: 1234567,
        storedOrganics: 999999,
        storedIndustrial: 987654,
        productionRemainder: const {
          'minerals': 0.99,
          'organics': 0.99,
          'industrial': 0.99,
        },
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

      tester.view.physicalSize = const Size(430, 2400);
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

      expect(tester.takeException(), isNull,
          reason:
              'a RenderFlex overflow throws in debug and would surface here');
      // And the long figures really are on screen, so the assertion above is not
      // passing because the card failed to build.
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.any((t) => t.startsWith('1,234,567.99/')), isTrue,
          reason: 'found ${texts.where((t) => t.contains(',')).toList()}');
    });

    testWidgets('shows the two-decimal figure, driven through the real screen',
        (tester) async {
      // **The screen, not a mirror of it.** The formatter is private, so an
      // earlier version of this file copied its logic into a local function to
      // assert on — which is a second implementation vouching for itself: it
      // passed with the real `_resourceBar` changed to drop the fraction
      // entirely. This reads the text the player actually sees.
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
        storedMinerals: 144,
        storedOrganics: 1234,
        storedIndustrial: 0,
        // The carried fraction, which is the whole point: `storedMinerals`
        // alone is 144 and would render as a static "144".
        productionRemainder: const {
          'minerals': 0.42,
          'organics': 0.5,
          'industrial': 0.075,
        },
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
          planets: [world],
        ),
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

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      // The card renders `value/cap`, so the two-decimal figure is a prefix.
      expect(texts.any((t) => t.startsWith('144.42/')), isTrue,
          reason: 'the carried fraction must reach the screen: found '
              '${texts.where((t) => t.startsWith('144')).toList()}');
      expect(texts.any((t) => t.startsWith('1,234.50/')), isTrue,
          reason: 'grouped, and rounded to two places');
      expect(texts.any((t) => t.startsWith('0.08/')), isTrue,
          reason: 'a tiny track must still show a non-zero figure');
      expect(texts.any((t) => t.startsWith('144/')), isFalse,
          reason: 'the bare integer form is the bug being fixed');
    });
  });
}
