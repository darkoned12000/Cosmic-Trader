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
    // The `hair` axis, which for the Vinari is a **silhouette** axis rather than
    // a surface one. It used to vary only a faint arc above the crown, which
    // made three options read as one — the single biggest variety problem in the
    // gallery, since the Duran have `horns` and the Traders have real hair and
    // the Vinari had nothing. The three forms are the "tendril fall" and
    // "bioluminescent frill" from the design doc's own layer catalogue.
    switch (c.style.hair) {
      case 1:
        _tendrilFall(c);
      case 2:
        _frillFan(c);
      default:
        _crownOfLight(c);
    }
  }

  /// `hair` 0 — a low crown of drifting light. Deliberately the plain option:
  /// the other two carry the silhouette, so this one stays close to the head and
  /// keeps the base look recognisable. Matches the Duran's "low ridge" and the
  /// Terran's "close-cropped" in being the unadorned end of the axis.
  void _crownOfLight(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    for (final side in [-1.0, 1.0]) {
      c.fill(
        Path()
          ..moveTo(o.dx + side * r * 0.78, o.dy - r * 0.30)
          ..cubicTo(
              o.dx + side * r * 1.34,
              o.dy - r * 0.70,
              o.dx + side * r * 1.30,
              o.dy + r * 0.26,
              o.dx + side * r * 0.82,
              o.dy + r * 0.52)
          ..close(),
        c.hair.withValues(alpha: 0.30),
      );
    }
    // No thin strokes off the crown. An earlier pass drew three filaments here
    // and they read unmistakably as insect antennae — the wrong species, and the
    // exact failure the original implementation comment warned about. The plain
    // option does not need them now that the other two carry real silhouette.
  }

  /// `hair` 1 — a fall of long tendrils.
  ///
  /// The widest and longest of the three. Anchored around the upper head and
  /// sweeping out and *down*, so the outline changes rather than just gaining
  /// something above the crown.
  void _tendrilFall(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;
    // Angles in radians, measured **from straight-down**: 0 hangs vertically,
    // positive leans right. Spread symmetrically with a small per-pitch jitter so
    // a roster does not look stamped.
    const spread = [-1.05, -0.62, -0.20, 0.0, 0.20, 0.62, 1.05];
    final lengths = [1.35, 1.70, 2.00, 2.10, 2.00, 1.70, 1.35];
    for (var i = 0; i < spread.length; i++) {
      final side = i < spread.length ~/ 2 ? -1.0 : 1.0;
      final idx = side < 0 ? spread.length - 1 - i : i;
      // Mirror by the *sign* of the angle, not just the anchor — mirroring the
      // anchor alone drew the whole fan on one side, which read as wind-blown
      // hair rather than a symmetric fall.
      //
      // See the note on [_tendril] for why the sign has to be applied *there*.
      final angle = side * (spread[idx] + (c.rng.nextDouble() - 0.5) * 0.10);
      final length = r * lengths[idx] * (0.92 + c.rng.nextDouble() * 0.16);
      // Anchored above the eye line so the roots hide under the head fill.
      final anchor = Offset(
        o.dx + side * r * 0.42,
        o.dy - r * (0.92 - (lengths[idx] - 1.35) * 0.30),
      );
      _tendril(
        c,
        anchor,
        angle,
        length,
        r * 0.11,
        c.hair.withValues(alpha: 0.42),
      );
    }
  }

  /// One tapered tendril with a luminous tip: wide at the root, a point at the
  /// end, bowing slightly away from straight.
  ///
  /// [angle] is measured **from straight-down**, so 0 hangs vertically and
  /// positive leans right. Sign it *here*, at the point the direction is built,
  /// and the fan mirrors correctly. A peer review found this reading the angle
  /// from +x instead: `cos` stayed positive across the entire spread, so every
  /// tendril leaned right and the "symmetric fall" was a one-sided spray. The
  /// comment had claimed a symmetry the maths never produced, which is why it
  /// survived a visual review — the shape still looked like a fan, just a swept
  /// one.
  void _tendril(
    AvatarDrawContext c,
    Offset anchor,
    double angle,
    double length,
    double halfWidth,
    Color color,
  ) {
    // `angle` is measured from straight-down, so the direction is
    // `(sin, cos)` — **not** `(cos, sin)`. With `(cos, sin)` the angle is read
    // from +x instead, `cos` is positive across the whole spread, and every
    // tendril points right: the "symmetric fall" was a one-sided diagonal spray
    // from roots on both sides of the head. A peer review caught that the comment
    // above claimed a symmetry the maths never produced.
    final dir = Offset(math.sin(angle), math.cos(angle));
    final tip = anchor + dir * length;
    final perp = Offset(-dir.dy, dir.dx);
    // A gentle bow, so a fan of them reads as fluid rather than as spikes.
    final mid = anchor + dir * (length * 0.55) + perp * (length * 0.16);
    c.fill(
      Path()
        ..moveTo(
            anchor.dx + perp.dx * halfWidth, anchor.dy + perp.dy * halfWidth)
        ..quadraticBezierTo(mid.dx + perp.dx * halfWidth * 0.55,
            mid.dy + perp.dy * halfWidth * 0.55, tip.dx, tip.dy)
        ..quadraticBezierTo(
            mid.dx - perp.dx * halfWidth * 0.55,
            mid.dy - perp.dy * halfWidth * 0.55,
            anchor.dx - perp.dx * halfWidth,
            anchor.dy - perp.dy * halfWidth)
        ..close(),
      color,
    );
    c.glow(tip.dx, tip.dy, halfWidth * 2.4, color.withValues(alpha: 0.55));
  }

  /// `hair` 2 — a wide membranous frill, like a bell or a lotus petal.
  ///
  /// A crescent membrane reaching ~1.6r out at the temples and ~2.2r above the
  /// crown. Reads as one continuous fan rather than a bundle of strands, which is
  /// what keeps it distinct from the tendrils at 48px.
  ///
  /// Built as three stacked passes — bloom, membrane, lit rim — rather than one
  /// translucent wash. A wash is *darker* than the head it sits behind, so the
  /// frill rendered as a monk's cowl: the dullest shape in a portrait of a
  /// luminous species. Light has to be added for it to read as light.
  ///
  /// ## All three passes come from one geometry
  ///
  /// The fill, both strokes, and the rib endpoints are all derived from a
  /// [_FrillArch] rather than each re-deriving their own curve. A peer review
  /// found three separate defects that all came from those copies drifting apart:
  ///
  ///  - `_frillTip` was used as **pixels** where the constant and its doc both
  ///    said head radii, so the tips sat 1.6px from centre instead of ~50px. The
  ///    frill was a narrow steeple, and the head hid all but the part above the
  ///    crown — which is why it read as a glowing arc and passed visual review.
  ///  - The edge was built `close()`d and then **stroked**, and `drawPath` strokes
  ///    a closed path's closing chord too. That put a hard horizontal line from
  ///    tip to tip across the bottom. Invisible while the tips were 1.6px apart;
  ///    a visible lampshade cut the moment the units were fixed.
  ///  - The rib endpoints came from a *quadratic* through the same three points,
  ///    whose midpoint only reaches halfway to its control. The ribs therefore
  ///    peaked at ~0.96r — **below the 1.46r crown** — and were hidden behind the
  ///    skull. The comment claimed they had been fixed; they had not.
  ///
  /// `_FrillArch.pointAt` evaluates the real cubics, so an endpoint cannot land
  /// somewhere the drawn edge does not.
  void _frillFan(AvatarDrawContext c) {
    final o = c.headCenter;
    final r = c.headR;

    // The inner edge sits just under the crown (1.46r) so the membrane always
    // covers the skull and shows a clean crescent above it, rather than leaving a
    // gap at the top on a narrow head.
    final outer = _FrillArch(c, reach: 1.06, apex: 2.16);
    final inner = _FrillArch(c, reach: 0.90, apex: 1.38);

    // 1. Bloom along the lit edge, wide and faint. This is the pass that makes
    //    the frill emit rather than merely occupy space.
    c.stroke(
      outer.path,
      c.hair.withValues(alpha: 0.15),
      width: c.u(0.14),
    );
    // 2. The membrane: one explicit outline, outer edge forward and inner edge
    //    backward. `Path.combine(difference)` on two arches that share their tips
    //    leaves hairline slivers along the coincident chord, so the shape is
    //    walked out by hand instead.
    c.fill(outer.membraneWith(inner), c.hair.withValues(alpha: 0.30));
    // 3. A crisp rim just inside the outer edge, so the silhouette keeps a hard
    //    boundary at 48px where the bloom has already faded.
    c.stroke(
      _FrillArch(c, reach: 1.02, apex: 2.12).path,
      c.hair.withValues(alpha: 0.72),
      width: math.max(1.5, c.u(0.014)),
    );

    // Ribs radiating from a hub just inside the crown out onto the membrane
    // edge. They are the only straight lines on the form and therefore what
    // still reads at 48px.
    //
    // Endpoints are sampled off the outer arch with [pointAt], so they land on
    // the drawn edge rather than near it.
    final ribArch = _FrillArch(c, reach: 1.00, apex: 2.08);
    for (var i = 0; i < 5; i++) {
      final t = (i - 2) / 2.0; // -1 .. 1
      c.line(
        Offset(o.dx + t * r * 0.20, o.dy - r * 1.22),
        ribArch.pointAt(0.5 + t * 0.44),
        c.hair.withValues(alpha: 0.42),
        width: math.max(1, c.u(0.008)),
      );
    }
  }

  /// How far out the frill reaches at the temples, in **head radii**.
  ///
  /// Multiplied by `headR` at every use. A peer review caught this being applied
  /// as raw pixels, which put the tips 1.6px from centre instead of ~50px and
  /// turned the frill into a narrow steeple rather than a bell.
  static const double frillTip = 1.58;

  /// How far below the head centre the frill's tips sit, in head radii. The outer
  /// and inner edges share this, which is what tapers the frill to a point.
  static const double frillDrop = 0.16;

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
    _pirateScars(c);
  }

  /// Fracture scars, **pirates only**.
  ///
  /// A native Vinari is unmarked by lore — they are luminous, not painted — which
  /// is why the markings axis is hidden for them in the editor. A pirate is a
  /// different case rather than a contradiction of it: a born Vinari has nothing
  /// painted on them, but a raider who has been shot and burned has a *crack* in
  /// the form, and light escaping through it. That is damage, not decoration, and
  /// it is why this draws a fracture with a glowing seam instead of pigment.
  ///
  /// Deliberately gated on the affiliation, so a native Vinari renders exactly as
  /// before even if a save or a seed hands it a non-zero `markings` value — the
  /// axis is inert for them by lore, and a hidden control must not start working
  /// behind the player's back.
  void _pirateScars(AvatarDrawContext c) {
    if (c.portrait.affiliation != AvatarAffiliation.pirate) return;
    if (c.style.markings == 0) return;
    final o = c.headCenter;
    final r = c.headR;
    // A dim, dead seam with light bleeding out of it. Drawn as a dark line with a
    // brighter core so it reads as a split in a glowing form rather than as a
    // scratch on an opaque one.
    //
    // `markings` 1 is one break down the left cheek; 2 adds a shorter temple break
    // on the right, so the two options are distinguishable at 48px.
    //
    // Both are placed **clear of the eyes**, which sit at `o.dy - 0.04r`. A first
    // pass ran the seam straight through that line and the result read as a crude
    // lettered zigzag across the face rather than as damage — the same failure as
    // the Duran war paint, which was moved off the mouth for exactly this reason.
    // Three points rather than four: enough to bend like a fracture, few enough
    // not to read as a glyph.
    final seams = <Path>[
      _seamPath([
        Offset(o.dx - r * 0.76, o.dy + r * 0.16),
        Offset(o.dx - r * 0.34, o.dy + r * 0.58),
        Offset(o.dx - r * 0.10, o.dy + r * 1.02),
      ]),
      if (c.style.markings >= 2)
        _seamPath([
          Offset(o.dx + r * 0.44, o.dy - r * 0.70),
          Offset(o.dx + r * 0.74, o.dy - r * 0.32),
          Offset(o.dx + r * 0.82, o.dy + r * 0.08),
        ]),
    ];

    for (final path in seams) {
      // The dark break itself.
      c.stroke(
        path,
        Color.lerp(c.skin, Colors.black, 0.62)!.withValues(alpha: 0.85),
        width: math.max(1.5, c.u(0.030)),
      );
      // Light escaping the crack — the same trick as the Vinari frill, because a
      // form this luminous cannot have a dark break in it and mean nothing.
      c.stroke(
        path,
        c.hair.withValues(alpha: 0.55),
        width: math.max(1, c.u(0.011)),
      );
    }
  }

  Path _seamPath(List<Offset> points) {
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    return path;
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
    // The on-top luminosity for the form chosen in [appendages].
    //
    // This used to be the *only* place `hair` did anything, drawing a faint arc
    // above the crown for all three values. Now it only adds the light that
    // belongs on top, so each form's silhouette stays the thing that differs.
    final o = c.headCenter;
    final r = c.headR;
    switch (c.style.hair) {
      case 1:
        // Bright nodes where the tendrils cross the head outline, so the fall
        // reads as attached rather than floating behind.
        for (final side in [-1.0, 1.0]) {
          c.glow(
            o.dx + side * r * 0.46,
            o.dy - r * 0.86,
            c.u(0.090),
            c.hair.withValues(alpha: 0.30),
          );
        }
        c.glow(
            o.dx, o.dy - r * 1.18, c.u(0.070), c.hair.withValues(alpha: 0.22));
      case 2:
        // The frill draws its own bloom, membrane, and rim in [appendages], all
        // of which sit clear of the skull. What belongs *on top* is the one thing
        // the head fill hides: a bright node where the membrane's apex passes
        // behind the crown, which stops the fan reading as a separate wing parked
        // behind the pilot rather than growing out of them.
        c.glow(
            o.dx, o.dy - r * 1.44, c.u(0.085), c.hair.withValues(alpha: 0.34));
        for (final side in [-1.0, 1.0]) {
          c.glow(o.dx + side * r * 0.62, o.dy - r * 1.20, c.u(0.055),
              c.hair.withValues(alpha: 0.20));
        }
      default:
        c.fill(
          Path()
            ..moveTo(o.dx - r * 0.62, o.dy - r * 1.06)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 1.74, o.dx + r * 0.62, o.dy - r * 1.06)
            ..quadraticBezierTo(
                o.dx, o.dy - r * 1.24, o.dx - r * 0.62, o.dy - r * 1.06)
            ..close(),
          c.hair.withValues(alpha: 0.36),
        );
    }
  }
}

