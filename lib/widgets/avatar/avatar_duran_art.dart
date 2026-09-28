import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

/// Duran art: scaled insectoid warriors in battle-armour.
///
/// Lore: *"scaly, insectoid warriors with glowing red eyes, clad in
/// battle-armour"*. Three things follow from that and drive every choice here:
/// a long low reptilian skull, real overlapping **scales** rather than a
/// painted texture, and segmented plate armour instead of fabric.
///
/// **Gender is carried by silhouette only** — crest rake and count, horn lean,
/// and plating density. They are a warrior race, so a per-presentation palette
/// would be the wrong answer, and `AvatarPalette.outfit(duran, …)` is
/// presentation-independent by design.
class DuranArt extends SpeciesArt {
  const DuranArt();

  @override
  AvatarSpecies get species => AvatarSpecies.duran;

  @override
  Path headPath(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    return Path()
      ..moveTo(o.dx, o.dy - r * 1.06)
      ..lineTo(o.dx + r * 0.98, o.dy - r * 0.44)
      ..lineTo(o.dx + r * 1.04, o.dy + r * 0.16)
      ..lineTo(o.dx + r * 0.74, o.dy + r * 0.74)
      ..lineTo(o.dx, o.dy + r * 1.16)
      ..lineTo(o.dx - r * 0.74, o.dy + r * 0.74)
      ..lineTo(o.dx - r * 1.04, o.dy + r * 0.16)
      ..lineTo(o.dx - r * 0.98, o.dy - r * 0.44)
      ..close();
  }

  @override
  void appendages(AvatarDrawContext c) {
    _horns(c);
  }

  /// Horns or antennae. Drawn *before* the head so the skull overlaps each root.
  void _horns(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    for (final side in [-1.0, 1.0]) {
      final lean = c.presentation == AvatarPresentation.female
          ? -0.34
          : (c.presentation == AvatarPresentation.male ? 0.30 : 0.0);
      final length = switch (c.style.horns) {
        1 => 2.30, // tall crown spikes
        2 => 1.42, // short antenna barbel
        _ => 1.92, // forward-curved battle horns
      };
      final curl = switch (c.style.horns) {
        1 => 0.10,
        2 => 0.55,
        _ => 0.28,
      };
      final horn = Color.lerp(c.skinShadow, Colors.black, 0.18)!;
      c.fill(
        Path()
          ..moveTo(o.dx + side * r * 0.50, o.dy - r * 0.62)
          ..quadraticBezierTo(
              o.dx + side * r * (0.72 + lean),
              o.dy - r * (length * 0.66),
              o.dx + side * r * (0.34 + lean * curl),
              o.dy - r * length)
          ..quadraticBezierTo(
              o.dx + side * r * (0.60 + lean * 0.4),
              o.dy - r * (length * 0.58),
              o.dx + side * r * 0.26,
              o.dy - r * 0.70)
          ..close(),
        horn,
      );
      // A brighter inner edge gives the horn some roundness.
      c.stroke(
        Path()
          ..moveTo(o.dx + side * r * 0.46, o.dy - r * 0.66)
          ..quadraticBezierTo(
              o.dx + side * r * (0.62 + lean * 0.8),
              o.dy - r * (length * 0.62),
              o.dx + side * r * (0.30 + lean * curl),
              o.dy - r * (length * 0.96)),
        Color.lerp(horn, Colors.white, 0.30)!,
        width: math.max(1, c.u(0.012)),
      );
      if (c.style.horns == 2) {
        c.dot(Offset(o.dx + side * r * (0.34 + lean * curl), o.dy - r * length),
            c.u(0.016), c.accent);
      }
    }
  }

  @override
  void faceTexture(AvatarDrawContext c) {
    _scales(c);
    _snout(c);
    _warPaint(c);
  }

