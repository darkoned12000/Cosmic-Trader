import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

/// Vinari art: a luminous, non-humanoid spirit species.
///
/// Lore: *"glowing, fluid forms with shifting colors, like living auroras"*.
///
/// The governing rule is that this is **not a purple human**. The previous
/// single-file version gave the Vinari a humanoid skull with ears, a nose, and
/// a mouth tinted violet, which was the single least convincing thing in the
/// gallery. So: no ears, no nose, no mouth, no sclera; an elongated tapering
/// form; a luminous internal core; and drifting motes, which are the first cue
/// a viewer's eye lands on before any facial detail resolves.
class VinariArt extends SpeciesArt {
  const VinariArt();

  @override
  AvatarSpecies get species => AvatarSpecies.vinari;

  @override
  Path headPath(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    // Elongated teardrop, narrow at the crown, trailing at the base.
    return Path()
      ..moveTo(o.dx, o.dy - r * 1.46)
      ..cubicTo(o.dx + r * 0.52, o.dy - r * 1.30, o.dx + r * 0.86,
          o.dy - r * 0.72, o.dx + r * 0.94, o.dy - r * 0.06)
      ..cubicTo(o.dx + r * 1.00, o.dy + r * 0.52, o.dx + r * 0.52,
          o.dy + r * 1.02, o.dx, o.dy + r * 1.62)
      ..cubicTo(o.dx - r * 0.52, o.dy + r * 1.02, o.dx - r * 1.00,
          o.dy + r * 0.52, o.dx - r * 0.94, o.dy - r * 0.06)
      ..cubicTo(o.dx - r * 0.86, o.dy - r * 0.72, o.dx - r * 0.52,
          o.dy - r * 1.30, o.dx, o.dy - r * 1.46)
      ..close();
  }

  @override
  void appendages(AvatarDrawContext c) {
    // Drift motes. Drawn first of everything so they sit furthest back.
    for (var i = 0; i < 7; i++) {
      final a = c.rng.nextDouble() * math.pi * 2;
      final d = c.u(0.16 + c.rng.nextDouble() * 0.26);
      c.glow(
        c.headCenter.dx + math.cos(a) * d,
        c.headCenter.dy + math.sin(a) * d * 0.9,
        c.u(0.012 + c.rng.nextDouble() * 0.020),
        c.hair.withValues(alpha: 0.55),
      );
    }
    _frills(c);
  }

