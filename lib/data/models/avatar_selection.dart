import 'package:flutter/foundation.dart';

import 'package:cosmic_trader/data/models/faction.dart';
// Deliberate dependency: the model resolves portrait IDs, and the registry
// that owns those IDs lives with the avatar widgets. `avatar_catalog.dart`
// imports this file for the enums back, so the two form a legal import cycle —
// kept harmless by keeping the catalog free of any `package:flutter` import, so
// the data layer never drags the widget layer in with it.
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';

/// A pilot species, one per playable faction.
///
/// Species is *derived* from the player's faction — it is not an independent
/// choice, and [AvatarSelection.forFaction] repairs any saved mismatch.
enum AvatarSpecies {
  duran,
  vinari,
  terran;

  /// The faction this species belongs to.
  FactionClass get faction {
    switch (this) {
      case AvatarSpecies.duran:
        return FactionClass.duran;
      case AvatarSpecies.vinari:
        return FactionClass.vinari;
      case AvatarSpecies.terran:
        return FactionClass.trader;
    }
  }

  /// Short species name for UI labels.
  String get label {
    switch (this) {
      case AvatarSpecies.duran:
        return 'Duran';
      case AvatarSpecies.vinari:
        return 'Vinari';
      case AvatarSpecies.terran:
        return 'Terran';
    }
  }

  /// The species backing [fc].
  ///
  /// Pirates have no species of their own — the design doc (§11) reuses Terran
  /// as a stand-in until pirates become selectable anywhere. Mapping them here
  /// (rather than throwing) keeps a hand-edited or future pirate save resolvable
  /// to a valid portrait instead of a missing-asset box.
  static AvatarSpecies forFaction(FactionClass fc) {
    switch (fc) {
      case FactionClass.duran:
        return AvatarSpecies.duran;
      case FactionClass.vinari:
        return AvatarSpecies.vinari;
      case FactionClass.trader:
      case FactionClass.pirate:
        return AvatarSpecies.terran;
    }
  }

  /// Tolerant decode: unknown or missing names fall back to [fallback].
  static AvatarSpecies fromName(Object? raw,
      {AvatarSpecies fallback = AvatarSpecies.terran}) {
    for (final s in AvatarSpecies.values) {
      if (s.name == raw) return s;
    }
    return fallback;
  }
}

/// A visual presentation style, not biological sex. The design doc treats
/// male/female/neutral purely as art direction for silhouette and styling.
enum AvatarPresentation {
  male,
  female,
  neutral;

  String get label {
    switch (this) {
      case AvatarPresentation.male:
        return 'Male';
      case AvatarPresentation.female:
        return 'Female';
      case AvatarPresentation.neutral:
        return 'Neutral';
    }
  }

  static AvatarPresentation fromName(
    Object? raw, {
    AvatarPresentation fallback = AvatarPresentation.neutral,
  }) {
    for (final p in AvatarPresentation.values) {
      if (p.name == raw) return p;
    }
    return fallback;
  }
}

/// Where a portrait comes from.
///
/// [custom] and [customFile] are reserved for the optional upload feature
/// (design doc §7), which is not implemented yet. The enum and the field are in
/// the v1 schema anyway so adding uploads later is not a schema change; until
/// then [AvatarCanvas] falls back to the selected preset rather than a
/// broken-image box.
enum AvatarSource {
  preset,
  custom;

  static AvatarSource fromName(Object? raw,
      {AvatarSource fallback = AvatarSource.preset}) {
    for (final s in AvatarSource.values) {
      if (s.name == raw) return s;
    }
    return fallback;
  }
}

/// Identifies one editable axis on an [AvatarStyle].
///
/// Lives in the model rather than beside the editor UI because
/// [AvatarStyle.rerolled] has to honour locks, and the data layer must not
/// import a widget library. It also gives per-axis UI state — the lock toggle,
/// the "changed" marker — a stable identity that does not depend on a widget
/// instance being rebuilt.
enum AxisStyleAxis {
  tone,
  eyes,
  eyeColor,
  markings,
  markingColor,
  expression,
  hair,
  hairColor,
  horns,
  gear,
  outfit,
  outfitTone,
  trimColor,
  backdrop,
}

