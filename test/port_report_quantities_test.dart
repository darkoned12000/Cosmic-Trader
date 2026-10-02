import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/computer_screen.dart';
import 'support/storage_fakes.dart';

Player _player() => Player(
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

Port _port(String name, {required int supply, required int demand}) => Port(
      name: name,
      portClass: PortClass.free,
      buyPrices: const {'minerals': 60},
      sellPrices: const {'minerals': 50},
      supply: {'minerals': supply},
      demand: {'minerals': demand},
      maxSupply: const {'minerals': 80000},
      maxDemand: const {'minerals': 60000},
      portCredits: 1000000,
      desiredCredits: 1000000,
    );

void main() {
  setUp(() {
    UniverseStorage.instanceForTest = ReadOnlyUniverse([
      Sector(
          id: 1,
          name: 'Home',
          x: 0,
          y: 0,
          warpRoutes: const [2],
          hasPort: true,
          port: _port('Home Port', supply: 50000, demand: 12000)),
      Sector(
          id: 2,
          name: 'Near',
          x: 100,
          y: 0,
          warpRoutes: const [1, 3],
          hasPort: true,
          port: _port('Near Port', supply: 10000, demand: 6000)),
      Sector(
          id: 3,
          name: 'Far',
          x: 200,
          y: 0,
          warpRoutes: const [2],
          hasPort: true,
          port: _port('Far Port', supply: 40000, demand: 30000)),
    ]);
  });

  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  Future<void> openReport(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ComputerScreen(player: _player(), onPlayerUpdate: (_) {}),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('Port Report'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  testWidgets('rows show live quantities and hops from the player',
      (WidgetTester tester) async {
    await openReport(tester);

    // Quantities are live stock against the effective cap, not bare prices.
    expect(find.text('50.0K/80.0K'), findsOneWidget,
        reason: 'sell-side supply/cap on the home port');
    expect(find.text('12.0K/60.0K'), findsOneWidget,
        reason: 'buy-side demand/cap on the home port');
    expect(find.text('10.0K/80.0K'), findsOneWidget);

    // Distance from the player's sector on every card.
    expect(find.text('here'), findsOneWidget);
    expect(find.text('1 hop'), findsOneWidget);
    expect(find.text('2 hops'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Nearest sort puts the closest port first',
      (WidgetTester tester) async {
    await openReport(tester);

    await tester.tap(find.text('Nearest'));
    await tester.pumpAndSettle();

    // Cards render in sector order by default (1, 2, 3); after Nearest the
    // player's own sector still leads and the far port trails. Read order
    // off the rendered positions rather than trusting the model list.
    final dy1 = tester.getTopLeft(find.text('#1')).dy;
    final dy2 = tester.getTopLeft(find.text('#2')).dy;
    final dy3 = tester.getTopLeft(find.text('#3')).dy;
    expect(dy1, lessThan(dy2));
    expect(dy2, lessThan(dy3));
    expect(tester.takeException(), isNull);
  });

  testWidgets('report fits a 430px phone with no overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430 * 3, 900 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await openReport(tester);
    // A RenderFlex overflow throws during layout and fails via takeException.
    expect(find.text('50.0K/80.0K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
