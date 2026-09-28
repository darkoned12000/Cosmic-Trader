import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_portrait_painter.dart';

/// Renders a pilot portrait at a fixed size.
///
/// The widget hides *how* a portrait is produced. Callers hand it an
/// [AvatarSelection] and get back a clipped, accessible portrait; nothing
/// outside this file branches on [AvatarSource] or on whether the artwork is an
/// asset or procedural. When real portrait assets land, this is the single
/// place that learns to load them.
///
/// Resolution is total — an unknown portrait ID, or a custom upload that has
/// not been implemented/saved yet, degrades to the faction's default portrait
/// rather than rendering a broken-image box.
class AvatarCanvas extends StatelessWidget {
  const AvatarCanvas({
    super.key,
    required this.selection,
    this.size = 96,
    this.showRing = true,
    this.selected = false,
    this.semanticLabel,
  });

  final AvatarSelection selection;

  /// Edge length of the square box; the portrait itself is a circle.
  final double size;

  /// Draws a faction-coloured ring. Kept as a thin border rather than a tint so
  /// it identifies the faction without washing out the artwork.
  final bool showRing;

  /// Draws the painter's inner halo behind the head. Used by the gallery to mark
  /// the chosen portrait; distinct from [showRing]'s outer border.
  final bool selected;

  /// Overrides the spoken label. Defaults to the portrait's callsign.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final portrait = _resolve();
    final accent = factionColor(portrait.species.faction);
    final label = semanticLabel ?? '${portrait.label} portrait';

    return Semantics(
      image: true,
      label: label,
      child: SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: showRing
                ? Border.all(
                    color: accent.withValues(alpha: 0.55),
                    width: size >= 64 ? 2 : 1.5,
                  )
                : null,
          ),
          child: ClipOval(
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size.square(size),
                painter: AvatarPortraitPainter(
                  portrait: portrait,
                  // Only pass a style when the player has chosen one, so an
                  // un-customised portrait falls back to the seeded look.
                  style: selection.style,
                  selected: selected,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Never null and never throws: an unusable selection falls back to the
  /// species default so a pilot always has a face.
  AvatarPortrait _resolve() {
    final byId = AvatarCatalog.byId(selection.portraitId);
    if (byId != null && byId.species == selection.species) return byId;

    if (selection.source == AvatarSource.custom) {
      // Custom uploads (design doc §7) are not implemented yet, and a saved
      // custom file may be missing on a new device. Either way the selected
      // preset stays valid as a fallback, so use it rather than showing a hole.
      debugPrint(
        '[AvatarCanvas] Custom avatar "${selection.customFile}" unavailable '
        '— falling back to preset ${selection.portraitId}',
      );
    }
    return AvatarCatalog.defaultFor(selection.species);
  }
}
