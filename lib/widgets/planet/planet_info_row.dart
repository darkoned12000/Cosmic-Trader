import 'package:flutter/material.dart';

/// A label/value row for the planet cards, optionally with an `(i)` bubble.
///
/// [info] is the affordance the colonists transfer row and the Supply draw row
/// use: a small amber icon that explains a mechanic too long to fit in the row.
/// It opens on **hover or tap** — `TooltipTriggerMode.tap` governs the gesture
/// while mouse hover keeps working independently, so it is usable on desktop and
/// on a touch screen without a long-press nobody would guess at.
///
/// Extracted from `PlanetScreen` because five cards use it and it reads nothing
/// from the screen's state. It takes its colour from `Theme.of(context)` rather
/// than from a passed-in `ColorScheme`, which is what lets it be a plain
/// `StatelessWidget` with no arguments beyond the row itself.
class PlanetInfoRow extends StatelessWidget {
  const PlanetInfoRow(this.label, this.value, {super.key, this.info});

  final String label;
  final String value;

  /// When non-null, an `(i)` bubble is shown after the label carrying this text.
  final String? info;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final labelStyle = TextStyle(
      color: cs.onSurface.withValues(alpha: 0.6),
      fontSize: 12,
      fontWeight: FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: labelStyle),
                ),
                if (info != null)
                  Tooltip(
                    message: info!,
                    triggerMode: TooltipTriggerMode.tap,
                    waitDuration: const Duration(milliseconds: 400),
                    showDuration: const Duration(seconds: 12),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: Icon(
                        Icons.info_outline_rounded,
                        size: 12,
                        color: Colors.amber.shade600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // The value is flexible and the label is not, so a long value (a
          // population against a million-colonist cap, say) ellipsises instead
          // of overflowing the row. Both were natural width once, which meant
          // adding any "12,450 / 1.5M" value broke every card at 430px.
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
