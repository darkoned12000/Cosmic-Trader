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
        nowMs: 0,
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
          nowMs: 0,
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
        nowMs: 0,
      );
      expect(result, LaunchResult.noTorpedoes);
      expect(world, isNull);
      expect(sector.planets, isEmpty);
    });

    test('a full hold is no reason to be short of a torpedo', () {
      // Torpedoes are **equipment**, not cargo: they are carried on the ship
      // rather than in the hold, so ore filling every slot must not stop a
      // launch. This replaced a guard that asserted the opposite - that a full
      // hold refuses the launch - which was true of the first implementation and
      // wrong about the item. A capacity limit a player cannot see and cannot
      // clear would read as a bug, and `cargoPerUnit` is 0 precisely so the
      // accounting is not even possible to get wrong.
      final sector = orbit();
      final (result, world) = WorldForging.launch(
        player: pilot(torpedoes: 1, cargoUsed: 100, maxCargo: 100),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        nowMs: 0,
      );
      expect(result, LaunchResult.launched);
      expect(world, isNotNull);
      expect(WorldForging.cargoPerUnit, 0,
          reason: 'the bound is the absence of one, not a small number');
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
          nowMs: 0,
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
        nowMs: 0,
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
        nowMs: 0,
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

  group('the gravity clock', () {
    // The clock is the whole mechanic. It starts the moment a sector goes over
    // the cap and a check falls due 24 hours later, so these assert *when* a
    // sector is eligible, not merely that it can lose a world.
    const day = 24 * 60 * 60 * 1000;

    test('nothing is due the moment a sector goes over', () {
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      expect(sector.destabilisedAtMs, t0,
          reason: 'the clock starts at the crossing, not before it');

      var destroyed = 0;
      for (var i = 0; i < 200; i++) {
        destroyed += WorldForging.runDueCollisions(
            [sector], 3, t0 + i * 1000, math.Random(i));
      }
      expect(destroyed, 0,
          reason: '2000 seconds is not a day; the sector has barely aged');
    });

    test('a check falls due once the clock runs out', () {
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      // One millisecond early is still early. The boundary matters: a sector
      // that is due at `t0 + day` and not at `t0 + day - 1` is exactly a clock.
      expect(
        WorldForging.runDueCollisions(
            [sector], 3, t0 + day - 1, math.Random(1)),
        0,
        reason: 'a millisecond early is still early',
      );
      // A fixed roll is unreliable on its own, so drive many sectors through
      // their due moment rather than depending on one outcome.
      var destroyed = 0;
      for (var i = 0; i < 400; i++) {
        final s = orbit(worlds: 4, id: 100 + i);
        s.reconcileStability(3, t0);
        destroyed +=
            WorldForging.runDueCollisions([s], 3, t0 + day, math.Random(i));
      }
      expect(destroyed, greaterThan(0),
          reason: '400 sectors all reached their due moment and nothing ever '
              'collided');
    });

    test('the clock is per sector, not per galaxy', () {
      // Two sectors over-stacked at different times. Checking a shared daily
      // wall-clock hour would destroy the younger one's worlds hours early.
      final old = orbit(worlds: 5, id: 20);
      final young = orbit(worlds: 5, id: 21);
      final t0 = 1000000;
      old.reconcileStability(3, t0);
      young.reconcileStability(3, t0 + day - 60000);

      // Many *distinct* sectors, one roll each. My first version reused one
      // sector 600 times at the same `nowMs`, and since a roll re-arms the clock
      // to that same instant, every call after the first found itself 0 ms past
      // its own re-arm and was never due. The test was measuring one roll, not
      // six hundred.
      var oldLost = 0;
      var youngLost = 0;
      for (var i = 0; i < 600; i++) {
        final a = orbit(worlds: 5, id: 1000 + i);
        final b = orbit(worlds: 5, id: 2000 + i);
        a.reconcileStability(3, t0);
        b.reconcileStability(3, t0 + day - 60000);
        oldLost +=
            WorldForging.runDueCollisions([a], 3, t0 + day, math.Random(i));
        youngLost +=
            WorldForging.runDueCollisions([b], 3, t0 + day, math.Random(i));
      }
      expect(oldLost, greaterThan(0),
          reason: '600 sectors all reached their due moment and not one '
              'collided');
      expect(youngLost, 0,
          reason: 'the younger sectors are a minute short of due and must not '
              'be rolled - a global daily alarm would have hit all of them');
    });

    test('a surviving check re-arms, so the hazard is daily not one-shot', () {
      // Asserted on *eligibility*, not on waiting for a dice hit, because "it
      // rolled and nothing happened" and "it was never due" are the same
      // observation. One-shot would be a trap door rather than a hazard: survive
      // the first check and the system is safe forever while it stays
      // over-stacked, and the only thing making over-stacking a decision is that
      // it stays a decision tomorrow.
      final sector = orbit(worlds: 5);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);

      WorldForging.runDueCollisions([sector], 3, t0 + day, math.Random(1));
      expect(sector.destabilisedAtMs, t0 + day,
          reason: 'a check re-arms from the moment it came due, not from the '
              'tick interval afterwards');

      // A millisecond later it is not due again, so the stamp must not move.
      WorldForging.runDueCollisions([sector], 3, t0 + day + 1, math.Random(2));
      expect(sector.destabilisedAtMs, t0 + day,
          reason: 'still inside the new day');

      // Exactly one day later it is due again. Proven by the stamp moving, which
      // happens on every due check whether or not the dice land.
      WorldForging.runDueCollisions([sector], 3, t0 + 2 * day, math.Random(3));
      expect(sector.destabilisedAtMs, t0 + 2 * day,
          reason: 'a surviving check must schedule the next one, or the hazard '
              'is one-shot and an over-stacked system is eventually safe');
    });

    test('clearing the sector below the cap cancels the clock', () {
      // The detonator is the answer to over-stacking, so a player who uses one
      // must not still be rolling hazard an hour later.
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      expect(sector.destabilisedAtMs, t0);

      WorldForging.detonate(
          player: pilot(detonators: 1),
          sector: sector,
          world: sector.planets.first);
      WorldForging.runDueCollisions([sector], 3, t0 + day, math.Random(1));

      expect(sector.destabilisedAtMs, isNull);
      expect(sector.livingPlanets, hasLength(3),
          reason: 'and nothing collided');
    });

    test('going over again after a fix starts a fresh day, not the old one',
        () {
      // The stale-clock bug this guards: a sector stabilised and then pushed over
      // again an hour later would inherit the first crossing's remaining time and
      // roll early.
      //
      // The cap itself is the lever, because a four-world sector cannot be
      // stabilised by destroying anything here — the fixture is already over a
      // cap of three, so "stabilise" and "still over-stacked" are the same state
      // and my first attempt asserted the stamp cleared when nothing had
      // changed.
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      expect(sector.destabilisedAtMs, t0,
          reason: 'four worlds against a cap of three');

      // Stabilised: a fourth slot is authorised, so nothing is over-stacked.
      sector.reconcileStability(4, t0 + day - 60000);
      expect(sector.destabilisedAtMs, isNull,
          reason: 'no longer over the cap, so the clock is cancelled');

      // Over again a minute later, under the original cap.
      final t1 = t0 + day - 60000;
      sector.reconcileStability(3, t1);
      expect(sector.destabilisedAtMs, t1,
          reason: 'a fresh crossing starts a fresh clock, not the remainder of '
              'the old one');

      var destroyed = 0;
      for (var i = 0; i < 300; i++) {
        destroyed += WorldForging.runDueCollisions(
            [sector], 2, t1 + day - 1000, math.Random(i));
      }
      expect(destroyed, 0, reason: 'a second early');
    });

    test('a stable sector is never rolled, however old it is', () {
      final sector = orbit(worlds: 2);
      final t0 = 1000000;
      var destroyed = 0;
      for (var d = 1; d <= 500; d++) {
        destroyed += WorldForging.runDueCollisions(
            [sector], 3, t0 + d * day, math.Random(d));
      }
      expect(destroyed, 0, reason: '500 days of a legal system');
      expect(sector.livingPlanets, hasLength(2));
      expect(sector.destabilisedAtMs, isNull,
          reason: 'and it never armed a clock in the first place');
    });

    test('the clock survives a save and reload', () {
      // A tick reads sectors from disk, so a stamp held only in memory is a
      // sector that re-arms on every load and never falls due.
      final sector = orbit(worlds: 4)..reconcileStability(3, 1000000);
      final restored = Sector.fromJson(sector.toJson());
      expect(restored.destabilisedAtMs, 1000000);
    });
  });
}
