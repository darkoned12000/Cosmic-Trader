import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Colony supply, the zero-yield harsh types, and the fact that starvation no
/// longer exists.
///
/// The starvation guards are **absent, not inverted**. A colony that cannot
/// starve cannot regress into starving, so there is nothing to assert; a test
/// forbidding the mechanic from returning would outlive its reason. What is
/// asserted instead is the property that replaced it and the two things the
/// replacement must never do — lose colonists, and fail to be satisfiable.
Planet colony({
  String type = 'Terran',
  int population = 10000,
  int minerals = 5000,
  int organics = 3000,
  int industrial = 1500,
  int drones = 500,
  int storedMinerals = 0,
  int storedOrganics = 0,
  int storedIndustrial = 0,
  int level = 1,
}) =>
    Planet(
      name: 'C',
      planetType: type,
      population: population,
      colonistsMinerals: minerals,
      colonistsOrganics: organics,
      colonistsIndustrial: industrial,
      colonistsDrones: drones,
      storedMinerals: storedMinerals,
      storedOrganics: storedOrganics,
      storedIndustrial: storedIndustrial,
      level: level,
    );

/// A colony with **no workforce at all**, so it produces nothing and its stores
/// stay where the fixture left them.
///
/// Every "unpaid" case needs this. A colony with colonists on a track refills
/// its own store well before the bill comes due, so an empty-store fixture on a
/// *producing* colony quietly pays its own way and the test proves nothing.
Planet idleColony({int population = 10000, int level = 1}) => colony(
      population: population,
      minerals: 0,
      organics: 0,
      industrial: 0,
      drones: 0,
      level: level,
    );

/// Runs ticks until the next supply draw comes due, returning that tick.
PlanetTickReport runToSupply(Planet p) {
  PlanetTickReport last = const PlanetTickReport();
  for (var i = 0; i < Planet.supplyInterval; i++) {
    last = p.produce();
  }
  return last;
}

