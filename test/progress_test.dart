import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/core/progress.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';

/// The maths behind every progress bar, and the bar that draws it.
///
/// Pure functions first, so the formulas are pinned without a widget; then the
/// tick-driven bar, which is the part that has actually been wrong twice.
void main() {
  group('clamp01', () {
    test('clamps both ends and passes the middle through', () {
      expect(clamp01(-1), 0);
      expect(clamp01(0), 0);
      expect(clamp01(0.5), 0.5);
      expect(clamp01(1), 1);
      expect(clamp01(2), 1);
    });

    test('NaN becomes 0 rather than propagating', () {
      // `NaN.clamp(...)` is `NaN`, which paints as an empty bar and raises
      // nothing — the silent-divisor failure.
      expect(clamp01(double.nan), 0);
    });
  });

  group('ease', () {
    test('every curve passes through 0 and 1', () {
      for (final e in ProgressEasing.values) {
        expect(ease(0, e), 0, reason: '$e at 0');
        expect(ease(1, e), 1, reason: '$e at 1');
      }
    });

    test('linear is the identity', () {
      expect(ease(0.25, ProgressEasing.linear), 0.25);
      expect(ease(0.75, ProgressEasing.linear), 0.75);
    });

    test('matches the documented formulas', () {
      const u = 0.5;
      // smoothstep: 3u^2 - 2u^3
      expect(ease(u, ProgressEasing.easeInOut), 3 * u * u - 2 * u * u * u);
      // 1 - (1 - u)^2
      expect(ease(u, ProgressEasing.easeOut), 1 - (1 - u) * (1 - u));
      // u^2
      expect(ease(u, ProgressEasing.easeIn), u * u);
    });

    test('easeIn starts below linear and easeOut above it', () {
      // The property a viewer sees, not just the formula: easeIn is slow at the
      // start, easeOut is fast.
      expect(ease(0.25, ProgressEasing.easeIn), lessThan(0.25));
      expect(ease(0.25, ProgressEasing.easeOut), greaterThan(0.25));
      // And they are mirrors of each other.
      expect(ease(0.25, ProgressEasing.easeOut),
          closeTo(1 - ease(0.75, ProgressEasing.easeIn), 1e-9));
    });

    test('clamps input rather than overshooting', () {
      expect(ease(-5, ProgressEasing.easeInOut), 0);
      expect(ease(5, ProgressEasing.easeInOut), 1);
    });
  });

  group('progressFraction', () {
    test('is elapsed over duration, clamped', () {
      expect(
          progressFraction(
              const Duration(seconds: 15), const Duration(seconds: 60)),
          0.25);
      expect(
          progressFraction(
              const Duration(seconds: 60), const Duration(seconds: 60)),
          1);
      expect(
          progressFraction(
              const Duration(seconds: 90), const Duration(seconds: 60)),
          1,
          reason: 'past the end is 100%, not 150%');
      expect(progressFraction(Duration.zero, const Duration(seconds: 60)), 0);
    });

    test('a zero or negative duration is finished, not empty', () {
      // Returning 0 would leave a bar permanently empty on any division a caller
      // forgot to guard. A zero-length task is done.
      expect(progressFraction(Duration.zero, Duration.zero), 1);
      expect(
          progressFraction(
              const Duration(seconds: 5), const Duration(seconds: -1)),
          1);
    });

    test('percent is the fraction times a hundred', () {
      expect(
          progressPercent(
              const Duration(seconds: 30), const Duration(seconds: 60)),
          50);
    });
  });

  group('steppedFraction', () {
    test('is (total - remaining) / total', () {
      expect(steppedFraction(2, 2), 0);
      expect(steppedFraction(1, 2), 0.5);
      expect(steppedFraction(0, 2), 1);
    });

    test('a zero total is finished, not a divide by zero', () {
      expect(steppedFraction(0, 0), 1);
    });

    test('clamps a remaining above the total', () {
      // A corrupt save could carry `remaining > total`; the bar must not go
      // negative.
      expect(steppedFraction(10, 2), 0);
    });
  });

  group('formatDuration', () {
    test('is coarse on purpose', () {
      expect(formatDuration(const Duration(seconds: 30)), '30s');
      expect(formatDuration(const Duration(minutes: 4)), '4m');
      expect(formatDuration(const Duration(minutes: 59)), '59m');
      expect(formatDuration(const Duration(hours: 1)), '1h');
      expect(formatDuration(const Duration(minutes: 65)), '1h 5m');
      expect(formatDuration(const Duration(hours: 24)), '1d');
      expect(formatDuration(Duration.zero), 'now');
    });
  });

  group('TickProgressBar', () {
    /// Hosts the bar at a fixed tick state, with a rebuild hook.
    Future<void> pump(
      WidgetTester tester, {
      required int remaining,
      required int total,
    }) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: TickProgressBar(
            key: const ValueKey('bar'),
            remaining: remaining,
            total: total,
            secondsPerTick: 30,
          ),
        ),
      ));
    }

    double drawn(WidgetTester tester) => tester
        .widget<LinearProgressIndicator>(find.descendant(
          of: find.byKey(const ValueKey('bar')),
          matching: find.byType(LinearProgressIndicator),
        ))
        .value!;

    testWidgets('starts at the completed fraction', (tester) async {
      await pump(tester, remaining: 4, total: 4);
      expect(drawn(tester), 0);
      await pump(tester, remaining: 2, total: 4);
      expect(drawn(tester), 0.5);
      await pump(tester, remaining: 0, total: 4);
      expect(drawn(tester), 1);
    });

    testWidgets('advances every second WITHOUT the tick moving',
        (tester) async {
      // The whole point. A bar drawn straight from tick state sits still for
      // thirty seconds and then jumps; a player reported that as frozen.
      await pump(tester, remaining: 2, total: 2);
      final atStart = drawn(tester);

      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final later = drawn(tester);

      expect(later, greaterThan(atStart),
          reason: 'the bar must move between ticks');
      expect(later, lessThan(0.5),
          reason: 'five seconds into a thirty-second tick is not halfway');
    });

    testWidgets('never claims more than the ticks have granted',
        (tester) async {
      // **The rule that keeps it honest.** The sub-tick term is bounded by one
      // tick, so the bar cannot reach the next tick's value until that tick
      // lands. A `t / D` clock of its own would sail past this.
      await pump(tester, remaining: 1, total: 2);
      expect(drawn(tester), 0.5, reason: 'one of two ticks done');

      // Sit for longer than a whole tick, without the count moving.
      for (var i = 0; i < 90; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(drawn(tester), lessThanOrEqualTo(1.0),
          reason: 'bounded by the total');
      expect(drawn(tester), greaterThan(0.5),
          reason: 'and it should have crept toward the next tick');
      expect(drawn(tester), lessThan(1.0),
          reason: 'but a bar whose last tick has NOT landed must not read as '
              'finished — that is the lie a self-driven clock tells');
    });

    testWidgets('the tick landing resets the sub-tick rather than carrying it',
        (tester) async {
      await pump(tester, remaining: 2, total: 2);
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      final beforeTick = drawn(tester);

      // The tick lands.
      await pump(tester, remaining: 1, total: 2);
      final afterTick = drawn(tester);

      expect(afterTick, 0.5,
          reason:
              'the completed count moved and the sub-tick went back to zero');
      // **Monotonic, which is the property that matters.** Before the tick the
      // sub-tick had climbed to 0.98 of a tick, giving 0.49; the tick landing
      // gives 0.5. A bar that *carried* the sub-tick instead of resetting it
      // would read (1 + 0.98) / 2 = 0.99 — a jump of half the bar for one tick.
      expect(afterTick, greaterThan(beforeTick),
          reason: 'the bar must never run backwards when a tick lands');
      expect(afterTick, lessThan(0.6),
          reason: 'a carried sub-tick would have jumped to ~0.99');
    });

    testWidgets('a zero total does not divide by zero', (tester) async {
      await pump(tester, remaining: 0, total: 0);
      expect(drawn(tester), 1);
    });

    testWidgets('paints a real track at 0%, not nothing', (tester) async {
      // A determinate bar at 0% is *only* its track. A track too close to the
      // card fill reads as no bar at all on the tick it starts.
      await pump(tester, remaining: 4, total: 4);
      final bar = tester.widget<LinearProgressIndicator>(find.descendant(
        of: find.byKey(const ValueKey('bar')),
        matching: find.byType(LinearProgressIndicator),
      ));
      expect(bar.backgroundColor, isNotNull);
      expect(bar.backgroundColor!.a, greaterThan(0.05),
          reason: 'a fully transparent track is an invisible bar');
    });
  });
}
