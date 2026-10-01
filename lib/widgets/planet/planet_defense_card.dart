import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/widgets/planet/planet_info_row.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';

/// One capability bar: `value / max` with the figure printed as integers.
///
/// Distinct from the Resources card's bar, which shows a **stored commodity**
/// with two decimals so a slow production track is visibly moving. A shield or
/// hull figure is a capability, not an accumulating stock, so it is shown whole.
class PlanetDefenseBar extends StatelessWidget {
  const PlanetDefenseBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
  });

  final String label;
  final double value;
  final double max;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return StatBar(
      layout: StatBarLayout.stacked,
      label: label,
      value: '${value.toInt()} / ${max.toInt()}',
      percent: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
      color: color,
    );
  }
}

/// The Defense card: level, drones, shield and armour.
///
/// Extracted from `PlanetScreen` as a pure widget — a [Planet] in, nothing out.
class PlanetDefenseCard extends StatelessWidget {
  const PlanetDefenseCard({
    super.key,
    required this.planet,
    required this.cs,
  });

  final Planet planet;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Defense',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            PlanetInfoRow('Defense Level', '${planet.defenseLevel} / 4'),
            // No two-decimal fraction here: that exists on the Resources card to
            // make a slow production track visibly move, and a drone stock is
            // read as a capability rather than watched tick by tick. The figures
            // are still **compacted**, because this row shares the Resources
            // builder and a raw seven-digit drone count would wrap the card.
            StatBar(
              layout: StatBarLayout.stacked,
              label: 'Drones',
              value: planet.maxDrones > 0
                  ? '${compact(planet.storedDrones)}/${compact(planet.maxDrones)}'
                  : compact(planet.storedDrones),
              percent: planet.maxDrones > 0
                  ? (planet.storedDrones / planet.maxDrones).clamp(0.0, 1.0)
                  : 0.0,
              color: Colors.red,
            ),
            const SizedBox(height: 4),
            PlanetDefenseBar(
                label: 'Shield',
                value: planet.shield,
                max: planet.maxShield,
                color: Colors.cyan),
            PlanetDefenseBar(
                label: 'Armor',
                value: planet.hull,
                max: planet.maxHull,
                color: Colors.green),
          ],
        ),
      ),
    );
  }
}
