/// Turning elapsed time into a 0..1 progress fraction, with easing.
///
/// Pure maths, deliberately Flutter-free, so it can be unit-tested without a
/// widget and read from anywhere. `lib/widgets/shared/progress_bar.dart` consumes
/// it; nothing here draws.
///
/// ## Two different things are called "progress"
///
/// **Continuous progress** knows a start and a duration — a 60-second flight, a
/// four-minute cargo run — and asks "how far through are we". That is
/// [progressFraction], and the formulas are for that.
///
/// **Stepped progress** only changes when an authoritative event lands, and the
/// value between events is unknown. A bar drawn straight from it sits still and
/// then jumps, which reads as broken: the colonist transit bar did exactly that,
/// and at a four-minute run the problem is sixteen times worse than the
/// twenty-nine seconds that prompted the fix. A stepped bar wants
/// `EasedProgressBar`, which glides toward each new value rather than inventing
/// time between them.
///
/// Confusing the two is how a bar claims a job is finished before it is — a
/// continuous clock reaches 100% happily while the tick that lands the cargo has
/// not run. **The tick stays the authority; this is presentation.**
library;

import 'dart:math' as math;

/// Clamps [value] into 0..1.
///
/// `min(1, max(0, x))` from the source formulas, named so the intent reads at a
/// call site. `NaN` becomes 0 rather than propagating: `NaN.clamp(...)` is `NaN`,
/// which paints as an empty bar instead of raising anything anyone would notice.
double clamp01(double value) => value.isNaN ? 0 : value.clamp(0.0, 1.0);

/// The easing curves available to a progress bar.
enum ProgressEasing {
  /// Constant rate. The right default for a **task** bar: a player watching a
  /// four-minute run wants to know how much is left, and an eased bar misreports
  /// that at both ends.
  linear,

  /// Starts slow, accelerates, slows into the end — smoothstep. Pretty, and wrong
  /// for a countdown for the same reason.
  easeInOut,

  /// Starts fast, decelerates into the end.
  easeOut,

  /// Starts slow, accelerates into the end.
  easeIn,
}

/// Applies [easing] to a **normalised** time `u`.
///
/// Input is clamped, so a caller that has not clamped does not get a curve that
/// overshoots.
double ease(double u, ProgressEasing easing) {
  final t = clamp01(u);
  return switch (easing) {
    ProgressEasing.linear => t,
    // 3u^2 - 2u^3
    ProgressEasing.easeInOut => 3 * t * t - 2 * t * t * t,
    // 1 - (1 - u)^2
    ProgressEasing.easeOut => 1 - (1 - t) * (1 - t),
    // u^2
    ProgressEasing.easeIn => t * t,
  };
}

/// Elapsed time as a fraction of [duration], clamped to 0..1.
///
/// `min(1, max(0, t / D))` — the source formula, verbatim.
///
/// **A non-positive [duration] returns 1, not 0.** A zero-length task is
/// finished, and returning 0 would leave a bar permanently empty on any division
/// a caller forgot to guard. Say the answer rather than dividing — the same lesson
/// as the `max(1, …)` that silently turned a 1px lid into "no lid at all".
double progressFraction(
  Duration elapsed,
  Duration duration, {
  ProgressEasing easing = ProgressEasing.linear,
}) {
  if (duration <= Duration.zero) return 1;
  return ease(elapsed.inMicroseconds / duration.inMicroseconds, easing);
}

/// As [progressFraction], in percent 0..100.
double progressPercent(
  Duration elapsed,
  Duration duration, {
  ProgressEasing easing = ProgressEasing.linear,
}) =>
    progressFraction(elapsed, duration, easing: easing) * 100;

/// `(remaining, total)` as a fraction complete, clamped.
///
/// The shape a **stepped** bar actually has: the models carry ticks remaining and
/// a total, not a wall-clock start — `constructionTicksRemaining` /
/// `constructionTotalTicks`, `colonistTransitTicks` / `colonistTransitDelayTicks`,
/// and a trade job's `ticksRemaining` / `ticksPerRun`. Taking the pair directly
/// means no screen converts to a `Duration` just to draw a bar.
///
/// A non-positive [total] is treated as finished, for the same reason as above.
double steppedFraction(
  int remaining,
  int total, {
  ProgressEasing easing = ProgressEasing.linear,
}) {
  if (total <= 0) return 1;
  return ease((total - remaining) / total, easing);
}

/// Formats a duration the way a countdown should read — `4m`, `30s`, `1h 5m`.
///
/// Deliberately coarse. A bar driven by 30-second ticks has no business printing
/// precision it does not have, and `4m` is what a player repeats to themselves.
String formatDuration(Duration d) {
  if (d <= Duration.zero) return 'now';
  final seconds = d.inSeconds;
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (hours < 24) return rem == 0 ? '${hours}h' : '${hours}h ${rem}m';
  final days = hours ~/ 24;
  final remH = hours % 24;
  return remH == 0 ? '${days}d' : '${days}d ${remH}h';
}

/// Guards a divisor so a bar cannot produce `NaN`.
///
/// Kept because the failure is silent: a `total` of 0 gives `NaN`, which paints as
/// an empty bar rather than as anything a test would catch.
int atLeastOne(int value) => math.max(1, value);
