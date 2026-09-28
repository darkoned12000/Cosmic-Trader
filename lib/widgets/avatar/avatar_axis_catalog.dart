import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';

/// One selectable value on an axis.
///
/// [value] is `null` for the colour and gear slots, where `null` means "keep
/// the value the shape implied" — see the null-means-legacy rule on
/// [AvatarStyle].
@immutable
class AxisOption {
  const AxisOption({required this.value, required this.label, this.swatch});

  final int? value;

  /// Visible text. Never rely on [swatch] alone — the repo's accessibility rule
  /// is that no option may be distinguished by colour alone.
  final String label;

  /// Optional colour chip. Present on every colour axis; absent on shape axes,
  /// where the silhouette is the identifier.
  final Color? swatch;

  /// `true` for the auto/default entry on a nullable slot, which renders the
  /// legacy coupled value rather than any particular colour.
  bool get isAuto => value == null;
}

/// A group of related axes shown on one tab.
///
/// Text-only labels, deliberately. With an icon stacked above each label, six
/// tabs overflowed a 430px phone and two of them were simply not visible — with
/// no affordance that the strip scrolled, which read as "there are only four
/// tabs". Dropping the icons fits all six and hands the reclaimed height to the
/// axis list.
enum AvatarTab {
  portrait('Portrait'),
  face('Face'),
  hair('Hair'),
  gear('Gear'),
  outfit('Outfit'),
  backdrop('Backdrop');

  const AvatarTab(this.label);

  final String label;
}

/// One editable axis: how to read it, how to write it, and what its options
/// are called.
///
/// Declared as data rather than hand-built per axis so the designer widget stays
/// about layout, and so adding an axis is a single entry here instead of a new
/// block of UI.
@immutable
class AxisSpec {
  const AxisSpec({
    required this.axis,
    required this.label,
    required this.read,
    required this.write,
    this.applies = _anySpecies,
    this.resetValue,
  });

  /// Identifies the axis. Used for the "modified" marker and for per-axis reset.
  final AxisStyleAxis axis;

  final String label;

  final int? Function(AvatarStyle style) read;

  final AvatarStyle Function(AvatarStyle style, int? value) write;

  /// Whether the axis does anything for this species.
  ///
  /// Needed because some axes are inert for part of the gallery: `horns` is
  /// Duran-only, and the Vinari are unmarked by lore. Offering a control that
  /// silently does nothing is worse than not offering it, because the player
  /// reasonably assumes they changed something.
  final bool Function(AvatarSpecies species, AvatarPresentation presentation)
      applies;

  /// The value that means "as the catalogue seed has it".
  ///
  /// `null` on a nullable slot is the legacy coupled value. Left null on the
  /// shape axes, whose reset is handled by the caller using the seed directly —
  /// there is nothing nullable to restore.
  final int? Function(AvatarStyle seed)? resetValue;

  static bool _anySpecies(
    AvatarSpecies s,
    AvatarPresentation p,
  ) =>
      true;
}

/// Every axis, grouped into tabs, with human labels for every value.
///
/// The one rule this file exists to enforce: **no axis is a row of integers.**
/// A player choosing "Angular" is making a decision; a player choosing "2" is
/// guessing.
class AvatarAxisCatalog {
  const AvatarAxisCatalog._();

  /// The Vinari are luminous rather than painted, so markings do not apply.
  static bool _notVinari(AvatarSpecies s, AvatarPresentation p) =>
      s != AvatarSpecies.vinari;

  /// Only the Duran grow horns. Every other species ignores the axis, so the
  /// control is hidden rather than shown inert.
  static bool _duranOnly(AvatarSpecies s, AvatarPresentation p) =>
      s == AvatarSpecies.duran;

  // ── Option label tables ─────────────────────────────────────────
  //
  // Hair is the awkward one: the Terran shapes are chosen per *presentation*
  // inside the painter, so a single label set would be wrong for two thirds of
  // the Terran gallery. The Vinari have no hair either — theirs is a luminous
  // drift.