/// Explicit, persisted appearance choices for the parts of a portrait that are
/// not baked into its catalogue entry.
///
/// Every axis is a small bounded index rather than a continuous value, and
/// [reroll] randomises all of them together. There is deliberately no UI for
/// setting individual axes: the pickers proved redundant once re-rolling was
/// strong enough, and a grid of variant controls is exactly what the design doc
/// (§5) warns against before a real art set exists.
///
/// A `null` style means "whatever the catalogue seeds for this portrait", which
/// is what keeps every pre-existing save rendering unchanged.
@immutable
class AvatarStyle {
  const AvatarStyle({
    required this.tone,
    required this.outfit,
    required this.outfitTone,
    required this.hair,
    required this.horns,
    required this.eyes,
    required this.markings,
    required this.expression,
    this.hairColor,
    this.eyeColor,
    this.markingColor,
    this.trimColor,
    this.gear,
    this.backdrop,
  });

  /// Which skin tone from the species' palette to use. Indexes
  /// `AvatarPalette.skinFor` — human complexions for Traders, bluish/purplish
  /// for the Vinari, greenish/brown for Duran. Deliberately not a raw hue: the
  /// previous build tinted skin with the *faction* colour, which produced green
  /// Traders and red Duran.
  final int tone;

  /// Garment silhouette. Each value pairs a collar/closure style with the kit
  /// that goes with it, so a zippered flight suit and a buttoned merchant coat
  /// read as whole outfits rather than mismatched parts.
  final int outfit;

  /// Which garment colour within the species' outfit range.
  final int outfitTone;

  /// Hair/crest silhouette. For the Vinari this is a luminous drift rather than
  /// hair, and the palette entry reflects that. For the Duran it is a chitin
  /// crest — they are scaled, not hirsute.
  final int hair;

  /// Horn or antenna shape. Duran only; the other species ignore it.
  final int horns;

  /// Eye shape — round, narrow, or angular.
  final int eyes;

  /// Face markings: `0` is unmarked, `1` and `2` are paint/freckles and
  /// scar/tattoo respectively. Only the Duran and Traders use this axis — the
  /// Vinari are unmarked by nature.
  ///
  /// [reroll] biases away from `0`, because an unseeded uniform draw made
  /// markings far too rare to be worth having the axis at all.
  final int markings;

  /// Brow and mouth shape: neutral, stern, or faintly amused.
  final int expression;

  // ── Decoupled colours ──────────────────────────────────────────
  //
  // Each is `null` when unset, and `null` means "keep the colour the shape
  // already implied". That matters: before these existed, `hair` chose a
  // hairstyle *and* its colour, `eyes` chose a shape *and* an iris colour, and
  // `markings` chose a pattern *and* a pigment — so 3 shapes gave 3 looks
  // instead of 9. A null here reproduces the old coupled behaviour exactly,
  // which is what keeps every pre-existing save rendering unchanged.
  //
  // Bounds match the shape axes (see `AvatarCatalog.variantCount`); an
  // out-of-range value is coerced to null on decode rather than clamped, so a
  // corrupt save falls back to the coupled default instead of silently snapping
  // to an arbitrary option.

  /// Hair / crest / drift colour. `null` follows [hair].
  final int? hairColor;

  /// Iris colour. `null` follows [eyes].
  final int? eyeColor;

  /// Marking pigment. `null` follows [markings].
  final int? markingColor;

  /// Garment trim and accent colour. `null` derives a trim from [outfitTone].
  final int? trimColor;

  /// Worn headgear: 0 none, 1 comms headset, 2 goggles. `null` keeps the legacy
  /// coupling to [outfit] (1 -> headset, 2 -> goggles, else none), so adding
  /// this slot did not re-dress anyone's existing pilot.
  final int? gear;

