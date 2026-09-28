import 'package:cosmic_trader/data/models/avatar_selection.dart';

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

  /// Deterministic seed for the procedural portrait painter.
  ///
  /// Uses a stable FNV-1a hash of [id] rather than `String.hashCode`, which is
  /// explicitly not a persistence contract — the art must not reshuffle when
  /// the SDK changes its string hashing.
  int get drawSeed => AvatarCatalog.stableSeedFor(id);

  /// The appearance this portrait gets when the player has not customised
  /// anything. Derived from [drawSeed], so it is stable across platforms and
  /// identical for every build that has not been given a `null` style.
  AvatarStyle get seededStyle => AvatarCatalog.seededStyleFor(id);

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

  /// FNV-1a over the UTF-16 code units of [value]. Stable across platforms and
  /// SDK versions, unlike `String.hashCode`.
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
  /// one. Derived purely from [portraitId] so an un-customised portrait looks
  /// the same everywhere and across rebuilds.
  static AvatarStyle seededStyleFor(String portraitId) {
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

    return AvatarStyle(
      tone: nextInt(AvatarStyle.toneCount),
      outfit: nextInt(variantCount),
      outfitTone: nextInt(variantCount),
      hair: nextInt(variantCount),
      horns: nextInt(variantCount),
      eyes: nextInt(variantCount),
      // Same weighting as AvatarStyle.reroll, so an un-customised portrait is
      // as likely to carry markings as a re-rolled one.
      markings: nextInt(4) == 0 ? 0 : nextInt(2) + 1,
      expression: nextInt(variantCount),
    ).sanitized();
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
