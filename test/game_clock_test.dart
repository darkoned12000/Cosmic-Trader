import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/services/game_clock.dart';

/// The clock every game duration is counted in.
///
/// Two properties matter more than the arithmetic, and both were defects first:
///
///  * **Time stops when the game is closed.** Nothing accrues against a period
///    that passed in real time while the app was shut.
///  * **A deadline outlives the session that set it.** A counter that reset on
///    launch would not merely mis-measure a period \u2014 it would make every stored
///    "expires at tick N" meaningless, because N came from the previous run.
/// One factory for all three settings fixtures.
///
/// Written once because three hand-written copies of a required-argument list is
/// exactly how a fixture ends up not exercising the field it exists to test: the
/// third copy is the one that was edited last.
GameSettings settingsWith({int worldTick = 0, bool includeTick = true}) {
  return GameSettings.fromJson({
    'totalSectors': 50,
    'portDensity': 0.35,
    'planetDensity': 0.5,
    'traderDensity': 0.12,
    'duranDensity': 0.10,
    'vinariDensity': 0.08,
    'pirateDensity': 0.10,
    'anomalyDensity': 0.1,
    'fedSpaceEnd': 7,
    'bubbleChance': 0.15,
    'maxBubbleSize': 12, // int, not double
    if (includeTick) 'worldTick': worldTick,
  });
}