/// One edge of the Vinari frill: an arch from the left tip, over an explicit apex
/// point, to the right tip.
///
/// Exists so the fill, the two strokes, and the rib endpoints cannot disagree
/// about where the edge is. Every earlier version of this frill re-derived its
/// own curve in each place that needed one, and they drifted apart in three
/// separate ways — see the note on `VinariArt._frillFan`.
///
/// ## Why the apex is a point and not a control height
///
/// A cubic's midpoint only reaches 3/4 of the way to its control points. Asking
/// for controls at 2.10r produced an actual apex of 1.45r — exactly the crown
/// line — and the whole membrane hid behind the skull, leaving `hair` 0 and
/// `hair` 2 pixel-identical above the crown. Every curve here therefore routes
/// *through* the apex rather than aiming at it.
class _FrillArch {
  _FrillArch(
    AvatarDrawContext c, {
    required this.reach,
    required this.apex,
  })  : o = c.headCenter,
        r = c.headR;

  final double reach;
  final double apex;
  final Offset o;
  final double r;

  Offset get tipL =>
      Offset(o.dx - r * VinariArt.frillTip, o.dy + r * VinariArt.frillDrop);
  Offset get tipR =>
      Offset(o.dx + r * VinariArt.frillTip, o.dy + r * VinariArt.frillDrop);
  Offset get top => Offset(o.dx, o.dy - r * apex);