  /// Environment behind the pilot: an index into the species' backdrop list
  /// (Duran forge glow / ember field / void, Vinari aurora / nebula / deep
  /// drift, Terran hangar / starfield / viewport).
  ///
  /// `null` renders the original single faction bloom, byte-identical to every
  /// portrait saved before this slot existed. Unlike the colour slots this has
  /// no legacy *coupling* to resolve — the old backdrop was not tied to any
  /// other axis — so there is no `effectiveBackdrop` getter; a null simply means
  /// "draw the bloom".
  final int? backdrop;

  /// Number of skin tones available per species.
  ///
  /// Mirrors the list lengths in `AvatarPalette`, but lives in the model so
  /// [sanitized] does not have to import a widget library. A test asserts the
  /// two stay in step.
  static const int toneCount = 6;

  static const AvatarStyle neutral = AvatarStyle(
    tone: 0,
    outfit: 0,
    outfitTone: 0,
    hair: 0,
    horns: 0,
    eyes: 0,
    markings: 0,
    expression: 0,
  );

  /// How many worn-headgear options exist (none / headset / goggles).
  static const int gearCount = 3;

  /// How many backdrop options exist per species. Kept in the model for the same
  /// reason as [toneCount]: [sanitized] must not import a widget library. A
  /// test asserts this matches the lists in `AvatarPalette`.
  static const int backdropCount = 3;

  /// True when this style overrides nothing beyond its shape axes, i.e. it is
  /// indistinguishable from the catalogue's own seeded look for this portrait.
  bool get isCoupled =>
      hairColor == null &&
      eyeColor == null &&
      markingColor == null &&
      trimColor == null &&
      gear == null &&
      backdrop == null;

  /// Every axis re-rolled at once. This is what the Reroll action calls, and it
  /// is why there is no separate Random action: re-rolling covers portrait choice
  /// too when the caller also swaps the id.
  factory AvatarStyle.reroll(int Function(int max) nextInt) =>
      AvatarStyle.neutral.rerolled(nextInt);

  /// Re-rolls every axis that is not in [locked], keeping the rest exactly as
  /// they are.
  ///
  /// Locks are a **transient editor concern**, deliberately not persisted: they
  /// describe how a player wants to re-roll, not what their pilot is. A lock
  /// that survived Save would describe a decision the player has already made,
  /// and would add schema for it.
  ///
  /// A locked axis keeps its *current* value, including a `null` colour slot.
  /// Locking is therefore orthogonal to the null-means-coupled rule: locking a
  /// dye that is still coupled locks the coupled value, and unlocking it lets
  /// the next roll decouple it again.
  AvatarStyle rerolled(
    int Function(int max) nextInt, {
    Set<AxisStyleAxis> locked = const {},
  }) {
    int pick() => nextInt(AvatarCatalog.variantCount);
    // A decoupled colour stays null roughly one roll in four, so some pilots
    // keep the colour their shape implies. That variety is worth having, and it
    // also keeps a coupled look reachable without needing a Reset button.
    int? maybeColor() => nextInt(4) == 0 ? null : pick();
    bool hold(AxisStyleAxis axis) => locked.contains(axis);
    return AvatarStyle(
      tone: hold(AxisStyleAxis.tone) ? tone : nextInt(toneCount),
      outfit: hold(AxisStyleAxis.outfit) ? outfit : pick(),
      outfitTone: hold(AxisStyleAxis.outfitTone) ? outfitTone : pick(),
      hair: hold(AxisStyleAxis.hair) ? hair : pick(),
      horns: hold(AxisStyleAxis.horns) ? horns : pick(),
      eyes: hold(AxisStyleAxis.eyes) ? eyes : pick(),
      // Unmarked roughly one roll in four. A uniform draw left markings
      // appearing too rarely to be worth the axis existing.
      markings: hold(AxisStyleAxis.markings)
          ? markings
          : (nextInt(4) == 0 ? 0 : nextInt(2) + 1),
      expression: hold(AxisStyleAxis.expression) ? expression : pick(),
      hairColor: hold(AxisStyleAxis.hairColor) ? hairColor : maybeColor(),
      eyeColor: hold(AxisStyleAxis.eyeColor) ? eyeColor : maybeColor(),
      markingColor:
          hold(AxisStyleAxis.markingColor) ? markingColor : maybeColor(),
      trimColor: hold(AxisStyleAxis.trimColor) ? trimColor : maybeColor(),
      gear: hold(AxisStyleAxis.gear)
          ? gear
          : (nextInt(4) == 0 ? null : nextInt(gearCount)),
      backdrop: hold(AxisStyleAxis.backdrop)
          ? backdrop
          : (nextInt(4) == 0 ? null : nextInt(backdropCount)),
    );
  }

