import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';

/// Skin, garment, and eye palettes for each species.
///
/// These are deliberately **separate from the faction palette**. An earlier
/// pass derived skin by tinting `factionColor()`, which is why Traders came out
/// green and Duran came out red — faction identity belongs on the portrait's
/// border and backdrop, not on the pilot's actual skin. `FactionPalette` stays
/// the single source of truth for the ring and backdrop; this file is the
/// source of truth for what a species looks like.
///
/// Lore anchors:
///   Duran  — "scaly, insectoid warriors clad in battle-armor"
///   Vinari — "glowing, fluid forms with shifting colors, like living auroras"
///   Trader — "diverse Terrans in practical jumpsuits or merchant finery"
abstract final class AvatarPalette {
  /// Human complexions for the Traders. A plain spread of skin tones; nothing
  /// here implies anything about a pilot beyond the colour itself.
  static const List<Color> terranSkin = [
    Color(0xFFF6DCC8),
    Color(0xFFEFC39C),
    Color(0xFFD9A273),
    Color(0xFFB07B4B),
    Color(0xFF8A5A34),
    Color(0xFF5E3A22),
  ];

  /// Ethereal Vinari forms: bluish, purplish, and near-white.
  static const List<Color> vinariSkin = [
    Color(0xFFF2F0FF),
    Color(0xFFD6D0FF),
    Color(0xFFB3A8FF),
    Color(0xFF8E7DE8),
    Color(0xFF6FC2D8),
    Color(0xFF5B6FC4),
  ];

  /// Duran: greenish, black, and brown, over a scaled base.
  static const List<Color> duranSkin = [
    Color(0xFF7C8F63),
    Color(0xFF556B3F),
    Color(0xFF3A4A2E),
    Color(0xFF6B5638),
    Color(0xFF43331F),
    Color(0xFF232E1F),
  ];

  static List<Color> skinFor(AvatarSpecies species) {
    switch (species) {
      case AvatarSpecies.terran:
        return terranSkin;
      case AvatarSpecies.vinari:
        return vinariSkin;
      case AvatarSpecies.duran:
        return duranSkin;
    }
  }

  /// Picks a skin tone by index, wrapping so any integer is safe.
  static Color skin(AvatarSpecies species, int index) {
    final list = skinFor(species);
    return list[((index % list.length) + list.length) % list.length];
  }

  /// Wraps [index] into a list of [options] items.
  ///
  /// Deliberately derived from the list length rather than a hard-coded `3`.
  /// A hard-coded modulus silently mapped any extra option back onto option 0
  /// if [AvatarCatalog.variantCount] ever grew past the palette lists.
  static int _wrap(int index, int length) =>
      ((index % length) + length) % length;

  /// Garment base for a species and presentation.
  ///
  /// The Duran read as battle-armour (dark, plate-like), the Vinari as a
  /// shifting fluid shroud, the Traders as practical jumpsuit fabric.
  ///
  /// [presentation] only shifts the Vinari: a lavender/pearl shroud for the
  /// female presentation, deeper jewel tones otherwise. The Duran deliberately
  /// get **no** presentation shift in colour — they are a warrior race, so
  /// gender is carried by silhouette (crest and horn shape, plating density)
  /// rather than a palette that would undercut them.
  ///
  /// ## Pirates
  ///
  /// [affiliation] swaps in [pirateOutfit], which is the same garment
  /// construction in cloth bought off-planet: darker, flatter, and less
  /// saturated than anything a faction issues. The Duran lose their military
  /// green, the Vinari their aurora jewel tones, the Traders their Guild
  /// blues — which is the point, since a pirate is wearing whatever they could
  /// get rather than what was issued to them.
  ///
  /// Skin and eyes are **not** affected. A pirate is still a Duran, Vinari, or
  /// Terran underneath; only the clothes are defected. Making a pirate's skin
  /// darker would be inventing a fourth race, which is exactly what
  /// [AvatarAffiliation] exists to avoid.
  static Color outfit(
    AvatarSpecies species,
    int variant, [
    AvatarPresentation presentation = AvatarPresentation.neutral,
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  ]) {
    if (affiliation == AvatarAffiliation.pirate) {
      return pirateOutfit(species, variant);
    }
    switch (species) {
      case AvatarSpecies.duran:
        return const [
          Color(0xFF2E3A2A),
          Color(0xFF3B2F22),
          Color(0xFF232B20)
        ][_wrap(variant, 3)];
      case AvatarSpecies.vinari:
        if (presentation == AvatarPresentation.female) {
          return const [
            Color(0xFF6E5FA8),
            Color(0xFF8C7BC4),
            Color(0xFFA79AD8)
          ][_wrap(variant, 3)];
        }
        return const [
          Color(0xFF3B3468),
          Color(0xFF2A2F5C),
          Color(0xFF47407E)
        ][_wrap(variant, 3)];
      case AvatarSpecies.terran:
        return const [
          Color(0xFF3E4A57),
          Color(0xFF4A3F38),
          Color(0xFF2F3B44)
        ][_wrap(variant, 3)];
    }
  }

