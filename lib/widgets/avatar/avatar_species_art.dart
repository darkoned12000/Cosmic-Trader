import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_duran_art.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_terran_art.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_vinari_art.dart';

/// Everything a species renderer needs for one portrait.
///
/// Exists so the species art files take one argument instead of a fifteen-
/// parameter call, and so a colour added to a portrait is added in exactly two
/// places (the painter's palette lookup, and [field] on this class) rather than
/// threaded through every method signature.
class AvatarDrawContext {
  const AvatarDrawContext({
    required this.canvas,
    required this.size,
    required this.portrait,
    required this.style,
    required this.skin,
    required this.skinShadow,
    required this.skinLight,
    required this.hair,
    required this.cloth,
    required this.clothTrim,
    required this.plateLight,
    required this.accent,
    required this.headCenter,
    required this.headR,
    required this.shoulderTop,
    required this.shoulderWidth,
    required this.jawTaper,
    required this.rng,
  });

  final Canvas canvas;

  /// The full portrait box. The painter has already clipped to whatever shape
  /// the caller wants (a circle, in practice).
  final Size size;

  final AvatarPortrait portrait;

  /// Already sanitized — every axis is in range.
  final AvatarStyle style;

  // Species palette colours. Faction colour lives in [accent] and is used only
  // for the ring, the backdrop, and insignia.
  final Color skin;
  final Color skinShadow;
  final Color skinLight;
  final Color hair;
  final Color cloth;
  final Color clothTrim;
  final Color plateLight;
  final Color accent;

  final Offset headCenter;
  final double headR;
  final double shoulderTop;
  final double shoulderWidth;
  final double jawTaper;

  /// Per-portrait proportion jitter, deterministic from the catalogue id.
  final math.Random rng;

  /// A deterministic generator scoped to [key], independent of [rng].
  ///
  /// Anything drawn **before** the species slots must use this, never [rng].
  /// [rng] is one shared sequence whose draw order is effectively part of the
  /// save format: the Vinari drift motes and the Terran hair lean consume from
  /// it, and the painter draws the backdrop ahead of both. Taking draws from
  /// [rng] in the backdrop would shift every later consumer and silently
  /// repaint portraits saved before the backdrop axis existed — the exact
  /// failure the null-means-coupled rule exists to prevent.
  math.Random scoped(int key) => math.Random(portrait.drawSeed ^ key);

  AvatarSpecies get species => portrait.species;
  AvatarPresentation get presentation => portrait.presentation;

  /// Scales against the *shorter* edge, so portraits stay square-safe.
  double u(double v) => v * math.min(size.width, size.height);
  double ux(double v) => v * size.width;
  double uy(double v) => v * size.height;
  Offset p(double x, double y) => Offset(x * size.width, y * size.height);

  /// A soft radial glow. Used for the Vinari's inner light, the selected halo,
  /// and drift motes.
  void glow(double x, double y, double radius, Color color) {
    if (radius <= 0) return;
    canvas.drawCircle(
      Offset(x, y),
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [color, color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromCircle(center: Offset(x, y), radius: radius)),
    );
  }

  void fill(Path path, Color color) =>
      canvas.drawPath(path, Paint()..color = color);

  void stroke(
    Path path,
    Color color, {
    double width = 1.0,
    StrokeCap cap = StrokeCap.round,
  }) {
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = cap,
    );
  }

  void line(Offset a, Offset b, Color color, {double width = 1.0}) {
    canvas.drawLine(
      a,
      b,
      Paint()
        ..color = color
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round,
    );
  }

  void dot(Offset at, double radius, Color color) {
    canvas.drawCircle(at, radius, Paint()..color = color);
  }

  /// Fills the whole box with [color]. Backdrops start here.
  void fillBase(Color color) {
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  /// Darkens the outer edge of the box.
  ///
  /// Every backdrop ends with one. It is how "a backdrop must not compete with
  /// the pilot" is enforced in a single place rather than re-argued per species:
  /// pulling the edges down keeps the head and shoulders separated from the
  /// environment at 48px, which is where the separation is actually lost.
  void vignette({double strength = 0.6, double inner = 0.42}) {
    if (strength <= 0) return;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          colors: [
            const Color(0x00000000),
            Color(0x00000000),
            Color.fromRGBO(0, 0, 0, strength),
          ],
          stops: [0.0, inner, 1.0],
        ).createShader(rect),
    );
  }
}

