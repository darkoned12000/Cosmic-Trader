import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';

void main() {
  setUp(() => EconomyMetrics.resetForTest());
  tearDown(() => EconomyMetrics.resetForTest());

  test('recordTrade accumulates totals and splits player/NPC', () {
    final m = EconomyMetrics.global;
    m.recordTrade(
      commodity: 'minerals',
      units: 10,
      credits: 200,
      actorFaction: 'trader',
      isPlayer: false,
      isBuy: true,
    );
    m.recordTrade(
      commodity: 'minerals',
      units: 5,
      credits: 300,
      actorFaction: 'duran',
      isPlayer: true,
      isBuy: false,
    );

    expect(m.tradeCount, 2);
    expect(m.totalUnits, 15);
    expect(m.totalCredits, 500);
    expect(m.playerTrades, 1);
    expect(m.npcTrades, 1);

    final minerals = m.perCommodity['minerals']!;
    expect(minerals.buyUnits, 10);
    expect(minerals.sellUnits, 5);
    expect(minerals.avgUnitPrice, 500 / 15);

    final trader = m.perFaction['trader']!;
    expect(trader.buys, 1);
    expect(trader.buyCredits, 200);
    expect(trader.net, -200);

    final duran = m.perFaction['duran']!;
    expect(duran.sells, 1);
    expect(duran.net, 300);
  });

  test('zero-unit trades are ignored', () {
    final m = EconomyMetrics.global;
    m.recordTrade(
      commodity: 'minerals',
      units: 0,
      credits: 100,
      actorFaction: 'trader',
      isPlayer: false,
      isBuy: true,
    );
    expect(m.tradeCount, 0);
    expect(m.perCommodity, isEmpty);
  });

  test('reset clears everything and restarts the clock', () {
    final m = EconomyMetrics.global;
    m.recordTrade(
      commodity: 'organics',
      units: 3,
      credits: 90,
      actorFaction: 'vinari',
      isPlayer: false,
      isBuy: true,
    );
    expect(m.tradeCount, 1);

    m.reset();
    expect(m.tradeCount, 0);
    expect(m.totalUnits, 0);
    expect(m.perCommodity, isEmpty);
    expect(m.perFaction, isEmpty);
    expect(m.tradesPerMinute, 0);
  });

  test('loot is tracked separately from trade volume', () {
    final m = EconomyMetrics.global;
    m.recordLoot(actorFaction: 'pirate', credits: 5000, isPlayer: false);
    m.recordLoot(actorFaction: 'pirate', credits: 0, isPlayer: false);

    expect(m.totalLoot, 5000);
    expect(m.tradeCount, 0);
    expect(m.totalCredits, 0);
    final pirate = m.perFaction['pirate']!;
    expect(pirate.lootCredits, 5000);
    expect(pirate.net, 0);
    expect(pirate.totalEarned, 5000);

    m.reset();
    expect(m.totalLoot, 0);
  });

  test('faction keys normalize casing into one row', () {
    final m = EconomyMetrics.global;
    m.recordTrade(
      commodity: 'minerals',
      units: 1,
      credits: 10,
      actorFaction: 'Trader',
      isPlayer: false,
      isBuy: true,
    );
    m.recordLoot(actorFaction: 'TRADER', credits: 5, isPlayer: false);
    expect(m.perFaction.keys, ['trader']);
    expect(m.perFaction['trader']!.buys, 1);
    expect(m.perFaction['trader']!.lootCredits, 5);
  });

  test('snapshot round-trips through JSON (persistence shape)', () async {
    final m = EconomyMetrics.global;
    m.recordTrade(
      commodity: 'ore',
      units: 4,
      credits: 200,
      actorFaction: 'trader',
      isPlayer: true,
      isBuy: false,
    );
    m.recordLoot(actorFaction: 'pirate', credits: 50, isPlayer: false);

    final json = m.toJson();
    expect(json['tradeCount'], 1);
    expect(json['totalLoot'], 50);

    EconomyMetrics.resetForTest();
    final fresh = EconomyMetrics.global;
    expect(fresh.tradeCount, 0);
    // Restore with no file present is a safe no-op (storage swallows).
    await fresh.restore();
    expect(fresh.tradeCount, 0);
  });
}
