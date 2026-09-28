import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';

/// One selectable portrait in the gallery.
///
/// [id] is the **stable** key persisted in `players.json`. It is derived from
/// the species/presentation/role/number of the portrait and must never be
/// reused for different artwork — renaming the catalogue entry is fine,
/// changing the id would silently repoint every saved selection.
class AvatarPortrait {
  const AvatarPortrait({
    required this.id,
    required this.species,
    required this.presentation,
    required this.label,
    this.isDefault = false,
    this.affiliation = AvatarAffiliation.native,
  });

  /// Stable catalogue key, e.g. `duran_male_lancer_01`.
  final String id;
  final AvatarSpecies species;
  final AvatarPresentation presentation;

  /// Human-readable callsign. Every option carries a name so a player never
  /// has to tell two portraits apart by colour alone (accessibility).
  final String label;

  /// The portrait handed to new pilots and to existing accounts with no saved
  /// selection. Exactly one per species; see [AvatarCatalog.defaultFor].
  final bool isDefault;

  /// Who this pilot fights for, independent of species. Every catalogue entry is
  /// [AvatarAffiliation.native]; only derived NPC portraits are ever pirates.
  final AvatarAffiliation affiliation;

  /// The faction whose colour identifies this pilot on the ring and backdrop.
  ///
  /// Resolved through [AvatarAffiliation.factionColorFor] rather than from
  /// `species.faction`, so the painter and `AvatarPortraitView` cannot disagree
  /// about a pirate's colour — a pirate Duran is orange, not Hegemony red.
  ///
  /// Returns a [FactionClass] rather than a `Color` to keep this file free of
  /// `package:flutter`; callers pass it to `factionColor()`.
  FactionClass get accentFaction =>
      AvatarAffiliation.factionColorFor(affiliation, species);

  /// Deterministic seed for the procedural portrait painter.
  ///
  /// Uses a stable FNV-1a hash of [id] rather than `String.hashCode`, which is
  /// explicitly not a persistence contract — the art must not reshuffle when
  /// the SDK changes its string hashing.
  int get drawSeed => AvatarCatalog.stableSeedFor(id);

  /// The appearance this portrait gets when the player has not customised
  /// anything. Derived from [drawSeed], so it is stable across platforms and
  /// identical for every build that has not been given a `null` style.
  AvatarStyle get seededStyle =>
      AvatarCatalog.seededStyleFor(id, affiliation: affiliation);

  @override
  String toString() => 'AvatarPortrait($id)';
}

