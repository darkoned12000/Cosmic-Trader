import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/game_clock.dart';

/// The in-transit colonist shipment, drawn like `PlanetConstructionPanel`.
///
/// Same determinate bar, same amber track, same "N / M ticks" progress row —
/// because it is the same kind of thing: work already paid for that advances one
/// step per game tick. The bar is what makes a purchase feel like it did
/// something; a text row alone did not, and a player who had just spent credits
/// on 100 colonists reported "nothing happens on the planet screen".
///
/// Extracted from `PlanetScreen` as a pure widget: it reads a [Planet] and a
/// [ColorScheme] and nothing else, so it has no reason to live inside a 3,500-line
/// `State`.
class PlanetTransitPanel extends StatelessWidget {
  const PlanetTransitPanel({
    super.key,
    required this.planet,
    required this.cs,
  });

  final Planet planet;
  final ColorScheme cs;

  /// Countdown in game-clock units.
  ///
  /// `GameClock.format`, not a seconds clock: a tick is 30 seconds, so a
  /// wall-clock countdown would be inventing precision the tick does not have.
  ///
  /// The exhausted case says "now" rather than "0s" because the countdown is
  /// displayed *before* the tick that lands it, so `0` is the ordinary state on
  /// the final tick and a bare "0s" reads as a broken timer.
  static String _remainingLabel(Planet planet) {
    if (planet.colonistTransitTicks <= 0) return 'now';
    return GameClock.format(planet.colonistTransitTicks);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = planet.colonistTransitTicks;
    final headcount = planet.colonistsInTransit;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.groups_rounded, size: 16, color: Colors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${compact(headcount)} colonists en route',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            // **The bar animates, but the tick clock stays the truth.**
            //
            // `colonistTransitProgress` only changes when a tick lands, so a raw
            // bar sat still for 29 seconds and then jumped half its length — a
            // liveness indicator that reads as frozen. `TweenAnimationBuilder`
            // moves the drawn value from wherever it is *toward* the true value
            // over one tick's worth of real time, which fills the gap without
            // inventing progress: it never animates past `end`, so a late tick
            // makes it wait rather than lie, and it cannot reach 100% before the
            // shipment actually lands.
            //
            // The duration is one tick, not the whole flight, because the target
            // is re-read on every rebuild (the screen refreshes each second, and
            // the tick lands every 30). Each tick moves the target and the bar
            // glides to meet it. If a dev changes the tick interval the *rate* is
            // out of step while the *value* stays honest, which is the right way
            // round for a display.
            child: TweenAnimationBuilder<double>(
              // `begin: 0` is read only on the first build — afterwards the
              // builder keeps the current drawn value and animates from there to
              // the new `end`, which is what makes the bar continuous rather than
              // restarting on every rebuild.
              tween: Tween<double>(
                begin: 0,
                end: planet.colonistTransitDrawnProgress,
              ),
              duration: const Duration(seconds: GameClock.secondsPerTick),
              builder: (context, value, _) => LinearProgressIndicator(
                // Keyed so a test can name *this* bar. The colony card draws six
                // other progress bars (one per workforce track, plus the drone
                // readout), so a count of `LinearProgressIndicator` cannot tell
                // the transit bar apart from any of them — the same trap as
                // counting warp-chip icons.
                key: const ValueKey('colonist-transit-bar'),
                value: value,
                minHeight: 10,
                // A real track, not decoration — the same reason as the build
                // bar: a determinate bar at 0% is only its track, and a track too
                // close to the card fill reads as no bar at all on the tick it
                // starts.
                backgroundColor: Colors.amber.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(Colors.amber),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Arriving in ${_remainingLabel(planet)}'
            '${remaining > 0 ? '  (${GameClock.estimate(remaining)})' : ''}'
            ' — then they join the reserve below. Assign them to a track to '
            'put them to work.',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}
