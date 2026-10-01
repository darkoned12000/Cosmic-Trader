import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/world_forging.dart';

// Destroying a world is only a free action when you made it.
//
// The case that forced the rule: you fight the defences of a Guild world, win,
// and **claim** it — so `owner` is now you. It is still not yours. Blowing it up
// is an act against the Guild, and `creator` rather than `owner` is what
// distinguishes the two. A rule keyed on ownership would let the player launder a
// reputation hit by taking the world first, which is the exact opposite of the
// incentive the rule exists to remove.

Player _player({
  String name = 'Vance',
  int detonators = 1,
  FactionClass faction = FactionClass.trader,
}) =>
    Player(
      name: name,
      currentSectorId: 20,
      hull: 1000,
      maxHull: 1000,
      shields: 500,
      maxShields: 500,
      cargoUsed: 0,
      maxCargo: 20,
      cargoSize: 20,
      credits: 1000,
      researchPoints: 0,
      faction: faction,
      atomicDetonators: detonators,
    );

Planet _world({
  String name = 'Xandor',
  String? creator,
  FactionClass? owner,
  FactionClass? creatorFaction,
}) =>
    Planet(
      id: 'w-$name',
      name: name,
      planetType: 'Terran',
      scanned: true,
      owner: owner,
      creator: creator,
      creatorFaction: creatorFaction,
      hull: 40000,
      maxHull: 40000,
      population: 10000,
    );

Sector _sector(Planet world) => Sector(
    id: 20, name: 'S20', x: 0, y: 0, warpRoutes: const [21], planets: [world]);

/// A generator from above the 0.07 ceiling, so the blast never lands and the
/// assertions are about reputation alone.
final Fixed _cleanBlast = Fixed(0.99);

(DetonateResult, Player, ReputationHit?) _fire(
  Player player,
  Planet world,
) {
  final sector = _sector(world);
  return WorldForging.detonate(
    player: player,
    sector: sector,
    world: world,
    cap: 3,
    tick: 0,
    rng: _cleanBlast,
  );
}

