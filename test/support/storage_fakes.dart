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

/// A universe that behaves like the real one: **one shared object graph**,
/// written through to a JSON blob on every save.
///
/// It used to round-trip through JSON on *every load*, because that is what
/// `UniverseStorage.loadUniverse()` did — and being stricter than production was
/// the point, because a fake that hands back one shared list cannot reproduce
/// isolation. Production no longer isolates: it caches one graph for the
/// session, so a screen and the tick mutate the same `Planet` and a stale
/// write-back is not merely unlikely but unrepresentable.
///
/// That inversion is worth stating, because it is the trap this class used to
/// fall into and now had to be un-trapped from. A fake *stricter* than
/// production is not safe either — it makes tests pass by demanding a guarantee
/// the game does not make, and it silently becomes the thing carrying the
/// behaviour under test. When the mechanism changes, the fake has to follow it,
/// or the tests start asserting against a program that no longer runs.
///
/// The blob is still real, because durability still is: it backs [snapshot] for
/// tests that genuinely want a deep copy, and it is what `writeBackSnapshot`
/// overwrites when a test needs to inject the stale write that can no longer
/// happen on its own.
class FaithfulUniverse extends UniverseStorage {
  FaithfulUniverse(List<Sector> initial) : _blob = encode(initial);

  String _blob;

  /// The one graph, exactly as the real storage holds one.
  List<Sector>? _graph;

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

  /// A genuine deep copy of the stored universe — the thing [loadUniverse] no
  /// longer hands out. Used where a test needs a snapshot it can mutate freely
  /// without disturbing the live graph.
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
  /// it loaded **before** someone else's write landed.
  ///
  /// This is now **fault injection, not simulation**. It cannot happen through
  /// the normal API — a tick loading and saving the graph holds the same objects
  /// a screen does, so there is no stale copy for it to write back. It overwrites
  /// the *file* only, and deliberately leaves `_graph` alone, so a test can prove
  /// the running game is untouched by a rollback of the durable state.
  void writeBackSnapshot(List<Sector> snapshot) {
    _blob = encode(snapshot);
    writes++;
    _announce();
  }

  @override
  List<Sector>? get sharedUniverse => _graph;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async {
    reads++;
    if (blobThrows) throw StateError('universe blob is unreadable');
    return _graph ??= decode();
  }

  /// Merges by sector id into the shared graph, exactly as the real one does —
  /// including the refusal paths, so a caller that ignores the `bool` fails the
  /// same way it would in the app.
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
    if (!identical(_graph, sectors)) _graph = sectors;
    _blob = encode(sectors);
    writes++;
    _announce();
  }

  @override
  void logSectorStats(List<Sector> _) {}
}

/// **One file still carries a private fake: `test/planet_colony_ui_test.dart`.**
///
/// Its `_FakeUniverse` hands back the caller's own `List<Sector>` *and* makes
/// `saveSectors` a no-op. Under the old architecture that made it unfaithful in
/// the dangerous direction — a screen's mutation and the tick's were always the
/// same objects, so "the screen forgot to save" was unobservable. Under the
/// shared graph it is faithful in the ways that matter (one graph, real writes
/// observed), so it no longer needs migrating for correctness. It is still worth
/// folding in eventually, because two fake styles is one more thing to keep in
/// step with the real thing.
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
///
/// Shares the graph like the real storage does. That is what makes it useful for
/// the durability question specifically: the change stays live in memory (the
/// simulation keeps running) while the file never catches up, which is exactly
/// the split the real `saveUniverse` now has.
class FailingUniverse extends UniverseStorage {
  FailingUniverse(List<Sector> initial)
      : _blob = FaithfulUniverse.encode(initial);

  final String _blob;

  /// The one graph, populated on first load. Adopting on save matters here: a
  /// write that never lands must still leave the running universe as truth, or
  /// the test would be asserting against a screen that lost state.
  List<Sector>? _graph;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async =>
      _graph ??= (jsonDecode(_blob) as List)
          .cast<Map<String, dynamic>>()
          .map(Sector.fromJson)
          .toList();

  @override
  Future<bool> saveSectors(List<Sector> sectors) async => false;

  @override
  Future<void> saveUniverse(List<Sector> sectors) async {
    if (!identical(_graph, sectors)) _graph = sectors;
  }

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
