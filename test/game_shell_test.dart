import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/game_shell.dart';

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

const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory documentsDir;

  setUp(() {
    // Point path_provider at a real temp folder so the storages complete
    // their writes (otherwise the save futures never resolve in the
    // fake-async test zone and the exit-timeout timer stays pending).
    documentsDir = Directory.systemTemp.createTempSync('ct_documents');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      _pathProviderChannel,
      (call) async => documentsDir.path,
    );
    // Let SystemNavigator.pop() (the non-desktop exit path) resolve — the
    // framework already treats 'flutter/platform' as an optional channel, so
    // no mock is required here.

    UniverseStorage.instanceForTest = _FakeUniverseStorage([
      _makeSector(1, 'Alpha Prime'),
      _makeSector(2, 'Beta Reach'),
      _makeSector(3, 'Gamma Hollow'),
    ]);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    UniverseStorage.instanceForTest = null;
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  });

  /// Pumps GameShell, then unmounts it so the tick timer and any animations
  /// are disposed before the test ends (no pending-timer failures).
  Future<void> pumpShell(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester
        .pumpWidget(MaterialApp(home: GameShell(initialPlayer: _makePlayer())));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  }

  Future<void> unmountShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('Exit Game is available in the small layout and does not throw',
      (WidgetTester tester) async {
    await pumpShell(tester, const Size(580, 900));

    // AppBar action with "Exit Game" tooltip.
    final exitButton = find.byTooltip('Exit Game');
    expect(exitButton, findsOneWidget,
        reason: 'small layout AppBar should expose Exit Game');

    await tester.tap(exitButton);
    await tester.pump();
    // Pump past the exit-save timeout: real file I/O can't resolve inside
    // the fake-async zone, so firing the 10s timeout completes the exit
    // flow deterministically (the save handlers never throw either way).
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull,
        reason: 'tapping Exit Game must not throw');

    await unmountShell(tester);
  });

  testWidgets('Exit Game is available in the rail layout and does not throw',
      (WidgetTester tester) async {
    await pumpShell(tester, const Size(1600, 900));

    // Rail bottom button labelled "Exit Game" below "Logout".
    expect(find.widgetWithText(TextButton, 'Exit Game'), findsOneWidget,
        reason: 'large layout rail should expose an Exit Game button');
    expect(find.widgetWithText(TextButton, 'Logout'), findsOneWidget);

    await tester.tap(find.text('Exit Game'));
    await tester.pump();
    // Pump past the exit-save timeout: real file I/O can't resolve inside
    // the fake-async zone, so firing the 10s timeout completes the exit
    // flow deterministically (the save handlers never throw either way).
    await tester.pump(const Duration(seconds: 11));
    expect(tester.takeException(), isNull,
        reason: 'tapping Exit Game must not throw');

    await unmountShell(tester);
  });

  testWidgets('rail remains usable in a short desktop panel',
      (WidgetTester tester) async {
    await pumpShell(tester, const Size(700, 500));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull,
        reason: 'a short desktop panel must not overflow the navigation rail');

    await unmountShell(tester);
  });
}
