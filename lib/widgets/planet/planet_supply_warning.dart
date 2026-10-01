import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/planet.dart';

/// The "stores empty — supply unpaid" banner in the Colony card.
///
/// A colony is billed a share of its own output once a game day, and this is
/// what the player sees when it could not pay. The message names the fix rather
/// than the problem, and the fix differs by world type: a world that cannot make
/// organics at all is not short of effort, it is structurally unable to feed
/// itself, so it needs goods hauled in or a complement planted beside it.
///
/// Extracted from `PlanetScreen` as a pure widget.
class PlanetSupplyWarning extends StatelessWidget {
  const PlanetSupplyWarning({
    super.key,
    required this.planet,
    required this.cs,
  });

  final Planet planet;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stores empty — supply unpaid',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  planet.canProduce('organics')
                      ? 'Haul minerals, organics or industrial in, or collect '
                          'what is already queued.'
                      : 'This world cannot make organics. Unload organics from '
                          'your hold, or plant a world beside it that grows '
                          'them.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
