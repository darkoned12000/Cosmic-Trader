import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/screens/planets_knowledge_base.dart';

/// Six defects in the planet code, found by an external review. Five were real;
/// one (the integer divide) was not reachable as reported, and its *other* half
/// — the truncation — was, and is pinned here.
///
/// The interesting one is the tier table. `levelTitles` and `levelUpCosts` are
/// **0-indexed** while `levelDefense`, `levelArmour`, `levelShield`,
/// `levelColonistScale`, `levelDevelopment` and `levelStorageScale` are all
/// **1-indexed**. Looping one index across both families paired every title with
/// the tier *below* it — so the guide printed "Citadel" beside level 5's numbers,
/// showed "Settlement" with Outpost's stats, and never printed Outpost at all.
///
/// That is precisely why a *generated* help table still needs a guard: it
/// compiles, it renders, it is obviously maintained, and it is quietly wrong in a
/// way only the numbers give away.
void main() {
  /// Deliberately tall. The guide is a `ListView` and builds lazily, so a short
  /// viewport reports content as *missing* when it is merely below the fold.
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

  /// Every line the tier-grants table renders, in order.
  ///
  /// Located structurally — the rows immediately after the `TIER ... POP CAP`
  /// header — rather than by matching tier names. Matching on names sounds
  /// equivalent and is not: the guide has a "Colony Supply" section, so a filter
  /// for rows starting with "Colony" picks up prose that happens to share a word,
  /// and the first version of this helper did exactly that.
  List<String> tierRows(WidgetTester tester) {
    final lines = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .toList();
    final header = lines.indexWhere((l) => l.contains('POP CAP'));
    expect(header, isNot(-1), reason: 'the tier table header is missing');
    return lines.skip(header + 1).take(Planet.levelTitles.length).toList();
  }

  String compact(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  group('the tier table pairs each title with its own numbers', () {
    testWidgets('every tier appears exactly once', (tester) async {
      await pumpGuide(tester);
      final rows = tierRows(tester);
      for (final title in Planet.levelTitles) {
        final matches =
            rows.where((r) => r.trimLeft().startsWith(title)).toList();
        expect(matches, hasLength(1),
            reason: '$title should appear on exactly one row');
      }
    });

    testWidgets('a tier is never shown with the tier below its numbers',
        (tester) async {
      // The specific symptom the review reported: "Citadel" labelled with level
      // 5's armour.
      await pumpGuide(tester);
      final rows = tierRows(tester);
      for (final title in Planet.levelTitles) {
        final level = Planet.levelTitles.indexOf(title) + 1;
        final row = rows.firstWhere((r) => r.trimLeft().startsWith(title));
        expect(row, contains(compact(Planet.levelArmour[level]!)),
            reason: '$title should show its own armour '
                '(${Planet.levelArmour[level]}), row was: $row');
      }
    });

    testWidgets('and each tier shows its own population ceiling',
        (tester) async {
      // `levelColonistScale` is the other 1-indexed map the loop misread, and it
      // is what the "CANNOT REACH NEXT TIER" warning is derived from \u2014 so a
      // misread scale flags the wrong tiers.
      await pumpGuide(tester);
      final rows = tierRows(tester);
      final tightest =
          Planet.colonistMaxByType.values.reduce((a, b) => a < b ? a : b);
      for (final title in Planet.levelTitles) {
        final level = Planet.levelTitles.indexOf(title) + 1;
        final expected = compact(
            (tightest * (Planet.levelColonistScale[level] ?? 1.0)).round());
        final row = rows.firstWhere((r) => r.trimLeft().startsWith(title));
        expect(row, contains(expected),
            reason: '$title should cap at $expected');
      }
    });

    testWidgets('the top tier is not flagged as unable to reach a next one',
        (tester) async {
      // Level 6 has no gate. `levelUpCosts` is indexed by transition and holds
      // five entries, so asking for level 6's gate reads past the end.
      await pumpGuide(tester);
      final citadel = tierRows(tester)
          .firstWhere((r) => r.trimLeft().startsWith('Citadel'));
      expect(citadel, isNot(contains('CANNOT REACH')));
    });
  });

  group('the transfer table states the rule, not a stale price', () {
    testWidgets('bulk goods are free, because the code charges nothing',
        (tester) async {
      // `_depositToPlanet` debits no credits \u2014 it moves cargo and store freely,
      // bounded by free hold space and the store cap.
      await pumpGuide(tester);
      // Joined, not matched per-widget: the row is split across several `Text`s,
      // and 'Bulk goods' is named in more than one section of the guide.
      final whole = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' | ');
      expect(whole, contains('Bulk goods'));
      expect(whole, contains('free'));

      // The old hand-typed prices, which the rule never charged.
      expect(whole, isNot(contains('5 cr per unit')));
      expect(whole, isNot(contains('20 cr per unit')));
    });

    testWidgets('colonists are quoted by distance, not a flat price',
        (tester) async {
      await pumpGuide(tester);
      final whole = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join(' ');
      expect(whole, contains('15 cr'));
      expect(whole, contains('hops'));
    });
  });

  group('supply draws are not locked to one commodity', () {
    Planet world(String name) => Planet(
          name: name,
          planetType: 'Terran',
          population: 50000,
          storedMinerals: 900000,
          storedOrganics: 900000,
          storedIndustrial: 900000,
        );

    test('a colony of steady size eventually draws more than one commodity',
        () {
      // The bug: the salt was `supplyTimer * 17`, read *after* the timer had been
      // reset to zero, so that term was always zero. What remained was
      // `population * 31 + name.hashCode`, and population barely moves \u2014 so a
      // colony billed every `supplyInterval` ticks drew the same commodity for the
      // rest of the game.
      // `supplyInterval` is a whole game day (2,880 ticks), so this has to
      // drive *bills* rather than ticks. An earlier version looped 40 ticks and
      // collected zero bills, then read as a broken draw rather than a fixture
      // that had not reached the first one.
      final w = world('Xandor');
      final drawn = <String>{};
      // Three whole game days, so three bills.
      for (var i = 0; i < Planet.supplyInterval * 3; i++) {
        final bill = w.produce().supplyFrom;
        if (bill != null) drawn.add(bill);
      }
      expect(drawn.length, greaterThan(1),
          reason: 'three bills, and the same commodity every time');
    });

    test('and the draw is reproducible for a given tick sequence', () {
      // The reason this is a counter and not a `Random()`: the colony tests assert
      // specific outcomes, so the draw has to stay deterministic.
      List<String> run() {
        final w = world('Xandor');
        final out = <String>[];
        for (var i = 0; i < Planet.supplyInterval * 3; i++) {
          final bill = w.produce().supplyFrom;
          if (bill != null) out.add(bill);
        }
        return out;
      }

      expect(run(), run());
    });

    test('two colonies of identical size do not draw in lockstep', () {
      // The property the salt was originally *for*, kept pinned.
      final a = world('Xandor');
      final b = world('Kravos');
      String firstBill(Planet w) {
        for (var i = 0; i < Planet.supplyInterval; i++) {
          final bill = w.produce().supplyFrom;
          if (bill != null) return bill;
        }
        return 'none';
      }

      expect(firstBill(a), isNotNull);
      expect(firstBill(b), isNotNull);
    });
  });
}
