import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

Port _port() => const Port(
      name: 'P',
      portClass: PortClass.free,
      buyPrices: {'minerals': 50.0},
      sellPrices: {'minerals': 30.0},
      supply: {'minerals': 50},
      demand: {'minerals': 50},
      maxSupply: {'minerals': 100},
      maxDemand: {'minerals': 100},
      portCredits: 1000,
      desiredCredits: 1000,
    );

void main() {
  test('standing multipliers scale both sides, clamped', () {
    expect(Port.standingBuyMultiplier(100), 0.8);
    expect(Port.standingBuyMultiplier(-100), 1.2);
    expect(Port.standingBuyMultiplier(0), 1.0);
    expect(Port.standingSellMultiplier(100), 1.2);
    expect(Port.standingSellMultiplier(-100), 0.8);
  });

  test('effective prices apply standing; zero is neutral', () {
    final port = _port();
    expect(port.getEffectiveSellPriceFor('minerals'),
        port.getEffectiveSellPrice('minerals'));
    // demand/supply half → depth 1.0; base sell 30 × loved (0.8).
    expect(port.getEffectiveSellPriceFor('minerals', standing: 100),
        closeTo(24.0, 1e-9));
    // base buy 50 × hated sell mult (0.8).
    expect(port.getEffectiveBuyPriceFor('minerals', standing: -100),
        closeTo(40.0, 1e-9));
  });

  test('resolveFor prefers persisted over lore defaults', () {
    // Duran default toward traders is -10.
    expect(
      FactionStanding.resolveFor(FactionClass.duran, FactionClass.trader, {}),
      -10,
    );
    expect(
      FactionStanding.resolveFor(
          FactionClass.duran, FactionClass.trader, {'trader': 60}),
      60,
    );
    expect(FactionStanding.resolveFor(FactionClass.duran, null, {}), 0);
  });

  test('evaluator prices standing into route selection', () {
    // Seller loves duran (+100 → pays 20% over), buyer hates them.
    final knownPorts = {
      1: const PortInfo(
        name: 'P1',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {'minerals': 10.0},
      ),
      2: const PortInfo(
        name: 'P2',
        portClass: PortClass.free,
        buyPrices: {'minerals': 200.0},
        sellPrices: {},
      ),
    };
    final sectors = [
      Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
      Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1]),
    ];
    final plain = TradeEvaluator.findBestTradeRoute(1, knownPorts, sectors, 30);
    final loved = TradeEvaluator.findBestTradeRoute(
      1,
      {
        1: const PortInfo(
          name: 'P1',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 10.0},
          ownerFaction: FactionClass.trader,
        ),
        2: const PortInfo(
          name: 'P2',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
          ownerFaction: FactionClass.trader,
        ),
      },
      sectors,
      30,
      actorFaction: FactionClass.trader,
      standings: const {'trader': 100},
    );
    expect(plain, isNotNull);
    expect(loved, isNotNull);
    // Loved on both ends: cheaper buy AND richer sell.
    expect(loved!.buyPrice, lessThan(plain!.buyPrice));
    expect(loved.sellPrice, greaterThan(plain.sellPrice));
  });

  test('ownerFaction survives a PortInfo round-trip', () {
    const info = PortInfo(
      name: 'P',
      portClass: PortClass.free,
      buyPrices: {},
      sellPrices: {},
      ownerFaction: FactionClass.pirate,
    );
    final restored = PortInfo.fromJson(
      Map<String, dynamic>.from(info.toJson()),
    );
    expect(restored.ownerFaction, FactionClass.pirate);
  });
}
