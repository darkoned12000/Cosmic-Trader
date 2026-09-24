import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';

/// Rounded panel card with an optional header row (icon / leading + title +
/// subtitle + trailing) above a set of body [children].
///
/// Consolidates the widely copy-pasted `Card(elevation: 0)` + rounded-16 +
/// padded `Column` header pattern used across screens (ship status, planet,
/// faction rankings, port management, …). All padding/gap tokens route
/// through [UiScale.spacing], so the density setting (Compact/Normal/Cozy)
/// and the global UI-scale canvas transform apply uniformly everywhere the
/// card is used.
class PanelCard extends StatelessWidget {
  const PanelCard({
    super.key,
    this.title,
    this.subtitle,
    this.icon,
    this.leading,
    this.trailing,
    this.color,
    this.onTap,
    this.padding = 16,
    this.children = const [],
  });

  /// Header title (bold `titleMedium`).
  final String? title;

  /// Secondary header line rendered under [title].
  final String? subtitle;

  /// Header icon shown left of [title] in the theme's primary color.
  final IconData? icon;

  /// Custom leading widget; replaces [icon] when provided.
  final Widget? leading;

  /// Trailing widget pinned to the right of the header row.
  final Widget? trailing;

  /// Background color override (defaults to the theme's card color).
  final Color? color;

  /// Makes the card tappable (ripple over the whole surface).
  final VoidCallback? onTap;

  /// Base padding around the body; scaled by the density token.
  final double padding;

  /// Body widgets below the header (or the whole body when no header).
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasHeader =
        leading != null || icon != null || title != null || trailing != null;

    final header = hasHeader
        ? Row(
            children: [
              if (leading != null)
                leading!
              else if (icon != null) ...[
                Icon(icon, color: cs.primary, size: 20),
                const SizedBox(width: 8),
              ],
              if (title != null)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title!,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              else if (trailing != null)
                const Spacer(),
              if (trailing != null) trailing!,
            ],
          )
        : null;

    return Card(
      elevation: 0,
      color: color,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: onTap != null ? Clip.antiAlias : Clip.none,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(UiScale.spacing(padding)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (header != null) ...[
                header,
                if (children.isNotEmpty) SizedBox(height: UiScale.spacing(12)),
              ],
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
