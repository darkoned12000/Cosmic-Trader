import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A world that satisfies the current level's gate, built from the table so the
/// fixture cannot drift from the rules.
Planet _ready({String type = 'Terran', int level = 1}) {
  final cost = Planet.levelUpCosts[level - 1];
  return Planet(
    name: 'Kravos',
    planetType: type,
    level: level,
    population: cost.requiredColonists,
    storedMinerals: cost.requiredMinerals + 1000,
    storedOrganics: cost.requiredOrganics + 1000,
    storedIndustrial: cost.requiredIndustrial + 1000,
  );
}

Sector _sectorWith(Planet planet) => Sector(
      id: 7,
      name: 'Testreach',
      x: 0,
      y: 0,
      warpRoutes: const <int>[],
      planet: planet,
      hasPlanet: true,
    );

void main() {
  group('persistence', () {
    test('a build in progress survives a save/load round-trip', () {
      // The countdown is a persisted field, not a UI-held value. If it were not
      // written, every restart would silently refund the player their build.
      final planet = _ready()..startConstruction();
      final remaining = planet.constructionTicksRemaining;
      expect(remaining, greaterThan(0));

      final restored = Planet.fromJson(planet.toJson());

      expect(restored.constructionTicksRemaining, remaining);
      expect(restored.constructionTarget, 2);
      expect(restored.isUnderConstruction, isTrue);
      expect(restored.level, 1, reason: 'still level 1 — it had not finished');
    });

    test('a pre-construction save loads as not building', () {
      // A save written before this feature existed has neither key.
      final json = _ready().toJson()..remove('constructionTicksRemaining');
      final restored = Planet.fromJson(json);

      expect(restored.constructionTicksRemaining, 0);
      expect(restored.isUnderConstruction, isFalse);
    });
  });

  group('the tick advances construction', () {
    test('one tick does not finish a build', () {
      final planet = _ready()..startConstruction();
      final ticks = planet.constructionTicksRemaining;

      PlanetProductionService.process([_sectorWith(planet)]);

      expect(planet.constructionTicksRemaining, ticks - 1);
      expect(planet.level, 1);
    });

    test('the level lands on the final tick and is reported', () {
      final planet = _ready()..startConstruction(timeScale: 0.1);
      final total = planet.constructionTicksRemaining;

      PlanetProductionSummary summary = const PlanetProductionSummary();
      for (var i = 0; i < total; i++) {
        summary = PlanetProductionService.process([_sectorWith(planet)]);
      }

      expect(planet.level, 2);
      expect(planet.isUnderConstruction, isFalse);
      expect(summary.constructionsCompleted, 1);
      expect(summary.isQuiet, isFalse,
          reason: 'a finished citadel is worth a log line even with no output');
    });

    test('a build still progresses when the colony is starving', () {
      // The population check that gates production runs after construction on
      // purpose. A starving colony has already paid for its upgrade; stalling
      // the build would make a bad run destroy work that was paid for, and the
      // resources would be gone either way.
      // Start first, then collapse the population: the gate is only checked when
      // work begins, which is the whole point of paying up front.
      final planet = _ready()..startConstruction();
      expect(planet.isUnderConstruction, isTrue);
      planet.population = 0;
      final total = planet.constructionTicksRemaining;

      for (var i = 0; i < total; i++) {
        PlanetProductionService.process([_sectorWith(planet)]);
      }

      expect(planet.level, 2);
    });

    test('a destroyed world does not complete its build', () {
      final planet = _ready()..startConstruction();
      planet.destroy();

      PlanetProductionService.process([_sectorWith(planet)]);

      expect(planet.level, 1);
      expect(planet.isUnderConstruction, isFalse);
    });

    test('a finished build reports zero on the following tick', () {
      // Guard against a stuck counter: a summary that keeps reporting a
      // completion every tick would spam the log forever.
      final planet = _ready()..startConstruction(timeScale: 0.1);
      while (planet.isUnderConstruction) {
        PlanetProductionService.process([_sectorWith(planet)]);
      }

      final summary = PlanetProductionService.process([_sectorWith(planet)]);
      expect(summary.constructionsCompleted, 0);
    });
  });

  group('the whole arc is reachable', () {
    test('every type can reach every tier, and the arc stays affordable', () {
      // The re-derived cost table and the level-scaled cap have to agree at
      // every step, for every type. A single mismatched row would make one
      // planet type a dead end, which is exactly the defect the old table had.
      for (final type in Planet.allTypes) {
        var world = Planet(name: 'W', planetType: type, level: 1);
        for (var step = 0; step < Planet.levelUpCosts.length; step++) {
          final cost = Planet.levelUpCosts[step];
          expect(
              world.colonistMax, greaterThanOrEqualTo(cost.requiredColonists),
              reason: '$type is capped at ${world.colonistMax} on level '
                  '${world.level} but needs ${cost.requiredColonists} for '
                  '${world.level} -> ${world.level + 1}');
          world.level++;
        }
        expect(world.level, 6, reason: '$type could not reach Citadel');
      }
    });

    test('cost rises monotonically', () {
      for (var i = 1; i < Planet.levelUpCosts.length; i++) {
        expect(Planet.levelUpCosts[i].requiredColonists,
            greaterThan(Planet.levelUpCosts[i - 1].requiredColonists));
        expect(Planet.levelUpCosts[i].requiredMinerals,
            greaterThan(Planet.levelUpCosts[i - 1].requiredMinerals));
      }
    });

    test('construction time rises with the tier', () {
      final ticks =
          [1, 2, 3, 4, 5].map((l) => Planet.constructionLengthFor(l)).toList();
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i], greaterThan(ticks[i - 1]),
            reason: 'the top tier is the long one; step $i is not');
      }
    });

    test('a full 1 to 6 is hours, not a wall', () {
      // The point of shortening the classic game's 34-52 day builds. At the
      // 30s tick this has to be hours of play, and it has to be more than a
      // single sitting or the six tiers are just a menu.
      final totalTicks = [1, 2, 3, 4, 5]
          .map((l) => Planet.constructionLengthFor(l))
          .reduce((a, b) => a + b);
      final hours = totalTicks * 30 / 3600;

      expect(hours, greaterThan(1.0), reason: 'too short to be a progression');
      expect(hours, lessThan(8.0),
          reason: 'too long to finish in a few sittings');
    });
  });
}
