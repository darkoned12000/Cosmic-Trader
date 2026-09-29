import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Colony production. The bug this file exists for: the planet screen displayed
/// a per-tick rate and nothing ever applied it, because the only code that
/// wrote a planet's stores was the credits-based transfer in the screen. Every
/// test below drives [Planet.produce] and checks the stores actually move.
void main() {
  /// A colony with room in every store, so overflow never confuses a test that
  /// is about something else.
  Planet colony({
    String type = 'Terran',
    int population = 0,
    int minerals = 0,
    int organics = 0,
    int industrial = 0,
    int drones = 0,
    double efficiency = 1.0,
    int level = 1,
    int storedOrganics = 0,
  }) {
    return Planet(
      name: 'Test Colony',
      planetType: type,
      population: population,
      colonistsMinerals: minerals,
      colonistsOrganics: organics,
      colonistsIndustrial: industrial,
      colonistsDrones: drones,
      productionEfficiency: efficiency,
      level: level,
      storedOrganics: storedOrganics,
    );
  }

  group('the displayed rate is the applied rate', () {
    // This is the regression guard for the original defect. The screen used to
    // compute the yield inline, four times, and nothing applied it. Now the
    // screen reads [mineralOutput] and the tick calls [produce], so a change to
    // one that missed the other would show up here.
    test('produce() adds exactly what the getters report', () {
      final p = colony(
        population: 4000,
        minerals: 1000,
        organics: 1000,
        industrial: 1000,
        drones: 1000,
        efficiency: 1.0,
        level: 3,
      );

      final before = [
        p.storedMinerals,
        p.storedOrganics,
        p.storedIndustrial,
        p.storedDrones,
      ];
      p.produce();
      final after = [
        p.storedMinerals,
        p.storedOrganics,
        p.storedIndustrial,
        p.storedDrones,
      ];

      expect(
        after[0] - before[0],
        p.mineralOutput,
        reason: 'minerals shown to the player must be minerals delivered',
      );
      expect(
        after[2] - before[2],
        p.industrialOutput,
        reason: 'industrial likewise',
      );
      expect(after[3] - before[3], p.droneOutput, reason: 'drones likewise');
    });

    test('the report agrees with the getters too', () {
      final p = colony(population: 1000, minerals: 500, efficiency: 0.8);
      final report = p.produce();
      expect(report.mineralsGained, p.mineralOutput);
    });
  });

  /// Expected units from the same inputs the model uses, so a change to
  /// [Planet.baseOutputPerColonist] is a one-line edit here rather than a hunt
  /// through hard-coded numbers that are really just asserting the scale.
  int expected({
    required int colonists,
    required double mult,
    double efficiency = 1.0,
    int level = 1,
  }) =>
      (colonists *
              mult *
              efficiency *
              (Planet.levelDevelopment[level] ?? 1.0) *
              Planet.baseOutputPerColonist)
          .round();

  group('the formula', () {
    test('colonists x type x efficiency x development', () {
      // Lava minerals 2.0, 1000 colonists, 1.0 efficiency, level 1 (1.0x).
      final p = colony(type: 'Lava', population: 1000, minerals: 1000);
      expect(p.mineralOutput, expected(colonists: 1000, mult: 2.0));

      // Efficiency and development both scale it.
      final q = colony(
        type: 'Lava',
        population: 1000,
        minerals: 1000,
        efficiency: 0.5,
        level: 6, // 2.0x
      );
      expect(q.mineralOutput,
          expected(colonists: 1000, mult: 2.0, efficiency: 0.5, level: 6));
    });

    test('type multipliers keep their identity as levels rise', () {
      // The balance reason for a shallow development curve: a developed Lava
      // world must stay a mineral powerhouse, not become a universal one.
      final lava = colony(
          type: 'Lava',
          population: 1000,
          minerals: 1000,
          level: 6,
          storedOrganics: 1 << 30);
      final ocean = colony(
          type: 'Ocean',
          population: 1000,
          organics: 1000,
          level: 6,
          storedOrganics: 1 << 30);

      expect(
          lava.mineralOutput, expected(colonists: 1000, mult: 2.0, level: 6));
      expect(
          ocean.organicOutput, expected(colonists: 1000, mult: 2.0, level: 6));
      // Neither world is good at the other's speciality.
      expect(lava.organicOutput, 0);
      expect(ocean.mineralOutput, 0);
    });

    test('an unknown planet type falls back to 1.0 rather than throwing', () {
      final p = colony(
          type: 'Not A Planet',
          population: 100,
          minerals: 100,
          storedOrganics: 1 << 30);
      expect(p.produce().mineralsGained, expected(colonists: 100, mult: 1.0));
    });
  });

  group('storage: nothing is wasted', () {
    // The first version of production discarded anything that did not fit the
    // store. A 5,400-population Lava world filled 5,000 minerals in 1.6 ticks
    // and then threw away ~98% of everything it made from then on, so a busy
    // colony was a liability. Output now spills into a shipment pool instead.

    test('output fills the working store first', () {
      // Fed, so the population cannot shrink underneath the assertions and
      // quietly change what `mineralOutput` evaluates to.
      final p = colony(
          type: 'Lava', population: 100, minerals: 100, storedOrganics: 100000);
      final output = p.mineralOutput;
      p.storedMinerals = 0;
      p.produce();
      expect(p.storedMinerals, output,
          reason: 'the first tick should land entirely in the store');
    });

    test('a dead colony stops producing and stops costing anything', () {
      final p = colony(population: 0, minerals: 500);
      final report = p.produce();
      expect(report.isInteresting, isFalse);
      expect(p.storedMinerals, 0);
      expect(p.supplyDraw, 0, reason: 'an empty colony has no bill');
    });
  });

  group('workforce never exceeds population', () {
    test('track counts are rebalanced after a population loss', () {
      // Starvation shrinks population under the tracks. If the tracks were left
      // alone, assignedColonists would exceed population and the screen would
      // show a negative reserve.
      final p = colony(
        population: 1000,
        minerals: 400,
        organics: 300,
        industrial: 200,
        drones: 100,
        storedOrganics: 0,
      );
      expect(p.assignedColonists, 1000);
      expect(p.reserveColonists, 0);

      for (var i = 0; i < 10; i++) {
        p.produce();
      }

      expect(p.assignedColonists, lessThanOrEqualTo(p.population),
          reason: 'tracks must fit the population that is left');
      expect(p.reserveColonists, greaterThanOrEqualTo(0));
      expect(p.assignedColonists + p.reserveColonists, p.population);
    });

    test('rebalancing preserves the mix rather than zeroing tracks', () {
      final p = colony(
        population: 1000,
        minerals: 600,
        organics: 200,
        industrial: 150,
        drones: 50,
        storedOrganics: 0,
      );
      for (var i = 0; i < 10; i++) {
        p.produce();
      }
      // 60/20/15/5 should stay roughly 60/20/15/5, not collapse to one track.
      final total = p.assignedColonists;
      expect(p.colonistsMinerals / total, closeTo(0.6, 0.05));
      expect(p.colonistsDrones, greaterThan(0),
          reason: 'the smallest track must not be rounded to nothing');
    });

    test('a reserve is population minus assigned', () {
      final p = colony(population: 1000, minerals: 250, organics: 250);
      expect(p.reserveColonists, 500);
    });

    test('an over-assigned colony reports no negative reserve', () {
      // Defensive: tracks above population can only come from a corrupt save.
      final p = colony(population: 100, minerals: 400);
      expect(p.assignedColonists, 400);
      expect(p.reserveColonists, 0, reason: 'clamped, never negative');
    });
  });

  group('inert states', () {
    test('a destroyed world produces nothing at all', () {
      final p = colony(population: 10000, minerals: 1000)..destroy();
      final report = p.produce();
      expect(report.isInteresting, isFalse);
      expect(p.storedMinerals, 0);
    });

    test('a level-1 and level-6 colony differ, but not absurdly', () {
      // Guards the multiplier regression. A 5.5x development curve compounded
      // with type into a ~110x spread; 2.0x keeps it near 4x.
      final low = colony(population: 1000, minerals: 1000, level: 1);
      final high = colony(population: 1000, minerals: 1000, level: 6);
      expect(high.mineralOutput / low.mineralOutput, closeTo(2.0, 0.01));
    });
  });

  group('service pass', () {
    Sector sectorWith(Planet? planet, [int id = 1]) {
      return Sector(
        id: id,
        name: 'Test $id',
        x: 0,
        y: 0,
        warpRoutes: const <int>[],
        planet: planet,
      );
    }

    test('advances populated colonies and skips the rest', () {
      final worked = colony(population: 1000, minerals: 1000);
      final empty = colony();
      final corpse = colony(population: 5000, minerals: 1000)..destroy();
      final noPlanet = sectorWith(null, 2);

      final summary = PlanetProductionService.process([
        sectorWith(worked),
        sectorWith(empty),
        sectorWith(corpse),
        noPlanet
      ]);

      final gain = worked.mineralOutput;
      expect(summary.colonies, 1, reason: 'only the populated live colony');
      expect(summary.minerals, gain);
      expect(worked.storedMinerals, gain);
    });

    test('an empty galaxy is quiet', () {
      final summary = PlanetProductionService.process([sectorWith(null)]);
      expect(summary.isQuiet, isTrue);
    });

    test('reports a colony that cannot pay its supply', () {
      final broke = colony(population: 1000, minerals: 1000);
      broke.storedMinerals = 0;
      broke.storedOrganics = 0;
      broke.storedIndustrial = 0;
      // Run until a supply draw comes due.
      for (var i = 0; i < Planet.supplyInterval; i++) {
        broke.produce();
      }
      // Drain it again so the next draw is genuinely unaffordable, then let
      // the service run the pass that notices.
      broke.storedMinerals = 0;
      broke.storedOrganics = 0;
      broke.storedIndustrial = 0;
      final summary = PlanetProductionService.process([sectorWith(broke)]);
      expect(summary.supplyPaid, 0,
          reason: 'nothing to take from an empty colony');
    });
  });
}