  static const Map<AvatarSpecies, List<String>> _hairLabels = {
    AvatarSpecies.duran: ['Low ridge', 'Swept crest', 'Spike crown'],
    // The Vinari `hair` axis is a silhouette axis, not a surface one — the three
    // forms are the "tendril fall" and "bioluminescent frill" from the design
    // doc's layer catalogue, because the species had no way to vary its outline
    // at all before this.
    AvatarSpecies.vinari: ['Crown of light', 'Tendril fall', 'Frill fan'],
    AvatarSpecies.terran: ['Swept back', 'Tall crest', 'Forward fin'],
  };

  static const Map<AvatarPresentation, List<String>> _terranHairLabels = {
    AvatarPresentation.male: ['Swept back', 'Tall crest', 'Forward fin'],
    AvatarPresentation.female: ['Long fall', 'Centre part', 'Shoulder sweep'],
    AvatarPresentation.neutral: ['Close crop', 'Shaved band', 'Short spikes'],
  };

  static const Map<AvatarSpecies, List<String>> _outfitLabels = {
    AvatarSpecies.duran: ['Banded plate', 'Heavy pauldron', 'Scale mail'],
    AvatarSpecies.vinari: ['Plain shroud', 'Layered mantle', 'Halo collar'],
    AvatarSpecies.terran: ['Flight suit', 'Merchant coat', 'Cross harness'],
  };

  static const Map<AvatarSpecies, List<String>> _markingLabels = {
    AvatarSpecies.duran: ['None', 'Cheek stripes', 'Ritual scar'],
    AvatarSpecies.terran: ['None', 'Freckles', 'Scar'],
  };

  // ── Tabs ────────────────────────────────────────────────────────

  static List<AxisSpec> axesFor(
    AvatarTab tab,
    AvatarSpecies species,
    AvatarPresentation presentation,
  ) {
    switch (tab) {
      case AvatarTab.face:
        return [
          tone,
          eyes,
          eyeColor,
          markings,
          markingColor,
          expression,
        ];
      case AvatarTab.hair:
        return [hair, hairColor, horns];
      case AvatarTab.gear:
        return [gear];
      case AvatarTab.outfit:
        return [outfit, outfitTone, trimColor];
      case AvatarTab.backdrop:
        return [backdrop];
      case AvatarTab.portrait:
        // Not an axis — the seed and the presentation are handled by the
        // gallery, which this tab embeds.
        return const [];
    }
  }

  /// The spec for an axis id, for callers that hold an id rather than going via
  /// a tab.
  static AxisSpec specFor(AxisStyleAxis axis) => switch (axis) {
        AxisStyleAxis.tone => tone,
        AxisStyleAxis.eyes => eyes,
        AxisStyleAxis.eyeColor => eyeColor,
        AxisStyleAxis.markings => markings,
        AxisStyleAxis.markingColor => markingColor,
        AxisStyleAxis.expression => expression,
        AxisStyleAxis.hair => hair,
        AxisStyleAxis.hairColor => hairColor,
        AxisStyleAxis.horns => horns,
        AxisStyleAxis.gear => gear,
        AxisStyleAxis.outfit => outfit,
        AxisStyleAxis.outfitTone => outfitTone,
        AxisStyleAxis.trimColor => trimColor,
        AxisStyleAxis.backdrop => backdrop,
      };

