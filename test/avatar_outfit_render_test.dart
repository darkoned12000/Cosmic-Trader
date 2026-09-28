import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_portrait_painter.dart';

const double _size = 200.0;

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

Future<Set<int>> _sampleRect(
  ui.Image image,
  double fromX,
  double fromY,
  double toX,
  double toY,
) async {
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  final seen = <int>{};
  for (var y = (_size * fromY).toInt(); y < (_size * toY).toInt(); y += 3) {
    for (var x = (_size * fromX).toInt(); x < (_size * toX).toInt(); x += 3) {
      seen.add(data!.getUint32((y * _size.toInt() + x) * 4));
    }
  }
  return seen;
}

/// Distinct colours in a horizontal band across the middle of the portrait.
Future<Set<int>> _bandColours(
  AvatarSelection selection,
  double fromY,
  double toY,
) async {
  final image = await _render(selection);
  final seen = await _sampleRect(image, 0.30, fromY, 0.70, toY);
  image.dispose();
  return seen;
}

/// Distinct colours in the strip above the head, which is pure backdrop.
///
/// The head centre sits at 0.42h and the crown reaches roughly 0.22h, so
/// everything above 0.16h is background for every species and presentation.
Future<Set<int>> _backdropColours(AvatarSelection selection) async {
  final image = await _render(selection);
  final seen = await _sampleRect(image, 0.05, 0.03, 0.95, 0.14);
  image.dispose();
  return seen;
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
        final colours = await _bandColours(selection, 0.72, 0.92);
        expect(
          colours.length,
          greaterThan(8),
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
    final seen = await _sampleRect(image, 0.30, 0.72, 0.70, 0.92);
    expect(seen.length, lessThan(8),
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
