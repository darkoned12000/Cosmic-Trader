import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

/// Terran art: humans in practical jumpsuits and merchant finery.
///
/// Lore: *"diverse Terrans in practical jumpsuits or merchant finery"*. Humans
/// have no alien anatomy to draw, so personality is carried by **kit** — which
/// is also exactly what the lore describes.
///
/// ## Male faces
///
/// An earlier pass gave every presentation the same rounded skull, the same
/// thin high brows, and the same wide round eyes, so male and female Terrans
/// read identically — the male faces looked girlish. Three changes fix it, and
/// none of them is a colour change:
///
///   * a **squarer skull** for the male presentation — wider jaw, flatter chin;
///   * **lower, heavier, straighter brows** instead of thin high arches;
///   * a **heavier upper lid**, which reads as a squint.
///
/// The player's [AvatarStyle.eyes] choice is still honoured; only the lid weight
/// and the skull/brow geometry bend with presentation.
class TerranArt extends SpeciesArt {
  const TerranArt();

  @override
  AvatarSpecies get species => AvatarSpecies.terran;

  @override
  Path headPath(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    switch (c.presentation) {
      case AvatarPresentation.male:
        // Wider jaw, squarer corners, flatter chin, heavier brow shelf.
        return Path()
          ..moveTo(o.dx, o.dy - r * 1.10)
          ..cubicTo(o.dx + r * 0.92, o.dy - r * 1.08, o.dx + r * 1.00,
              o.dy - r * 0.30, o.dx + r * 0.98, o.dy + r * 0.20)
          ..lineTo(o.dx + r * 0.86, o.dy + r * 0.74)
          ..lineTo(o.dx + r * 0.52, o.dy + r * 1.06)
          ..lineTo(o.dx - r * 0.52, o.dy + r * 1.06)
          ..lineTo(o.dx - r * 0.86, o.dy + r * 0.74)
          ..lineTo(o.dx - r * 0.98, o.dy + r * 0.20)
          ..cubicTo(o.dx - r * 1.00, o.dy - r * 0.30, o.dx - r * 0.92,
              o.dy - r * 1.08, o.dx, o.dy - r * 1.10)
          ..close();
      case AvatarPresentation.female:
        // Narrower, more tapered, softer jaw.
        return Path()
          ..moveTo(o.dx, o.dy - r * 1.10)
          ..cubicTo(o.dx + r * 0.84, o.dy - r * 1.06, o.dx + r * 0.90,
              o.dy - r * 0.34, o.dx + r * 0.84, o.dy + r * 0.16)
          ..cubicTo(o.dx + r * 0.78, o.dy + r * 0.78, o.dx + r * 0.36,
              o.dy + r * 1.12, o.dx, o.dy + r * 1.10)
          ..cubicTo(o.dx - r * 0.36, o.dy + r * 1.12, o.dx - r * 0.78,
              o.dy + r * 0.78, o.dx - r * 0.84, o.dy + r * 0.16)
          ..cubicTo(o.dx - r * 0.90, o.dy - r * 0.34, o.dx - r * 0.84,
              o.dy - r * 1.06, o.dx, o.dy - r * 1.10)
          ..close();
      case AvatarPresentation.neutral:
        return Path()
          ..moveTo(o.dx, o.dy - r * 1.10)
          ..cubicTo(o.dx + r * 0.88, o.dy - r * 1.06, o.dx + r * 0.94,
              o.dy - r * 0.34, o.dx + r * 0.90, o.dy + r * 0.16)
          ..cubicTo(o.dx + r * 0.84, o.dy + r * 0.82, o.dx + r * 0.42,
              o.dy + r * 1.10, o.dx, o.dy + r * 1.10)
          ..cubicTo(o.dx - r * 0.42, o.dy + r * 1.10, o.dx - r * 0.84,
              o.dy + r * 0.82, o.dx - r * 0.90, o.dy + r * 0.16)
          ..cubicTo(o.dx - r * 0.94, o.dy - r * 0.34, o.dx - r * 0.88,
              o.dy - r * 1.06, o.dx, o.dy - r * 1.10)
          ..close();
    }
  }

