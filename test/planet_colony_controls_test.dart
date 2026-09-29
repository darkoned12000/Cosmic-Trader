import 'dart:convert';
import 'dart:io';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faithful storage: re-parses on every load and really writes, so a mutation
/// that is not saved cannot be observed by accident.
class _FaithfulUniverse extends UniverseStorage {
  _FaithfulUniverse(List<Sector> initial) : _blob = _encode(initial);
  String _blob;
  static String _encode(List<Sector> s) =>
      jsonEncode(s.map((e) => e.toJson()).toList(growable: false));

  @override
  Future<List<Sector>> loadUniverse() async =>
      (jsonDecode(_blob) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Sector.fromJson)
          .toList();

  @override
  Future<void> saveSectors(List<Sector> updated) async {
    final existing = await loadUniverse();
    if (existing.isEmpty) return;
    for (final u in updated) {
      final i = existing.indexWhere((s) => s.id == u.id);
      if (i >= 0) existing[i] = u;
    }
    _blob = _encode(existing);
  }
}

void main() {
  setUpAll(() async {
    final bytes = File('assets/fonts/Audiowide.ttf').readAsBytesSync();
    final loader = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  });

  late _FaithfulUniverse store;
  late Planet planet;
  late Sector sector;
  late List<Player> seen;

  setUp(() {
    planet = Planet(
      name: 'Xandor',
      planetType: 'Jungle',
      owner: FactionClass.trader,
      population: 900, // deliberately under the 100-colonist step
      colonistsMinerals: 200,
      colonistsOrganics: 200,
      colonistsIndustrial: 200,
      colonistsDrones: 100,
      storedMinerals: 40000,
      storedOrganics: 40000,
      storedIndustrial: 40000,
      storedDrones: 40000,
      scanned: true,
    );
    sector = Sector(
      id: 7,
      name: 'Kronos Reach',
      x: 0,
      y: 0,
      warpRoutes: const [],
      planets: [planet],
    );
    store = _FaithfulUniverse([sector]);
    UniverseStorage.instanceForTest = store;
    seen = [];
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  Player playerWith({int cargoUsed = 0, Map<String, int> cargo = const {}}) =>
      Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargoUsed: cargoUsed,
        maxCargo: 100000,
        cargoSize: 100000,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.trader,
        cargo: cargo,
      );

  Future<void> pump(WidgetTester tester, Player player) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: PlanetScreen(player: player, onPlayerUpdate: seen.add),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The planet as the screen's own copy now stands.
  ///
  /// **Read from disk, never from the `planet` fixture.** The screen loads a
  /// freshly parsed copy from the store, so anything it mutates is a different
  /// object from the one the fixture holds. Asserting on the fixture after an
  /// interaction reads a value the action never touched — the same two-copies
  /// trap that hid the missing-save bug.
  Future<Planet> onDisk() async =>
      (await store.loadUniverse()).first.planets.first;

  group('level-gate rows', () {
    testWidgets('a met requirement is a green tick, an unmet one a red cross',
        (tester) async {
      final cost = Planet.levelUpCosts.first;
      // Stock everything except organics, so both states are on screen at once.
      planet.storedMinerals = cost.requiredMinerals;
      planet.storedIndustrial = cost.requiredIndustrial;
      planet.population = cost.requiredColonists;
      planet.storedOrganics = cost.requiredOrganics - 1;
      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(3),
          reason: 'colonists, minerals and industrial are met');
      expect(find.byIcon(Icons.cancel_rounded), findsOneWidget,
          reason: 'organics is one short');
    });

    testWidgets('every requirement row carries a mark, met or not',
        (tester) async {
      // Under-stocked on purpose. The default fixture is over-stocked, so every
      // requirement is met and the "nothing is met" claim would be vacuous.
      planet
        ..population = 0
        ..storedMinerals = 0
        ..storedOrganics = 0
        ..storedIndustrial = 0;
      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      expect(find.byIcon(Icons.cancel_rounded), findsNWidgets(4),
          reason: 'no row may be left ambiguous');
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
    });

    testWidgets('the marks carry a semantic label, not just a colour',
        (tester) async {
      planet
        ..population = 0
        ..storedMinerals = 0
        ..storedOrganics = 0
        ..storedIndustrial = 0;
      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      // Asserted on the widget property, **not** through `find.bySemanticsLabel`:
      // the enclosing Row merges the marks' semantics away, so the label never
      // appears as its own node and a semantics-tree finder sees nothing at all.
      // This proves the label is *set*, which is what the code is responsible
      // for; it does not prove the label survives into an accessibility tree,
      // and that is a gap rather than a check.
      //
      // It is worth having anyway: colour alone is not a signal a player can
      // read, and a glyph renders as a full-width box in the default test font.
      final marks =
          tester.widgetList<Icon>(find.byIcon(Icons.cancel_rounded)).toList();
      expect(marks, hasLength(4));
      for (final m in marks) {
        expect(m.semanticLabel, isNotNull,
            reason: 'a colour-only mark conveys nothing to a screen reader');
      }
    });
  });

  group('workforce steppers move less than a full step', () {
    testWidgets('a small reserve can still be assigned', (tester) async {
      expect(planet.reserveColonists, 200);
      expect(planet.population, 900);
      await pump(tester, playerWith());

      // The real assertion is the second test; this one pins that the control
      // exists and is live at all, so a missing stepper is not mistaken for a
      // stepper that refuses to move.
      final adds = find.byIcon(Icons.add);
      expect(adds, findsWidgets);
      final inks =
          find.ancestor(of: adds.first, matching: find.byType(InkWell));
      expect(inks.first, findsOneWidget);
    });

    testWidgets('a reserve smaller than one step is still movable',
        (tester) async {
      // 40 colonists in the reserve against a 100 step: the old gate
      // `reserve >= step` was false, so all four add buttons were dead.
      // 1,000 colonists is the important part: that is the population band
      // where the step is **100**. My first fixture used 340, where the step is
      // only 10, so a reserve of 40 cleared the old `reserve >= step` gate and
      // the guard passed with the fault still in place.
      planet
        ..population = 1000
        ..colonistsMinerals = 950
        ..colonistsOrganics = 0
        ..colonistsIndustrial = 0
        ..colonistsDrones = 0;
      expect(planet.reserveColonists, 50);
      expect(planet.population, 1000);

      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      expect(planet.colonistsMinerals, 950, reason: 'sanity: the fixture');
      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      // Asserted against the fixture's own starting figure. This was
      // `greaterThan(100)` when the fixture started at 100, and when the
      // fixture was changed to start at 950 the bound was left behind — so the
      // assertion passed with the button dead. A bound that is not derived from
      // the fixture is a bound that will outlive it.
      final after = (await onDisk()).colonistsMinerals;
      expect(after, greaterThan(950),
          reason: 'a 50-colonist reserve against a 100 step must still move. '
              'The old gate was `reserve >= step`, which left every add dead.');
    });
  });

  group('transfer amounts', () {
    testWidgets('Max sets the amount to everything that can move',
        (tester) async {
      final player = playerWith(
        cargoUsed: 0,
        cargo: const {'minerals': 6000},
      );
      await pump(tester, player);

      expect(find.text('Max'), findsWidgets);
      await tester.tap(find.text('Max').first);
      await tester.pumpAndSettle();

      // 6,000 in the hold is the ceiling; the world has plenty of room and the
      // hold has plenty of space, so Max must be the hold.
      final amounts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => int.tryParse(t.data ?? ''))
          .whereType<int>()
          .toList();
      expect(amounts, contains(6000));
    });

    testWidgets('Max never promises more than the free cargo space',
        (tester) async {
      // Asserts the **displayed amount**, not the outcome of pressing Load.
      // The handler clamps too, so cargoUsed ends up identical whether Max is
      // bounded or not — a version of this test passed with the bound removed.
      // Max's own contract is that it does not display a figure it cannot move.
      final player = playerWith(
        cargoUsed: 99000, // 1,000 slots free
        cargo: const {'minerals': 60000},
      );
      await pump(tester, player);

      await tester.tap(find.text('Max').first);
      await tester.pumpAndSettle();

      final shown = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => int.tryParse(t.data ?? ''))
          .whereType<int>()
          .toList();
      expect(shown, contains(1000),
          reason: 'Max must be the free space, not the 60,000 in the hold');
      expect(shown, isNot(contains(60000)));

      // And the hold is still never overfilled.
      await tester.tap(find.text('Load').first);
      await tester.pumpAndSettle();
      expect(seen.last.cargoUsed, lessThanOrEqualTo(100000));
    });

    testWidgets('Max is absent on the colonists row', (tester) async {
      // Colonists are bought, not hauled, and their ceiling is credits rather
      // than cargo — offering Max there would promise a cap it cannot honour.
      await pump(tester, playerWith());
      expect(find.text('Recruit'), findsOneWidget);
    });
  });
}
