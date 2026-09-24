import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';

/// How a [StatBar] lays out its label, progress bar and value.
enum StatBarLayout {
  /// Icon + monospace label on the left, bar in the middle, value right.
  /// The classic HUD row (hull/shields/cargo in sector views).
  inline,

  /// Label and value on one line above the bar (planet production/defense,
  /// faction power). No icon by default.
  stacked,
}

/// Compact label + progress bar + value display used across status surfaces
/// (hull, shields, cargo, planet production, faction power, …).
///
/// Replaces the copy-pasted bar-row / label-above-bar implementations in
/// sector views, ship screens, planet and faction-ranking screens. Gaps and
/// column widths are density-aware via [UiScale.spacing], so Compact/Cozy
/// adjusts the rhythm everywhere the bar appears.
class StatBar extends StatelessWidget {
  const StatBar({
    super.key,
    required this.label,
    required this.value,
    required this.percent,
    required this.color,
    this.icon,
    this.layout = StatBarLayout.inline,
    this.labelWidth = 50,
    this.valueWidth = 55,
    this.barHeight = 6,
    this.trackColor,
  });

  /// Short label, e.g. `HULL` (inline) or `Mineral Production` (stacked).
  final String label;

  /// Right-aligned value text, e.g. `87 / 100`.
  final String value;

  /// Fill fraction 0..1 (clamped internally).
  final double percent;

  /// Bar (and inline icon) color.
  final Color color;

  /// Small icon left of the label (inline only). Optional.
  final IconData? icon;

  final StatBarLayout layout;

  /// Monospace label column width (inline only).
  final double labelWidth;

  /// Value column width (inline only).
  final double valueWidth;

  final double barHeight;

  /// Track fill color; defaults to `surfaceContainerHighest` at 30% alpha.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final track =
        trackColor ?? cs.surfaceContainerHighest.withValues(alpha: 0.3);

    if (layout == StatBarLayout.stacked) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 11,
                  ),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                backgroundColor: track,
                color: color,
                minHeight: barHeight,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 14, color: color),
          SizedBox(width: UiScale.spacing(6)),
        ],
        SizedBox(
          width: labelWidth,
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontFamily: 'monospace',
            ),
          ),
        ),
        SizedBox(width: UiScale.spacing(8)),
        Expanded(
          child: Stack(
            children: [
              Container(
                height: barHeight,
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(barHeight / 2),
                ),
              ),
              FractionallySizedBox(
                widthFactor: percent.clamp(0.0, 1.0),
                child: Container(
                  height: barHeight,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(barHeight / 2),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: UiScale.spacing(8)),
        SizedBox(
          width: valueWidth,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: cs.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}
