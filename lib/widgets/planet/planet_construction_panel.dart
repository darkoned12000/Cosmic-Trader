import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/widgets/planet/planet_info_row.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';

/// The progress panel for a Citadel tier already under construction.
///
/// Takes the whole card over while a build runs. The level-gate rows describe
/// work that has already been paid for, so showing them again beside a progress
/// bar would invite the player to think they still had a choice.
///
/// Extracted from `PlanetScreen` as a pure widget: a [Planet] and a
/// [ColorScheme] in, nothing else.
class PlanetConstructionPanel extends StatelessWidget {
  const PlanetConstructionPanel({
    super.key,
    required this.planet,
    required this.cs,
  });

  final Planet planet;
  final ColorScheme cs;

  /// The tier being built, named.
  ///
  /// `levelTitles` is 0-indexed and `constructionTarget` is the **level number**
  /// being built, so this needs `[target - 1]`. Reading `[target]` paired every
  /// build with the tier above it — a 1->2 build labelled "Colony" — and, because
  /// this sits beside a header reading `Building $title — level ${level + 1}`,
  /// printed "Building Citadel — level 2". The `length - 1` guard was a second
  /// bug on top: a 5->6 build has `target == 6` and `length == 6`, so it fell
  /// through to the literal string "Level 6" — a third presentation for the same
  /// fact.
  ///
  /// The bound is `target <= length`, and a target outside the table has no name
  /// to show, so it degrades to the number rather than to a mislabelled tier.
  static String titleFor(Planet planet) {
    final target = planet.constructionTarget;
    return target > 0 && target <= Planet.levelTitles.length
        ? Planet.levelTitles[target - 1]
        : 'Level $target';
  }

  @override
  Widget build(BuildContext context) {
    final remaining = planet.constructionTicksRemaining;
    final total = planet.constructionTotalTicks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // No spinner here. The bar below is determinate, so a spinner would
            // be redundant *and* worse: an indeterminate indicator animates
            // forever, which never settles, costs a frame every rebuild, and
            // reads as "working" even on a build the player has set to instant.
            const Icon(Icons.construction_rounded,
                size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Building ${titleFor(planet)} — level ${planet.level + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.amber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // The same bar as the transit panel, for the same reason: a build is a
        // tick countdown, so it can move every second and stay honest about how
        // many ticks are left. It used to be a bare `LinearProgressIndicator`
        // driven straight from `constructionProgress`, which sat still for thirty
        // seconds and then jumped — the identical defect, in the panel beside it.
        TickProgressBar(
          key: const ValueKey('planet-construction-bar'),
          remaining: planet.constructionTicksRemaining,
          total: planet.constructionTotalTicks,
          secondsPerTick: GameClock.secondsPerTick,
          color: Colors.amber,
          trackColor: Colors.amber.withValues(alpha: 0.18),
        ),
        const SizedBox(height: 8),
        PlanetInfoRow(
          'Progress',
          '${total - remaining} / $total ticks'
              '${total > 0 ? '  (${GameClock.estimate(remaining)})' : ''}',
        ),
        const SizedBox(height: 6),
        Text(
          'Advances one step per game tick, so it only moves while you are '
          'playing — the same clock the galaxy runs on.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}
