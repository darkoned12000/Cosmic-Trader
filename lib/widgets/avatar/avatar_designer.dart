import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_axis_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_gallery.dart';

/// Tabbed per-axis customisation for a pilot portrait.
///
/// Replaces the flat "gallery + Reroll" editor. Reroll remains, but it is no
/// longer the *only* way to change anything — a player who likes everything
/// about their portrait except their hairstyle no longer has to re-roll their
/// face to change it.
///
/// The design is a preview you cannot lose (it lives in the caller, above this
/// widget, so it stays put across tabs) plus one tab per group of related axes.
/// Every option is a **named** choice, never an integer: choosing "Angular" is
/// a decision, choosing "2" is a guess.
///
/// An axis that does nothing for the current species is hidden rather than
/// shown inert — see [AxisSpec.applies].
class AvatarDesigner extends StatefulWidget {
  const AvatarDesigner({
    super.key,
    required this.species,
    required this.selection,
    required this.onChanged,
  });

  final AvatarSpecies species;
  final AvatarSelection selection;
  final ValueChanged<AvatarSelection> onChanged;

  @override
  State<AvatarDesigner> createState() => _AvatarDesignerState();
}

class _AvatarDesignerState extends State<AvatarDesigner>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: AvatarTab.values.length,
    vsync: this,
  );

  /// Axes the player has settled, so a re-roll leaves them alone.
  ///
  /// Deliberately **not** persisted. A lock describes how someone wants to
  /// re-roll, not what their pilot is; it is spent the moment they Save, and
  /// storing it would add schema for a decision already made. It also resets
  /// whenever the editor is reopened, which is right — a lock is a mode, not a
  /// preference.
  ///
  /// Starts empty on purpose. A surprising number of players should find
  /// Reroll still means "surprise me".
  final Set<AxisStyleAxis> _locked = <AxisStyleAxis>{};

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _toggleLock(AxisStyleAxis axis) {
    setState(() {
      if (!_locked.remove(axis)) _locked.add(axis);
    });
  }

  /// The presentation the current seed belongs to. Needed because the Terran
  /// hair silhouettes are chosen per presentation, so the option labels differ.
  AvatarPresentation get _presentation {
    final saved = AvatarCatalog.byId(widget.selection.portraitId);
    if (saved != null && saved.species == widget.species) {
      return saved.presentation;
    }
    return widget.selection.presentation;
  }

  /// The seed the current style was rolled on top of, which is what "reset this
  /// axis" restores.
  AvatarStyle get _seed => widget.selection.portrait.seededStyle.sanitized();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = factionColor(widget.species.faction);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TabStrip(controller: _tabs, accent: accent),
        SizedBox(height: UiScale.spacing(8)),
        // Expanded rather than a fixed height: the caller decides how much room
        // the designer gets, and each tab scrolls inside it. A hard-coded height
        // fought the pinned-preview layout — it had to be guessed, and it was
        // wrong on short viewports.
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: TabBarView(
              controller: _tabs,
              children: [
                for (final tab in AvatarTab.values)
                  _TabBody(
                    tab: tab,
                    species: widget.species,
                    presentation: _presentation,
                    style: widget.selection.style,
                    seed: _seed,
                    accent: accent,
                    selection: widget.selection,
                    onChanged: widget.onChanged,
                    locked: _locked,
                    onToggleLock: _toggleLock,
                  ),
              ],
            ),
          ),
        ),
        SizedBox(height: UiScale.spacing(10)),
        _RerollBar(
          accent: accent,
          onReroll: _rerollEverything,
          lockedCount: _locked.length,
          onResetAll: widget.selection.style == null
              ? null
              : () => widget.onChanged(
                    widget.selection.copyWith(clearStyle: true),
                  ),
          isAtSeed: widget.selection.style == null,
        ),
      ],
    );
  }

  /// Re-rolls every **unlocked** axis and draws a new catalogue seed, in one
  /// pass, so the portrait and the style can never disagree about what this
  /// pilot looks like — the same reasoning the gallery's Reroll tile uses.
  ///
  /// A new seed is drawn even when axes are locked, and that is fine: a lock
  /// pins an axis to the *player's* value, which the seed does not override.
  void _rerollEverything() {
    final rng = math.Random();
    widget.onChanged(
      widget.selection.randomized(
        nextInt: rng.nextInt,
        randomizeStyle: true,
        newPortrait: true,
        locked: _locked,
      ),
    );
  }
}

/// Horizontal tab strip, scrollable so six tabs fit at any width.
class _TabStrip extends StatelessWidget {
  const _TabStrip({required this.controller, required this.accent});