/// Per-species portrait art.
///
/// Split one file into three because the three species share a drawing
/// *vocabulary* but almost no drawing *code*: silhouettes, appendages, face
/// texture, and garments are all species-specific, while the layered head
/// shading, eye construction, and expression rig are common.
///
/// ## Layer order is load-bearing
///
/// [AvatarPortraitPainter] draws in exactly this sequence, and each species
/// fills the matching slot:
///
/// 1. `appendages` — anything reaching past the skull (horns, frills, ears,
///    worn gear). **Before** the head fill, or a head clip slices the roots.
/// 2. `headPath` fill.
/// 3. `faceTexture` — inside `clipPath(headPath)`.
/// 4. `eyes` / `expression` / `crest`.
///
/// A previous single-file version drew appendages inside step 3, which cut the
/// Duran horn roots flat and lost the Terran ears almost entirely. The seam
/// exists so that cannot happen again silently.
abstract class SpeciesArt {
  const SpeciesArt();

  /// The species this renderer draws.
  AvatarSpecies get species;

  // ── Required per-species slots ──────────────────────────────────

  /// Skull silhouette. Differs enough between species to be identifiable in
  /// pure black.
  Path headPath(AvatarDrawContext c);

  /// Parts that extend past [headPath]. Drawn *before* the head.
  void appendages(AvatarDrawContext c);

  /// Skin detail inside the head clip: scales, glow bands, freckles, war paint.
  void faceTexture(AvatarDrawContext c);

  /// The body garment.
  void outfit(AvatarDrawContext c);

  // ── Backdrop ────────────────────────────────────────────────────

  /// Step 1. The environment behind the pilot, drawn before anything else.
  ///
  /// A null [AvatarStyle.backdrop] renders [factionBloom] — the single backdrop
  /// every portrait used before the axis existed, and what a pre-axis save must
  /// still render. A set slot dispatches to the species' own list.
  void backdrop(AvatarDrawContext c) {
    final index = c.style.backdrop;
    if (index == null) {
      factionBloom(c);
    } else {
      backdropVariant(c, index);
    }
  }

  /// A species backdrop. [index] is already sanitized into range.
  ///
  /// Defaults to [factionBloom] so a species without bespoke options — or an
  /// index added to the palette without art to match — still renders something
  /// sensible instead of nothing.
  void backdropVariant(AvatarDrawContext c, int index) => factionBloom(c);

