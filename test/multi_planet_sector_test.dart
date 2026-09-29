import 'dart:convert';
import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A sector can hold several worlds, which makes `(sectorId)` no longer a
/// planet's identity. Every guard here exists because a plausible-looking
/// `sector.planets.first` compiles, runs, and silently picks the wrong world.
void main() {
  group('the model', () {
    test('a world has an identity that survives its sector and its name', () {
      final a = Planet(name: 'Kravos', planetType: 'Lava');
      final b = Planet(name: 'Kravos', planetType: 'Lava');
      expect(a.id, isNotEmpty);
      expect(a.id, isNot(b.id),
          reason: 'two worlds may share a name and a sector');
    });

    test('ids are unique across a generated galaxy', () {
      final sectors =
          UniverseGenerator(GameSettings.defaults().copyWith(seed: 7))
              .generate();
      final ids = <String>{};
      var worlds = 0;
      for (final s in sectors) {
        for (final p in s.planets) {
          worlds++;
          expect(ids.add(p.id), isTrue, reason: 'duplicate id on ${p.name}');
        }
      }
      expect(worlds, greaterThan(0));
    });

    test('a legacy single-planet save loads as a one-element list', () {
      // The migration that matters: a save written before this refactor has a
      // `planet` object and no `planets` array.
      final legacy = <String, dynamic>{
        'id': 7,
        'name': 'Kronos Reach',
        'x': 0.0,
        'y': 0.0,
        'warpRoutes': <int>[],
        'hasPort': false,
        'hasPlanet': true,
        'planet': {
          'name': 'Xandor',
          'planetType': 'Jungle',
          'population': 100,
        },
      };

      final sector = Sector.fromJson(legacy);

      expect(sector.planets, hasLength(1));
      expect(sector.planets.first.name, 'Xandor');
      expect(sector.planets.first.id, isNotEmpty,
          reason: 'a migrated world needs a minted identity');
      expect(sector.hasPlanet, isTrue);
    });

    test('a legacy sector with no world loads as empty', () {
      final sector = Sector.fromJson({
        'id': 1,
        'name': 'Terra Prime',
        'x': 0.0,
        'y': 0.0,
        'warpRoutes': <int>[],
      });
      expect(sector.planets, isEmpty);
      expect(sector.hasPlanet, isFalse);
    });

    test('hasPlanet follows the list, not a stale stored flag', () {
      // A legacy save can disagree with itself: flagged true, object missing.
      // Trusting the flag would lose the world silently.
      final sector = Sector.fromJson({
        'id': 2,
        'name': 'Nowhere',
        'x': 0.0,
        'y': 0.0,
        'warpRoutes': <int>[],
        'hasPlanet': true,
      });
      expect(sector.hasPlanet, isFalse);
    });

    test('a destroyed world is excluded from living worlds but still listed',
        () {
      final dead = Planet(name: 'Scorched', planetType: 'Lava')..destroy();
      final live = Planet(name: 'Xandor', planetType: 'Jungle');
      final s = Sector(
          id: 3,
          name: 'T',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [dead, live]);

      expect(s.planets, hasLength(2), reason: 'a corpse is still drawn');
      expect(s.livingPlanets, hasLength(1));
      expect(s.livingPlanets.first.name, 'Xandor');
    });

    test('homeworld finds the capital wherever in the sector it sits', () {
      final neighbour = Planet(name: 'Frontier', planetType: 'Moon');
      final capital =
          Planet(name: 'Kravos', planetType: 'Lava', isHomeworld: true);
      final s = Sector(
          id: 4,
          name: 'T',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [neighbour, capital]);

      // Deliberately in slot 1, with a non-homeworld in slot 0. `primaryPlanet`
      // would return the frontier world here.
      expect(s.primaryPlanet!.name, 'Frontier');
      expect(s.homeworld!.name, 'Kravos');
    });

    test('round-trips three worlds through JSON', () {
      final s = Sector(
        id: 5,
        name: 'Trio',
        x: 1,
        y: 2,
        warpRoutes: const [6],
        planets: [
          Planet(name: 'A', planetType: 'Ocean'),
          Planet(name: 'B', planetType: 'Lava'),
          Planet(name: 'C', planetType: 'Terran'),
        ],
      );

      final back = Sector.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, dynamic>);

      expect(back.planets, hasLength(3));
      expect(back.planets.map((p) => p.id), s.planets.map((p) => p.id));
      expect(back.planets.map((p) => p.name), ['A', 'B', 'C']);
    });
  });

  group('the generator', () {
    late List<Sector> sectors;

    setUp(() {
      sectors = UniverseGenerator(GameSettings.defaults().copyWith(seed: 7))
          .generate();
    });

    test('honours the per-sector cap', () {
      final cap = GameSettings.defaults().planetsPerSector;
      for (final s in sectors) {
        expect(s.planets.length, lessThanOrEqualTo(cap),
            reason: 'sector ${s.id} over cap');
      }
    });

    test('actually places more than one world per sector', () {
      // The whole point of the refactor. A generator that quietly produced one
      // world everywhere would pass every other test in this file.
      final multi = sectors.where((s) => s.planets.length > 1).toList();
      expect(multi, isNotEmpty,
          reason: 'no sector holds more than one world — the loop is dead');
      // Measured at the default 0.5 density: 22 empty / 12 single / 9 double /
      // 7 triple, so ~32%. The floor is 25% — below that the complementarity
      // loop has nowhere to live and the whole design is decorative. Raising
      // density is the lever; this assertion is what makes the lever visible.
      // Measured at the default 0.5 density: 22 empty / 12 single / 9 double /
      // 7 triple, so ~32%. The floor is 25% — below that the complementarity
      // loop has nowhere to live and the whole design is decorative. Density is
      // the lever, and this assertion is what makes the lever visible.
      expect(multi.length, greaterThan(sectors.length ~/ 4),
          reason: 'multi-world sectors are too rare to build an economy on');
    });

    test('planetsPerSector is a knob that does something', () {
      final one = UniverseGenerator(
              GameSettings.defaults().copyWith(seed: 7, planetsPerSector: 1))
          .generate();
      for (final s in one) {
        expect(s.planets.length, lessThanOrEqualTo(1));
      }
    });

    test('two factions can share a sector without a shared name', () {
      // The invariant that broke: "one homeworld per sector" is no longer true,
      // but "no two capitals share a name" still is.
      final names = <String>{};
      for (final s in sectors) {
        for (final p in s.planets) {
          if (p.isHomeworld) {
            expect(names.add(p.name), isTrue, reason: 'duplicate ${p.name}');
          }
        }
      }
    });

    test('pirate outposts sit in distinct sectors', () {
      final outpostSectors = <int>{};
      for (final s in sectors) {
        for (final p in s.planets) {
          if (p.isHomeworld && p.homeworldOf == FactionClass.pirate) {
            outpostSectors.add(s.id);
          }
        }
      }
      expect(outpostSectors, hasLength(2));
    });
  });

  group('services read every world, not slot zero', () {
    late List<Sector> sectors;

    setUp(() {
      sectors = UniverseGenerator(GameSettings.defaults().copyWith(seed: 7))
          .generate();
    });

    test('production ticks every world in a sector', () {
      // Slot 0 only would run the complementarity loop at a third of its value
      // and hide the rest of the colony entirely.
      final multi = sectors.firstWhere((s) => s.planets.length >= 2);
      for (final p in multi.planets) {
        p.population = 10000;
        p.colonistsMinerals = 10000;
      }
      final before = multi.planets.map((p) => p.storedMinerals).toList();

      PlanetProductionService.process([multi]);

      for (var i = 0; i < multi.planets.length; i++) {
        expect(multi.planets[i].storedMinerals, greaterThan(before[i]),
            reason: '${multi.planets[i].name} was skipped by the tick');
      }
    });

    test('a capital in slot 2 is still found by colonist supply', () {
      // Build the pathological case by hand: a non-homeworld in slot 0 and the
      // capital behind it. Reading slot 0 would price colonists off a frontier
      // world, and the test would pass while the game shipped a lie.
      final capital = Planet(
        name: 'Test Capital',
        planetType: 'Lava',
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        owner: FactionClass.duran,
      );
      final neighbour = Planet(name: 'Neighbour', planetType: 'Moon');
      final home = Sector(
        id: 900,
        name: 'Home Sector',
        x: 0,
        y: 0,
        warpRoutes: const [901],
        planets: [neighbour, neighbour, capital],
      );

      final source = ColonistSupply.sourceFor([home], FactionClass.duran);

      expect(source.name, 'Test Capital',
          reason: 'supply was priced off slot 0 (${neighbour.name}) instead of '
              'the capital');
    });

    test('every capital in a sector counts down, not just slot 0', () {
      // Rewritten after a fault injection proved the first version could not
      // fail. It put the capital in slot 2 and asserted its timer was
      // **unchanged**; truncating the loop to `.take(1)` skips the capital
      // entirely, which also leaves the timer unchanged. The assertion could not
      // distinguish "processed and correctly frozen" from "never looked at".
      //
      // The fix is to make the test fail on the *positive*: two owned capitals
      // in one sector, both of which must tick. Truncating to slot 0 freezes the
      // second one and that is visible.
      final first = Planet(
        name: 'Yard A',
        planetType: 'Lava',
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        owner: FactionClass.duran,
        productionTimer: 5,
        spawnInterval: 10,
      );
      final second = Planet(
        name: 'Yard B',
        planetType: 'Lava',
        isHomeworld: true,
        homeworldOf: FactionClass.vinari,
        owner: FactionClass.vinari,
        productionTimer: 5,
        spawnInterval: 10,
      );
      final s = Sector(
        id: 902,
        name: 'Yards',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [first, Planet(name: 'Filler', planetType: 'Moon'), second],
      );

      RepopulationService.produce([s], const [], rng: math.Random(3));

      expect(first.productionTimer, 4, reason: 'slot 0 did not tick');
      expect(second.productionTimer, 4,
          reason: 'a capital in slot 2 was skipped by the yard loop');
    });

    test('a captured capital does not count down wherever it sits', () {
      // Kept as a separate case now that the loop-coverage test no longer
      // doubles as the capture test — the two faults have different symptoms
      // and a single test cannot see both.
      final capital = Planet(
        name: 'Cold Yard',
        planetType: 'Lava',
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        owner: FactionClass.trader, // captured
        productionTimer: 1,
        spawnInterval: 10,
      );
      final s = Sector(
        id: 903,
        name: 'Frozen',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [capital],
      );

      RepopulationService.produce([s], const [], rng: math.Random(3));

      expect(capital.productionTimer, 1,
          reason: 'a captured yard must not count down');
    });
  });
}