void main() {
  group('the harsh types cannot make organics at all', () {
    test('the multiplier is a true zero, not a small number', () {
      // The distinction is the whole design. 0.2 meant "expensive"; 0.0 means
      // "incapable", and only the second one makes planting a complement the
      // answer rather than a tax to be minimised.
      for (final type in ['Lava', 'Barren', 'Toxic', 'Ice', 'Moon']) {
        expect(Planet.typeMultipliers[type]!.organics, 0.0,
            reason: '$type should produce no organics at all');
      }
    });

    test('the fertile types still can', () {
      for (final type in ['Terran', 'Jungle', 'Desert', 'Ocean', 'Gas Giant']) {
        expect(Planet.typeMultipliers[type]!.organics, greaterThan(0.0),
            reason: '$type should still grow organics');
      }
    });

    test('canProduce reports it, and the UI can lock on it', () {
      final lava = colony(type: 'Lava');
      expect(lava.canProduce('organics'), isFalse);
      expect(lava.canProduce('minerals'), isTrue);
      expect(lava.canProduce('industrial'), isTrue);

      final terran = colony(type: 'Terran');
      for (final c in ['minerals', 'organics', 'industrial', 'drones']) {
        expect(terran.canProduce(c), isTrue);
      }
    });

    test('a harsh world produces no organics however many colonists it assigns',
        () {
      final lava = colony(type: 'Lava', population: 100000, organics: 100000);
      expect(lava.organicOutput, 0,
          reason:
              'assigning the whole workforce to a dead track must be inert');
    });
  });

  group('the supply bill', () {
    test('is charged once every supplyInterval ticks, not every tick', () {
      final p = colony(storedMinerals: 1 << 30);
      var charged = 0;
      for (var i = 0; i < Planet.supplyInterval * 3; i++) {
        if (p.produce().supplyPaid > 0) charged++;
      }
      expect(charged, 3, reason: 'three intervals, three bills');
    });

    test('is a share of the colony\'s own output at every scale', () {
      // The load-bearing property, and the reason the bill is not per-capita.
      // A fixed rate per colonist is trivial at 100 and ruinous at two million.
      for (final pop in [100, 10000, 1000000]) {
        final p = colony(population: pop, minerals: pop ~/ 2);
        // **Per day, because the bill is per day.** The first version summed the
        // per-tick getters, which is a different unit: the bill charges a share
        // of a day's output once a day, so dividing it by a tick's output gave a
        // share 2,880x too large - and for a small colony, whose per-tick output
        // rounds to zero, the division returned Infinity and the assertion was
        // measuring nothing.
        //
        // The per-tick getters also *consume* the production remainder, so
        // summing them here would have advanced the colony's production as a
        // side effect of measuring it.
        final output = p.outputPerDayFor('minerals') +
            p.outputPerDayFor('organics') +
            p.outputPerDayFor('industrial');
        expect(output, greaterThan(0),
            reason: 'sanity: population $pop must make something');
        final share = p.supplyDraw / output;
        expect(share, closeTo(Planet.supplyShareOfOutput, 0.01),
            reason:
                'at population $pop the bill is ${(share * 100).toStringAsFixed(1)}% '
                'of output, but it must not vary with scale');
      }
    });

    test('is always payable by a colony that has stock', () {
      // The "if a planet doesn't make minerals it pulls from another
      // resource" rule. A world short of the drawn commodity falls back, so the
      // bill can never be unsatisfiable by a type's multiplier alone.
      for (final type in Planet.allTypes) {
        final p = colony(
          type: type,
          population: 10000,
          minerals: 5000,
          organics: 3000,
          industrial: 1500,
          storedMinerals: 1 << 20,
          storedOrganics: 1 << 20,
          storedIndustrial: 1 << 20,
        );
        final report = runToSupply(p);
        expect(report.supplyFrom, isNotNull, reason: '$type drew nothing');
        expect(report.supplyShortfall, 0,
            reason: '$type had stock in all three and still went short');
      }
    });

    test('falls back to another commodity when the drawn one is empty', () {
      final p = idleColony()..storedIndustrial = 1 << 20;
      final report = runToSupply(p);
      expect(report.supplyFrom, isNotNull);
      expect(report.supplyShortfall, 0);
      expect(p.storedIndustrial, lessThan(1 << 20),
          reason: 'it must have been paid out of the only thing it had');
    });

    test('draws from the shipment pool, not just the working store', () {
      // The property that survived the mechanic change: goods already produced
      // and awaiting collection are still goods. A busy colony must not be told
      // it cannot feed itself while its own output sits unclaimed.
      final p = idleColony();
      // Stocked directly rather than produced over time: a colony producing
      // into the pool would also be refilling the working store, and the
      // property under test is specifically that the *pool alone* is enough.
      p.pendingMinerals = 1 << 20;
      p.pendingOrganics = 1 << 20;
      p.pendingIndustrial = 1 << 20;
      expect(p.storedMinerals, 0, reason: 'sanity: the working store is empty');
      expect(p.pendingTotal, greaterThan(0),
          reason: 'sanity: the pool is full');

      final report = runToSupply(p);
      expect(report.supplyShortfall, 0,
          reason: 'a full shipment pool must count toward the bill');
    });

    test('never charges drones', () {
      // Drones are combat units, not a consumable. A colony that ate its own
      // drone force would be nonsense, and drones have no market value anyway.
      for (final c in Planet.supplyCommodities) {
        expect(c, isNot('drones'));
      }
    });
  });

  group('there is no starvation', () {
    test('an empty colony loses nobody', () {
      // The replacement for every deleted starvation guard. Nothing dies, ever,
      // so this is the assertion that actually holds for the whole mechanic.
      final p = idleColony();
      final before = p.population;
      for (var i = 0; i < 500; i++) {
        p.produce();
      }
      expect(p.population, before,
          reason: 'an unpaid supply bill is not a death sentence');
    });

    test('an unpaid bill is reported rather than inflicted', () {
      final p = idleColony();
      final report = runToSupply(p);
      expect(report.supplyShortfall, greaterThan(0));
      expect(report.isUnsupplied, isTrue);
      expect(report.isInteresting, isTrue,
          reason: 'it is the one thing a player must act on');
    });

    test('the service counts unsupplied colonies', () {
      final p = idleColony();
      final sector = Sector(
        id: 1,
        name: 'S',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [p],
      );
      // Stop one tick short, so the **service pass** is the tick the bill comes
      // due on. Running a full interval first would have the draw fire early and
      // leave the service looking at an ordinary production tick.
      for (var i = 0; i < Planet.supplyInterval - 1; i++) {
        p.produce();
      }
      final summary = PlanetProductionService.process([sector]);
      expect(summary.unsupplied, 1);
      expect(summary.supplyPaid, 0, reason: 'it had nothing to take');
      expect(summary.isQuiet, isFalse);
    });
  });

  group('the draw is visible to the player', () {
    test('the countdown is reported before the bill lands', () {
      final p = colony(storedMinerals: 1 << 20);
      expect(p.ticksToSupply, Planet.supplyInterval);
      p.produce();
      expect(p.ticksToSupply, Planet.supplyInterval - 1);
    });

    test('a dead colony has no bill', () {
      expect(colony(population: 0).supplyDraw, 0);
      expect(colony(population: 0).ticksToSupply, Planet.supplyInterval,
          reason: 'an empty colony is never billed');
    });

    test('a colony holding goods is not short of supply', () {
      // `storesEmpty` drives the warning, so it must mean "cannot pay" and not
      // "has nothing", or a well-stocked colony warns about nothing.
      final stocked = idleColony()..storedMinerals = 500;
      expect(stocked.storesEmpty, isFalse);
      expect(idleColony().storesEmpty, isTrue);
    });
  });
}