void main() {
  group('your own world still costs reputation', () {
    // Reversed. There used to be an exemption for a world you made yourself, on
    // the reasoning that demolishing your own mistake is what the detonator is
    // *for*. That exemption was the farming vector: a launch paid out and
    // self-demolition was free, so the pair was a pure profit loop. Destroying a
    // populated world is a violent act whoever signed for it.
    test('alignment falls, even though you made it', () {
      final world = _world(creator: 'Vance', owner: FactionClass.trader);
      final (_, after, hit) = _fire(_player(), world);
      expect(hit, isNotNull);
      expect(hit!.alignment, ReputationActions.destroyWorld);
      expect(after.alignment, lessThan(0.0));
    });

    test('but your own faction is never charged for it', () {
      // The standing hit means \"you did this to somebody else\". Wrecking your own
      // holdings should not make your own faction think less of you — and a
      // self-demolition dropping your standing with yourself is the kind of
      // nonsense a shared code path produces without being looked at.
      final world = _world(creator: 'Vance', owner: FactionClass.trader);
      final before = _player();
      final (_, after, hit) = _fire(before, world);
      expect(hit!.faction, isNull);
      expect(after.factionStandingWith(FactionClass.trader),
          before.factionStandingWith(FactionClass.trader));
    });

    test('and the blast still lands on top of it', () {
      // Two costs, not one choice between them.
      final world = _world(creator: 'Vance', owner: FactionClass.trader);
      final before = _player();
      final (_, after, hit) = WorldForging.detonate(
        player: before,
        sector: _sector(world),
        world: world,
        cap: 3,
        tick: 0,
        rng: Fixed(0.0), // forced hit
      );
      expect(hit!.alignment, ReputationActions.destroyWorld);
      // Two costs on two different axes: the blast is hull and shields, the
      // charge is alignment. Asserting the blast moved alignment would have been
      // wrong — and it *did* pass, because a blast that did nothing and a blast
      // that damaged the ship look identical from that side.
      expect(after.shields, lessThan(before.shields));
      expect(after.hull, lessThan(before.hull));
    });
  });

  group('a world you did not make costs reputation', () {
    test('generator-placed: notoriety only, nobody to offend', () {
      final world = _world(); // creator null, owner null
      final (_, after, hit) = _fire(_player(), world);

      expect(hit, isNotNull);
      expect(hit!.faction, isNull, reason: 'no owner, no faction to offend');
      expect(after.alignment, WorldForging.destructionAlignment);
    });

    test('owned by a faction: notoriety and standing', () {
      final world = _world(owner: FactionClass.duran);
      final before = _player();
      final (_, after, hit) = _fire(before, world);

      expect(hit!.faction, FactionClass.duran);
      expect(after.alignment, WorldForging.destructionAlignment);
      // A *delta* of the charge, because the baseline is not zero: standing
      // starts positive with your own faction and negative with a rival.
      expect(
        after.factionStandingWith(FactionClass.duran) -
            before.factionStandingWith(FactionClass.duran),
        WorldForging.destructionStanding,
      );
      expect(after.factionStandingWith(FactionClass.trader),
          before.factionStandingWith(FactionClass.trader),
          reason: 'your own faction is not implicated');
    });

    test('and crucially: capturing it first does not launder the hit', () {
      // `owner` is now the player \u2014 they fought for it \u2014 but the maker is still
      // someone else. This is the whole reason the rule reads `creator`.
      final world = _world(
          creator: 'Ilsa Marr',
          owner: FactionClass.trader,
          creatorFaction: FactionClass.duran);
      final (_, after, hit) = _fire(_player(), world);

      expect(hit, isNotNull, reason: 'owning it is not making it');
      // Charged against the *maker's* faction, not the current holder. Reading
      // `owner` here found the player themselves and quietly let the destroyer
      // walk clean — which is exactly the laundering this rule exists to stop.
      expect(hit!.faction, FactionClass.duran);
      expect(after.alignment, WorldForging.destructionAlignment);
    });

    test('notoriety is capped at 100 like every other gain', () {
      // The clamp is the point: a pilot who is already well liked must not be
      // able to walk off the top of the ladder, and the same at the bottom.
      final liked = _fire(_player().copyWith(alignment: 4.0), _world()).$2;
      expect(liked.alignment, lessThanOrEqualTo(Reputation.absMax));
      final hated =
          _fire(_player().copyWith(alignment: -Reputation.absMax), _world()).$2;
      expect(hated.alignment, greaterThanOrEqualTo(-Reputation.absMax));
    });
  });

  group('provenance is recorded, not inferred', () {
    test('a torpedo-launched world remembers the pilot who fired it', () {
      final sector = _sector(_world(name: 'placeholder'));
      sector.planets.clear();
      final (_, world, after) = WorldForging.launch(
        player: _player().copyWith(genesisTorpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(5),
        tick: 0,
      );
      expect(world!.creator, 'Vance');
      expect(after.alignment, ReputationActions.createWorld);
    });

    test('a generated world has no maker at all', () {
      // Almost every world in the galaxy. Null is the normal case, not a
      // missing value to be back-filled later.
      expect(Planet(name: 'Kronos', planetType: 'Terran').creator, isNull);
    });

    test('the creator cannot be changed after the fact', () {
      // `final` is the guarantee, not a convention: nothing can rewrite
      // provenance, so there is no way to launder the hit by editing a field.
      final world = _world(creator: 'Ilsa Marr', owner: FactionClass.trader);
      world.owner = FactionClass.trader; // ownership moves freely
      world.isHomeworld = true;
      world.population = 999999;
      expect(world.creator, 'Ilsa Marr', reason: 'provenance is immutable');
    });

    test('it survives a save and reload', () {
      final world = _world(creator: 'Ilsa Marr', owner: FactionClass.duran);
      final reloaded = Planet.fromJson(world.toJson());
      expect(reloaded.creator, 'Ilsa Marr');
      expect(reloaded.owner, FactionClass.duran);
      // And a world with no maker does not gain one on the way through.
      expect(
          Planet.fromJson(Planet(name: 'X', planetType: 'Terran').toJson())
              .creator,
          isNull);
    });
  });

  group('the numbers are one place, and they are pinned', () {
    test('the constants are what the doc claims', () {
      // The log line tells the player this happened; a silent retune of the
      // charge would make that message a lie.
      expect(WorldForging.destructionAlignment, -128.0);
      expect(WorldForging.destructionStanding, -10);
      expect(WorldForging.destructionStanding, lessThan(0));
    });
  });
  group('the log does not give away the position', () {
    // A destroyed world is something worth hunting for. Naming the sector it
    // stood in turns the player's own detonation into a map to it — the stated
    // reason for dropping it.
    test('neither the action log nor the world-news line names a sector', () {
      final world = _world(creator: 'Vance', owner: FactionClass.trader);
      final sector = _sector(world);
      // Cleared first, because this is a process-wide ring that outlives the
      // test that filled it — reading it without clearing would find *some*
      // vaporisation line from an earlier test and pass for the wrong reason.
      GameEventLog.global.clear();

      WorldForging.detonate(
        player: _player(),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: _cleanBlast,
      );

      final lines = GameEventLog.global.entries.map((e) => e.message).toList();
      expect(lines, isNotEmpty, reason: 'the event was recorded');
      for (final line in lines.where((l) => l.contains('vaporised'))) {
        expect(line, isNot(contains(sector.name)),
            reason: 'a destroyed world must not come with its coordinates');
        expect(line, isNot(contains('${sector.id}')),
            reason: 'nor its sector id');
        // But it must still say *what* happened.
        expect(line, contains(world.name));
      }
    });
  });
}

/// A generator pinned above the blast band, so the blast cannot interfere with
/// a reputation assertion.
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
