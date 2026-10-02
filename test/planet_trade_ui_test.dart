import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';
import 'package:cosmic_trader/widgets/planet/planet_mini_controls.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';
import 'support/storage_fakes.dart';

/// Always below any failure chance, so a run that comes due is lost. Mirrors
/// `_AlwaysFailRandom` in the service tests; duplicated rather than shared
/// because a double that lives in another test file is a cross-file import
/// that breaks the moment that file is renamed.
class _AlwaysFailRandom implements math.Random {
  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}

/// Never below any failure chance, so the runs after a forced loss deliver.
class _NeverFailRandom implements math.Random {
  @override
  double nextDouble() => 1.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => max - 1;
}

final _rng = _NeverFailRandom();

/// Always fails, and picks the **last positive-weight cause** by returning the
/// top of the roll range. Against a federal port with no anomaly that is
/// `customsSeizure`, which is how a widget test reaches the seizure class
/// without a second injected decision.
class _LastCauseRandom implements math.Random {
  @override
  double nextDouble() => 0.0;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => max - 1;
}

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

/// Two ports with **different** maxima: one sells 50K, the other buys 8K.
///
/// This asymmetry is the point. With one port, or two ports where both maxima
/// coincide, a direction-blind "Max" is indistinguishable from a correct one —
/// so the fixture has to make the two answers disagree.
List<Sector> _twoSidedUniverse({int storedMinerals = 20000}) {
  final planet = _ownedWorld()..storedMinerals = storedMinerals;
  return [
    Sector(
        id: 1,
        name: 'Home',
        x: 0,
        y: 0,
        warpRoutes: const [2, 3],
        planets: [planet]),
    Sector(
        id: 2,
        name: 'Market',
        x: 100,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: _sellingPort()),
    Sector(
        id: 3,
        name: 'Buyer',
        x: -100,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: Port(
          name: 'Buyer',
          portClass: PortClass.free,
          buyPrices: const {'minerals': 60},
          sellPrices: const {},
          supply: const {},
          demand: const {'minerals': 8000},
          maxSupply: const {},
          maxDemand: const {'minerals': 8000},
          portCredits: 1000000,
          desiredCredits: 1000000,
        )),
  ];
}

