import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/sector.dart';

/// Production survives a **save and reload between every tick**.
///
/// ## Why this file exists, and why it is shaped this way
///
/// `productionRemainder` is the sub-unit fraction of each tick's output, carried
/// forward so that a track earning less than one unit per tick still banks
/// something. Per-tick output is a fraction of a unit — a Volcanic ore track peaks
/// at 17.36/tick, a Glacial organics track at 0.17 — so without the carry **any
/// track under 2,880 units/day banks literally nothing, ever**.
///
/// It was not persisted. `GameTickService` re-parses the whole universe on every
/// pass (`loadUniverse()` → `Sector.fromJson`), so each planet arrived with an
/// empty remainder map and `_drawProduction` computed `floor(0 + perTick)`
/// forever. Measured across all 26 producible tracks: **13 banked exactly zero**,
/// the rest lost 6–37%, and at realistic staffing *no world type* banked a single
/// unit of organics or industrial — so no colony could self-supply even the
/// level 1→2 requirement (250 minerals / 150 organics / 100 industrial).
///
/// The reason 965 tests were green throughout is the reason this file has to
/// exist: **every existing production test holds one long-lived `Planet` across
/// all 2,880 ticks**, which is precisely the condition under which the bug cannot
/// appear. The one JSON round-trip in the planet suite was in a `setUp`, never
/// between ticks. A guard that cannot see the failure is worse than no guard,
/// because it looks like coverage.
///
/// So every test here drives the **real** path: mutate, persist, and reload the
/// evolving planet before the next tick. That is a property no single-object test
/// can assert, which is why it is worth a whole file.
void main() {
  /// One tick of the real service: mutate, then save, then reload.
  ///
  /// The reload is the whole point. Without it the remainder simply lives in
  /// memory and this file would pass against the bug it was written for.
  Planet tick(Planet w) {
    w.produce();
    return Planet.fromJson(w.toJson());
  }

  /// A colony staffed to [track]'s optimum on [type], at efficiency 1.0.
  Planet staffedAtOptimum(String type, String track) {
    final opt = planetClasses[type]!.productFor(track).optimumColonists;
    return Planet(
      name: 'Xandor',
      planetType: type,
      population: opt,
      colonistsMinerals: track == 'minerals' ? opt : 0,
      colonistsOrganics: track == 'organics' ? opt : 0,
      colonistsIndustrial: track == 'industrial' ? opt : 0,
      productionEfficiency: 1.0,
    );
  }

  int bankedOf(Planet p, String track) => switch (track) {
        'minerals' => p.storedMinerals,
        'organics' => p.storedOrganics,
        'industrial' => p.storedIndustrial,
        _ => p.storedDrones,
      };

  group('a track earning under a unit per tick still banks units', () {
    test('and does so across the real tick path', () {
      var w = staffedAtOptimum('Terran', 'organics');
      final shown = w.outputPerDayFor('organics');
      for (var i = 0; i < 2880; i++) {
        w = tick(w);
      }
      // A day's production, less the supply bill. Asserted as a *band* rather
      // than exactly: the bill is 8% of daily output and the draw lands on one
      // of three commodities, so the exact figure depends on which.
      expect(bankedOf(w, 'organics'), greaterThan(shown * 0.5),
          reason: 'shown $shown/day; a colony reloaded every tick must still '
              'bank the large majority of it');
      expect(bankedOf(w, 'organics'), lessThanOrEqualTo(shown),
          reason: 'never more than the track makes');
    });
  });

  group('every producible track banks something over a day', () {
    // The sweep that found it. A single table fails on a subset; this walks all
    // of them so a *newly added* type cannot quietly inherit the bug.
    for (final type in Planet.allTypes) {
      for (final track in PlanetClassSpec.tracks) {
        final spec = planetClasses[type]!;
        if (!spec.productFor(track).isPossible) continue;

        test('$type / $track', () {
          var w = staffedAtOptimum(type, track);
          final shown = w.outputPerDayFor(track);
          for (var i = 0; i < 2880; i++) {
            w = tick(w);
          }
          final banked = bankedOf(w, track);
          expect(banked, greaterThan(0),
              reason: 'shown $shown/day but banked nothing across 2,880 '
                  'reload-per-tick cycles \u2014 the production remainder is not '
                  'surviving the save');
          expect(banked, lessThanOrEqualTo(shown));
        });
      }
    }
  });

  group('the remainder itself round-trips', () {
    test('and is mutable, because the tick writes to it', () {
      // Two halves, and both were bugs in the making of this fix:
      //  * a `const {}` default made it unmodifiable, so the first tick threw
      //    `Cannot modify unmodifiable map` \u2014 and a mutable default *parameter*
      //    is not available either, since Dart requires default parameter values
      //    to be constant. It has to be made in an initializer list.
      //  * a `fromJson` fallback of `const {}` handed the same unmodifiable map
      //    straight back, defeating the mutable default entirely.
      final w = staffedAtOptimum('Terran', 'organics');
      final r = Planet.fromJson(w.toJson());

      expect(() => r.productionRemainder['probe'] = 0.5, returnsNormally,
          reason: 'a tick writes to this map on every produce()');
      expect(r.productionRemainder.containsKey('probe'), isTrue);
    });

    test('a fractional remainder survives the save', () {
      var w = staffedAtOptimum('Terran', 'organics');
      w.produce();
      expect(w.productionRemainder['organics'], greaterThan(0),
          reason: 'one tick at 0.74/unit leaves a fraction behind');

      final r = Planet.fromJson(w.toJson());
      expect(r.productionRemainder['organics'],
          closeTo(w.productionRemainder['organics']!, 1e-6));
    });

    test('a save with no remainder reads as empty, not as an error', () {
      // Every pre-fix save lacks the key. Starting from zero costs at most one
      // tick's fraction; inventing a value would be worse.
      final r = Planet.fromJson({
        'name': 'Xandor',
        'planetType': 'Terran',
      });
      expect(r.productionRemainder, isEmpty);
      expect(() => r.produce(), returnsNormally);
    });
  });

  group('the whole-slot path, not just a single planet', () {
    test('a reloaded Sector keeps its planets\u2019 remainders', () {
      // The unit above tests `Planet` directly. The real service round-trips a
      // **Sector**, and `Sector.fromJson` is what actually rebuilds the planets.
      // A remainder that survives its own `fromJson` but is dropped by the
      // sector's would pass everything above and still ship broken.
      final sector = Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [staffedAtOptimum('Terran', 'organics')],
      );

      var w = Sector.fromJson(sector.toJson()).planets.first;
      w.produce();
      expect(w.productionRemainder['organics'], greaterThan(0));

      // Repersist with the mutated world and reload the sector.
      final saved = Sector.fromJson(sector.toJson())..planets = [w];
      final reloaded = Sector.fromJson(saved.toJson()).planets.first;
      expect(reloaded.productionRemainder['organics'],
          closeTo(w.productionRemainder['organics']!, 1e-6));
    });
  });
}