  /// Temple frills and crown filaments — both reach past the head, so both are
  /// appendages rather than face texture.
  void _frills(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(o.dx + side * r * 0.78, o.dy - r * 0.30)
          ..cubicTo(
              o.dx + side * r * 1.44,
              o.dy - r * 0.72,
              o.dx + side * r * 1.40,
              o.dy + r * 0.28,
              o.dx + side * r * 0.82,
              o.dy + r * 0.54)
          ..close(),
        c.hair.withValues(alpha: 0.34),
      );
    }
    for (var i = 0; i < 3; i++) {
      final x = o.dx + (i - 1) * r * 0.36;
      c.line(
        Offset(x, o.dy - r * 1.20),
        Offset(x + (i.isEven ? 1 : -1) * r * 0.18, o.dy - r * 1.90),
        c.hair.withValues(alpha: 0.40),
        width: math.max(1, c.u(0.012)),
      );
    }
  }

  @override
  void faceTexture(AvatarDrawContext c) {
    // An internal luminous core plus bands of shifting colour. The "form" is the
    // character here, so there is no skull, nose, or mouth to draw.
    final o = c.headCenter;
    final r = c.headR;
    c.glow(o.dx, o.dy + r * 0.10, r * 1.25, c.hair.withValues(alpha: 0.30));
    for (var i = 0; i < 3; i++) {
      final y = o.dy - r * 0.70 + i * r * 0.52;
      c.fill(
        Path()
          ..moveTo(o.dx - r * 0.80, y)
          ..cubicTo(o.dx - r * 0.30, y - r * 0.20, o.dx + r * 0.30,
              y + r * 0.20, o.dx + r * 0.80, y)
          ..lineTo(o.dx + r * 0.80, y + r * 0.09)
          ..cubicTo(o.dx + r * 0.30, y + r * 0.29, o.dx - r * 0.30,
              y - r * 0.11, o.dx - r * 0.80, y + r * 0.09)
          ..close(),
        c.hair.withValues(alpha: 0.34),
      );
    }
  }

  @override
  void outfit(AvatarDrawContext c) {
    // A shroud, not a garment with a closure. The `outfit` axis still applies —
    // it used to be inert here, which left one of eight axes doing nothing for
    // a third of the gallery.
    final st = c.shoulderTop;
    final sw = c.shoulderWidth;
    // Lapels meeting at the centre front, matching the other species so the
    // silhouettes stay comparable in the gallery.
    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(c.ux(0.5 + side * 0.070), st - c.u(0.085))
          ..lineTo(c.ux(0.5 + side * sw * 0.64), st + c.u(0.15))
          ..lineTo(c.ux(0.5 + side * sw * 0.33), st + c.u(0.19))
          ..lineTo(c.ux(0.5 + side * 0.010), st + c.u(0.20))
          ..close(),
        c.clothTrim,
      );
    }
    c.fill(
      Path()
        ..moveTo(c.ux(0.5 - 0.070), st - c.u(0.085))
        ..lineTo(c.ux(0.5 + 0.070), st - c.u(0.085))
        ..lineTo(c.ux(0.5 + 0.070), st - c.u(0.030))
        ..lineTo(c.ux(0.5 - 0.070), st - c.u(0.030))
        ..close(),
      c.clothTrim,
    );

    switch (c.style.outfit) {
      case 1: // layered mantle
        for (var i = 0; i < 2; i++) {
          final spread = 0.58 - i * 0.16;
          for (final side in [-1.0, 1.0]) {
            c.fill(
              Path()
                ..moveTo(c.ux(0.5 + side * 0.070), st - c.u(0.070))
                ..lineTo(
                    c.ux(0.5 + side * sw * spread), st + c.u(0.16 + i * 0.08))
                ..lineTo(c.ux(0.5 + side * 0.02), st + c.u(0.20 + i * 0.10))
                ..close(),
              i == 0 ? c.clothTrim : c.cloth,
            );
          }
        }
      case 2: // halo collar of drifting light
        for (final side in [-1.0, 1.0]) {
          c.fill(
            Path()
              ..moveTo(c.ux(0.5 + side * 0.070), st - c.u(0.085))
              ..lineTo(c.ux(0.5 + side * 0.175), st - c.u(0.22))
              ..lineTo(c.ux(0.5 + side * 0.215), st - c.u(0.05))
              ..close(),
            c.clothTrim,
          );
        }
      default: // plain shroud
        break;
    }

    for (final side in [-1.0, 1.0]) {
      c.dot(Offset(c.ux(0.5 + side * sw * 0.60), st + c.u(0.16)), c.u(0.024),
          c.accent);
    }
  }

  // ── Backdrop: living light ──────────────────────────────────────
  //
  // The lore is "glowing, fluid forms with shifting colors, like living
  // auroras", so the Vinari environment is the only place in the gallery where
  // the backdrop is allowed to be soft and luminous. The constraint that still
  // applies is contrast: the pilot's own glow is drawn later and on top, so
  // every backdrop here stays under it in value and never adds a competing
  // bright core near the head.

  @override
  void backdropVariant(AvatarDrawContext c, int index) {
    switch (index) {
      case 1:
        _nebula(c);
      case 2:
        _deepDrift(c);
      default:
        _aurora(c);
    }
    c.vignette(strength: 0.5, inner: 0.5);
  }

  /// Soft vertical curtains, the way an aurora actually reads.
  ///
  /// Each curtain is sheared rather than drawn as an axis-aligned bar — four
  /// vertical bars read as a barcode, which is the failure mode when this was
  /// first sketched with plain rects.
  void _aurora(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF07070F));
    final w = c.size.width;
    final h = c.size.height;
    final r = c.scoped(0x0A);
    const band = [Color(0xFF7C5CFF), Color(0xFF35C8E8), Color(0xFFB06CFF)];
    for (var i = 0; i < 4; i++) {
      final x = w * (0.08 + i * 0.28 + r.nextDouble() * 0.10);
      final halfWidth = w * (0.05 + r.nextDouble() * 0.06);
      final shear = (i.isEven ? 1.0 : -1.0) * (0.10 + r.nextDouble() * 0.10);
      final color = band[i % band.length];
      final rect =
          Rect.fromLTWH(x - halfWidth, -h * 0.1, halfWidth * 2, h * 1.2);
      c.canvas.save();
      c.canvas.clipRect(Offset.zero & c.size);
      // `Canvas.transform` takes a column-major Float64List, not a Matrix4.
      c.canvas.transform(Matrix4.skewX(shear).storage);
      c.canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.0),
              color.withValues(alpha: 0.30),
              color.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(rect),
      );
      c.canvas.restore();
    }
  }

  /// Mottled cloud with a couple of brighter cores.
  void _nebula(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF0A0614));
    final w = c.size.width;
    final h = c.size.height;
    final r = c.scoped(0x0B);
    const cloud = [Color(0xFFB14FE0), Color(0xFF5B3FD6), Color(0xFF2E7FD6)];
    for (var i = 0; i < 6; i++) {
      final x = r.nextDouble() * w;
      final y = r.nextDouble() * h;
      final radius = c.u(0.16 + r.nextDouble() * 0.22);
      c.glow(x, y, radius, cloud[i % cloud.length].withValues(alpha: 0.20));
    }
    // Two cores, deliberately placed away from the head so the pilot's own
    // luminosity stays the brightest thing in frame.
    c.glow(w * 0.18, h * 0.20, c.u(0.10),
        const Color(0xFFE9C4FF).withValues(alpha: 0.24));
    c.glow(w * 0.84, h * 0.76, c.u(0.08),
        const Color(0xFF9FE8FF).withValues(alpha: 0.20));
  }

  /// Deep, slow, and almost empty — motes rather than clouds.
  void _deepDrift(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF05060E));
    final w = c.size.width;
    final h = c.size.height;
    c.glow(w * 0.5, h * 0.46, c.u(0.34),
        const Color(0xFF4A3C8C).withValues(alpha: 0.26));
    final r = c.scoped(0x0C);
    for (var i = 0; i < 9; i++) {
      final x = r.nextDouble() * w;
      final y = r.nextDouble() * h;
      final radius = c.u(0.010 + r.nextDouble() * 0.026);
      c.glow(
          x, y, radius * 3.0, const Color(0xFFBFD4FF).withValues(alpha: 0.22));
      c.dot(Offset(x, y), radius * 0.5,
          const Color(0xFFE6EEFF).withValues(alpha: 0.30));
    }
  }

  @override
  void crest(AvatarDrawContext c) {
    // A crown of drifting light. Deliberately soft: an earlier pass drew thin
    // strokes here, which read as insect antennae — the wrong species.
    final o = c.headCenter;
    final r = c.headR;
    switch (c.style.hair) {
      case 1:
        for (var i = 0; i < 5; i++) {
          final x = o.dx + (i - 2) * r * 0.34;
          c.glow(
            x + (i.isEven ? 1 : -1) * r * 0.10,
            o.dy - r * (1.50 + (i % 2) * 0.28),
            c.u(0.075),
            c.hair.withValues(alpha: 0.34 - (i % 2) * 0.10),
          );
        }
      case 2:
        c.fill(
          Path()
            ..moveTo(o.dx - r * 0.86, o.dy - r * 0.86)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 2.20, o.dx + r * 0.86, o.dy - r * 0.86)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 1.10, o.dx - r * 0.86, o.dy - r * 0.86)
            ..close(),
          c.hair.withValues(alpha: 0.30),
        );
      default:
        c.fill(
          Path()
            ..moveTo(o.dx - r * 0.70, o.dy - r * 1.00)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 1.86, o.dx + r * 0.70, o.dy - r * 1.00)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 1.22, o.dx - r * 0.70, o.dy - r * 1.00)
            ..close(),
          c.hair.withValues(alpha: 0.40),
        );
    }
  }
}
