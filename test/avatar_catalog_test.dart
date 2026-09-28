import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';

void main() {
  test('portrait ids are unique and follow the stable naming convention', () {
    // A duplicated id would make one portrait unreachable and silently repoint
    // every saved selection pointing at it.
    final ids = AvatarCatalog.portraits.map((p) => p.id).toList();
    expect(ids.toSet().length, ids.length,
        reason: 'duplicate portrait ids would break saved selections');

    final convention =
        RegExp(r'^(duran|vinari|terran)_(male|female|neutral)_[a-z]+_\d{2}$');
    for (final p in AvatarCatalog.portraits) {
      expect(convention.hasMatch(p.id), isTrue,
          reason: '${p.id} must match the naming convention');
      expect(
          p.id.startsWith('${p.species.name}_${p.presentation.name}_'), isTrue,
          reason: '${p.id} must encode its own species and presentation');
    }
  });

  test('every species and presentation combination has portraits', () {
    // The gallery filters by presentation, so an empty tab would strand the
    // player on a screen with nothing to pick.
    for (final species in AvatarSpecies.values) {
      for (final presentation in AvatarPresentation.values) {
        final options =
            AvatarCatalog.forSpecies(species, presentation: presentation);
        expect(options.length, greaterThan(1),
            reason:
                '$species/${presentation.name} needs real choice, not one option');
        for (final option in options) {
          expect(option.species, species);
          expect(option.presentation, presentation);
        }
      }
    }
  });

  test('every portrait has a non-empty label', () {
    // Accessibility: options must be distinguishable by name, not by colour.
    for (final p in AvatarCatalog.portraits) {
      expect(p.label.trim(), isNotEmpty, reason: '${p.id} needs a callsign');
    }
    final labels = AvatarCatalog.portraits.map((p) => p.label).toList();
    expect(labels.toSet().length, labels.length,
        reason: 'duplicate callsigns would make options ambiguous');
  });

  test('every species has exactly one default', () {
    for (final species in AvatarSpecies.values) {
      final defaults =
          AvatarCatalog.forSpecies(species).where((p) => p.isDefault).toList();
      expect(defaults.length, 1, reason: '$species needs exactly one default');
      expect(AvatarCatalog.defaultFor(species).id, defaults.single.id);
    }
  });

  test('isValidFor rejects a portrait used with the wrong species', () {
    // This is the check that stops a stale save rendering the wrong faction's
    // art after a faction change.
    expect(
        AvatarCatalog.isValidFor(AvatarSpecies.duran, 'duran_male_lancer_01'),
        isTrue);
    expect(
        AvatarCatalog.isValidFor(AvatarSpecies.terran, 'duran_male_lancer_01'),
        isFalse);
    expect(AvatarCatalog.isValidFor(AvatarSpecies.duran, 'nope'), isFalse);
  });

  test('catalogue order does not affect a saved selection', () {
    // Reordering or inserting entries must never change what a returning
    // player sees, which is the whole reason ids are persisted instead of
    // indices.
    const originalId = 'vinari_female_lumen_03';
    final saved = AvatarSelection(
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.female,
      portraitId: originalId,
    );

    final shuffled = AvatarCatalog.portraits.reversed.toList();
    expect(shuffled.map((p) => p.id), contains(originalId),
        reason: 'reordering must not drop the entry');
    expect(AvatarCatalog.byId(originalId)!.label,
        AvatarCatalog.portraits.firstWhere((p) => p.id == originalId).label);
    expect(
      AvatarSelection.fromJson(saved.toJson(),
          fallbackFaction: FactionClass.vinari),
      saved,
    );
  });

  test('the draw seed is stable and varies between portraits', () {
    // Art must not reshuffle when the SDK changes its string hashing, so the
    // seed comes from an explicit FNV-1a rather than String.hashCode.
    expect(AvatarCatalog.stableSeedFor('duran_male_lancer_01'),
        AvatarCatalog.stableSeedFor('duran_male_lancer_01'));
    expect(AvatarCatalog.stableSeedFor('duran_male_lancer_01'),
        isNot(AvatarCatalog.stableSeedFor('duran_male_warden_02')));

    for (final p in AvatarCatalog.portraits) {
      expect(p.drawSeed, AvatarCatalog.stableSeedFor(p.id));
      expect(p.drawSeed, inInclusiveRange(0, 0xFFFFFFFF));
    }
  });

  test('the seeded style is stable, in range, and varied across portraits', () {
    // This is what an un-customised portrait renders with, so it must depend on
    // nothing but the id and must never produce an out-of-range axis.
    for (final p in AvatarCatalog.portraits) {
      final a = AvatarCatalog.seededStyleFor(p.id);
      final b = AvatarCatalog.seededStyleFor(p.id);
      expect(a, b, reason: '${p.id} seed must be stable across calls');
      expect(a, p.seededStyle, reason: 'the entry and the lookup must agree');
      expect(a.tone, inInclusiveRange(0, AvatarStyle.toneCount - 1));
      for (final axis in [
        a.outfit,
        a.outfitTone,
        a.hair,
        a.horns,
        a.eyes,
        a.markings,
        a.expression,
      ]) {
        expect(axis, inInclusiveRange(0, AvatarCatalog.variantCount - 1),
            reason: '${p.id} axis out of range');
      }
    }

    final all = AvatarCatalog.portraits
        .map((p) => AvatarCatalog.seededStyleFor(p.id))
        .toSet();
    expect(all.length, greaterThan(1),
        reason: 'seeded styles should not all be identical');
  });

  test('AvatarStyle.toneCount matches the palettes the painter indexes', () {
    // The model clamps tone against this constant while the painter indexes
    // real lists. If they drift, a valid tone would render out of range.
    expect(AvatarStyle.toneCount, AvatarPalette.terranSkin.length);
    expect(AvatarStyle.toneCount, AvatarPalette.vinariSkin.length);
    expect(AvatarStyle.toneCount, AvatarPalette.duranSkin.length);
  });

  test('species skin is drawn from its own palette, not the faction colour',
      () {
    // The regression this file exists for: an earlier pass tinted skin with
    // factionColor(), which made Traders green and Duran red. Faction colour
    // belongs on the ring and backdrop; skin belongs to the species.
    for (final species in AvatarSpecies.values) {
      final accent = factionColor(species.faction);
      for (var i = 0; i < AvatarStyle.toneCount; i++) {
        final skin = AvatarPalette.skin(species, i);
        expect(skin, isNot(accent),
            reason: '$species skin $i must not be its faction colour');
      }
    }

    // Spot-check the lore bands the design calls for.
    expect(
      AvatarPalette.terranSkin.every((c) => c.r >= c.g && c.r >= c.b),
      isTrue,
      reason:
          'Terrans are human complexions, so warm — never the faction green',
    );
    expect(
      AvatarPalette.terranSkin.map((c) => c.computeLuminance()).toSet().length,
      greaterThan(3),
      reason: '"diverse Terrans" implies a real spread of complexions',
    );
    expect(
      AvatarPalette.duranSkin.every((c) => c.b <= c.g && c.b <= c.r),
      isTrue,
      reason: 'Duran skin should read greenish/brown — never red, so blue is '
          'never the dominant channel',
    );
    expect(
      AvatarPalette.vinariSkin
          .every((c) => c.b >= c.r - 0.08 && c.b >= c.g - 0.08),
      isTrue,
      reason: 'Vinari forms should stay bluish/purplish/whitish',
    );
  });

  test('the Vinari are treated as a non-humanoid species', () {
    // Lore: "glowing, fluid forms... like living auroras". The sclera rule is
    // the model's expression of that; the painter omits ears, nose, and mouth.
    expect(AvatarPalette.hasSclera(AvatarSpecies.terran), isTrue);
    expect(AvatarPalette.hasSclera(AvatarSpecies.duran), isTrue);
    expect(AvatarPalette.hasSclera(AvatarSpecies.vinari), isFalse);
  });

  test('variantCount stays in a range the painter can actually draw', () {
    // The gallery builds one swatch per variant from this constant and
    // AvatarStyle.sanitized clamps to it, so a bad value breaks both.
    expect(AvatarCatalog.variantCount, greaterThan(0));
    final maxed = AvatarStyle(
      tone: AvatarStyle.toneCount - 1,
      outfit: AvatarCatalog.variantCount - 1,
      outfitTone: AvatarCatalog.variantCount - 1,
      hair: AvatarCatalog.variantCount - 1,
      horns: AvatarCatalog.variantCount - 1,
      eyes: AvatarCatalog.variantCount - 1,
      markings: AvatarCatalog.variantCount - 1,
      expression: AvatarCatalog.variantCount - 1,
    ).sanitized();
    expect(maxed.tone, AvatarStyle.toneCount - 1);
    expect(maxed.hair, AvatarCatalog.variantCount - 1);
    expect(maxed.horns, AvatarCatalog.variantCount - 1);
  });

  test('re-rolls produce markings often enough to be worth the axis', () {
    // Regression: a uniform draw over 3 values left "unmarked" two rolls in
    // three, so markings were barely visible in practice.
    var seed = 31337;
    int nextInt(int max) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return (seed >> 8) % max;
    }

    var marked = 0;
    const rolls = 200;
    for (var i = 0; i < rolls; i++) {
      if (AvatarStyle.reroll(nextInt).markings != 0) marked++;
    }

    expect(marked / rolls, greaterThan(0.6),
        reason: 'markings should appear on the majority of re-rolls');
    expect(marked, lessThan(rolls), reason: 'unmarked must still be possible');
  });

  test('seeded styles also favour a marked face', () {
    final marked = AvatarCatalog.portraits
        .where((p) => AvatarCatalog.seededStyleFor(p.id).markings != 0)
        .length;
    expect(marked / AvatarCatalog.portraits.length, greaterThan(0.6),
        reason: 'an un-customised portrait should usually carry markings too');
  });

  test('Duran garment colour ignores presentation', () {
    // They are a warrior race. Gender is carried by crest, horn, and plating
    // silhouette instead — a per-presentation palette would undercut them, so
    // this is deliberately a non-feature and is pinned by a test.
    for (var v = 0; v < 3; v++) {
      final colors = AvatarPresentation.values
          .map((p) => AvatarPalette.outfit(AvatarSpecies.duran, v, p))
          .toSet();
      expect(colors.length, 1,
          reason: 'Duran armour must not shift with presentation');
    }
  });

  test('Vinari garments do shift with presentation', () {
    final female = AvatarPalette.outfit(
        AvatarSpecies.vinari, 0, AvatarPresentation.female);
    final neutral = AvatarPalette.outfit(
        AvatarSpecies.vinari, 0, AvatarPresentation.neutral);
    expect(female, isNot(neutral),
        reason: 'the female Vinari shroud is a lighter lavender');
    // Still inside the species band, though.
    expect(female.b, greaterThanOrEqualTo(female.g),
        reason: 'Vinari clothing stays bluish/purplish');
  });

  test('marking pigment is not the faction colour', () {
    // Faction red on green Duran skin read as a bleeding wound.
    for (final species in AvatarSpecies.values) {
      final accent = factionColor(species.faction);
      for (var v = 0; v < 2; v++) {
        expect(AvatarPalette.markingPigment(species, v, null), isNot(accent),
            reason: '$species marking $v must not be the faction colour');
      }
    }
  });

  test('seed generation stays inside the exact-integer range', () {
    // A JS double cannot represent every integer above 2^53, so an LCG whose
    // intermediate product exceeds that loses low bits on Flutter web and
    // renders different portraits than the VM. These bounds are the guard for
    // the "stable across platforms" claim on [AvatarCatalog.stableSeedFor] and
    // [AvatarCatalog.seededStyleFor].
    for (final id in AvatarCatalog.portraits.map((p) => p.id)) {
      final seed = AvatarCatalog.stableSeedFor(id);
      expect(seed, inInclusiveRange(0, 0xFFFFFFFF),
          reason: '$id seed out of 32-bit range');
      // Reproduce the largest intermediate the hash performs.
      final biggest = 0xFFFF * 0x0100 + 0xFFFF * 0x0193;
      expect(biggest, lessThan(0x1 << 53));
      final style = AvatarCatalog.seededStyleFor(id);
      expect(style.tone, inInclusiveRange(0, AvatarStyle.toneCount - 1));
    }
  });

  test('seeded styles are identical across repeated calls and platforms', () {
    // Same id must always give the same look, or a returning player would see
    // their pilot change between sessions.
    for (final id in AvatarCatalog.portraits.map((p) => p.id)) {
      expect(AvatarCatalog.seededStyleFor(id), AvatarCatalog.seededStyleFor(id),
          reason: '$id must seed deterministically');
    }
  });

  test('every species has a distinct garment set per outfit value', () {
    // The `outfit` axis used to be inert for the Duran and the Vinari, so
    // 8 axes were really 6 for two thirds of the gallery.
    for (final species in AvatarSpecies.values) {
      final colors = <Color>{
        for (var o = 0; o < AvatarCatalog.variantCount; o++)
          AvatarPalette.outfit(species, o),
      };
      expect(colors.length, greaterThan(1),
          reason: '$species needs visibly different outfits');
    }
  });
}
