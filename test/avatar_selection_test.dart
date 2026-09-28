import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';

Player _pilot(
    {FactionClass faction = FactionClass.trader, AvatarSelection? avatar}) {
  return Player(
    name: 'Tester',
    currentSectorId: 1,
    hull: 100,
    maxHull: 100,
    shields: 50,
    maxShields: 50,
    cargoUsed: 0,
    maxCargo: 100,
    cargoSize: 5,
    credits: 1000,
    researchPoints: 0,
    faction: faction,
    avatar: avatar,
  );
}

void main() {
  test('a selection round-trips through JSON exactly', () {
    for (final portrait in AvatarCatalog.portraits) {
      final original = AvatarSelection(
        species: portrait.species,
        presentation: portrait.presentation,
        portraitId: portrait.id,
      );
      final restored = AvatarSelection.fromJson(
        original.toJson(),
        fallbackFaction: portrait.species.faction,
      );

      expect(restored, original,
          reason: 'round-trip must be lossless for ${portrait.id}');
      expect(restored.hashCode, original.hashCode,
          reason: 'hashCode must agree with == for ${portrait.id}');
    }
  });

  test('legacy saves with no avatar key resolve to a faction default', () {
    // Pre-avatar players.json records have no 'avatar' key at all. They must
    // load without a migration pass and still render a real portrait.
    final legacy = _pilot(faction: FactionClass.duran).toJson();
    expect(legacy.containsKey('avatar'), isTrue,
        reason: 'toJson writes the key; remove it to simulate a legacy record');
    legacy.remove('avatar');

    final player = Player.fromJson(legacy);
    expect(player.avatar, isNull,
        reason: 'a legacy record must stay null, not backfilled');
    expect(player.effectiveAvatar.species, AvatarSpecies.duran);
    expect(
      player.effectiveAvatar.portraitId,
      AvatarCatalog.defaultFor(AvatarSpecies.duran).id,
      reason: 'existing accounts get their faction curated default',
    );
    expect(player.effectiveAvatar.isRenderable, isTrue);
  });

  test(
      'a removed portrait id resolves to the faction default instead of throwing',
      () {
    final selection = AvatarSelection.fromJson(
      {
        'schemaVersion': 1,
        'species': 'terran',
        'presentation': 'female',
        'portraitId': 'terran_female_envoy_99', // removed from the catalogue
        'source': 'preset',
      },
      fallbackFaction: FactionClass.trader,
    );

    expect(selection.portraitId,
        AvatarCatalog.defaultFor(AvatarSpecies.terran).id);
    expect(selection.isRenderable, isTrue,
        reason: 'a stale id must never surface as a missing-asset box');
  });

  test('malformed and unknown JSON values never throw', () {
    final garbage = <Map<String, dynamic>>[
      {},
      {'portraitId': 42},
      {'species': 'martian', 'presentation': 'other', 'source': 'telepathy'},
      {'portraitId': null, 'customFile': 7},
      {'schemaVersion': 'one'},
      // A known id paired with a species that contradicts the faction.
      {'species': 'duran', 'portraitId': 'terran_male_broker_01'},
    ];

    for (final json in garbage) {
      for (final faction in FactionClass.values) {
        final selection =
            AvatarSelection.fromJson(json, fallbackFaction: faction);
        expect(selection.isRenderable, isTrue,
            reason: '$json as $faction must still resolve to real art');
        expect(selection.species, AvatarSpecies.forFaction(faction),
            reason: 'the faction is the authority on species');
      }
    }
  });

  test('a non-Map avatar payload is ignored rather than crashing the load', () {
    final json = _pilot(faction: FactionClass.vinari).toJson();
    json['avatar'] = 'not-a-map';

    final player = Player.fromJson(json);
    expect(player.avatar, isNull);
    expect(player.effectiveAvatar.species, AvatarSpecies.vinari);
  });

  test('forFaction repairs a portrait that belongs to another species', () {
    // A Duran portrait on a Terran account — the shape a hand-edited save or a
    // future faction change would produce.
    final mismatched = AvatarSelection(
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.male,
      portraitId: 'duran_male_lancer_01',
    );

    final repaired = mismatched.forFaction(FactionClass.trader);
    expect(repaired.species, AvatarSpecies.terran);
    expect(repaired.isRenderable, isTrue);
    expect(
      AvatarCatalog.byId(repaired.portraitId)!.species,
      AvatarSpecies.terran,
      reason: 'a pilot must never show another species\' art',
    );
  });

  test('forFaction is a no-op for a valid selection of the same faction', () {
    final selection = AvatarSelection(
      species: AvatarSpecies.vinari,
      presentation: AvatarPresentation.female,
      portraitId: 'vinari_female_oracle_02',
    );
    expect(selection.forFaction(FactionClass.vinari), same(selection));
  });

  test('every playable faction has a renderable default of its own species',
      () {
    for (final faction in FactionClass.values) {
      final fallback = AvatarSelection.defaultFor(faction);
      expect(fallback.isRenderable, isTrue,
          reason: '$faction needs a real default portrait');
      // Pirate is the documented exception: it has no species of its own and
      // reuses Terran until pirates become selectable (design doc §11).
      if (faction != FactionClass.pirate) {
        expect(fallback.species.faction, faction,
            reason: '$faction default must belong to $faction');
      }
    }
  });

  test('a custom file with path separators is rejected as a preset', () {
    // The stored reference must be a bare filename; a crafted save must not be
    // able to point the renderer outside the avatar store.
    for (final pathy in [
      '../../etc/passwd',
      'sub/dir/a.png',
      r'C:\avatars\a.png',
      ''
    ]) {
      final selection = AvatarSelection.fromJson(
        {
          'species': 'terran',
          'presentation': 'male',
          'portraitId': 'terran_male_broker_01',
          'source': 'custom',
          'customFile': pathy,
        },
        fallbackFaction: FactionClass.trader,
      );

      expect(selection.source, AvatarSource.preset,
          reason: 'a rejected file must not leave the selection unrenderable');
      expect(selection.customFile, isNull);
    }
  });

  test(
      'a custom source with a bare filename is preserved with its preset fallback',
      () {
    // Uploads are not implemented yet, so AvatarCanvas falls back — but the
    // preset must survive as a valid fallback rather than being lost.
    final selection = AvatarSelection.fromJson(
      {
        'species': 'duran',
        'presentation': 'male',
        'portraitId': 'duran_male_scout_03',
        'source': 'custom',
        'customFile': 'pilot.png',
      },
      fallbackFaction: FactionClass.duran,
    );

    expect(selection.source, AvatarSource.custom);
    expect(selection.customFile, 'pilot.png');
    expect(selection.portraitId, 'duran_male_scout_03',
        reason: 'the preset stays available as the fallback');
  });

  test('the player avatar survives persistence', () {
    final avatar = AvatarSelection(
      species: AvatarSpecies.duran,
      presentation: AvatarPresentation.female,
      portraitId: 'duran_female_seer_03',
    );
    final restored = Player.fromJson(_pilot(
      faction: FactionClass.duran,
      avatar: avatar,
    ).toJson());

    expect(restored.avatar, avatar);
    expect(restored.effectiveAvatar, avatar);
  });

  test('copyWith replaces the portrait and keeps it through further copies',
      () {
    final player = _pilot();
    expect(player.avatar, isNull);

    final withAvatar = player.copyWith(
      avatar: AvatarSelection.defaultFor(FactionClass.duran),
    );
    expect(withAvatar.avatar, isNotNull);
    expect(withAvatar.copyWith(credits: 5).avatar, withAvatar.avatar,
        reason: 'an unrelated copyWith must not drop the portrait');
    expect(withAvatar.copyWith(credits: 5).credits, 5);
  });

  test('pirates resolve to a portrait instead of throwing', () {
    // Faction.forClass(pirate) has no Faction const and throws, so the avatar
    // path must never route through it.
    final selection = AvatarSelection.defaultFor(FactionClass.pirate);
    expect(selection.isRenderable, isTrue);
    expect(selection.species, AvatarSpecies.terran,
        reason: 'pirates reuse Terran until they become selectable');
    expect(
      Player.fromJson(_pilot(faction: FactionClass.pirate).toJson())
          .effectiveAvatar
          .isRenderable,
      isTrue,
    );
  });

  // ── AvatarStyle (customisation) ────────────────────────────────

  test('a selection with a style round-trips losslessly', () {
    final styled = AvatarSelection.defaultFor(FactionClass.duran).copyWith(
      style: const AvatarStyle(
        horns: 0,
        tone: 4,
        outfit: 2,
        outfitTone: 1,
        hair: 2,
        eyes: 1,
        markings: 0,
        expression: 1,
      ),
    );

    final restored = AvatarSelection.fromJson(
      styled.toJson(),
      fallbackFaction: FactionClass.duran,
    );

    expect(restored, styled);
    expect(restored.style, styled.style);
  });

  test('a pre-customisation save keeps a null style and falls back to the seed',
      () {
    // The point of a nullable style: an existing save must keep rendering
    // exactly as before, and must not start carrying invented customisation.
    final json = _pilot(faction: FactionClass.trader).toJson();
    json.remove('style');

    final restored = AvatarSelection.fromJson(json);
    expect(restored.style, isNull,
        reason: 'a save with no style key must not gain one');
    expect(
      restored.effectiveStyle,
      AvatarCatalog.seededStyleFor(restored.portraitId),
      reason: 'an unset style resolves to the catalogue seed',
    );
  });

  test('out-of-range style axes are clamped rather than trusted', () {
    // A hand-edited or corrupt save must not be able to index past the variants
    // or skin tones the painter actually draws.
    final decoded = AvatarStyle.fromJson(const {
      'tone': 99,
      'outfit': -5,
      'outfitTone': 40,
      'hair': 7,
      'horns': 11,
      'eyes': -1,
      'markings': 3,
      'expression': 12,
    });

    expect(decoded.tone, AvatarStyle.toneCount - 1);
    for (final axis in [
      decoded.outfit,
      decoded.outfitTone,
      decoded.hair,
      decoded.horns,
      decoded.eyes,
      decoded.markings,
      decoded.expression,
    ]) {
      expect(axis, inInclusiveRange(0, AvatarCatalog.variantCount - 1));
    }
  });

  test('a malformed style payload never throws', () {
    // Every axis has to tolerate the wrong type, not just a missing key: a
    // hand-edited save must not be able to crash login over a cosmetic field.
    for (final junk in [
      <String, dynamic>{},
      {'tone': 'pale', 'outfit': null, 'hair': [], 'horns': 'none'},
      {'eyes': true, 'expression': 1.5},
      {'tone': 1.9},
    ]) {
      final style = AvatarStyle.fromJson(junk);
      expect(style.tone, inInclusiveRange(0, AvatarStyle.toneCount - 1));
      expect(style.outfit, inInclusiveRange(0, AvatarCatalog.variantCount - 1));
      expect(style.expression,
          inInclusiveRange(0, AvatarCatalog.variantCount - 1));
    }
  });

  test('the player style survives persistence and species repair', () {
    const style = AvatarStyle(
      tone: 3,
      outfit: 1,
      outfitTone: 2,
      hair: 0,
      horns: 1,
      eyes: 2,
      markings: 1,
      expression: 2,
    );
    final player = _pilot(
      faction: FactionClass.vinari,
      avatar: AvatarSelection.defaultFor(FactionClass.vinari)
          .copyWith(style: style),
    );

    final restored = Player.fromJson(player.toJson());
    expect(restored.effectiveAvatar.style, style);

    // A faction change keeps the player's customisation while re-pointing the
    // portrait at the new species. The style is interpreted per species, so it
    // stays valid across a change of appearance rules.
    final moved =
        restored.copyWith(faction: FactionClass.duran).effectiveAvatar;
    expect(moved.style, style, reason: 'customisation is faction-agnostic');
    expect(moved.species, AvatarSpecies.duran);
    expect(AvatarCatalog.byId(moved.portraitId)!.species, AvatarSpecies.duran);
  });

  test('randomized changes every appearance axis but never the pilot', () {
    // The distinction that matters: a re-roll must alter appearance without
    // silently swapping who the player is.
    final base = AvatarSelection.defaultFor(FactionClass.trader);

    var seed = 999;
    int nextInt(int max) {
      seed = (seed * 1103515245 + 12345) & 0x7FFFFFFF;
      return (seed >> 8) % max;
    }

    final rolls = List.generate(20, (_) => base.randomized(nextInt: nextInt));
    for (final rolled in rolls) {
      expect(rolled.portraitId, base.portraitId,
          reason: 'default re-roll must keep the pilot');
      expect(rolled.species, base.species);
      expect(rolled.presentation, base.presentation);
      expect(rolled.style, isNotNull);
      expect(rolled.style!.sanitized(), rolled.style);
    }
    expect(rolls.map((r) => r.style).toSet().length, greaterThan(1),
        reason: 're-rolling must actually produce different looks');
  });

  test('newPortrait re-rolls the portrait too, staying inside the catalogue',
      () {
    final base = AvatarSelection.defaultFor(FactionClass.duran);
    final rng = math.Random(7);
    final ids = <String>{base.portraitId};
    final styles = <AvatarStyle>{};

    for (var i = 0; i < 30; i++) {
      final rolled = base.randomized(
        nextInt: rng.nextInt,
        newPortrait: true,
      );
      expect(rolled.isRenderable, isTrue);
      expect(rolled.species, AvatarSpecies.duran);
      expect(rolled.presentation, base.presentation);
      ids.add(rolled.portraitId);
      styles.add(rolled.style!);
    }

    expect(ids.length, greaterThan(1),
        reason: 'newPortrait must actually move between catalogue entries');
    expect(styles.length, greaterThan(1),
        reason: 'the appearance must vary too');
  });

  test('randomizeStyle false keeps a caller-supplied style', () {
    // The gallery rolls a style and then re-picks the portrait from the same
    // roll; without this flag the style it just rolled would be discarded.
    const wanted = AvatarStyle(
      tone: 2,
      outfit: 1,
      outfitTone: 0,
      hair: 2,
      horns: 2,
      eyes: 0,
      markings: 2,
      expression: 1,
    );
    final rolled = AvatarSelection.defaultFor(FactionClass.vinari)
        .copyWith(style: wanted)
        .randomized(
          nextInt: math.Random(3).nextInt,
          randomizeStyle: false,
          newPortrait: true,
        );

    expect(rolled.style, wanted);
  });

  test('clearStyle falls back to the seeded look without losing the portrait',
      () {
    final styled = AvatarSelection.defaultFor(FactionClass.duran).copyWith(
      style: const AvatarStyle(
        tone: 5,
        horns: 0,
        outfit: 2,
        outfitTone: 2,
        hair: 1,
        eyes: 1,
        markings: 0,
        expression: 0,
      ),
    );

    final cleared = styled.copyWith(clearStyle: true);
    expect(cleared.style, isNull);
    expect(cleared.portraitId, styled.portraitId);
    expect(cleared.effectiveStyle,
        AvatarCatalog.seededStyleFor(styled.portraitId));
  });

  // ── Decoupled colour slots ──────────────────────────────────────

  test('a null colour slot reproduces the old coupled colour exactly', () {
    // The compatibility guarantee: a save written before these slots existed
    // must render identically, so each resolver's null branch has to equal the
    // shape-keyed list it replaced.
    for (final species in AvatarSpecies.values) {
      for (var shape = 0; shape < AvatarCatalog.variantCount; shape++) {
        expect(AvatarPalette.hair(species, shape, null),
            AvatarPalette.legacyHair(species, shape),
            reason: '$species hair \$shape must be unchanged when unset');
        expect(AvatarPalette.eye(species, shape, null),
            AvatarPalette.legacyEye(species, shape));
        expect(AvatarPalette.markingPigment(species, shape, null),
            AvatarPalette.legacyMarkingPigment(species, shape));
        expect(AvatarPalette.trim(species, shape, null),
            AvatarPalette.outfitTrim(species, shape));
      }
    }
  });

  test('a coupled style writes no colour keys, so old JSON is unchanged', () {
    final coupled = AvatarStyle(
      tone: 2,
      outfit: 1,
      outfitTone: 0,
      hair: 1,
      horns: 0,
      eyes: 2,
      markings: 1,
      expression: 0,
    );
    expect(coupled.isCoupled, isTrue);
    for (final key in [
      'hairColor',
      'eyeColor',
      'markingColor',
      'trimColor',
      'gear',
    ]) {
      expect(coupled.toJson().containsKey(key), isFalse,
          reason: '$key should be omitted while unset');
    }
    // And it must still round-trip losslessly.
    expect(AvatarStyle.fromJson(coupled.toJson()), coupled);
  });

  test('decoupled colours round-trip and are part of equality', () {
    final styled = AvatarStyle(
      tone: 1,
      outfit: 0,
      outfitTone: 2,
      hair: 1,
      horns: 2,
      eyes: 0,
      markings: 1,
      expression: 2,
      hairColor: 2,
      eyeColor: 1,
      markingColor: 0,
      trimColor: 2,
      gear: 1,
      backdrop: 2,
    );
    expect(styled.isCoupled, isFalse);

    final restored = AvatarStyle.fromJson(styled.toJson());
    expect(restored, styled);
    expect(restored.hairColor, 2);
    expect(restored.gear, 1);
    // Equality has to include the colour slots, or a style-only change in the
    // editor would compare equal and never be saved.
    expect(styled.copyWith(eyeColor: 0), isNot(styled));
  });

  test('an out-of-range colour coerces to null instead of clamping', () {
    final decoded = AvatarStyle.fromJson(const {
      'tone': 1,
      'outfit': 0,
      'outfitTone': 0,
      'hair': 0,
      'horns': 0,
      'eyes': 0,
      'markings': 0,
      'expression': 0,
      'hairColor': 99,
      'eyeColor': -3,
      'trimColor': 'gold',
      'gear': 77,
      'backdrop': 12,
    });
    // Null means "fall back to the shape's own colour", which is a valid look.
    // Clamping would have snapped a corrupt value to an arbitrary end of list.
    expect(decoded.hairColor, isNull);
    expect(decoded.eyeColor, isNull);
    expect(decoded.trimColor, isNull);
    expect(decoded.gear, isNull);
    expect(decoded.backdrop, isNull);
    expect(decoded.isCoupled, isTrue);
  });

  test('clear flags unset a colour slot without touching the others', () {
    final styled = AvatarStyle(
      tone: 0,
      outfit: 0,
      outfitTone: 0,
      hair: 0,
      horns: 0,
      eyes: 0,
      markings: 0,
      expression: 0,
      hairColor: 1,
      eyeColor: 2,
    );
    final cleared = styled.copyWith(clearHairColor: true);
    expect(cleared.hairColor, isNull);
    expect(cleared.eyeColor, 2, reason: 'other slots must survive');
  });

  test('a null gear slot keeps the legacy outfit coupling', () {
    AvatarStyle withOutfit(int o) => AvatarStyle(
          tone: 0,
          outfit: o,
          outfitTone: 0,
          hair: 0,
          horns: 0,
          eyes: 0,
          markings: 0,
          expression: 0,
        );
    expect(withOutfit(0).effectiveGear, 0, reason: 'suit wore nothing');
    expect(withOutfit(1).effectiveGear, 1, reason: 'coat wore a headset');
    expect(withOutfit(2).effectiveGear, 2, reason: 'rig wore goggles');
    // An explicit slot overrides the coupling, which is the whole point of it.
    expect(withOutfit(1).copyWith(gear: 2).effectiveGear, 2);
    expect(withOutfit(1).copyWith(gear: 0).effectiveGear, 0);
  });

  test('the backdrop slot round-trips, clears, and counts as an override', () {
    final styled = AvatarStyle.neutral.copyWith(backdrop: 1);
    expect(styled.backdrop, 1);
    expect(styled.isCoupled, isFalse,
        reason: 'choosing a backdrop is an override, so the style is no '
            'longer indistinguishable from the catalogue seed');
    expect(AvatarStyle.fromJson(styled.toJson()), styled);
    expect(AvatarStyle.fromJson(styled.toJson()).backdrop, 1);
    // Equality has to include it, or a backdrop change in the editor would
    // compare equal and never be saved.
    expect(styled.copyWith(backdrop: 2), isNot(styled));
    expect(styled.copyWith(clearBackdrop: true).backdrop, isNull);
    expect(styled.copyWith(clearBackdrop: true).isCoupled, isTrue);
  });

  test('an out-of-range backdrop coerces to null, not to an end of the list',
      () {
    // Clamping would silently pick backdrop 0 for a corrupt save. Null means
    // "the legacy bloom", which is a valid look and the safest fallback.
    for (final bad in [-1, 3, 99]) {
      final decoded = AvatarStyle.fromJson({
        'tone': 0,
        'outfit': 0,
        'outfitTone': 0,
        'hair': 0,
        'horns': 0,
        'eyes': 0,
        'markings': 0,
        'expression': 0,
        'backdrop': bad,
      });
      expect(decoded.backdrop, isNull, reason: 'backdrop $bad must coerce');
    }
    // In-range values survive untouched.
    for (var good = 0; good < AvatarStyle.backdropCount; good++) {
      final kept = AvatarStyle.fromJson({
        'tone': 0,
        'outfit': 0,
        'outfitTone': 0,
        'hair': 0,
        'horns': 0,
        'eyes': 0,
        'markings': 0,
        'expression': 0,
        'backdrop': good,
      });
      expect(kept.backdrop, good);
    }
  });

  test('re-rolls vary the colour slots but leave some pilots coupled', () {
    var seed = 555;
    int nextInt(int max) {
      seed = (seed * 16807) % 0x7FFFFFFF;
      return seed % max;
    }

    final rolls = List.generate(120, (_) => AvatarStyle.reroll(nextInt));
    for (final r in rolls) {
      final cleaned = r.sanitized();
      expect(cleaned, r, reason: 'a re-rolled style must already be in range');
      if (cleaned.hairColor != null) {
        expect(cleaned.hairColor,
            inInclusiveRange(0, AvatarCatalog.variantCount - 1));
      }
      if (cleaned.gear != null) {
        expect(cleaned.gear, inInclusiveRange(0, AvatarStyle.gearCount - 1));
      }
      if (cleaned.backdrop != null) {
        expect(cleaned.backdrop,
            inInclusiveRange(0, AvatarStyle.backdropCount - 1));
      }
    }
    // Every slot must be seen both set and unset across the sample. Asserting
    // "at least one fully coupled roll" instead would be a ~1-in-100 flake.
    for (final read in <int? Function(AvatarStyle)>[
      (s) => s.hairColor,
      (s) => s.eyeColor,
      (s) => s.markingColor,
      (s) => s.trimColor,
      (s) => s.gear,
      (s) => s.backdrop,
    ]) {
      final values = rolls.map(read).toList();
      expect(values.where((v) => v == null).length, greaterThan(0),
          reason: 'a nullable slot must sometimes stay coupled');
      expect(values.where((v) => v != null).toSet().length, greaterThan(1),
          reason: 'a nullable slot must actually vary');
    }
  });

  // ── Per-axis locks ───────────────────────────────────────────────

  test('a re-roll keeps every locked axis and moves every unlocked one', () {
    // A generator that always returns the *last* index, against a base whose
    // every axis is the *first*. So any axis that gets rolled is guaranteed to
    // differ, and an assertion of the form "unlocked axes must move" is
    // deterministic rather than true 3 times in 4.
    int nextInt(int max) => max - 1;

    for (final locked in <Set<AxisStyleAxis>>[
      {},
      {AxisStyleAxis.tone},
      {AxisStyleAxis.backdrop},
      {AxisStyleAxis.eyeColor, AxisStyleAxis.hair},
      AxisStyleAxis.values.toSet(),
    ]) {
      final base = AvatarStyle.neutral;
      expect(base.tone, 0);
      final rolled = base.rerolled(nextInt, locked: locked);

      void expectHeld(String what, int? got, int? want) {
        if (locked.contains(_axisOf(what))) {
          expect(got, want, reason: '$what is locked so must be held');
        } else {
          expect(got, isNot(want), reason: '$what is unlocked so must move');
        }
      }

      expectHeld('tone', rolled.tone, base.tone);
      expectHeld('outfit', rolled.outfit, base.outfit);
      expectHeld('outfitTone', rolled.outfitTone, base.outfitTone);
      expectHeld('hair', rolled.hair, base.hair);
      expectHeld('horns', rolled.horns, base.horns);
      expectHeld('eyes', rolled.eyes, base.eyes);
      expectHeld('markings', rolled.markings, base.markings);
      expectHeld('expression', rolled.expression, base.expression);
      expectHeld('hairColor', rolled.hairColor, base.hairColor);
      expectHeld('eyeColor', rolled.eyeColor, base.eyeColor);
      expectHeld('markingColor', rolled.markingColor, base.markingColor);
      expectHeld('trimColor', rolled.trimColor, base.trimColor);
      expectHeld('gear', rolled.gear, base.gear);
      expectHeld('backdrop', rolled.backdrop, base.backdrop);

      if (locked.length == AxisStyleAxis.values.length) {
        expect(rolled, base, reason: 'locking every axis must be a no-op');
      }
    }
  });

  test('locking a coupled colour slot holds the coupled value', () {
    var seed = 99;
    int nextInt(int max) {
      seed = (seed * 16807) % 0x7FFFFFFF;
      return seed % max;
    }

    // A null dye is the "follows the shape" value. Locking it must hold the
    // null, not roll a new colour — locking is orthogonal to the
    // null-means-coupled rule.
    final coupled = AvatarStyle.neutral.copyWith(clearEyeColor: true);
    expect(coupled.eyeColor, isNull);

    final held = coupled.rerolled(nextInt, locked: {AxisStyleAxis.eyeColor});
    expect(held.eyeColor, isNull);

    // Unlocking it lets the roll decouple it again. The roll leaves null one
    // time in four, so sample until it is not.
    var sawDecoupled = false;
    for (var i = 0; i < 40 && !sawDecoupled; i++) {
      final free = coupled.rerolled(nextInt);
      if (free.eyeColor != null) sawDecoupled = true;
    }
    expect(sawDecoupled, isTrue,
        reason: 'an unlocked colour slot must be free to become decoupled');
  });

  test('locks are transient: they never enter the persisted style', () {
    // The whole point of keeping them out of the model. If this ever fails, a
    // lock has been added to the schema and will outlive the decision it
    // described.
    final rolled = AvatarStyle.neutral.rerolled(
      (max) => 0,
      locked: AxisStyleAxis.values.toSet(),
    );
    final json = rolled.toJson();
    expect(json.containsKey('locked'), isFalse);
    expect(json.values.any((v) => v is List), isFalse,
        reason: 'the style must stay a flat set of ints');
    for (final key in ['lock', 'locks', 'lockedAxes', 'pinned']) {
      expect(json.containsKey(key), isFalse);
    }
    // A round trip cannot invent one either.
    expect(AvatarStyle.fromJson(json), rolled);
  });

  test(
      'randomized rolls from the current style so locks have something to hold',
      () {
    // Same forced generator as the test above, so "unlocked moved" is
    // deterministic rather than true 3 times in 4.
    int nextInt(int max) => max - 1;

    final portrait = AvatarCatalog.defaultFor(AvatarSpecies.duran);
    final base = AvatarSelection(
      species: portrait.species,
      presentation: portrait.presentation,
      portraitId: portrait.id,
      style: AvatarStyle.neutral.copyWith(
        tone: 5,
        backdrop: 1,
        gear: 2,
      ),
    );

    final rolled = base.randomized(
      nextInt: nextInt,
      newPortrait: false,
      locked: const {
        AxisStyleAxis.tone,
        AxisStyleAxis.backdrop,
        AxisStyleAxis.gear
      },
    );
    expect(rolled.style!.tone, 5);
    expect(rolled.style!.backdrop, 1);
    expect(rolled.style!.gear, 2);
    // Unlocked axes moved. These were 0 and the generator always returns the last
    // index, so neither can pass by luck.
    expect(rolled.style!.outfit, isNot(0));
    expect(rolled.style!.hair, isNot(0));
  });

  test('randomized with a null style still honours locks against the seed', () {
    // A legacy save opens with `style: null`, so the axes are the catalogue
    // seed's. A lock there must hold the seed value, not a fresh roll.
    var seed = 31;
    int nextInt(int max) {
      seed = (seed * 16807) % 0x7FFFFFFF;
      return seed % max;
    }

    final legacy = AvatarSelection.defaultFor(FactionClass.duran)
        .copyWith(clearStyle: true);
    expect(legacy.style, isNull);
    final seedTone = legacy.portrait.seededStyle.tone;

    final rolled = legacy.randomized(
      nextInt: nextInt,
      newPortrait: false,
      locked: const {AxisStyleAxis.tone},
    );
    expect(rolled.style!.tone, seedTone,
        reason: 'a locked axis on a legacy save holds the seed value');
  });
}

/// Maps an axis name in a failure message back to its enum, so the assertion
/// above can be written as readable strings.
AxisStyleAxis _axisOf(String name) =>
    AxisStyleAxis.values.firstWhere((a) => a.name == name);