  /// Resolves [gear] against the legacy coupling, so a null slot behaves as it
  /// did before the slot existed.
  int get effectiveGear {
    final g = gear;
    if (g != null) return g;
    return switch (outfit) {
      1 => 1, // headset
      2 => 2, // goggles
      _ => 0, // none
    };
  }

  /// Clamps every axis into range, so a hand-edited or corrupt save still
  /// produces a drawable portrait.
  AvatarStyle sanitized() {
    int clamp(int v) => v.clamp(0, AvatarCatalog.variantCount - 1);
    // A nullable slot coerces an out-of-range value to null rather than clamping,
    // so a corrupt save falls back to the shape's own default instead of
    // snapping to an arbitrary end of the list. Applies to the colour slots and
    // to `gear`/`backdrop` alike.
    int? slot(int? v) =>
        (v == null || v < 0 || v >= AvatarCatalog.variantCount) ? null : v;
    return AvatarStyle(
      tone: tone.clamp(0, toneCount - 1),
      outfit: clamp(outfit),
      outfitTone: clamp(outfitTone),
      hair: clamp(hair),
      horns: clamp(horns),
      eyes: clamp(eyes),
      markings: clamp(markings),
      expression: clamp(expression),
      hairColor: slot(hairColor),
      eyeColor: slot(eyeColor),
      markingColor: slot(markingColor),
      trimColor: slot(trimColor),
      gear: (gear != null && gear! >= 0 && gear! < gearCount) ? gear : null,
      backdrop:
          (backdrop != null && backdrop! >= 0 && backdrop! < backdropCount)
              ? backdrop
              : null,
    );
  }

  /// Only non-null colour slots are written, so a coupled style produces the
  /// same compact JSON it did before these fields existed.
  Map<String, dynamic> toJson() => {
        'tone': tone,
        'outfit': outfit,
        'outfitTone': outfitTone,
        'hair': hair,
        'horns': horns,
        'eyes': eyes,
        'markings': markings,
        'expression': expression,
        if (hairColor != null) 'hairColor': hairColor,
        if (eyeColor != null) 'eyeColor': eyeColor,
        if (markingColor != null) 'markingColor': markingColor,
        if (trimColor != null) 'trimColor': trimColor,
        if (gear != null) 'gear': gear,
        if (backdrop != null) 'backdrop': backdrop,
      };

  /// Tolerant decode — never throws, always returns a drawable style.
  factory AvatarStyle.fromJson(Map<String, dynamic> json) {
    int read(String key) => json[key] is int ? json[key] as int : 0;
    int? readOrNull(String key) => json[key] is int ? json[key] as int : null;
    return AvatarStyle(
      tone: read('tone'),
      outfit: read('outfit'),
      outfitTone: read('outfitTone'),
      hair: read('hair'),
      horns: read('horns'),
      eyes: read('eyes'),
      markings: read('markings'),
      expression: read('expression'),
      hairColor: readOrNull('hairColor'),
      eyeColor: readOrNull('eyeColor'),
      markingColor: readOrNull('markingColor'),
      trimColor: readOrNull('trimColor'),
      gear: readOrNull('gear'),
      backdrop: readOrNull('backdrop'),
    ).sanitized();
  }