void main() {
  setUp(() => GameClock.resetForTest());

  group('the unit conversions the game quotes to players', () {
    test('a tick is 30 seconds', () {
      // Every "you are going to do something for 30 minutes, that is 60 ticks"
      // statement in the game comes from these three constants.
      expect(GameClock.secondsPerTick, 30);
      expect(GameClock.ticksPerMinute, 2);
      expect(GameClock.ticksPerHour, 120);
      expect(GameClock.ticksPerDay, 2880);
      expect(60 * 2, GameClock.ticksPerHour, reason: '30 minutes is 60 ticks');
    });

    test('the banking rate the player is shown is derivable from ticks', () {
      // The worked example: 1.1% a day on 100,000 cr is 1,100 cr over a day,
      // which is this many credits per tick.
      const balance = 100000.0;
      const rate = 0.011;
      final perDay = balance * rate;
      expect(perDay, 1100);
      expect(perDay / GameClock.ticksPerDay, closeTo(0.38194, 0.00001));
    });

    test('formats durations the way the countdown widgets need', () {
      // 60 ticks = 30 min, 120 = one hour, 148 = 1h 14m. I wrote '2h' for 120
      // on the first pass, which is the arithmetic error this test exists to
      // prevent being made in the UI: ticksPerHour is 120, so 120 ticks *is* an
      // hour, not two.
      expect(GameClock.format(60), '30m');
      expect(GameClock.format(120), '1h');
      expect(GameClock.format(120 + 28), '1h 14m');
      expect(GameClock.format(GameClock.ticksPerDay), '1d');
      expect(GameClock.format(GameClock.ticksPerDay + 240), '1d 2h');
      expect(GameClock.format(0), '0s');
    });
  });

  group('a deadline is compared in ticks', () {
    test('active before the deadline and inactive on it', () {
      GameClock.resetForTest(100);
      expect(GameClock.isActive(200), isTrue);
      expect(GameClock.isActive(100), isFalse,
          reason: 'the boundary: due *at* the deadline, not one tick after');
      expect(GameClock.hasPassed(100), isTrue);
      expect(GameClock.hasPassed(200), isFalse);
    });

    test('a null deadline is neither active nor passed', () {
      // How an absent ban or timer reads. Getting this wrong in either direction
      // is how a "no deadline" becomes "already expired".
      expect(GameClock.isActive(null), isFalse);
      expect(GameClock.hasPassed(null), isFalse);
    });

    test('remaining counts down and floors at zero', () {
      GameClock.resetForTest(100);
      expect(GameClock.remaining(160), 60);
      expect(GameClock.remaining(100), 0);
      expect(GameClock.remaining(10), 0,
          reason: 'a passed deadline is not negative');
    });
  });

  group('closing the game stops the clock', () {
    test('a deadline set in one session still stands in the next', () {
      // The property the hack ban and the sabotage both depend on. If the counter
      // reset, a 24-hour ban would be void on the next launch \u2014 the player clears
      // a ban by quitting, which is not a ban.
      GameClock.resetForTest(1000);
      final banUntil = GameClock.tick + GameClock.ticksPerDay;

      // "A month later" in wall-clock terms. The clock has not moved, because the
      // game was closed the entire time.
      GameClock.resetForTest(1000);
      expect(GameClock.isActive(banUntil), isTrue,
          reason: 'a month of real time is not game time');

      // 2,879 ticks of play \u2014 still banned.
      GameClock.resetForTest(1000 + GameClock.ticksPerDay - 1);
      expect(GameClock.isActive(banUntil), isTrue);

      // One more tick, and the day is up.
      GameClock.resetForTest(banUntil);
      expect(GameClock.isActive(banUntil), isFalse);
    });
  });

  group('the counter only moves forward', () {
    test('advance moves it and reports the new value', () async {
      GameClock.resetForTest(10);
      expect(GameClock.tick, 10);
      final next = await GameClock.advance();
      expect(next, 11);
      expect(GameClock.tick, 11);
    });

    test('advance is a no-op for zero or negative', () async {
      GameClock.resetForTest(10);
      await GameClock.advance(0);
      expect(GameClock.tick, 10);
      await GameClock.advance(-5);
      expect(GameClock.tick, 10,
          reason: 'a negative advance would move every deadline backwards');
    });

    test('a run of ticks accumulates exactly', () async {
      // Counted one at a time on purpose. A per-tick clock asserted in one bulk
      // call is not the same assertion: the port refill's guard caught a real
      // drift only because it stepped 2,880 times, and a single bulk call here
      // would pass against a counter that mishandles intermediate values.
      GameClock.resetForTest(0);
      for (var i = 0; i < 100; i++) {
        await GameClock.advance();
      }
      expect(GameClock.tick, 100);
    });
  });

  group('the counter is persisted on GameSettings', () {
    test('worldTick survives a JSON round trip', () {
      // Without this, every stored deadline in every save is meaningless: the
      // counter comes back at 0 and `N - 0` is enormous, so nothing ever expires.
      final restored =
          GameSettings.fromJson(settingsWith(worldTick: 12345).toJson());
      expect(restored.worldTick, 12345);
    });

    test('an absent key reads as a fresh universe, not a huge one', () {
      // Every pre-clock save lacks the key. 0 is correct: there is no cooldown
      // progress to preserve, and a null or sentinel would make every deadline
      // unreachable instead.
      final restored =
          GameSettings.fromJson(settingsWith(includeTick: false).toJson());
      expect(restored.worldTick, 0);
    });

    test('copyWith can advance it without disturbing the rest', () {
      final base = settingsWith();
      final moved = base.copyWith(worldTick: 99);
      expect(moved.worldTick, 99);
      expect(moved.totalSectors, base.totalSectors,
          reason: 'the clock shares a file with the universe config, so '
              'writing it must not disturb the generation settings');
      expect(moved.portDensity, base.portDensity);
    });
  });

  group('periodsSince is the shared age conversion', () {
    test('counts whole units and goes negative for the future', () {
      GameClock.resetForTest(1000);
      expect(GameClock.periodsSince(1000 - 240, GameClock.ticksPerHour), 2,
          reason: '240 ticks is two hours');
      expect(GameClock.periodsSince(1000, GameClock.ticksPerMinute), 0);
      expect(
          GameClock.periodsSince(
              1000 + GameClock.ticksPerDay, GameClock.ticksPerMinute),
          -1440,
          reason:
              'a future deadline must read negative so the UI can say "left"');
    });
  });
}
