import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';

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
          // **The bar measures the sub-tick; the tick count stays the truth.**
          //
          // A run of N ticks is exactly N x 30s, so the bar can measure real time
          // within the current tick and resync whenever the count moves. It moves
          // every second and cannot claim progress the ticks have not granted —
          // see `TickProgressBar`.
          //
          // This replaced a look-ahead getter (`colonistTransitDrawnProgress`,
          // "one tick ahead") that existed only because the previous bar animated
          // *toward* the next tick's value. Measuring the sub-tick directly is
          // simpler and needs no such field on the model.
          TickProgressBar(
            // Keyed so a test can name *this* bar. The colony card draws six
            // other progress bars (one per workforce track, plus the drone
            // readout), so a count of `LinearProgressIndicator` cannot tell the
            // transit bar apart from any of them — the same trap as counting
            // warp-chip icons.
            key: const ValueKey('colonist-transit-bar'),
            remaining: planet.colonistTransitTicks,
            total: planet.colonistTransitTotalTicks,
            secondsPerTick: GameClock.secondsPerTick,
            color: Colors.amber,
            trackColor: Colors.amber.withValues(alpha: 0.18),
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
