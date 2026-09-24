import 'package:flutter/material.dart';

import 'package:cosmic_trader/data/models/faction.dart';

/// Single source of truth for the faction identity palette.
///
/// A3 "consistent faction color language": every screen that color-codes a
/// [FactionClass] (galaxy map dots + legend, tactical map, faction rankings,
/// port ownership tags, NPC lists, combat, knowledge base, lore) must use this
/// function instead of a private local palette. Previously each screen carried
/// its own copy — the map used blue/teal accents while the leaderboard used
/// violet/green, so the same faction changed color depending on the view.
///
/// Palette (chosen to stay distinct on dark backgrounds):
///   Duran   — red 600      (military empire)
///   Vinari  — deep purple  (science / psi-tech)
///   Trader  — green 500    (commerce)
///   Pirate  — orange 500   (raiders / warning)
const FactionPalette pa = FactionPalette._();

class FactionPalette {
  const FactionPalette._();

  static const duran = Color(0xFFE53935);
  static const vinari = Color(0xFF7C4DFF);
  static const trader = Color(0xFF4CAF50);
  static const pirate = Color(0xFFFF9800);
}

Color factionColor(FactionClass fc) {
  switch (fc) {
    case FactionClass.duran:
      return FactionPalette.duran;
    case FactionClass.vinari:
      return FactionPalette.vinari;
    case FactionClass.trader:
      return FactionPalette.trader;
    case FactionClass.pirate:
      return FactionPalette.pirate;
  }
}
