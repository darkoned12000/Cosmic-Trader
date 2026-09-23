import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/computer_screen.dart';
import 'package:cosmic_trader/screens/ports_knowledge_base.dart';

/// Fake universe storage that returns a synthetic universe without touching
/// the filesystem (path_provider is unavailable in widget tests).
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

Sector _makeSector(int id, String name) => Sector(
      id: id,
      name: name,
      x: id * 100.0,
      y: id * 50.0,
      warpRoutes: [1, 2, 3].where((w) => w != id).toList(),
    );

void main() {
  setUp(() {
    UniverseStorage.instanceForTest = _FakeUniverseStorage([
      _makeSector(1, 'Alpha Prime'),
      _makeSector(2, 'Beta Reach'),
    ]);
  });

  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  Future<void> pumpComputer(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      home: ComputerScreen(
        player: _makePlayer(),
        onPlayerUpdate: (_) {},
      ),
    ));
    // Let the async universe load complete.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  testWidgets('Ports Guide back arrow returns to the Computer menu',
      (WidgetTester tester) async {
    // Regression: PortsKnowledgeBaseScreen previously called
    // Navigator.of(context).pop() on its back button, but it is swapped
    // inline inside ComputerScreen (a GameShell tab — not a pushed route).
    // The pop removed the app's root route, disposing GameShell and killing
    // the tick service (gray screen, "[TickService] Stopped").
    await pumpComputer(tester);

    await tester.tap(find.text('Ports Guide'));
    await tester.pumpAndSettle();
    expect(find.byType(PortsKnowledgeBaseScreen), findsOneWidget,
        reason: 'Ports Guide should open');

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    // The Computer menu must be back — not an empty/pop up root route.
    expect(find.byType(PortsKnowledgeBaseScreen), findsNothing);
    expect(find.text('Banking'), findsOneWidget,
        reason: 'back should return to the Computer menu, not pop the app');
    expect(tester.takeException(), isNull);
  });
}