/// The single port, but **federal** — which is the only port class that can
/// impound a shipment, and therefore the only way to reach the seizure class
/// from a widget test.
List<Sector> _federalUniverse({int storedMinerals = 0}) {
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
        name: 'Customs',
        x: 100,
        y: 0,
        warpRoutes: const [1],
        hasPort: true,
        port: _sellingPort().copyWith(
          name: 'Customs',
          portClass: PortClass.federal,
        )),
  ];
}

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

  testWidgets('a lost run shows LOST and a named cause in the Report',
      (WidgetTester tester) async {
    // The bug this fixes: the row counted a lost run toward "delivered", so an
    // order that lost its only run read 50/100 while the store gained nothing.
    // The row is the thing the player is watching, so a number that
    // overstates delivery is worse than no number at all.
    //
    // The order is built through the model rather than by tapping, because a
    // one-run order that loses its run **completes** and its row disappears —
    // which is correct, and is precisely why the Report (not the row) is the
    // durable record. A three-run order keeps a row alive to show the loss on.
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    await _pumpMarket(tester,
        enabled: true, player: _player(), onUpdate: (_) {});

    final reloaded = await store.loadUniverse();
    PlanetTradeService.create(
      planet: reloaded.first.planets.single,
      playerId: 'p1',
      portSectorId: 2,
      commodity: 'minerals',
      direction: TradeDirection.buy,
      units: 12000,
      ticksPerRun: 2,
      unitsPerRun: PlanetTradeService.freighterHold,
      unitPrice: 50,
    );
    // Two ticks: the first counts down, the second fires the run — and the
    // always-fail generator loses it.
    PlanetTradeService.advanceAll(reloaded, rng: _AlwaysFailRandom());
    PlanetTradeService.advanceAll(reloaded, rng: _AlwaysFailRandom());
    await store.saveUniverse(reloaded);

    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // Obvious, named, and it says where to find out why.
    expect(find.textContaining('LOST'), findsWidgets);
    expect(find.textContaining('see Report for the cause'), findsOneWidget);

    // **The delivered figure itself.** Asserting "LOST appears" cannot catch a
    // counter that lies: the marker is driven by `unitsLost`, so it renders
    // whether or not the number is right. This is the number the player is
    // watching, so it is the number asserted — 0 of 12.0K arrived, and the
    // 5.0K that went missing must not be counted as delivery.
    expect(find.textContaining('0 / 12.0K'), findsOneWidget);
    expect(find.textContaining('5.0K / 12.0K'), findsNothing);

    // And the Report names a cause, not just "lost".
    final report = find.byKey(const Key('market-report'));
    await tester.scrollUntilVisible(report, 200);
    await tester.pumpAndSettle();
    await tester.tap(report);
    await tester.pumpAndSettle();
    expect(find.text('Freight Report'), findsOneWidget);
    expect(find.textContaining('LOST —'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Max is direction-specific: the menu names both, and each fills '
      'its own figure', (WidgetTester tester) async {
    // The bug this fixes: one "Max" took the larger of the two maxima and wrote
    // it into a shared field, so pressing Max then the *other* button silently
    // did less than Max promised. Here the maxima differ five-fold, so the
    // wrong one is unmissable.
    final store = FaithfulUniverse(_twoSidedUniverse());
    UniverseStorage.instanceForTest = store;
    await _pumpMarket(tester,
        enabled: true, player: _player(), onUpdate: (_) {});

    final max = find.byKey(const Key('market-max-minerals'));
    await tester.scrollUntilVisible(max, 200);
    await tester.pumpAndSettle();
    await tester.tap(max);
    await tester.pumpAndSettle();

    // Both directions are offered, each with its own figure quoted live.
    // `textContaining`, not `text`: there is a Max button per commodity row, so
    // the bare label is not unique, and the menu entries carry trailing padding
    // spaces — both make an exact-match finder report "not found" for something
    // plainly on screen.
    expect(find.textContaining('Max buy'), findsOneWidget);
    expect(find.textContaining('Max sell'), findsOneWidget);
    // Both figures are **quoted**, not merely applied: a menu that silently
    // picked one would pass the behaviour check below while telling the
    // player nothing about the other.
    expect(find.text('50.0K'), findsWidgets, reason: 'the buy maximum');
    expect(find.text('8.0K'), findsWidgets, reason: 'the sell maximum');

    await tester.tap(find.textContaining('Max sell'));
    await tester.pumpAndSettle();

    // **What the control promised, not what the handler saved.** The sell path
    // clamps to the store and the planner fills only what the port will buy, so
    // a wrong figure in the field still produces a correct-looking order — and a
    // guard that only checks `unitsTotal` after the tap cannot tell the two
    // apart. The *displayed* amount is Max's actual contract.
    expect(find.text('8.0K'), findsOneWidget,
        reason: 'the field must show the sell maximum after Max sell');
    expect(find.text('50.0K'), findsNothing,
        reason: 'and not the buy maximum, which is what the old Max filled in');

    // The field now holds the *sell* maximum, and pressing Sell places exactly
    // that — not the buy maximum, and not a clamped surprise.
    final sell = find.byKey(const Key('market-sell-minerals'));
    await tester.scrollUntilVisible(sell, 200);
    await tester.pumpAndSettle();
    await tester.tap(sell);
    await tester.pumpAndSettle();

    // **Re-read after the tap.** `loadUniverse` re-parses a fresh graph every
    // call, so a universe captured beforehand is a snapshot the tap never
    // touches — asserting on it measures the wrong object and passes for the
    // wrong reason.
    final after = await store.loadUniverse();
    final jobs = after.first.planets.single.tradeJobs;
    expect(jobs, hasLength(1));
    expect(jobs.single.unitsTotal, 8000);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Report shows a finished order and its cause',
      (WidgetTester tester) async {
    final store = FaithfulUniverse(_universe());
    UniverseStorage.instanceForTest = store;
    await _pumpMarket(tester,
        enabled: true, player: _player(), onUpdate: (_) {});

    // Built through the model, then driven by the real tick pass with a forced
    // loss, because a *widget* can only be reached by tapping: the report's
    // subject is a settled order.
    final reloaded = await store.loadUniverse();
    PlanetTradeService.createOrder(
      planet: reloaded.first.planets.single,
      universe: reloaded,
      playerId: 'p1',
      commodity: 'minerals',
      direction: TradeDirection.buy,
      volume: 10000,
      actorFaction: 'trader',
    );
    // **Two** passes with the forcing generator: the cadence is hops-derived, so
    // the first pass only counts the run down and the second fires it. One pass
    // loses nothing, the order closes clean, and the report reads COMPLETE —
    // a fixture that cannot satisfy the condition it is testing.
    PlanetTradeService.advanceAll(reloaded, rng: _AlwaysFailRandom());
    PlanetTradeService.advanceAll(reloaded, rng: _AlwaysFailRandom());
    for (var i = 0;
        i < 20 && reloaded.first.planets.single.tradeJobs.isNotEmpty;
        i++) {
      PlanetTradeService.advanceAll(reloaded, rng: _rng);
    }
    await store.saveUniverse(reloaded);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    final report = find.byKey(const Key('market-report'));
    await tester.scrollUntilVisible(report, 200);
    await tester.pumpAndSettle();
    await tester.tap(report);
    await tester.pumpAndSettle();

    // Two sections answering two different questions.
    expect(find.text('Freight Report'), findsOneWidget);
    expect(find.text('ORDERS'), findsOneWidget);
    expect(find.text('RECENT RUNS'), findsOneWidget);
    // The order is summarised rather than listing ten anonymous runs.
    expect(find.textContaining('PARTIALLY LOST'), findsOneWidget);
    expect(find.textContaining('lost'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an impounded run reads HELD on the row, not LOST',
      (WidgetTester tester) async {
    // The report cannot be the only place a seizure is visible: the row is what
    // the player watches while the order runs. This is the guard that was
    // missing — with `seized += 0` in the row, every other test in the file
    // stayed green because none of them created a seizure.
    final store = FaithfulUniverse(_federalUniverse());
    UniverseStorage.instanceForTest = store;
    await _pumpMarket(tester,
        enabled: true, player: _player(), onUpdate: (_) {});

    final reloaded = await store.loadUniverse();
    PlanetTradeService.createOrder(
      planet: reloaded.first.planets.single,
      universe: reloaded,
      playerId: 'p1',
      commodity: 'minerals',
      direction: TradeDirection.buy,
      volume: 10000,
      actorFaction: 'trader',
    );
    // Two passes: the cadence is hops-derived, so the first only counts down.
    PlanetTradeService.advanceAll(reloaded, rng: _LastCauseRandom());
    PlanetTradeService.advanceAll(reloaded, rng: _LastCauseRandom());
    await store.saveUniverse(reloaded);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();

    // The row names the shortfall and says which kind it is.
    expect(find.textContaining('HELD'), findsWidgets);
    expect(find.textContaining('LOST'), findsNothing,
        reason: 'an impoundment is a partial delivery, not a destruction');
    expect(find.textContaining('held by customs'), findsOneWidget);

    final report = find.byKey(const Key('market-report'));
    await tester.scrollUntilVisible(report, 200);
    await tester.pumpAndSettle();
    await tester.tap(report);
    await tester.pumpAndSettle();
    expect(find.textContaining('PARTIAL —'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the Buy button refuses an order whose cover it cannot afford',
      (WidgetTester tester) async {
    // **The control's promise, not the handler's.** The panel quotes the premium
    // in the price line, so a button that ignored it would *look* right and let
    // the order through; the screen's own affordability check would then unwind
    // it with a snackbar a moment later. Two numbers for one order, and only the
    // visible one is the player's.
    final store = FaithfulUniverse(_twoSidedUniverse());
    UniverseStorage.instanceForTest = store;

    // **Derived from the fixture, not typed.** The threshold is "enough for the
    // goods, not enough for the goods plus cover", and a hand-written credit
    // figure sits inside a narrow band between two prices that move whenever the
    // economy is retuned — which is how a bound outlives the fixture it was
    // measured against. The price is read off the same plan the button reads.
    final universe = await store.loadUniverse();
    final probe = PlanetTradeService.plan(
      universe: universe,
      planet: universe.first.planets.single,
      commodity: 'minerals',
      direction: TradeDirection.buy,
      volume: 1000,
    );
    var goods = 0;
    for (final a in probe.allocations) {
      goods += a.units * a.unitPrice;
    }
    expect(goods, greaterThan(0));
    expect(PlanetTradeService.premiumFor(probe, TradeInsurance.full),
        greaterThan(0),
        reason: 'cover must cost something, or this fixture proves nothing');

    await _pumpMarket(tester,
        enabled: true, player: _player(credits: goods), onUpdate: (_) {});

    final cover = find.byKey(const Key('market-cover-full'));
    await tester.scrollUntilVisible(cover, 200);
    await tester.pumpAndSettle();
    await tester.tap(cover);
    await tester.pumpAndSettle();

    // The quote names what the cover costs, so the disabled button is explicable.
    expect(find.textContaining('cover'), findsWidgets);

    final buy = find.byKey(const Key('market-buy-minerals'));
    await tester.scrollUntilVisible(buy, 200);
    await tester.pumpAndSettle();
    // **The button's own state**, not the outcome. Tapping it and finding no
    // order proves nothing: the screen's own affordability check unwinds the
    // order a moment later, so a *live* button produces the same empty universe.
    // Only the control's `enabled` distinguishes the two.
    final button = tester.widget<PlanetMiniButton>(buy);
    expect(button.enabled, isFalse,
        reason: 'cover the pilot cannot afford must disable the button');
    // And it says why, because a dead button with no reason reads as a broken
    // one — the playtest report these controls already produced once.
    expect(button.disabledReason, contains('including cover'));

    // Nothing is placed, and the tap is inert rather than throwing.
    await tester.tap(buy, warnIfMissed: false);
    await tester.pumpAndSettle();
    final after = await store.loadUniverse();
    expect(after.first.planets.single.tradeJobs, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
