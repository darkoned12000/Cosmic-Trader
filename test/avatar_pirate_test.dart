import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

/// Perceptual luminance. `Color.computeLuminance` rather than an average of the
/// channels, because green contributes far more to perceived brightness than
/// blue — a mean-channel "darkness" check would pass a colour that reads bright.
double _lum(Color c) => c.computeLuminance();

/// Mean luminance across a dye list.
double _meanLum(List<Color> list) =>
    list.map(_lum).reduce((a, b) => a + b) / list.length;

void main() {
  group('the pirate affiliation', () {
    test('is not a species', () {
      // The whole point of the design: a pirate is a defector, not a race. If a
      // pirate ever needed an `AvatarSpecies` of its own, the lore would be
      // wrong and every pirate would share one silhouette and one palette — the
      // exact variety problem the Vinari axis fix had to undo.
      expect(AvatarSpecies.values, hasLength(3));
      expect(FactionClass.values, hasLength(4));
      // Pirates are not something a player can join, so they never reach a
      // player's saved selection at all.
      expect(FactionClass.selectable, isNot(contains(FactionClass.pirate)));
      expect(FactionClass.pirate.isSelectable, isFalse);
      expect(
        FactionClass.selectable,
        FactionClass.values.where((f) => f != FactionClass.pirate).toList(),
      );
    });

    test('is not persisted on a selection', () {
      // A player selection has no affiliation field and must not grow one: a
      // pirate is derived per-NPC from an id, so there is nothing to store and
      // nothing to migrate.
      //
      // Asserted on the **serialised keys**, not on some unrelated property. The
      // first version asserted `defaultFor(...).style == null`, which is true
      // whether or not an affiliation field exists — Dart offers no runtime way to
      // assert a field is absent without reflection, so the test was named after an
      // invariant it did not touch. The keys can see one, and a real guard is the
      // type system refusing to compile a reference to it.
      final json = AvatarSelection.defaultFor(FactionClass.trader).toJson();
      expect(json.keys, isNot(contains('affiliation')));
      expect(json.containsKey('style'), isTrue,
          reason: 'sanity: the key set is being inspected at all');
      // And the round trip must not invent one either.
      expect(AvatarSelection.fromJson(json).toJson().keys,
          isNot(contains('affiliation')));
    });
  });

  group('pirate palette', () {
    test('garment is darker than native for every species and variant', () {
      for (final species in AvatarSpecies.values) {
        for (var variant = 0; variant < AvatarCatalog.variantCount; variant++) {
          final native = AvatarPalette.outfit(species, variant);
          final pirate = AvatarPalette.outfit(species, variant,
              AvatarPresentation.neutral, AvatarAffiliation.pirate);
          expect(_lum(pirate), lessThan(_lum(native)),
              reason: '$species variant $variant: a pirate should be wearing '
                  'darker cloth than a faction member, not a brighter one');
          // And it must be a *different* colour, not merely a shade of the same.
          expect(pirate, isNot(native));
        }
      }
    });

    test(
        'a pirate trim is darker than issued trim AND visible on its own cloth',
        () {
      // Two properties, because they fail independently and the second is the one
      // a viewer can see.
      //
      // 1. Darker than native trim. Previously asserted as `lessThanOrEqualTo`,
      //    which was **too weak to catch the bug it existed for**: the trim
      //    derivation was reading `base = outfit(...)` at the default native
      //    affiliation, so pirate trim came out *bit-for-bit equal* to native trim
      //    and the `<=` sailed through. Strict `<` now.
      // 2. Contrast against the pirate's **own** garment, which is what decides
      //    whether the trim reads at all. The first version of the palette lerped
      //    native trim toward black, which satisfied (1) perfectly while putting
      //    cloth-to-trim at 1.15:1 — worse than the native baseline in all nine
      //    combinations, and the trim all but vanished.
      for (final species in AvatarSpecies.values) {
        for (var variant = 0; variant < AvatarCatalog.variantCount; variant++) {
          final pirateTrim = AvatarPalette.outfitTrim(
              species, variant, AvatarAffiliation.pirate);
          final nativeTrim = AvatarPalette.outfitTrim(species, variant);
          final pirateCloth = AvatarPalette.outfit(species, variant,
              AvatarPresentation.neutral, AvatarAffiliation.pirate);
          final nativeCloth = AvatarPalette.outfit(species, variant);

          expect(_lum(pirateTrim), lessThan(_lum(nativeTrim)),
              reason: '$species variant $variant: pirate trim ($pirateTrim) is '
                  'not darker than issued trim ($nativeTrim). Equal counts as a '
                  'failure: an identical trim means the affiliation never reached '
                  'the derivation');

          // The property that matters. A peer review is right that a trim-vs-trim
          // comparison cannot see this, and that it is the one that determines
          // whether the garment reads.
          final ratio = AvatarPalette.contrast(pirateTrim, pirateCloth);
          expect(ratio, greaterThan(1.5),
              reason: '$species variant $variant: pirate trim $pirateTrim on '
                  'pirate cloth $pirateCloth is only ${ratio.toStringAsFixed(2)}:1 '
                  'and will not read');

          // And it should not be *better* than issued trim, or the affiliation
          // stops reading as a downgrade.
          expect(
              ratio,
              lessThanOrEqualTo(
                  AvatarPalette.contrast(nativeTrim, nativeCloth) + 0.35),
              reason: '$species variant $variant: pirate trim is a clearer '
                  'contrast than issued trim, so it does not read as salvage');
        }
      }
    });

    test('hair dye reads darker on average, per species', () {
      // Asserted on the mean, not index by index. A pirate is bleached as often
      // as they are sun-darkened, so one dye is legitimately lighter than the
      // native equivalent — the palette as a whole is the darker one.
      for (final species in AvatarSpecies.values) {
        expect(
          _meanLum(AvatarPalette.pirateHairColours(species)),
          lessThan(_meanLum(AvatarPalette.hairColours(species))),
          reason: '$species: pirate hair should be darker on average',
        );
      }
    });

    test('marking pigment is a scar tone, not faction colour and not native',
        () {
      for (final species in AvatarSpecies.values) {
        for (var i = 0; i < AvatarCatalog.variantCount; i++) {
          final pirate = AvatarPalette.pirateMarkingColours(species)[i];
          expect(pirate, isNot(AvatarPalette.markingColours(species)[i]),
              reason: '$species pigment $i should differ from the native one');
          // The rule that faction colour never reaches skin. A pirate's marks
          // read as damage; in faction pigment they would read as a livery.
          expect(pirate, isNot(factionColor(FactionClass.pirate)),
              reason: '$species pigment $i is the faction colour');
          expect(pirate, isNot(factionColor(species.faction)),
              reason: '$species pigment $i is the species faction colour');
        }
      }
    });

    test('a pirate mark stays legible on every skin tone', () {
      // The pigment tables cannot serve six tones on their own. Measured across
      // every species' own table, the worst pigment-on-skin pair is **1.02:1** —
      // the mark is drawn and completely invisible. A dark scar on dark skin and a
      // pale one on pale skin are the two cases that matter, and a static table
      // gets at most one of them right.
      //
      // `markingPigment` takes the skin for exactly this. Natives keep the table
      // as authored so no saved portrait moves; the same weakness is real for them
      // and is separate work, because fixing it repaints every portrait that has
      // markings.
      for (final species in AvatarSpecies.values) {
        for (var tone = 0;
            tone < AvatarPalette.skinFor(species).length;
            tone++) {
          final skin = AvatarPalette.skin(species, tone);
          // `dye` is the index that actually selects the table entry; the
          // pattern variant is only a fallback when the dye is null, and it is
          // 1 or 2 in practice because 0 means unmarked. A peer review caught this
          // loop passing `pigment + 1` and so reaching a pattern variant of 3,
          // which no generated style can produce — coverage of an impossible
          // input dressed up as coverage.
          for (var dye = 0; dye < 3; dye++) {
            final resolved = AvatarPalette.markingPigment(
                species, 1, dye, AvatarAffiliation.pirate, skin);
            expect(AvatarPalette.contrast(resolved, skin), greaterThan(1.5),
                reason: '$species tone $tone dye $dye resolves to $resolved on '
                    '$skin, which is too close to read');
          }
        }
      }
    });

    test('a null dye still resolves to pirate pigment, not the native colour',
        () {
      // The `null`-means-legacy rule says a null dye falls back to the shape's
      // own colour so pre-slot saves render unchanged. A pirate opts out: their
      // style is derived per-NPC and never persisted, so there is no older
      // pirate build to stay compatible with, and the native colour is exactly
      // the faction identity the affiliation exists to replace.
      for (final species in AvatarSpecies.values) {
        for (var shape = 0; shape < AvatarCatalog.variantCount; shape++) {
          expect(
            AvatarPalette.hair(species, shape, null, AvatarAffiliation.pirate),
            isNot(AvatarPalette.hair(species, shape, null)),
            reason: '$species shape $shape fell through to the native hair '
                'colour, so a pirate would be wearing their old faction palette',
          );
          expect(
            AvatarPalette.markingPigment(
                species, shape, null, AvatarAffiliation.pirate),
            isNot(AvatarPalette.markingPigment(species, shape, null)),
            reason: '$species shape $shape fell through to the native pigment',
          );
        }
      }
    });

    test('skin and eyes are untouched — a pirate is still their own species',
        () {
      // The guard against the affiliation quietly becoming a fourth race. Darker
      // *cloth* is defection; darker *skin* would be inventing biology.
      //
      // Pinned values, not a comparison of a call to itself. `skin` and `eye` take
      // no affiliation parameter at all, so the meaningful assertion is that the
      // species tables they read are still the ones the lore test
      // (`avatar_catalog_test.dart`) describes. A pirate branch would have to
      // change one of these to have any effect, and that is what fails here.
      expect(AvatarPalette.skinFor(AvatarSpecies.terran),
          AvatarPalette.terranSkin);
      expect(AvatarPalette.skinFor(AvatarSpecies.vinari),
          AvatarPalette.vinariSkin);
      expect(
          AvatarPalette.skinFor(AvatarSpecies.duran), AvatarPalette.duranSkin);

      expect(AvatarPalette.terranSkin.first, const Color(0xFFF6DCC8));
      expect(AvatarPalette.terranSkin.last, const Color(0xFF5E3A22));
      expect(AvatarPalette.vinariSkin.first, const Color(0xFFF2F0FF));
      expect(AvatarPalette.vinariSkin.last, const Color(0xFF5B6FC4));
      expect(AvatarPalette.duranSkin.first, const Color(0xFF7C8F63));
      expect(AvatarPalette.duranSkin.last, const Color(0xFF232E1F));

      // Eyes, both the legacy and the decoupled path.
      expect(AvatarPalette.eye(AvatarSpecies.duran, 0, null),
          const Color(0xFFD4A017));
      expect(AvatarPalette.eye(AvatarSpecies.terran, 2, null),
          const Color(0xFF4A5A34));
      expect(AvatarPalette.eye(AvatarSpecies.vinari, 1, 1),
          const Color(0xFFBFE9FF));

      // The lore colour bands themselves — no red Duran skin, no warm Vinari — are
      // owned by `avatar_catalog_test.dart`, which already asserts them properly.
      // Duplicating a weaker version here would only invite it to drift.
    });
  });

  group('pirate generation', () {
    test('carries markings far more often than anyone else', () {
      // Deterministic: ids are fixed, so this is a measurement, not a sample. A
      // random generator here would make the test flaky for no benefit.
      const n = 4000;
      var pirateMarked = 0;
      var nativeMarked = 0;
      for (var i = 0; i < n; i++) {
        final id = 'npc_rate_$i';
        if (AvatarCatalog.seededStyleFor(id,
                    affiliation: AvatarAffiliation.pirate)
                .markings !=
            0) {
          pirateMarked++;
        }
        if (AvatarCatalog.seededStyleFor(id).markings != 0) nativeMarked++;
      }
      // Measured 94.8% against 76.0%. Thresholds sit well inside both, so a
      // small refactor of the weighting does not fail the suite.
      expect(pirateMarked / n, greaterThan(0.90));
      expect(nativeMarked / n, greaterThan(0.70));
      expect(pirateMarked / n, greaterThan(nativeMarked / n + 0.10));
      // Not *every* pirate. A pirate with no marks reads as somebody who joined
      // last week, which is a look worth keeping in the mix — an earlier version
      // re-rolled unconditionally and measured exactly 100%.
      expect(pirateMarked, lessThan(n));
    });

    test('never draws the smiling expression', () {
      // "Amused" is the third expression and the only one with a mouth that
      // curves upward. A grinning raider reads as friendly, which is the one
      // impression the affiliation is working against.
      //
      // The second assertion keeps the first from being vacuous: it proves the
      // option is reachable for everyone else, so "pirates never draw 2" is a
      // real exclusion rather than a property of the axis.
      const n = 3000;
      final pirateExpressions = <int>{};
      final nativeExpressions = <int>{};
      for (var i = 0; i < n; i++) {
        pirateExpressions.add(AvatarCatalog.seededStyleFor('npc_expr_$i',
                affiliation: AvatarAffiliation.pirate)
            .expression);
        nativeExpressions
            .add(AvatarCatalog.seededStyleFor('npc_expr_$i').expression);
      }
      expect(pirateExpressions, isNot(contains(2)),
          reason: 'a pirate drew the amused/smiling expression');
      // Both remaining options stay in the mix — "mean" is not one face.
      expect(pirateExpressions, {0, 1});
      expect(nativeExpressions, {0, 1, 2},
          reason: 'natives should still reach every expression, otherwise the '
              'exclusion above proves nothing');
    });

    test('the scowl is a scowl, and a faction member never gets one', () {
      // The exact values, asserted directly. A rendered-pixel difference cannot
      // cover this: the cloth, hair, and backdrop all differ between a pirate and
      // a native, so a guard that only asks "do these faces differ" passes even
      // with the scowl removed entirely. These numbers are the definition, so
      // nothing unrelated can contaminate them.
      // No species or presentation loop. An earlier version nested both and
      // claimed it was proving the scowl does not vary with either — but
      // `forAffiliation` takes neither parameter, so the independence is already
      // guaranteed by the signature. The loops cost nothing and proved nothing;
      // a peer review was right to call them vacuous.
      final seen = <Scowl>{};
      for (final expression in [0, 1]) {
        {
          {
            final pirate =
                Scowl.forAffiliation(AvatarAffiliation.pirate, expression);
            final native =
                Scowl.forAffiliation(AvatarAffiliation.native, expression);

            expect(native.isNone, isTrue,
                reason: 'a faction member should never scowls');
            expect(native.mouthCurve, isNull,
                reason: 'a native mouth keeps the species default, so the '
                    'upward "Amused" curve stays reachable');

            expect(pirate.isNone, isFalse);
            seen
              ..remove(pirate)
              ..add(pirate);
            // Inner brow ends drop, and the expression's own arch deepens.
            expect(pirate.browBias, greaterThan(0));
            expect(pirate.archScale, greaterThan(1));
            // A scowl sits closer to the eye.
            expect(pirate.browDrop, greaterThan(0));
            // The mouth is never flat and never upturned.
            expect(pirate.mouthCurve, lessThan(0));
            expect(pirate.mouthScale, greaterThan(1));
            expect(pirate.mouthWidthScale, greaterThan(1));
          }
        }
      }
      // Asserted on the field tuples rather than on a set of `Scowl`s. Relying on
      // value equality here meant this assertion would start failing — for a
      // reason unrelated to what it is checking — the moment `==`/`hashCode` were
      // dropped from `Scowl` in a refactor that treated it as identity-only. A
      // peer review flagged that as a false alarm waiting to happen.
      expect(
          seen
              .map((s) => '${s.browBias}/${s.archScale}/${s.browDrop}/'
                  '${s.mouthCurve}/${s.mouthScale}/${s.mouthWidthScale}')
              .toSet(),
          hasLength(2),
          reason: 'expected exactly the mild and stern scowls, nothing else');
    });

    test('a stern pirate scowls harder than a neutral one', () {
      // The one number that distinguishes the two reachable expressions, and the
      // reason "mean" is not a single face. The brow is identical between them;
      // only the mouth deepens.
      Scowl of(int expression, bool pirate) => Scowl.forAffiliation(
          pirate ? AvatarAffiliation.pirate : AvatarAffiliation.native,
          expression);
      expect(of(1, true).mouthCurve, lessThan(of(0, true).mouthCurve!));
      expect(of(1, true).browBias, of(0, true).browBias);
      // A native's stern is a frown too, but a far shallower one.
      expect(of(1, true).mouthCurve, lessThan(of(1, false).mouthCurve ?? 0));
    });

    test('leaves every native seeded style byte-identical', () {
      // Pinned literals for **all 27** catalogue entries, not a sample. A sample
      // catches a stream that shifted for the ids it covers and stays silent about
      // one that shifted for the rest, and there is no reason to accept a partial
      // guard on the single most fragile invariant in the change: any shift here
      // silently repaints every saved player avatar.
      //
      // Ordered [tone, outfit, outfitTone, hair, horns, eyes, markings,
      // expression] — the shape axes, in draw order.
      const expected = <String, List<int>>{
        'duran_male_lancer_01': [3, 2, 0, 1, 2, 0, 2, 0],
        'duran_male_warden_02': [5, 2, 1, 0, 2, 1, 2, 0],
        'duran_male_scout_03': [2, 2, 0, 0, 2, 1, 1, 1],
        'duran_female_razor_01': [2, 0, 0, 0, 2, 1, 1, 1],
        'duran_female_warden_02': [4, 2, 0, 0, 1, 1, 1, 2],
        'duran_female_seer_03': [2, 0, 0, 2, 2, 1, 2, 2],
        'duran_neutral_ash_01': [2, 1, 0, 0, 0, 0, 1, 1],
        'duran_neutral_cinder_02': [4, 1, 0, 0, 2, 1, 0, 0],
        'duran_neutral_flint_03': [4, 2, 1, 1, 0, 1, 0, 2],
        'vinari_male_oracle_01': [2, 0, 1, 2, 2, 0, 2, 1],
        'vinari_male_weaver_02': [1, 1, 2, 1, 0, 1, 1, 2],
        'vinari_male_lumen_03': [1, 2, 1, 0, 1, 1, 1, 2],
        'vinari_female_weaver_01': [5, 2, 0, 2, 0, 2, 0, 1],
        'vinari_female_oracle_02': [2, 1, 2, 1, 1, 0, 2, 1],
        'vinari_female_lumen_03': [3, 1, 0, 1, 2, 2, 2, 2],
        'vinari_neutral_aurora_01': [0, 2, 2, 2, 0, 1, 0, 1],
        'vinari_neutral_halo_02': [0, 2, 0, 2, 2, 1, 2, 1],
        'vinari_neutral_drifter_03': [5, 0, 0, 0, 2, 1, 0, 1],
        'terran_male_broker_01': [4, 2, 1, 0, 2, 1, 0, 2],
        'terran_male_pilot_02': [1, 1, 1, 1, 1, 2, 0, 0],
        'terran_male_envoy_03': [0, 0, 1, 2, 0, 2, 1, 2],
        'terran_female_broker_01': [3, 0, 2, 1, 0, 0, 1, 1],
        'terran_female_pilot_02': [3, 0, 0, 1, 1, 2, 1, 0],
        'terran_female_envoy_03': [3, 2, 1, 0, 1, 0, 2, 2],
        'terran_neutral_broker_01': [0, 2, 2, 0, 1, 2, 1, 2],
        'terran_neutral_pilot_02': [1, 1, 0, 0, 0, 1, 1, 2],
        'terran_neutral_envoy_03': [4, 0, 1, 0, 2, 2, 1, 1],
      };
      // And no entry may be missing, so a new catalogue portrait has to be pinned
      // rather than inheriting the old ones' guarantee.
      expect(expected, hasLength(AvatarCatalog.portraits.length),
          reason: 'every catalogue portrait needs a pinned style');
      expect(expected.keys.toSet(),
          AvatarCatalog.portraits.map((p) => p.id).toSet());

      for (final p in AvatarCatalog.portraits) {
        final s = AvatarCatalog.seededStyleFor(p.id);
        final actual = [
          s.tone,
          s.outfit,
          s.outfitTone,
          s.hair,
          s.horns,
          s.eyes,
          s.markings,
          s.expression,
        ];
        expect(actual, expected[p.id],
            reason: '${p.id} seeded style drifted — every player who saved '
                'this portrait renders differently now');
        // And no colour slot may be set, since a set slot on a native would change
        // its render rather than being a legacy-compatible null.
        expect(s.hairColor, isNull, reason: '${p.id} has a hair dye set');
        expect(s.eyeColor, isNull, reason: '${p.id} has an eye dye set');
        expect(s.markingColor, isNull, reason: '${p.id} has a pigment set');
        expect(s.trimColor, isNull, reason: '${p.id} has a trim dye set');
        expect(s.backdrop, isNull, reason: '${p.id} has a backdrop set');
        // The explicit-native call is the same as the default.
        expect(
            AvatarCatalog.seededStyleFor(p.id,
                affiliation: AvatarAffiliation.native),
            AvatarCatalog.seededStyleFor(p.id));
      }
    });
  });
}
