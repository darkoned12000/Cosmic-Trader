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
  static Color outfit(
    AvatarSpecies species,
    int variant, [
    AvatarPresentation presentation = AvatarPresentation.neutral,
  ]) {
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

  /// Highlight for a Duran armour plate edge. Kept separate from [outfitTrim]
  /// because plating wants a harder, brighter catch than a fabric collar.
  static Color plateHighlight(AvatarSpecies species, int variant) {
    if (species == AvatarSpecies.duran) {
      return const [
        Color(0xFF9A8C5E),
        Color(0xFF8A6A48),
        Color(0xFF6F7F5A)
      ][_wrap(variant, 3)];
    }
    return outfitTrim(species, variant);
  }

  /// A lighter trim tone for collars, straps, and insignia.
  ///
  /// Tinted toward the species rather than just lightened: an earlier pass used
  /// a flat lerp-to-white, which made every species' garment trim read as the
  /// same washed-out grey.
  static Color outfitTrim(AvatarSpecies species, int variant) {
    final base = outfit(species, variant);
    switch (species) {
      case AvatarSpecies.duran:
        // Worn chitin edge.
        return Color.lerp(base, const Color(0xFF8A7A4E), 0.34)!;
      case AvatarSpecies.vinari:
        // A luminous edge, not cloth.
        return Color.lerp(base, const Color(0xFF9E93FF), 0.30)!;
      case AvatarSpecies.terran:
        return Color.lerp(base, const Color(0xFFB9C4D0), 0.18)!;
    }
  }

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

  /// Resolved hair colour: the player's dye if set, else the shape's own.
  static Color hair(AvatarSpecies species, int shapeVariant, int? dye) =>
      dye == null
          ? legacyHair(species, shapeVariant)
          : hairColours(species)[_wrap(dye, hairColours(species).length)];

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

  /// Resolved marking pigment.
  static Color markingPigment(
          AvatarSpecies species, int patternVariant, int? dye) =>
      dye == null
          ? legacyMarkingPigment(species, patternVariant)
          : markingColours(species)[_wrap(dye, markingColours(species).length)];

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
  static Color trim(AvatarSpecies species, int outfitTone, int? dye) =>
      dye == null
          ? outfitTrim(species, outfitTone)
          : trimColours(species)[_wrap(dye, trimColours(species).length)];
}