/// The single source of truth for which portraits exist.
///
/// The gallery builds itself from [portraits]; a selection stores only the
/// stable [AvatarPortrait.id]. Reordering or adding entries here can therefore
/// never change what a returning player sees.
abstract final class AvatarCatalog {
  static const List<AvatarPortrait> portraits = [
    // ── Duran — scaly insectoid warriors in battle-armor ──────────
    AvatarPortrait(
      id: 'duran_male_lancer_01',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.male,
      label: 'Veth Kaal',
      isDefault: true,
    ),
    AvatarPortrait(
      id: 'duran_male_warden_02',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.male,
      label: 'Sarrun Okh',
    ),
    AvatarPortrait(
      id: 'duran_male_scout_03',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.male,
      label: 'Ith Gresh',
    ),
    AvatarPortrait(
      id: 'duran_female_razor_01',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.female,
      label: "Nyx'a Tessen",
    ),
    AvatarPortrait(
      id: 'duran_female_warden_02',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.female,
      label: 'Keth Vaan',
    ),
    AvatarPortrait(
      id: 'duran_female_seer_03',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.female,
      label: 'Mirr Uhl',
    ),
    AvatarPortrait(
      id: 'duran_neutral_ash_01',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.neutral,
      label: 'Vol Tesh',
    ),
    AvatarPortrait(
      id: 'duran_neutral_cinder_02',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.neutral,
      label: 'Ruk Gaal',
    ),
    AvatarPortrait(
      id: 'duran_neutral_flint_03',
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.neutral,
      label: 'Aden Kraal',
    ),

    // ── Vinari — glowing fluid forms, shifting like living auroras ─
    AvatarPortrait(
      id: 'vinari_male_oracle_01',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.male,
      label: 'Sael Ithri',
      isDefault: true,
    ),
    AvatarPortrait(
      id: 'vinari_male_weaver_02',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.male,
      label: 'Oryn Vess',
    ),
    AvatarPortrait(
      id: 'vinari_male_lumen_03',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.male,
      label: 'Kaveth Sol',
    ),
    AvatarPortrait(
      id: 'vinari_female_weaver_01',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.female,
      label: 'Aelune Thys',
    ),
    AvatarPortrait(
      id: 'vinari_female_oracle_02',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.female,
      label: 'Nivea Ossu',
    ),
    AvatarPortrait(
      id: 'vinari_female_lumen_03',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.female,
      label: 'Sarina Vel',
    ),
    AvatarPortrait(
      id: 'vinari_neutral_aurora_01',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.neutral,
      label: 'Ilex Nume',
    ),
    AvatarPortrait(
      id: 'vinari_neutral_halo_02',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.neutral,
      label: 'Corin Elu',
    ),
    AvatarPortrait(
      id: 'vinari_neutral_drifter_03',
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.neutral,
      label: 'Tal Sivo',
    ),

    // ── Terran — diverse humans in jumpsuits and merchant finery ──
    AvatarPortrait(
      id: 'terran_male_broker_01',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.male,
      label: 'Wes Halloway',
      isDefault: true,
    ),
    AvatarPortrait(
      id: 'terran_male_pilot_02',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.male,
      label: 'Dez Okoro',
    ),
    AvatarPortrait(
      id: 'terran_male_envoy_03',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.male,
      label: 'Marc Sung',
    ),
    AvatarPortrait(
      id: 'terran_female_broker_01',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.female,
      label: 'Ines Vargas',
    ),
    AvatarPortrait(
      id: 'terran_female_pilot_02',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.female,
      label: 'Rin Takahashi',
    ),
    AvatarPortrait(
      id: 'terran_female_envoy_03',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.female,
      label: 'Sol Adeyemi',
    ),
    AvatarPortrait(
      id: 'terran_neutral_broker_01',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.neutral,
      label: 'Jules Abernathy',
    ),
    AvatarPortrait(
      id: 'terran_neutral_pilot_02',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.neutral,
      label: 'Kai Lindqvist',
    ),
    AvatarPortrait(
      id: 'terran_neutral_envoy_03',
      species: AvatarSpecies.terran,
      presentation: AvatarPresentation.neutral,
      label: 'Ash Mbeki',
    ),
  ];

  /// How many distinct crest/hair and marking variants the painter can draw.
  ///
  /// A single source of truth so the bounds in [AvatarStyle.sanitized] and the
  /// gallery's swatch rows cannot drift from what the painter actually draws.
  static const int variantCount = 3;