  /// Off-planet cloth, per species. Every entry is darker than its native
  /// counterpart at the same [variant]; `avatar_palette_test.dart` asserts that
  /// with relative luminance rather than trusting the hex values to look right.
  static const Map<AvatarSpecies, List<Color>> _pirateOutfits = {
    AvatarSpecies.duran: [
      Color(0xFF1D2318),
      Color(0xFF261F16),
      Color(0xFF141810),
    ],
    AvatarSpecies.vinari: [
      Color(0xFF221E3E),
      Color(0xFF191B30),
      Color(0xFF2A2448),
    ],
    AvatarSpecies.terran: [
      Color(0xFF232830),
      Color(0xFF2B2521),
      Color(0xFF1A1F25),
    ],
  };

  static List<Color> pirateOutfits(AvatarSpecies species) =>
      _pirateOutfits[species]!;

  static Color pirateOutfit(AvatarSpecies species, int variant) =>
      pirateOutfits(species)[_wrap(variant, pirateOutfits(species).length)];

  /// Highlight for a Duran armour plate edge. Kept separate from [outfitTrim]
  /// because plating wants a harder, brighter catch than a fabric collar.
  static Color plateHighlight(
    AvatarSpecies species,
    int variant, [
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  ]) {
    if (species == AvatarSpecies.duran) {
      if (affiliation == AvatarAffiliation.pirate) {
        // Salvaged plate, not issued plate: the catch is duller and dirtier.
        return const [
          Color(0xFF6E6444),
          Color(0xFF615038),
          Color(0xFF4E5A3E)
        ][_wrap(variant, 3)];
      }
      return const [
        Color(0xFF9A8C5E),
        Color(0xFF8A6A48),
        Color(0xFF6F7F5A)
      ][_wrap(variant, 3)];
    }
    return outfitTrim(species, variant, affiliation);
  }

  /// A lighter trim tone for collars, straps, and insignia.
  ///
  /// Tinted toward the species rather than just lightened: an earlier pass used
  /// a flat lerp-to-white, which made every species' garment trim read as the
  /// same washed-out grey.
  static Color outfitTrim(
    AvatarSpecies species,
    int variant, [
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  ]) {
    if (affiliation == AvatarAffiliation.pirate) {
      // Somebody else's insignia: the same trim *target* as a faction member's,
      // mixed into the pirate's own cloth rather than into issued cloth.
      //
      // Two reviews' worth of history here, and the second one caught the first
      // fix being wrong. v1 lerped the *native trim* toward black, which
      // guaranteed the property its test asserted — darker than native trim —
      // while degrading the one that matters: contrast against its own garment.
      // Measured, that put cloth-to-trim at 1.15:1, worse than the native 1.43:1
      // in all nine species/variant combinations, so the trim all but vanished.
      //
      // v2 aimed at the right shape and quoted the right numbers, but kept
      // `final base = outfit(species, variant)` — which resolves with the
      // **default, native** affiliation. The pirate branch therefore computed
      // exactly what the native branch computed, and pirate trim came out
      // *bit-for-bit identical* to native trim. It passed the "never brighter"
      // assertion because that assertion was `lessThanOrEqualTo` and they were
      // equal, and the comment described a derivation the code did not do.
      //
      // The base has to be the pirate's own cloth. Note how quietly that failed:
      // the wrong answer was indistinguishable from the right one to every
      // assertion that existed, which is the argument for asserting the property
      // a viewer can see (contrast) rather than a relationship between two values
      // that happen to be computed from the same input.
      return Color.lerp(
          outfit(species, variant, AvatarPresentation.neutral,
              AvatarAffiliation.pirate),
          _trimTarget(species),
          _trimRate(species))!;
    }
    final base = outfit(species, variant);
    return Color.lerp(base, _trimTarget(species), _trimRate(species))!;
  }

