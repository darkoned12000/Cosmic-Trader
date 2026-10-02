import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// The treasury withdrawal glitch: withdrawing never zeroed the treasury, so
/// the same credits withdrew over and over.
///
/// Mechanism: the tick loads the universe, works it for seconds, then saves
/// it back. A withdrawal landing inside that window is overwritten by a
/// snapshot taken before it existed — no error, and the treasury reads full
/// again. The screen now holds the withdrawal as intent and re-asserts it
/// until the stored value drops, crediting the pilot exactly once.

Player _player() => Player(
      id: 'p1',
      name: 'Tester',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 50,
      maxShields: 50,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: 1000,
      researchPoints: 0,
    );

List<Sector> _universe({int revenue = 5000}) {
  final planet = Planet(
    id: 'w1',
    name: 'Xandor',
    planetType: 'Terran',
    owner: FactionClass.trader,
    scanned: true,
  )..accumulatedRevenue = revenue;
  return [
    Sector(
        id: 1,
        name: 'Home',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [planet]),
  ];
}

Future<void> _pump(WidgetTester tester,
    {required Player player, required void Function(Player) onUpdate}) async {
  await tester.pumpWidget(MaterialApp(
    home: PlanetScreen(
      player: player,
      onPlayerUpdate: onUpdate,
      planetTradingEnabled: true,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  expect(tester.takeException(), isNull);
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(finder, 200);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  testWidgets('withdraw moves revenue once and zeroes the treasury',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pump(tester, player: player, onUpdate: (p) => player = p);

    await _tapKey(tester, 'market-withdraw');

    expect(player.credits, 6000);
    var reloaded = await store.loadUniverse();
    expect(reloaded.single.planets.single.accumulatedRevenue, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale tick write-back cannot resurrect withdrawn revenue',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pump(tester, player: player, onUpdate: (p) => player = p);

    // The tick's snapshot, taken before the withdrawal exists.
    final stale = store.snapshot();
    expect(stale.single.planets.single.accumulatedRevenue, 5000);

    await _tapKey(tester, 'market-withdraw');
    expect(player.credits, 6000);

    // The tick finishes its pass and writes the stale snapshot back.
    store.writeBackSnapshot(stale);

    // The 1-second poll reconciles: the intent re-asserts the deduction.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Credited exactly once — never 11,000 — and the treasury is 0 again.
    expect(player.credits, 6000);
    final reloaded = await store.loadUniverse();
    expect(reloaded.single.planets.single.accumulatedRevenue, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale pass landing after settle is caught by the watch',
      (WidgetTester tester) async {
    // The narrower race: a tick that started before the withdrawal lands
    // AFTER the confirming poll has already settled the intent. Settling
    // starts a short watch carrying the job digest; a treasury climbing back
    // with no landing to explain it re-registers the guard.
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pump(tester, player: player, onUpdate: (p) => player = p);

    final stale = store.snapshot();
    await _tapKey(tester, 'market-withdraw');
    expect(player.credits, 6000);

    // Confirming poll: deduction visible, intent settles into the watch.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // The stale pass finally lands — after the settle, with no guard left
    // except the watch.
    store.writeBackSnapshot(stale);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    // Watch re-registered the intent; the next poll re-asserts the cut.
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Still credited exactly once, treasury back at zero.
    expect(player.credits, 6000);
    final reloaded = await store.loadUniverse();
    expect(reloaded.single.planets.single.accumulatedRevenue, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('send to bank earns Guild interest from a stamped deposit',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pump(tester, player: player, onUpdate: (p) => player = p);

    await _tapKey(tester, 'market-bank');

    // Wallet untouched; the Guild account holds it with the clock stamped,
    // which is what starts interest (a null stamp earns nothing).
    expect(player.credits, 1000);
    expect(player.bankBalance, 5000);
    expect(player.lastInterestTick, isNotNull);
    final reloaded = await store.loadUniverse();
    expect(reloaded.single.planets.single.accumulatedRevenue, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a stale write-back cannot resurrect banked revenue either',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pump(tester, player: player, onUpdate: (p) => player = p);

    final stale = store.snapshot();
    await _tapKey(tester, 'market-bank');
    expect(player.bankBalance, 5000);

    store.writeBackSnapshot(stale);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    expect(player.bankBalance, 5000);
    final reloaded = await store.loadUniverse();
    expect(reloaded.single.planets.single.accumulatedRevenue, 0);
    expect(tester.takeException(), isNull);
  });
}