  /// Resolves an axis's options for the portrait it is being shown for.
  ///
  /// Per-species and per-presentation, because the palette lists and the hair
  /// silhouettes both vary.
  static List<AxisOption> optionsFor(
    AxisStyleAxis axis,
    AvatarSpecies species,
    AvatarPresentation presentation,
  ) {
    // An axis the species does not have offers no options. `horns` is
    // Duran-only and the Vinari are unmarked by lore, so naming a pattern or a
    // horn for them would be inventing lore — and offering a control that
    // cannot change anything is worse than offering none.
    if (!specFor(axis).applies(species, presentation)) return const [];

    switch (axis) {
      case AxisStyleAxis.tone:
        return [
          for (var i = 0; i < AvatarStyle.toneCount; i++)
            AxisOption(
              value: i,
              label: 'Tone ${i + 1}',
              swatch: AvatarPalette.skin(species, i),
            ),
        ];

      case AxisStyleAxis.eyes:
        return const [
          AxisOption(value: 0, label: 'Round'),
          AxisOption(value: 1, label: 'Narrow'),
          AxisOption(value: 2, label: 'Angular'),
        ];

      case AxisStyleAxis.eyeColor:
        final dyes = AvatarPalette.eyeColours(species);
        return [
          const AxisOption(value: null, label: 'Matches shape'),
          for (var i = 0; i < dyes.length; i++)
            AxisOption(
              value: i,
              label: 'Iris ${i + 1}',
              swatch: dyes[i],
            ),
        ];

      case AxisStyleAxis.markings:
        // `_applies` above already guaranteed the Vinari never reach here, so
        // the lookup is safe.
        final labels = _markingLabels[species]!;
        return [
          for (var i = 0; i < labels.length; i++)
            AxisOption(
              value: i,
              label: labels[i],
              swatch:
                  i == 0 ? null : AvatarPalette.markingPigment(species, i, 0),
            ),
        ];

      case AxisStyleAxis.markingColor:
        final dyes = AvatarPalette.markingColours(species);
        return [
          const AxisOption(value: null, label: 'Matches pattern'),
          for (var i = 0; i < dyes.length; i++)
            AxisOption(
              value: i,
              label: 'Pigment ${i + 1}',
              swatch: dyes[i],
            ),
        ];

      case AxisStyleAxis.expression:
        return const [
          AxisOption(value: 0, label: 'Neutral'),
          AxisOption(value: 1, label: 'Stern'),
          AxisOption(value: 2, label: 'Amused'),
        ];

      case AxisStyleAxis.hair:
        final labels = species == AvatarSpecies.terran
            ? _terranHairLabels[presentation]!
            : _hairLabels[species]!;
        return [
          for (var i = 0; i < labels.length; i++)
            AxisOption(value: i, label: labels[i]),
        ];

      case AxisStyleAxis.hairColor:
        final dyes = AvatarPalette.hairColours(species);
        return [
          const AxisOption(value: null, label: 'Matches shape'),
          for (var i = 0; i < dyes.length; i++)
            AxisOption(
              value: i,
              label: 'Shade ${i + 1}',
              swatch: dyes[i],
            ),
        ];

      case AxisStyleAxis.horns:
        return const [
          AxisOption(value: 0, label: 'Battle horns'),
          AxisOption(value: 1, label: 'Crown spikes'),
          AxisOption(value: 2, label: 'Short barbel'),
        ];

      case AxisStyleAxis.gear:
        return const [
          AxisOption(value: null, label: 'Auto'),
          AxisOption(value: 0, label: 'None'),
          AxisOption(value: 1, label: 'Headset'),
          AxisOption(value: 2, label: 'Goggles'),
        ];

      case AxisStyleAxis.outfit:
        return [
          for (var i = 0; i < _outfitLabels[species]!.length; i++)
            AxisOption(value: i, label: _outfitLabels[species]![i]),
        ];

      case AxisStyleAxis.outfitTone:
        // `outfitTone` indexes the garment colour list, which has
        // `variantCount` entries — not `toneCount`. Reading it as the skin-tone
        // count threw a RangeError and took the whole editor down.
        //
        // No "auto" entry: unlike the dye slots this is a plain `int` on
        // AvatarStyle, so there is no coupled value to fall back to and an Auto
        // option would be a button that silently does nothing.
        return [
          for (var i = 0; i < AvatarCatalog.variantCount; i++)
            AxisOption(
              value: i,
              label: 'Garment ${i + 1}',
              swatch: AvatarPalette.outfit(species, i, presentation),
            ),
        ];

      case AxisStyleAxis.trimColor:
        final dyes = AvatarPalette.trimColours(species);
        return [
          const AxisOption(value: null, label: 'Auto'),
          for (var i = 0; i < dyes.length; i++)
            AxisOption(
              value: i,
              label: 'Trim ${i + 1}',
              swatch: dyes[i],
            ),
        ];

      case AxisStyleAxis.backdrop:
        return [
          const AxisOption(value: null, label: 'Auto'),
          for (var i = 0; i < AvatarStyle.backdropCount; i++)
            AxisOption(value: i, label: backdropLabel(species, i)),
        ];
    }
  }

  /// Human names for the backdrops, per species.
  static String backdropLabel(AvatarSpecies species, int index) {
    switch (species) {
      case AvatarSpecies.duran:
        return const ['Forge glow', 'Ember field', 'Void'][index];
      case AvatarSpecies.vinari:
        return const ['Aurora', 'Nebula', 'Deep drift'][index];
      case AvatarSpecies.terran:
        return const ['Hangar', 'Starfield', 'Viewport'][index];
    }
  }

