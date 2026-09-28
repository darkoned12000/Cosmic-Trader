import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_designer.dart';

/// Standalone Save/Cancel wrapper around [AvatarDesigner] for changing a portrait
/// after the account exists.
///
/// The editor is tabbed rather than a flat list because there are 14 axes; a
/// single scrolling column of them is unreadable, and worse, pushes the preview
/// off-screen so you cannot see what you are changing. The preview therefore
/// lives here, above the tabs, and never moves.
///
/// Edits are a local draft: nothing is written to the player until SAVE, and
/// CANCEL discards them. Pops the committed [AvatarSelection] on save and
/// `null` on cancel, so the caller decides when to touch storage.
class AvatarEditorScreen extends StatefulWidget {
  const AvatarEditorScreen({
    super.key,
    required this.faction,
    this.initialSelection,
  });

  final FactionClass faction;

  /// The player's current selection, if any. `null` (a legacy save) starts from
  /// the faction default.
  final AvatarSelection? initialSelection;

  @override
  State<AvatarEditorScreen> createState() => _AvatarEditorScreenState();
}

class _AvatarEditorScreenState extends State<AvatarEditorScreen> {
  late AvatarSelection _draft;

  /// The selection the player started from, resolved the same way as the draft.
  ///
  /// Compared against the *resolved* value rather than the raw
  /// [AvatarEditorScreen.initialSelection], so a legacy account with a null
  /// selection doesn't open the editor already flagged as changed.
  late final AvatarSelection _initial;

  @override
  void initState() {
    super.initState();
    _initial =
        (widget.initialSelection ?? AvatarSelection.defaultFor(widget.faction))
            .forFaction(widget.faction);
    _draft = _initial;
  }

  /// Species is derived from the faction and is not player-selectable, so a
  /// faction change behind this screen (not currently possible) would be
  /// repaired on read rather than surfacing a wrong-species portrait.
  AvatarSpecies get _species => AvatarSpecies.forFaction(widget.faction);

  bool get _isDirty => _draft != _initial;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Change Appearance'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_draft),
            child: const Text('SAVE'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The preview is *pinned*, and the designer scrolls between it and
            // the buttons. Putting all three in one scroll view looked fine and
            // quietly broke the whole point: the preview scrolled off-screen, so
            // changing a hairstyle meant changing it blind. This is the layout
            // the tabbed editor exists to justify.
            //
            // The preview shrinks on short viewports rather than forcing the
            // designer out of the remaining space.
            final previewSize =
                (constraints.maxHeight * 0.21).clamp(84.0, 132.0);
            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        UiScale.spacing(20),
                        UiScale.spacing(12),
                        UiScale.spacing(20),
                        UiScale.spacing(10),
                      ),
                      child: _PreviewHeader(
                        selection: _draft,
                        previewSize: previewSize,
                        isDirty: _isDirty,
                        dirtyLabelStyle: theme.textTheme.bodySmall?.copyWith(
                          color: cs.tertiary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: UiScale.spacing(20),
                        ),
                        child: AvatarDesigner(
                          species: _species,
                          selection: _draft,
                          onChanged: (value) => setState(() => _draft = value),
                        ),
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.all(UiScale.spacing(16)),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: const Text('CANCEL'),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () =>
                                  Navigator.of(context).pop(_draft),
                              child: const Text(
                                'SAVE CHANGES',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The pinned preview plus identity caption.
///
/// Deliberately outside [AvatarDesigner] and outside its scroll view: it must
/// not move when the player changes tabs or scrolls the axis list, because every
/// other control in the editor is meaningless without seeing the effect.
class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({
    required this.selection,
    required this.previewSize,
    required this.isDirty,
    required this.dirtyLabelStyle,
  });

  final AvatarSelection selection;
  final double previewSize;
  final bool isDirty;
  final TextStyle? dirtyLabelStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final portrait = selection.portrait;
    final accent = factionColor(portrait.species.faction);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AvatarCanvas(selection: selection, size: previewSize),
        SizedBox(width: UiScale.spacing(16)),
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
              // Makes it explicit that the editor is a draft — nothing reaches
              // the account until SAVE.
              if (isDirty)
                Text('Unsaved portrait change', style: dirtyLabelStyle)
              else
                Text(
                  portrait.isDefault ? 'Preset look' : 'Custom look',
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
}