  AvatarStyle copyWith({
    int? tone,
    int? outfit,
    int? outfitTone,
    int? hair,
    int? horns,
    int? eyes,
    int? markings,
    int? expression,
    int? hairColor,
    int? eyeColor,
    int? markingColor,
    int? trimColor,
    int? gear,
    int? backdrop,
    // The nullable slots cannot be cleared by `?? this.x`, so "unset this" is
    // an explicit flag, matching `clearCustomFile` on AvatarSelection.
    bool clearHairColor = false,
    bool clearEyeColor = false,
    bool clearMarkingColor = false,
    bool clearTrimColor = false,
    bool clearGear = false,
    bool clearBackdrop = false,
  }) {
    return AvatarStyle(
      tone: tone ?? this.tone,
      outfit: outfit ?? this.outfit,
      outfitTone: outfitTone ?? this.outfitTone,
      hair: hair ?? this.hair,
      horns: horns ?? this.horns,
      eyes: eyes ?? this.eyes,
      markings: markings ?? this.markings,
      expression: expression ?? this.expression,
      hairColor: clearHairColor ? null : (hairColor ?? this.hairColor),
      eyeColor: clearEyeColor ? null : (eyeColor ?? this.eyeColor),
      markingColor:
          clearMarkingColor ? null : (markingColor ?? this.markingColor),
      trimColor: clearTrimColor ? null : (trimColor ?? this.trimColor),
      gear: clearGear ? null : (gear ?? this.gear),
      backdrop: clearBackdrop ? null : (backdrop ?? this.backdrop),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AvatarStyle &&
      other.tone == tone &&
      other.outfit == outfit &&
      other.outfitTone == outfitTone &&
      other.hair == hair &&
      other.horns == horns &&
      other.eyes == eyes &&
      other.markings == markings &&
      other.expression == expression &&
      other.hairColor == hairColor &&
      other.eyeColor == eyeColor &&
      other.markingColor == markingColor &&
      other.trimColor == trimColor &&
      other.gear == gear &&
      other.backdrop == backdrop;

  @override
  int get hashCode => Object.hash(
      tone,
      outfit,
      outfitTone,
      hair,
      horns,
      eyes,
      markings,
      expression,
      hairColor,
      eyeColor,
      markingColor,
      trimColor,
      gear,
      backdrop);

  @override
  String toString() => 'AvatarStyle(tone: $tone, outfit: $outfit, '
      'outfitTone: $outfitTone, hair: $hair, horns: $horns, eyes: $eyes, '
      'markings: $markings, expression: $expression, hairColor: $hairColor, '
      'eyeColor: $eyeColor, markingColor: $markingColor, trimColor: $trimColor, '
      'gear: $gear)';
}

/// A pilot's chosen portrait, persisted as a **stable catalogue ID** rather
/// than a list index or a display label, so reordering the gallery can never
/// change which portrait a returning player sees.
///
/// Every decode path is total: malformed, legacy, or partially-written JSON
/// resolves to a valid faction default instead of throwing. That matters
/// because this is read during login and on every `players.json` load — a
/// throw here would take a whole account offline over a cosmetic field.
@immutable
class AvatarSelection {
  const AvatarSelection({
    required this.species,
    required this.presentation,
    required this.portraitId,
    this.schemaVersion = currentSchemaVersion,
    this.source = AvatarSource.preset,
    this.customFile,
    this.style,
  });

  /// Bump when the persisted shape changes incompatibly. [fromJson] reads the
  /// stored value and tolerates anything it does not recognise.
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final AvatarSpecies species;
  final AvatarPresentation presentation;

  /// Stable catalogue key, e.g. `duran_male_lancer_01`. Remains meaningful as a
  /// fallback when [source] is [AvatarSource.custom] and the file is lost.
  final String portraitId;

  final AvatarSource source;

  /// Bare filename under the avatar store — never an absolute path. Only
  /// consulted when [source] is [AvatarSource.custom].
  final String? customFile;

  /// Player-chosen customisation, or `null` to accept the catalogue's own
  /// seeded appearance. `null` is the common case and renders identically to
  /// the pre-customisation build, which is what keeps existing saves valid.
  final AvatarStyle? style;

  /// The curated default portrait for [faction].
  factory AvatarSelection.defaultFor(FactionClass faction) {
    final species = AvatarSpecies.forFaction(faction);
    final portrait = AvatarCatalog.defaultFor(species);
    return AvatarSelection(
      species: species,
      presentation: portrait.presentation,
      portraitId: portrait.id,
    );
  }

  /// The style to actually draw: the player's, or the catalogue's seeded style
  /// for this portrait when the player has not customised anything.
  ///
  /// Callers (notably the painter) read this instead of inspecting [style]
  /// themselves, so "unset means seeded" lives in exactly one place.
  AvatarStyle get effectiveStyle =>
      style ?? AvatarCatalog.seededStyleFor(portraitId);

  /// A copy with [newStyle] applied, always re-sanitized so a caller cannot
  /// push out-of-range variants into the persisted state.
  AvatarSelection withStyle(AvatarStyle? newStyle) => copyWith(style: newStyle);

  /// A copy with a freshly re-rolled [AvatarStyle], so the pilot's whole
  /// appearance changes — outfit, hair, eyes, markings, expression, and skin
  /// tone — without changing who they are (same callsign, species, and
  /// presentation).
  ///
  /// Set [newPortrait] to also draw a different catalogue entry; that is what
  /// the gallery's single Reroll action does, and it is why there is no
  /// separate Random action. Set [randomizeStyle] to `false` when the caller has
  /// already rolled a style it wants to keep — otherwise the caller's roll gets
  /// discarded and replaced, which would make the two disagree.
  AvatarSelection randomized({
    required int Function(int max) nextInt,
    bool newPortrait = false,
    bool randomizeStyle = true,
    Set<AxisStyleAxis> locked = const {},
  }) {
    final next = nextInt;
    // Roll from the *current* style rather than from neutral, so a locked axis
    // can be honoured: `AvatarStyle.reroll` starts from neutral and therefore
    // has no existing value to hold on to.
    var result = randomizeStyle
        ? withStyle(effectiveStyle.rerolled(next, locked: locked))
        : this;

    if (newPortrait) {
      final pool =
          AvatarCatalog.forSpecies(species, presentation: presentation);
      if (pool.isNotEmpty) {
        final pick = pool[next(pool.length)];
        if (pick.id != portraitId) {
          result = result.copyWith(
            presentation: pick.presentation,
            portraitId: pick.id,
          );
        }
      }
    }
    return result;
  }

  /// Repairs this selection against [faction].
  ///
  /// The player's faction is the authority on species; a save carrying a
  /// stale or hand-edited portrait (or one left over from a faction change)
  /// is repaired rather than displayed, so a pilot never shows a Duran head on
  /// a Terran account. A custom upload is species-agnostic and survives, but
  /// its preset fallback is re-pointed at the new faction's default.
  AvatarSelection forFaction(FactionClass faction) {
    final target = AvatarSpecies.forFaction(faction);
    if (target == species && AvatarCatalog.isValidFor(species, portraitId)) {
      return this;
    }
    final fallback = AvatarSelection.defaultFor(faction);
    if (source == AvatarSource.custom && customFile != null) {
      return AvatarSelection(
        species: target,
        presentation: presentation,
        portraitId: fallback.portraitId,
        source: AvatarSource.custom,
        customFile: customFile,
        style: style,
      );
    }
    // Keep the player's customisation even though the portrait had to change.
    // Appearance choices are species-agnostic, so silently reverting them
    // would look like the game forgot the player had chosen anything.
    return fallback.copyWith(style: style);
  }

  /// True when this selection can be drawn as-is (a real catalogue entry).
  bool get isRenderable => AvatarCatalog.isValidFor(species, portraitId);

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'species': species.name,
      'presentation': presentation.name,
      'portraitId': portraitId,
      'source': source.name,
      'customFile': customFile,
      'style': style?.toJson(),
    };
  }

