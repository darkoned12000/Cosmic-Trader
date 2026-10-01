import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/banking_ai.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';
import 'package:cosmic_trader/widgets/banking_widget.dart';

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

  test('service refusal trips at -50 standing', () {
    const port = Port(
      name: 'P',
      portClass: PortClass.free,
      buyPrices: {},
      sellPrices: {},
      ownerFaction: FactionClass.trader,
    );
    expect(port.deniesServiceTo(-50), isTrue);
    expect(port.deniesServiceTo(-100), isTrue);
    expect(port.deniesServiceTo(-49), isFalse);
    expect(port.deniesServiceTo(30), isFalse);
  });

  test('bank rate follows Trade Guild standing', () {
    // BankingWidget.effectiveRateFor is widget-static; replicate via
    // factionStandingWith on players with known standings.
    Player playerWith(int traderStanding) {
      // Start from trader-faction defaults (trader→trader = 30) then shift.
      final base = Player(
        name: 'T',
        currentSectorId: 1,
        hull: 1,
        maxHull: 1,
        shields: 1,
        maxShields: 1,
        cargoUsed: 0,
        maxCargo: 1,
        cargoSize: 1,
        credits: 0,
        researchPoints: 0,
      );
      final delta =
          traderStanding - base.factionStandingWith(FactionClass.trader);
      return base.withFactionStandingChange(FactionClass.trader, delta);
    }

    // Base rate 1% scaled ±0.2%/100 standing, clamped [0.5%, 1.5%].
    expect(
      BankingWidget.rateFor(playerWith(100)),
      closeTo(0.012, 1e-9),
    );
    expect(
      BankingWidget.rateFor(playerWith(-100)),
      closeTo(0.008, 1e-9),
    );
    expect(
      BankingWidget.rateFor(playerWith(30)),
      closeTo(0.0106, 1e-9),
    );
  });

  test('NPC skips hostile emporiums and is refused on arrival', () {
    Sector emporium(int id, List<int> warps, FactionClass owner) => Sector(
          id: id,
          name: 'E$id',
          x: 0,
          y: 0,
          warpRoutes: warps,
          hasPort: true,
          port: Port(
            name: 'Emporium',
            portClass: PortClass.hardwareEmporium,
            buyPrices: const {},
            sellPrices: const {},
            ownerFaction: owner,
          ),
        );
    // Pirate (trader standing -60 → refused) with only a trader-owned
    // emporium discovered.
    final sectors = [
      emporium(1, [2], FactionClass.trader),
      emporium(2, [1], FactionClass.trader)
    ];
    var memory = const NpcMemory();
    memory = memory.withDiscoveredPort(
      2,
      const PortInfo(
        name: 'Emporium',
        portClass: PortClass.hardwareEmporium,
        buyPrices: {},
        sellPrices: {},
        ownerFaction: FactionClass.trader,
      ),
    );
    var npc = NpcShip.create(
      faction: FactionClass.pirate,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 5000,
      seed: 81,
    ).copyWith(
      personality: NpcPersonality.pirateHunter,
      memory: memory,
      energy: 50,
    );

    // No servable emporium → no refuel goal (roams instead).
    expect(NpcAiService.createRefuelGoal(npc, sectors), isNull);

    // Forced arrival at the hostile pump fails cleanly: no fuel bought,
    // goal replanned next tick (failed → explore), energy spent moving on.
    npc = npc.copyWith(
      energy: 900,
      currentGoal: NpcGoal(
        type: NpcGoalType.refuelEnergy,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {'targetSectorId': 2},
      ),
      currentSectorId: 2,
    );
    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(after.credits, 5000);
    // Refused: replanned to explore in the same tick (failed goal never
    // lingers to steer movement anymore).
    expect(after.currentGoal?.type, NpcGoalType.explore);
    final recovered = NpcAiService.processTurn(after, sectors, [], [after]);
    // …and the NPC roams instead of looping the hostile pump.
    expect(recovered.currentGoal?.type, isNot(NpcGoalType.refuelEnergy));
  });

  test(
      'interest accrues per game day, and the clock starts with no retro payout',
      () {
    // Ticks throughout. A game day is `GameClock.ticksPerDay` (2,880) — a real
    // day at the default 30-second tick, and **nothing at all** while the game is
    // closed. That last half is the whole point: a wall-clock period here meant a
    // player who closed the game for a week came back to seven days of interest
    // for a week they never played.
    final t0 = 1000;

    // First balance: the clock starts, nothing is paid retroactively.
    final first = BankingAi.accrueInterest(
      bankBalance: 100000,
      lastInterestTick: null,
      rate: 0.011,
      nowTick: t0,
    );
    expect(first, isNotNull);
    expect(first!.interest, 0);
    expect(first.stamp, t0,
        reason: 'a null stamp is initialised to now, never to zero \u2014 '
            'stamping zero would credit a year of interest on first load');

    // One tick short of a day: nothing.
    expect(
      BankingAi.accrueInterest(
        bankBalance: 100000,
        lastInterestTick: t0,
        rate: 0.011,
        nowTick: t0 + GameClock.ticksPerDay - 1,
      ),
      isNull,
    );

    // Exactly one day at 1.1%: 100,000 * 0.011 = 1,100 cr.
    //
    // The user's own worked example, which is the reason the rate is quotable:
    // 1,100 cr over 2,880 ticks is **0.38194 cr per tick**.
    final oneDay = BankingAi.accrueInterest(
      bankBalance: 100000,
      lastInterestTick: t0,
      rate: 0.011,
      nowTick: t0 + GameClock.ticksPerDay,
    );
    expect(oneDay!.interest, 1100);
    expect(1100 / GameClock.ticksPerDay, closeTo(0.38194, 0.00001));

    // Two days at 1%: 2000.
    final paid = BankingAi.accrueInterest(
      bankBalance: 100000,
      lastInterestTick: t0,
      rate: 0.01,
      nowTick: t0 + GameClock.ticksPerDay * 2,
    );
    expect(paid!.interest, 2000);

    // Broke: nothing, ever.
    expect(
      BankingAi.accrueInterest(
        bankBalance: 0,
        lastInterestTick: t0 - GameClock.ticksPerDay * 30,
        rate: 0.01,
        nowTick: t0,
      ),
      isNull,
    );
  });

  test('a partial day carries forward instead of being discarded', () {
    // The old rule stamped "now" after paying, which threw the remainder away.
    // An NPC paid on **every tick** therefore collected 2,880 partial payouts
    // instead of one, and each discarded remainder was a rounding loss in the
    // player's favour; a player visiting every twelve hours was paid
    // `floor(half) x 2` rather than `floor(whole)` \u2014 quietly under the
    // advertised rate, and worse the *more* often they checked in.
    final t0 = 5000;

    // Half a day, nothing due.
    expect(
      BankingAi.accrueInterest(
        bankBalance: 100000,
        lastInterestTick: t0,
        rate: 0.01,
        nowTick: t0 + GameClock.ticksPerDay ~/ 2,
      ),
      isNull,
    );

    // A day and a half: one day's interest, and the stamp advances by exactly
    // one day \u2014 so the other half is still owed in six hours' time.
    final aDayAndAHalf = BankingAi.accrueInterest(
      bankBalance: 100000,
      lastInterestTick: t0,
      rate: 0.01,
      nowTick: t0 + GameClock.ticksPerDay + GameClock.ticksPerDay ~/ 2,
    );
    // **One** day's interest, not one and a half's: the half day is not consumed,
    // so it must not be paid for. Paying `days` (1.5) while advancing the stamp
    // by `wholeDays` (1) was my first version and it leaked — the next payout
    // charged a full day for the same half day, so two days paid 2,500 instead of
    // 2,000.
    expect(aDayAndAHalf!.interest, 1000);
    expect(aDayAndAHalf.stamp, t0 + GameClock.ticksPerDay,
        reason: 'the stamp must advance by whole days only, or the remainder '
            'is paid for twice');

    // Completing that second day pays exactly one more day.
    final secondDay = BankingAi.accrueInterest(
      bankBalance: 100000,
      lastInterestTick: aDayAndAHalf.stamp,
      rate: 0.01,
      nowTick: t0 + GameClock.ticksPerDay * 2,
    );
    expect(secondDay!.interest, 1000);
    expect(secondDay.stamp, t0 + GameClock.ticksPerDay * 2);
    // Two elapsed days have now paid for two days and no more — the property the
    // two-halves-must-agree rule exists to hold.
    expect(aDayAndAHalf.interest + secondDay.interest, 2000,
        reason: '2,500 here would mean the fractional day was paid twice');
  });
}