  /// A split-multiply hash over the UTF-16 code units of [value]. Stable across
  /// platforms and SDK versions, unlike `String.hashCode`.
  ///
  /// **Not FNV-1a**, despite what an earlier version of this comment claimed and
  /// what the file's history implies. The prime is applied as
  /// `lo * 0x193 + hi * 0x100 + (hash >> 16)` rather than `hash * 0x01000193`, and
  /// the multiply is deliberately split into 16-bit halves to keep every
  /// intermediate inside 2^53 for web parity. That is a *different function* from
  /// FNV-1a, and a weaker one: after the first code unit the state is bounded near
  /// 2.7e7 regardless of input length, so a few thousand ids can collide by
  /// birthday. Fine for 27 catalogue entries and for the "hundreds of NPCs show no
  /// repeats" claim, which is what this is used for. Do not describe it as FNV-1a,
  /// and do not "fix" it to be — that would repaint every saved portrait and every
  /// existing NPC face.
  ///
  /// The multiply is deliberately kept under 2^53. A plain 32-bit FNV prime
  /// (0x01000193) times a 32-bit hash reaches ~7e16, which exceeds the exact
  /// integer range of a JS double — so on Flutter web the intermediate product
  /// silently loses low bits and the art would differ from the VM. Reducing
  /// between steps keeps every intermediate exactly representable.
  static int stableSeedFor(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      // Two 16-bit halves so each product stays well inside 2^53.
      hash = (((hash & 0xFFFF) * 0x0193) +
              (((hash >> 16) & 0xFFFF) * 0x0100) +
              (hash >>> 16)) &
          0xFFFFFFFF;
    }
    return hash;
  }

  /// The style a portrait falls back to when a selection carries no explicit
  /// one. Derived purely from [portraitId] (and [affiliation]) so an
  /// un-customised portrait looks the same everywhere and across rebuilds.
  ///
  /// [affiliation] biases one axis and nothing else. Pirates carry markings far
  /// more often: a hard life leaves a record, and more of it on somebody who
  /// chose that life.
  ///
  /// ## The extra draw is deliberately last-ish
  ///
  /// The bias consumes an *additional* draw, and only for pirates, so the RNG
  /// stream for every [AvatarAffiliation.native] portrait is untouched. Drawing
  /// the bias inside the shared sequence would shift [expression] and every
  /// later consumer for all 27 catalogue entries, silently repainting every
  /// player portrait saved so far — the exact failure the `null`-means-legacy
  /// rule exists to prevent. Pirates are derived per-NPC and never persisted, so
  /// they are free to consume a different number of draws.
  static AvatarStyle seededStyleFor(
    String portraitId, {
    AvatarAffiliation affiliation = AvatarAffiliation.native,
  }) {
    // A local Lehmer draw rather than `math.Random` so the value depends on
    // nothing but the id — no global RNG state, no library import here.
    //
    // Park–Miller LCG (multiplier 16807, modulus 2^31 - 1). The multiplier is
    // chosen so `seed * 16807` stays below 2^53 for every seed, which keeps this
    // bit-identical on the VM and on Flutter web; the common 1103515245
    // constant overflows a JS double and would give web different portraits.
    var seed = (stableSeedFor(portraitId) ^ 0x5BF03635) % 0x7FFFFFFF;
    if (seed <= 0) seed += 0x7FFFFFFE;
    int nextInt(int max) {
      seed = (seed * 16807) % 0x7FFFFFFF;
      return seed % max;
    }

    final pirate = affiliation == AvatarAffiliation.pirate;

    // Hoisted into sequential locals rather than passed as named arguments.
    //
    // Dart evaluates named arguments in source order, so the argument list *was*
    // the draw order — a formatter will not reorder it, but any refactor that
    // reorders or regroups those arguments silently shifts the stream for all 27
    // catalogue portraits and every saved avatar. Written out, the order is
    // visible and a reorder is a diff rather than an accident.
    final tone = nextInt(AvatarStyle.toneCount);
    final outfit = nextInt(variantCount);
    final outfitTone = nextInt(variantCount);
    final hair = nextInt(variantCount);
    final horns = nextInt(variantCount);
    final eyes = nextInt(variantCount);
    // Same weighting as AvatarStyle.reroll, so an un-customised portrait is as
    // likely to carry markings as a re-rolled one.
    final markings = nextInt(4) == 0 ? 0 : nextInt(2) + 1;
    // Pirates never draw "Amused" (the third option, the only one with a mouth
    // that curves upward). A smiling raider reads as friendly, and a third of a
    // pirate roster grinning detours the eye straight past the silhouette work
    // the affiliation otherwise does.
    //
    // Drawn over 2 rather than 3, so the modulus differs but the **number of
    // draws does not** — one `nextInt` either way, which is what keeps the native
    // stream identical. Over 1 would be the tempting version ("always stern") and
    // it would throw away the neutral option for nothing: half stern and half
    // neutral still never smiles, and keeps two faces in the mix.
    final expression = nextInt(pirate ? 2 : variantCount);

    // Colour slots. Left null for everyone, which is the "coupled" reading that
    // reproduces the old shape-keyed colours for pre-slot saves.
    //
    // Pirates are the exception, and a peer review caught why it matters: with
    // `hairColor` null, `AvatarPalette.hair` keys the pirate's dye off the hair
    // *shape*, so a pirate got 3 distinct looks from a 3×3 shape/dye grid — the
    // exact coupling the dye axis exists to remove — and one entry of each
    // pirate dye list was unreachable. Drawing the slots costs two extra draws
    // **on the pirate path only**, which is free: a pirate style is derived
    // per-NPC and never persisted.
    final hairColor = pirate ? nextInt(3) : null;
    final markingColor = pirate && markings > 0 ? nextInt(3) : null;

    var style = AvatarStyle(
      tone: tone,
      outfit: outfit,
      outfitTone: outfitTone,
      hair: hair,
      horns: horns,
      eyes: eyes,
      markings: markings,
      expression: expression,
      hairColor: hairColor,
      markingColor: markingColor,
    );

    // Only reached by a pirate who drew unmarked, so native portraits never
    // consume these draws and their stream is unchanged.
    //
    // Three unmarked draws in four become marked. That takes pirates from ~75%
    // marked to ~95% rather than to 100%: a pirate with no marks at all reads as
    // somebody who joined last week, which is a look worth keeping in the mix. An
    // earlier version re-rolled unconditionally and measured exactly 100%, which
    // is a stronger claim than "more often" and threw away a variant for nothing.
    //
    // An earlier version also skewed the base rate (`nextInt(5)` for pirates) to
    // push the number up. A peer review showed that contributed almost nothing —
    // 6.25% unmarked down to 5% — while the re-roll does essentially all the work,
    // so the extra rate was complexity for no measurable gain and is gone.
    if (!pirate || style.markings != 0) {
      return style.sanitized();
    }
    style = style.copyWith(
      markings: nextInt(4) == 0 ? 0 : nextInt(2) + 1,
      // A pirate who loses their mark has no pigment to spend on one.
      clearMarkingColor: true,
    );
    return style.sanitized();
  }

  static final Map<String, AvatarPortrait> _byId = {
    for (final p in portraits) p.id: p,
  };

  /// Species that have a gallery, in presentation order.
  static List<AvatarSpecies> get species => AvatarSpecies.values;

  static List<AvatarPortrait> forSpecies(
    AvatarSpecies species, {
    AvatarPresentation? presentation,
  }) {
    return portraits
        .where((p) =>
            p.species == species &&
            (presentation == null || p.presentation == presentation))
        .toList(growable: false);
  }

  static AvatarPortrait? byId(String id) => _byId[id];

  /// Whether [portraitId] is a real entry belonging to [species] — the check
  /// that keeps a stale save from pointing at another species' art.
  static bool isValidFor(AvatarSpecies species, String portraitId) {
    final entry = _byId[portraitId];
    return entry != null && entry.species == species;
  }

  /// The recommended portrait for [species].
  ///
  /// When [presentation] is given, the species' curated default is used only if
  /// it matches — otherwise the first portrait in that presentation. This is
  /// what the gallery calls when the player switches presentation tabs: the tab
  /// label and the shown artwork must not disagree.
  ///
  /// Falls back to the first entry of the species if a species is ever left
  /// without a flagged default, so this never throws.
  static AvatarPortrait defaultFor(
    AvatarSpecies species, {
    AvatarPresentation? presentation,
  }) {
    for (final p in portraits) {
      if (p.species == species && p.isDefault && presentation == null) return p;
    }
    final pool = forSpecies(species, presentation: presentation);
    if (pool.isEmpty) return portraits.first;
    for (final p in pool) {
      if (p.isDefault) return p;
    }
    return pool.first;
  }
}
