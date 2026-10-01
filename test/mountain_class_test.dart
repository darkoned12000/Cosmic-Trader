import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';

// Class L (Mountain) is the seventh TradeWars class, and it was the one the
// design document had already written down — ratios 2/5/20, max 40,000,
// 1,250 drones/day — while `planet_classes.dart` had no entry for it. That is
// how a document ends up right about something the code does not have: the
// triangle table listed seven sourced classes and only six existed.
//
// These guards hold Mountain to the standard the other six already met, which
// is that the figures are *derived* rather than transcribed. One mistyped digit
// in a ratio breaks the reproduced fighter figure AND the peak relationship, so
// a wrong input shows up as a broken relationship instead of a plausible
// number.

/// Peak output for a track, which is always reached at the optimum — half of
/// the track's maximum. The triangle's whole shape is that this is a peak and
/// not a ceiling, so "the best this track can do" is the half-way figure.
int _peak(ProductSpec p) =>
    p.colonistsPerUnit == 0 ? 0 : (p.maxColonists ~/ 2) ~/ p.colonistsPerUnit;

/// The published drones/day for each of the six sourced classes.
const Map<String, int> _publishedDronesPerDay = {
  'Terran': 829, // M Earth
  'Desert': 682, // K
  'Ocean': 3733, // O
  'Mountain': 1250, // L
  'Ice': 64, // C Glacial
  'Lava': 1002, // H Volcanic
};

void main() {
  group('all six sourced classes are implemented', () {
    test('the document\'s claim of six is true of the code', () {
      final sourced =
          planetClasses.values.where((s) => s.sourced).map((s) => s.key);
      expect(sourced.toSet(), _publishedDronesPerDay.keys.toSet(),
          reason: 'the sourced set is the six TradeWars classes the game '
              'implements; a mismatch means a class was added, dropped, or '
              'mislabelled as sourced. Class U is deliberately absent \u2014 its '
              'ratios are N-A on every product, so the world it described '
              'produced nothing at all (see the dead-end guard in '
              'planet_class_test.dart).');
    });
  });

  group('Mountain is derived, not transcribed', () {
    test('its drones/day falls out of the triangle', () {
      final spec = planetClasses['Mountain']!;
      final sum =
          _peak(spec.ore) + _peak(spec.organics) + _peak(spec.equipment);
      // 10,000 + 4,000 + 1,000 = 15,000; 15,000 / 12 = 1,250.
      expect(sum, 15000,
          reason:
              'the three peaks are 10,000 / 4,000 / 1,000 at half of 40,000');
      expect(sum ~/ spec.colonistsPerDrone, _publishedDronesPerDay['Mountain']);
    });

    test('every sourced class reproduces its published figure', () {
      for (final entry in _publishedDronesPerDay.entries) {
        final spec = planetClasses[entry.key]!;
        final sum =
            _peak(spec.ore) + _peak(spec.organics) + _peak(spec.equipment);
        final derived =
            spec.colonistsPerDrone <= 0 ? 0 : sum ~/ spec.colonistsPerDrone;
        expect(derived, entry.value, reason: entry.key);
      }
    });

    test('its peak IS its published maximum, so the table cannot lie', () {
      // If `maxOutputPerDay` were something other than the peak, the drone
      // figure above would be reproducing the wrong number. Ties the two
      // halves of the model together for every product.
      for (final track in ['minerals', 'organics', 'industrial']) {
        final spec = planetClasses['Mountain']!.productFor(track);
        expect(_peak(spec), spec.maxOutputPerDay,
            reason: '$track: the documented peak is not the table maximum');
      }
    });
  });

  group('Mountain is wired into every table a world type needs', () {
    // A half-added type is worse than a missing one. `PlanetClassTuning`
    // resolves an unknown class to a private `_unknownSpec` that produces
    // *nothing at all*, and `_baseStorage` falls back to a flat 50,000 — both
    // silent, neither an error. So the check that a type is complete has to be
    // made explicitly, and `planet_class_test` already does it for the class,
    // multiplier and atmosphere tables. This covers the two the model reads
    // through fallbacks: the storage row and the image pool.
    test('storage is authored, not defaulted', () {
      final row = Planet.baseStorageByType['Mountain'];
      expect(row, isNotNull,
          reason: 'falls back to a flat [50000,50000,50000]');
      // Must agree with the spec's declared storageCap, as Desert's does. Two
      // storage tables that can disagree is the trap this pair exists to close.
      final spec = planetClasses['Mountain']!;
      expect(row![0], spec.ore.storageCap);
      expect(row[1], spec.organics.storageCap);
      expect(row[2], spec.equipment.storageCap);
    });

    test('it has images, and the files are the ones on disk', () {
      final pool = Planet.imagePool['Mountain'];
      expect(pool, isNotNull);
      expect(pool, isNotEmpty);
      // The pool holds bare filenames; the generator prefixes them. Assert the
      // convention rather than trusting it, since the orphaned pool this reuses
      // was never checked against anything.
      for (final file in pool!) {
        expect(file, matches(RegExp(r'^Mountain_World_[0-9]+\.gif$')),
            reason: '$file breaks the <Type>_World_N.gif convention every '
                'other pool follows');
      }
    });

    test('it can produce all three commodities', () {
      // `canProduce` returns TRUE for a missing multiplier row, so a type with
      // no row silently gets live steppers for tracks it cannot farm. Mountain
      // is not a harsh world — organics ratio 5 is perfectly productive — so
      // every track must be enabled.
      for (final c in ['minerals', 'organics', 'industrial', 'drones']) {
        expect(Planet(name: 'M', planetType: 'Mountain').canProduce(c), isTrue,
            reason: c);
      }
    });

    test('and its headline reads as minerals, matching its biggest peak', () {
      // The Planet Guide derives "strongest at" from `typeMultipliers`, and the
      // colony card from the triangle. Those are different tables, so this pins
      // that they agree in *direction* — otherwise the help screen tells a
      // player a world is best at something its numbers contradict.
      final peak = _peak(planetClasses['Mountain']!.ore);
      expect(peak, greaterThan(_peak(planetClasses['Mountain']!.organics)));
      expect(peak, greaterThan(_peak(planetClasses['Mountain']!.equipment)));
      expect(Planet(name: 'M', planetType: 'Mountain').dominantCommodity,
          'minerals');
    });
  });
}
