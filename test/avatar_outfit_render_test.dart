import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_portrait_painter.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

const double _size = 200.0;

/// Fixed identity for the Terran gear guard, so every gear option renders the
/// same face underneath.
const AvatarPortrait _gearPortrait = AvatarPortrait(
  id: 'gear-probe',
  species: AvatarSpecies.terran,
  presentation: AvatarPresentation.male,
  label: 'x',
);

/// The portrait the Vinari axis guard renders. One fixed identity so every
/// `hair` value is compared against the same backdrop, palette, and proportions.
const AvatarPortrait _axisPortrait = AvatarPortrait(
  id: 'vinari-axis',
  species: AvatarSpecies.vinari,
  presentation: AvatarPresentation.male,
  label: 'x',
);

/// A fully pinned style, so the only thing that varies between two renders of
/// [_axisPortrait] is the axis under test.
AvatarStyle _axisStyle(int hair) => AvatarStyle.neutral.copyWith(
      hair: hair,
      tone: 2,
      outfit: 0,
      outfitTone: 0,
      markings: 0,
      hairColor: 0,
      gear: 0,
      backdrop: null,
    );

Future<ui.Image> _render(AvatarSelection selection) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, _size, _size),
    Paint()..color = const Color(0xFF12141C),
  );
  AvatarPortraitPainter(
    portrait: AvatarCatalog.byId(selection.portraitId)!,
    style: selection.style,
  ).paint(canvas, const Size.square(_size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size.toInt(), _size.toInt());
  picture.dispose();
  return image;
}

/// Renders an already-resolved portrait.
///
/// [_render] goes through [AvatarCatalog.byId], which is right for a player's
/// selection but cannot resolve a derived NPC portrait — there is no catalogue
/// entry for one, by design.
Future<ui.Image> _renderPortrait(
    AvatarPortrait portrait, AvatarStyle? style) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, _size, _size),
    Paint()..color = const Color(0xFF12141C),
  );
  AvatarPortraitPainter(portrait: portrait, style: style)
      .paint(canvas, const Size.square(_size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size.toInt(), _size.toInt());
  picture.dispose();
  return image;
}

/// Distinct colours in a region.
///
/// [quantise] buckets each channel to that many levels before counting, so a
/// smooth gradient or an antialiased edge collapses instead of manufacturing
/// distinct values. **1 means raw** and is the default, because the callers that
/// compare smooth gradients need the fine gradations: making quantising global
/// collided two backdrop options outright.
///
/// Bucketing to 16 is what the "multi-tone garment" guard wants. Anti-aliased
/// edges alone produce well over eight distinct RGBA values on a garment with one
/// or two real design tones, so an unquantised "more than 8 distinct colours means
/// multi-tone" threshold can be satisfied by edge noise. A peer review raised this;
/// re-measuring after quantising showed the old threshold sat *below* the real
/// Terran value, i.e. it had been measuring how smooth the renderer is.
Future<Set<int>> _sampleRect(
  ui.Image image,
  double fromX,
  double fromY,
  double toX,
  double toY, {
  int quantise = 1,
}) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final seen = <int>{};
  int bucket(int channel) =>
      quantise <= 1 ? channel : (channel ~/ quantise).clamp(0, 15);
  for (var y = (_size * fromY).toInt(); y < (_size * toY).toInt(); y += 3) {
    for (var x = (_size * fromX).toInt(); x < (_size * toX).toInt(); x += 3) {
      final at = (y * _size.toInt() + x) * 4;
      seen.add((bucket(data!.getUint8(at)) << 16) |
          (bucket(data.getUint8(at + 1)) << 8) |
          bucket(data.getUint8(at + 2)));
    }
  }
  return seen;
}

/// Distinct colours in a horizontal band across the middle of the portrait.
Future<Set<int>> _bandColours(
  AvatarSelection selection,
  double fromY,
  double toY, {
  int quantise = 1,
}) async {
  final image = await _render(selection);
  final seen =
      await _sampleRect(image, 0.30, fromY, 0.70, toY, quantise: quantise);
  image.dispose();
  return seen;
}