  /// The hue a species' trim is mixed toward. Shared by the native and pirate
  /// paths so the two cannot drift into different families.
  static Color _trimTarget(AvatarSpecies species) {
    switch (species) {
      case AvatarSpecies.duran:
        return const Color(0xFF8A7A4E); // worn chitin edge
      case AvatarSpecies.vinari:
        return const Color(0xFF9E93FF); // a luminous edge, not cloth
      case AvatarSpecies.terran:
        return const Color(0xFFB9C4D0);
    }
  }

  /// How far toward [_trimTarget] the trim is mixed. The Terran take less because
  /// their issued cloth is lighter and a heavy mix reads as white piping.
  static double _trimRate(AvatarSpecies species) {
    switch (species) {
      case AvatarSpecies.duran:
        return 0.34;
      case AvatarSpecies.vinari:
        return 0.30;
      case AvatarSpecies.terran:
        return 0.18;
    }
  }

  /// Pirate trim targets, per species: salvage that does not match the garment
  /// it is sewn onto. Used only when a `trimColor` dye is chosen — the implicit
  /// path mixes [_trimTarget] into the pirate cloth, which keeps the contrast.
  static const Map<AvatarSpecies, List<Color>> _pirateTrimColours = {
    AvatarSpecies.duran: [
      Color(0xFF7A6A44),
      Color(0xFF6E5A48),
      Color(0xFF5F6A4A),
    ],
    AvatarSpecies.vinari: [
      Color(0xFF7E74C8),
      Color(0xFF5FA89E),
      Color(0xFFB87E9C),
    ],
    AvatarSpecies.terran: [
      Color(0xFF9AA4AE),
      Color(0xFFB09A7C),
      Color(0xFF7E9E8C),
    ],
  };

  static List<Color> pirateTrimColours(AvatarSpecies species) =>
      _pirateTrimColours[species]!;

  // ── Hair / crest / drift ───────────────────────────────────────
  //
  // Two lists, because colour and shape used to be welded together: `hair`
  // chose a silhouette *and* its colour, so three silhouettes gave three looks
  // instead of nine. [hairColour] is the decoupled dye list; [legacyHair] is
  // the old shape-keyed list, kept as the fallback so a save with a null
  // `hairColor` renders exactly as it did before the slot existed.

  /// The colour a shape implied, back when colour and shape were one axis.
  static Color legacyHair(AvatarSpecies species, int shapeVariant) {
    switch (species) {
      case AvatarSpecies.duran:
        return const [
          Color(0xFF1D2418),
          Color(0xFF2E2114),
          Color(0xFF14180F),
        ][_wrap(shapeVariant, 3)];
      case AvatarSpecies.vinari:
        // Not hair — a luminous drift. Kept in the violet/cyan band so it reads
        // as part of the form rather than something worn.
        return const [
          Color(0xFFD8D2FF),
          Color(0xFFA9B6FF),
          Color(0xFFC8E6F5),
        ][_wrap(shapeVariant, 3)];
      case AvatarSpecies.terran:
        return const [
          Color(0xFF2A2119),
          Color(0xFF6B4A2C),
          Color(0xFF9C9186),
        ][_wrap(shapeVariant, 3)];
    }
  }

