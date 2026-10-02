import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';

/// One stored commodity against its cap.
///
/// [showFraction] adds the two-decimal sub-unit remainder, and is on only for
/// the Resources rows. The Defense card's Drones row is a capability readout
/// rather than a production one — a `0.00` there would be noise, and the player
/// watching a slow track is looking at Resources.
class PlanetResourceBar extends StatelessWidget {
  const PlanetResourceBar({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    required this.color,
    this.showFraction = false,
  });

  final String label;

  /// A double because the Resources rows carry the sub-unit remainder: see
  /// [Planet.storedPlusRemainder]. Per-tick output is a fraction of a unit, so
  /// the integer half moves only every few ticks and a compacted figure does not
  /// move at all above a thousand.
  final double value;
  final int max;
  final Color color;
  final bool showFraction;

  @override
  Widget build(BuildContext context) {
    final shown = showFraction ? groupedDecimal(value) : compact(value.floor());
    return StatBar(
      layout: StatBarLayout.stacked,
      label: label,
      // Current against cap, not just the current figure. The bar was already
      // drawn proportionally, so the number beside it was the only place a
      // player could not see how much room a world has left — which matters
      // because a full store spills the surplus into the shipment pool rather
      // than wasting it, and the player's next decision is whether to sweep
      // it back or to reassign colonists.
      value: max > 0 ? '$shown/${compact(max)}' : shown,
      percent: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
      color: color,
    );
  }
}

/// Output waiting to be swept into the stores.
///
/// A colony keeps producing once its working store is full — that surplus is
/// queued here rather than discarded, so a world nobody has visited in a while
/// is still earning. Sweeping is free and priceless: it moves goods, never
/// credits, which is what retired the flat payout table that used to live
/// here.
///
/// The pool is overflow, not a sale — so this panel quotes no price. An
/// earlier version paid a flat per-unit table here, which gave the same goods
/// a second price beside the live port markets (and a third beside the old
/// transfer table). That button is deleted; this one only moves goods.
class PlanetShipmentPanel extends StatelessWidget {
  const PlanetShipmentPanel({
    super.key,
    required this.planet,
    required this.cs,
    required this.onSweep,
  });

  final Planet planet;
  final ColorScheme cs;

  /// Called when the player presses the sweep. Moving goods needs no amount:
  /// everything that fits goes. The transaction itself — moving the pool,
  /// persisting — stays on the screen, because it owns the write. This
  /// widget only knows how to draw the offer.
  final void Function() onSweep;

  @override
  Widget build(BuildContext context) {
    Widget line(String label, int amount, Color colour) {
      if (amount <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: colour)),
            Text('${compact(amount)} ready',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.6),
                )),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text('Ready to collect',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 6),
          line('Minerals', planet.pendingMinerals, Colors.orange),
          line('Organics', planet.pendingOrganics, Colors.green),
          line('Industrial', planet.pendingIndustrial, Colors.blue),
          line('Drones', planet.pendingDrones, Colors.red),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSweep,
              icon: const Icon(Icons.drive_file_move_rounded, size: 16),
              label: const Text('Move to store'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The Resources card: three stores against their caps, plus the shipment pool.
class PlanetResourcesCard extends StatelessWidget {
  const PlanetResourcesCard({
    super.key,
    required this.planet,
    required this.cs,
    required this.onSweep,
  });

  final Planet planet;
  final ColorScheme cs;
  final void Function() onSweep;

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
              'Resources',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Each commodity against its own cap. A single shared cap shown next
            // to a sum of three stores made a legal planet read as overfull.
            //
            // The stored figure is the **exact** value including the carried
            // fraction, not the compacted integer. Two reasons, and both were
            // reported: the integer only moves when a whole unit banks (every
            // third tick on a 5,000-colonist minerals track), and `compact`
            // hides any change at all once the figure passes a thousand. The cap
            // stays compacted, because a cap is a magnitude and does not need to
            // be watched.
            PlanetResourceBar(
              label: 'Minerals',
              value: planet.storedPlusRemainder('minerals'),
              max: planet.maxMinerals,
              color: Colors.orange,
              showFraction: true,
            ),
            PlanetResourceBar(
              label: 'Organics',
              value: planet.storedPlusRemainder('organics'),
              max: planet.maxOrganics,
              color: Colors.green,
              showFraction: true,
            ),
            PlanetResourceBar(
              label: 'Industrial',
              value: planet.storedPlusRemainder('industrial'),
              max: planet.maxIndustrial,
              color: Colors.blue,
              showFraction: true,
            ),
            if (planet.pendingTotal > 0) ...[
              const SizedBox(height: 12),
              PlanetShipmentPanel(planet: planet, cs: cs, onSweep: onSweep),
            ],
          ],
        ),
      ),
    );
  }
}
