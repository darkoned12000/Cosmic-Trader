import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_palette.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_species_art.dart';

/// Draws a pilot portrait by delegating to the per-species renderer.
///
/// **This is placeholder art, not the final v1 gallery.** The design doc
/// (`player-avatar.md` §3, Option A) calls for a curated set of finished
/// faction portraits; the repo ships no character art, so these are generated.
/// The seam is deliberate: swapping in real assets means teaching
/// [AvatarCanvas] a new branch, and nothing else in the app changes.
///
/// This class is orchestration only — the species live in `avatar_duran_art.dart`,
/// `avatar_vinari_art.dart`, and `avatar_terran_art.dart` behind [SpeciesArt].
/// What lives here is the thing every species shares, and which must not drift:
///
/// ## Layer order
///
/// 1. backdrop
/// 2. [SpeciesArt.outfit] — torso and garment
/// 3. [SpeciesArt.appendages] — anything past the skull, **before the head**
/// 4. [SpeciesArt.headPath] fill
/// 5. [SpeciesArt.headShading] + [SpeciesArt.faceTexture] — inside the head clip
/// 6. eyes, expression, crest
///
/// Step 3 before step 4 is load-bearing. An earlier single-file version drew
/// appendages inside the clipped step, which sliced the Duran horn roots flat
/// and lost the Terran ears almost entirely. The [SpeciesArt] doc spells this
/// out so it cannot regress quietly.
class AvatarPortraitPainter extends CustomPainter {
  const AvatarPortraitPainter({
    required this.portrait,
    this.style,
    this.selected = false,
  });

  final AvatarPortrait portrait;

  /// Explicit appearance. `null` uses the catalogue's seeded style, which is
  /// what keeps un-customised presets rendering unchanged.
  final AvatarStyle? style;

  /// Faction-coloured halo behind the head, for the selected gallery thumbnail.
  /// Distinct from [AvatarCanvas.showRing]'s outer border.
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final species = portrait.species;
    final accent = factionColor(species.faction);
    final rng = math.Random(portrait.drawSeed);
    final s = (style ?? portrait.seededStyle).sanitized();

    // Colours come from the species palette, not the faction colour. Faction
    // identity stays on the ring and the backdrop.
    final skin = AvatarPalette.skin(species, s.tone);
    final cloth =
        AvatarPalette.outfit(species, s.outfitTone, portrait.presentation);
    final minDim = math.min(w, h);
    double u(double v) => v * minDim;

    // Small per-portrait proportion jitter, so two portraits with the same
    // style are still not pixel-identical.
    final headWidth = (0.160 + rng.nextDouble() * 0.035) *
        (species == AvatarSpecies.vinari ? 0.94 : 1.0);

    final ctx = AvatarDrawContext(
      canvas: canvas,
      size: size,
      portrait: portrait,
      style: s,
      skin: skin,
      skinShadow: Color.lerp(skin, Colors.black, 0.42)!,
      skinLight: Color.lerp(skin, Colors.white, 0.30)!,
      hair: AvatarPalette.hair(species, s.hair, s.hairColor),
      cloth: cloth,
      clothTrim: AvatarPalette.trim(species, s.outfitTone, s.trimColor),
      plateLight: AvatarPalette.plateHighlight(species, s.outfitTone),
      accent: accent,
      headCenter: Offset(0.5 * w, 0.42 * h),
      headR: u(headWidth),
      shoulderTop: 0.70 * h,
      shoulderWidth: 0.40 + rng.nextDouble() * 0.14,
      jawTaper: _jawTaperFor(portrait.presentation, rng),
      rng: rng,
    );

    final art = SpeciesArt.of(species);

    // ── 1. Backdrop ───────────────────────────────────────────────
    art.backdrop(ctx);

    if (selected) {
      ctx.glow(ctx.headCenter.dx, ctx.headCenter.dy, u(0.40),
          accent.withValues(alpha: 0.45));
    }

    // ── 2. Torso ──────────────────────────────────────────────────
    final sw = ctx.shoulderWidth;
    final st = ctx.shoulderTop;
    canvas.drawPath(
      Path()
        ..moveTo(ctx.ux(0.5 - sw), h)
        ..lineTo(ctx.ux(0.5 - sw * 0.86), st + u(0.05))
        ..quadraticBezierTo(
            ctx.ux(0.5 - sw * 0.42), st - u(0.035), ctx.ux(0.5), st - u(0.045))
        ..quadraticBezierTo(ctx.ux(0.5 + sw * 0.42), st - u(0.035),
            ctx.ux(0.5 + sw * 0.86), st + u(0.05))
        ..lineTo(ctx.ux(0.5 + sw), h)
        ..close(),
      Paint()..color = cloth,
    );

    // ── 3. Neck. The Vinari have no skeletal neck; their form trails into
    // the shoulders.
    if (species != AvatarSpecies.vinari) {
      canvas.drawRect(
        Rect.fromLTRB(ctx.ux(0.5 - 0.055), ctx.headCenter.dy,
            ctx.ux(0.5 + 0.055), st + u(0.02)),
        Paint()..color = ctx.skinShadow,
      );
    }

    art.outfit(ctx);

    // ── 4. Appendages, BEHIND the head ────────────────────────────
    art.appendages(ctx);

    // ── 5. Head ───────────────────────────────────────────────────
    final headPath = art.headPath(ctx);
    canvas.drawPath(headPath, Paint()..color = skin);
    art.headShading(ctx);

    // ── 6. Face texture, clipped to the head ──────────────────────
    canvas.save();
    canvas.clipPath(headPath);
    art.faceTexture(ctx);
    canvas.restore();

    // ── 7. Features ───────────────────────────────────────────────
    art.eyes(ctx);
    art.expression(ctx);
    art.crest(ctx);

    // No inner white rim light: at 48-112px it sat close enough to the outer
    // faction ring to read as a muddy double edge.
  }

  /// Jaw profile varies by presentation, giving a second axis of variety on top
  /// of the hair.
  double _jawTaperFor(AvatarPresentation presentation, math.Random rng) {
    switch (presentation) {
      case AvatarPresentation.male:
        return 0.78 + rng.nextDouble() * 0.18;
      case AvatarPresentation.female:
        return 0.64 + rng.nextDouble() * 0.14;
      case AvatarPresentation.neutral:
        return 0.70 + rng.nextDouble() * 0.16;
    }
  }

  @override
  bool shouldRepaint(AvatarPortraitPainter oldDelegate) {
    return oldDelegate.portrait.id != portrait.id ||
        oldDelegate.style != style ||
        oldDelegate.selected != selected;
  }
}
