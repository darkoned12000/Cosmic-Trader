import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';
import 'support/storage_fakes.dart';

Player _player({int credits = 1000000}) => Player(
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
      credits: credits,
      researchPoints: 0,
    );

Planet _ownedWorld() => Planet(
      id: 'w1',
      name: 'Xandor',
      planetType: 'Terran',
      owner: FactionClass.trader,
      scanned: true,
    );

Port _sellingPort() => Port(
      name: 'Emporium',
      portClass: PortClass.free,
      buyPrices: const {},
      sellPrices: const {'minerals': 50},
      supply: const {'minerals': 50000},
      demand: const {},
      maxSupply: const {'minerals': 80000},
      maxDemand: const {},
      portCredits: 1000000,
      desiredCredits: 1000000,
    );

List<Sector> _universe({int storedMinerals = 0}) {
  final planet = _ownedWorld()..storedMinerals = storedMinerals;
  return [
    Sector(
        id: 1,
        name: 'Home',
        x: 0,
        y: 0,
        warpRoutes: const [2],
        planets: [planet]),
    Sector(
        id: 2,
        name: 'Market',
        x: 100,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: _sellingPort()),
  ];
}

Future<void> _pumpMarket(WidgetTester tester,
    {required bool enabled,
    required Player player,
    required void Function(Player) onUpdate}) async {
  await tester.pumpWidget(MaterialApp(
    home: PlanetScreen(
      player: player,
      onPlayerUpdate: onUpdate,
      planetTradingEnabled: enabled,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  // Land on the owned world: the transfers/market live in the owner card.
  expect(tester.takeException(), isNull);
}

void main() {
  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  testWidgets('market controls are absent when the toggle is off',
      (WidgetTester tester) async {
    UniverseStorage.instanceForTest = FaithfulUniverse(_universe());
    await _pumpMarket(tester,
        enabled: false, player: _player(), onUpdate: (_) {});

    expect(find.byKey(const Key('market-buy-minerals')), findsNothing);
    expect(find.byKey(const Key('market-sell-minerals')), findsNothing);
    expect(find.text('Market'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market controls are present when the toggle is on',
      (WidgetTester tester) async {
    UniverseStorage.instanceForTest = FaithfulUniverse(_universe());
    await _pumpMarket(tester,
        enabled: true, player: _player(), onUpdate: (_) {});

    expect(find.byKey(const Key('market-buy-minerals')), findsOneWidget);
    expect(find.byKey(const Key('market-sell-minerals')), findsOneWidget);
    expect(find.text('Market'), findsOneWidget);
    // The quote names the filling port rather than counting it.
    expect(find.textContaining('Emporium'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buy places a job, charges credits, reserves the port',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Paid up front at the live price: 1,000 units × effective sell price.
    expect(player.credits, lessThan(1000000));
    // A job is in flight with a per-run countdown bar.
    expect(find.byType(TickProgressBar), findsWidgets);
    // The port's shelf shrank by the reservation (paid for, written through).
    final reloaded = await store.loadUniverse();
    final portSector = reloaded.firstWhere((s) => s.id == 2);
    expect(portSector.port!.getSupply('minerals'), lessThan(50000));
    final home = reloaded.firstWhere((s) => s.id == 1);
    expect(home.planets.single.tradeJobs, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sell moves goods off the world into a job',
      (WidgetTester tester) async {
    // A buying port instead of a selling one.
    final planet = _ownedWorld()..storedMinerals = 5000;
    final buying = Port(
      name: 'Buyer',
      portClass: PortClass.free,
      buyPrices: const {'minerals': 60},
      sellPrices: const {},
      supply: const {},
      demand: const {'minerals': 40000},
      maxSupply: const {},
      maxDemand: const {'minerals': 60000},
      portCredits: 1000000,
      desiredCredits: 1000000,
    );
    final store = FaithfulUniverse([
      Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2],
          planets: [planet]),
      Sector(
          id: 2,
          name: 'Market',
          x: 100,
          y: 0,
          warpRoutes: const [1],
          hasPort: true,
          port: buying),
    ]);
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final sell = find.byKey(const Key('market-sell-minerals'));
    await tester.scrollUntilVisible(sell, 200);
    await tester.pumpAndSettle();
    await tester.tap(sell);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Goods left the store at order time (the reservation).
    final reloaded = await store.loadUniverse();
    final home = reloaded.firstWhere((s) => s.id == 1);
    expect(home.planets.single.storedMinerals, lessThan(5000));
    expect(home.planets.single.tradeJobs, hasLength(1));
    // The port's demand book shrank by the same reservation.
    final portSector = reloaded.firstWhere((s) => s.id == 2);
    expect(portSector.port!.getDemand('minerals'), lessThan(40000));
    expect(tester.takeException(), isNull);
  });

  testWidgets('two taps are two order rows with one Cancel each',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pump();
    await tester.tap(buy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // One Cancel per request — never one per port-run, never a shared row.
    expect(find.text('Cancel'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a split order reads as one row across its ports',
      (WidgetTester tester) async {
    Port small(String name, int supply) => Port(
          name: name,
          portClass: PortClass.free,
          buyPrices: const {},
          sellPrices: const {'minerals': 50},
          supply: {'minerals': supply},
          demand: const {},
          maxSupply: const {'minerals': 80000},
          maxDemand: const {},
          portCredits: 1000000,
          desiredCredits: 1000000,
        );
    final planet = _ownedWorld();
    final store = FaithfulUniverse([
      Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2, 3],
          planets: [planet]),
      Sector(
          id: 2,
          name: 'Near',
          x: 100,
          y: 0,
          warpRoutes: const [1],
          hasPort: true,
          port: small('Near Port', 300)),
      Sector(
          id: 3,
          name: 'Far',
          x: 200,
          y: 0,
          warpRoutes: const [1],
          hasPort: true,
          port: small('Far Port', 800)),
    ]);
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 300 + 700 across two ports, but one request: one row, one Cancel.
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.textContaining('2 ports'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('market fits a 430px phone with a job in flight',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Job rows, countdown bars and preview lines all laid out: a RenderFlex
    // overflow throws during layout and fails via takeException.
    expect(find.byType(TickProgressBar), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a clobbered order is re-dispatched once, never re-charged',
      (WidgetTester tester) async {
    // The tick snapshot race, end to end: the order is paid for and saved,
    // a stale pass erases it, and the poll re-creates the same shares under
    // the same ids instead of losing the money.
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    var player = _player();
    await _pumpMarket(tester,
        enabled: true, player: player, onUpdate: (p) => player = p);

    final pre = store.snapshot();
    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    await tester.tap(buy);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final charged = player.credits;
    expect(charged, lessThan(1000000));
    var reloaded = await store.loadUniverse();
    final firstId = reloaded.first.planets.single.tradeJobs.single.id;

    // A stale pass wipes the order back to before it existed.
    store.writeBackSnapshot(pre);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Re-dispatched, not duplicated (same job id) and not re-charged.
    expect(player.credits, charged);
    reloaded = await store.loadUniverse();
    final jobs = reloaded.first.planets.single.tradeJobs;
    expect(jobs, hasLength(1));
    expect(jobs.single.id, firstId);
    final portSector = reloaded.firstWhere((s) => s.id == 2);
    expect(portSector.port!.getSupply('minerals'), lessThan(50000));

    // Past the confirmation bound the order is left alone: still one job,
    // still single-charged — re-creating blindly would duplicate goods.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    reloaded = await store.loadUniverse();
    expect(reloaded.first.planets.single.tradeJobs, hasLength(1));
    expect(player.credits, charged);
    expect(tester.takeException(), isNull);
  });
}