  /// Overlapping reptilian scales. Staggered rows of small arcs in two tones,
  /// so the texture survives a 48px downscale instead of turning to mush.
  void _scales(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    final scaleR = r * 0.20;
    for (var row = 0; row < 9; row++) {
      final y = o.dy - r * 1.10 + row * scaleR * 1.32;
      if (y > o.dy + r * 1.20) break;
      // Alternate the offset per row so the rows interlock like real scales.
      final offset = row.isEven ? 0.0 : scaleR * 0.9;
      for (var col = -3; col <= 3; col++) {
        final x = o.dx + col * scaleR * 1.74 + offset;
        if ((x - o.dx).abs() > r * 1.05) continue;
        c.fill(
          Path()
            ..moveTo(x - scaleR, y)
            ..quadraticBezierTo(x, y - scaleR * 1.15, x + scaleR, y)
            ..quadraticBezierTo(x, y + scaleR * 0.45, x - scaleR, y)
            ..close(),
          ((row + col) % 2 == 0 ? c.skinLight : c.skinShadow)
              .withValues(alpha: 0.30),
        );
      }
    }
    // Heavy brow ridge.
    c.fill(
      Path()
        ..moveTo(o.dx - r * 0.90, o.dy - r * 0.16)
        ..lineTo(o.dx, o.dy - r * 0.44)
        ..lineTo(o.dx + r * 0.90, o.dy - r * 0.16)
        ..lineTo(o.dx + r * 0.82, o.dy + r * 0.06)
        ..lineTo(o.dx, o.dy - r * 0.22)
        ..lineTo(o.dx - r * 0.82, o.dy + r * 0.06)
        ..close(),
      c.skinShadow,
    );
  }

  /// Nostril slits and a jaw line — reptilian, not mammalian.
  void _snout(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    for (final side in [-1.0, 1.0]) {
      c.line(
        Offset(o.dx + side * r * 0.16, o.dy + r * 0.44),
        Offset(o.dx + side * r * 0.30, o.dy + r * 0.42),
        c.skinShadow,
        width: math.max(1, c.u(0.018)),
      );
    }
    c.line(
      Offset(o.dx - r * 0.52, o.dy + r * 0.80),
      Offset(o.dx + r * 0.52, o.dy + r * 0.80),
      c.skinShadow,
      width: math.max(1, c.u(0.016)),
    );
  }

  /// War paint. `markings` 0 is unmarked by design; the reroll weighting keeps
  /// 1 and 2 common enough to be worth seeing.
  ///
  /// Pigment comes from the palette, never the faction colour: faction red on
  /// green skin read as a bleeding wound, and one variant looked like a gag.
  void _warPaint(AvatarDrawContext c) {
    if (c.style.markings == 0) return;
    final o = c.headCenter;
    final r = c.headR;
    final paint = AvatarPalette.markingPigment(
            AvatarSpecies.duran, c.style.markings, c.style.markingColor)
        .withValues(alpha: 0.80);
    if (c.style.markings == 1) {
      // Two cheek stripes, kept clear of the mouth.
      for (final side in [-1.0, 1.0]) {
        c.stroke(
          Path()
            ..moveTo(o.dx + side * r * 0.82, o.dy - r * 0.04)
            ..quadraticBezierTo(o.dx + side * r * 0.74, o.dy + r * 0.30,
                o.dx + side * r * 0.62, o.dy + r * 0.56),
          paint,
          width: math.max(1.4, c.u(0.026)),
        );
      }
    } else {
      // Ritual scar: one diagonal slash across a cheek.
      c.stroke(
        Path()
          ..moveTo(o.dx + r * 0.24, o.dy - r * 0.44)
          ..quadraticBezierTo(o.dx + r * 0.60, o.dy - r * 0.10, o.dx + r * 0.78,
              o.dy + r * 0.26),
        paint,
        width: math.max(1.4, c.u(0.026)),
      );
    }
  }

  @override
  void outfit(AvatarDrawContext c) {
    _armour(c);
  }

