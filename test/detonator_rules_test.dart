import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/world_forging.dart';

// The detonator is the only irreversible control in the game, and it is now
// reachable from two places. Three things therefore have to hold, and each of
// them was a real bug or a real trap while this was being built:
//
// 1. The item is spent by the *rule*, not by the caller. `launch` used to leave
//    that to the screen while `detonate` did it itself, so the moment a second
//    launch site appeared the accounting had two owners.
// 2. The blast lands on shields first, exactly like every other damage path.
// 3. A destroyed world leaves the system: no slot, no production, no
//    homeworld, and the stability clock cleared rather than left armed.
//
// The blast chance is a `double` comparison against a shared RNG, so a test
// that does not inject its own generator is testing the weather.

Player _player({int torpedoes = 1, int detonators = 1, int hull = 1000}) {
  return Player(
    name: 'Cap',
    currentSectorId: 20,
    hull: hull,
    maxHull: hull,
    shields: 500,
    maxShields: 500,
    cargoUsed: 0,
    maxCargo: 20,
    cargoSize: 20,
    credits: 1000,
    researchPoints: 0,
    faction: FactionClass.trader,
    genesisTorpedoes: torpedoes,
    atomicDetonators: detonators,
  );
}

Planet _world({String name = 'Xandor', int hull = 40000, int pop = 10000}) {
  return Planet(
    name: name,
    planetType: 'Terran',
    hull: hull.toDouble(),
    maxHull: hull.toDouble(),
    population: pop,
    level: 3,
  );
}

Sector _sector(List<Planet> planets) => Sector(
      id: 20,
      name: 'S20',
      x: 0,
      y: 0,
      warpRoutes: const [21],
      planets: planets,
    );