  /// Tolerant decode. Never throws.
  ///
  /// A complete, valid payload round-trips exactly. Anything missing,
  /// mistyped, out of date, or pointing at a removed portrait degrades to
  /// [fallbackFaction]'s default — the caller supplies the faction so the
  /// repair lands on the *right* species rather than a fixed one.
  factory AvatarSelection.fromJson(
    Map<String, dynamic> json, {
    FactionClass fallbackFaction = FactionClass.trader,
  }) {
    final species = AvatarSpecies.forFaction(fallbackFaction);
    final fallback = AvatarSelection.defaultFor(fallbackFaction);

    // Preserve an explicitly stored species when it matches the faction; a
    // stored species that contradicts the faction is a stale save, so defer to
    // the faction rather than trusting it.
    final storedSpecies = AvatarSpecies.fromName(json['species']);
    final resolvedSpecies =
        storedSpecies.faction == fallbackFaction ? storedSpecies : species;

    final storedId = json['portraitId'];
    final portraitId = storedId is String &&
            AvatarCatalog.isValidFor(resolvedSpecies, storedId)
        ? storedId
        : fallback.portraitId;

    // `customFile` is a bare filename under the avatar store. A value carrying
    // path separators is not a bare filename — reject it rather than let a
    // crafted save point the renderer outside the store.
    final rawFile = json['customFile'];
    final customFile =
        rawFile is String && _isBareFilename(rawFile) ? rawFile : null;

    final source = AvatarSource.fromName(json['source']);
    // A custom source with no usable file is not renderable; fall back to the
    // preset instead of rendering nothing.
    final resolvedSource = source == AvatarSource.custom && customFile == null
        ? AvatarSource.preset
        : source;

    // A pre-customisation save has no 'style' key, which stays null and is
    // resolved to the catalogue's seeded style on read. A malformed style is
    // sanitized rather than dropped, so a hand-edited save keeps whatever it
    // got right.
    final rawStyle = json['style'];
    final style = rawStyle is Map
        ? AvatarStyle.fromJson(rawStyle.cast<String, dynamic>()).sanitized()
        : null;

    return AvatarSelection(
      schemaVersion: json['schemaVersion'] is int
          ? json['schemaVersion'] as int
          : currentSchemaVersion,
      species: resolvedSpecies,
      presentation: AvatarPresentation.fromName(json['presentation'],
          fallback: fallback.presentation),
      portraitId: portraitId,
      source: resolvedSource,
      // Retained even for a preset source so a pending custom upload can fall
      // back cleanly; the renderer only reads it when source is custom.
      customFile: customFile,
      style: style,
    );
  }

