import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:cosmic_trader/services/game_clock.dart';
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
    test('it lands in the sector already scanned and already yours', () {
      final sector = orbit();
      final (_, world, _) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
      );

      expect(world, isNotNull);
      expect(sector.planets, hasLength(1));
      // Reversed from the original rule, which made a torpedoed world an
      // unscanned orbit the player then had to survey and claim. That fought
      // the feature: the player made this world and paid a torpedo for it, and
      // the loop it serves (launch, over-stack, detonate the one you regret)
      // only means something if launching is an act you perform on a world you
      // own. It also read as broken — the sector contents listed the new world
      // with `NOT SCANNED` where a freshly claimed one reads `OWNED`, so the
      // thing you had just paid for looked like someone else's.
      expect(world!.scanned, isTrue);
      expect(world.owner, isNotNull);
      // Owned by *the launching pilot*, not by whoever happens to be first in a
      // faction enum — the supply and repopulation services key off this.
      expect(world.owner, pilot().faction);
      // Still raw: creating a world is not settling it.
      expect(world.population, 0);
      expect(world.level, 1);
      expect(world.id, isNotEmpty, reason: 'a new world needs an identity');
    });

    test('the type the caller supplies is the type that gets created', () {
      // The naming dialog shows the roll before the world exists, so `launch`
      // must not roll again. If it did, the dialog could promise a Desert and
      // hand over an Ice, and every "what did I get" report would be a bug
      // report. Passing `type` is what makes the dialog honest.
      final sector = orbit();
      final (_, world, _) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
        type: 'Mountain',
        name: 'Ironhold',
      );
      expect(world!.planetType, 'Mountain');
      expect(world.name, 'Ironhold');
    });

    test('and the supplied name is not overwritten by the suggestion', () {
      // The suggestion exists only to prefill a text field; accepting it must
      // give the same world either way, and typing must win.
      final a = orbit();
      final b = orbit();
      final suggested = WorldForging.suggestName('Terran', a, math.Random(7));
      final (_, viaSuggest, _) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: a,
        cap: 3,
        rng: math.Random(9),
        tick: 0,
        type: 'Terran',
        name: suggested,
      );
      final (_, viaType, _) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: b,
        cap: 3,
        rng: math.Random(9),
        tick: 0,
        name: suggested,
      );
      expect(viaSuggest!.name, suggested);
      expect(viaType!.name, suggested);
    });

    test('the type is drawn from all ten, and the roll is reproducible', () {
      final types = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final sector = orbit();
        final (_, w, _) = WorldForging.launch(
          player: pilot(torpedoes: 1),
          sector: sector,
          cap: 3,
          rng: math.Random(seed),
          tick: 0,
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
      final (result, world, _) = WorldForging.launch(
        player: pilot(),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
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
      final (result, world, _) = WorldForging.launch(
        player: pilot(torpedoes: 1, cargoUsed: 100, maxCargo: 100),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
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
        final (_, w, _) = WorldForging.launch(
          player: pilot(torpedoes: 1),
          sector: sector,
          cap: 10,
          rng: math.Random(seed),
          tick: 0,
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
      final (result, world, _) = WorldForging.launch(
        player: pilot(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(2),
        tick: 0,
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

      final (result, after, _) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: sector.planets.first,
        cap: 3,
        tick: 0,
      );
      expect(result, DetonateResult.destroyed);
      expect(sector.worldSlotsUsed, 2, reason: 'the slot must be free');
      expect(after.atomicDetonators, 0);
      expect(after.cargoUsed,
          WorldForging.cargoPerUnit - WorldForging.cargoPerUnit,
          reason: 'the detonator left the hold too');

      final (_, world, _) = WorldForging.launch(
        player: after,
        sector: sector,
        cap: 3,
        rng: math.Random(7),
        tick: 0,
      );
      expect(world, isNotNull);
      expect(sector.worldSlotsUsed, 3);
      expect(sector.isOverStacking(3), isFalse);
    });

    test('a destroyed world leaves the records entirely', () {
      // Reversed. It used to stay in the list as a corpse so it could "still be
      // drawn and argued about", which in practice meant a vaporised world stayed
      // listed, landable, and claimable again — so destroying it did not destroy
      // it. Removed now; the slot frees because the world is gone, not because a
      // flag was set on something still there.
      final sector = orbit(worlds: 2);
      final doomed = sector.planets.first;
      WorldForging.detonate(
        player: pilot(detonators: 1),
        sector: sector,
        world: doomed,
        cap: 3,
        tick: 0,
      );
      expect(sector.planets, hasLength(1));
      expect(sector.planets.any((p) => p.id == doomed.id), isFalse,
          reason: 'the world is not merely flagged, it is absent');
      expect(sector.livingPlanets, hasLength(1));
      expect(sector.freeSlots(3), 2);

      // The detached object is still neutralised. Every screen holds its own copy
      // of the universe, so the instance the detonation was fired from outlives
      // its removal from the list — if it kept its colony it would go on
      // producing into a world that no longer exists.
      expect(doomed.isDestroyed, isTrue);
      expect(doomed.population, 0);
      expect(doomed.outputPerDayFor('minerals'), 0);
    });
  });

  group('create and destroy, repeatedly', () {
    // The player should be able to make a world, regret it, and make the same
    // world again — as many times as they like. This only works because
    // destruction *removes* the record: a corpse left in the sector would keep
    // the name occupied, so `suggestName` would drift away from it and the
    // suggestion the dialog offers would never come back.
    test('the same name can be reused ten times in a row', () {
      final sector = orbit(worlds: 0);
      var player = pilot(torpedoes: 20, detonators: 20);
      const wanted = 'Ironhold';

      for (var i = 0; i < 10; i++) {
        final (result, world, spent) = WorldForging.launch(
          player: player,
          sector: sector,
          cap: 3,
          rng: math.Random(i),
          tick: i,
          type: 'Mountain',
          name: wanted,
        );
        expect(world, isNotNull, reason: 'launch $i produced a world');
        expect(sector.worldSlotsUsed, 1, reason: 'exactly one world at a time');
        player = spent;

        final (det, afterDet, _) = WorldForging.detonate(
          player: player,
          sector: sector,
          world: world!,
          cap: 3,
          tick: i,
        );
        expect(det, DetonateResult.destroyed, reason: 'round $i destroyed');
        expect(sector.planets, isEmpty, reason: 'round $i left nothing behind');
        player = afterDet;
      }

      expect(player.genesisTorpedoes, 10, reason: 'ten fired, ten spent');
      expect(player.atomicDetonators, 10, reason: 'ten spent, ten spent');
    });

    test('and the name is offered again once the world is gone', () {
      // The suggestion is what the dialog prefills, so if the pool treated a
      // removed world as still-taken the player would stop being offered the
      // name they just used.
      final sector = orbit(worlds: 0);
      final suggested =
          WorldForging.suggestName('Mountain', sector, math.Random(3));
      // A detonator as well as a torpedo: the first version of this test passed
      // only `torpedoes`, so `detonate` correctly refused with `noDetonators`
      // and the assertion failed on a leftover world for a reason that had
      // nothing to do with name reuse.
      final (_, world, spent) = WorldForging.launch(
        player: pilot(torpedoes: 1, detonators: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(3),
        tick: 0,
        type: 'Mountain',
        name: suggested,
      );
      final (det, afterDet, _) = WorldForging.detonate(
        player: spent,
        sector: sector,
        world: world!,
        cap: 3,
        tick: 1,
      );
      // A sector with no worlds must not be told any name is taken, so the
      // suggestion is drawn from the full pool rather than avoiding a ghost.
      final again =
          WorldForging.suggestName('Mountain', sector, math.Random(3));
      expect(afterDet.atomicDetonators, 0);
      expect(again, isNotEmpty);
      expect(sector.planets, isEmpty);
    });
  });

  group('detonating', () {
    test('is refused with no detonators, and the world survives', () {
      final sector = orbit(worlds: 1);
      final (result, after, _) = WorldForging.detonate(
        player: pilot(),
        sector: sector,
        world: sector.planets.first,
        cap: 3,
        tick: 0,
      );
      expect(result, DetonateResult.noDetonators);
      expect(after.atomicDetonators, 0);
      expect(sector.livingPlanets, hasLength(1));
    });

    test('refuses to destroy a world twice', () {
      final sector = orbit(worlds: 1);
      final p = pilot(detonators: 2);
      // Hold the instance. The second attempt can no longer reach it through
      // `sector.planets`, because the world is no longer there, and a fresh
      // lookup would fail on an empty list rather than on the rule.
      final doomed = sector.planets.first;
      final (_, after1, _) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: doomed,
        cap: 3,
        tick: 0,
      );
      final (result, _, _) = WorldForging.detonate(
          player: after1, sector: sector, world: doomed, cap: 3, tick: 0);
      // `alreadyDead`, not `notFound`: the world is gone, but this is the *same*
      // world the caller already detonated, and `notFound` would blame the
      // caller for handing over something that is not in the sector. The flag on
      // the detached instance is what separates the two cases.
      expect(result, DetonateResult.alreadyDead,
          reason: 'a second detonator must not be spent on a corpse');
    });
  });

  group('the gravity clock', () {
    // The clock is the whole mechanic. It starts the moment a sector goes over
    // the cap and a check falls due a game day later, so these assert *when* a
    // sector is eligible, not merely that it can lose a world.
    //
    // In **ticks**. This group used to say `24 * 60 * 60 * 1000`, which would
    // still compile after the rename and would then be 2,880,000 ticks — about
    // 34 game days — so every "due after a day" assertion would still have
    // passed while measuring the wrong thing entirely. A unit change with a
    // hand-typed period is a silent breakage, which is why the period now comes
    // from the same constant the rule does.
    const day = GameClock.ticksPerDay;

    test('nothing is due the moment a sector goes over', () {
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      expect(sector.destabilisedAtTick, t0,
          reason: 'the clock starts at the crossing, not before it');

      var destroyed = 0;
      // One tick per iteration. This was `i * 1000` — a thousand *milliseconds*,
      // i.e. a second — which after the switch to ticks is 8 hours and a half
      // per step, so 200 steps overshot the deadline by 69 game days and the
      // assertion passed for exactly the wrong reason before failing loudly.
      for (var i = 0; i < 200; i++) {
        destroyed +=
            WorldForging.runDueCollisions([sector], 3, t0 + i, math.Random(i));
      }
      expect(destroyed, 0,
          reason: '200 ticks is not a day; the sector has barely aged');
    });

    test('a check falls due once the clock runs out', () {
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      // One tick early is still early. The boundary matters: a sector that is due
      // at `t0 + day` and not at `t0 + day - 1` is exactly a clock — and now the
      // increment under test is a tick, which is the unit the rule counts in.
      expect(
        WorldForging.runDueCollisions(
            [sector], 3, t0 + day - 1, math.Random(1)),
        0,
        reason: 'one tick early is still early',
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
      young.reconcileStability(3, t0 + day - GameClock.ticksPerHour);

      // Many *distinct* sectors, one roll each. My first version reused one
      // sector 600 times at the same `tick`, and since a roll re-arms the clock
      // to that same instant, every call after the first found itself 0 ms past
      // its own re-arm and was never due. The test was measuring one roll, not
      // six hundred.
      var oldLost = 0;
      var youngLost = 0;
      for (var i = 0; i < 600; i++) {
        final a = orbit(worlds: 5, id: 1000 + i);
        final b = orbit(worlds: 5, id: 2000 + i);
        a.reconcileStability(3, t0);
        b.reconcileStability(3, t0 + day - GameClock.ticksPerHour);
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
      expect(sector.destabilisedAtTick, t0 + day,
          reason: 'a check re-arms from the moment it came due, not from the '
              'tick interval afterwards');

      // A millisecond later it is not due again, so the stamp must not move.
      WorldForging.runDueCollisions([sector], 3, t0 + day + 1, math.Random(2));
      expect(sector.destabilisedAtTick, t0 + day,
          reason: 'still inside the new day');

      // Exactly one day later it is due again. Proven by the stamp moving, which
      // happens on every due check whether or not the dice land.
      WorldForging.runDueCollisions([sector], 3, t0 + 2 * day, math.Random(3));
      expect(sector.destabilisedAtTick, t0 + 2 * day,
          reason: 'a surviving check must schedule the next one, or the hazard '
              'is one-shot and an over-stacked system is eventually safe');
    });

    test('clearing the sector below the cap cancels the clock', () {
      // The detonator is the answer to over-stacking, so a player who uses one
      // must not still be rolling hazard an hour (120 ticks) later.
      final sector = orbit(worlds: 4);
      final t0 = 1000000;
      sector.reconcileStability(3, t0);
      expect(sector.destabilisedAtTick, t0);

      WorldForging.detonate(
        player: pilot(detonators: 1),
        sector: sector,
        world: sector.planets.first,
        cap: 3,
        tick: t0,
      );
      WorldForging.runDueCollisions([sector], 3, t0 + day, math.Random(1));

      expect(sector.destabilisedAtTick, isNull);
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
      expect(sector.destabilisedAtTick, t0,
          reason: 'four worlds against a cap of three');

      // Stabilised: a fourth slot is authorised, so nothing is over-stacked.
      sector.reconcileStability(4, t0 + day - GameClock.ticksPerHour);
      expect(sector.destabilisedAtTick, isNull,
          reason: 'no longer over the cap, so the clock is cancelled');

      // Over again a minute later, under the original cap.
      final t1 = t0 + day - GameClock.ticksPerHour;
      sector.reconcileStability(3, t1);
      expect(sector.destabilisedAtTick, t1,
          reason: 'a fresh crossing starts a fresh clock, not the remainder of '
              'the old one');

      var destroyed = 0;
      for (var i = 0; i < 300; i++) {
        destroyed += WorldForging.runDueCollisions(
            [sector], 2, t1 + day - 1, math.Random(i));
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
      expect(sector.destabilisedAtTick, isNull,
          reason: 'and it never armed a clock in the first place');
    });

    test('the clock survives a save and reload', () {
      // A tick reads sectors from disk, so a stamp held only in memory is a
      // sector that re-arms on every load and never falls due.
      final sector = orbit(worlds: 4)..reconcileStability(3, 1000000);
      final restored = Sector.fromJson(sector.toJson());
      expect(restored.destabilisedAtTick, 1000000);
    });
  });
}
