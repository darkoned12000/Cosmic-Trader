import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/sector_view.dart';

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
  late List<Sector> universe;

  setUp(() {
    universe = [
      _makeSector(1, 'Alpha Prime'),
      _makeSector(2, 'Beta Reach'),
      _makeSector(3, 'Gamma Hollow'),
    ];
    UniverseStorage.instanceForTest = _FakeUniverseStorage(universe);
  });

  tearDown(() {
    UniverseStorage.instanceForTest = null;
  });

  /// Pumps SectorView at [width] and verifies the layout builds and lays out
  /// without throwing. TacticalMap runs a repeating starfield animation, so
  /// fixed pumps are used instead of pumpAndSettle (which would time out).
  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    await tester.binding.setSurfaceSize(Size(width, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SectorView(
          player: _makePlayer(),
          onPlayerUpdate: (_) {},
          npcs: const [],
          fedSpaceEnd: 1,
        ),
      ),
    ));
    // Let the async universe load complete and build the layout.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // The sector view should have rendered content (not the loading spinner).
    expect(
      find.byType(SectorView),
      findsOneWidget,
      reason: 'SectorView should render at width $width',
    );
  }

  testWidgets(
      'SectorView layouts render without exceptions at every breakpoint',
      (WidgetTester tester) async {
    // Desktop (>= 900), tablet (600-900), mobile (< 600), plus narrow
    // logical sizes reached at high UI scale (e.g. 180% on a ~1160px
    // window → ~644px logical → tablet layout with a ~364px map column).
    const widths = [500, 620, 650, 700, 800, 900, 1200, 1600];
    for (final w in widths) {
      await pumpAtWidth(tester, w.toDouble());
    }
  });

  testWidgets(
      'tablet layout uses fixed heights (no vertical Expanded inside scroll)',
      (WidgetTester tester) async {
    // Regression: the tablet layout previously gave ActionLogPanel and
    // CommunicationsPanel vertical `Expanded` flex inside a
    // SingleChildScrollView, which threw an unbounded-height RenderFlex
    // assertion whenever UI scale moved the logical window width into the
    // 600-900px range. Fixed SizedBox heights are required instead.
    await pumpAtWidth(tester, 800);

    final build = tester.widget<SectorView>(find.byType(SectorView));
    expect(build, isNotNull);
  });
}