/// How many pixels differ between two images inside a region.
///
/// A **count**, not a boolean, because "these differ" cannot detect a difference
/// being removed — see the scowl guard for the full argument.
Future<int> _differingPixels(
  ui.Image a,
  ui.Image b,
  double fromX,
  double fromY,
  double toX,
  double toY,
) async {
  final da = (await a.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final db = (await b.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final px = _size.toInt();
  var count = 0;
  for (var y = (_size * fromY).toInt(); y < (_size * toY).toInt(); y++) {
    for (var x = (_size * fromX).toInt(); x < (_size * toX).toInt(); x++) {
      if (da.getUint32((y * px + x) * 4) != db.getUint32((y * px + x) * 4)) {
        count++;
      }
    }
  }
  return count;
}

/// Row-major bytes of the outside-head mask, for an "is this form the same as
/// that one" comparison.
List<int> _outsideHeadSignature(ByteData data) {
  final px = _size.toInt();
  final out = <int>[];
  for (var y = 0; y < px; y++) {
    for (var x = 0; x < px; x++) {
      if (_outsideHead(x / _size, y / _size)) {
        out.add(data.getUint32((y * px + x) * 4));
      }
    }
  }
  return out;
}

/// Whether a normalised point lies **outside** the head silhouette.
///
/// The mask that makes the Vinari axis measurable. The head is only 0.94r wide
/// and the crown reaches about 0.17h, so this is the two flanks plus the strip
/// above the crown — the only places an appendage can reach.
///
/// It matters because `crest()` *also* varies with `hair`, drawing a glow on top
/// of the head. Any sample that includes the head therefore measures the crest
/// too, and the crest is much larger than the silhouette being tested: an earlier
/// version of this guard drew 4500 of its 5709 differing pixels from the crest,
/// which is why it reported an entirely inert `hair` axis as three distinct
/// silhouettes.
bool _outsideHead(double fx, double fy) {
  if (fy > 0.62) return false; // shoulders and torso
  if (fx < 0.33 || fx > 0.67) return fx >= 0.10 && fx <= 0.90; // the flanks
  return fy <= 0.15; // above the crown
}

/// Differing pixels in the outside-head mask, optionally restricted to one side.
int _differingOutsideHead(
  ByteData a,
  ByteData b, {
  double? fromX,
  double? toX,
}) {
  final px = _size.toInt();
  var count = 0;
  for (var y = 0; y < px; y++) {
    final fy = y / _size;
    for (var x = 0; x < px; x++) {
      final fx = x / _size;
      if (!_outsideHead(fx, fy)) continue;
      if (fromX != null && fx < fromX) continue;
      if (toX != null && fx > toX) continue;
      if (a.getUint32((y * px + x) * 4) != b.getUint32((y * px + x) * 4)) {
        count++;
      }
    }
  }
  return count;
}

Future<Set<int>> _backdropColours(AvatarSelection selection) async {
  final image = await _render(selection);
  final seen = await _sampleRect(image, 0.05, 0.03, 0.95, 0.14);
  image.dispose();
  return seen;
}

/// [_renderPortrait], with the scowl seam forwarded.
///
/// The seam is the only way to measure a scowl without also measuring every other
/// difference between a pirate and a native; see the guard that uses it.
Future<ui.Image> _renderPortraitWith(
  AvatarPortrait portrait,
  AvatarStyle? style, {
  Scowl? scowlOverride,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, _size, _size),
    Paint()..color = const Color(0xFF12141C),
  );
  AvatarPortraitPainter(
    portrait: portrait,
    style: style,
    scowlOverride: scowlOverride,
  ).paint(canvas, const Size.square(_size));
  final picture = recorder.endRecording();
  final image = await picture.toImage(_size.toInt(), _size.toInt());
  picture.dispose();
  return image;
}

void main() {
  // This file exists on its own — with no widget tests — because
  // `Picture.toImage` needs real async and never completes inside the fake-async
  // zone `testWidgets` runs in.

  test('every species paints a multi-tone garment in the torso', () async {
    // Regression guard. A refactor once wrapped already-pixel values in `uy()`
    // a second time, pushing every garment off-canvas: the Duran lost their
    // armour, the Vinari their shroud, the Traders their collar and zip.
    // Nothing threw, so exception-only assertions passed happily. Sampling
    // rendered pixels is what actually catches it.
    for (final faction in FactionClass.values) {
      for (var outfit = 0; outfit < AvatarCatalog.variantCount; outfit++) {
        final selection = AvatarSelection.defaultFor(faction).copyWith(
          style: AvatarStyle.neutral.copyWith(outfit: outfit),
        );
        // Quantised by [_sampleRect], so this counts design tones rather than
        // antialiasing. A collar beside a robe is hundreds of levels apart; a
        // gradient along an edge is not.
        final colours = await _bandColours(selection, 0.72, 0.92, quantise: 16);
        // Threshold calibrated against the *quantised* counts, because the raw
        // count was passing partly on antialiasing. Measured in this band:
        // Duran 10-12, Vinari 8, Terran 6-7, and a single flat fill 1. The old
        // "> 8 raw colours" sat below the real Terran value once quantised, i.e.
        // it had been measuring how smooth the renderer is rather than whether a
        // garment was drawn. The floor is set well clear of the flat fill and well
        // below the lowest real garment, so it is not sensitive to art tweaks.
        expect(
          colours.length,
          greaterThan(3),
          reason: '$faction outfit $outfit must actually draw a garment; got '
              '${colours.length} distinct torso colours, which means the outfit '
              'is off-canvas or invisible',
        );
      }
    }
  });

  test('a flat fill would fail the guard above', () async {
    // Sanity check on the guard itself: a single flat rect and nothing else.
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, _size, _size),
      Paint()..color = const Color(0xFF12141C),
    );
    final picture = recorder.endRecording();
    final image = await picture.toImage(_size.toInt(), _size.toInt());
    picture.dispose();
    // One quantised colour, against a floor of 4 in the guard above. The old
    // `< 8` on raw values was nowhere near this and did not mean much.
    final seen = await _sampleRect(image, 0.30, 0.72, 0.70, 0.92, quantise: 16);
    expect(seen.length, lessThanOrEqualTo(3),
        reason: 'a single flat fill must not look like a drawn garment');
    image.dispose();
  });

  test('every backdrop index draws something distinct, and none is the bloom',
      () async {
    // The backdrop axis is only worth having if the options are actually
    // different. Two failures this catches: an index falling through to the
    // default case (so two of the three render identically), and an option
    // that nobody art-directed, which would silently be the faction bloom and
    // so would not be a new look at all.
    for (final faction in FactionClass.values) {
      final base = AvatarSelection.defaultFor(faction);

      final bloom = await _backdropColours(base);
      expect(bloom.length, greaterThan(2),
          reason: '$faction null backdrop should render the faction bloom');

      // A list, not a set: `Set` has no indexer, and the ordering is what
      // makes "differs from every earlier option" expressible.
      final seen = <Set<int>>[bloom];
      for (var bd = 0; bd < AvatarStyle.backdropCount; bd++) {
        final image = await _render(base.copyWith(
          style: (base.style ?? AvatarStyle.neutral).copyWith(backdrop: bd),
        ));
        final colours = await _sampleRect(image, 0.05, 0.03, 0.95, 0.14);
        image.dispose();

        expect(colours.length, greaterThan(2),
            reason: '$faction backdrop $bd drew no structure at all');
        for (final earlier in seen) {
          expect(colours, isNot(equals(earlier)),
              reason: '$faction backdrop $bd is pixel-identical to an earlier '
                  'option — it fell through to the default case');
        }
        seen.add(colours);
      }
      expect(seen.length, AvatarStyle.backdropCount + 1,
          reason: '$faction should offer $AvatarStyle.backdropCount backdrops '
              'plus the legacy bloom');
    }
  });

  test('the Vinari hair axis changes the silhouette, not just a faint arc',
      () async {
    // Regression guard for the finding that started this work: the Vinari had no
    // axis that changed their outline, so a roster of them read as one silhouette
    // in several tints. `hair` is now a silhouette axis (crown of light / tendril
    // fall / frill fan).
    //
    // ## Measured outside the head, not inside it
    //
    // Everything here samples [_outsideHead] — the two flanks and the strip above
    // the crown, the only places an appendage reaches. `crest()` also varies with
    // `hair`, drawing a glow on top of the head, and it is much larger than the
    // silhouette under test: an earlier version of this guard drew 4500 of its
    // 5709 differing pixels from the crest, so it reported an entirely **inert**
    // axis as three distinct silhouettes. Brightness counting is no better — it
    // moved under 7% when the frill's apex was pushed back below the crown, which
    // is the exact defect this test exists to catch.
    //
    // Nothing is compared against the crown strip alone either. That was the first
    // band, and a peer review found the tendril angle was being read from +x
    // rather than from straight-down, so the whole fan leaned right; fixing that
    // made the tendrils *hang* below the crown, where the narrow band could no
    // longer see them at all.
    //
    // ## Two failure shapes, two assertions
    //
    //  * **Vanished or shrunken** — a form's outline is gone or has retreated
    //    behind the skull. A differential pixel count catches it.
    //  * **Lopsided** — a form is present and even large but no longer
    //    mirror-symmetric. No size check can catch this: the one-sided tendril
    //    spray covers *more* pixels (1600) than the symmetric fall (1129), so
    //    every count threshold passes it. Only a left/right balance check sees it.
    //
    // Measured, each threshold between the correct value and the worst faulted:
    //
    //            tendrils   frill      balance
    //   correct      1129     3569      0.89 / 0.95
    //   frill apex          2454
    //   one-sided    1600               0.07
    //   inert axis      0      224
    final images = <ui.Image>[];
    final bytes = <ByteData>[];
    for (var hair = 0; hair < AvatarCatalog.variantCount; hair++) {
      final image = await _renderPortrait(_axisPortrait, _axisStyle(hair));
      images.add(image);
      bytes.add((await image.toByteData(format: ui.ImageByteFormat.rawRgba))!);
    }
    final signatures = bytes.map(_outsideHeadSignature).toList();

    // 1. Every *non-plain* form draws a real outline outside the head.
    //    Form 0 is the plain form and is the reference, so it has nothing to add
    //    by construction; an inert axis shows up as forms 1 and 2 collapsing onto
    //    it (measured 0 and 224 against floors of 900 and 3000).
    for (var hair = 1; hair < bytes.length; hair++) {
      final n = _differingOutsideHead(bytes[0], bytes[hair]);
      expect(n, greaterThan(hair == 1 ? 900 : 3000),
          reason: 'Vinari hair $hair moves only $n pixels against the plain '
              'form, so it has no silhouette outside the head — check that '
              'appendages() dispatches on it, and that the form is not being '
              'drawn behind the skull');
    }

    // 2. The forms are distinguishable outside the head. A pairwise comparison on
    //    the mask, not on the whole box, so the shared head cannot vouch for an
    //    axis that only changed a glow on top of it.
    for (var i = 0; i < signatures.length; i++) {
      for (var j = i + 1; j < signatures.length; j++) {
        expect(signatures[i], isNot(equals(signatures[j])),
            reason:
                'Vinari hair $i and $j are identical outside the head, so the '
                'axis is not changing the outline');
      }
    }

    // 3. Every form is balanced left to right. Catches a form that is present and
    //    large but lopsided, which no size assertion can see.
    for (var hair = 0; hair < bytes.length; hair++) {
      if (hair == 0) continue;
      final left =
          _differingOutsideHead(bytes[0], bytes[hair], fromX: 0.0, toX: 0.5);
      final right =
          _differingOutsideHead(bytes[0], bytes[hair], fromX: 0.5, toX: 1.0);
      final hi = left > right ? left : right;
      final lo = left > right ? right : left;
      expect(lo / hi, greaterThan(0.6),
          reason: 'Vinari hair $hair is lopsided — $left pixels differ on the '
              'left against $right on the right. Check the direction the '
              'appendage is built from: an angle measured from +x rather than '
              'from straight-down leans every strand the same way');
    }

    for (final r in images) {
      r.dispose();
    }
  });

  test('every species actually consumes the pirate scowl', () async {
    // A pirate gets a scowl, and the species' `expression()` is supposed to consume
    // it. The failure this guards is real and has happened: `TerranArt` overrides
    // `expression()` without calling `super`, so the first implementation put the
    // adjustments only in the base class and the Terran — the one species whose
    // face actually shows a mouth — never scowled at all.
    //
    // ## Why this does not compare a pirate to a native
    //
    // That was the first approach and it is **structurally unable to cover all
    // three species**. Comparing across affiliations also picks up cloth, hair
    // dye, and — for the Vinari — a face wash drawn in the hair colour. Measured,
    // the Vinari's *background* difference is 3736 pixels against a scowl
    // contribution of about 95, so an entire scowl removed from the Vinari still
    // read far above any threshold that worked for the Duran (background 4) and
    // the Terran (background 0). The old guard acknowledged that gap in a comment
    // and pointed at `avatar_pirate_test.dart` for cover — but that file only
    // asserts properties of the `Scowl` *value* and never renders anything, so it
    // could not tell whether a species' `expression()` consumed that value. The
    // gap was documented as covered and was not. A peer review caught it.
    //
    // `AvatarDrawContext.scowlOverride` is the fix: render the *same* pirate twice,
    // once normally and once with the scowl forced to `Scowl.none()`. Nothing else
    // differs, so the whole signal is the scowl, for every species equally.
    //
    // Measured, differing pixels in the brow/mouth band inside the head:
    //   Duran   261 neutral / 349 stern
    //   Vinari  184 neutral / 251 stern
    //   Terran  276 neutral / 418-480 stern
    // The smallest single value across all 18 combinations is 184, so a floor of
    // 120 clears it with margin while a scowl removed entirely reads 0.
    for (final species in AvatarSpecies.values) {
      for (final presentation in AvatarPresentation.values) {
        for (final expression in [0, 1]) {
          final style = AvatarStyle.neutral.copyWith(
            tone: 2,
            outfit: 0,
            outfitTone: 0,
            hair: 1,
            expression: expression,
            hairColor: 0,
            markings: 0,
            backdrop: null,
            gear: 0,
          );
          final portrait = AvatarPortrait(
            id: 'scowl-probe',
            species: species,
            presentation: presentation,
            label: 'x',
            // Always a pirate, so the scowl is switched off by the override rather
            // than by the affiliation — that is the whole point.
            affiliation: AvatarAffiliation.pirate,
          );

          final withScowl =
              await _renderPortraitWith(portrait, style, scowlOverride: null);
          final withoutScowl = await _renderPortraitWith(portrait, style,
              scowlOverride: const Scowl.none());

          expect(
            await _differingPixels(
                withoutScowl, withScowl, 0.35, 0.35, 0.65, 0.59),
            greaterThan(120),
            reason: '$species ${presentation.name} expression $expression: the '
                'scowl moved fewer than 120 pixels, so this species is almost '
                'certainly not consuming it — check whether expression() is '
                'overridden without routing through Scowl.forContext',
          );

          withScowl.dispose();
          withoutScowl.dispose();
        }
      }
    }
  });

  test('worn gear is drawn over the head, not painted over by it', () async {
    // Regression guard for a bug that was invisible for the life of the feature.
    // Terran gear was called from `appendages` with a comment insisting it "must be
    // unclipped" — true, and irrelevant, because `appendages` is drawn *before* the
    // head fill. Everything inside the skull silhouette was painted over; only the
    // earcup, the one part reaching past it, ever showed. Two of the three gear
    // options were therefore indistinguishable, and the visible part read as a
    // rendering fault rather than as gear.
    //
    // The existing "appendages reach outside the head clip" guard cannot see this:
    // it samples *above* the crown, while the goggle lenses sit around
    // `dy - 0.69r` — deep inside the head. Hence a band across the forehead.
    //
    // Asserted as all three options being distinct from each other, which is the
    // property that was actually broken (two options looked alike), plus a
    // non-empty forehead contribution so a future refactor cannot quietly drop the
    // slot and pass on distinctness alone.
    final images = <ui.Image>[];
    for (var gear = 0; gear < 3; gear++) {
      images.add(await _renderPortraitWith(
        _gearPortrait,
        AvatarStyle.neutral.copyWith(
          tone: 1,
          outfit: 0,
          outfitTone: 0,
          hair: 0,
          hairColor: 0,
          expression: 0,
          markings: 0,
          gear: gear,
          backdrop: null,
        ),
      ));
    }

    for (var i = 0; i < images.length; i++) {
      // The forehead, where a goggle band and lenses live.
      final onFace =
          await _differingPixels(images[0], images[i], 0.36, 0.24, 0.64, 0.40);
      if (i == 0) continue;
      expect(onFace, greaterThan(200),
          reason: 'gear option $i changes only $onFace pixels across the '
              'forehead — it is being drawn behind the head, so only the part '
              'that clears the skull is visible');
    }

    for (var i = 0; i < images.length; i++) {
      for (var j = i + 1; j < images.length; j++) {
        expect(
          await _differingPixels(images[i], images[j], 0.30, 0.18, 0.70, 0.46),
          greaterThan(200),
          reason:
              'gear options $i and $j are indistinguishable on the face, so '
              'the gear axis is doing nothing for a Terran',
        );
      }
    }

    for (final i in images) {
      i.dispose();
    }
  });

  test('appendages reach outside the head clip rather than being sliced by it',
      () async {
    // Guards the layer-order bug that actually happened: appendages used to be
    // drawn *inside* `clipPath(headPath)`, which cut the Duran horn roots flat
    // and lost the Terran ears almost entirely. Nothing threw and no existing
    // assertion covered it.
    //
    // Tall horns must reach higher above the crown than short ones. If they are
    // clipped, neither can, and the two renders above the crown become identical
    // — which is what this asserts against.
    //
    // A backdrop cannot be used to make this fail: the head fill is opaque and
    // drawn after it, so anything the backdrop draws is covered regardless. That
    // version of the test was written, passed two deliberate faults, and was
    // deleted as worthless.
    for (final bd in <int?>[null, 0, 1, 2]) {
      Future<Set<int>> aboveCrown(int horns) async {
        final image = await _render(
          AvatarSelection.defaultFor(FactionClass.duran).copyWith(
            style: AvatarStyle.neutral.copyWith(horns: horns, backdrop: bd),
          ),
        );
        final seen = await _sampleRect(image, 0.30, 0.02, 0.70, 0.10);
        image.dispose();
        return seen;
      }

      final tall = await aboveCrown(1); // tall crown spikes, reaches 2.30r
      final short = await aboveCrown(0); // battle horns, reach 1.92r
      expect(tall, isNot(equals(short)),
          reason: 'backdrop $bd: tall horns must differ from short horns above '
              'the crown. If they match, the appendages are being clipped to '
              'the head path.');
    }
  });
}
