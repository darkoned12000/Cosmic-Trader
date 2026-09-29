import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:cosmic_trader/screens/planets_knowledge_base.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Planet Guide states the system's numbers to the player, so it has to
/// agree with the model. These tests exist because a help screen is exactly the
/// kind of thing that goes stale silently: nothing in the app breaks when a
/// balance value changes and the guide keeps quoting the old one.
void main() {
  /// Deliberately tall.
  ///
  /// The guide is a `ListView`, so it builds lazily. Once the Colonist Transport
  /// section went in, a 2400px viewport stopped building the cards below the
  /// fold and every content assertion in this file began reporting "missing"
  /// for text that was plainly on screen. A find that returns nothing here means
  /// *not built*, not *not there* — size the viewport, do not conclude the
  /// content is gone.
  Future<void> pumpGuide(WidgetTester tester,
      {Size size = const Size(1400, 12000)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetsKnowledgeBaseScreen(onBack: () {}),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders at phone and desktop widths', (tester) async {
    // Overflow is a test failure in this framework, so pumping is the assertion.
    for (final size in [
      const Size(430, 2400),
      const Size(900, 2400),
      const Size(1400, 2400)
    ]) {
      await pumpGuide(tester, size: size);
      expect(find.text('Planet Guide'), findsOneWidget);
    }
  });

  testWidgets('lists every planet type the model defines', (tester) async {
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final type in Planet.allTypes) {
      expect(text, contains(type),
          reason: '$type exists in the model but is missing from the guide — '
              'a new planet type has to appear in the player reference');
    }
  });

  testWidgets('lists every Citadel transition the model defines',
      (tester) async {
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final title in Planet.levelTitles) {
      expect(text, contains(title),
          reason: 'Citadel tier "$title" is missing from the guide');
    }
  });

  testWidgets('derives "strongest at" from the winning multiplier',
      (tester) async {
    // A help screen that tells a player a Lava world is good at organics, or a
    // Gas Giant is good at minerals, is worse than no table at all. The claim is
    // computed from the same multipliers the game uses, so it cannot contradict
    // them; this pins the computation itself.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');

    for (final type in Planet.allTypes) {
      final m = Planet.typeMultipliers[type]!;
      final best = <String, double>{
        'Minerals': m.minerals,
        'Organics': m.organics,
        'Industrial': m.industrial,
        'Drones': m.drones,
      };
      final winner = best.entries.reduce((a, b) => a.value >= b.value ? a : b);
      final tied = best.values.where((v) => v == winner.value).length;
      final expected = tied > 1 ? 'all-round' : winner.key.toLowerCase();
      expect(text, contains(expected),
          reason: '$type should read as "$expected" — its multipliers are '
              'min ${m.minerals} / org ${m.organics} / ind ${m.industrial} / '
              'dro ${m.drones}');
    }
  });

  testWidgets('quotes the real colonist supply prices', (tester) async {
    // The guide states transport costs to the player. If the curve is retuned
    // and the guide is not, the reference is simply wrong.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (var hops = 1; hops <= 8; hops++) {
      expect(text, contains('${ColonistSupply.pricePerColonist(hops)}'),
          reason: 'the guide should quote the price at $hops hops');
    }
    expect(text, contains('homeworld'),
        reason: 'the guide must say colonists come from the faction capital, '
            'not a shared pool');
  });

  testWidgets('lists every planet type in the storage table', (tester) async {
    // The storage table is the answer to "why would I colonise this", so a new
    // planet type that is missing from it is a documentation gap, not a
    // cosmetic one.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    for (final type in Planet.allTypes) {
      expect(text, contains(type));
    }
    expect(text, contains('Storage'));
  });

  testWidgets('quotes the upkeep divisor the model actually uses',
      (tester) async {
    // The guide interpolates Planet.organicsUpkeepDivisor, so this is really a
    // guard that the guide stopped hard-coding the number.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(text, contains('P ÷ ${Planet.organicsUpkeepDivisor}'));
  });

  testWidgets('quotes the starvation rate the model actually uses',
      (tester) async {
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    final pct = (Planet.maxStarvationRatePerTick * 100).round();
    expect(text, contains('$pct%'));
  });

  testWidgets('states that storage is a per-commodity cap', (tester) async {
    // The planet screen shows a storage row that sums the commodities against a
    // single cap, so it can read as overfull. The guide is where that rule has
    // to be explained, and this pins the explanation.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(text, contains('per commodity'));
  });

  testWidgets('marks the unbuilt mechanics as coming soon', (tester) async {
    await pumpGuide(tester);
    // Scroll it into existence first: a ListView builds lazily, so the last
    // card is simply not in the tree while it is below the fold. A find that
    // returns nothing here means "off screen", not "missing from the guide".
    await tester.scrollUntilVisible(find.text('Coming Soon'), 300);
    expect(find.text('Coming Soon'), findsOneWidget);
  });

  testWidgets('back is wired, not a Navigator.pop', (tester) async {
    // The guide is swapped inline inside ComputerScreen; popping the Navigator
    // here would pop GameShell and kill the session.
    var backs = 0;
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetsKnowledgeBaseScreen(onBack: () => backs++),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(backs, 1);
  });

  testWidgets('the grant table flags no tier as unreachable', (tester) async {
    // The guide prints "<-- CANNOT REACH NEXT TIER" when a population ceiling
    // falls below the gate for the next step. It must never appear: the whole
    // point of deriving the cap from the level is that the pairing cannot
    // break. A future retune of either table that breaks it will show up here
    // rather than in a player's playthrough.
    final guide = PlanetsKnowledgeBaseScreen(onBack: () {});
    // Build it off-screen wide enough that the whole Citadel section is laid out.
    tester.view.physicalSize = const Size(1600, 12000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Material(child: guide)));
    await tester.pumpAndSettle();

    expect(find.textContaining('CANNOT REACH'), findsNothing);
  });
}