  /// Battle-armour, rebuilt twice after render review.
  ///
  /// v1 was thin curved bands across a flat torso with pauldron shapes floating
  /// beside the shoulders. v2 connected a yoke to the throat but left a dark
  /// rectangular slab that read as an apron. What works at 48px is fewer,
  /// larger, higher-contrast shapes: a pauldron-yoke per side, a shield-shaped
  /// cuirass laid over their inner ends so the pieces share edges, and a gorget.
  ///
  /// The `outfit` axis picks the armour set — banded plate, a single heavy
  /// pauldron, or light scale-mail. Presentation only modulates density within
  /// the chosen set.
  void _armour(AvatarDrawContext c) {
    final st = c.shoulderTop;
    final sw = c.shoulderWidth;
    final dense = c.presentation == AvatarPresentation.male;
    final set = c.style.outfit;

    final plate = switch (set) {
      1 => Color.lerp(c.cloth, c.plateLight, 0.52)!,
      2 => Color.lerp(c.cloth, c.plateLight, 0.26)!,
      _ => Color.lerp(c.cloth, c.plateLight, 0.42)!,
    };
    final plateLit = Color.lerp(c.cloth, c.plateLight, 0.66)!;
    final groove = Color.lerp(c.cloth, Colors.black, 0.42)!;

    // ── Pauldron-yoke: throat out over each shoulder ───────────────
    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(c.ux(0.5 + side * 0.075), st - c.u(0.050))
          ..lineTo(c.ux(0.5 + side * sw * 0.86), st + c.u(0.09))
          ..lineTo(c.ux(0.5 + side * sw * 0.76), st + c.u(0.25))
          ..lineTo(c.ux(0.5 + side * 0.105), st + c.u(0.16))
          ..close(),
        plate,
      );
      c.line(
        Offset(c.ux(0.5 + side * 0.075), st - c.u(0.050)),
        Offset(c.ux(0.5 + side * sw * 0.86), st + c.u(0.09)),
        plateLit,
        width: math.max(1, c.u(0.013)),
      );
      // The heavy-pauldron set drops the off side, so it reads asymmetric.
      if (!(set == 1 && side < 0)) {
        for (var i = 0; i < 3; i++) {
          final t = 0.42 + i * 0.22;
          c.dot(
            Offset(
              c.ux(0.5 + side * (0.075 + (sw * 0.86 - 0.075) * t)),
              st - c.u(0.050) + c.u(0.15) * t + c.u(0.035),
            ),
            math.max(0.9, c.u(0.008)),
            plateLit,
          );
        }
      }
    }

    // ── Cuirass: a shield, not a box ───────────────────────────────
    final top = st + c.u(0.06);
    final bottom = st + c.u(0.31);
    final flare = sw * 0.60;
    final shield = Path()
      ..moveTo(c.ux(0.5 - 0.100), top)
      ..lineTo(c.ux(0.5 + 0.100), top)
      ..lineTo(c.ux(0.5 + flare * 0.84), top + c.u(0.075))
      ..lineTo(c.ux(0.5 + flare), top + c.u(0.145))
      ..cubicTo(c.ux(0.5 + flare * 0.90), bottom - c.u(0.015),
          c.ux(0.5 + flare * 0.44), bottom, c.ux(0.5), bottom)
      ..cubicTo(c.ux(0.5 - flare * 0.44), bottom, c.ux(0.5 - flare * 0.90),
          bottom - c.u(0.015), c.ux(0.5 - flare), top + c.u(0.145))
      ..lineTo(c.ux(0.5 - flare * 0.84), top + c.u(0.075))
      ..close();
    c.fill(shield, set == 2 ? plate : plateLit);

    if (set == 2) {
      // Light scale-mail: a fine mesh instead of a breastplate.
      final cell = c.u(0.030);
      for (var y = top; y < bottom; y += cell) {
        c.line(
            Offset(c.ux(0.5 - flare), y), Offset(c.ux(0.5 + flare), y), groove,
            width: math.max(0.8, c.u(0.005)));
      }
    } else {
      c.line(Offset(c.ux(0.5 - 0.100), top), Offset(c.ux(0.5 + 0.100), top),
          Color.lerp(plateLit, Colors.white, 0.35)!,
          width: math.max(1, c.u(0.010)));
      // Raised centre ridge. Full-width grooves read as a smiling mouth, so
      // seams stay short and low.
      c.fill(
        Path()
          ..moveTo(c.ux(0.5 - 0.030), top + c.u(0.02))
          ..lineTo(c.ux(0.5 + 0.030), top + c.u(0.02))
          ..lineTo(c.ux(0.5 + 0.022), bottom - c.u(0.03))
          ..lineTo(c.ux(0.5 - 0.022), bottom - c.u(0.03))
          ..close(),
        Color.lerp(plateLit, Colors.white, 0.22)!,
      );
      final low = top + c.u(0.185);
      final gw = flare * 0.52;
      c.line(Offset(c.ux(0.5 - gw), low), Offset(c.ux(0.5 + gw), low), groove,
          width: math.max(1, c.u(0.009)));
      if (dense) {
        final gw2 = flare * 0.30;
        c.line(
          Offset(c.ux(0.5 - gw2), top + c.u(0.105)),
          Offset(c.ux(0.5 + gw2), top + c.u(0.105)),
          groove,
          width: math.max(1, c.u(0.008)),
        );
      }
    }

    // ── Gorget over the throat, with the faction gem ───────────────
    c.fill(
      Path()
        ..moveTo(c.ux(0.5 - 0.098), st - c.u(0.060))
        ..lineTo(c.ux(0.5 - 0.072), st + c.u(0.120))
        ..lineTo(c.ux(0.5 + 0.072), st + c.u(0.120))
        ..lineTo(c.ux(0.5 + 0.098), st - c.u(0.060))
        ..close(),
      Color.lerp(plate, plateLit, 0.5)!,
    );
    c.dot(Offset(c.ux(0.5), st + c.u(0.022)), c.u(0.020), c.accent);
  }

  // ── Backdrop: a forge world ─────────────────────────────────────
  //
  // The Duran are a warrior caste, so their environment is heat and industry
  // rather than the faction's political colour. All three stay dark enough that
  // green scaled skin and a lit armour edge carry the read; a hot backdrop
  // competing with a hot crest would flatten the portrait.

  @override
  void backdropVariant(AvatarDrawContext c, int index) {
    switch (index) {
      case 1:
        _emberField(c);
      case 2:
        _voidBackdrop(c);
      default:
        _forgeGlow(c);
    }
    c.vignette();
  }

  /// A forge mouth burning somewhere behind the pilot's shoulder.
  void _forgeGlow(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF0B0A0C));
    final o = c.headCenter;
    final w = c.size.width;
    final h = c.size.height;
    // Low and off-centre, so it rakes across the armour instead of sitting
    // behind the head as a halo.
    final mouth = Offset(o.dx + w * 0.22, h * 0.86);
    c.glow(mouth.dx, mouth.dy, c.u(0.62),
        const Color(0xFFD6551A).withValues(alpha: 0.55));
    c.glow(mouth.dx, mouth.dy, c.u(0.26),
        const Color(0xFFFFB04A).withValues(alpha: 0.60));
    c.glow(mouth.dx, mouth.dy, c.u(0.10),
        const Color(0xFFFFE7B0).withValues(alpha: 0.55));
    // A dull wash of reflected light on the opposite wall.
    c.glow(w * 0.12, h * 0.30, c.u(0.34),
        const Color(0xFF6B2E12).withValues(alpha: 0.42));
  }

  /// Embers rising off a cooling floor, plus a warm horizon.
  void _emberField(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF0A0A10));
    final h = c.size.height;
    final w = c.size.width;
    // Horizon: the floor is lit, the air above it is not.
    c.canvas.drawRect(
      Rect.fromLTWH(0, h * 0.72, w, h * 0.28),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFB8410F).withValues(alpha: 0.0),
            const Color(0xFFB8410F).withValues(alpha: 0.45),
            const Color(0xFF2A0E06).withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.45, 1.0],
        ).createShader(Rect.fromLTWH(0, h * 0.72, w, h * 0.28)),
    );
    final r = c.scoped(0x0D);
    for (var i = 0; i < 16; i++) {
      // Density falls off with height so the embers read as rising rather than
      // as a uniform scatter of dots.
      final t = r.nextDouble();
      final x = r.nextDouble() * w;
      final y = h * (0.92 - t * 0.78);
      final radius = c.u(0.006 + (1 - t) * 0.008);
      final warm = t < 0.5 ? const Color(0xFFFFC46A) : const Color(0xFFE2701F);
      c.glow(x, y, radius * 3.4, warm.withValues(alpha: 0.30 * (1 - t * 0.6)));
      c.dot(Offset(x, y), radius, warm.withValues(alpha: 0.55 + (1 - t) * 0.4));
    }
  }

  /// Near-empty space. The darkest option, which is what makes the scales and
  /// the lit eye slits carry the whole portrait.
  void _voidBackdrop(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF05060A));
    final w = c.size.width;
    final h = c.size.height;
    // A single cold rim down one side — enough to separate the silhouette from
    // the background without lighting the face a second time.
    c.canvas.drawRect(
      Rect.fromLTWH(0, 0, w, h),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            const Color(0xFF1B2740).withValues(alpha: 0.55),
            const Color(0xFF000000).withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    // Two dim motes, well apart. Any more and this stops reading as empty.
    final r = c.scoped(0x0E);
    for (var i = 0; i < 2; i++) {
      c.glow(r.nextDouble() * w, r.nextDouble() * h * 0.5, c.u(0.05),
          const Color(0xFF8FA8C8).withValues(alpha: 0.16));
    }
  }

  @override
  void crest(AvatarDrawContext c) {
    // A reptile wears armour, not a haircut. Chitin crest grown from the skull.
    final o = c.headCenter;
    final r = c.headR;
    final plate = Color.lerp(c.skinShadow, Colors.black, 0.30)!;
    // Bent by presentation as well as the `hair` axis: male get a heavy angular
    // brow crest, female a plumed one swept well back, neutral a low ridge.
    final sweep = c.presentation == AvatarPresentation.female
        ? 0.62
        : (c.presentation == AvatarPresentation.male ? -0.14 : 0.10);

    switch (c.style.hair) {
      case 1: // swept crest
        c.fill(
          Path()
            ..moveTo(o.dx - r * 0.88, o.dy - r * 0.58)
            ..quadraticBezierTo(o.dx - r * 0.34, o.dy - r * (1.52 - sweep),
                o.dx + r * (0.40 + sweep), o.dy - r * (1.70 - sweep * 0.7))
            ..quadraticBezierTo(
                o.dx + r * 1.08,
                o.dy - r * (1.50 - sweep * 0.6),
                o.dx + r * 0.94,
                o.dy - r * 0.50)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 0.96, o.dx - r * 0.88, o.dy - r * 0.58)
            ..close(),
          plate,
        );
      case 2: // spike crown, count and rake by presentation
        final spikes = c.presentation == AvatarPresentation.female ? 4 : 3;
        final rake = c.presentation == AvatarPresentation.female ? 0.22 : 0.0;
        final p = Path()..moveTo(o.dx - r * 0.82, o.dy - r * 0.56);
        for (var i = 0; i < spikes; i++) {
          final x0 = o.dx - r * 0.82 + i * (r * 1.64 / spikes);
          p
            ..lineTo(x0 + r * 0.10, o.dy - r * (1.36 + 0.16 * (i % 2) - rake))
            ..lineTo(x0 + r * (0.46 + rake), o.dy - r * 0.70);
        }
        p
          ..lineTo(o.dx + r * 0.86, o.dy - r * 0.54)
          ..quadraticBezierTo(
              o.dx, o.dy - r * 0.98, o.dx - r * 0.82, o.dy - r * 0.56)
          ..close();
        c.fill(p, plate);
      default: // low centre ridge
        c.fill(
          Path()
            ..moveTo(o.dx - r * 0.70, o.dy - r * 0.70)
            ..quadraticBezierTo(o.dx, o.dy - r * (1.36 - sweep * 0.5),
                o.dx + r * 0.70, o.dy - r * 0.70)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 0.94, o.dx - r * 0.70, o.dy - r * 0.70)
            ..close(),
          plate,
        );
    }
  }
}