  final TabController controller;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      // No fixed height here. Pinning the container to 44 while the TabBar
      // sized itself to its own content overflowed by a pixel; letting the
      // TabBar decide is both simpler and correct at any text scale.
      child: TabBar(
        controller: controller,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorColor: accent,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        labelColor: accent,
        // Tighter than the Material default. With the default padding, six tabs
        // overflowed a 430px phone by enough that `Backdrop` sat off-screen with
        // no affordance that the strip scrolled — a tap on it silently did
        // nothing, which reads as a broken control rather than a hidden one.
        labelPadding: const EdgeInsets.symmetric(horizontal: 7),
        // Selected tabs are carried by weight and colour together, never by
        // colour alone.
        labelStyle:
            theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
        unselectedLabelStyle: theme.textTheme.labelMedium
            ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
        tabs: [
          for (final tab in AvatarTab.values) Tab(text: tab.label),
        ],
      ),
    );
  }
}

/// The scrollable body of one tab.
class _TabBody extends StatelessWidget {
  const _TabBody({
    required this.tab,
    required this.species,
    required this.presentation,
    required this.style,
    required this.seed,
    required this.accent,
    required this.selection,
    required this.onChanged,
    required this.locked,
    required this.onToggleLock,
  });

  final AvatarTab tab;
  final AvatarSpecies species;
  final AvatarPresentation presentation;
  final AvatarStyle? style;
  final AvatarStyle seed;
  final Color accent;
  final AvatarSelection selection;
  final ValueChanged<AvatarSelection> onChanged;
  final Set<AxisStyleAxis> locked;
  final ValueChanged<AxisStyleAxis> onToggleLock;

  @override
  Widget build(BuildContext context) {
    // The Portrait tab is not axes — it is the seed and presentation picker,
    // reused from the gallery so both surfaces stay in step.
    if (tab == AvatarTab.portrait) {
      return SingleChildScrollView(
        padding: EdgeInsets.all(UiScale.spacing(10)),
        child: AvatarGallery(
          species: species,
          selection: selection,
          onChanged: onChanged,
          // The editor pins its own larger preview above the tabs, so this tab
          // is only the seed picker.
          showPreview: false,
          thumbnailSize: 56,
          // The gallery's own Reroll tile is a second way to re-roll, so it has
          // to honour the same locks as the button below. Empty for registration,
          // which has no locks.
          locked: locked,
        ),
      );
    }

    final specs = AvatarAxisCatalog.axesFor(tab, species, presentation)
        .where((s) => s.applies(species, presentation))
        .toList();

    // Every axis on this tab was filtered out for this species.
    if (specs.isEmpty) {
      return Center(
        child: Text(
          'Nothing to customise here',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.6),
              ),
        ),
      );
    }

    return ListView(
      padding: EdgeInsets.all(UiScale.spacing(10)),
      children: [
        for (final spec in specs)
          _AxisRow(
            spec: spec,
            species: species,
            presentation: presentation,
            style: (style ?? seed).sanitized(),
            seed: seed,
            accent: accent,
            locked: locked.contains(spec.axis),
            onToggleLock: () => onToggleLock(spec.axis),
            onChanged: (next) => onChanged(selection.copyWith(style: next)),
          ),
      ],
    );
  }
}

/// One axis: a label, its named options as chips, and a reset.
class _AxisRow extends StatelessWidget {
  const _AxisRow({
    required this.spec,
    required this.species,
    required this.presentation,
    required this.style,
    required this.seed,
    required this.accent,
    required this.locked,
    required this.onToggleLock,
    required this.onChanged,
  });

  final AxisSpec spec;
  final AvatarSpecies species;
  final AvatarPresentation presentation;
  final AvatarStyle style;
  final AvatarStyle seed;
  final Color accent;
  final bool locked;
  final VoidCallback onToggleLock;
  final ValueChanged<AvatarStyle> onChanged;

  /// The value this axis holds when it matches the catalogue seed.
  ///
  /// For a nullable slot that is the seed's own value, which is `null` for every
  /// pre-colour-axis save. For a shape axis it is the seed's value too — so
  /// "unchanged" always means "as the preset had it", never "as option 0".
  int? get _defaultValue => spec.read(seed);

  int? get _current => spec.read(style);

  bool get _isModified => _current != _defaultValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final options =
        AvatarAxisCatalog.optionsFor(spec.axis, species, presentation);
    final current = _current;

