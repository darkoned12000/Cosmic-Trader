import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/port_screen.dart';

class _FakeUniverseStorage extends UniverseStorage {
  final List<Sector> sectors;

  _FakeUniverseStorage(this.sectors);

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async => sectors;

  @override
  void logSectorStats(List<Sector> _) {}
}

Player _makePlayer() => Player(
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

void main() {
  tearDown(() => UniverseStorage.instanceForTest = null);

  testWidgets('Hack Codex dialog lays out without intrinsic viewport errors',
      (WidgetTester tester) async {
    final port = Port(
      name: 'Test Port',
      portClass: PortClass.independent,
      buyPrices: const {},
      sellPrices: const {},
      maxSupply: const {'minerals': 10},
      maxDemand: const {'minerals': 10},
    );
    final sector = Sector(
      id: 1,
      name: 'Test Sector',
      x: 0,
      y: 0,
      warpRoutes: const [],
      hasPort: true,
      port: port,
    );
    UniverseStorage.instanceForTest = _FakeUniverseStorage([sector]);

    await tester.binding.setSurfaceSize(const Size(1000, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PortScreen(
            player: _makePlayer().copyWith(
              successfulHacks: 2,
              hackedPorts: const ['Test Port'],
            ),
            onPlayerUpdate: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Codex'));
    await tester.pump();

    expect(find.text('HACK CODEX'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
