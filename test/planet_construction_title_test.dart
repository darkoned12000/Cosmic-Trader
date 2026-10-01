import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// A citadel build is named by its **target level**, and `Planet.levelTitles` is
/// **0-indexed**. That is one index base against two conventions, and the
/// construction panel got it wrong.
///
/// It read `levelTitles[constructionTarget]`, so a 1->2 build was labelled
/// "Colony" rather than "Settlement", 4->5 read "Citadel" rather than "Planetary
/// Base", and \u2014 because the same expression guarded on `target <= length - 1`
/// \u2014 a 5->6 build fell through to the literal string `"Level 6"`. The header beside
/// it prints `Building $title \u2014 level N`, so the player read **"Building Citadel
/// \u2014 level 2"**.
///
/// Two other lookups in the same file were already correct (`[level - 1]`), which
/// is exactly why a fix to the *Planet Guide's* tier table did not catch this one:
/// the guide and the panel are two transcriptions of one rule and only one was
/// wrong. Hence a guard per surface rather than one for the rule \u2014 the same shape
/// as the bug.
void main() {
  Player pilot() => Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 1000,
        maxHull: 1000,
        shields: 500,
        maxShields: 500,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 100,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.trader,
      );

  /// A world sitting at [level] with its next build **actually started**.
  ///
  /// Started through `startConstruction` rather than by assigning
  /// `constructionTarget` by hand: that field is only written by a real build, so
  /// setting it directly produces a countdown that never advances \u2014 a fixture that
  /// cannot satisfy the condition it is testing. The stores are stocked to the
  /// gate, because `startConstruction` refuses without them.
  Planet buildingAt(int level) {
    final w = Planet(
      id: 'w-1',
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      scanned: true,
      level: level,
      hull: 40000,
      maxHull: 40000,
    );
    final cost = Planet.levelUpCosts[level - 1];
    w.population = cost.requiredColonists;
    w.storedMinerals = cost.requiredMinerals;
    w.storedOrganics = cost.requiredOrganics;
    w.storedIndustrial = cost.requiredIndustrial;

    final started = w.startConstruction();
    expect(started, isTrue,
        reason: 'the fixture must actually start a build at level $level');
    expect(w.constructionTarget, level + 1);
    expect(w.isUnderConstruction, isTrue);
    return w;
  }

  /// Pumps a throwaway tree first, so the next `pumpWidget` builds a **new**
  /// `State` instead of reusing the previous one.
  ///
  /// `pumpWidget` with a structurally identical tree keeps the existing `State`,
  /// and `PlanetScreen` loads its sector once at mount — so without this every
  /// iteration after the first is still showing the *previous* world. The
  /// symptom is an off-by-one that looks exactly like the bug under test: level 4
  /// reported "Building Fortified Colony — level 4", which is level 3's answer.
  Future<void> resetTree(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump(const Duration(milliseconds: 60));
  }

  Future<void> pump(WidgetTester tester, Planet planet) async {
    UniverseStorage.instanceForTest = FaithfulUniverse([
      Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [planet],
      )
    ]);
    addTearDown(() => UniverseStorage.instanceForTest = null);
    await resetTree(tester);
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: PlanetScreen(player: pilot(), onPlayerUpdate: (_) {}),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('each transition is labelled with the tier it is building',
      (tester) async {
    // The whole sweep, not just the reported transition. A "fix" that happened
    // to be right for 1->2 and wrong for 4->5 is the more likely mistake, and a
    // single-target test would pass against it.
    for (final level in [1, 2, 3, 4, 5]) {
      final target = level + 1;
      await pump(tester, buildingAt(level));

      final expected = Planet.levelTitles[target - 1];
      expect(
        find.textContaining('Building $expected'),
        findsOneWidget,
        reason: 'a $level -> $target build is "$expected"',
      );

      // And it is *not* the tier above, which is the symptom.
      if (target < Planet.levelTitles.length) {
        final wrong = Planet.levelTitles[target];
        expect(
          find.textContaining('Building $wrong'),
          findsNothing,
          reason: '"$wrong" is the tier above a $target build',
        );
      }
    }
  });

  testWidgets('the header agrees with the level number beside it',
      (tester) async {
    // The pair that produced "Building Citadel \u2014 level 2": a title and a level
    // read from two different lookups, so each could be right alone and wrong
    // together.
    await pump(tester, buildingAt(1));
    expect(find.textContaining('Building Settlement \u2014 level 2'),
        findsOneWidget);
  });

  testWidgets('the top transition does not fall back to a bare number',
      (tester) async {
    // `constructionTarget == levelTitles.length` for the 5->6 build, and the old
    // `target <= length - 1` guard sent it to the literal "Level 6" \u2014 a third
    // presentation for a fact the screen renders two other ways.
    await pump(tester, buildingAt(5));
    expect(find.textContaining('Building Citadel'), findsOneWidget,
        reason: 'the last tier has a name and must use it');
    expect(find.textContaining('Building Level 6'), findsNothing);
  });
}