  /// Decoupled hair / crest / drift dye, per species.
  static const Map<AvatarSpecies, List<Color>> _hairDyes = {
    AvatarSpecies.duran: [
      Color(0xFF1B2417),
      Color(0xFF6B5A32),
      Color(0xFF2F4A2C),
    ],
    AvatarSpecies.vinari: [
      Color(0xFFD8D2FF),
      Color(0xFF7FE3D8),
      Color(0xFFFFC9E0),
    ],
    AvatarSpecies.terran: [
      Color(0xFF1F1A16),
      Color(0xFF8C5A2B),
      Color(0xFFD9C7A8),
    ],
  };

  static List<Color> hairColours(AvatarSpecies species) => _hairDyes[species]!;

  /// Pirate hair / crest / drift, per species.
  ///
  /// Sun-bleached, sweat-dark, or dyed with whatever was to hand. Deliberately
  /// still *species-plausible*: a Vinari's drift is dimmer, not brown, because
  /// the form is luminous whatever its owner does.
  static const Map<AvatarSpecies, List<Color>> _pirateHairDyes = {
    AvatarSpecies.duran: [
      Color(0xFF12160E),
      Color(0xFF4A3F26),
      Color(0xFF22301F),
    ],
    AvatarSpecies.vinari: [
      Color(0xFF9A93C8),
      Color(0xFF4E9E96),
      Color(0xFFB08CA0),
    ],
    AvatarSpecies.terran: [
      Color(0xFF15110E),
      Color(0xFF5C3A1C),
      Color(0xFFA79A88),
    ],
  };

  static List<Color> pirateHairColours(AvatarSpecies species) =>
      _pirateHairDyes[species]!;

  /// Resolved hair colour: the player's dye if set, else the shape's own.
  ///
  /// ## Why a pirate skips the legacy fallback
  ///
  /// Every other resolution here ends in `dye == null ? legacyHair(...)`, which
  /// reproduces what a save written before the dye slot existed looked like.
  /// A pirate opts out of that, because a pirate's style is derived per-NPC from
  /// an id and **never persisted** — there is no older pirate build to stay
  /// byte-compatible with. Falling through to the native hair colour would give
  /// a pirate the faction palette the affiliation exists to replace.
  static Color hair(
    AvatarSpecies species,
    int shapeVariant,
    int? dye, [
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  ]) {
    if (affiliation == AvatarAffiliation.pirate) {
      final list = pirateHairColours(species);
      return list[_wrap(dye ?? shapeVariant, list.length)];
    }
    return dye == null
        ? legacyHair(species, shapeVariant)
        : hairColours(species)[_wrap(dye, hairColours(species).length)];
  }

  // ── Eyes ───────────────────────────────────────────────────────

  /// The iris colour a shape implied, back when colour and shape were one axis.
  static Color legacyEye(AvatarSpecies species, int shapeVariant) {
    switch (species) {
      case AvatarSpecies.duran:
        return const [
          Color(0xFFD4A017),
          Color(0xFFC1440E),
          Color(0xFF8FA617)
        ][_wrap(shapeVariant, 3)];
      case AvatarSpecies.vinari:
        return const [
          Color(0xFFFFFFFF),
          Color(0xFFBFE9FF),
          Color(0xFFE4D8FF)
        ][_wrap(shapeVariant, 3)];
      case AvatarSpecies.terran:
        return const [
          Color(0xFF3B2A1A),
          Color(0xFF2E4A5C),
          Color(0xFF4A5A34)
        ][_wrap(shapeVariant, 3)];
    }
  }

  static const Map<AvatarSpecies, List<Color>> _eyeColours = {
    AvatarSpecies.duran: [
      Color(0xFFD4A017),
      Color(0xFFC1440E),
      Color(0xFF8FA617),
    ],
    AvatarSpecies.vinari: [
      Color(0xFFFFFFFF),
      Color(0xFFBFE9FF),
      Color(0xFFE4D8FF),
    ],
    AvatarSpecies.terran: [
      Color(0xFF3B2A1A),
      Color(0xFF2E4A5C),
      Color(0xFF4A5A34),
    ],
  };