  @override
  void appendages(AvatarDrawContext c) {
    _ears(c);
    _gear(c);
  }

  /// Ears. The strongest single cue that a head is human, and an appendage
  /// because they reach past the skull.
  void _ears(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(o.dx + side * r * 0.86, o.dy - r * 0.14)
          ..quadraticBezierTo(o.dx + side * r * 1.30, o.dy - r * 0.18,
              o.dx + side * r * 0.92, o.dy + r * 0.28)
          ..close(),
        c.skinShadow,
      );
    }
  }

  /// Worn gear. These are worn things, not painted on, so they live in their
  /// own `gear` slot rather than the markings axis. A null slot resolves through
  /// [AvatarStyle.effectiveGear], which keeps the old coupling to `outfit` so
  /// existing pilots keep whatever they were wearing.
  ///
  /// Unclipped, because a headset band and a goggle strap both cross the head
  /// silhouette.
  void _gear(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    switch (c.style.effectiveGear) {
      case 1:
        c.dot(Offset(o.dx + r * 0.96, o.dy + r * 0.02), r * 0.30, c.clothTrim);
        c.line(
          Offset(o.dx + r * 0.96, o.dy - r * 0.26),
          Offset(o.dx - r * 0.30, o.dy - r * 0.96),
          c.clothTrim,
          width: math.max(1.5, c.u(0.030)),
        );
        c.line(
          Offset(o.dx - r * 0.30, o.dy - r * 0.96),
          Offset(o.dx - r * 0.62, o.dy - r * 0.38),
          c.clothTrim,
          width: math.max(1, c.u(0.018)),
        );
        c.dot(Offset(o.dx - r * 0.66, o.dy - r * 0.32), r * 0.10, c.accent);
      case 2:
        final bandY = o.dy - r * 0.84;
        c.fill(
          Path()
            ..addRect(Rect.fromLTRB(
                o.dx - r * 1.0, bandY, o.dx + r * 1.0, bandY + r * 0.30)),
          c.clothTrim,
        );
        for (final side in [-1.0, 1.0]) {
          final lens = RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(o.dx + side * r * 0.42, bandY + r * 0.15),
                width: r * 0.72,
                height: r * 0.46),
            Radius.circular(r * 0.18),
          );
          c.canvas.drawRRect(
              lens, Paint()..color = Color.lerp(c.accent, Colors.white, 0.4)!);
          c.canvas.drawRRect(
            lens,
            Paint()
              ..color = Colors.black.withValues(alpha: 0.4)
              ..style = PaintingStyle.stroke
              ..strokeWidth = math.max(1, c.u(0.012)),
          );
        }
      default:
        break;
    }
  }

  @override
  void faceTexture(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    // Nose.
    c.line(
      Offset(o.dx, o.dy - r * 0.02),
      Offset(o.dx, o.dy + r * 0.42),
      c.skinShadow,
      width: math.max(1, c.u(0.016)),
    );
    // A brow shelf shadow on the male skull, so the heavier brows sit on
    // something rather than floating on a round face.
    if (c.presentation == AvatarPresentation.male) {
      c.fill(
        Path()
          ..moveTo(o.dx - r * 0.86, o.dy - r * 0.30)
          ..quadraticBezierTo(
              o.dx, o.dy - r * 0.52, o.dx + r * 0.86, o.dy - r * 0.30)
          ..lineTo(o.dx + r * 0.80, o.dy - r * 0.16)
          ..quadraticBezierTo(
              o.dx, o.dy - r * 0.36, o.dx - r * 0.80, o.dy - r * 0.16)
          ..close(),
        c.skinShadow.withValues(alpha: 0.28),
      );
    }

    // Markings. 0 is unmarked by design; the reroll weighting keeps 1 and 2
    // common enough to be worth seeing.
    switch (c.style.markings) {
      case 1:
        final dot = Paint()..color = c.skinShadow.withValues(alpha: 0.55);
        for (final side in [-1.0, 1.0]) {
          for (var i = 0; i < 4; i++) {
            c.dot(
              Offset(o.dx + side * r * (0.52 + i * 0.11),
                  o.dy + r * (0.30 - i * 0.13)),
              math.max(0.8, r * 0.035),
              dot.color,
            );
          }
        }
      case 2:
        c.line(
          Offset(o.dx + r * 0.22, o.dy - r * 0.50),
          Offset(o.dx + r * 0.74, o.dy + r * 0.18),
          c.skinShadow,
          width: math.max(1, c.u(0.022)),
        );
      default:
        break;
    }
  }

  @override
  void eyes(AvatarDrawContext c, {int? eyeShapeIndex}) {
    // The male presentation gets a heavier upper lid, which reads as a squint.
    // The player's shape choice is still honoured; only the lid weight bends.
    super.eyes(c, eyeShapeIndex: eyeShapeIndex);
  }

  @override
  double lidWidth(AvatarDrawContext c) =>
      c.presentation == AvatarPresentation.male ? 0.030 : 0.014;

  @override
  void expression(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    final male = c.presentation == AvatarPresentation.male;
    final female = c.presentation == AvatarPresentation.female;

    // Brows: the male presentation gets them lower, thicker, and straighter.
    // Thin high arches are the single strongest "girlish" signal on a
    // stylised face.
    final browY = o.dy -
        r *
            (male
                ? 0.40
                : female
                    ? 0.32
                    : 0.34);
    final browW = math.max(
        1.0,
        c.u(male
            ? 0.040
            : female
                ? 0.018
                : 0.026));
    final arch = switch (c.style.expression) {
      1 => 1.0,
      2 => -0.5,
      _ => 0.0,
    };
    // A male brow is nearly straight; the female one arches.
    final inner = male ? 0.02 : 0.10;
    for (final side in [-1.0, 1.0]) {
      c.stroke(
        Path()
          ..moveTo(o.dx + side * r * 0.76, browY - side * arch * r * 0.10)
          ..quadraticBezierTo(
              o.dx + side * r * 0.50,
              browY - r * inner - side * arch * r * 0.02,
              o.dx + side * r * 0.26,
              browY + side * arch * r * 0.06),
        c.skinShadow,
        width: browW,
      );
    }

    // Mouth: wider and heavier on the male face.
    final mouthY = o.dy + r * 0.66;
    final halfWidth = r *
        (male
            ? 0.32
            : female
                ? 0.22
                : 0.26);
    final curve = switch (c.style.expression) {
      1 => -0.14,
      2 => 0.18,
      _ => 0.0,
    };
    c.stroke(
      Path()
        ..moveTo(o.dx - halfWidth, mouthY)
        ..quadraticBezierTo(o.dx, mouthY + r * curve, o.dx + halfWidth, mouthY),
      c.skinShadow,
      width: math.max(1, c.u(male ? 0.024 : 0.016)),
    );
  }

  @override
  void outfit(AvatarDrawContext c) {
    final st = c.shoulderTop;
    final sw = c.shoulderWidth;
    // The collar's lapels and the closure meet at one shared point, so the
    // garment reads as a single piece rather than a scarf over a vest.
    final placketTop = st + c.u(0.20);
    const neckHalf = 0.070;
    final collarOuter = sw * 0.64;

    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(c.ux(0.5 + side * neckHalf), st - c.u(0.085))
          ..lineTo(c.ux(0.5 + side * collarOuter), st + c.u(0.15))
          ..lineTo(c.ux(0.5 + side * collarOuter * 0.52), st + c.u(0.19))
          ..lineTo(c.ux(0.5 + side * 0.010), placketTop)
          ..close(),
        c.clothTrim,
      );
    }
    c.fill(
      Path()
        ..addRect(Rect.fromLTRB(c.ux(0.5 - neckHalf), st - c.u(0.085),
            c.ux(0.5 + neckHalf), st - c.u(0.030))),
      c.clothTrim,
    );

    final placketX = c.ux(0.5);
    final run = c.u(0.30);
    switch (c.style.outfit) {
      case 1: // buttoned merchant coat
        c.line(
          Offset(placketX, placketTop),
          Offset(placketX, placketTop + run),
          Color.lerp(c.cloth, Colors.black, 0.40)!,
          width: math.max(1, c.u(0.010)),
        );
        for (var i = 0; i < 3; i++) {
          c.dot(
            Offset(placketX + c.u(0.022), placketTop + run * (0.20 + i * 0.30)),
            math.max(1.2, c.u(0.013)),
            c.clothTrim,
          );
        }
        for (final side in [-1.0, 1.0]) {
          c.fill(
            Path()
              ..moveTo(c.ux(0.5 + side * neckHalf), st - c.u(0.085))
              ..lineTo(c.ux(0.5 + side * 0.135), st - c.u(0.20))
              ..lineTo(c.ux(0.5 + side * 0.175), st - c.u(0.06))
              ..close(),
            c.clothTrim,
          );
        }
      case 2: // cross harness, no closure
        final w = c.u(0.030);
        for (final side in [-1.0, 1.0]) {
          c.line(
            Offset(c.ux(0.5 + side * sw * 0.74), placketTop + c.u(0.020)),
            Offset(c.ux(0.5 - side * 0.11), placketTop + c.u(0.240)),
            c.clothTrim,
            width: w,
          );
        }
        c.canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(placketX, placketTop + c.u(0.130)),
                width: c.u(0.060),
                height: c.u(0.052)),
            Radius.circular(c.u(0.014)),
          ),
          Paint()..color = c.accent,
        );
      default: // zippered flight suit
        // Teeth start below the collar join so the two never overlap, and butt
        // caps keep the track from curling into a U at the top.
        final start = placketTop + c.u(0.010);
        c.line(
          Offset(placketX, start),
          Offset(placketX, start + run),
          Color.lerp(c.cloth, Colors.white, 0.26)!,
          width: math.max(1, c.u(0.011)),
        );
        final teeth = Color.lerp(c.cloth, Colors.black, 0.50)!;
        for (var t = c.u(0.014); t < run; t += c.u(0.024)) {
          for (final side in [-1.0, 1.0]) {
            c.line(
              Offset(placketX + side * c.u(0.011), start + t),
              Offset(placketX + side * c.u(0.011), start + t + c.u(0.013)),
              teeth,
              width: math.max(1, c.u(0.008)),
            );
          }
        }
        c.canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
                center: Offset(placketX + c.u(0.020), start + c.u(0.030)),
                width: c.u(0.017),
                height: c.u(0.032)),
            Radius.circular(c.u(0.008)),
          ),
          Paint()..color = c.clothTrim,
        );
    }

    // Faction-coloured insignia: this and the AvatarCanvas ring are where
    // faction identity lives now that skin is no longer tinted by faction.
    for (final side in [-1.0, 1.0]) {
      c.dot(Offset(c.ux(0.5 + side * sw * 0.60), st + c.u(0.17)), c.u(0.024),
          c.accent);
    }
  }

  // ── Backdrop: human-scale places ────────────────────────────────
  //
  // Unlike the Duran and Vinari, the Traders' world is a place rather than a
  // phenomenon, so these read as architecture: a hangar deck, open space, and a
  // viewport. All three are low-saturation on purpose — a busy backdrop behind
  // a human face is the classic way to make a face unreadable.

  @override
  void backdropVariant(AvatarDrawContext c, int index) {
    switch (index) {
      case 1:
        _starfield(c);
      case 2:
        _viewport(c);
      default:
        _hangar(c);
    }
    c.vignette();
  }

  /// A hangar deck: horizon line, floor gradient, two structural light bars.
  void _hangar(AvatarDrawContext c) {
    final w = c.size.width;
    final h = c.size.height;
    final horizon = h * 0.66;
    c.canvas.drawRect(
      Offset.zero & c.size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF141A22), Color(0xFF1E2833)],
        ).createShader(Offset.zero & c.size),
    );
    // Deck, receding: lighter at the horizon, dark again at the near edge.
    c.canvas.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0xFF2C3947), Color(0xFF0C1015)],
        ).createShader(Rect.fromLTWH(0, horizon, w, h - horizon)),
    );
    c.line(Offset(0, horizon), Offset(w, horizon), const Color(0xFF4A6076),
        width: math.max(1, c.u(0.005)));
    // Two light bars receding toward the horizon, so the space has a vanishing
    // point rather than reading as a flat two-tone split.
    for (final side in [-1.0, 1.0]) {
      c.canvas.drawPath(
        Path()
          ..moveTo(c.ux(0.5 + side * 0.34), h)
          ..lineTo(c.ux(0.5 + side * 0.17), horizon),
        Paint()
          ..color = const Color(0xFF7FA8C8).withValues(alpha: 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1, c.u(0.008)),
      );
    }
    c.glow(w * 0.5, horizon, c.u(0.30),
        const Color(0xFF6E93B0).withValues(alpha: 0.16));
  }

  /// Open space. The most legible option at 48px, and the most obviously
  /// "outside", which is why it exists as an alternative to the interior.
  void _starfield(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF04050A));
    final w = c.size.width;
    final h = c.size.height;
    final r = c.scoped(0x0F);
    // Draw the small majority first, then a few brighter ones on top.
    for (var i = 0; i < 46; i++) {
      c.dot(
        Offset(r.nextDouble() * w, r.nextDouble() * h),
        c.u(0.0035),
        const Color(0xFFDCE6F5).withValues(alpha: 0.35 + r.nextDouble() * 0.30),
      );
    }
    for (var i = 0; i < 5; i++) {
      final at = Offset(r.nextDouble() * w, r.nextDouble() * h);
      // A tight halo only. A wide one made several bright stars read as a single
      // lens-flare column whenever the draw happened to clump them.
      c.glow(at.dx, at.dy, c.u(0.015),
          const Color(0xFFBFD8FF).withValues(alpha: 0.20));
      c.dot(at, c.u(0.007), const Color(0xFFF2F7FF).withValues(alpha: 0.90));
    }
  }

  /// A viewport: the limb of a planet filling the lower third.
  ///
  /// The arc is the whole point — it is the one backdrop with a hard edge, and
  /// the only silhouette in the set that is not the pilot's own.
  void _viewport(AvatarDrawContext c) {
    c.fillBase(const Color(0xFF03040A));
    final w = c.size.width;
    final h = c.size.height;
    // Planet centre well below the frame, so only the shoulder of it shows.
    final center = Offset(w * 0.34, h * 1.62);
    final radius = c.u(1.34);
    c.canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          // Deliberately dull. A bright teal limb was the single most luminous
          // thing in frame and pulled the eye off the face, which is the one
          // thing a backdrop must never do.
          colors: const [Color(0xFF1B3A49), Color(0xFF060F17)],
        ).createShader(
          Rect.fromCircle(center: center, radius: radius),
        ),
    );
    // Terminator: a warm rim along the lit edge only.
    c.canvas.save();
    c.canvas.clipPath(Path()
      ..addOval(
        Rect.fromCircle(center: center, radius: radius),
      ));
    c.canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c.u(0.035)
        ..shader = SweepGradient(
          startAngle: math.pi * 0.9,
          endAngle: math.pi * 1.9,
          colors: [
            const Color(0x00000000),
            const Color(0x66FFB877),
            const Color(0x00000000),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );
    c.canvas.restore();
    // A thin atmosphere line just outside the limb.
    c.canvas.drawCircle(
      center,
      radius + c.u(0.012),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = c.u(0.008)
        ..color = const Color(0x3FA8D8FF),
    );
    final starX = c.scoped(0x10);
    final starY = c.scoped(0x11);
    for (var i = 0; i < 12; i++) {
      c.dot(
        Offset(starX.nextDouble() * w, starY.nextDouble() * h * 0.4),
        c.u(0.003),
        const Color(0xFFDCE6F5).withValues(alpha: 0.4),
      );
    }
  }

  @override
  void crest(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    final lean = (c.rng.nextDouble() - 0.5) * 0.30;
    final hair = c.hair;

    switch (c.presentation) {
      case AvatarPresentation.male:
        switch (c.style.hair) {
          case 1: // tall crest
            c.fill(
              Path()
                ..moveTo(o.dx - r * 0.72, o.dy - r * 0.66)
                ..quadraticBezierTo(o.dx - r * 0.30, o.dy - r * 2.06,
                    o.dx + r * (0.20 + lean), o.dy - r * 2.12)
                ..quadraticBezierTo(o.dx + r * 0.70, o.dy - r * 2.02,
                    o.dx + r * 0.74, o.dy - r * 0.64)
                ..quadraticBezierTo(
                    o.dx, o.dy - r * 1.02, o.dx - r * 0.72, o.dy - r * 0.66)
                ..close(),
              hair,
            );
          case 2: // close crop with a forward fin
            c.fill(
              Path()
                ..moveTo(o.dx - r * 0.92, o.dy - r * 0.32)
                ..quadraticBezierTo(o.dx - r * 0.80, o.dy - r * 1.20,
                    o.dx + r * 0.30, o.dy - r * 1.30)
                ..lineTo(o.dx + r * (1.26 + lean), o.dy - r * 1.22)
                ..lineTo(o.dx + r * 0.96, o.dy - r * 0.92)
                ..quadraticBezierTo(
                    o.dx, o.dy - r * 1.00, o.dx - r * 0.92, o.dy - r * 0.32)
                ..close(),
              hair,
            );
          default: // swept back
            c.fill(
              Path()
                ..moveTo(o.dx - r * 0.94, o.dy - r * 0.44)
                ..quadraticBezierTo(o.dx - r * 0.70, o.dy - r * 1.54,
                    o.dx + r * (0.30 + lean), o.dy - r * 1.60)
                ..quadraticBezierTo(o.dx + r * 1.20, o.dy - r * 1.54,
                    o.dx + r * 0.98, o.dy - r * 0.40)
                ..quadraticBezierTo(o.dx + r * 0.40, o.dy - r * 0.98,
                    o.dx - r * 0.94, o.dy - r * 0.44)
                ..close(),
              hair,
            );
        }
      case AvatarPresentation.female:
        switch (c.style.hair) {
          case 1: // centre-parted, long
            c.fill(
              Path()
                ..moveTo(o.dx - r * 1.20, o.dy + r * 1.06)
                ..cubicTo(o.dx - r * 1.26, o.dy - r * 0.80, o.dx - r * 0.50,
                    o.dy - r * 1.50, o.dx, o.dy - r * 1.28)
                ..cubicTo(o.dx + r * 0.50, o.dy - r * 1.50, o.dx + r * 1.26,
                    o.dy - r * 0.80, o.dx + r * 1.20, o.dy + r * 1.06)
                ..lineTo(o.dx + r * 0.90, o.dy + r * 1.06)
                ..cubicTo(o.dx + r * 0.96, o.dy - r * 0.30, o.dx + r * 0.38,
                    o.dy - r * 0.92, o.dx, o.dy - r * 0.92)
                ..cubicTo(o.dx - r * 0.38, o.dy - r * 0.92, o.dx - r * 0.96,
                    o.dy - r * 0.30, o.dx - r * 0.90, o.dy + r * 1.06)
                ..close(),
              hair,
            );
          case 2: // shoulder-length sweep
            c.fill(
              Path()
                ..moveTo(o.dx - r * 1.08, o.dy + r * 0.32)
                ..cubicTo(o.dx - r * 1.30, o.dy - r * 0.70, o.dx - r * 0.54,
                    o.dy - r * 1.42, o.dx + r * (0.30 + lean), o.dy - r * 1.38)
                ..cubicTo(o.dx + r * 1.12, o.dy - r * 1.28, o.dx + r * 1.22,
                    o.dy - r * 0.34, o.dx + r * 1.00, o.dy + r * 0.38)
                ..lineTo(o.dx + r * 0.72, o.dy + r * 0.24)
                ..cubicTo(o.dx + r * 0.88, o.dy - r * 0.30, o.dx + r * 0.54,
                    o.dy - r * 0.86, o.dx - r * 0.26, o.dy - r * 0.86)
                ..cubicTo(o.dx - r * 0.80, o.dy - r * 0.84, o.dx - r * 0.90,
                    o.dy - r * 0.20, o.dx - r * 0.78, o.dy + r * 0.26)
                ..close(),
              hair,
            );
          default: // long fall framing the face
            c.fill(
              Path()
                ..moveTo(o.dx - r * 1.12, o.dy + r * 0.70)
                ..cubicTo(o.dx - r * 1.36, o.dy - r * 0.60, o.dx - r * 0.58,
                    o.dy - r * 1.48, o.dx + r * (0.20 + lean), o.dy - r * 1.42)
                ..cubicTo(o.dx + r * 1.16, o.dy - r * 1.34, o.dx + r * 1.30,
                    o.dy + r * 0.20, o.dx + r * 1.08, o.dy + r * 0.76)
                ..lineTo(o.dx + r * 0.82, o.dy + r * 0.60)
                ..cubicTo(o.dx + r * 0.98, o.dy - r * 0.20, o.dx + r * 0.68,
                    o.dy - r * 0.84, o.dx - r * 0.28, o.dy - r * 0.84)
                ..cubicTo(o.dx - r * 0.84, o.dy - r * 0.82, o.dx - r * 0.94,
                    o.dy - r * 0.10, o.dx - r * 0.84, o.dy + r * 0.62)
                ..close(),
              hair,
            );
        }
      case AvatarPresentation.neutral:
        switch (c.style.hair) {
          case 1: // shaved with a thin band
            c.fill(
              Path()
                ..moveTo(o.dx - r * 0.86, o.dy - r * 0.52)
                ..lineTo(o.dx + r * (0.34 + lean), o.dy - r * 1.00)
                ..lineTo(o.dx + r * 0.88, o.dy - r * 0.48)
                ..lineTo(o.dx + r * 0.80, o.dy - r * 0.34)
                ..lineTo(o.dx + r * (0.24 + lean), o.dy - r * 0.84)
                ..lineTo(o.dx - r * 0.78, o.dy - r * 0.38)
                ..close(),
              hair,
            );
          case 2: // short spikes
            // Irregular and forward-swept on purpose. A symmetric row of
            // evenly-sized triangles read as a *crown* rather than hair, and on
            // a pale dye it read unmistakably as royalty. Real spiked hair is
            // uneven and combed, so the heights vary and the peaks rake to one
            // side.
            final spike = Path()..moveTo(o.dx - r * 0.90, o.dy - r * 0.26);
            const heights = [1.06, 0.86, 1.00, 0.80];
            const rakes = [-0.14, 0.02, -0.06, 0.10];
            for (var i = 0; i < heights.length; i++) {
              final x0 = o.dx - r * 0.90 + i * r * 0.48;
              spike
                ..lineTo(x0 + r * (0.10 + rakes[i]), o.dy - r * heights[i])
                ..lineTo(x0 + r * 0.42, o.dy - r * 0.58);
            }
            spike
              ..lineTo(o.dx + r * 0.90, o.dy - r * 0.24)
              ..quadraticBezierTo(
                  o.dx, o.dy - r * 0.72, o.dx - r * 0.90, o.dy - r * 0.26)
              ..close();
            c.fill(spike, hair);
          default: // close-cropped
            c.fill(
              Path()
                ..moveTo(o.dx - r * 0.90, o.dy - r * 0.30)
                ..quadraticBezierTo(o.dx - r * 0.78, o.dy - r * 1.20,
                    o.dx + r * lean, o.dy - r * 1.22)
                ..quadraticBezierTo(o.dx + r * 0.80, o.dy - r * 1.20,
                    o.dx + r * 0.92, o.dy - r * 0.28)
                ..quadraticBezierTo(o.dx + r * 0.30, o.dy - r * 0.76,
                    o.dx - r * 0.90, o.dy - r * 0.30)
                ..close(),
              hair,
            );
        }
    }
  }
}
