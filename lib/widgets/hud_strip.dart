import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';

/// Persistent mission HUD strip — the game's "always on" status bar.
///
/// A3 black-box request: sector name, credits, turns/energy and hull/shields
/// "always visible at the top instead of buried in tabs". The strip sits
/// above the tab content on both the mobile and desktop layouts, updates
/// live with the player, wears a faction *ambiance* accent (dominant faction
/// in the current sector), and routes all spacing through [UiScale.spacing]
/// so Compact/Cozy density adjusts it like every other A2 surface.
class HudStrip extends StatelessWidget {
  const HudStrip({
    super.key,
    required this.player,
    this.sector,
    this.dominantFaction,
  });

  final Player player;

  /// Current sector when the universe is loaded (name/id shown left).
  final Sector? sector;

  /// Dominant faction in the current sector — tints the leading accent bar
  /// and the sector title (the "per-sector faction ambiance" tint).
  final FactionClass? dominantFaction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mono = 'monospace';

    final accent =
        dominantFaction == null ? cs.primary : factionColor(dominantFaction!);
    final sectorLabel =
        sector != null ? '${sector!.name.toUpperCase()} • S${sector!.id}' : '…';

    final hullPct = player.maxHull > 0 ? player.hull / player.maxHull : 0.0;
    final shieldPct =
        player.maxShields > 0 ? player.shields / player.maxShields : 0.0;

    // The strip must never overflow: on narrow layouts the hull/shield bars
    // and even the turns meter drop off rather than squashing the row.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final showBars = width >= 760;
        final showTurns = width >= 560;
        return Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.55),
            border: Border(
              bottom: BorderSide(
                color: cs.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: UiScale.spacing(14),
            vertical: UiScale.spacing(5),
          ),
          child: Row(
            children: [
              // Faction ambiance accent bar.
              Container(
                width: 3,
                height: 26,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: UiScale.spacing(10)),
              Icon(Icons.my_location_rounded, size: 16, color: accent),
              SizedBox(width: UiScale.spacing(6)),
              Flexible(
                child: Text(
                  sectorLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: cs.onSurface,
                  ),
                ),
              ),
              const Spacer(),
              _metric(
                context,
                icon: Icons.paid_rounded,
                value: '${player.credits}',
                color: Colors.amber.shade600,
                mono: mono,
              ),
              if (showTurns) ...[
                SizedBox(width: UiScale.spacing(18)),
                _metric(
                  context,
                  icon: Icons.bolt_rounded,
                  value: '${player.turns} / ${player.maxTurns}',
                  color: cs.onSurface.withValues(alpha: 0.55),
                  mono: mono,
                ),
              ],
              if (showBars) ...[
                SizedBox(width: UiScale.spacing(16)),
                SizedBox(
                  width: 170,
                  child: StatBar(
                    label: 'HULL',
                    value: '${player.hull}',
                    percent: hullPct,
                    color: _hullColor(hullPct),
                    icon: Icons.shield_rounded,
                    labelWidth: 38,
                    valueWidth: 34,
                    barHeight: 5,
                  ),
                ),
                SizedBox(width: UiScale.spacing(16)),
                SizedBox(
                  width: 170,
                  child: StatBar(
                    label: 'SHD',
                    value: '${player.shields}',
                    percent: shieldPct,
                    color: Colors.lightBlueAccent,
                    icon: Icons.bubble_chart_rounded,
                    labelWidth: 32,
                    valueWidth: 34,
                    barHeight: 5,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Color _hullColor(double pct) {
    if (pct <= 0.25) return Colors.redAccent;
    if (pct <= 0.5) return Colors.orangeAccent;
    return Colors.greenAccent;
  }

  Widget _metric(
    BuildContext context, {
    required IconData icon,
    required String value,
    required Color color,
    required String mono,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color),
        SizedBox(width: UiScale.spacing(5)),
        Text(
          value,
          style: TextStyle(
            fontFamily: mono,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