  /// The original backdrop: a faction-coloured radial bloom, warm at the centre
  /// falling to near-black at the corners.
  ///
  /// Shared rather than per-species because it is the compatibility path. Any
  /// change here changes every portrait saved before the backdrop axis existed,
  /// so it should stay exactly as it was.
  void factionBloom(AvatarDrawContext c) {
    c.canvas.drawRect(
      Offset.zero & c.size,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Color.lerp(c.accent, Colors.black, 0.42)!,
            const Color(0xFF090C12),
          ],
        ).createShader(Offset.zero & c.size),
    );
  }

  // ── Shared drawing ──────────────────────────────────────────────

  /// Form shadow + jaw-to-neck falloff, clipped to the head.
  ///
  /// This is the difference between a flat silhouette and a modelled face, and
  /// it is shared because it is purely a lighting decision.
  void headShading(AvatarDrawContext c) {
    final canvas = c.canvas;
    final path = headPath(c);
    canvas.save();
    canvas.clipPath(path);

    final r = c.headR;
    final center = c.headCenter;
    canvas.drawRect(
      Rect.fromLTRB(center.dx - r * 1.3, center.dy - r * 1.5,
          center.dx + r * 1.3, center.dy + r * 1.5),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Color(0x00000000), Color(0x1A000000), Color(0x8C000000)],
          stops: [0.0, 0.5, 1.0],
        ).createShader(Rect.fromLTRB(center.dx - r * 1.3, center.dy - r * 1.5,
            center.dx + r * 1.3, center.dy + r * 1.5)),
    );

    // A flat black gradient can't be tinted to the skin's shadow tone, so the
    // jaw falloff is drawn with the real shadow colour.
    canvas.drawRect(
      Rect.fromLTRB(center.dx - r * 1.2, center.dy + r * 0.70,
          center.dx + r * 1.2, center.dy + r * 1.45),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            c.skinShadow.withValues(alpha: 0.0),
            c.skinShadow.withValues(alpha: 0.6),
          ],
        ).createShader(Rect.fromLTRB(center.dx - r * 1.2, center.dy + r * 0.70,
            center.dx + r * 1.2, center.dy + r * 1.45)),
    );
    canvas.restore();
  }

  /// Width of the lid line drawn over the eye. Overridable: the Terran male
  /// presentation uses a heavier lid, which reads as a squint and is one of the
  /// three changes that stop the male faces looking girlish.
  double lidWidth(AvatarDrawContext c) => c.u(0.014);

  /// Eyes. Three shapes, and the species decides whether a sclera exists.
  ///
  /// [eyeShapeIndex] lets a caller override the style's [AvatarStyle.eyes] value.
  void eyes(AvatarDrawContext c, {int? eyeShapeIndex}) {
    final r = c.headR;
    final eyeY = c.headCenter.dy - r * 0.04;
    final dx = r * 0.44;
    final color = AvatarPalette.eye(c.species, c.style.eyes, c.style.eyeColor);

    final shape = eyeShapeIndex ?? c.style.eyes;
    double eyeWidth;
    double eyeHeight;
    var pupilScale = 0.52;
    switch (shape) {
      case 1: // narrow
        eyeWidth = 0.26;
        eyeHeight = 0.11;
        pupilScale = 0.40;
      case 2: // angular
        eyeWidth = 0.30;
        eyeHeight = 0.15;
        pupilScale = 0.36;
      default: // round
        eyeWidth = 0.24;
        eyeHeight = 0.17;
    }

    for (final side in [-1.0, 1.0]) {
      final center = Offset(c.headCenter.dx + side * dx, eyeY);
      final rw = r * eyeWidth;
      final rh = r * eyeHeight;

      Path outline;
      if (shape == 2) {
        outline = Path()
          ..moveTo(center.dx - rw, center.dy + rh * 0.4)
          ..lineTo(center.dx - rw * 0.4, center.dy - rh)
          ..lineTo(center.dx + rw * 0.6, center.dy - rh * 0.8)
          ..lineTo(center.dx + rw, center.dy + rh * 0.2)
          ..lineTo(center.dx, center.dy + rh * 0.8)
          ..close();
      } else {
        outline = Path()
          ..addOval(Rect.fromCenter(center: center, width: rw, height: rh * 2));
      }

      if (AvatarPalette.hasSclera(c.species)) {
        c.fill(outline, const Color(0xFFF4F6FA));
        c.canvas.save();
        c.canvas.clipPath(outline);
        c.dot(center, rh * pupilScale, color);
        if (c.species == AvatarSpecies.duran) {
          // Reptilian vertical slit, sized to survive a 48px downscale.
          c.canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: center,
                width: math.max(1.0, rw * pupilScale * 0.42),
                height: rh * 1.9,
              ),
              Radius.circular(rw * pupilScale * 0.2),
            ),
            Paint()..color = Colors.black.withValues(alpha: 0.9),
          );
        } else {
          c.dot(center, rh * pupilScale * 0.45,
              Colors.black.withValues(alpha: 0.88));
        }
        c.canvas.restore();
        c.dot(center.translate(-rh * 0.24, -rh * 0.30),
            math.max(0.8, rh * 0.18), Colors.white.withValues(alpha: 0.95));
      } else {
        // Luminous, no sclera — a glowing lens sitting on the form.
        c.glow(center.dx, center.dy, rw * 1.5, color.withValues(alpha: 0.5));
        c.fill(outline, color);
        c.dot(center.translate(-rw * 0.22, -rh * 0.3), math.max(0.8, rw * 0.16),
            Colors.white.withValues(alpha: 0.9));
      }

      // Lid line, so the eye reads as set into the face.
      c.stroke(
        Path()
          ..moveTo(center.dx - rw, center.dy - rh * 0.2)
          ..quadraticBezierTo(center.dx, center.dy - rh * 1.5, center.dx + rw,
              center.dy - rh * 0.2),
        Color.lerp(c.skinLight, Colors.black, 0.55)!,
        width: math.max(1, lidWidth(c)),
      );
    }
  }

  /// Brow and mouth. Species without a mouth (the Vinari) get brows only.
  void expression(AvatarDrawContext c) {
    final r = c.headR;
    final browY = c.headCenter.dy - r * 0.34;
    final tilt = switch (c.style.expression) {
      1 => 1.0, // stern
      2 => -0.5, // faintly amused
      _ => 0.0,
    };

    for (final side in [-1.0, 1.0]) {
      c.line(
        Offset(
            c.headCenter.dx + side * r * 0.74, browY - side * tilt * r * 0.14),
        Offset(
            c.headCenter.dx + side * r * 0.30, browY + side * tilt * r * 0.10),
        c.skinShadow,
        width: math.max(1, c.u(0.022)),
      );
    }

    if (c.species == AvatarSpecies.vinari) return;

    final mouthY = c.headCenter.dy + r * 0.66;
    final curve = switch (c.style.expression) {
      1 => -0.14,
      2 => 0.18,
      _ => 0.0,
    };
    c.stroke(
      Path()
        ..moveTo(c.headCenter.dx - r * 0.26, mouthY)
        ..quadraticBezierTo(c.headCenter.dx, mouthY + r * curve,
            c.headCenter.dx + r * 0.26, mouthY),
      c.skinShadow,
      width: math.max(1, c.u(0.016)),
    );
  }

  /// Hair, crest, or drift — see the species subclasses.
  void crest(AvatarDrawContext c);

  /// The renderer for a species.
  static SpeciesArt of(AvatarSpecies species) {
    switch (species) {
      case AvatarSpecies.duran:
        return const DuranArt();
      case AvatarSpecies.vinari:
        return const VinariArt();
      case AvatarSpecies.terran:
        return const TerranArt();
    }
  }
}