  Offset get _c1 => Offset(o.dx - r * reach, o.dy + r * 0.24);
  Offset get _c2 => Offset(o.dx - r * reach * 0.52, top.dy);
  Offset get _c3 => Offset(o.dx + r * reach * 0.52, top.dy);
  Offset get _c4 => Offset(o.dx + r * reach, o.dy + r * 0.24);

  /// The arch as an **open** path, for stroking.
  ///
  /// Open on purpose: `drawPath` strokes a closed path's closing chord as well,
  /// which drew a hard horizontal line from tip to tip across the bottom of the
  /// frill. Harmless while the tips were 1.6px apart, a visible cut once they
  /// were not.
  Path get path => Path()
    ..moveTo(tipL.dx, tipL.dy)
    ..cubicTo(_c1.dx, _c1.dy, _c2.dx, _c2.dy, top.dx, top.dy)
    ..cubicTo(_c3.dx, _c3.dy, _c4.dx, _c4.dy, tipR.dx, tipR.dy);

  /// A point on the arch, `u` running 0 at the left tip to 1 at the right tip.
  ///
  /// Evaluated from the same control points [path] is built from, so a caller
  /// cannot land somewhere the drawn edge is not. A quadratic through the same
  /// three points is *not* good enough: it only reaches halfway to its control,
  /// which put the rib endpoints below the crown and behind the skull.
  Offset pointAt(double u) {
    final t = u.clamp(0.0, 1.0);
    if (t <= 0.5) {
      return _cubic(tipL, _c1, _c2, top, t * 2);
    }
    return _cubic(top, _c3, _c4, tipR, (t - 0.5) * 2);
  }

  /// The crescent between this arch and [inner], as one closed outline: this edge
  /// forward, then the inner edge backward.
  Path membraneWith(_FrillArch inner) => Path.from(path)
    ..addPath(
      Path()
        ..moveTo(tipR.dx, tipR.dy)
        ..cubicTo(
            _inner(inner._c4).dx,
            _inner(inner._c4).dy,
            _inner(inner._c3).dx,
            _inner(inner._c3).dy,
            inner.top.dx,
            inner.top.dy)
        ..cubicTo(
            _inner(inner._c2).dx,
            _inner(inner._c2).dy,
            _inner(inner._c1).dx,
            _inner(inner._c1).dy,
            inner.tipL.dx,
            inner.tipL.dy),
      Offset.zero,
    );

  /// Mirror a control point about the vertical axis, for walking an arch
  /// backwards.
  Offset _inner(Offset p) => Offset(o.dx - (p.dx - o.dx), p.dy);

  static Offset _cubic(Offset p0, Offset p1, Offset p2, Offset p3, double t) {
    final u = 1 - t;
    return p0 * (u * u * u) +
        p1 * (3 * u * u * t) +
        p2 * (3 * u * t * t) +
        p3 * (t * t * t);
  }
}