    return Padding(
      padding: EdgeInsets.only(bottom: UiScale.spacing(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                spec.label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (_isModified) ...[
                SizedBox(width: UiScale.spacing(6)),
                // A dot plus text, not a colour change: the marker has to be
                // legible without relying on the accent.
                Icon(Icons.circle, size: 6, color: accent),
                SizedBox(width: UiScale.spacing(3)),
                Text(
                  'changed',
                  style: theme.textTheme.labelSmall?.copyWith(color: accent),
                ),
              ],
              const Spacer(),
              if (_isModified)
                TextButton.icon(
                  onPressed: () => onChanged(_reset()),
                  icon: const Icon(Icons.restart_alt_rounded, size: 15),
                  label: const Text('Reset'),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        EdgeInsets.symmetric(horizontal: UiScale.spacing(8)),
                  ),
                ),
              // Lock and Reset are independent: a lock governs re-rolling, a
              // reset governs the value. Resetting a locked axis does not unlock
              // it, and locking a modified axis does not hide the marker.
              _LockToggle(
                locked: locked,
                accent: accent,
                onToggle: onToggleLock,
              ),
            ],
          ),
          SizedBox(height: UiScale.spacing(6)),
          Wrap(
            spacing: UiScale.spacing(6),
            runSpacing: UiScale.spacing(6),
            children: [
              for (final option in options)
                _OptionChip(
                  option: option,
                  selected: option.value == current,
                  accent: accent,
                  onTap: () => onChanged(spec.write(style, option.value)),
                ),
            ],
          ),
          // Named value shown as text too, so the choice is never swatch-only.
          if (options.any((o) => o.value == current))
            Padding(
              padding: EdgeInsets.only(top: UiScale.spacing(4)),
              child: Text(
                'Now: ${options.firstWhere((o) => o.value == current).label}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurface.withValues(alpha: 0.55)),
              ),
            ),
        ],
      ),
    );
  }

  /// Returns this axis to the value the catalogue seed gave it.
  ///
  /// Both cases end up calling [AxisSpec.write] with a concrete value: for a
  /// nullable slot the seed value *is* the thing to write (usually `null`, which
  /// restores the legacy coupled colour), and for a shape axis it is the seed's
  /// own index.
  AvatarStyle _reset() => spec.write(style, _defaultValue);
}

/// One named option. A colour option shows a swatch *and* its name.
class _OptionChip extends StatelessWidget {
  const _OptionChip({
    required this.option,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final AxisOption option;
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
      label: option.label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? Color.lerp(accent, cs.surface, 0.24)
                : cs.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (option.swatch != null) ...[
                Container(
                  width: 11,
                  height: 11,
                  decoration: BoxDecoration(
                    color: option.swatch,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ] else if (option.isAuto) ...[
                // "Auto" is not a colour, so it gets a distinct glyph rather
                // than an empty swatch that would read as a rendering fault.
                Icon(Icons.auto_awesome_rounded, size: 12, color: accent),
                const SizedBox(width: 5),
              ],
              Text(
                option.label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color:
                      selected ? accent : cs.onSurface.withValues(alpha: 0.75),
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The per-axis lock.
///
/// A padlock rather than a checkbox, and it carries text in its tooltip and
/// semantics label — the repo rule is that nothing may be identified by a glyph
/// or a colour alone.
class _LockToggle extends StatelessWidget {
  const _LockToggle({
    required this.locked,
    required this.accent,
    required this.onToggle,
  });

  final bool locked;
  final Color accent;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Tooltip(
      message: locked
          ? 'Locked. A re-roll will leave this alone.'
          : 'Lock this so a re-roll leaves it alone',
      child: Semantics(
        button: true,
        toggled: locked,
        label: locked
            ? '${locked ? 'Un' : ''}lock axis'
            : 'Lock this axis against re-rolling',
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(7),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: UiScale.spacing(7),
              vertical: UiScale.spacing(5),
            ),
            decoration: BoxDecoration(
              color: locked
                  ? Color.lerp(accent, cs.surface, 0.26)
                  : cs.surfaceContainerHighest.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(7),
              border: Border.all(
                color: locked ? accent : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Icon(
              locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              size: 15,
              color: locked ? accent : cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ),
      ),
    );
  }
}

/// Reroll plus full reset.
class _RerollBar extends StatelessWidget {
  const _RerollBar({
    required this.accent,
    required this.onReroll,
    required this.lockedCount,
    required this.onResetAll,
    required this.isAtSeed,
  });

  final Color accent;
  final VoidCallback onReroll;
  final int lockedCount;
  final VoidCallback? onResetAll;
  final bool isAtSeed;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Tooltip(
            message: lockedCount == 0
                ? 'Re-roll every axis and draw a new portrait'
                : 'Re-roll the $lockedCount unlocked '
                    '${lockedCount == 1 ? 'axis' : 'axes'} and draw a new '
                    'portrait. $lockedCount locked '
                    '${lockedCount == 1 ? 'axis is' : 'axes are'} kept.',
            child: OutlinedButton.icon(
              onPressed: onReroll,
              icon: const Icon(Icons.casino_rounded, size: 18),
              // Says what it will do, not just what the button is called — with
              // locks active, "Reroll everything" would be a lie. Deliberately
              // short: "Reroll unlocked (3)" wrapped to two lines on a 430px
              // phone and made this row taller than the button beside it. The
              // count lives in the tooltip.
              label: Text(
                lockedCount == 0 ? 'Reroll everything' : 'Reroll unlocked',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        SizedBox(width: UiScale.spacing(10)),
        Expanded(
          child: Tooltip(
            // Says what it does *not* do. It resets every axis to this seed's
            // values; it does not change the seed, because the player may have
            // picked that deliberately on the Portrait tab.
            message: 'Reset every axis to this portrait preset. The portrait '
                'you picked is kept.',
            child: OutlinedButton.icon(
              onPressed: onResetAll,
              icon: const Icon(Icons.settings_backup_restore_rounded, size: 18),
              label: Text(isAtSeed ? 'At preset' : 'Reset all'),
            ),
          ),
        ),
      ],
    );
  }
}
