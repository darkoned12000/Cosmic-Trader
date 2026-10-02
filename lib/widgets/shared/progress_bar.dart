import 'dart:async';

import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/progress.dart';

/// A progress bar driven by a **tick countdown**, smooth between ticks.
///
/// ## Why it can be both smooth and accurate
///
/// One tick is 30 seconds, so a run of `total` ticks has an exactly known
/// duration. That makes the maths easy and honest: the bar measures real time
/// *within the current tick* and resyncs the moment the tick count changes.
///
/// ```
/// fraction = (completedTicks + timeIntoCurrentTick / secondsPerTick) / total
/// ```
///
/// So it moves every second, and it can never claim more progress than the ticks
/// have actually granted — the sub-tick term is bounded by one tick, and it is
/// discarded the instant the real count moves.
///
/// ## The failure this replaces
///
/// A bar drawn straight from tick state sits still for a whole tick and then
/// lurches. The colonist transit bar did exactly that — twenty-nine seconds of
/// nothing, then half its length — and a player reported it as frozen, because
/// from their side it was. The first fix animated *toward* the next tick's value,
/// which worked but needed a look-ahead getter on the model and would have been
/// re-derived for every new bar. Measuring the sub-tick directly is simpler, has
/// no look-ahead, and is the same shape for every countdown in the game.
///
/// ## The rule that keeps it honest
///
/// [remaining] and [total] are the **truth** and come from the tick clock. The
/// sub-tick term is presentation. A bar driven by a `t / D` clock of its own would
/// reach 100% on schedule whether or not the work landed; this one cannot, because
/// the whole-number part only ever moves when a tick does.
class TickProgressBar extends StatefulWidget {
  const TickProgressBar({
    super.key,
    required this.remaining,
    required this.total,
    this.secondsPerTick = 30,
    this.easing = ProgressEasing.linear,
    this.color,
    this.trackColor,
    this.minHeight = 10,
    this.radius = 5,
  });

  /// Ticks left. The authority — supplied by the tick clock, not measured here.
  final int remaining;

  /// Ticks the whole job was given.
  final int total;

  /// One tick in seconds. Passed in rather than hardcoded so the widget has no
  /// opinion about the game's clock; callers use `GameClock.secondsPerTick`.
  final int secondsPerTick;

  /// Curve applied to the fraction. [ProgressEasing.linear] by default: a task
  /// bar should not misreport how much is left, and an eased bar does at both
  /// ends.
  final ProgressEasing easing;

  final Color? color;
  final Color? trackColor;
  final double minHeight;
  final double radius;

  @override
  State<TickProgressBar> createState() => _TickProgressBarState();
}

class _TickProgressBarState extends State<TickProgressBar> {
  /// Seconds elapsed in the **current** tick, counted by the pump below.
  ///
  /// A counter rather than a `Stopwatch` or `DateTime.now()`, and that is a
  /// deliberate trade. Both of those measure *real* time, which `flutter_test`'s
  /// fake-async zone does not advance — so a bar driven by them works in the app
  /// and is **untestable**, and a guard that cannot fail is worse than no guard.
  /// This was found by the first test written against it: the timer fired, the
  /// stopwatch did not move, and the assertion failed.
  ///
  /// The cost is drift: a busy frame delays the timer, so the count can lag real
  /// time. That is bounded by one game tick, because [didUpdateWidget] resets it
  /// whenever the authoritative count moves — and this is a bar, not a clock.
  int _secondsIntoCurrentTick = 0;

  Timer? _pump;

  /// Advances the sub-tick term once a second.
  ///
  /// A second rather than a frame: a bar that moves 1/30th of its length per
  /// second reads as moving, and rebuilding every frame for a background job is a
  /// cost with no visible return. The colonist bar was specified at 1s for the
  /// same reason.
  static const Duration _pumpInterval = Duration(seconds: 1);

  @override
  void initState() {
    super.initState();
    _pump = Timer.periodic(_pumpInterval, (_) {
      if (!mounted) return;
      setState(() => _secondsIntoCurrentTick++);
    });
  }

  @override
  void didUpdateWidget(TickProgressBar old) {
    super.didUpdateWidget(old);
    // The tick landed: drop the sub-tick term rather than carrying it, so the
    // fraction steps from `completed + ~1` back to `completed + 0` and keeps
    // climbing. Carrying it would jump the bar forward by a full tick.
    if (old.remaining != widget.remaining) {
      _secondsIntoCurrentTick = 0;
    }
  }

  @override
  void dispose() {
    _pump?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fill = widget.color ?? cs.primary;
    final track =
        widget.trackColor ?? cs.surfaceContainerHighest.withValues(alpha: 0.3);

    final total = widget.total;
    final fraction = total <= 0
        ? 1.0
        : _fraction(
            completed: total - widget.remaining,
            total: total,
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: widget.minHeight,
        // A real track, not decoration: a determinate bar at 0% is *only* its
        // track, and a track too close to the card fill reads as no bar at all
        // on the tick it starts.
        backgroundColor: track,
        valueColor: AlwaysStoppedAnimation(fill),
      ),
    );
  }

  /// `(completed + timeIntoCurrentTick) / total`, clamped.
  ///
  /// **The sub-tick term never completes a tick.** It is capped just below one,
  /// so the fraction can approach the next tick's value but never reach it: a bar
  /// whose last tick has not landed must not read as finished. Without the cap the
  /// arithmetic is `(total - 1 + 1) / total = 1` on the final tick, which is the
  /// same lie a self-driven `t / D` clock tells — and it was caught by a test
  /// written against exactly that claim.
  ///
  /// 0.98 is a visible "nearly there" that stalls for the last 2% of a tick —
  /// under a second of a thirty-second one, so it is not perceptible as a stall.
  ///
  /// The term is also discarded the instant the real count moves (see
  /// `didUpdateWidget`), so a suspended app — where the timer stops but the count
  /// does not — parks the bar rather than racing it to the end.
  double _fraction({required int completed, required int total}) {
    if (completed >= total) return 1;
    if (completed < 0) return 0;

    final secondsPerTick = widget.secondsPerTick;
    final subTick = secondsPerTick <= 0
        ? 0.0
        : clamp01(_secondsIntoCurrentTick / secondsPerTick) * _maxSubTick;

    final raw = (completed + subTick) / total;
    return ease(clamp01(raw), widget.easing);
  }

  /// How far into the current tick the bar is allowed to draw.
  static const double _maxSubTick = 0.98;
}
