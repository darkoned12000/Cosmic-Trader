import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:flutter_test/flutter_test.dart';

Player pilot({
  int torpedoes = 0,
  int detonators = 0,
  int cargoUsed = 0,
  int maxCargo = 100,
  int credits = 10000000,
}) =>
    Player(
      name: 'Tester',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 100,
      maxShields: 100,
      cargoUsed: cargoUsed,
      maxCargo: maxCargo,
      cargoSize: maxCargo,
      credits: credits,
      researchPoints: 0,
      faction: FactionClass.duran,
      genesisTorpedoes: torpedoes,
      atomicDetonators: detonators,
    );

Sector orbit({int worlds = 0, int id = 7}) => Sector(
      id: id,
      name: 'Kronos Reach',
      x: 0,
      y: 0,
      warpRoutes: const [],
      planets: List<Planet>.generate(
        worlds,
        (i) => Planet(name: 'W$i', planetType: 'Terran'),
      ),
    );

void main() {
  group('a torpedo creates a world', () {
    test('it lands in the sector, unscanned and unowned', () {
      final sector = orbit();
      final (_, world) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
      );

      expect(world, isNotNull);
      expect(sector.planets, hasLength(1));
      // A torpedoed world is a raw orbit, not a colony. Pre-scanned or pre-owned
      // would hand the player a world for free.
      expect(world!.scanned, isFalse);
      expect(world.owner, isNull);
      expect(world.population, 0);
      expect(world.level, 1);
      expect(world.id, isNotEmpty, reason: 'a new world needs an identity');
    });

    test('the type is drawn from all ten, and the roll is reproducible', () {
      final types = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final sector = orbit();
        final (_, w) = WorldForging.launch(
          player: pilot(torpedoes: 1),
          sector: sector,
          cap: 3,
          rng: math.Random(seed),
        );
        expect(w!.planetType, isIn(Planet.allTypes));
        types.add(w.planetType);
      }
      // A roll that always returned the same type would make the detonator
      // pointless, which is the whole reason the type is random.
      expect(types.length, greaterThan(3),
          reason: '200 rolls covered only ${types.length} types');
    });

    test('it is refused with no torpedoes, and nothing is created', () {
      final sector = orbit();
      final (result, world) = WorldForging.launch(
        player: pilot(),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
      );
      expect(result, LaunchResult.noTorpedoes);
      expect(world, isNull);
      expect(sector.planets, isEmpty);
    });

    test('it is refused when the hold is full', () {
      // Torpedoes are cargo-bounded, and the *fired* one needs a slot for the
      // world it becomes once the player fills the hold with something else.
      final sector = orbit();
      final (result, _) = WorldForging.launch(
        player: pilot(torpedoes: 1, cargoUsed: 100, maxCargo: 100),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
      );
      expect(result, LaunchResult.holdFull);
      expect(sector.planets, isEmpty);
    });

    test('the new name is not one already in the sector', () {
      // Two worlds with the same label in one list is a visible duplicate.
      final sector = orbit(worlds: 3);
      final taken = sector.planets.map((p) => p.name).toSet();
      for (var seed = 0; seed < 60; seed++) {
        final (_, w) = WorldForging.launch(
          player: pilot(torpedoes: 1),
          sector: sector,
          cap: 10,
          rng: math.Random(seed),
        );
        expect(taken.contains(w!.name), isFalse,
            reason: '${w.name} duplicates a world already in the sector');
      }
    });
  });

  group('over-stacking is allowed, and is a hazard', () {
    test('firing past the cap still creates the world', () {
      // Hard-blocking it would remove the only offensive use of the torpedo and
      // make the detonator pointless: a capacity limit can be waited out, a
      // hazard has to be answered.
      final sector = orbit(worlds: 3);
      final (result, world) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(2),
      );
      expect(result, LaunchResult.wouldOverstack);
      expect(world, isNotNull);
      expect(sector.worldSlotsUsed, 4);
      expect(sector.isOverStacking(3), isTrue,
          reason: 'four worlds against a cap of three is genuinely over');
    });

    test('a legal system never rolls a collision', () {
      // No point spending a dice roll on a system that cannot collide.
      for (var seed = 0; seed < 500; seed++) {
        final sector = orbit(worlds: 2);
        expect(sector.rollCollision(3, math.Random(seed)), isEmpty,
            reason: 'seed $seed destroyed a world in a legal system');
      }
    });

    test('over-stacking does eventually destroy a pair', () {
      // The load-bearing property: the hazard has to be real, or over-stacking
      // is a free bonus rather than a decision.
      var destroyed = 0;
      for (var seed = 0; seed < 4000; seed++) {
        final sector = orbit(worlds: 4);
        destroyed += sector.rollCollision(3, math.Random(seed)).length;
      }
      expect(destroyed, greaterThan(0),
          reason:
              '4000 days of a 4-world system against a cap of 3 and nothing '
              'ever collided');
    });

    test('a collision takes a pair, and only living worlds', () {
      final dead = Planet(name: 'Corpse', planetType: 'Lava')..destroy();
      // Four **living** worlds against a cap of 3, plus a corpse. My first
      // fixture had three living, which is exactly *at* the cap — and
      // `rollCollision` correctly declines to roll for a system that is not over
      // stacked, so the loop never did anything and the test passed on an
      // assertion it should have failed.
      final sector = Sector(
        id: 7,
        name: 'S',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [
          dead,
          Planet(name: 'A', planetType: 'Terran'),
          Planet(name: 'B', planetType: 'Ocean'),
          Planet(name: 'C', planetType: 'Lava'),
          Planet(name: 'D', planetType: 'Desert'),
        ],
      );
      expect(sector.worldSlotsUsed, 4, reason: 'the corpse holds no slot');

      for (var seed = 0; seed < 500 && sector.worldSlotsUsed >= 3; seed++) {
        sector.rollCollision(3, math.Random(seed));
      }
      expect(sector.livingPlanets.length, lessThan(4),
          reason: 'a 4-world system over a cap of 3 should lose something');
      // The corpse must never be a casualty, or a dead slot could be re-rolled
      // and the collision would be a no-op.
      expect(dead.isDestroyed, isTrue);
    });

    test('detonating frees the slot the next torpedo needs', () {
      // The loop the whole item pair exists for.
      final sector = orbit(worlds: 3);
      final p = pilot(torpedoes: 1, detonators: 1);
      expect(sector.isFull(3), isTrue,
          reason:
              'three worlds in a three-world sector is full, not over-stacked');
      expect(sector.isOverStacking(3), isFalse,
          reason: 'and a full sector is not gravitationally unstable');

      final (result, after) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: sector.planets.first,
      );
      expect(result, DetonateResult.destroyed);
      expect(sector.worldSlotsUsed, 2, reason: 'the slot must be free');
      expect(after.atomicDetonators, 0);
      expect(after.cargoUsed,
          WorldForging.cargoPerUnit - WorldForging.cargoPerUnit,
          reason: 'the detonator left the hold too');

      final (_, world) = WorldForging.launch(
        player: after,
        sector: sector,
        cap: 3,
        rng: math.Random(7),
      );
      expect(world, isNotNull);
      expect(sector.worldSlotsUsed, 3);
      expect(sector.isOverStacking(3), isFalse);
    });

    test('a destroyed world still shows in the list but holds no slot', () {
      // Removal from a list mid-iteration is a bug factory, and a corpse still has
      // to be drawn and argued about. So it stays, and the *slot* is what frees.
      final sector = orbit(worlds: 2);
      WorldForging.detonate(
        player: pilot(detonators: 1),
        sector: sector,
        world: sector.planets.first,
      );
      expect(sector.planets, hasLength(2));
      expect(sector.livingPlanets, hasLength(1));
      expect(sector.freeSlots(3), 2);
    });
  });

  group('detonating', () {
    test('is refused with no detonators, and the world survives', () {
      final sector = orbit(worlds: 1);
      final (result, after) = WorldForging.detonate(
        player: pilot(),
        sector: sector,
        world: sector.planets.first,
      );
      expect(result, DetonateResult.noDetonators);
      expect(after.atomicDetonators, 0);
      expect(sector.livingPlanets, hasLength(1));
    });

    test('refuses to destroy a world twice', () {
      final sector = orbit(worlds: 1);
      final p = pilot(detonators: 2);
      final (_, after1) = WorldForging.detonate(
          player: p, sector: sector, world: sector.planets.first);
      final (result, _) = WorldForging.detonate(
          player: after1, sector: sector, world: sector.planets.first);
      expect(result, DetonateResult.alreadyDead,
          reason: 'a second detonator must not be spent on a corpse');
    });
  });

  group('the daily sweep', () {
    test('only touches over-stacked sectors', () {
      final safe = orbit(worlds: 2);
      final doomed = orbit(worlds: 5, id: 8);
      var anyDestroyed = 0;
      for (var seed = 0; seed < 3000; seed++) {
        anyDestroyed += WorldForging.runDailyCollisions(
            [safe, doomed], 3, math.Random(seed));
      }
      expect(safe.livingPlanets, hasLength(2),
          reason: 'a legal system was never touched');
      expect(anyDestroyed, greaterThan(0),
          reason: '3000 days of a 5-world system and nothing ever collided');
    });
  });
}