  static List<Color> eyeColours(AvatarSpecies species) => _eyeColours[species]!;

  /// Resolved iris colour.
  static Color eye(AvatarSpecies species, int shapeVariant, int? dye) =>
      dye == null
          ? legacyEye(species, shapeVariant)
          : eyeColours(species)[_wrap(dye, eyeColours(species).length)];

  /// Whether this species' eyes have a visible sclera. The Vinari lore says
  /// otherwise, and it is a big part of why they read as non-humanoid.
  static bool hasSclera(AvatarSpecies species) =>
      species != AvatarSpecies.vinari;

  /// The pigment a marking pattern implied, back when pattern and pigment were
  /// one axis.
  static Color legacyMarkingPigment(AvatarSpecies species, int patternVariant) {
    switch (species) {
      case AvatarSpecies.duran:
        return const [
          Color(0xFFD8CFA8),
          Color(0xFF7A2E22)
        ][_wrap(patternVariant, 2)];
      case AvatarSpecies.vinari:
        return const [
          Color(0xFFD8D2FF),
          Color(0xFF9E93FF)
        ][_wrap(patternVariant, 2)];
      case AvatarSpecies.terran:
        return const [
          Color(0xFF7A5A48),
          Color(0xFF9C4A3A)
        ][_wrap(patternVariant, 2)];
    }
  }

  /// Decoupled marking pigment, per species.
  ///
  /// Deliberately *not* the faction colour. An early pass painted Duran war
  /// paint in faction red, which on green skin read as a bleeding gash and at
  /// one variant looked like a gag across the mouth.
  static const Map<AvatarSpecies, List<Color>> _markingColours = {
    AvatarSpecies.duran: [
      Color(0xFFD8CFA8),
      Color(0xFF7A2E22),
      Color(0xFF2E3A4A),
    ],
    AvatarSpecies.vinari: [
      Color(0xFFD8D2FF),
      Color(0xFF9E93FF),
      Color(0xFFFFFFFF),
    ],
    AvatarSpecies.terran: [
      Color(0xFF7A5A48),
      Color(0xFF9C4A3A),
      Color(0xFF3F5A6B),
    ],
  };

  static List<Color> markingColours(AvatarSpecies species) =>
      _markingColours[species]!;

  /// Pirate marking pigment, per species.
  ///
  /// This is where the affiliation's *markings* bias earns its keep. A native
  /// pilot's markings are decorative — clan pigment, war paint, a guild device.
  /// A pirate's read as a record of a hard life: scar tissue, old burns, the
  /// patchy remains of something that was inked once and never touched up. Pale
  /// scar and bruised tones rather than saturated pigment, so the same pattern
  /// reads as damage instead of decoration.
  ///
  /// Kept off faction colour for the same reason the native pigments are — see
  /// [_markingColours]. A red marking on a green pirate Duran would read as a
  /// fresh wound, which is at least consistent, but a *Durani* red on their own
  /// war paint would read as loyalism rather than as a scar.
  static const Map<AvatarSpecies, List<Color>> _pirateMarkingColours = {
    AvatarSpecies.duran: [
      Color(0xFFC9BFA4),
      Color(0xFF5A3A44),
      Color(0xFF2A3038),
    ],
    AvatarSpecies.vinari: [
      Color(0xFFB8B2D8),
      Color(0xFF6E63A8),
      Color(0xFF8FA0B8),
    ],
    AvatarSpecies.terran: [
      Color(0xFFC4B2A4),
      Color(0xFF6E4A48),
      Color(0xFF3A4650),
    ],
  };

  static List<Color> pirateMarkingColours(AvatarSpecies species) =>
      _pirateMarkingColours[species]!;

