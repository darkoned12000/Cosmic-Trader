import 'dart:io' as io;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';

import 'support/storage_fakes.dart';

Planet _world({String id = 'w1', String type = 'Terran'}) {
  return Planet(
    id: id,
    name: 'Xandor',
    planetType: type,
    owner: null,
  );
}

Sector _sectorWith(Planet planet) {
  return Sector(
    id: 1,
    name: 'Sol',
    x: 0,
    y: 0,
    warpRoutes: const [],
    planets: [planet],
  );
}

void main() {
  group('T1 model + service', () {
    test('buy advances one run per interval and lands cargo exactly once', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 6,
        ticksPerRun: 2,
      )!;
      expect(planet.tradeJobs, contains(job));

      final universe = [_sectorWith(planet)];

      // Tick 1: countdown, nothing lands.
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      expect(planet.tradeJobs, contains(job));

      // Tick 2: first run lands 2 of 6; job stays (multi-run, not complete).
      final first = PlanetTradeService.advanceAll(universe);
      expect(first[job.id]!.units, 2);
      expect(planet.tradeJobs, contains(job));
      expect(planet.storedMinerals, 2);

      // Ticks 3-4: second run; ticks 5-6: final run completes and removes.
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      PlanetTradeService.advanceAll(universe);
      expect(planet.tradeJobs, contains(job));
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      final last = PlanetTradeService.advanceAll(universe);
      expect(last[job.id]!.units, 2);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 6);
    });

    test('sell deducts at order and earns revenue on landing', () {
      final planet = _world()..storedMinerals = 100;
      expect(
        PlanetTradeService.create(
          planet: planet,
          playerId: 'p1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.sell,
          units: 10,
          ticksPerRun: 10,
          unitPrice: 5,
        ),
        isNotNull,
      );
      // Goods leave at order time (reservation).
      expect(planet.storedMinerals, 90);

      for (var i = 0; i < 9; i++) {
        expect(PlanetTradeService.advanceAll([_sectorWith(planet)]), isEmpty);
      }
      final landed = PlanetTradeService.advanceAll([_sectorWith(planet)]);
      expect(landed.values.single.units, 10);
      expect(planet.accumulatedRevenue, 50);
      expect(planet.tradeJobs, isEmpty);
    });

    test('sell refuses when the store cannot fill the order', () {
      final planet = _world()..storedMinerals = 5;
      expect(
        PlanetTradeService.create(
          planet: planet,
          playerId: 'p1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.sell,
          units: 10,
          ticksPerRun: 2,
        ),
        isNull,
      );
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 5);
    });

    test('cancel removes and returns unsold goods to the store', () {
      final planet = _world()..storedMinerals = 100;
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        units: 10,
        ticksPerRun: 10,
      )!;
      expect(planet.storedMinerals, 90);
      expect(PlanetTradeService.cancel(planet, job.id), isTrue);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 100);
      expect(PlanetTradeService.cancel(planet, job.id), isFalse);
    });

    test('hold-size runs: distance sets cadence, not shipment size', () {
      // The playtest order: 3,700 units against a 3-hop port (6 ticks/run).
      // Coupled pacing delivered 6/run over 617 runs and 31 hours; hold
      // pacing delivers one 3,700-unit run in 6 ticks.
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 3700,
        ticksPerRun: 6,
        unitsPerRun: PlanetTradeService.freighterHold,
      )!;
      expect(job.runsTotal, 1);
      final universe = [_sectorWith(planet)];
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      expect(PlanetTradeService.advanceAll(universe), isEmpty);
      final landed = PlanetTradeService.advanceAll(universe);
      expect(landed[job.id]!.units, 3700);
      expect(planet.tradeJobs, isEmpty);
      expect(planet.storedMinerals, 3700);
    });

    test('a share larger than the hold takes several full runs', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 12000,
        ticksPerRun: 8,
        unitsPerRun: PlanetTradeService.freighterHold,
      )!;
      expect(job.runsTotal, 3);
      final universe = [_sectorWith(planet)];
      var landedTotal = 0;
      for (var i = 0; i < 8; i++) {
        final landed = PlanetTradeService.advanceAll(universe);
        for (final e in landed.values) {
          landedTotal += e.units;
        }
      }
      expect(landedTotal, 5000);
      expect(planet.tradeJobs, contains(job));
    });
  });

  group('order grouping and whole-order cancel', () {
    (Planet, List<Sector>) twoPortWorld() {
      final planet = _world();
      final universe = [
        Sector(
            id: 1,
            name: 'Home',
            x: 0,
            y: 0,
            warpRoutes: const [2, 3],
            planets: [planet]),
        Sector(
            id: 2,
            name: 'Near',
            x: 100,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: Port(
              name: 'Near Port',
              portClass: PortClass.free,
              buyPrices: const {},
              sellPrices: const {'minerals': 50},
              supply: const {'minerals': 3000},
              demand: const {},
              maxSupply: const {'minerals': 80000},
              maxDemand: const {},
              portCredits: 1000000,
              desiredCredits: 1000000,
            )),
        Sector(
            id: 3,
            name: 'Far',
            x: 200,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: Port(
              name: 'Far Port',
              portClass: PortClass.free,
              buyPrices: const {},
              sellPrices: const {'minerals': 50},
              supply: const {'minerals': 4000},
              demand: const {},
              maxSupply: const {'minerals': 80000},
              maxDemand: const {},
              portCredits: 1000000,
              desiredCredits: 1000000,
            )),
      ];
      return (planet, universe);
    }

    test('one tap is one order id across every share', () {
      final (planet, universe) = twoPortWorld();
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 6000,
        actorFaction: 'trader',
      );
      // 3,000 near + 3,000 far: two shares, one order, hold-size runs.
      expect(result.jobs, hasLength(2));
      expect(result.jobs[0].orderId, isNotEmpty);
      expect(result.jobs[1].orderId, result.jobs[0].orderId);
      expect(result.jobs[0].unitsPerRun, PlanetTradeService.freighterHold);
      expect(result.placedUnits, 6000);
      expect(result.shortfall, 0);
      expect(result.portSectorIds.toSet(), {2, 3});
      // Both shelves shrank: the reservation is real on both ports.
      expect(universe[1].port!.getSupply('minerals'), 0);
      expect(universe[2].port!.getSupply('minerals'), 1000);
    });

    test('cancelOrder unwinds every share and refunds the remainder', () {
      final (planet, universe) = twoPortWorld();
      // Restock above the hold so the first run lands only part of a share.
      universe[1].port = universe[1].port!.copyWith(
        supply: const {'minerals': 12000},
        maxSupply: const {'minerals': 80000},
      );
      universe[2].port = universe[2].port!.copyWith(
        supply: const {'minerals': 12000},
        maxSupply: const {'minerals': 80000},
      );
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 20000,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(2));
      // One run lands on each share (both 1 hop: 2 ticks, 5,000-unit runs).
      PlanetTradeService.advanceAll(universe);
      PlanetTradeService.advanceAll(universe);
      var landedRemainder = 0;
      for (final j in result.jobs) {
        expect(j.unitsRemaining, lessThan(j.unitsTotal));
        landedRemainder += j.unitsRemaining;
      }

      final beforeNear = universe[1].port!.getSupply('minerals');
      final cancel =
          PlanetTradeService.cancelOrder(planet, universe, result.orderId);
      expect(planet.tradeJobs, isEmpty);
      // Shelves grow back by exactly the unlanded remainder — delivered runs
      // stay delivered.
      expect(universe[1].port!.getSupply('minerals'),
          beforeNear + result.jobs[0].unitsRemaining);
      expect(landedRemainder, greaterThan(0));
      // Refund covers the unlanded remainder only.
      var expected = 0;
      for (final j in result.jobs) {
        expected += j.unitsRemaining * j.unitPrice;
      }
      expect(cancel.refund, expected);
      expect(cancel.portSectorIds.toSet(), {2, 3});
    });

    test('pre-grouping jobs carry no order id and group alone', () {
      final planet = _world();
      final job = PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 6,
        ticksPerRun: 2,
      )!;
      expect(job.orderId, isEmpty);
      expect(
          PlanetTradeService.cancelOrder(planet, [_sectorWith(planet)], job.id)
              .refund,
          6 * job.unitPrice);
      expect(planet.tradeJobs, isEmpty);
    });
  });

  group('model floors', () {
    test('an explicit zero cadence clamps instead of quickening', () {
      final job = TradeJob.fromJson({
        'playerId': 'p1',
        'planetId': 'w1',
        'portSectorId': 2,
        'commodity': 'minerals',
        'direction': 'buy',
        'unitsTotal': 100,
        'ticksPerRun': 0,
        'unitsRemaining': 100,
        'ticksRemaining': 0,
      });
      // A hand-edited `"ticksPerRun": 0` used to deliver a full hold every
      // tick — distance cadence deleted by hand. Now the cadence is 1 and
      // the corrupt zero-countdown fires exactly once, for one unit, before
      // the standard rhythm takes over.
      expect(job.ticksPerRun, 1);
      expect(job.advance(), 1);
      expect(job.unitsRemaining, 99);
      expect(job.advance(), 1);
      expect(job.unitsRemaining, 98);
    });

    test('a zero or negative hold clamps instead of stalling or growing', () {
      for (final hold in [0, -50]) {
        final job = TradeJob(
          playerId: 'p1',
          planetId: 'w1',
          portSectorId: 2,
          commodity: 'minerals',
          direction: TradeDirection.buy,
          unitsTotal: 10,
          ticksPerRun: 2,
          unitsPerRun: hold,
        );
        expect(job.unitsPerRun, 1);
        // One full cadence lands exactly one unit: no stall, and the
        // remainder never climbs.
        expect(job.advance(), 0);
        expect(job.advance(), 1);
        expect(job.unitsRemaining, 9);
      }
    });

    test('escrow round-trips through JSON', () {
      final job = TradeJob(
        playerId: 'p1',
        planetId: 'w1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        unitsTotal: 100,
        ticksPerRun: 2,
        unitPrice: 50,
        escrowed: 100,
      );
      expect(TradeJob.fromJson(job.toJson()).escrowed, 100);
    });
  });

  group('escrow conservation', () {
    (Planet, List<Sector>) poorPortWorld() {
      final planet = _world()..storedMinerals = 100000;
      Port port({required int credits, required int demand}) => Port(
            name: 'Poor Port',
            portClass: PortClass.free,
            buyPrices: const {'minerals': 50},
            sellPrices: const {},
            supply: const {},
            demand: {'minerals': demand},
            maxSupply: const {},
            maxDemand: const {'minerals': 60000},
            portCredits: credits.toDouble(),
            desiredCredits: 1000000,
          );
      final universe = [
        Sector(
            id: 1,
            name: 'Home',
            x: 0,
            y: 0,
            warpRoutes: const [2, 3],
            planets: [planet]),
        Sector(
            id: 2,
            name: 'Poor',
            x: 100,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: port(credits: 100, demand: 10000)),
        Sector(
            id: 3,
            name: 'Rich',
            x: 200,
            y: 0,
            warpRoutes: const [1],
            hasPort: true,
            port: port(credits: 1000000, demand: 10000)),
      ];
      return (planet, universe);
    }

    test('reserve-then-cancel on a cash-poor port mints nothing', () {
      final (planet, universe) = poorPortWorld();
      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.sell,
        volume: 1000,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(1));
      // Worth 50,000 against a 100-credit pool: only 100 was ever taken.
      expect(result.jobs.single.escrowed, 100);
      expect(universe[1].port!.portCredits, 0);

      PlanetTradeService.cancelOrder(planet, universe, result.orderId);
      // Exactly what was taken comes back — the old code returned the full
      // 50,000 here, a repeatable 49,900-credit mint per cycle.
      expect(universe[1].port!.portCredits, 100);
      expect(planet.tradeJobs, isEmpty);
    });

    test('overlapping reservations balance to the credit', () {
      final (planet, universe) = poorPortWorld();
      // A buy that pays the poor port first: pool 100 + 500.
      universe[1].port = universe[1].port!.copyWith(
        buyPrices: const {'minerals': 60},
        sellPrices: const {'minerals': 50},
        supply: const {'minerals': 5000},
        maxSupply: const {'minerals': 80000},
      );
      final buyShare = TradeAllocation(
          portSectorId: 2, units: 500, hops: 1, ticksPerRun: 2, unitPrice: 1);
      final buyValue = PlanetTradeService.reserveShare(
        universe: universe,
        share: buyShare,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        actorFaction: 'trader',
      );
      expect(buyValue, isNotNull);
      expect(universe[1].port!.portCredits, 600);
      // A sell that escrows the whole pool: 600 of a larger nominal.
      final sellShare = TradeAllocation(
          portSectorId: 2, units: 600, hops: 1, ticksPerRun: 2, unitPrice: 10);
      final sellRes = PlanetTradeService.reserveShare(
        universe: universe,
        share: sellShare,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        actorFaction: 'trader',
      );
      expect(sellRes!.escrowed, 600);
      expect(universe[1].port!.portCredits, 0);
      // Unwind both in reverse: the buy release subtracts its exact 500 even
      // though the pool sits at 0 — the sell reservation is holding it.
      PlanetTradeService.releaseReservation(
        universe: universe,
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 500,
        unitPrice: 1,
        escrowed: 500,
      );
      expect(universe[1].port!.portCredits, -500);
      PlanetTradeService.releaseReservation(
        universe: universe,
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        units: 600,
        unitPrice: 10,
        escrowed: 600,
      );
      // To the credit: every movement reversed exactly.
      expect(universe[1].port!.portCredits, 100);
    });
  });

  group('T2 tick persistence', () {
    test('multi-run countdown survives save-reload-advance', () async {
      final planet = _world();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        units: 4,
        ticksPerRun: 2,
      );
      final store = FaithfulUniverse([_sectorWith(planet)]);

      // Mutate (one tick of countdown), save, reload into a fresh graph.
      var loaded = await store.loadUniverse();
      PlanetTradeService.advanceAll(loaded);
      await store.saveUniverse(loaded);

      var reloaded = await store.loadUniverse();
      // Must be a different object graph (the productionRemainder lesson).
      expect(identical(loaded, reloaded), isFalse);
      final job = reloaded.first.planets.first.tradeJobs.single;
      expect(job.unitsRemaining, 4);
      expect(job.ticksRemaining, 1);

      // Advance to the first landing after the reload: proves the countdown
      // was carried, not reset to full.
      final landed = PlanetTradeService.advanceAll(reloaded);
      expect(landed.values.single.units, 2);
      expect(reloaded.first.planets.first.storedMinerals, 2);
      // And the job is still in flight, not completed early.
      expect(reloaded.first.planets.first.tradeJobs, hasLength(1));
    });

    test('trade jobs round-trip through Planet JSON', () {
      final planet = _world();
      PlanetTradeService.create(
        planet: planet,
        playerId: 'p1',
        portSectorId: 2,
        commodity: 'organics',
        direction: TradeDirection.buy,
        units: 8,
        ticksPerRun: 4,
        unitPrice: 7,
      );
      PlanetTradeService.advanceAll([_sectorWith(planet)]);

      final revived = Planet.fromJson(planet.toJson());
      final job = revived.tradeJobs.single;
      expect(job.planetId, planet.id);
      expect(job.commodity, 'organics');
      expect(job.unitPrice, 7);
      expect(job.unitsRemaining, 8);
      // One tick of countdown was consumed before the save.
      expect(job.ticksRemaining, 3);
    });

    test('tick saves unconditionally so a countdown cannot reset', () async {
      // Structural: the save must not be gated on a hand-maintained list of
      // counters (the colonist-transit lesson — a countdown nobody logs
      // resets to full every tick and the shipment never lands).
      final content = await UniverseStorageSavesUnconditionally.readTickBody();
      expect(content, contains('saveUniverse(sectors)'));
      expect(content, isNot(contains('if (portsRegened')));
    });
  });
}

/// Reads this repo's tick body to assert the save is ungated.
///
/// A source scan is the documented exception for exactly this question: a full
/// tick fixture is a large thing for "is there a call site", and only a scan
/// asks it (see gravity_wiring_test.dart for the precedent).
class UniverseStorageSavesUnconditionally {
  static Future<String> readTickBody() async {
    // Cheap and honest: the guard is about the tick file's own structure.
    final file = await _read('lib/services/game_tick_service.dart');
    final start = file.indexOf('Save the universe. **Unconditionally');
    return file.substring(start < 0 ? 0 : start);
  }

  static Future<String> _read(String path) async {
    // Tests run with the package root as cwd.
    final f = _File(path);
    return f.readAsString();
  }
}

// Minimal file reader without importing dart:io into the test zone twice.
class _File {
  _File(this.path);
  final String path;
  Future<String> readAsString() => io.File(path).readAsString();
}
