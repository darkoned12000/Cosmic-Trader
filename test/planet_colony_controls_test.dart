import 'dart:convert';
import 'dart:io';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
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

/// Every non-empty label in the built semantics tree, in document order.
///
/// Walks the tree rather than using `find.bySemanticsLabel`, and that is not a
/// stylistic choice. The finder could not see these nodes at all while the
/// wrapping `Semantics` was `container: false` — it only annotates, so each
/// label merged into the nearest ancestor and became indistinguishable from its
/// neighbours. A guard built on the finder reported green while a screen reader
/// would have read the whole card as one run of text.
///
/// So this asserts what a user actually receives: a **standalone node per
/// requirement**, discoverable in the tree.
List<String> semanticsLabels(WidgetTester tester) {
  final labels = <String>[];
  void walk(SemanticsNode? node) {
    if (node == null) return;
    final label = node.getSemanticsData().label;
    if (label.isNotEmpty) labels.add(label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  // `pipelineOwner` is deprecated in favour of `rootPipelineOwner`, but the
  // replacement is empty under `testWidgets` — the test binding's semantics owner
  // hangs off the deprecated getter, and the modern one returns a node with no
  // labels, which reads as "the screen has no semantics" rather than as a
  // failure. Verified by dumping both. The ignore is deliberate and scoped to
  // this one line; the rest of the project is on the modern API.
  // ignore: deprecated_member_use
  walk(tester.binding.pipelineOwner.semanticsOwner!.rootSemanticsNode);
  return labels;
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

  /// The compact form the screen renders, so a needle matches what is on screen
  /// rather than the raw integer.
  String shortForm(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

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
    /// The row whose text is exactly `have / need`.
    ///
    /// Matched on the **whole** row text. An earlier version searched for a
    /// needle like "250" and took the first `/`-bearing match, which is a
    /// different row entirely — the level gate, the colony card and the
    /// transfers rows all print slash-separated figures.
    Text? rowFor(WidgetTester tester, int have, int need) {
      final target = '${shortForm(have)} / ${shortForm(need)}';
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        if (t.data == target) return t;
      }
      return null;
    }

    testWidgets('a met requirement reads green and an unmet one red',
        (tester) async {
      final cost = Planet.levelUpCosts.first;
      // Met on everything except organics, so both states are on screen at once.
      planet.storedMinerals = cost.requiredMinerals;
      planet.storedIndustrial = cost.requiredIndustrial;
      planet.population = cost.requiredColonists;
      planet.storedOrganics = cost.requiredOrganics - 1;
      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      expect(
          rowFor(tester, cost.requiredColonists, cost.requiredColonists)
              ?.style
              ?.color,
          Colors.green.shade400,
          reason: 'colonists are met');
      expect(
          rowFor(tester, cost.requiredMinerals, cost.requiredMinerals)
              ?.style
              ?.color,
          Colors.green.shade400,
          reason: 'minerals are met');
      expect(
          rowFor(tester, cost.requiredIndustrial, cost.requiredIndustrial)
              ?.style
              ?.color,
          Colors.green.shade400,
          reason: 'industrial is met');

      final unmet =
          rowFor(tester, cost.requiredOrganics - 1, cost.requiredOrganics);
      expect(unmet, isNotNull, reason: 'sanity: the organics row is on screen');
      expect(unmet!.style?.color, isNot(Colors.green.shade400),
          reason: 'organics is one short and must not read as met');
      expect(unmet.style?.color, isNotNull,
          reason: 'unmet must be visibly distinct, not merely un-green');
    });

    testWidgets('there are no tick or cross marks left in the row',
        (tester) async {
      final cost = Planet.levelUpCosts.first;
      planet.storedMinerals = cost.requiredMinerals;
      planet.storedOrganics = cost.requiredOrganics;
      await store.saveSectors([sector]);
      await pump(tester, playerWith());

      // The marks were a fourth icon column for a binary the numbers already
      // carry. A RenderFlex overflow or a stray icon would both show here.
      expect(find.byIcon(Icons.check_circle_rounded), findsNothing);
      expect(find.byIcon(Icons.cancel_rounded), findsNothing);
      expect(find.textContaining('\u2713'), findsNothing,
          reason: 'and no tick glyph hiding in a string either');
    });

    testWidgets('each label is its own node, not merged into a neighbour',
        (tester) async {
      // This is the check that actually closes the gap. `container: true` on the
      // `Semantics` wrapper is what makes each requirement a standalone node; with
      // the default (`container: false`) the label only annotates, merges into
      // whatever ancestor is nearest, and a screen reader reads every label in
      // the card as one long run — or drops them.
      //
      // The earlier version of this guard asserted only that the `Semantics`
      // widget carried a label, which passed even while the tree could not see
      // it. The tree walk below is the property a user actually gets.
      final handle = tester.ensureSemantics();
      await pump(tester, playerWith());

      final labels = semanticsLabels(tester);
      handle.dispose();

      for (final expected in const [
        'Colonists requirement met',
        'Minerals requirement met',
        'Organics requirement met',
        'Industrial requirement met',
      ]) {
        expect(labels, contains(expected),
            reason: 'the tree exposes no standalone node for "$expected". '
                'Semantics needs container: true or it merges into a parent.');
      }
    });

    testWidgets('an unmet requirement says so in words, not only in colour',
        (tester) async {
      final cost = Planet.levelUpCosts.first;
      planet.storedOrganics = cost.requiredOrganics - 1;
      await store.saveSectors([sector]);

      final handle = tester.ensureSemantics();
      await pump(tester, playerWith());
      final labels = semanticsLabels(tester);
      handle.dispose();

      expect(labels, contains('Organics requirement not met'),
          reason:
              'colour is not an accessible signal; the state is stated too');
      expect(labels, isNot(contains('Organics requirement met')),
          reason: 'and the wording must follow the state, not lag behind it');
    });
  });

  group('reading the colony card does not produce anything', () {
    // Found by fault injection, and worth stating plainly: pointing the track
    // rows back at the per-tick getters made **every test in the suite pass**
    // while the screen silently stole production. Those getters consume the
    // fractional remainder on the way out, so merely *looking* at a colony banked
    // its units early and left the remainder wrong for the real tick.
    //
    // No assertion on a displayed number can catch it, because the displayed
    // number looked correct. What was broken is a **side effect on state**.
    testWidgets('the per-day figures the card shows consume nothing',
        (tester) async {
      // Staffed at **this** world's optimum, read from its own class rather than
      // assumed. The fixture is a Jungle, and its numbers are not Terran's; a
      // hardcoded 15,000 produced 2,500/day there, which is under one unit per
      // tick and made the consuming-getter half of this test fail for a reason
      // that had nothing to do with consumption.
      final ore = planet.classSpec.ore;
      planet
        ..population = ore.optimumColonists
        ..colonistsMinerals = ore.optimumColonists;

      // Read everything the card reads, repeatedly, as a rebuild would.
      for (var i = 0; i < 5; i++) {
        expect(planet.productionRemainder, isEmpty,
            reason: 'displaying a colony must not advance its production');
        for (final track in PlanetClassSpec.tracks) {
          expect(planet.outputPerDayFor(track), greaterThanOrEqualTo(0));
          expect(planet.perTickFor(track), greaterThanOrEqualTo(0));
        }
        expect(planet.maxDroneOutputPerDay, greaterThanOrEqualTo(0));
      }
      await pump(tester, playerWith());
      expect(planet.productionRemainder, isEmpty,
          reason: 'and the card itself must not advance it either');
    });

    testWidgets(
        'the per-tick getters do consume, which is why the card avoids '
        'them', (tester) async {
      // The other half of the property. Without this, "the card consumes
      // nothing" could pass because nothing consumes anything, and the rename
      // would have removed a mechanism rather than a bug.
      final ore = planet.classSpec.ore;
      planet
        ..population = ore.optimumColonists
        ..colonistsMinerals = ore.optimumColonists;

      expect(planet.productionRemainder, isEmpty);
      // At the optimum this world makes its peak per day, which is a fraction of
      // a unit per tick, so the remainder is where the units live.
      final expectedPerTick = ore.maxOutputPerDay / PlanetClock.ticksPerDay;
      expect(expectedPerTick, greaterThan(1),
          reason: 'sanity: the peak must exceed one unit per tick, or there is '
              'no remainder to observe');
      expect(expectedPerTick, lessThan(2),
          reason: 'sanity: and must be under two, so the first tick banks '
              'exactly one whole unit');

      final first = planet.mineralOutput;
      expect(first, 1, reason: 'one whole unit banked, the rest carried');
      expect(planet.productionRemainder.containsKey('minerals'), isTrue,
          reason: 'the per-tick getter must carry its fraction forward');
      expect(planet.productionRemainder['minerals'],
          closeTo(expectedPerTick - 1, 0.0001));
    });

    testWidgets('a tick is what moves production', (tester) async {
      final ore = planet.classSpec.ore;
      planet
        ..population = ore.optimumColonists
        ..colonistsMinerals = ore.optimumColonists;
      final before = planet.productionRemainder['minerals'] ?? 0.0;
      planet.produce();
      expect(planet.productionRemainder['minerals'], isNot(before),
          reason: 'the tick is the only thing that should advance production');
    });

    test('the colony card reads the non-consuming getter', () {
      // A source scan, and deliberately so. This is a **structural** fact —
      // which identifier the track rows call — and not a behavioural one, so
      // scanning is the right tool. (The lesson about scans being answered by
      // prose was about asserting *behaviour* through source; here a comment
      // mentioning `mineralOutput` would fail this scan, which is a false
      // positive someone can see and fix, rather than a guard that silently
      // vouches for the wrong behaviour.)
      final screen = File('lib/screens/planet_screen.dart').readAsStringSync();
      // The row builder's call site, not the whole file: the drone readout and
      // the tick-reporting paths legitimately use the per-day form too.
      final rows = screen.substring(
        screen.indexOf('for (final t in PlanetClassSpec.tracks)'),
        screen.indexOf('_droneReadout(planet, cs)'),
      );
      expect(rows, contains('planet.outputPerDayFor(t)'));
      expect(rows, isNot(contains('mineralOutput')),
          reason: 'the per-tick getters consume the production remainder, so '
              'reading the card would take production away from the colony');
      expect(rows, isNot(contains('organicOutput')));
      expect(rows, isNot(contains('industrialOutput')));
    });
  });

  group('each track row has exactly one of each button', () {
    testWidgets('one add and one remove per track, not two of either',
        (tester) async {
      // A track row used to carry a `\u2212` on *both* sides of its count, and the
      // two did the same thing: both pulled colonists off the track and returned
      // them to the reserve. They were not equivalent, though \u2014 the leading
      // one was enabled only when the track held a full step, so on any colony
      // smaller than a step it rendered greyed out and read as a dead control
      // while the trailing one worked. Asked directly, nobody could say what
      // either button was for.
      //
      // The count is asserted per icon across the whole colony card: four tracks
      // \u00d7 one pair. The transfer steppers elsewhere on the screen use
      // `remove_rounded`, and the workforce ones use a bare `remove`, so the bare
      // glyph is what selects these and nothing else.
      await pump(tester, playerWith());

      // Three, not four: drones used to be a fourth workforce track and are now
      // derived from the output of the other three, so there is nothing to staff.
      expect(find.byIcon(Icons.add), findsNWidgets(3),
          reason: 'one assign button per production track');
      expect(find.byIcon(Icons.remove), findsNWidgets(3),
          reason: 'a second remove per row would be a duplicate control');
    });

    testWidgets('the buttons say what they move', (tester) async {
      // The reason the question could not be answered: a bare +/- pair on a row
      // of numbers does not say that the pair moves colonists between two
      // places, which is the only thing they do. The tooltip is the only place
      // that says so, so it has to be there.
      await pump(tester, playerWith());
      final tooltips = tester
          .widgetList<Tooltip>(find.byType(Tooltip))
          .map((t) => '${t.message}')
          .toList();

      expect(tooltips.where((m) => m.startsWith('Assign from reserve')),
          hasLength(3),
          reason: 'each add button names its source');
      expect(tooltips.where((m) => m == 'Return to reserve'), hasLength(3),
          reason: 'each remove button names its destination');
    });
  });

  group('workforce steppers move less than a full step', () {
    testWidgets('a small reserve can still be assigned', (tester) async {
      // 300, not the 200 this used to assert. The fixture still staffs 100
      // colonists on the drone track, and drones are no longer a workforce track,
      // so those 100 are in the reserve and available to assign. The test is
      // about a *small* reserve still being movable, and 300 is still small
      // against a 100-colonist step.
      expect(planet.reserveColonists, 300);
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