  /// Resolved marking pigment.
  ///
  /// As with [hair], a pirate resolves against its own table even for a null
  /// dye: pirate styles are derived per-NPC and never persisted, so there is no
  /// legacy pirate render to preserve.
  /// WCAG relative-luminance contrast between two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final hi = la > lb ? la : lb;
    final lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Nudges [pigment] away from [skin] until the pair is legible, or gives up and
  /// returns whichever of lightening/darkening got closest.
  ///
  /// A fixed pigment table cannot serve six skin tones. Measured across every
  /// species' own table, the worst pigment-on-skin pair is **1.02:1** — the mark is
  /// there and completely invisible. A dark scar on dark skin and a pale one on
  /// pale skin are the two cases that matter, and a static table gets at most one
  /// of them right.
  ///
  /// Applied to **pirates only**. Natives keep the table as authored so no saved
  /// portrait moves; the same weakness is real for them and is a separate piece of
  /// work, because fixing it repaints every portrait that has markings.
  static Color _ensureLegible(Color pigment, Color skin, {double min = 1.6}) {
    if (contrast(pigment, skin) >= min) return pigment;
    final lighter = Color.lerp(pigment, Colors.white, 0.72)!;
    final darker = Color.lerp(pigment, Colors.black, 0.72)!;
    return contrast(lighter, skin) >= contrast(darker, skin) ? lighter : darker;
  }

  /// Resolved marking pigment.
  ///
  /// [skin] is the colour the mark will be drawn on. Optional, and only used for
  /// pirates: without it there is nothing to check legibility against, which is the
  /// case for the editor's swatch row.
  ///
  /// As with [hair], a pirate resolves against its own table even for a null dye:
  /// pirate styles are derived per-NPC and never persisted, so there is no legacy
  /// pirate render to preserve.
  static Color markingPigment(
    AvatarSpecies species,
    int patternVariant,
    int? dye, [
    AvatarAffiliation affiliation = AvatarAffiliation.native,
    Color? skin,
  ]) {
    if (affiliation == AvatarAffiliation.pirate) {
      final list = pirateMarkingColours(species);
      final base = list[_wrap(dye ?? patternVariant, list.length)];
      return skin == null ? base : _ensureLegible(base, skin);
    }
    return dye == null
        ? legacyMarkingPigment(species, patternVariant)
        : markingColours(species)[_wrap(dye, markingColours(species).length)];
  }

  /// Decoupled garment trim / accent dye, per species. `outfitTrim` remains the
  /// legacy shape-keyed fallback.
  static const Map<AvatarSpecies, List<Color>> _trimColours = {
    AvatarSpecies.duran: [
      Color(0xFF8A7A4E),
      Color(0xFF6F7F5A),
      Color(0xFF8A6A48),
    ],
    AvatarSpecies.vinari: [
      Color(0xFF9E93FF),
      Color(0xFF7FE3D8),
      Color(0xFFFFC9E0),
    ],
    AvatarSpecies.terran: [
      Color(0xFFB9C4D0),
      Color(0xFFC8A882),
      Color(0xFF8FBFA8),
    ],
  };

  static List<Color> trimColours(AvatarSpecies species) =>
      _trimColours[species]!;

  /// Resolved garment trim colour.
  static Color trim(
    AvatarSpecies species,
    int outfitTone,
    int? dye, [
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  ]) {
    if (affiliation == AvatarAffiliation.pirate) {
      // Honours the dye too, which the first pirate version did not. `hair` and
      // `markingPigment` both take it, so ignoring it here made the exception
      // inconsistent inside itself. A dye picks a *target*, which is then mixed
      // into the pirate cloth at the same rate the implicit path uses — so a
      // chosen dye changes the hue without losing the contrast.
      if (dye == null) return outfitTrim(species, outfitTone, affiliation);
      final list = pirateTrimColours(species);
      return Color.lerp(
          outfit(species, outfitTone, AvatarPresentation.neutral, affiliation),
          list[_wrap(dye, list.length)],
          _trimRate(species))!;
    }
    return dye == null
        ? outfitTrim(species, outfitTone)
        : trimColours(species)[_wrap(dye, trimColours(species).length)];
  }
}
