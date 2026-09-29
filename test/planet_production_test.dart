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
      // Capture before producing: the getter is live and a starvation tick
      // would rebalance the workforce, so reading it afterwards compares a
      // post-mutation value against a pre-mutation report.
      final output = p.mineralOutput;
      p.storedMinerals = p.maxMinerals - output;

      final report = p.produce();

      expect(report.mineralsGained, output);
      expect(p.storedMinerals, p.maxMinerals);
      expect(p.pendingMinerals, 0);
      expect(report.shipmentQueued, 0);
    });

    test('surplus goes to the shipment pool, not the bin', () {
      final p = colony(
          type: 'Lava',
          population: 1000,
          minerals: 1000,
          storedOrganics: 1000000);
      p.storedMinerals = p.maxMinerals;

      final produced = p.mineralOutput;
      final report = p.produce();

      expect(p.storedMinerals, p.maxMinerals, reason: 'already full');
      expect(p.pendingMinerals, produced,
          reason: 'every unit still owed to the player');
      expect(report.shipmentQueued, produced);
      expect(report.storageOverflowed, isFalse,
          reason: 'a full working store is normal operation, not a loss');
    });

    test('only a full shipment pool is a genuine loss', () {
      final p = colony(
          type: 'Gas Giant',
          population: 1000,
          minerals: 1000,
          storedOrganics: 1000000);
      // Fill both the store and the pool.
      p.storedMinerals = p.maxMinerals;
      p.pendingMinerals = p.maxMinerals * Planet.pendingCapMultiple;

      final report = p.produce();

      expect(report.storageOverflowed, isTrue,
          reason: 'a colony ignored long enough to overflow even the pool is '
              'the one case worth warning about');
    });

    test('caps are per commodity, not one shared number', () {
      // A Lava world is vast for minerals and almost useless for organics;
      // an Ocean world is the reverse. One shared cap destroyed that.
      final lava = colony(type: 'Lava', population: 10);
      final ocean = colony(type: 'Ocean', population: 10);

      expect(lava.maxMinerals, greaterThan(lava.maxOrganics * 10));
      expect(ocean.maxOrganics, greaterThan(ocean.maxMinerals * 5));
      expect(lava.maxMinerals, isNot(ocean.maxMinerals));
    });

    test('storage grows with Citadel level', () {
      final low = colony(type: 'Terran', population: 10)..level = 1;
      final high = colony(type: 'Terran', population: 10)..level = 6;
      expect(high.maxMinerals, greaterThan(low.maxMinerals * 5));
      expect(high.maxOrganics, high.maxMinerals,
          reason: 'Terran stores all three equally');
    });

    test('a large colony can never out-produce its own store', () {
      // The guard the previous version was missing. A fixed per-type cap cannot
      // serve both a colony of a hundred and a colony of two million: the big
      // one filled its store in under a tick and overflowed for the other
      // 99.4%, whatever the output scale was set to. The cap is therefore
      // floored at `minimumTicksOfOutput` of the colony's own output, so this
      // holds at *any* size — which is the point of computing it rather than
      // tuning a constant.
      for (final population in [1000, 100000, 2000000]) {
        final p = colony(
            type: 'Terran',
            population: population,
            minerals: (population * 0.6).round(),
            storedOrganics: 1 << 30);
        expect(
          p.maxMinerals,
          greaterThanOrEqualTo(p.mineralOutput * Planet.minimumTicksOfOutput),
          reason: 'a colony of $population must be able to hold its own '
              'output',
        );
        // And so must it hold that for a working day without wasting anything.
        p.storedMinerals = 0;
        for (var i = 0; i < Planet.minimumTicksOfOutput; i++) {
          p.produce();
        }
        expect(p.pendingMinerals, 0,
            reason: 'a colony of $population wasted output inside a single '
                'working window');
      }
    });

    test('drones are a defence product and track the mineral store', () {
      final lava = colony(type: 'Lava', population: 10);
      expect(lava.maxDrones, (lava.maxMinerals * 0.25).round());
    });

    test('collecting empties the pool and reports what was owed', () {
      final p = colony(
          type: 'Lava',
          population: 1000,
          minerals: 1000,
          storedOrganics: 1000000);
      p.storedMinerals = p.maxMinerals;
      p.produce();
      expect(p.pendingMinerals, greaterThan(0));

      final collected = p.collectShipment();

      expect(collected['minerals'], p.maxMinerals == 0 ? 0 : greaterThan(0));
      expect(collected.containsKey('minerals'), isTrue);
      expect(p.pendingMinerals, 0);
      expect(p.pendingTotal, 0);
    });

    test('an old save holding more than the new cap is not destroyed', () {
      // Caps are derived now, so an existing world can sit above its cap. The
      // goods must survive: the store simply stops accepting more.
      final p = colony(
          type: 'Gas Giant',
          population: 100,
          minerals: 100,
          storedOrganics: 100000);
      final over = p.maxMinerals + 50000;
      final output = p.mineralOutput;
      p.storedMinerals = over;

      final report = p.produce();

      expect(p.storedMinerals, over,
          reason: 'existing goods are never clamped away');
      expect(p.pendingMinerals, output,
          reason: 'new output routes around the full store');
      expect(report.mineralsGained, 0,
          reason: 'and none of it is claimed as gained into the store');
    });
  });

  group('upkeep', () {
    // Upkeep and output are both divided by Planet.baseOutputPerColonist, so
    // every ratio here is independent of that constant: a colony still breaks
    // even with 1/10th of its population on organics at 1.0x multipliers.
    test('a colony is charged for its population', () {
      final p = colony(population: 1000, storedOrganics: 1 << 30);
      final before = p.storedOrganics;
      p.produce();
      expect(before - p.storedOrganics, p.organicsUpkeep,
          reason: 'upkeep is the only thing that should have moved organics');
    });

    test('production lands before upkeep, so a farm feeds itself', () {
      // Order is the whole equilibrium argument. Charging upkeep first would
      // make a colony that exactly feeds itself bleed out anyway.
      final p = colony(population: 1000, organics: 100, storedOrganics: 0);
      // 100 organics colonists at 1.0x, level 1.
      final output = p.organicOutput;
      expect(p.organicsUpkeep, output,
          reason: 'this is the break-even case, and it must actually be one');

      p.produce();
      expect(p.storedOrganics, 0, reason: 'it produced exactly what it ate');
    });

    test('a self-sufficient colony is stable over many ticks', () {
      // The property that makes the upkeep number worth having. A colony that
      // farms exactly enough organics must neither grow nor shrink, and must not
      // quietly pile up a shipment backlog either.
      final p = colony(population: 1000, organics: 100);
      expect(p.organicOutput, p.organicsUpkeep);
      for (var i = 0; i < 50; i++) {
        p.produce();
      }
      expect(p.population, 1000);
      expect(p.storedOrganics, 0, reason: 'steady state, no drift');
      expect(p.pendingTotal, 0,
          reason: 'break-even must not accumulate a shipment backlog');
    });

    test('a colony with spare organics banks the surplus', () {
      // The other side of equilibrium, and the reason the share above is 1/10
      // rather than 1/1: over-farming organics is a legitimate choice with a
      // real payoff, and under-farming is a slow death.
      final p = colony(population: 1000, organics: 300, storedOrganics: 0);
      p.produce();
      expect(p.storedOrganics, p.organicOutput - p.organicsUpkeep);
      expect(p.storedOrganics, greaterThan(0));
      expect(p.population, 1000);
    });

    test('the share needed to feed a colony depends on its organics type', () {
      // A Lava world (organics 0.2x) needs five times the organics workforce of
      // a Terran one for the same population. That is the intended pressure:
      // barren-world colonies are expensive to run and lean on imports.
      final terran = colony(type: 'Terran', population: 1000, organics: 100);
      final lava = colony(type: 'Lava', population: 1000, organics: 500);
      expect(lava.organicOutput, terran.organicOutput);
      expect(terran.organicOutput, terran.organicsUpkeep);
      expect(lava.organicOutput, lava.organicsUpkeep);
    });

    test('a break-even colony queues nothing', () {
      // A Volcanic world at 0.2x organics needs half its population farming
      // food just to stand still. At exact break-even there is no surplus at
      // all, so nothing should accumulate anywhere.
      final p = colony(
        type: 'Lava',
        population: 100000,
        organics: 50000,
        minerals: 50000,
        storedOrganics: 0,
      );
      expect(p.organicOutput, p.organicsUpkeep,
          reason: 'sanity: this fixture is the break-even case');
      for (var i = 0; i < 200; i++) {
        p.produce();
      }
      expect(p.pendingTotal, 0, reason: 'nothing to ship');
      expect(p.population, 100000, reason: 'and it never starves');
    });

    test('a colony does not starve on food it has already produced', () {
      // Regression, and the actual point of drawing upkeep from the shipment
      // pool as well as the working store.
      //
      // A busy poor-organics world fills its store, spills the surplus into the
      // pool, and then has a working store of zero. Upkeep charged only the
      // store, so such a world starved while tens of thousands of organics sat
      // unclaimed beside it. Barren worlds are meant to be expensive to feed,
      // not impossible.
      //
      // Two phases, because only this sequence discriminates. A colony that
      // merely over-produces can feed itself from current output either way, so
      // the fixture stocks the pool while the workforce is large, then cuts the
      // organists so production alone is no longer enough.
      final p = colony(
        type: 'Lava',
        population: 100000,
        organics: 100000, // 200/tick against an upkeep of 100
        storedOrganics: 0,
      );
      expect(p.organicOutput, greaterThan(p.organicsUpkeep));

      for (var i = 0; i < 500; i++) {
        p.produce();
      }
      expect(p.pendingOrganics, greaterThan(0),
          reason: 'sanity: the pool should have filled');
      expect(p.population, 100000, reason: 'sanity: it was fed throughout');

      // Now starve it of labour: output drops below upkeep, and the working
      // store is emptied so the only food left is in the pool.
      p.colonistsOrganics = 25000;
      p.storedOrganics = 0;
      expect(p.organicOutput, lessThan(p.organicsUpkeep),
          reason: 'sanity: production alone is no longer sufficient');

      for (var i = 0; i < 100; i++) {
        p.produce();
      }
      expect(p.population, 100000,
          reason: 'organics already produced are still food');
      expect(p.pendingOrganics, greaterThan(0),
          reason: 'and it was drawing them down, not starving');
    });
  });

  group('starvation', () {
    test('a colony that cannot feed itself loses colonists', () {
      final p = colony(population: 100000, storedOrganics: 10);
      final upkeep = p.organicsUpkeep;
      final report = p.produce();

      expect(report.isStarving, isTrue);
      expect(report.organicsShortfall, upkeep - 10,
          reason: 'needed the whole upkeep and found 10');
      expect(report.colonistsLost, greaterThan(0));
      expect(p.population, lessThan(100000));
      expect(p.storedOrganics, 0, reason: 'it ate what it had');
    });

    test('starvation is a bleed, not an extinction', () {
      // Without the 2% cap a colony with no organics would lose everyone in
      // one tick, which no amount of emergency delivery could recover from.
      final p = colony(population: 10000, storedOrganics: 0);
      p.produce();
      expect(p.population, greaterThanOrEqualTo(9800));
    });

    test('a full collapse over many ticks if nothing changes', () {
      // The bleed compounds, so this needs far more ticks than it looks. From
      // 10,000 measured: 10% gone in 3 minutes, half in 17, and zero only at
      // about 170 minutes. A 1,000-colony test colony therefore needs ~300
      // ticks, not the 200 this first asserted — the shortfall was mine, not
      // the code's, and it hid the fact that extinction really is slow.
      final p = colony(population: 1000);
      var ticks = 0;
      while (p.population > 0 && ticks < 1000) {
        p.produce();
        ticks++;
      }
      expect(p.population, 0, reason: 'an un-fed colony eventually dies out');
      expect(ticks, greaterThan(100),
          reason: 'and it must not be quick — a wipe would be unrecoverable');
    });

    test('a colony below the bleed threshold still finishes dying', () {
      // Regression. `floor(population * 0.02)` is 0 below 50 colonists, so the
      // starvation cap used to floor the loss to zero and a starving colony
      // froze at 49 — a permanent zombie world, starving forever, that could
      // not be saved by delivering organics because the tick took nothing.
      final p = colony(population: 40);
      for (var i = 0; i < 60 && p.population > 0; i++) {
        p.produce();
      }
      expect(p.population, 0, reason: 'an un-fed colony must actually die');
    });

    test('a starving colony can still be saved by delivering organics', () {
      // The other half: the bleed has to be slow enough to recover from, or
      // the cap is a death sentence rather than a difficulty setting.
      final p = colony(population: 10000);
      p.produce();
      expect(p.population, lessThan(10000));
      expect(p.population, greaterThan(9500), reason: 'a bleed, not a wipe');

      // Deliver a surplus and the colony stops shrinking.
      p.storedOrganics = 50000;
      for (var i = 0; i < 5; i++) {
        p.produce();
      }
      expect(p.population, greaterThan(9500));
    });

    test('a dead colony stops producing and stops costing anything', () {
      final p = colony(population: 0, minerals: 500);
      final report = p.produce();
      expect(report.isInteresting, isFalse);
      expect(p.storedMinerals, 0);
      expect(p.organicsUpkeep, 0);
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
        hasPlanet: planet != null,
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

    test('reports a starving colony', () {
      final starving = colony(population: 1000);
      final summary = PlanetProductionService.process([sectorWith(starving)]);
      expect(summary.starving, 1);
      expect(summary.colonistsLost, greaterThan(0));
    });
  });
}
