import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/sector_view.dart';
import 'support/storage_fakes.dart';

/// Storage that re-parses on every read, like the real one.
///
/// It has to. `UniverseStorage.loadUniverse()` rebuilds the whole object graph
/// per call, which is why two widgets reading "the same" sector are mutating
/// different `Planet` objects. A fake that handed back one shared list would
/// make every write-through assertion pass for free and would have hidden the
/// original bug entirely.

/// A storage double that overrides **only `saveUniverse`**, leaving the real
/// `saveSectors` in place.
///
/// This is the exact shape the `_markWritten()` call in `saveSectors` exists
/// for, per its own comment: a fake that replaces the file seam and inherits the
/// merge would otherwise silently stop announcing writes, "and the guard for
/// 'does a write reach other screens' would go quiet without failing".
///
/// **That guard did not exist.** Removing the bump from `saveSectors` broke
/// nothing in the whole suite, because in production `saveUniverse` bumps too —
/// so the line was redundant *and* unverifiable, and its comment described
/// coverage it did not have. This test is the guard the comment promised.
class _SaveUniverseOnly extends UniverseStorage {
  _SaveUniverseOnly(this.sectors);

  final List<Sector> sectors;

  /// Counts calls, so the test can prove the real `saveSectors` really ran
  /// rather than the assertion passing because nothing happened.
  int saveUniverseCalls = 0;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async => sectors;

  @override
  Future<void> saveUniverse(List<Sector> sectors) async {
    saveUniverseCalls++;
  }

  @override
  void logSectorStats(List<Sector> _) {}
}

/// Pumps a bounded number of frames instead of `pumpAndSettle`.
///
/// `SectorView` hosts the tactical map, whose starfield animates forever, so
/// there is no frame at which the tree is quiet and `pumpAndSettle` times out
/// having asserted nothing. A fixed budget is the honest way to let layout and
/// the async load finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Sector _sector() => Sector(
      id: 1,
      name: 'Kronos Reach',
      x: 0,
      y: 0,
      warpRoutes: const [],
    );

Player _player() => Player(
      name: 'Tester',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 100,
      maxShields: 100,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 100,
      credits: 5000,
      researchPoints: 0,
      faction: FactionClass.duran,
      genesisTorpedoes: 2,
    );

/// The reported bug: a torpedo fired on the **Ship** screen creates a world,
/// and the Sector Contents panel sitting beside it kept showing the sector as it
/// had been at mount. The world you had just paid for was invisible until you
/// left the tab and came back.
///
/// The root cause was structural, not a missed `setState`: `SectorView` loaded
/// the universe once in `initState` and never re-read, so it had no idea the
/// file had changed. Patching that in the launching screen cannot work — the
/// writer knows nothing about the Sector tab — which is why the signal comes
/// from storage itself.
void main() {
  late FaithfulUniverse storage;

  setUp(() {
    storage = FaithfulUniverse([_sector()]);
    UniverseStorage.instanceForTest = storage;
  });
  tearDown(() => UniverseStorage.instanceForTest = null);

  Future<void> pumpView(WidgetTester tester) async {
    // Tall: the panel is a long column and a lazily-unbuilt entry reads as
    // absent rather than as below the fold.
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SectorView(
          player: _player(),
          npcs: const [],
          onPlayerUpdate: (_) {},
          settings: GameSettings.defaults(),
        ),
      ),
    ));
    await _settle(tester);
  }

  testWidgets('a world written by another screen reaches the Sector tab',
      (tester) async {
    await pumpView(tester);

    // Before: nothing but the launch row.
    expect(find.textContaining('NOT SCANNED'), findsNothing);

    // Someone else — the Ship screen, the planet screen, an NPC port raid —
    // writes a world. No callback into this widget, no setState, nothing but a
    // write to storage.
    final fresh = await storage.loadUniverse();
    final sector = fresh.first;
    sector.planets.add(Planet(
      id: 'p-new',
      name: 'Ironhold',
      planetType: 'Mountain',
      scanned: true,
      owner: FactionClass.duran,
    ));
    await storage.saveSectors([sector]);

    await _settle(tester);

    expect(find.text('IRONHOLD'), findsOneWidget,
        reason: 'the new world is listed');
    // The entry's *label* is uppercased but its detail line keeps the type as
    // stored, so assert on what the panel actually renders.
    expect(find.textContaining('Mountain'), findsOneWidget);
    // And it reads as yours, which is the other half of the request: a world
    // you just paid for must not render with `NOT SCANNED` next to it.
    expect(find.textContaining('NOT SCANNED'), findsNothing);
    expect(find.textContaining('OWNED'), findsOneWidget);
  });

  testWidgets('a failed read leaves the tab standing rather than blanking it',
      (tester) async {
    await pumpView(tester);
    // Marker has to be something that still exists. The contents list used to
    // carry a 'LAUNCH TORPEDO' row and no longer does, so this assertion would
    // have gone quietly green-to-red for a reason that had nothing to do with the
    // refresh. 'SECTOR CONTENTS' is the panel header and is always present.
    expect(find.textContaining('SECTOR CONTENTS'), findsOneWidget);

    // A refresh that cannot read must not take the view down with it: the
    // snapshot already on screen is older but true.
    storage.blobThrows = true;
    storage.revision.value++;
    await _settle(tester);

    expect(find.textContaining('SECTOR CONTENTS'), findsOneWidget,
        reason: 'stale beats blank');
  });

  testWidgets('a disposed tab stops reading the universe', (tester) async {
    await pumpView(tester);

    // Replace the tree so the SectorView's State is disposed. Without an
    // explicit removeListener the notifier keeps a live reference to a dead
    // State, and because the refresh checks `mounted` nothing *throws* — it just
    // performs an async disk read on every write from then on, once per tab
    // switch, growing for the rest of the session.
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await _settle(tester);

    // Bump the revision **directly** rather than writing. A real
    // `saveSectors` reads the universe itself to merge, so a write-based
    // baseline conflates the writer's own reads with the listener's and the
    // assertion then passes or fails for reasons that have nothing to do with
    // the listener. A bare signal is the only input that isolates it.
    final readsBefore = storage.reads;
    storage.revision.value++;
    await _settle(tester);

    expect(storage.reads, readsBefore,
        reason: 'a disposed SectorView must not answer a refresh signal');
  });

  testWidgets('a live tab does answer it', (tester) async {
    // The other half. Without this the test above would also pass if the
    // listener were never attached at all, which is a different bug with the
    // same silence.
    await pumpView(tester);

    final readsBefore = storage.reads;
    storage.revision.value++;
    await _settle(tester);

    expect(storage.reads, greaterThan(readsBefore),
        reason: 'the refresh is wired up, not merely harmless');
  });

  group('the write signal survives a patched file seam', () {
    test('saveSectors announces even when saveUniverse is overridden',
        () async {
      final storage = _SaveUniverseOnly([_sector()]);
      UniverseStorage.instanceForTest = storage;
      addTearDown(() => UniverseStorage.instanceForTest = null);

      final before = storage.revision.value;
      final ok = await storage.saveSectors([_sector()]);

      expect(ok, isTrue);
      expect(storage.saveUniverseCalls, greaterThan(0),
          reason: 'the real saveSectors must have reached the patched seam, or '
              'this proves nothing about the bump');
      expect(storage.revision.value, isNot(before),
          reason: 'a screen subscribed to `revision` would never learn of this '
              'write, so a cross-screen refresh would go quiet without failing '
              '\u2014 which is the failure the bump in saveSectors exists for');
    });
  });
}
