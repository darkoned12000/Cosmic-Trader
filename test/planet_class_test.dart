import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:flutter_test/flutter_test.dart';

/// The production and fighter tables, checked against their source.
///
/// These figures come from the TradeWars 2002 planet tables, and every one of
/// them is a *derived* value rather than a transcribed one: `maxOutputPerDay` is
/// `optimumColonists / colonistsPerUnit`, the optimum is always half the maximum,
/// and the fighter ceiling is the sum of the three products divided by a per-class
/// divisor.
///
/// That means the tables can be checked against each other without a single
/// hand-typed output figure. If any of it is wrong, one of these assertions
/// fails — which is the point of reconstructing the rule instead of the numbers.
/// It also keeps the four **derived** classes honest: they are checked against
/// the same relationships as the six sourced ones, so "we chose these" cannot
/// quietly become "these were never checked".
void main() {
  /// The published figures, keyed by class designation.
  ///
  /// Transcribed from the source tables and used only as an oracle. Nothing in
  /// `lib/` reads this map; if the model reproduces it, the model is right.
  const published = <String, int>{
    'M': 829, // Earth      8295 / 10
    'K': 682, // Desert    10240 / 15
    'O': 3733, // Ocean     56000 / 15
    'L': 1250, // Mountain  15000 / 12
    'C': 64, // Glacial     1600 / 25
    'H': 1002, // Volcanic  50100 / 50
  };

  group('every sourced class reproduces its published figures', () {
    for (final spec in planetClasses.values.where((s) => s.sourced)) {
      group('${spec.className} (Class ${spec.designation})', () {
        test('fighter ceiling', () {
          expect(spec.maxDroneOutputPerDay, published[spec.designation],
              reason: 'the class divisor for a Class '
                  '${spec.designation} no longer reproduces its table');
        });

        test('optimum is half the maximum, for every product', () {
          for (final track in PlanetClassSpec.tracks) {
            final p = spec.productFor(track);
            if (!p.isPossible) continue;
            expect(p.optimumColonists, p.maxColonists ~/ 2,
                reason: '$track optimum must be exactly half its maximum');
          }
        });

        test('each product peaks at its own optimum', () {
          // The peak of the triangle is the published maximum. If the curve were
          // flat to the maximum, or peaked somewhere else, the optimum would not
          // be producing what the table says it produces.
          for (final track in PlanetClassSpec.tracks) {
            final p = spec.productFor(track);
            if (!p.isPossible) continue;
            expect(p.outputPerDay(p.optimumColonists), p.maxOutputPerDay,
                reason: '$track does not peak at its optimum');
          }
        });
      });
    }
  });

  group('the triangle behaves as stated', () {
    // The Volcanic ore track is the one worked example the source gives in
    // prose, so it is the only curve we can check against a number that was not
    // itself computed from a ratio.
    final volcanic = planetClasses['Lava']!;
    final ore = volcanic.ore;

    test('the published worked example reproduces exactly', () {
      expect(ore.maxColonists, 100000);
      expect(ore.colonistsPerUnit, 1);
      expect(ore.outputPerDay(50000), 50000,
          reason: '"50,000 colonists in ore makes 50,000 a day"');
      expect(ore.outputPerDay(55000), 45000,
          reason: '"if you have 55,000 colonists you make 45,000 ore a day"');
    });

    test('output reaches zero at the maximum', () {
      // Stated as a consequence rather than read off the table: at the maximum
      // every colonist is past the peak, so the falling limb has nothing left.
      expect(ore.outputPerDay(100000), 0);
    });

    test('the curve is symmetric about the optimum', () {
      // A property of the shape, not of any one number. It is what makes the
      // falling limb feel like a mirror of the rising one rather than an
      // arbitrary second rule.
      const optimum = 50000;
      for (final offset in [1, 100, 5000, 25000, 49999]) {
        expect(ore.outputPerDay(optimum + offset),
            ore.outputPerDay(optimum - offset),
            reason:
                '$offset colonists either side of the peak must produce the '
                'same');
      }
    });

    test('output rises monotonically to the peak', () {
      for (var c = 1; c < ore.optimumColonists; c += 977) {
        expect(
            ore.outputPerDay(c + 1), greaterThanOrEqualTo(ore.outputPerDay(c)),
            reason: 'the rising limb never falls');
      }
    });

    test('overshooting past the maximum keeps falling rather than clamping',
        () {
      // A colony handed more colonists than the track can hold should produce
      // nothing, not a negative number. The falling limb is guarded at zero.
      expect(ore.outputPerDay(ore.maxColonists + 5000), 0);
      expect(ore.outputPerDay(0), 0);
      expect(ore.outputPerDay(-100), 0);
    });
  });

  group('an impossible product produces nothing, ever', () {
    test('a Volcanic organics track is inert at any staffing', () {
      final organics = planetClasses['Lava']!.organics;
      expect(organics.isPossible, isFalse);
      for (final c in [0, 1, 1000, 50000, 1000000]) {
        expect(organics.outputPerDay(c), 0,
            reason: '$c colonists on an impossible track');
      }
      expect(organics.maxOutputPerDay, 0);
    });

    // The zero-output world these guards exist for is gone, and it is worth
    // recording what it was, because the two tables used to disagree about it and
    // **both tests were green**: `TypeMultipliers` gave it 0.6 organics, so one
    // file asserted it grew food, while the class spec gave it N-A on every
    // product, so this file asserted it produced nothing at all. One type, two
    // answers, from two tables — and the class spec is the live rule, so that is
    // the answer that shipped.
    //
    // A dead world is a worse outcome than a bad one, which is why it was removed
    // rather than rescued: a player can see a bad world and detonate it.
    test('no class is a zero-output dead end', () {
      // The guard that outlives the type. A class with every ratio at zero is
      // inert at all staffing and all Citadel levels while still charging real
      // resources per build and occupying one of three slots in a sector, so a
      // new type cannot quietly reintroduce the shape.
      for (final spec in planetClasses.values) {
        final dead = PlanetClassSpec.tracks
            .where((t) => !spec.productFor(t).isPossible)
            .length;
        expect(dead, lessThan(PlanetClassSpec.tracks.length),
            reason: '${spec.key} cannot produce any of its '
                '${PlanetClassSpec.tracks.length} commodities — it is inert');
      }
    });

    test('every sourced class has a published figure to be checked against',
        () {
      // Without this, a class whose designation is absent from `published` looks
      // up `null` and fails the fighter test with a message about the divisor
      // rather than about the missing oracle row. It failed; it just did not say
      // why, and the why is a different kind of mistake.
      for (final spec in planetClasses.values.where((s) => s.sourced)) {
        expect(published, contains(spec.designation),
            reason: 'Class ${spec.designation} (${spec.key}) is marked sourced '
                'but has no published figure in the oracle, so nothing is '
                'actually being checked for it');
      }
    });

    test('every class is in every table the screens read', () {
      // The other half of the two-tables trap. A type present in the class spec
      // and missing from one of these renders as a blank row, or a world with no
      // picture, and the only symptom is a player looking at an empty card.
      for (final key in planetClasses.keys) {
        expect(Planet.allTypes, contains(key),
            reason: '$key is not in allTypes');
        expect(Planet.typeMultipliers, contains(key),
            reason: '$key has no TypeMultipliers row');
        expect(Planet.baseStorageByType, contains(key),
            reason: '$key has no storage row');
        expect(Planet.colonistMaxByType, contains(key),
            reason: '$key has no colonist cap');
        expect(Planet.planetAtmospheres, contains(key),
            reason: '$key has no atmosphere');
        expect(Planet.imagePool, contains(key),
            reason: '$key has no image pool, so it renders no picture');
      }
    });
  });

  group('drones are derived from production, not staffed', () {
    test('the Volcanic ceiling is the sum of its tracks over its divisor', () {
      final spec = planetClasses['Lava']!;
      expect(spec.ore.maxOutputPerDay, 50000);
      expect(spec.equipment.maxOutputPerDay, 100);
      expect(spec.organics.maxOutputPerDay, 0);
      expect(
        spec.droneOutputPerDay(
          orePerDay: spec.ore.maxOutputPerDay,
          organicsPerDay: 0,
          equipmentPerDay: spec.equipment.maxOutputPerDay,
        ),
        1002,
      );
    });

    test('under-producing any track lowers the fleet', () {
      // "Then the fighter production would not be 3000, it would be lower."
      final spec = planetClasses['Lava']!;
      final full = spec.droneOutputPerDay(
        orePerDay: 50000,
        organicsPerDay: 0,
        equipmentPerDay: 100,
      );
      final halfOre = spec.droneOutputPerDay(
        orePerDay: 25000,
        organicsPerDay: 0,
        equipmentPerDay: 100,
      );
      expect(full, 1002);
      expect(halfOre, lessThan(full));
    });

    test('overstaffing every track drives the fleet toward zero', () {
      // "if you put 20k in each maybe reduce the fighter production down to 0
      // because you're 100% over optimal production." On the Volcanic ore track,
      // 100,000 colonists is the maximum and therefore zero output; pushing past
      // it must not produce a negative fleet or a negative drone count.
      final spec = planetClasses['Lava']!;
      final overshot = spec.droneOutputPerDay(
        orePerDay: spec.ore.outputPerDay(spec.ore.maxColonists),
        organicsPerDay: 0,
        equipmentPerDay:
            spec.equipment.outputPerDay(spec.equipment.maxColonists),
      );
      expect(overshot, 0,
          reason: 'a colony staffed entirely past its optimum fields no fleet');
    });

    test('drones are never negative', () {
      final spec = planetClasses['Terran']!;
      expect(
        spec.droneOutputPerDay(
            orePerDay: 0, organicsPerDay: 0, equipmentPerDay: 0),
        0,
      );
    });
  });

  group('the class table is complete', () {
    test('every world type has a class', () {
      // Otherwise a generated world silently has no production rules at all, and
      // the failure is a missing row rather than an error.
      for (final type in Planet.allTypes) {
        expect(planetClasses[type], isNotNull,
            reason: 'no class spec for world type "$type"');
      }
    });

    test('no class spec is orphaned', () {
      for (final key in planetClasses.keys) {
        expect(Planet.allTypes, contains(key),
            reason: 'class spec "$key" matches no world type');
      }
    });

    test('every class names itself consistently', () {
      for (final spec in planetClasses.values) {
        expect(spec.key, isNotEmpty);
        expect(spec.designation, isNotEmpty);
        expect(spec.className, contains(spec.designation),
            reason: '${spec.className} does not mention Class '
                '${spec.designation}');
        expect(spec.lore.trim(), isNotEmpty,
            reason: '${spec.key} has no lore, so the Planet Guide would have a '
                'blank section for it');
      }
    });

    test('a track name that is not one of the three resolves to impossible',
        () {
      // Deliberate rather than a throw: an unknown track must not silently
      // produce at the default, because "produced nothing, quietly" is the one
      // failure mode the colony card cannot show.
      for (final spec in planetClasses.values) {
        expect(spec.productFor('drones').isPossible, isFalse);
        expect(spec.productFor('nonsense').isPossible, isFalse);
      }
    });
  });
}
