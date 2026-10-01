import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:cosmic_trader/services/energy_service.dart';
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

  /// The guide's own text, joined. Sized by `pumpGuide`, which builds the whole
  /// `ListView` — see its note about lazy building.
  Future<String> guideText(WidgetTester tester) async {
    await pumpGuide(tester);
    return tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
  }

  group('claims that had gone stale', () {
    testWidgets('scanning quotes the model cost, not the deleted second verb',
        (tester) async {
      // The guide described **two** scan verbs and priced the second at 4
      // energy. They were unified into one action at `EnergyService.scanCost`,
      // and the comment on that constant says so — but the guide kept the old
      // pair for the whole life of the change.
      final text = await guideText(tester);
      expect(text, contains('${EnergyService.scanCost} energy'));
      expect(text, isNot(contains('4 energy')),
          reason: 'the 4-energy full scan was deleted');
      expect(text, isNot(contains('Quick scan')),
          reason: 'there is one scan verb now, so there is no "quick" one');
      expect(text, isNot(contains('Full scan')));
    });

    testWidgets('does not describe a Scanner module, which does not exist',
        (tester) async {
      // The guide claimed a Scanner module auto-scans on sector entry, while
      // also listing that same feature as not-yet-available 200 lines below.
      // "scanner" appears nowhere in the hardware catalogue or the scan path.
      final text = await guideText(tester);
      expect(text, isNot(contains('scans itself on sector entry')),
          reason: 'no such module exists; the feature is listed as unbuilt');
      // And the not-yet-available list must still say so.
      expect(text, contains('Scanner module auto-scan'));
    });

    testWidgets('says three production tracks, and that drones are derived',
        (tester) async {
      // Drones stopped being a workforce track when they became derived from
      // the other three. The guide still called it a four-track split and told
      // the player to put colonists on a Drones track — which no stepper offers.
      final text = await guideText(tester);
      expect(text, contains('three production tracks'));
      expect(text, isNot(contains('four production tracks')));
      expect(text, isNot(contains('colonists on the Drones track')));
      expect(text, contains('Drones are not a fourth track'));
    });

    testWidgets('does not claim levelling leaves defence alone',
        (tester) async {
      // `levelUp()` applies `levelDefense`/`levelShield`/`levelArmour` on
      // completion, so the old sentence was simply false.
      final text = await guideText(tester);
      expect(
          text, isNot(contains('does not currently change as a world levels')),
          reason: 'levelling raises defence, shield and armour');
      expect(text, contains('raises all three'));
    });

    testWidgets('does not list Genesis Torpedoes as unbuilt', (tester) async {
      // They ship: the Ship screen carries them and the sector panel launches
      // them. The unbuilt list is the one place a player checks whether a thing
      // exists, so a stale entry there is a lie with a cost.
      final text = await guideText(tester);
      expect(text, isNot(contains('Genesis Torpedoes — creating a new world')),
          reason: 'torpedoes are playable; they must not be listed as unbuilt');
      expect(text, contains('Invasion — attacking and capturing'),
          reason: 'and the genuinely unbuilt entries stay');
    });

    testWidgets('quotes the homeworld cadence from the model', (tester) async {
      final text = await guideText(tester);
      expect(text, contains('${Planet.defaultSpawnInterval} ticks'));
      expect(text, contains('${Planet.pirateOutpostSpawnInterval} ticks'),
          reason: 'pirate outposts run on their own cadence and the guide said '
              'one number for both');
    });

    testWidgets('quotes the efficiency range from the model', (tester) async {
      final text = await guideText(tester);
      expect(text, contains('${Planet.minEfficiency}–${Planet.maxEfficiency}'));
    });

    testWidgets('mentions the colonist transit delay', (tester) async {
      final text = await guideText(tester);
      expect(text,
          contains('${Planet.colonistTransitDelayTicks} ticks in transit'),
          reason: 'a purchase is a shipment now, and the guide did not say so');
      expect(text, isNot(contains('whether or not you are watching it happen')),
          reason: 'that sentence predates the transit timer');
    });
  });

  group('formatting the surface cannot render', () {
    testWidgets('no literal markdown markers reach the player', (tester) async {
      // `_sectionCard` renders a plain `Text`, so `**bold**` and `*italic*`
      // arrive as literal asterisks. There were fourteen of them in here, all
      // invisible to every existing guard — the words were right and the
      // emphasis was punctuation on screen. Found by rendering the guide and
      // looking at it.
      final text = await guideText(tester);
      expect(text, isNot(contains('**')),
          reason: 'the guide renders plain text; emphasis markers show up as '
              'asterisks');
      expect(
        RegExp(r'\*[A-Za-z][^*]*\*').hasMatch(text),
        isFalse,
        reason: 'no markdown italics either',
      );
    });
  });

  group('the generated tables', () {
    testWidgets('the Type Reference header matches its own column count',
        (tester) async {
      // The header listed four columns after the commodity block and the rows
      // emitted three — `Food upkeep` was a phantom left over from the deleted
      // per-capita upkeep, so every value was labelled one column to the left.
      // A misaligned table is worse than a missing one: the numbers are right
      // and the headings lie about what they mean.
      final text = await guideText(tester);
      final lines = text.split('\n');
      final headerIndex =
          lines.indexWhere((l) => l.startsWith('Output/colonist'));
      expect(headerIndex, greaterThanOrEqualTo(0),
          reason: 'the reference table header moved');
      final header = lines[headerIndex];
      // **The row immediately after the header**, not `firstWhere(startsWith
      // ('Terran'))`: the Planet Types table also prints rows beginning with a
      // type name, and it has a different column count, so a name-based finder
      // compared this header against the wrong table.
      final row = lines[headerIndex + 1];

      int separators(String s) => '|'.allMatches(s).length;
      expect(separators(header), separators(row),
          reason: 'header: "$header"\nrow: "$row"');
      expect(header, isNot(contains('Food upkeep')),
          reason: 'the per-capita upkeep mechanic was deleted, not retuned');
    });
  });

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
    // an Ice world is good at organics, is worse than no table at all. The claim
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
    expect(text, contains('${Planet.supplyInterval} ticks'));
  });

  testWidgets('quotes the supply share the model actually uses',
      (tester) async {
    // Rewritten from the starvation-rate guard it replaced. The property is the
    // same one: the guide must not state a number the model does not use, or a
    // balance change leaves the reference quietly lying.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    final pct = (Planet.supplyShareOfOutput * 100).round();
    expect(text, contains('$pct%'));
  });

  testWidgets('says plainly that a world can be unable to produce something',
      (tester) async {
    // A multiplier of 0.0 in a table is not a warning. The harsh types have a
    // solvable problem and the guide is where a player would go looking for it.
    await pumpGuide(tester);
    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('\n');
    expect(text, contains('cannot make organics'));
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
