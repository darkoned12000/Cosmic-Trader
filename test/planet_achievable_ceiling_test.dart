import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';

// The colony card labels one number "max". The guard here is the property a
// player would notice if it broke: **a correctly-staffed track reaches its own
// stated maximum.** Before the fix, `_ceilingFor` read the class table's
// `maxOutputPerDay` while `outputPerDayFor` applied the colony's yield first,
// so a below-1.0 colony was told it was short of a ceiling it could never
// reach at any staffing — and the only way to close the gap was to staff past
// the optimum, which is the one move the production triangle punishes.
//
// Asserting "the ceiling is <= the class figure" would be the weak version: it
// holds for the broken number too. The relationship that matters is the one a
// player reads off the row.

Planet _colony({
  required String type,
  double efficiency = 1.0,
  int level = 1,
  int colonists = 100000,
}) {
  return Planet(
    name: 'T',
    planetType: type,
    atmosphere: Planet.planetAtmospheres[type]?.atmosphere ?? 'Unknown',
    productionEfficiency: efficiency,
    level: level,
    population: colonists,
  );
}

/// Staffs exactly one track to its optimum and leaves the others idle.
/// The workforce fields are separate rather than a map, so the caller names
/// the track.
Planet _staffedToOptimum(Planet planet, String track, int count) {
  planet.colonistsMinerals = track == 'minerals' ? count : 0;
  planet.colonistsOrganics = track == 'organics' ? count : 0;
  planet.colonistsIndustrial = track == 'industrial' ? count : 0;
  return planet;
}

void main() {
  group('a correctly-staffed track reaches the max the card shows', () {
    // Every producible track, at every efficiency the generator can roll
    // (0.5..1.5), and at the level it starts on. A level-1 colony is the case
    // that matters: developmentMultiplier is 1.00 there, so the whole yield
    // rests on the roll.
    for (final type in Planet.allTypes) {
      final spec = planetClasses[type];
      if (spec == null) continue;

      for (final efficiency in [0.5, 0.8, 1.0, 1.2, 1.5]) {
        test('$type at efficiency $efficiency', () {
          for (final track in PlanetClassSpec.tracks) {
            final product = spec.productFor(track);
            if (product.maxOutputPerDay == 0) continue; // cannot produce

            final planet = _staffedToOptimum(
                _colony(type: type, efficiency: efficiency),
                track,
                product.optimumColonists);

            final shown = planet.achievableMaxPerDayFor(track);
            final achieved = planet.outputPerDayFor(track);

            expect(shown, lessThanOrEqualTo(product.maxOutputPerDay),
                reason: 'the card may not promise more than the world can do');
            expect(achieved, shown,
                reason: 'staffed to the optimum (${product.optimumColonists}) '
                    'this track produced $achieved/day while the card showed a '
                    'max of $shown/day. A max the player cannot hit by staffing '
                    'correctly is a max that invites them to over-staff '
                    'instead.');
          }
        });
      }
    }
  });

  test('a below-1.0 yield is exactly what used to be mislabelled', () {
    // Pins the magnitude of the defect so the fix cannot quietly become a
    // rounding no-op: at efficiency 0.5 the class figure is double what the
    // colony can produce, so the old label overstated by 2x.
    final planet = _colony(type: 'Terran', efficiency: 0.5);
    final spec = planetClasses['Terran']!;
    final track = 'minerals';

    expect(planet.yieldScale, 0.5, reason: 'level 1, worst roll');
    expect(planet.achievableMaxPerDayFor(track),
        lessThan(spec.productFor(track).maxOutputPerDay),
        reason: 'the achievable ceiling must be below the class figure here');
    expect(planet.achievableMaxPerDayFor(track) * 2,
        spec.productFor(track).maxOutputPerDay,
        reason: 'the gap was a full factor of two, not a rounding detail');
  });

  test('a high-yield colony is still capped at the class ceiling', () {
    // The other direction: efficiency must never lift a colony past the cap
    // the whole triangle exists to enforce.
    final planet = _colony(type: 'Terran', efficiency: 1.5, level: 6);
    expect(planet.yieldScale, greaterThan(1.0));
    for (final track in PlanetClassSpec.tracks) {
      expect(planet.achievableMaxPerDayFor(track),
          lessThanOrEqualTo(planet.maxDailyOutputFor(track)));
    }
  });

  group('drone ceiling is derived from the achievable tracks', () {
    test('drones cannot be capped by an unreachable aggregate', () {
      final planet = _colony(type: 'Terran', efficiency: 0.5);
      // Sum the achievable per-track maxima the same way the class spec sums
      // the raw ones, and require the drone ceiling to agree.
      final expected = planet.classSpec.droneOutputPerDay(
        orePerDay: planet.achievableMaxPerDayFor('minerals'),
        organicsPerDay: planet.achievableMaxPerDayFor('organics'),
        equipmentPerDay: planet.achievableMaxPerDayFor('industrial'),
      );
      expect(planet.achievableMaxDroneOutputPerDay, expected);
      expect(planet.achievableMaxDroneOutputPerDay,
          lessThan(planet.maxDroneOutputPerDay),
          reason:
              'the class figure is built from the same three tracks at full '
              'strength, so a weak colony must not be shown it as reachable');
    });

    test('and the achievable drone ceiling is actually producible', () {
      final spec = planetClasses['Terran']!;
      // All three tracks at their optima, which is the state the class
      // drone figure describes.
      final planet = _colony(type: 'Terran', efficiency: 1.0)
        ..colonistsMinerals = spec.productFor('minerals').optimumColonists
        ..colonistsOrganics = spec.productFor('organics').optimumColonists
        ..colonistsIndustrial = spec.productFor('industrial').optimumColonists;
      final achieved = planet.classSpec.droneOutputPerDay(
        orePerDay: planet.outputPerDayFor('minerals'),
        organicsPerDay: planet.outputPerDayFor('organics'),
        equipmentPerDay: planet.outputPerDayFor('industrial'),
      );
      expect(achieved, planet.achievableMaxDroneOutputPerDay);
    });
  });
}
