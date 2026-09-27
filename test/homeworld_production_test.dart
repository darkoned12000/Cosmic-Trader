import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';

// C4a/b: production-driven spawning, backup homeworlds, planet-killer path.
Sector _homeworld({
  required int id,
  required FactionClass faction,
  FactionClass? owner,
  int timer = 5,
  int interval = 10,
  bool backup = false,
  bool destroyed = false,
}) {
  final planet = Planet(
    name: 'HW$id',
    planetType: 'Terran',
    owner: owner ?? faction,
    isHomeworld: true,
    homeworldOf: faction,
    isBackupHomeworld: backup,
    productionTimer: timer,
    spawnInterval: interval,
  );
  if (destroyed) planet.destroy();
  return Sector(
    id: id,
    name: 'S$id',
    x: 0,
    y: 0,
    warpRoutes: const [],
    hasPlanet: true,
    planet: planet,
  );
}

NpcShip _npc(FactionClass faction, int sector, int seed) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: 0,
    seed: seed,
  );
}

void main() {
  group('C4a production cadence', () {
    test('timers tick down, then fire and reset', () {
      final sectors = [
        _homeworld(id: 11, faction: FactionClass.trader, timer: 2)
      ];
      final rng = math.Random(7);

      var built = RepopulationService.produce(sectors, [], rng: rng);
      expect(built, isEmpty);
      expect(sectors[0].planet!.productionTimer, 1);

      built = RepopulationService.produce(sectors, [], rng: rng);
      expect(built, hasLength(1));
      expect(built[0].faction, FactionClass.trader);
      expect(built[0].currentSectorId, 11);
      expect(sectors[0].planet!.productionTimer, 10);
    });

    test('captured yards freeze; destroyed worlds are silent', () {
      final sectors = [
        _homeworld(
            id: 11,
            faction: FactionClass.trader,
            owner: FactionClass.duran,
            timer: 1),
        _homeworld(
            id: 12, faction: FactionClass.vinari, timer: 1, destroyed: true),
      ];
      final built =
          RepopulationService.produce(sectors, [], rng: math.Random(7));
      expect(built, isEmpty);
      // Captured: frozen mid-countdown. Destroyed: untouched.
      expect(sectors[0].planet!.productionTimer, 1);
      expect(sectors[1].planet!.isHomeworld, isFalse);
    });

    test('yards stand down at the cap (timer still resets)', () {
      final sectors = [
        _homeworld(id: 11, faction: FactionClass.trader, timer: 1)
      ];
      final npcs = [
        for (var i = 0; i < 8; i++) _npc(FactionClass.trader, 11, 100 + i),
      ];
      final built =
          RepopulationService.produce(sectors, npcs, rng: math.Random(7));
      expect(built, isEmpty);
      expect(sectors[0].planet!.productionTimer, 10);
    });

    test('below cap each world builds on its own cadence', () {
      final sectors = [
        _homeworld(id: 11, faction: FactionClass.trader, timer: 1),
        _homeworld(id: 12, faction: FactionClass.duran, timer: 3),
      ];
      final built =
          RepopulationService.produce(sectors, [], rng: math.Random(7));
      expect(built, hasLength(1));
      expect(built[0].faction, FactionClass.trader);
      expect(sectors[1].planet!.productionTimer, 2);
    });
  });

  group('C4b backups and planet-killer path', () {
    test('primary wins; backup takes over when primary falls', () {
      final sectors = [
        _homeworld(id: 11, faction: FactionClass.trader),
        _homeworld(id: 12, faction: FactionClass.trader, backup: true),
      ];
      // Both live: primary answers.
      expect(
        RepopulationService.homeworldSectors(sectors),
        {FactionClass.trader: 11},
      );
      // Primary captured: backup takes over (floors + production source).
      sectors[0].planet!.owner = FactionClass.duran;
      expect(
        RepopulationService.homeworldSectors(sectors),
        {FactionClass.trader: 12},
      );
      // Recapture restores the primary and idles the backup.
      sectors[0].planet!.owner = FactionClass.trader;
      expect(
        RepopulationService.homeworldSectors(sectors),
        {FactionClass.trader: 11},
      );
    });

    test('backup produces only without a live primary', () {
      final primary =
          _homeworld(id: 11, faction: FactionClass.trader, timer: 1);
      final backup = _homeworld(
          id: 12, faction: FactionClass.trader, timer: 1, backup: true);
      final sectors = [primary, backup];

      // Primary live: only it builds (backup timer frozen mid-countdown).
      var built = RepopulationService.produce(sectors, [], rng: math.Random(7));
      expect(built.map((n) => n.currentSectorId), [11]);
      expect(sectors[1].planet!.productionTimer, 1);

      // Primary captured: backup's yards warm up.
      sectors[0].planet!.owner = FactionClass.duran;
      built = RepopulationService.produce(sectors, built, rng: math.Random(7));
      expect(built.map((n) => n.currentSectorId), [12]);
    });

    test('destroy() clears the world; regen never resumes there', () {
      final planet = Planet(
        name: 'Kravos',
        planetType: 'Lava',
        owner: FactionClass.duran,
        isHomeworld: true,
        homeworldOf: FactionClass.duran,
        population: 12000,
        defenseLevel: 4,
        hull: 20000,
        maxHull: 20000,
      );
      planet.destroy();
      expect(planet.isDestroyed, isTrue);
      expect(planet.isHomeworld, isFalse);
      expect(planet.homeworldOf, isNull);
      expect(planet.owner, isNull);
      expect(planet.population, 0);
      expect(planet.hull, 0);

      final sectors = [
        Sector(
            id: 11,
            name: 'S11',
            x: 0,
            y: 0,
            warpRoutes: const [],
            hasPlanet: true,
            planet: planet),
      ];
      expect(RepopulationService.homeworldSectors(sectors), isEmpty);
      expect(
        RepopulationService.produce(sectors, [], rng: math.Random(7)),
        isEmpty,
      );
    });

    test('destroyed and backup flags survive JSON round-trip', () {
      final planet = Planet(
        name: 'Celestara',
        planetType: 'Terran',
        owner: FactionClass.vinari,
        isHomeworld: true,
        homeworldOf: FactionClass.vinari,
        isBackupHomeworld: true,
      );
      final restored = Planet.fromJson(planet.toJson().cast<String, dynamic>());
      expect(restored.isBackupHomeworld, isTrue);
      expect(restored.isDestroyed, isFalse);

      planet.destroy();
      final dead = Planet.fromJson(planet.toJson().cast<String, dynamic>());
      expect(dead.isDestroyed, isTrue);
      expect(dead.isHomeworld, isFalse);
      // Legacy saves default to live primaries.
      final legacy = Planet.fromJson(const {});
      expect(legacy.isDestroyed, isFalse);
      expect(legacy.isBackupHomeworld, isFalse);
    });
  });

  group('C4c living legends', () {
    setUp(BountyBoard.resetForTest);
    tearDown(BountyBoard.resetForTest);

    List<Sector> firingYard() => [
          _homeworld(id: 11, faction: FactionClass.duran, timer: 1),
        ];

    test('yards sometimes roll out a buffed, bountied legend', () {
      NpcShip? hero;
      for (var seed = 0; seed < 500 && hero == null; seed++) {
        final built = RepopulationService.produce(
          firingYard(),
          [],
          rng: math.Random(seed),
        );
        if (built.isNotEmpty && built[0].heroName != null) {
          hero = built[0];
        }
      }
      expect(hero, isNotNull, reason: 'no legend in 500 yard rolls');
      final lore =
          Faction.forClass(hero!.faction).notableHeroes.map((h) => h.name);
      expect(lore, contains(hero.heroName));
      expect(hero.pilotName, hero.heroName);
      expect(hero.heroTitle, isNotNull);
      // Buffed hull/shields, hot guns, marked notorious.
      expect(hero.hull, hero.maxHull);
      expect(hero.hull, greaterThan(0));
      expect(hero.shields, hero.maxShields);
      expect(hero.weaponSlots.values.every((lvl) => lvl >= 2), isTrue);
      expect(hero.notoriety, 15.0);
      // The Guild puts story money on legends.
      expect(
          BountyBoard.global.totalFor(hero.id), RepopulationService.heroBounty);
    });

    test('a legend already flying is never duplicated', () {
      final taken = Faction.forClass(FactionClass.duran)
          .notableHeroes
          .map((h) => h.name)
          .toSet();
      final roster = taken
          .map((name) => _npc(FactionClass.duran, 11, name.hashCode)
              .copyWith(heroName: name))
          .toList();
      for (var seed = 0; seed < 50; seed++) {
        final built = RepopulationService.produce(
          firingYard(),
          roster,
          rng: math.Random(seed),
        );
        for (final ship in built) {
          expect(ship.heroName, isNull);
        }
      }
    });

    test('pirates sail no legends (no lore table, no heroes)', () {
      // Pirate yards build rank-and-file only: the hero roll hits the
      // missing lore table and stands down every time.
      for (var seed = 0; seed < 20; seed++) {
        final sectors = [
          _homeworld(id: 11, faction: FactionClass.pirate, timer: 1),
        ];
        final built = RepopulationService.produce(
          sectors,
          [],
          rng: math.Random(seed),
        );
        for (final ship in built) {
          expect(ship.heroName, isNull);
        }
      }
    });

    test('hero identity survives JSON round-trip', () {
      final ship = _npc(FactionClass.vinari, 11, 77)
          .copyWith(heroName: 'X', heroTitle: 'Y');
      final restored = NpcShip.fromJson(ship.toJson().cast<String, dynamic>());
      expect(restored.heroName, 'X');
      expect(restored.heroTitle, 'Y');
      final legacy = NpcShip.fromJson({
        ...ship.toJson().cast<String, dynamic>(),
        'driftAggression': null,
      });
      expect(legacy.driftAggression, 0.0);
    });
  });

  group('C4d personality drift', () {
    NpcShip killerSetup() => NpcShip.create(
          faction: FactionClass.pirate,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: 11,
          startingCredits: 0,
          seed: 601,
        ).copyWith(
          personality: NpcPersonality.pirateHunter,
          energy: 1000,
          weaponSlots: const {'main_forward': 3},
        );

    NpcShip victimSetup({int hull = 1}) => NpcShip.create(
          faction: FactionClass.trader,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: 11,
          startingCredits: 0,
          seed: 602,
        ).copyWith(
          personality: NpcPersonality.traderMerchant,
          hull: hull,
          maxHull: hull,
          shields: 0,
          maxShields: 0,
          energy: 1000,
          weaponSlots: const {'main_forward': 1},
        );

    List<NpcShip> strike(List<Sector> sectors, List<NpcShip> npcs) {
      final out = List<NpcShip>.from(npcs);
      out[0] = out[0].copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {'targetSectorId': 11, 'targetId': out[1].id},
        ),
      );
      out[0] = NpcAiService.processTurn(out[0], sectors, [], out);
      return out;
    }

    List<Sector> arena() => [
          Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
          Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
        ];

    test('killers grow bolder', () {
      final sectors = arena();
      var npcs = [killerSetup(), victimSetup()];
      npcs = strike(sectors, npcs);
      expect(npcs[1].isDestroyed, isTrue);
      expect(npcs[0].driftAggression, NpcShip.killAggressionStep);
      final base =
          PersonalityConfig.all[NpcPersonality.pirateHunter]!.aggression;
      expect(npcs[0].personalityConfig.aggression,
          closeTo(base + NpcShip.killAggressionStep, 1e-9));
    });

    test('survivors grow warier', () {
      final sectors = arena();
      var npcs = [killerSetup(), victimSetup(hull: 5000)];
      npcs = strike(sectors, npcs);
      expect(npcs[1].isDestroyed, isFalse);
      expect(npcs[1].driftCaution, NpcShip.surviveCautionStep);
      // The killer missed its kill: no boldness earned.
      expect(npcs[0].driftAggression, 0.0);
    });

    test('drift caps instead of compounding forever', () {
      final sectors = arena();
      var killer =
          killerSetup().copyWith(driftAggression: 0.14, driftCaution: 0.14);
      var npcs = [killer, victimSetup()];
      npcs = strike(sectors, npcs);
      expect(npcs[1].isDestroyed, isTrue);
      expect(npcs[0].driftAggression, NpcShip.maxPersonalityDrift);
      expect(npcs[0].personalityConfig.aggression, lessThanOrEqualTo(1.0));
    });

    test('zero drift returns the archetype config itself', () {
      final ship = _npc(FactionClass.trader, 11, 603);
      expect(
          identical(
              ship.personalityConfig, PersonalityConfig.all[ship.personality]),
          isTrue);
      final wary = ship.copyWith(driftCaution: 0.1);
      expect(wary.personalityConfig.caution,
          closeTo(ship.personalityConfig.caution + 0.1, 1e-9));
      // Aggression untouched by caution drift.
      expect(
          wary.personalityConfig.aggression, ship.personalityConfig.aggression);
    });

    test('drift survives JSON round-trip with legacy defaults', () {
      final ship = _npc(FactionClass.duran, 11, 604)
          .copyWith(driftAggression: 0.06, driftCaution: 0.04);
      final restored = NpcShip.fromJson(ship.toJson().cast<String, dynamic>());
      expect(restored.driftAggression, 0.06);
      expect(restored.driftCaution, 0.04);
      final legacy = NpcShip.fromJson(const {
        'id': 'x',
        'shipDefName': 'nope',
        'faction': 'duran',
        'personality': 'duranConqueror',
      });
      expect(legacy.driftAggression, 0.0);
      expect(legacy.driftCaution, 0.0);
      expect(legacy.heroName, isNull);
    });
  });
}