void main() {
  group('the item is spent by the rule, not the caller', () {
    test('launch decrements the torpedo and hands back the player', () {
      final world = _world();
      final sector = _sector([world]);
      final p = _player(torpedoes: 2);

      final (result, created, spent) = WorldForging.launch(
        player: p,
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
      );

      expect(result, LaunchResult.launched);
      expect(created, isNotNull);
      expect(spent.genesisTorpedoes, 1, reason: 'the rule owns the accounting');
      expect(p.genesisTorpedoes, 2, reason: 'the input is immutable');
      expect(sector.worldSlotsUsed, 2);
    });

    test('no torpedoes means no spend and no world', () {
      final sector = _sector([_world()]);
      final (result, created, spent) = WorldForging.launch(
        player: _player(torpedoes: 0),
        sector: sector,
        cap: 3,
        rng: math.Random(1),
        tick: 0,
      );
      expect(result, LaunchResult.noTorpedoes);
      expect(created, isNull);
      expect(spent.genesisTorpedoes, 0);
      expect(sector.worldSlotsUsed, 1, reason: 'nothing was created');
    });

    test('detonate spends exactly one, and only on success', () {
      final world = _world();
      final sector = _sector([world]);
      final (_, spent, _) = WorldForging.detonate(
        player: _player(detonators: 3),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: math.Random(99),
      );
      expect(spent.atomicDetonators, 2);
    });

    test('a refused detonation costs nothing', () {
      final world = _world();
      final sector = _sector([world]);
      final (result, spent, _) = WorldForging.detonate(
        player: _player(detonators: 0),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: math.Random(1),
      );
      expect(result, DetonateResult.noDetonators);
      expect(spent.atomicDetonators, 0);
      expect(world.isDestroyed, isFalse, reason: 'the world survives');
    });
  });

  group('the blast', () {
    test('a forced hit lands on shields before hull', () {
      // The chance band is [0.03, 0.07); a generator returning 0.0 always hits.
      final world = _world(hull: 100000); // 2-5% of 100,000 = 2,000-5,000
      final sector = _sector([world]);
      final p = _player(hull: 1000, detonators: 1);
      final (result, after, _) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.0),
      );

      expect(result, DetonateResult.destroyed);
      // 2% of 100,000 is the floor of the band: 2,000 damage, and 500 of
      // shields cannot cover it, so hull must have taken the rest.
      expect(after.shields, 0, reason: 'shields absorb first');
      expect(after.hull, lessThan(p.hull), reason: 'hull takes the remainder');
      expect(after.hull, greaterThanOrEqualTo(0), reason: 'never below zero');
    });

    test('shields alone can take the whole hit', () {
      final world = _world(hull: 10000); // 200-500 damage
      final sector = _sector([world]);
      final p = _player(hull: 1000, detonators: 1);
      final (_, after, _) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.0),
      );
      expect(after.hull, p.hull, reason: 'shields held');
      expect(after.shields, lessThan(p.shields));
    });

    test('a forced miss leaves the ship untouched', () {
      final world = _world();
      final sector = _sector([world]);
      final p = _player(detonators: 1);
      // Above the 0.07 ceiling of the band, so the roll cannot land.
      final (_, after, _) = WorldForging.detonate(
        player: p,
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.99),
      );
      expect(after.shields, p.shields);
      expect(after.hull, p.hull);
    });

    test('damage scales with the world, so the biggest boom is not the safest',
        () {
      int damageFor(int worldHull) {
        final world = _world(hull: worldHull);
        final p = _player(hull: 100000, detonators: 1);
        // Shields zeroed so every point of damage is visible on the hull.
        final (_, after, _) = WorldForging.detonate(
          player: p.copyWith(shields: 0),
          sector: _sector([world]),
          world: world,
          cap: 3,
          tick: 0,
          rng: Fixed(0.0),
        );
        return p.hull - after.hull;
      }

      final small = damageFor(10000); // 200-500
      final large = damageFor(200000); // 4,000-10,000
      expect(large, greaterThan(small * 4),
          reason: 'a level-6 Citadel going up must outrank a scorched rock');
    });

    test('the documented band is the band', () {
      // Pin the constants rather than trusting the doc comment: a warning
      // dialog quotes these numbers to the player, so they are a promise.
      expect(WorldForging.blastChanceMin, 0.03);
      expect(WorldForging.blastChanceMax, 0.07);
      expect(
          WorldForging.blastChanceMin, lessThan(WorldForging.blastChanceMax));
    });
  });

  group('a destroyed world leaves the system', () {
    test('it holds no orbital slot', () {
      final world = _world();
      final sector = _sector([world]);
      expect(sector.worldSlotsUsed, 1);
      WorldForging.detonate(
        player: _player(),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.99),
      );
      expect(sector.worldSlotsUsed, 0,
          reason: 'this is what makes detonate-then-re-roll work');
      expect(sector.freeSlots(3), 3);
    });

    test('and it is removed from the records, not left as a corpse', () {
      // Reversed at the player's request. The corpse existed so a dead world
      // could "still be drawn and argued about", which in practice left it in
      // the sector contents, landable, and claimable again — so the detonator
      // freed the slot but not the world.
      final world = _world();
      final sector = _sector([world]);
      WorldForging.detonate(
        player: _player(),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.99),
      );
      expect(sector.planets, isEmpty);
      expect(sector.hasPlanet, isFalse);
      // The object itself is still neutralised, because a screen's private copy
      // of the universe is a *different instance* from the one in this list.
      expect(world.isDestroyed, isTrue);
      expect(world.population, 0);
    });

    test('the colony is emptied, so it cannot produce', () {
      final world = _world(pop: 500000);
      expect(world.population, 500000);
      WorldForging.detonate(
        player: _player(),
        sector: _sector([world]),
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.99),
      );
      expect(world.population, 0);
      expect(world.storedMinerals, 0);
      expect(world.outputPerDayFor('minerals'), 0);
    });

    test('a detonation that stabilises the sector clears the gravity clock',
        () {
      // The over-stack case: three worlds plus a fourth is unstable, and the
      // detonator is the only way back. The stamp has to be cleared the moment
      // the count drops, not on the next sweep — otherwise a sector pushed
      // over again inside that window inherits the old one's remaining time.
      final worlds = [_world(name: 'A'), _world(name: 'B'), _world(name: 'C')];
      final sector = _sector(worlds);
      final (launched, fourth, _) = WorldForging.launch(
        player: _player(torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(4),
        tick: 1000,
      );
      expect(launched, LaunchResult.wouldOverstack);
      expect(sector.destabilisedAtTick, 1000, reason: 'the clock is armed');

      WorldForging.detonate(
        player: _player(),
        sector: sector,
        world: fourth!,
        cap: 3,
        tick: 2000,
        rng: Fixed(0.99),
      );
      expect(sector.worldSlotsUsed, 3);
      expect(sector.isOverStacking(3), isFalse);
      expect(sector.destabilisedAtTick, isNull,
          reason: 'back under the cap, so no hazard is pending');
    });
  });
}

/// A generator pinned to one value, so both branches of a probability are
/// reachable without seeding luck. `nextDouble` is the only draw the blast
/// makes before the damage roll, and [fixed] answers the rest from the same
/// stream.
class Fixed implements math.Random {
  final double value;
  const Fixed(this.value);

  @override
  double nextDouble() => value;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
