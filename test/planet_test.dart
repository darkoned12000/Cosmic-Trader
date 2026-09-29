import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:flutter_test/flutter_test.dart';

/// First tests for the planet model. The file did not exist before the
/// fighters -> drones rename, which is a poor excuse for having none: the model
/// carries ~34 persisted fields, a gated level-up, a destructive `destroy`,
/// and now a key rename, so a bad decode is silent data loss.
void main() {
  group('serialisation', () {
    test('round-trips every field that matters', () {
      final original = Planet(
        name: 'Kravos',
        planetType: 'Lava',
        atmosphere: 'CO2',
        owner: FactionClass.duran,
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        isBackupHomeworld: true,
        population: 12345,
        colonistsMinerals: 3000,
        colonistsOrganics: 3001,
        colonistsIndustrial: 3002,
        colonistsDrones: 3003,
        productionEfficiency: 1.2,
        storedMinerals: 5000,
        storedOrganics: 4000,
        storedIndustrial: 3000,
        storedDrones: 2000,
        level: 4,
        defenseLevel: 4,
        shield: 8000,
        maxShield: 8000,
        hull: 20000,
        maxHull: 20000,
        productionTimer: 8,
        spawnInterval: 10,
        imagePath: 'Lava_World_2.gif',
        scanned: true,
      );

      final restored = Planet.fromJson(original.toJson());

      expect(restored.name, original.name);
      expect(restored.planetType, original.planetType);
      expect(restored.owner, FactionClass.duran);
      expect(restored.homeworldOf, FactionClass.duran);
      expect(restored.isHomeworld, isTrue);
      expect(restored.isBackupHomeworld, isTrue);
      expect(restored.population, 12345);
      expect(restored.colonistsDrones, 3003);
      expect(restored.storedDrones, 2000);
      expect(restored.maxMinerals, greaterThan(0));
      expect(restored.level, 4);
      expect(restored.defenseLevel, 4);
      expect(restored.hull, 20000);
      expect(restored.imagePath, 'Lava_World_2.gif');
      expect(restored.scanned, isTrue);
    });

    test('an unknown faction in JSON decodes to null rather than throwing', () {
      // Saves outlive balance changes; a faction that no longer exists must
      // not make the sector file unloadable.
      final restored = Planet.fromJson({
        'name': 'Nowhere',
        'planetType': 'Terran',
        'owner': 'the_former_fifth_faction',
        'homeworldOf': 'also_gone',
      });
      expect(restored.owner, isNull);
      expect(restored.homeworldOf, isNull);
    });
  });

  group('drones rename (was fighters)', () {
    test('legacy fighters keys still load, so old saves keep their colony', () {
      // The data-loss guard. `storedFighters` -> `storedDrones` is a rename of
      // a *persisted* key, and a decode that only reads the new name would
      // silently reset every existing colony to zero drones.
      final restored = Planet.fromJson({
        'name': 'Old Save',
        'planetType': 'Terran',
        'storedFighters': 777,
        'colonistsFighters': 333,
      });

      expect(restored.storedDrones, 777);
      expect(restored.colonistsDrones, 333);
    });

    test('the new key wins when a save somehow has both', () {
      // Defensive: if a hand-edited or half-migrated file carries both, the
      // current name is the one to trust.
      final restored = Planet.fromJson({
        'name': 'Both',
        'planetType': 'Terran',
        'storedFighters': 111,
        'storedDrones': 222,
        'colonistsFighters': 333,
        'colonistsDrones': 444,
      });

      expect(restored.storedDrones, 222);
      expect(restored.colonistsDrones, 444);
    });

    test('rewriting a legacy save emits only the new key', () {
      // Without this the legacy key would linger forever, because a save is
      // only ever rewritten by toJson.
      final restored = Planet.fromJson({
        'name': 'Old Save',
        'planetType': 'Terran',
        'storedFighters': 777,
        'colonistsFighters': 333,
      });
      final json = restored.toJson();

      expect(json.containsKey('storedFighters'), isFalse);
      expect(json.containsKey('colonistsFighters'), isFalse);
      expect(json['storedDrones'], 777);
      expect(json['colonistsDrones'], 333);
    });

    test('every planet type declares a drone multiplier', () {
      // The production readout dereferences this, and a missing entry silently
      // falls back to 1.0 — a type with no drones authored would look like a
      // type that averages 1.0.
      for (final type in Planet.allTypes) {
        final mults = Planet.typeMultipliers[type];
        expect(mults, isNotNull, reason: '$type has no multiplier row');
        expect(Planet.planetAtmospheres[type], isNotNull,
            reason: '$type has no atmosphere row');
        expect(Planet.imagePool[type], isNotNull,
            reason: '$type has no image pool');
        expect(mults!.drones, greaterThan(0), reason: '$type drone multiplier');
      }
    });
  });

  group('level up', () {
    /// A planet that satisfies the current level's cost, built from the
    /// static table so the fixture cannot drift from the rules.
    Planet readyToLevel() {
      final cost = Planet.levelUpCosts.first;
      return Planet(
        name: 'Test Colony',
        planetType: 'Terran',
        population: cost.requiredColonists,
        storedMinerals: cost.requiredMinerals,
        storedOrganics: cost.requiredOrganics,
        storedIndustrial: cost.requiredIndustrial,
      );
    }

    test('refuses when resources are short, and changes nothing', () {
      final planet = readyToLevel();
      planet.storedMinerals -= 1;

      expect(planet.canStartConstruction, isFalse);
      expect(planet.levelUp(), isFalse);
      expect(planet.level, 1, reason: 'a failed level-up must not advance');
      expect(
          planet.storedMinerals, Planet.levelUpCosts.first.requiredMinerals - 1,
          reason: 'a failed level-up must not consume');
    });

    test('succeeds, advances, and consumes the cost', () {
      final planet = readyToLevel();
      final before = Planet.levelUpCosts.first;

      expect(planet.levelUp(), isTrue);
      expect(planet.level, 2);
      expect(planet.storedMinerals, 0);
      expect(planet.storedOrganics, 0);
      expect(planet.storedIndustrial, 0);
      expect(planet.population, before.requiredColonists,
          reason: 'colonists are a gate, not a cost');
    });

    test('caps at level 6', () {
      final planet = readyToLevel();
      planet.level = 6;

      expect(planet.levelUpCost, isNull);
      expect(planet.canStartConstruction, isFalse);
      expect(planet.levelUp(), isFalse);
      expect(planet.level, 6);
    });

    test('a level-6 Citadel is reachable for every planet type', () {
      // This used to assert the OPPOSITE: 7 of 10 types could never reach
      // Citadel, because the colonist cap was a flat per-type number while the
      // gate demanded up to a million. The test was written to pin the broken
      // state so nobody could change a cap silently — but the state itself was
      // the defect, and a guard that forbids fixing it is a guard that outlives
      // its reason.
      //
      // The fix derives the cap from the level ([Planet.levelColonistScale]),
      // so reachability holds by construction rather than by tuning. Asserted
      // here so that changing the scale table cannot quietly reintroduce a dead
      // end for one type.
      for (final type in Planet.allTypes) {
        final atSix = Planet.levelUpCosts.last.requiredColonists;
        // The cap at the *target* level, since the gate is checked going up.
        final planet = Planet(name: 'X', planetType: type, level: 5);
        expect(planet.colonistMax, greaterThanOrEqualTo(atSix),
            reason: '$type caps at ${planet.colonistMax} on a level-5 world '
                'but the 5->6 gate needs $atSix colonists');
      }
    });

    test('the cap grows with the level', () {
      final world = Planet(name: 'X', planetType: 'Toxic');
      final atOne = world.colonistMax;

      world.level = 6;
      expect(world.colonistMax, greaterThan(atOne));
      expect(world.baseColonistMax, atOne,
          reason: 'baseColonistMax is the unlevelled figure and must not move');
    });
  });

  group('construction', () {
    Planet ready() {
      final cost = Planet.levelUpCosts.first;
      return Planet(
        name: 'Build Site',
        planetType: 'Terran',
        population: cost.requiredColonists,
        storedMinerals: cost.requiredMinerals + 5000,
        storedOrganics: cost.requiredOrganics + 5000,
        storedIndustrial: cost.requiredIndustrial + 5000,
      );
    }

    test('costs are spent at the start, not on completion', () {
      final planet = ready();
      final cost = Planet.levelUpCosts.first;

      expect(planet.startConstruction(), isTrue);
      expect(planet.storedMinerals, 5000,
          reason: 'the resources are committed the moment work begins');
      expect(planet.storedOrganics, 5000);
      expect(planet.storedIndustrial, 5000);
      expect(planet.level, 1, reason: 'not yet');
      expect(planet.isUnderConstruction, isTrue);
      expect(planet.constructionTarget, 2);
      expect(cost.requiredColonists, greaterThan(0));
    });

    test('a build is not instant: the level only lands when ticks elapse', () {
      final planet = ready();
      final ticks = Planet.constructionLengthFor(1);
      expect(ticks, greaterThan(1),
          reason: 'levelling used to be a single call with no wait at all');

      planet.startConstruction();
      for (var i = 0; i < ticks - 1; i++) {
        planet.advanceConstruction();
        expect(planet.level, 1, reason: 'finished early at tick $i');
      }
      planet.advanceConstruction();

      expect(planet.level, 2);
      expect(planet.isUnderConstruction, isFalse);
      expect(planet.constructionTarget, 0);
    });

    test('a second build cannot start while one is running', () {
      final planet = ready();
      planet.startConstruction();
      final spent = planet.storedMinerals;

      expect(planet.canStartConstruction, isFalse);
      expect(planet.startConstruction(), isFalse);
      expect(planet.storedMinerals, spent,
          reason: 'a refused build must not charge again');
    });

    test('completing a build grants defence, armour and shields', () {
      final planet = ready();
      planet.startConstruction();
      while (planet.isUnderConstruction) {
        planet.advanceConstruction();
      }

      // A Citadel defends as well as a Citadel should. Defence used to be set
      // once by the generator and never touched again, so every tier defended
      // identically and the six levels bought nothing.
      expect(planet.defenseLevel, Planet.levelDefense[2]);
      expect(planet.maxHull, Planet.levelArmour[2]);
      expect(planet.maxShield, Planet.levelShield[2]);
    });

    test('defence rises with the level', () {
      final tiers =
          [1, 2, 3, 4, 5, 6].map((l) => Planet.levelDefense[l] ?? 0).toList();
      for (var i = 1; i < tiers.length; i++) {
        expect(tiers[i], greaterThanOrEqualTo(tiers[i - 1]),
            reason: 'tier ${i + 1} defends no better than tier $i');
      }
    });

    test('time scale is applied when the build starts, not when it lands', () {
      // Halving the scale must halve the countdown that was recorded, and
      // changing the preference afterwards cannot retroactively shorten a build
      // whose resources are already spent.
      // Exact inversion is not assertable here: the base for 1->2 is 15 ticks,
      // and 15/2 rounds to 8, so 8*2 is 16. Assert monotonicity plus a factor
      // of two within a tick of slack, which is what the rule actually claims.
      final base = Planet.constructionLengthFor(1);
      final half = Planet.constructionLengthFor(1, timeScale: 0.5);
      final double_ = Planet.constructionLengthFor(1, timeScale: 2.0);
      expect(half, lessThan(base));
      expect(double_, greaterThan(base));
      expect((half - base * 0.5).abs(), lessThanOrEqualTo(1));
      expect((double_ - base * 2.0).abs(), lessThanOrEqualTo(1));

      // And the scale must be recorded, not consulted later: two builds started
      // at different scales keep their own countdowns.
      final slow = ready()..startConstruction();
      final quick = ready()..startConstruction(timeScale: 0.5);
      expect(quick.constructionTicksRemaining,
          lessThan(slow.constructionTicksRemaining));
    });

    test('instant construction is one tick, never zero', () {
      // A scale of 0 is the "I do not want to wait" preference. It must not
      // produce a zero-length build, which would divide by zero in the progress
      // getter and complete twice in the first tick.
      expect(Planet.constructionLengthFor(1, timeScale: 0), 1);
      expect(Planet.constructionLengthFor(1, timeScale: 0), greaterThan(0));
    });

    test('progress runs 0 to 1 across the build', () {
      final planet = ready();
      planet.startConstruction();
      expect(planet.constructionProgress, 0.0);

      final total = planet.constructionTotalTicks;
      for (var i = 0; i < total; i++) {
        expect(planet.constructionProgress, inInclusiveRange(0.0, 1.0));
        planet.advanceConstruction();
      }
      expect(planet.constructionProgress, 0.0,
          reason: 'a finished build is not 100% progress, it is done');
    });

    test('destroy clears a running build', () {
      // Same reasoning as the spawn timers: a corpse carrying a live countdown
      // would be granted a level by the tick for a world that no longer exists.
      final planet = ready();
      planet.startConstruction();
      planet.destroy();

      expect(planet.isUnderConstruction, isFalse);
      expect(planet.constructionTarget, 0);
    });
  });

  group('destroy', () {
    test('clears the colony, the capital, and the spawn timers', () {
      final planet = Planet(
        name: 'Kravos',
        planetType: 'Lava',
        owner: FactionClass.duran,
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        population: 12000,
        colonistsMinerals: 3000,
        colonistsDrones: 2000,
        storedMinerals: 5000,
        storedDrones: 500,
        defenseLevel: 4,
        shield: 8000,
        maxShield: 8000,
        hull: 20000,
        maxHull: 20000,
        productionTimer: 6,
        spawnInterval: 10,
      );

      planet.destroy();

      expect(planet.isDestroyed, isTrue);
      expect(planet.isHomeworld, isFalse);
      expect(planet.homeworldOf, isNull);
      expect(planet.owner, isNull);
      expect(planet.population, 0);
      expect(planet.colonistsMinerals, 0);
      expect(planet.colonistsDrones, 0);
      expect(planet.storedMinerals, 0);
      expect(planet.storedDrones, 0);
      expect(planet.defenseLevel, 0);
      expect(planet.shield, 0);
      expect(planet.hull, 0);
      // Timers matter: a corpse with a live countdown invites a future reader
      // who forgets the isDestroyed check to schedule ghost spawns.
      expect(planet.productionTimer, 0);
      expect(planet.spawnInterval, 0);
    });

    test('survives a save/load cycle still marked destroyed', () {
      // The flag is what keeps repopulation off a corpse, so losing it on
      // reload would resurrect a dead capital.
      final planet = Planet(name: 'Kravos', planetType: 'Lava')..destroy();

      expect(Planet.fromJson(planet.toJson()).isDestroyed, isTrue);
    });
  });

  group('defaults', () {
    test('requiredColonists default does not depend on how it was built', () {
      // The constructor said 1000 and fromJson said 100 for the same field.
      // Nothing reads the field today (gating uses the static table), which is
      // exactly why the drift went unnoticed.
      expect(
        Planet(name: 'A', planetType: 'Terran').requiredColonists,
        Planet.fromJson({'name': 'B', 'planetType': 'Terran'})
            .requiredColonists,
        reason: 'constructor and fromJson defaults have diverged before',
      );
    });
  });
}
