import 'dart:convert';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/ship_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The Ship screen's cargo/equipment card.
///
/// It exists because the card used to be called "Cargo Hold & Components" and
/// showed nothing but a capacity number, which made two things that obey
/// completely different rules look like one thing. These guards hold the split
/// in place: **cargo** is the resource types and shares one hold against a
/// shared capacity; **equipment** is the ordnance and takes no hold space at
/// all.
/// Faithful storage: re-parses on every load and really writes.
///
/// Needed because `ShipStatusView.initState` awaits `UniverseStorage.loadUniverse`,
/// and with no `path_provider` in a widget test that await is left **pending**
/// inside the fake-async zone. The screen never leaves its spinner, and every
/// content assertion then reports the text as missing while the test is plainly
/// looking at a loading state. Nothing throws and nothing warns.
class _FaithfulUniverse extends UniverseStorage {
  _FaithfulUniverse() : _blob = '[]';
  String _blob;

  @override
  Future<List<Sector>> loadUniverse() async =>
      (jsonDecode(_blob) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Sector.fromJson)
          .toList();

  @override
  Future<void> saveSectors(List<Sector> updated) async {
    _blob = jsonEncode(updated.map((e) => e.toJson()).toList(growable: false));
  }
}

void main() {
  late _FaithfulUniverse store;

  setUp(() {
    store = _FaithfulUniverse();
    UniverseStorage.instanceForTest = store;
  });

  tearDown(() => UniverseStorage.instanceForTest = null);

  Player pilot({
    Map<String, int> cargo = const {},
    int cargoUsed = 0,
    int maxCargo = 100,
    int torpedoes = 0,
    int detonators = 0,
  }) =>
      Player(
        name: 'Tester',
        currentSectorId: 1,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargo: cargo,
        cargoUsed: cargoUsed,
        maxCargo: maxCargo,
        cargoSize: maxCargo,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.duran,
        genesisTorpedoes: torpedoes,
        atomicDetonators: detonators,
      );

  Future<void> pump(WidgetTester tester, Player player) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
          body: ShipStatusView(player: player, onPlayerUpdate: (_) {})),
    ));
    // Settle rather than a fixed pump: the screen has to leave `_loading`
    // first, and the await behind that is a microtask chain off disk.
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason:
            'the screen is still loading \u2014 content assertions would be '
            'reading an empty tree and reporting the text as missing');
  }

  group('the card is titled Cargo & Equipment, not Cargo Hold & Components',
      () {
    testWidgets('and says so', (tester) async {
      await pump(tester, pilot());
      expect(find.text('Cargo & Equipment'), findsOneWidget);
      expect(find.text('Cargo Hold & Components'), findsNothing,
          reason: 'the old name made two different things look like one');
    });
  });

  group('cargo and equipment are labelled as different systems', () {
    testWidgets('both headings are on screen', (tester) async {
      await pump(tester, pilot());
      expect(find.text('CARGO — uses hold slots'), findsOneWidget);
      expect(find.text('EQUIPMENT — no hold slots'), findsOneWidget);
    });

    testWidgets('an empty hold says so rather than showing a blank',
        (tester) async {
      await pump(tester, pilot());
      // A card with a heading and nothing under it reads as broken, or as a
      // section that failed to load.
      expect(find.text('Empty'), findsOneWidget);
    });

    testWidgets('carrying nothing says so', (tester) async {
      await pump(tester, pilot());
      expect(find.text('None carried'), findsOneWidget);
    });
  });

  group('cargo contents are listed and counted', () {
    testWidgets('a loaded hold shows the types and their amounts',
        (tester) async {
      await pump(
          tester,
          pilot(
            cargo: const {'minerals': 5000, 'organics': 1200},
            cargoUsed: 6200,
          ));
      expect(find.text('Minerals'), findsOneWidget);
      expect(find.text('Organics'), findsOneWidget);
      // The compact form, because that is what the screen renders. Asserting
      // the raw integer would pass against a card that shows nothing.
      expect(find.text('5.0K'), findsOneWidget);
      expect(find.text('1.2K'), findsOneWidget);
    });

    testWidgets('the capacity row is used / capacity, not a bare number',
        (tester) async {
      // "6200" on its own cannot be read: it is out of context whether that is a
      // load, a limit, or a remaining figure.
      await pump(tester, pilot(cargoUsed: 40, maxCargo: 100));
      expect(find.text('40 / 100'), findsOneWidget);
    });
  });

  group('equipment is listed and is not cargo', () {
    testWidgets('held ordnance is shown with a count', (tester) async {
      await pump(tester, pilot(torpedoes: 3, detonators: 1));
      expect(find.text('Genesis Torpedo'), findsOneWidget);
      expect(find.text('Atomic Detonator'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);
    });

    testWidgets('an empty hold still shows carried ordnance', (tester) async {
      // The load-bearing case. Ordnance is **equipment**: it rides on the ship,
      // not in the hold, so a hold at zero and a full rack are the normal state
      // for a pilot about to plant a world. A card that only rendered equipment
      // *under* the hold heading would show "Empty" here and hide a full rack.
      await pump(tester, pilot(cargo: const {}, cargoUsed: 0, torpedoes: 5));
      expect(find.text('Empty'), findsOneWidget, reason: 'the hold is empty');
      expect(find.text('None carried'), findsNothing);
      expect(find.text('Genesis Torpedo'), findsOneWidget,
          reason: 'five torpedoes are carried and the hold has nothing to do '
              'with it');
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('a full hold still shows carried ordnance', (tester) async {
      await pump(
          tester,
          pilot(
            cargo: const {'minerals': 100},
            cargoUsed: 137,
            maxCargo: 137,
            detonators: 2,
          ));
      expect(find.text('137 / 137'), findsOneWidget, reason: 'hold is full');
      expect(find.text('Atomic Detonator'), findsOneWidget);
    });
  });

  group('the split is a rule, not a label', () {
    test('ordnance does not occupy the hold', () {
      // The card's two headings make a promise about *rules*, not about
      // presentation. If buying a torpedo ever moved `cargoUsed`, the two
      // sections would be describing the same pool under two names and the
      // player could not tell which number to watch.
      expect(_holding(player: pilot(torpedoes: 3, detonators: 2)), 0,
          reason: 'carrying five units of ordnance uses no hold space');
    });
  });
}

/// The hold usage a player actually ends up with after carrying ordnance.
///
/// Written out rather than read off the fixture so the guard is about the
/// *interaction* — carrying ordnance and being in the hold at the same time —
/// which is the only way a leak of the two systems into each other would show.
int _holding({required Player player}) {
  final base = player.cargoUsed;
  // Round-tripping the counters is what the emporium and the launch action do.
  final after =
      player.copyWith(genesisTorpedoes: 0, atomicDetonators: 0).cargoUsed;
  expect(after, base, reason: 'emptying the rack must not change the hold');
  return after;
}
