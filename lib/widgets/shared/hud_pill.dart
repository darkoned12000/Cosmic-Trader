import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';

/// Small rounded badge ("pill") for compact status labels — port class tags,
/// faction tags, stat chips, "sabotaged" warnings.
///
/// Replaces the copy-pasted tiny `Container` + `BorderRadius.circular` +
/// small-text pattern found in trade views, sector panels, faction rankings
/// and dialogs. Padding is density-aware via [UiScale.spacing] (override with
/// [padding] when exact fixed sizes are required).
class HudPill extends StatelessWidget {
  const HudPill({
    super.key,
    required this.text,
    required this.background,
    required this.foreground,
    this.bold = false,
    this.icon,
    this.iconColor,
    this.iconSize,
    this.fontSize = 10,
    this.radius = 4,
    this.padding,
    this.overflow = TextOverflow.clip,
  });

  final String text;
  final Color background;
  final Color foreground;
  final bool bold;

  /// Optional tiny icon rendered before the text.
  final IconData? icon;

  /// Icon color; defaults to [foreground].
  final Color? iconColor;

  /// Icon size; defaults to [fontSize] + 3.
  final double? iconSize;

  final double fontSize;

  /// Corner radius (density-aware badge vs. larger contextual chips).
  final double radius;

  /// Padding override; defaults to density-aware 7×1.
  final EdgeInsetsGeometry? padding;

  final TextOverflow overflow;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ??
          EdgeInsets.symmetric(
            horizontal: UiScale.spacing(7),
            vertical: UiScale.spacing(1),
          ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon,
                size: iconSize ?? fontSize + 3, color: iconColor ?? foreground),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              text,
              overflow: overflow,
              softWrap: false,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
                color: foreground,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
