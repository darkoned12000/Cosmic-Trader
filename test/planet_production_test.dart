import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
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
  /// Units of [track] a colony should bank in a whole day.
  ///
  /// The triangle, then the colony's own yield. Written out here rather than
  /// called from the model so that this file is checking the *rule* rather than
  /// agreeing with itself — the previous version of this helper restated the old
  /// linear formula, which meant the tests passed against whatever that formula
  /// was and could not have caught its replacement.
  int expectedPerDay({
    required int colonists,
    required String track,
    String type = 'Terran',
    double efficiency = 1.0,
    int level = 1,
  }) {
    final spec = planetClasses[type]!.productFor(track);
    final base = spec.outputPerDay(colonists);
    if (base <= 0) return 0;
    final yield_ = efficiency * (Planet.levelDevelopment[level] ?? 1.0);
    // Clamped, because that is part of the rule: the colony's yield scales a
    // figure that is already the peak, so it can never lift a colony past the
    // class ceiling. Without the clamp the helper and the model disagree at
    // exactly the point the tests below are checking.
    final scaled = (base * yield_).round();
    return scaled > spec.maxOutputPerDay ? spec.maxOutputPerDay : scaled;
  }

  group('the formula', () {
    test('output per day follows the triangle, not a linear product', () {
      // The Volcanic ore track: ratio 1, maximum 100,000 colonists, so the
      // optimum is 50,000 and the peak is 50,000/day.
      final atPeak =
          colony(type: 'Lava', population: 50000, minerals: 50000, drones: 0);
      expect(atPeak.outputPerDayFor('minerals'),
          expectedPerDay(colonists: 50000, track: 'minerals', type: 'Lava'),
          reason: 'sanity: the helper agrees with the model at the peak');
      expect(atPeak.outputPerDayFor('minerals'), 50000,
          reason: 'the published Volcanic peak');

      // Per-tick is a *fraction* of that, because a day is 2,880 ticks. The
      // per-tick getter is the one that consumes the remainder, so it is called
      // once and asserted on its own terms rather than being compared against a
      // per-day figure.
      expect(PlanetClock.perDayToPerTick(50000), closeTo(17.361, 0.001));
      expect(atPeak.mineralOutput, 17,
          reason: '17 whole units banked in the first tick, the fraction '
              'carried forward');
    });

    test('staffing past the optimum reduces output', () {
      // The mechanic. 55,000 colonists on a Volcanic ore track must produce
      // LESS than the 50,000 that 50,000 colonists produce.
      final peak = colony(type: 'Lava', population: 50000, minerals: 50000);
      final over = colony(type: 'Lava', population: 55000, minerals: 55000);
      expect(over.outputPerDayFor('minerals'), 45000);
      expect(over.outputPerDayFor('minerals'),
          lessThan(peak.outputPerDayFor('minerals')),
          reason: 'overshooting the peak must cost output, not merely stop '
              'helping — that is the whole mechanic');
    });

    test('efficiency scales output but cannot lift it past the cap', () {
      // The old formula multiplied the colonists, so efficiency could push a
      // colony past the peak the cap exists to enforce — the two rules
      // contradicted each other. Applied to the capped output instead, a
      // colony can approach its ceiling faster but never exceed it.
      // Below the peak, efficiency visibly helps: a well-run colony reaches its
      // ceiling sooner, which is the whole point of investing in a world.
      final plain = colony(type: 'Lava', population: 25000, minerals: 25000);
      final efficient = colony(
          type: 'Lava', population: 25000, minerals: 25000, efficiency: 2.0);
      expect(plain.outputPerDayFor('minerals'), 25000);
      expect(efficient.outputPerDayFor('minerals'), 50000);
      expect(efficient.outputPerDayFor('minerals'),
          greaterThan(plain.outputPerDayFor('minerals')));

      // At the peak it must NOT help, because the peak *is* the ceiling. This
      // assertion is the clamp's reason to exist: the first implementation
      // scaled the already-capped figure without a ceiling, so 2.0 efficiency at
      // the optimum produced 100,000 against a class maximum of 50,000.
      final atPeak = colony(type: 'Lava', population: 50000, minerals: 50000);
      final atPeakEfficient = colony(
          type: 'Lava', population: 50000, minerals: 50000, efficiency: 4.0);
      expect(atPeak.outputPerDayFor('minerals'), 50000);
      expect(atPeakEfficient.outputPerDayFor('minerals'), 50000,
          reason: 'no amount of efficiency lifts a colony past the class '
              'ceiling; two rules that contradict is what the cap prevents');
      // Twice the yield on the peak is still bounded by the class figure.
      expect(efficient.outputPerDayFor('minerals'), lessThanOrEqualTo(50000));
    });

    test('a world still has an identity at every level', () {
      // The balance reason for a shallow development curve: a developed Volcanic
      // world stays a mineral powerhouse rather than becoming a universal one.
      final lava = colony(
          type: 'Lava',
          population: 50000,
          minerals: 50000,
          level: 6,
          storedOrganics: 1 << 30);
      // Both tracks staffed with the *same* 50,000 colonists, so the comparison
      // is about the worlds rather than about how they were set up. The first
      // version of this test asserted `ocean.organicOutput > 0` style
      // cross-specialty checks without putting anyone on the other track, which
      // made them 0 trivially and proved nothing.
      final ocean = colony(
          type: 'Ocean',
          population: 50000,
          minerals: 50000,
          organics: 50000,
          level: 6,
          storedOrganics: 1 << 30);

      expect(
          lava.outputPerDayFor('minerals'),
          expectedPerDay(
              colonists: 50000, track: 'minerals', type: 'Lava', level: 6));
      expect(
          ocean.outputPerDayFor('organics'),
          expectedPerDay(
              colonists: 50000, track: 'organics', type: 'Ocean', level: 6));
      // Neither world is good at the other's speciality, and the difference is
      // one of *degree*, not of possibility.
      expect(lava.outputPerDayFor('organics'), 0,
          reason: 'a Volcanic world cannot make organics at all — the track is '
              'impossible, not merely bad');
      expect(ocean.outputPerDayFor('minerals'), greaterThan(0),
          reason: 'an Ocean world is a poor ore world, not an impossible one — '
              'its tables give a ratio of 20 colonists per unit');
      // Same 50,000 colonists, and it is the world's identity doing the work.
      // Volcanic ore peaks at 50,000/day. Ocean ore is 20 colonists per unit, so
      // 50,000 colonists reach 2,500 - doubled by level 6 development to 5,000,
      // which is exactly the Ocean's own class ceiling and is clamped there.
      expect(lava.outputPerDayFor('minerals'), 50000);
      expect(ocean.outputPerDayFor('minerals'), 5000);
      expect(ocean.maxDailyOutputFor('minerals'), 5000,
          reason: 'and it is sitting on its own ceiling, not merely near it');
      expect(
          ocean.outputPerDayFor('minerals') / lava.outputPerDayFor('minerals'),
          closeTo(0.1, 0.01),
          reason: 'ten times less ore from an identical workforce');
    });

    test('a world type with no data produces nothing rather than guessing', () {
      // This inverts an earlier assertion, and deliberately. The old formula
      // fell back to a 1.0 multiplier for an unknown type, which meant a world
      // nobody had planned for silently produced at the default. "We have no
      // rules for this" is honestly answered by producing nothing, which is also
      // what the Class U case does on purpose.
      final p = colony(
          type: 'Not A Planet',
          population: 100,
          minerals: 100,
          storedOrganics: 1 << 30);
      expect(p.outputPerDayFor('minerals'), 0);
      expect(p.produce().mineralsGained, 0,
          reason: 'an unclassifiable world must not bank resources from '
              'nowhere');
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
      // 900, not 1000: the fixture's 100 drone colonists are no longer on a
      // track, because drones are derived from output rather than staffed. They
      // sit in the reserve, and a shortfall after a population loss comes from
      // there.
      expect(p.assignedColonists, 900);
      expect(p.reserveColonists, 100);

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
      //
      // Measured **below the peak**, because at the optimum the comparison is
      // meaningless: both colonies sit on the class ceiling, the clamp flattens
      // them to the same number, and the ratio is 1.0. The development curve
      // governs how fast a colony *approaches* its ceiling, so it has to be
      // measured where the ceiling is not binding. Half the optimum.
      //
      // And on the per-day figure, not the per-tick getter: at half the optimum
      // a Terran ore track yields 2,500/day, which is under one unit per tick,
      // so the per-tick draw is 0 on the first tick and the ratio came out NaN.
      final low = colony(population: 7500, minerals: 7500, level: 1);
      final high = colony(population: 7500, minerals: 7500, level: 6);
      expect(low.outputPerDayFor('minerals'), 2500);
      expect(high.outputPerDayFor('minerals'), 5000);
      expect(high.outputPerDayFor('minerals') / low.outputPerDayFor('minerals'),
          closeTo(2.0, 0.01));
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
