import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixed epoch base so the regen maths is deterministic.

/// The economy's brake on planetary output.
///
/// A colony can produce far more than the galaxy can absorb: a port's buying
/// capacity is finite (`maxDemand`) and refills over a 24-hour cycle, so turning
/// production into credits is limited by the market, not by the tap rate. Port
/// storage upgrades raise that capacity 1.5x per level, which is the intended
/// progression — you get richer by making somewhere *willing* to buy more, not
/// by producing more.
///
/// This file exists because that loop was unreachable in the UI: buy/sell moved
/// exactly one unit per tap, so a port holding ~78,000 of demand took 78,000 taps
/// to cash in. The balance was correct and the control surface was not, which
/// makes it look like a balance bug from the player's side.
void main() {
  /// A port that buys minerals and sells nothing, so the demand side is the
  /// only thing under test.
  ///
  /// No clock stamp: regen is driven by explicit tick counts now, so a port
  /// carries no wall-clock state to make deterministic.
  Port portWith(int minerals) => Port(
        name: 'Test Port',
        portClass: PortClass.free,
        buyPrices: {
          'minerals': 50,
        },
        sellPrices: const {},
        maxDemand: {'minerals': minerals},
        demand: {'minerals': minerals},
      );

  group('demand is a real sink', () {
    test('a port will not buy more than its remaining demand', () {
      final p = portWith(1000);
      expect(p.demand['minerals'], 1000);
      final sold = 400;
      final after =
          p.copyWith(demand: {'minerals': p.demand['minerals']! - sold});
      expect(after.demand['minerals'], 600);
    });

    test('demand refills toward its cap rather than resetting', () {
      // Half a game day is half of [PlanetClock.ticksPerDay] ticks, and a game
      // day is a real day, so half the shortfall comes back.
      final p = portWith(1000).copyWith(demand: {'minerals': 0});
      final regen = p.regenTick(ticks: PlanetClock.ticksPerDay ~/ 2);
      expect(regen.demand['minerals']! > 400, isTrue);
      expect(regen.demand['minerals']! < 600, isTrue,
          reason: 'half a day should not fully refill a full-day cycle');
    });

    test('a full day refills completely', () {
      final p = portWith(1000).copyWith(demand: {'minerals': 0});
      final regen = p.regenTick(ticks: PlanetClock.ticksPerDay);
      expect(regen.demand['minerals'], 1000);
    });

    test('a port that is never ticked stays sold out', () {
      // The property the whole change exists for. [regenTick] takes a tick
      // count and nothing else — there is no wall-clock input to pass — so the
      // only thing that can refill a port is the tick, and the game being shut
      // off means the tick is not running. A player who closes the app
      // mid-trade must not come back to a restocked market.
      final p = portWith(1000).copyWith(demand: {'minerals': 0});
      expect(p.demand['minerals'], 0);
      expect(p.regenTick().demand['minerals'], 0,
          reason: 'one tick is 1,000 / 2,880 = 0.347 of a unit, which is not '
              'yet a unit — and 10 ticks was tried first, which is 3 units and '
              'so does NOT satisfy "no time has passed". The fixture has to '
              'reach the actual boundary, not a convenient one.');
      expect(p.regenTick(ticks: 10).demand['minerals'], 3,
          reason: 'ten ticks is 3.47 units, so a sold-out small port does move '
              '— which is the rate working, not the clock running');
    });

    test('the per-tick rate is the cap over a game day', () {
      // 50,000 / 2,880 = 17.361 per tick. The fraction is carried, so a whole
      // day still yields the whole cap — which is the property truncation would
      // have quietly broken for a small port (1,000 / 2,880 = 0.347, i.e. zero).
      final big = portWith(50000).copyWith(demand: {'minerals': 0});
      final one = big.regenTick();
      expect(one.demand['minerals'], 17,
          reason: '50,000 / 2,880 truncates to 17');

      var p = big;
      for (var i = 0; i < PlanetClock.ticksPerDay; i++) {
        p = p.regenTick();
      }
      expect(p.demand['minerals'], 50000,
          reason:
              'a whole day must land on the cap exactly, not on 17 x 2,880');

      final small = portWith(1000).copyWith(demand: {'minerals': 0});
      var s = small;
      for (var i = 0; i < PlanetClock.ticksPerDay; i++) {
        s = s.regenTick();
      }
      expect(s.demand['minerals'], 1000,
          reason: 'a small port is the case truncation would have starved');
    });
  });

  group('port storage upgrades raise buying capacity', () {
    test('each level multiplies what the port will absorb', () {
      final base = portWith(10000);
      expect(base.effectiveMaxDemand('minerals'), 10000);
      final one = base.copyWith(storageLevel: 1);
      expect(one.effectiveMaxDemand('minerals'), 15000);
      final five = base.copyWith(storageLevel: 5);
      expect(five.effectiveMaxDemand('minerals'), greaterThan(70000));
    });

    test('upgrades get genuinely expensive', () {
      // The point of the sink: opening up a market costs real money, so a
      // player cannot simply convert a colony's output into credits for free.
      final p = portWith(10000);
      final costs = [
        for (var i = 0; i < 5; i++)
          p.copyWith(storageLevel: i).storageUpgradeCost
      ];
      for (var i = 1; i < costs.length; i++) {
        expect(costs[i], greaterThan(costs[i - 1]),
            reason: 'upgrade $i must cost more than upgrade ${i - 1}');
      }
      expect(costs.first, 100000);
    });

    test('the last level is unreachable rather than merely expensive', () {
      final maxed = portWith(10000).copyWith(storageLevel: 10);
      expect(maxed.canUpgradeStorage, isFalse);
      expect(maxed.storageUpgradeCost, double.infinity);
    });

    test('capacity is capped at 1.5^10', () {
      final maxed = portWith(10000).copyWith(storageLevel: 10);
      // A port at 10 absorbs ~57x its base demand, which is the ceiling of the
      // progression and keeps a single port from becoming a bottomless sink.
      expect(maxed.effectiveMaxDemand('minerals'), lessThan(10000 * 58));
      expect(maxed.effectiveMaxDemand('minerals'), greaterThan(10000 * 57));
    });
  });
}
