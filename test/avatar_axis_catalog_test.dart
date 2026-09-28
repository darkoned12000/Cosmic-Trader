import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_axis_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';

/// The editor's axis metadata.
///
/// The failure this file exists to prevent: option lists were built by looping
/// to `AvatarStyle.toneCount` (6) for axes whose real source has 3 entries —
/// the skin list has 6, but every dye list and the garment list have 3. That
/// threw a `RangeError` while *building* the axis row, so the Face tab rendered
/// a single row and then nothing. Nothing about a widget test notices that the
/// tab is half-empty, and the crash only surfaced by screenshotting the editor.
void main() {
  // The expected count for each axis, taken from whatever actually supplies its
  // colours rather than from a single shared constant.
  int expectedCount(
    AxisStyleAxis axis,
    AvatarSpecies species,
    AvatarPresentation presentation,
  ) {
    switch (axis) {
      case AxisStyleAxis.tone:
        return AvatarStyle.toneCount;
      case AxisStyleAxis.eyes:
      case AxisStyleAxis.expression:
      case AxisStyleAxis.hair:
      case AxisStyleAxis.horns:
      case AxisStyleAxis.outfit:
      case AxisStyleAxis.gear:
        return AvatarStyle.gearCount;
      case AxisStyleAxis.eyeColor:
        return AvatarPalette.eyeColours(species).length;
      case AxisStyleAxis.hairColor:
        return AvatarPalette.hairColours(species).length;
      case AxisStyleAxis.markingColor:
        return AvatarPalette.markingColours(species).length;
      case AxisStyleAxis.trimColor:
        return AvatarPalette.trimColours(species).length;
      case AxisStyleAxis.outfitTone:
        return AvatarCatalog.variantCount;
      case AxisStyleAxis.backdrop:
        return AvatarStyle.backdropCount;
      case AxisStyleAxis.markings:
        // 0 = unmarked, plus the two marked patterns.
        return 3;
    }
  }

  /// Nullable slots get one extra "auto" entry, whose value is null.
  bool isNullableSlot(AxisStyleAxis axis) => const {
        AxisStyleAxis.eyeColor,
        AxisStyleAxis.hairColor,
        AxisStyleAxis.markingColor,
        AxisStyleAxis.trimColor,
        AxisStyleAxis.gear,
        AxisStyleAxis.backdrop,
      }.contains(axis);

  /// Mirrors [AxisSpec.applies] for an axis id, so the tests can skip the axes a
  /// species does not have.
  bool appliesTo(
    AxisStyleAxis axis,
    AvatarSpecies species,
    AvatarPresentation presentation,
  ) =>
      AvatarAxisCatalog.specFor(axis).applies(species, presentation);

  test('every axis offers exactly the options its source can supply', () {
    for (final species in AvatarSpecies.values) {
      for (final presentation in AvatarPresentation.values) {
        for (final axis in AxisStyleAxis.values) {
          final options =
              AvatarAxisCatalog.optionsFor(axis, species, presentation);
          if (!appliesTo(axis, species, presentation)) {
            // An inapplicable axis must report no options, not throw and not
            // offer a control that cannot do anything.
            expect(options, isEmpty,
                reason: '$species $axis does not apply but still offers '
                    '${options.length} options');
            continue;
          }
          final auto = isNullableSlot(axis) ? 1 : 0;
          expect(
            options.length,
            expectedCount(axis, species, presentation) + auto,
            reason: '$species/$presentation $axis: ${options.length} options. '
                'An axis must never generate more options than its colour list '
                'has entries — indexing past the end throws during build and '
                'takes the tab with it.',
          );
        }
      }
    }
  });

  test('option values are contiguous, in range, and never duplicated', () {
    for (final species in AvatarSpecies.values) {
      for (final axis in AxisStyleAxis.values) {
        if (!appliesTo(axis, species, AvatarPresentation.neutral)) continue;
        final options = AvatarAxisCatalog.optionsFor(
          axis,
          species,
          AvatarPresentation.neutral,
        );
        final values = options.map((o) => o.value).toList();
        // Exactly one "auto" entry, and it is null, when the slot is nullable.
        if (isNullableSlot(axis)) {
          expect(values.where((v) => v == null).length, 1,
              reason: '$axis must offer exactly one auto entry');
        } else {
          expect(values.contains(null), isFalse,
              reason: '$axis is not a nullable slot and must not offer null');
        }
        final concrete = values.whereType<int>().toSet();
        expect(concrete.length, concrete.length, reason: 'duplicate value');
        // Contiguous from 0, so the set is a valid index range for the painter.
        final sorted = concrete.toList()..sort();
        for (var i = 0; i < sorted.length; i++) {
          expect(sorted[i], i,
              reason: '$axis values must be contiguous from 0');
        }
      }
    }
  });

  test('every option has a label, and colour options have a swatch', () {
    // The repo's accessibility rule: nothing may be identified by colour alone,
    // and nothing may be an unnamed integer.
    for (final species in AvatarSpecies.values) {
      for (final presentation in AvatarPresentation.values) {
        for (final axis in AxisStyleAxis.values) {
          if (!appliesTo(axis, species, presentation)) continue;
          for (final option
              in AvatarAxisCatalog.optionsFor(axis, species, presentation)) {
            expect(option.label.trim(), isNotEmpty,
                reason: '$species $axis has an unlabelled option');
            final wantsSwatch = const {
              AxisStyleAxis.tone,
              AxisStyleAxis.eyeColor,
              AxisStyleAxis.hairColor,
              AxisStyleAxis.markingColor,
              AxisStyleAxis.trimColor,
              AxisStyleAxis.outfitTone,
            }.contains(axis);
            if (wantsSwatch && !option.isAuto) {
              expect(option.swatch, isNotNull,
                  reason: '${option.label} is a colour option with no swatch');
            }
          }
        }
      }
    }
  });

  test('inapplicable axes are filtered out rather than shown inert', () {
    // `horns` is Duran-only and the Vinari are unmarked by lore. A control that
    // silently does nothing is worse than no control.
    for (final tab in AvatarTab.values) {
      for (final species in AvatarSpecies.values) {
        for (final presentation in AvatarPresentation.values) {
          final specs = AvatarAxisCatalog.axesFor(tab, species, presentation)
              .where((s) => s.applies(species, presentation))
              .toList();
          if (tab == AvatarTab.portrait) {
            expect(specs, isEmpty, reason: 'Portrait is not an axis tab');
            continue;
          }
          if (species == AvatarSpecies.terran) {
            expect(
                specs.map((s) => s.axis), isNot(contains(AxisStyleAxis.horns)),
                reason: 'horns must be hidden for non-Duran');
          }
          if (species == AvatarSpecies.vinari) {
            expect(
                specs.map((s) => s.axis),
                isNot(
                    anyOf(AxisStyleAxis.markings, AxisStyleAxis.markingColor)),
                reason: 'the Vinari are unmarked by lore');
          }
        }
      }
    }
  });

  test('every axis in the catalogue is reachable from some tab', () {
    final reachable = <AxisStyleAxis>{};
    for (final tab in AvatarTab.values) {
      for (final species in AvatarSpecies.values) {
        reachable.addAll(
          AvatarAxisCatalog.axesFor(tab, species, AvatarPresentation.male)
              .map((s) => s.axis),
        );
      }
    }
    for (final axis in AxisStyleAxis.values) {
      expect(reachable, contains(axis),
          reason: '$axis exists but no tab offers it — it is unreachable');
    }
  });

  test('writing an option and reading it back is a round trip', () {
    // A mis-wired `write` (the wrong axis, or a value that does not stick) would
    // show up as a chip that appears selected but changes nothing.
    for (final species in AvatarSpecies.values) {
      final spec = AvatarAxisCatalog.axesFor(
        AvatarTab.outfit,
        species,
        AvatarPresentation.neutral,
      ).first;
      final base = AvatarStyle.neutral;
      for (final option in AvatarAxisCatalog.optionsFor(
          spec.axis, species, AvatarPresentation.neutral)) {
        if (option.value == null) continue;
        final written = spec.write(base, option.value);
        expect(spec.read(written), option.value,
            reason: '${spec.label} "${option.label}" did not stick');
      }
    }
  });

  test('reset restores the seed value for every axis', () {
    final portraits = [
      for (final species in AvatarSpecies.values)
        ...AvatarCatalog.forSpecies(species),
    ];
    // A style that differs from the seed on every axis, so a reset that is a
    // no-op cannot pass.
    for (final portrait in portraits) {
      final seed = portrait.seededStyle.sanitized();
      final dirty = AvatarStyle(
        tone: (seed.tone + 1) % AvatarStyle.toneCount,
        outfit: (seed.outfit + 1) % AvatarCatalog.variantCount,
        outfitTone: (seed.outfitTone + 1) % AvatarCatalog.variantCount,
        hair: (seed.hair + 1) % AvatarCatalog.variantCount,
        horns: (seed.horns + 1) % AvatarCatalog.variantCount,
        eyes: (seed.eyes + 1) % AvatarCatalog.variantCount,
        markings: 2,
        expression: (seed.expression + 1) % AvatarCatalog.variantCount,
        hairColor: 2,
        eyeColor: 2,
        markingColor: 2,
        trimColor: 2,
        gear: 1,
        backdrop: 1,
      ).sanitized();
      for (final tab in AvatarTab.values) {
        if (tab == AvatarTab.portrait) continue;
        for (final spec in AvatarAxisCatalog.axesFor(
          tab,
          portrait.species,
          portrait.presentation,
        )) {
          final reset = spec.write(dirty, spec.read(seed));
          expect(spec.read(reset), spec.read(seed),
              reason: '${portrait.id}: ${spec.label} did not reset to its seed '
                  'value');
        }
      }
    }
  });
}
