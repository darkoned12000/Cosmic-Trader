import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';

/// Reusable portrait picker, shared by account creation and the post-creation
/// appearance editor.
///
/// Shows one prominent live preview plus a strip of thumbnails for the active
/// presentation. Both are labelled with the portrait's callsign, so a player
/// never has to distinguish options by colour alone.
///
/// Themed entirely from [factionColor] rather than local literals, per the
/// repo's faction-colour contract.
class AvatarGallery extends StatelessWidget {
  const AvatarGallery({
    super.key,
    required this.species,
    required this.selection,
    required this.onChanged,
    this.previewSize = 112,
    this.thumbnailSize = 64,
    this.showPreview = true,
    this.locked = const {},
  });

  /// The player's faction. Species is derived from it, so the gallery
  /// re-scopes when the faction changes.
  final AvatarSpecies species;

  final AvatarSelection selection;
  final ValueChanged<AvatarSelection> onChanged;

  final double previewSize;
  final double thumbnailSize;

  /// Whether to draw the large preview and identity caption.
  ///
  /// `false` in the appearance editor, which already pins its own larger
  /// preview above the tabs. Showing both wasted the tab's height and pushed the
  /// thumbnail strip below the fold.
  final bool showPreview;

  /// Axes a re-roll must leave alone.
  ///
  /// Empty in registration, which has no locks. The appearance editor passes
  /// its lock set here so the tile in the Portrait tab and the editor's own
  /// re-roll button cannot disagree about what a re-roll does.
  final Set<AxisStyleAxis> locked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final accent = factionColor(species.faction);
    final active = _activePresentation();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Pilot Portrait',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: UiScale.spacing(2)),
        Text(
          _flavourLine(species),
          style: theme.textTheme.bodySmall
              ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
        ),
        SizedBox(height: UiScale.spacing(12)),
        _presentationSelector(context, active, accent),
        if (showPreview) ...[
          SizedBox(height: UiScale.spacing(12)),
          _preview(context, active, accent),
        ],
        SizedBox(height: UiScale.spacing(12)),
        _thumbnailStrip(context, active, accent),
      ],
    );
  }

  /// The presentation to show. A saved selection wins; otherwise fall back to
  /// the species default so the gallery never opens on an empty tab.
  AvatarPresentation _activePresentation() {
    final saved = AvatarCatalog.byId(selection.portraitId);
    if (saved != null && saved.species == species) {
      return saved.presentation;
    }
    if (AvatarCatalog.forSpecies(species, presentation: selection.presentation)
        .isNotEmpty) {
      return selection.presentation;
    }
    return AvatarCatalog.defaultFor(species).presentation;
  }

  /// Short art-direction line, taken straight from the faction lore rather
  /// than invented here so the two never drift.
  String _flavourLine(AvatarSpecies species) {
    final faction = species.faction;
    // `Faction.forClass` throws for pirate (no Faction const exists for it), so
    // guard rather than rely on pirates never being selectable.
    if (faction == FactionClass.pirate) {
      return 'Free traders of the open galaxy';
    }
    return Faction.forClass(faction).appearance;
  }

  Widget _presentationSelector(
    BuildContext context,
    AvatarPresentation active,
    Color accent,
  ) {
    return Row(
      children: [
        for (final p in AvatarPresentation.values)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: p == AvatarPresentation.values.last
                    ? 0
                    : UiScale.spacing(6),
              ),
              child: _SegmentButton(
                label: p.label,
                selected: p == active,
                accent: accent,
                onTap: () => onChanged(
                  selection
                      .copyWith(
                        species: species,
                        presentation: p,
                        // Default *within the chosen presentation*, so the active
                        // tab and the portrait on screen never disagree.
                        portraitId:
                            AvatarCatalog.defaultFor(species, presentation: p)
                                .id,
                        source: AvatarSource.preset,
                      )
                      .forFaction(species.faction),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _preview(
    BuildContext context,
    AvatarPresentation active,
    Color accent,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final portrait = selection.portrait;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AvatarCanvas(
          selection: selection,
          size: previewSize,
        ),
        SizedBox(width: UiScale.spacing(14)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                portrait.label,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: UiScale.spacing(2)),
              Text(
                '${portrait.species.label} · ${portrait.presentation.label}'
                ' presentation',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
              ),
              SizedBox(height: UiScale.spacing(6)),
              Text(
                portrait.isDefault ? 'Recommended' : 'Custom pick',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: portrait.isDefault
                      ? accent
                      : cs.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _thumbnailStrip(
    BuildContext context,
    AvatarPresentation active,
    Color accent,
  ) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options = AvatarCatalog.forSpecies(species, presentation: active);
    final selectedId = selection.portraitId;
    final captionStyle = theme.textTheme.labelSmall?.copyWith(fontSize: 10) ??
        const TextStyle(fontSize: 10);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // SizedBox rather than shrinkWrap: a horizontal strip keeps the 400px
        // registration column usable without a nested vertical scroll view.
        //
        // The height is *measured*, not guessed. A previous version used
        // `thumbnailSize + spacing(30)`, which silently overflowed by a pixel
        // whenever the density scale or the thumbnail size fell outside what the
        // magic number assumed — which is exactly what happened when the editor
        // started passing a smaller strip.
        SizedBox(
          height: thumbnailSize +
              UiScale.spacing(4) +
              _captionHeight(context, captionStyle),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            // Portraits, then the single Reroll action. Reroll also draws a new
            // catalogue entry, so it subsumes the old Random action rather than
            // sitting beside it.
            itemCount: options.length + 1,
            separatorBuilder: (_, __) => SizedBox(width: UiScale.spacing(8)),
            itemBuilder: (context, index) {
              if (index == options.length) {
                return _ActionTile(
                  icon: Icons.casino_rounded,
                  caption: 'Reroll',
                  tooltip: locked.isEmpty
                      ? 'Randomise outfit, hair, eyes, markings, expression and tone'
                      : 'Randomise every unlocked axis. '
                          '${locked.length} locked, kept.',
                  accent: accent,
                  size: thumbnailSize,
                  onTap: () {
                    final rng = math.Random();
                    // One roll produces both the portrait and the style, so the
                    // two can never disagree about what "this pilot" looks like.
                    // Rolls from the *current* style so `locked` has something to
                    // hold on to; with no locks this is indistinguishable from
                    // starting fresh.
                    onChanged(selection
                        .copyWith(
                          species: species,
                          presentation: active,
                          source: AvatarSource.preset,
                          style: selection.effectiveStyle
                              .rerolled(rng.nextInt, locked: locked),
                        )
                        .randomized(
                          nextInt: rng.nextInt,
                          randomizeStyle: false,
                          newPortrait: true,
                        ));
                  },
                );
              }
              final portrait = options[index];
              final isSelected = portrait.id == selectedId;
              return _Thumbnail(
                portrait: portrait,
                size: thumbnailSize,
                selected: isSelected,
                accent: accent,
                // Visible text label, not just a colour cue. `fontSize: 10`
                // matches the caption the strip height was measured against.
                labelStyle: captionStyle.copyWith(
                  color:
                      isSelected ? accent : cs.onSurface.withValues(alpha: 0.7),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                ),
                onTap: () => onChanged(selection.copyWith(
                  species: species,
                  presentation: active,
                  portraitId: portrait.id,
                  source: AvatarSource.preset,
                  // A preset is a template: tapping one adopts the look its
                  // tile is actually showing. Carrying a previous Reroll's
                  // style over meant the portrait you picked could hand you a
                  // visibly different face, which read as a bug.
                  clearStyle: true,
                )),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Height of one caption line at [style], including the text scale.
///
/// Measured rather than assumed, so the thumbnail strip is exactly as tall as
/// its contents at any UI density or accessibility text scale.
double _captionHeight(BuildContext context, TextStyle? style) {
  final painter = TextPainter(
    text: TextSpan(text: 'Ag', style: style),
    maxLines: 1,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

class _SegmentButton extends StatelessWidget {
  const _SegmentButton({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.symmetric(vertical: UiScale.spacing(8)),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // Solid-ish fill: an 0.18 tint was nearly invisible against the
            // near-black theme, leaving the 1.5px border as the only cue.
            color: selected
                ? Color.lerp(accent, cs.surface, 0.22)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? accent : cs.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.portrait,
    required this.size,
    required this.selected,
    required this.accent,
    required this.labelStyle,
    required this.onTap,
  });

  final AvatarPortrait portrait;
  final double size;
  final bool selected;
  final Color accent;
  final TextStyle? labelStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      label: portrait.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: size + UiScale.spacing(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarCanvas(
                // Deliberately the catalogue's seeded look, not the player's
                // rolled style: applying one style across the strip would make
                // all three candidates look near-identical, and the strip's job
                // is telling the three portraits apart.
                selection: AvatarSelection(
                  species: portrait.species,
                  presentation: portrait.presentation,
                  portraitId: portrait.id,
                ),
                size: size,
                showRing: selected,
                selected: selected,
                // The visible caption below already names it; don't announce
                // twice.
                semanticLabel: '',
              ),
              SizedBox(height: UiScale.spacing(4)),
              Text(
                portrait.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: labelStyle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.caption,
    required this.tooltip,
    required this.accent,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final String caption;

  /// Explains what the action does, since neither Random nor Reroll is obvious
  /// from the icon alone.
  final String tooltip;

  final Color accent;

  /// Matches the portrait tiles beside it. This used to be hard-coded to 64,
  /// which silently overflowed the strip at any other size — harmless at the
  /// default and a real bug the moment a caller passed something smaller.
  final double size;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: size + UiScale.spacing(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    border: Border.all(color: accent.withValues(alpha: 0.35)),
                  ),
                  child: Icon(icon,
                      size: (size * 0.375).clamp(16.0, 24.0), color: accent),
                ),
                SizedBox(height: UiScale.spacing(4)),
                Text(
                  caption,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
