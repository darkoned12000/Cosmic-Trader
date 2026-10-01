/// Shared test doubles for the file-backed storage singletons.
///
/// These existed as **22 private copies across 22 test files**, under six
/// different names, and they did not all behave the same. That is the part that
/// cost a bug: one copy returned a single shared `List<Sector>` and made
/// `saveSectors` a no-op, so a screen's mutation and the tick's mutation were
/// always the *same objects* — which made "the screen forgot to save" a state
/// that could not be observed. The guard passed while the feature was broken.
///
/// So the faithful implementation is the default here, and the cheap one has to
/// be asked for by name. **A fake must reproduce the mechanism under test, not
/// just satisfy the calls.**
library;

import 'dart:convert';

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';

/// A universe that **round-trips through JSON on every load**, like the real one.
///
/// This is the correct default. The real `UniverseStorage.loadUniverse()`
/// re-parses the file into a fresh object graph on every call, so two readers —
/// a screen and the tick — hold *different* `Planet` instances and only the file
/// is shared. A fake that hands back one shared list cannot reproduce that, and
/// a test using it is testing a program the game does not run.
class FaithfulUniverse extends UniverseStorage {
  FaithfulUniverse(List<Sector> initial) : _blob = encode(initial);

  String _blob;

  /// Successful writes that reached the blob, so a test can assert a save
  /// happened rather than inferring it from what the screen shows.
  int writes = 0;

  /// Reads, so a test can assert a screen does **not** re-read on every write —
  /// the shape a leaked listener takes: no exception, no visible failure, just a
  /// dead `State` performing a disk read per write for the rest of the session.
  int reads = 0;

  /// When true, [loadUniverse] throws, standing in for a corrupt or unreadable
  /// file. The real storage quarantines and returns empty rather than throwing,
  /// so this models the *caller's* resilience, not the storage's.
  bool blobThrows = false;

  static String encode(List<Sector> sectors) =>
      jsonEncode(sectors.map((e) => e.toJson()).toList(growable: false));

  List<Sector> decode() {
    if (blobThrows) throw StateError('universe blob is unreadable');
    return (jsonDecode(_blob) as List)
        .cast<Map<String, dynamic>>()
        .map(Sector.fromJson)
        .toList();
  }

  /// The current universe as a fresh object graph.
  List<Sector> snapshot() => decode();

  /// Announces a completed write the way the real storage does.
  ///
  /// **The copies this replaces all forgot this**, because every one of them
  /// replaced `saveSectors`/`saveUniverse` outright and so bypassed the real
  /// `_markWritten()`. `revision` is the signal `SectorView` subscribes to, so a
  /// fake that skips it makes cross-screen freshness untestable — and one test
  /// did fail on exactly that when these were consolidated. A fake that omits a
  /// side effect its subject performs is testing a different program.
  void _announce() {
    if (revision.value == 0x3fffffff) revision.value = 0;
    revision.value = revision.value + 1;
  }

  /// Simulates `GameTickService` finishing a pass: it writes back the snapshot
  /// it loaded **before** someone else's write landed. Used by the concurrent
  /// write tests; harmless otherwise.
  void writeBackSnapshot(List<Sector> snapshot) {
    _blob = encode(snapshot);
    writes++;
    _announce();
  }

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async {
    reads++;
    return decode();
  }

  /// Merges by sector id, exactly as the real one does — including the refusal
  /// paths, so a caller that ignores the `bool` fails the same way it would in
  /// the app.
  @override
  Future<bool> saveSectors(List<Sector> updated) async {
    final existing = await loadUniverse();
    if (existing.isEmpty) return false;
    for (final u in updated) {
      final i = existing.indexWhere((s) => s.id == u.id);
      if (i < 0) return false;
      existing[i] = u;
    }
    _blob = encode(existing);
    writes++;
    _announce();
    return true;
  }

  @override
  Future<void> saveUniverse(List<Sector> sectors) async {
    _blob = encode(sectors);
    writes++;
    _announce();
  }

  @override
  void logSectorStats(List<Sector> _) {}
}

/// **One file still carries the unfaithful fake: `test/planet_colony_ui_test.dart`.**
///
/// Its `_FakeUniverse` hands back the caller's own `List<Sector>`, so the test
/// mutates a `Planet` directly and the screen sees it because they are the same
/// object. Swapping it for [FaithfulUniverse] breaks **13 of that file's 36
/// tests** — measured, not estimated — because those tests rely on the sharing
/// to observe their subject at all. Fixing it means changing the fixture pattern
/// (mutate, save, then read back) rather than the class, which is a task of its
/// own. Left in place deliberately so the migration did not quietly weaken a
/// third of a file's coverage on the way to a commit.
///
/// A read-only universe, for screens that only ever load.
///
/// Deliberately **not** the default: it silently accepts writes that the real
/// storage would perform, so a screen test that needs to observe persistence
/// wants [FaithfulUniverse].
class ReadOnlyUniverse extends UniverseStorage {
  ReadOnlyUniverse(this.sectors);

  final List<Sector> sectors;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async => sectors;

  @override
  void logSectorStats(List<Sector> _) {}
}

/// A universe whose writes never land.
///
/// Reproduces the real storage's silent failure modes — it refuses to merge
/// after a failed load, and drops a sector it cannot find — so a test can assert
/// that a screen does not lose the player's change when the save fails.
class FailingUniverse extends UniverseStorage {
  FailingUniverse(List<Sector> initial)
      : _blob = FaithfulUniverse.encode(initial);

  final String _blob;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async => (jsonDecode(_blob) as List)
      .cast<Map<String, dynamic>>()
      .map(Sector.fromJson)
      .toList();

  @override
  Future<bool> saveSectors(List<Sector> sectors) async => false;

  @override
  Future<void> saveUniverse(List<Sector> sectors) async {}

  @override
  void logSectorStats(List<Sector> _) {}
}

/// An NPC roster that never touches the filesystem.
class FakeNpcStorage extends NpcStorage {
  FakeNpcStorage(this.npcs) : super.forTesting();

  final List<NpcShip> npcs;

  @override
  Future<List<NpcShip>> loadAll() async => npcs;

  @override
  Future<void> saveAll(List<NpcShip> _) async {}
}

/// A player roster that never touches the filesystem.
class FakePlayerStorage extends PlayerStorage {
  FakePlayerStorage(this.players) : super.forTesting();

  final List<Player> players;

  @override
  Future<List<Player>> loadPlayers() async => players;
}
