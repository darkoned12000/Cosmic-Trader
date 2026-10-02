import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';

Port _sellingPort({required int supply}) {
  return Port(
    name: 'Emporium',
    portClass: PortClass.free,
    buyPrices: const {},
    sellPrices: const {'minerals': 50},
    supply: {'minerals': supply},
    demand: const {},
    maxSupply: {'minerals': supply},
    maxDemand: const {},
    portCredits: 1000000,
    desiredCredits: 1000000,
  );
}

Port _buyingPort({required int demand}) {
  return Port(
    name: 'Buyer',
    portClass: PortClass.free,
    buyPrices: const {'minerals': 60},
    sellPrices: const {},
    supply: const {},
    demand: {'minerals': demand},
    maxSupply: const {},
    maxDemand: {'minerals': demand},
    portCredits: 1000000,
    desiredCredits: 1000000,
  );
}

Sector _sector({
  required int id,
  required List<int> warps,
  Port? port,
  List<Planet> planets = const [],
}) {
  return Sector(
    id: id,
    name: 'S$id',
    x: id.toDouble(),
    y: 0,
    warpRoutes: warps,
    hasPort: port != null,
    port: port,
    planets: List<Planet>.from(planets),
  );
}

void main() {
  group('T3 port selection', () {
    test('100k buy against 60k combined splits and reports shortfall', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran');
      final universe = [
        _sector(id: 1, warps: const [2], planets: [planet]),
        // 1 hop, 50k on the shelf.
        _sector(id: 2, warps: const [1, 3], port: _sellingPort(supply: 50000)),
        // 2 hops, 10k on the shelf.
        _sector(id: 3, warps: const [2], port: _sellingPort(supply: 10000)),
        // Holds minerals but does not sell them: stock alone must not qualify.
        _sector(
            id: 4,
            warps: const [1],
            port: const Port(
              name: 'Other',
              portClass: PortClass.free,
              buyPrices: {'food': 10},
              sellPrices: {'food': 20},
              supply: {'food': 99999, 'minerals': 99999},
              demand: {'food': 99999},
              maxSupply: {'food': 99999, 'minerals': 99999},
              maxDemand: {'food': 99999},
            )),
      ];

      final planResult = PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 100000,
      );

      expect(planResult.unitsAllocated, 60000);
      expect(planResult.shortfall, 40000);
      expect(planResult.allocations.fold(0, (sum, a) => sum + a.units), 60000);
      // Nearest first: the 1-hop 50k before the 2-hop 10k.
      expect(planResult.allocations.map((a) => a.portSectorId), [2, 3]);
      expect(planResult.allocations.map((a) => a.units), [50000, 10000]);
      // No share from the food-only port.
      expect(planResult.allocations.any((a) => a.portSectorId == 4), isFalse);
    });

    test('cadence is hops-scaled: 1 hop = 2 ticks, 2 hops = 4', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran');
      final universe = [
        _sector(id: 1, warps: const [2], planets: [planet]),
        _sector(id: 2, warps: const [1, 3], port: _sellingPort(supply: 50000)),
        _sector(id: 3, warps: const [2], port: _sellingPort(supply: 50000)),
      ];
      final planResult = PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 60000,
      );
      expect(planResult.allocations[0].hops, 1);
      expect(planResult.allocations[0].ticksPerRun,
          PlanetTradeService.ticksPerHop);
      expect(planResult.allocations[1].hops, 2);
      expect(planResult.allocations[1].ticksPerRun,
          2 * PlanetTradeService.ticksPerHop);
    });

    test('sell selects on demand and skips ports that do not buy', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran')
        ..storedMinerals = 100000;
      final universe = [
        _sector(id: 1, warps: const [2, 3], planets: [planet]),
        _sector(id: 2, warps: const [1], port: _buyingPort(demand: 25000)),
        // Sells minerals but buys nothing: invisible to a sell order.
        _sector(id: 3, warps: const [1], port: _sellingPort(supply: 99999)),
      ];
      final planResult = PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: TradeDirection.sell,
        volume: 100000,
      );
      expect(planResult.unitsAllocated, 25000);
      expect(planResult.shortfall, 75000);
      expect(planResult.allocations.single.portSectorId, 2);
    });

    test('unreachable, destroyed, and empty ports are excluded', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran');
      final universe = [
        _sector(id: 1, warps: const [2], planets: [planet]),
        _sector(id: 2, warps: const [1], port: _sellingPort(supply: 1000)),
        // No route here.
        _sector(id: 9, warps: const [], port: _sellingPort(supply: 99999)),
        // Empty shelf.
        _sector(id: 3, warps: const [1], port: _sellingPort(supply: 0)),
      ];
      // Destroyed port on a reachable sector.
      universe.add(_sector(
        id: 4,
        warps: const [1],
        port: Port(
          name: 'Dead',
          portClass: PortClass.free,
          buyPrices: const {},
          sellPrices: const {'minerals': 50},
          supply: const {'minerals': 99999},
          demand: const {},
          maxSupply: const {'minerals': 99999},
          maxDemand: const {},
          isDestroyed: true,
        ),
      ));

      final planResult = PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 5000,
      );
      expect(planResult.unitsAllocated, 1000);
      expect(planResult.allocations.single.portSectorId, 2);
    });

    test('plan is pure: no jobs, no stock moved', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran');
      final port = _sellingPort(supply: 50000);
      final universe = [
        _sector(id: 1, warps: const [2], planets: [planet]),
        _sector(id: 2, warps: const [1], port: port),
      ];
      PlanetTradeService.plan(
        universe: universe,
        planet: planet,
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 10000,
      );
      expect(planet.tradeJobs, isEmpty);
      expect(universe[1].port!.getSupply('minerals'), 50000);
    });

    test('createOrder places one job per share at live prices', () {
      final planet = Planet(id: 'w1', name: 'X', planetType: 'Terran');
      final universe = [
        _sector(id: 1, warps: const [2], planets: [planet]),
        _sector(id: 2, warps: const [1, 3], port: _sellingPort(supply: 50000)),
        _sector(id: 3, warps: const [2], port: _sellingPort(supply: 10000)),
      ];
      final before =
          universe[1].port!.getEffectiveSellPrice('minerals').round();

      final result = PlanetTradeService.createOrder(
        planet: planet,
        universe: universe,
        playerId: 'p1',
        commodity: 'minerals',
        direction: TradeDirection.buy,
        volume: 100000,
        actorFaction: 'trader',
      );
      expect(result.jobs, hasLength(2));
      expect(result.shortfall, 40000);
      expect(planet.tradeJobs, hasLength(2));
      expect(result.jobs[0].portSectorId, 2);
      expect(result.jobs[0].unitPrice, before);
      expect(result.jobs[0].ticksPerRun, PlanetTradeService.ticksPerHop);
      // One request, one order id, hold-size runs on every share.
      expect(result.jobs[1].orderId, result.jobs[0].orderId);
      expect(result.jobs[0].unitsPerRun, PlanetTradeService.freighterHold);
      // And the shelves moved: an order reserves, it does not just quote.
      expect(universe[1].port!.getSupply('minerals'), 0);
      expect(universe[2].port!.getSupply('minerals'), 0);
    });
  });
}