  // ── The axes ────────────────────────────────────────────────────

  static final AxisSpec tone = AxisSpec(
    axis: AxisStyleAxis.tone,
    label: 'Skin tone',
    read: (s) => s.tone,
    write: (s, v) => v == null ? s : s.copyWith(tone: v),
  );

  static final AxisSpec eyes = AxisSpec(
    axis: AxisStyleAxis.eyes,
    label: 'Eyes',
    read: (s) => s.eyes,
    write: (s, v) => v == null ? s : s.copyWith(eyes: v),
  );

  static final AxisSpec eyeColor = AxisSpec(
    axis: AxisStyleAxis.eyeColor,
    label: 'Iris colour',
    read: (s) => s.eyeColor,
    write: (s, v) =>
        v == null ? s.copyWith(clearEyeColor: true) : s.copyWith(eyeColor: v),
    resetValue: (seed) => seed.eyeColor,
  );

  static final AxisSpec markings = AxisSpec(
    axis: AxisStyleAxis.markings,
    label: 'Markings',
    read: (s) => s.markings,
    write: (s, v) => v == null ? s : s.copyWith(markings: v),
    applies: _notVinari,
  );

  static final AxisSpec markingColor = AxisSpec(
    axis: AxisStyleAxis.markingColor,
    label: 'Pigment',
    read: (s) => s.markingColor,
    write: (s, v) => v == null
        ? s.copyWith(clearMarkingColor: true)
        : s.copyWith(markingColor: v),
    applies: _notVinari,
  );

  static final AxisSpec expression = AxisSpec(
    axis: AxisStyleAxis.expression,
    label: 'Expression',
    read: (s) => s.expression,
    write: (s, v) => v == null ? s : s.copyWith(expression: v),
  );

  static final AxisSpec hair = AxisSpec(
    axis: AxisStyleAxis.hair,
    label: 'Hair',
    read: (s) => s.hair,
    write: (s, v) => v == null ? s : s.copyWith(hair: v),
  );

  static final AxisSpec hairColor = AxisSpec(
    axis: AxisStyleAxis.hairColor,
    label: 'Hair colour',
    read: (s) => s.hairColor,
    write: (s, v) =>
        v == null ? s.copyWith(clearHairColor: true) : s.copyWith(hairColor: v),
    resetValue: (seed) => seed.hairColor,
  );

  static final AxisSpec horns = AxisSpec(
    axis: AxisStyleAxis.horns,
    label: 'Horns',
    read: (s) => s.horns,
    write: (s, v) => v == null ? s : s.copyWith(horns: v),
    applies: _duranOnly,
  );

  static final AxisSpec gear = AxisSpec(
    axis: AxisStyleAxis.gear,
    label: 'Headgear',
    read: (s) => s.gear,
    write: (s, v) =>
        v == null ? s.copyWith(clearGear: true) : s.copyWith(gear: v),
    resetValue: (seed) => seed.gear,
  );

  static final AxisSpec outfit = AxisSpec(
    axis: AxisStyleAxis.outfit,
    label: 'Garment',
    read: (s) => s.outfit,
    write: (s, v) => v == null ? s : s.copyWith(outfit: v),
  );

  static final AxisSpec outfitTone = AxisSpec(
    axis: AxisStyleAxis.outfitTone,
    label: 'Garment colour',
    read: (s) => s.outfitTone,
    write: (s, v) => v == null ? s : s.copyWith(outfitTone: v),
  );

  static final AxisSpec trimColor = AxisSpec(
    axis: AxisStyleAxis.trimColor,
    label: 'Trim colour',
    read: (s) => s.trimColor,
    write: (s, v) =>
        v == null ? s.copyWith(clearTrimColor: true) : s.copyWith(trimColor: v),
    resetValue: (seed) => seed.trimColor,
  );

  static final AxisSpec backdrop = AxisSpec(
    axis: AxisStyleAxis.backdrop,
    label: 'Backdrop',
    read: (s) => s.backdrop,
    write: (s, v) =>
        v == null ? s.copyWith(clearBackdrop: true) : s.copyWith(backdrop: v),
    resetValue: (seed) => seed.backdrop,
  );
}
