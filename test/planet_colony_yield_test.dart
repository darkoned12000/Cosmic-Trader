import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/widgets/planet/planet_colony_card.dart';
import 'package:cosmic_trader/widgets/planet/planet_info_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The colony card must **show the colony's yield**, because every per-day
/// figure on it already includes that number.
///
/// `productionEfficiency` is rolled in `[0.5, 1.5)` when a world is generated and
/// never changes; `developmentMultiplier` is `1.00` at level 1 and rises with the
/// Citadel. Their product, `yieldScale`, is the multiplier the tick applies to
/// output. So before this row existed, roughly half of all generated worlds
/// produced visibly less than an identical world next to them and the screen
/// offered no reason — the difference was only visible as a number.
///
/// The card is a pure widget (a `Planet` and a `ColorScheme` in, nothing out), so
/// it is driven directly with no storage double at all. That matters here: the
/// lesson this file would otherwise repeat is that a double which reimplements
/// the subject vouches only for itself.
void main() {
  Planet world({double efficiency = 1.0, int level = 1}) => Planet(
        name: 'Xandor',
        planetType: 'Jungle',
        owner: FactionClass.trader,
        scanned: true,
        level: level,
        productionEfficiency: efficiency,
        population: 100000,
        colonistsMinerals: 20000,
        colonistsOrganics: 20000,
        colonistsIndustrial: 20000,
        hull: 40000,
        maxHull: 40000,
      );

  Future<void> pumpCard(WidgetTester tester, Planet planet) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: PlanetColonyCard(
          planet: planet,
          cs: ThemeData.dark(useMaterial3: true).colorScheme,
          canAssign: true,
          onAdjust: (_, __) {},
        ),
      ),
    ));
    await tester.pump();
  }

  /// The yield **as the card renders it** — the value the widget was built with,
  /// not a value recomputed here.
  ///
  /// Read off the `PlanetInfoRow` itself rather than by scraping `Text` widgets:
  /// an ancestor search for the label's `Row` matched two (the info row nests
  /// inside a header row), which is the "a finder that happens to be unique will
  /// silently find the wrong thing later" family. Recomputing the percentage in
  /// the test instead would be a second implementation that vouches only for
  /// itself — the displayed string is the thing under test.
  String renderedYield(WidgetTester tester) {
    final row = find.widgetWithText(PlanetInfoRow, 'World yield');
    expect(row, findsOneWidget, reason: 'the World yield row is not on screen');
    return tester.widget<PlanetInfoRow>(row).value;
  }

  testWidgets('it shows a yield, and the number is the model\'s',
      (tester) async {
    // Deliberately an awkward figure: 0.87 is neither 1.0 nor a round tenth, so
    // a row hard-coded to "100%" or reusing a stored string cannot pass.
    final planet = world(efficiency: 0.87);
    await pumpCard(tester, planet);

    expect(renderedYield(tester), '87%');
    expect(planet.yieldScale, closeTo(0.87, 1e-9),
        reason: 'precondition: the model agrees this is what yieldScale is');
  });

  testWidgets('a world below average says so', (tester) async {
    // The whole point of the row: a below-average world must not read as 100%.
    await pumpCard(tester, world(efficiency: 0.5));
    expect(renderedYield(tester), '50%');
  });

  testWidgets('levelling the world raises the figure', (tester) async {
    // The Citadel half of the yield is the only part a player can move, and
    // levelling is exactly the purchase the row is meant to justify. A guard that
    // only checked the natural roll would pass with the development half hard-
    // wired to 1.0 forever.
    final before = world(efficiency: 1.0, level: 1);
    final after = world(efficiency: 1.0, level: 6);
    expect(before.developmentMultiplier, lessThan(after.developmentMultiplier),
        reason: 'precondition: levelling raises the development multiplier');

    await pumpCard(tester, before);
    final low = renderedYield(tester);
    await pumpCard(tester, after);
    final high = renderedYield(tester);

    expect(low, isNot(high),
        reason: 'levelling did not move the displayed yield');
    expect(high, '${(after.yieldScale * 100).round()}%');
  });

  testWidgets('the reason names both halves', (tester) async {
    await pumpCard(tester, world(efficiency: 0.87));

    // Tap the (i) bubble, **scoped to this row**. The card carries two info
    // bubbles now (Supply draw and World yield), so a bare `find.byIcon` is the
    // "a finder that happens to be unique will silently find the wrong thing
    // later" trap — unique until the second row was added, then "Too many
    // elements". `TooltipTriggerMode.tap` is what the row uses, so this is a tap
    // rather than the default long press.
    final bubble = find.descendant(
      of: find.widgetWithText(PlanetInfoRow, 'World yield'),
      matching: find.byIcon(Icons.info_outline_rounded),
    );
    expect(bubble, findsOneWidget);
    await tester.tap(bubble);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // `textContaining`, not `find.text`: a tooltip renders as RichText, so a
    // byType(Text) assertion reports "no tooltip" for one plainly open.
    expect(find.textContaining('Natural yield'), findsOneWidget,
        reason:
            'the fixed roll is the half that explains why two worlds differ');
    expect(find.textContaining('Citadel development'), findsOneWidget,
        reason: 'the movable half is the one that justifies levelling');
  });
}