  static bool _isBareFilename(String value) {
    if (value.isEmpty) return false;
    if (value.contains('/') || value.contains(r'\')) return false;
    return value != '.' && value != '..';
  }

  /// The catalogue entry this selection draws, never null — an unknown
  /// portrait degrades to the species default.
  AvatarPortrait get portrait =>
      AvatarCatalog.byId(portraitId) ?? AvatarCatalog.defaultFor(species);

  AvatarSelection copyWith({
    int? schemaVersion,
    AvatarSpecies? species,
    AvatarPresentation? presentation,
    String? portraitId,
    AvatarSource? source,
    String? customFile,
    bool clearCustomFile = false,
    AvatarStyle? style,
    bool clearStyle = false,
  }) {
    return AvatarSelection(
      schemaVersion: schemaVersion ?? this.schemaVersion,
      species: species ?? this.species,
      presentation: presentation ?? this.presentation,
      portraitId: portraitId ?? this.portraitId,
      source: source ?? this.source,
      customFile: clearCustomFile ? null : (customFile ?? this.customFile),
      // Mirrors `customFile`: a value can be replaced, and nulling it out is
      // an explicit `clearStyle` rather than the `??` default. Clearing means
      // "go back to whatever the catalogue seeds", not "no portrait".
      style: clearStyle ? null : (style ?? this.style),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AvatarSelection &&
        other.schemaVersion == schemaVersion &&
        other.species == species &&
        other.presentation == presentation &&
        other.portraitId == portraitId &&
        other.source == source &&
        other.customFile == customFile &&
        other.style == style;
  }

  @override
  int get hashCode => Object.hash(schemaVersion, species, presentation,
      portraitId, source, customFile, style);

  @override
  String toString() => 'AvatarSelection($portraitId, ${presentation.name}, '
      '${source.name}${customFile == null ? '' : ', $customFile'}'
      '${style == null ? '' : ', $style'})';
}
