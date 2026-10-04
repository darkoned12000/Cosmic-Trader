import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_exploration_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/combat_metrics.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'file_safe.dart';

/// Handles reading/writing universe.json to persistent storage.
class UniverseStorage {
  UniverseStorage();

  static UniverseStorage? _instance;
  static UniverseStorage get instance => _instance ??= UniverseStorage();

  /// Test-only override for the singleton (e.g. to inject a fake that
  /// returns a synthetic universe without touching the filesystem).
  /// Pass `null` to restore the default on-demand instance.
  @visibleForTesting
  static set instanceForTest(UniverseStorage? storage) => _instance = storage;

  String? _cachedPath;

  /// Points this storage at [dir] instead of the platform documents directory.
  ///
  /// Test-only, and deliberately a real directory rather than a fake: the whole
  /// point of the guards in `test/support/storage_fakes.dart` is that a double
  /// which reimplements the mechanism under test vouches only for itself. The
  /// caching, adopting and write-failure paths in this file can be exercised for
  /// real against a temp directory, and should be — they are the load-bearing
  /// part of the session now.
  @visibleForTesting
  set testDirectory(String? dir) =>
      _cachedPath = dir == null ? null : '$dir/universe.json';

  Future<String> _getBasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> get _filePath async {
    if (_cachedPath != null) return _cachedPath!;
    final basePath = await _getBasePath();
    _cachedPath = '$basePath/universe.json';
    return _cachedPath!;
  }

  /// True when the last load hit a corrupt/unreadable file (storage
  /// review C1). Patch paths ([saveSectors]) refuse to write while set:
  /// merging into a failed read would persist the emptiness over good
  /// data. Cleared by every successful or absent load.
  bool _lastLoadFailed = false;

  /// **The one universe object graph**, owned here for the process lifetime.
  ///
  /// Every reader used to call [loadUniverse] and get a *fresh* parse, so two
  /// holders of "the same" sector were mutating different `Planet` objects and
  /// only disk was shared. That isolation is the root of the most serious class
  /// of bug this project has: a writer holding a snapshot taken before someone
  /// else's change could overwrite that change with no error anywhere, because
  /// "stale" was a thing the system could express.
  ///
  /// With one graph there is no window. A tick pass and a screen are mutating the
  /// same `Planet`, so a stale write-back is not merely unlikely, it is
  /// unrepresentable — there is no second copy to have been stale.
  ///
  /// It is also the largest single performance win available in this codebase.
  /// [saveUniverse] encodes the *entire* file on every write, and the planet
  /// screen re-parsed the whole universe once a second; caching removes both.
  ///
  /// The cost is memory (the whole graph resident, which matters only at very
  /// large universe sizes) and, more importantly, **write isolation**. A screen
  /// previously could not corrupt the tick's state at all. That safety net is
  /// replaced by ordering discipline — no screen may mutate a world in the middle
  /// of a tick pass — which is a rule in a comment rather than a structure in a
  /// type, and worth knowing is the weaker of the two.
  List<Sector>? _graph;

  /// The shared graph, or null before the first successful load. Not a
  /// lazily-created empty list: "not loaded" and "loaded and empty" are
  /// different states, and conflating them lets a failed first read look like a
  /// universe.
  List<Sector>? get sharedUniverse => _graph;

  /// Discard the cache and re-parse from disk on the next [loadUniverse].
  ///
  /// Nothing in the game needs this — the whole point is that there is one graph
  /// for the session. It exists for tests that swap the file underneath the
  /// storage, and as the seam a future multiplayer authority would reload from.
  @visibleForTesting
  void invalidateCache() => _graph = null;

  /// Bumped once per **successful write**, so a screen holding the universe in
  /// memory can learn that someone else changed it and repaint.
  ///
  /// This used to be the whole cross-screen freshness mechanism, and its own
  /// comment admitted it bought "freshness, not shared identity" — two callers
  /// could still hold different `Planet` objects. Now that [sharedUniverse] is
  /// the single graph, this no longer carries correctness; it carries
  /// *notification*. Nothing re-reads to obtain the change, because there is
  /// nothing stale to obtain: the screen is already looking at it.
  ///
  /// Only successful writes bump it. A refused or failed write leaves the file
  /// as it was, and telling readers to re-read would be a lie they cannot
  /// check. Both write paths raise it — [saveUniverse] for direct callers, and
  /// [saveSectors] as well — so a patched write is still announced by a test
  /// double that replaces [saveUniverse].
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  /// Announces a completed write. Separate from the notifier so the bump is
  /// impossible to forget at a new call site: add a write, get a refresh.
  void _markWritten() {
    if (revision.value == 0x3fffffff) revision.value = 0;
    revision.value = revision.value + 1;
  }

  /// Clears a sticky load failure: generation authors brand-new truth.
  /// Called by [generateWithSettings].
  void clearLoadFailure() {
    _lastLoadFailed = false;
  }

  /// The universe: **the shared graph**, loaded from disk on first call only.
  ///
  /// Callers mutate the returned list and its `Planet`s directly. That is
  /// intended — it is what makes the tick and a screen the same writer — and it
  /// means a caller that wants a private copy must make one itself, because this
  /// no longer provides isolation.
  ///
  /// Corrupt files are quarantined aside (recoverable) with a loud log instead
  /// of silently becoming an empty universe that later writes would cement. A
  /// **failed load deliberately does not populate the cache**: the empty list
  /// handed back is not truth, and caching it would make a corrupt file look
  /// like an empty universe for the rest of the session. The next call retries
  /// the read, so a transient failure self-heals and a subsequent successful
  /// load or generation re-establishes the graph.
  Future<List<Sector>> loadUniverse() async {
    final cached = _graph;
    if (cached != null) return cached;
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) {
        _lastLoadFailed = false;
        return [];
      }
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      final sectors =
          list.map((e) => Sector.fromJson(e as Map<String, dynamic>)).toList();
      _lastLoadFailed = false;
      _graph = sectors;
      return sectors;
    } catch (e) {
      debugPrint('Error loading universe: $e');
      GameEventLog.global.system(
          '[UniverseStorage] Load failed — quarantining universe.json: $e');
      try {
        await FileSafe.quarantine(File(await _filePath));
      } catch (_) {}
      _lastLoadFailed = true;
      return [];
    }
  }

  /// Save the universe, and make [sectors] the shared graph.
  ///
  /// Adopting the argument is what lets a fresh list — the generator's, a test
  /// fixture's — become the session's truth, which is why [generateWithSettings]
  /// needs no separate wiring. Adopting is a no-op in the normal case, where the
  /// caller is saving the graph it was handed by [loadUniverse].
  Future<void> saveUniverse(List<Sector> sectors) async {
    // Adopt **before** the write is attempted, so a write that fails still
    // leaves the graph as the live truth. The in-memory universe is the
    // simulation; the file is its durability. A failed write costs you a
    // session's worth of progress on restart, not the running game.
    if (!identical(_graph, sectors)) _graph = sectors;
    try {
      final path = await _filePath;
      final file = File(path);
      final content = jsonEncode(sectors.map((s) => s.toJson()).toList());
      await FileSafe.writeString(file, content);
      // Only after the write resolves — a failed write leaves the file as it
      // was, and a refresh signal would send readers looking for a change that
      // does not exist.
      _markWritten();
    } catch (e) {
      debugPrint('Error saving universe: $e');
    }
  }

  /// Check if a usable universe has been generated: the file must
  /// exist AND parse to a non-empty sector list (storage review H5 —
  /// an empty `[]` file used to count as "generated" forever).
  Future<bool> hasUniverse() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return false;
      final content = (await file.readAsString()).trim();
      if (content.isEmpty || content == '[]') return false;
      final list = jsonDecode(content) as List;
      return list.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Delete the universe (useful for regeneration).
  Future<void> deleteUniverse() async {
    // Drop the graph too. Leaving it cached would be the worst of both worlds:
    // the file is gone, so a load returns empty, but every existing holder still
    // points at the old graph and keeps mutating a universe that no longer
    // exists — and the next write would resurrect it from memory.
    _graph = null;
    try {
      final path = await _filePath;
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('Error deleting universe: $e');
    }
  }

  /// In-flight generation shared across overlapping callers (storage
  /// review C2): main, shell, sector and galaxy views can all fire
  /// within one startup. Without this, two runs both observe
  /// hasUniverse() == false and generate different universes (seed 0
  /// mints per run), pairing one run's sectors with another's NPCs.
  static Future<void>? _inflightEnsure;

  /// Generate a new universe if one doesn't already exist.
  ///
  /// Uses saved settings if available, otherwise defaults.
  Future<void> ensureUniverse() async {
    final running = _inflightEnsure;
    if (running != null) {
      await running;
      return;
    }
    final fut = _ensureUniverseInner();
    _inflightEnsure = fut;
    try {
      await fut;
    } finally {
      _inflightEnsure = null;
    }
  }

  Future<void> _ensureUniverseInner() async {
    if (await hasUniverse()) return;
    final savedSettings = await SettingsStorage.instance.load();
    final settings = savedSettings ?? GameSettings.defaults();
    final usedSettings = await generateWithSettings(settings);
    await SettingsStorage.instance.save(usedSettings);
  }

  /// Delete existing universe and generate a new one with [settings].
  ///
  /// Returns the [GameSettings] actually used (with the real seed if 0 was
  /// entered, so the caller can display it).
  Future<GameSettings> generateWithSettings(GameSettings settings) async {
    // If seed was 0 (random), pick a concrete seed now so it's reproducible
    // and displayable.
    final actualSeed = settings.seed == 0
        ? DateTime.now().millisecondsSinceEpoch
        : settings.seed;
    // When seed was 0 (random), replace rawSeed with the actual seed so the
    // user sees it; otherwise keep the original text ("haga01", etc.).
    final rawSeed =
        settings.seed == 0 ? actualSeed.toString() : settings.rawSeed;
    final actualSettings =
        settings.copyWith(seed: actualSeed, rawSeed: rawSeed);

    debugPrint('Generating new universe with settings… (seed: $actualSeed)');
    // Brand-new truth: clear any sticky load failures first, or the
    // guards below would refuse to persist the fresh world after an
    // old corruption (storage review C1 lifecycle bug, caught live).
    UniverseStorage.instance.clearLoadFailure();
    NpcStorage().clearLoadFailure();
    PlayerStorage.instance.clearLoadFailure();
    final generator = UniverseGenerator(actualSettings);
    final sectors = generator.generate();
    await saveUniverse(sectors);
    // NPC persistence is awaited HERE (not fire-and-forget inside the
    // generator) so post-generation ticks can never load a partial roster.
    await NpcStorage().saveAll(generator.generatedNpcs);
    // Fresh world, fresh board + combat slate (soak-found bug): bounties
    // reference dead-universe NPC ids and never pay out against them.
    await BountyBoard.global.resetForNewUniverse();
    CombatMetrics.global.reset();
    // Fresh world, fresh ledgers (storage review H4): the economy
    // report and the visited map belong to the old universe.
    EconomyMetrics.global.reset();
    await PlayerExplorationStorage.instance.reset();
    logSectorStats(sectors);
    debugPrint('Universe generated: ${sectors.length} sectors saved.');
    return actualSettings;
  }

  /// Save a subset of sectors by patching them into the shared graph.
  ///
  /// Merges [updatedSectors] into the graph by id, then writes the graph back.
  /// When the caller is holding the graph's own sectors — the normal case, now
  /// that [loadUniverse] hands out the shared list — every merge is a
  /// self-assignment and this is simply "write the file".
  ///
  /// It still *merges* rather than assuming that, because "patch these foreign
  /// copies into the universe" is a reasonable thing for a caller to mean, and
  /// silently ignoring it would write an unrelated universe.
  ///
  /// Refuses when the preceding load failed or the graph is empty (storage
  /// review C1/H1): patching onto a failed read would cement the emptiness over
  /// the good file.
  Future<bool> saveSectors(List<Sector> updatedSectors) async {
    try {
      final existing = await loadUniverse();
      if (_lastLoadFailed || existing.isEmpty) {
        final reason = _lastLoadFailed ? 'failed load' : 'empty universe';
        debugPrint('[UniverseStorage] saveSectors refused ($reason) — '
            'not overwriting the file');
        GameEventLog.global
            .system('[UniverseStorage] saveSectors refused ($reason)');
        // No bump: nothing was written, and the merge it refused to perform is
        // exactly the case where a reader must keep believing what it has.
        return false;
      }
      for (final updated in updatedSectors) {
        final idx = existing.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) {
          existing[idx] = updated;
        } else {
          // **Never silent.** This used to be an `if` with no else, so a sector
          // whose id was not in the freshly-read file was dropped and the write
          // reported success — the caller had no way to know its change had not
          // landed. Reported as "credits deducted, nothing happened".
          debugPrint('[UniverseStorage] saveSectors: sector #${updated.id} is '
              'not in the stored universe — dropped');
          GameEventLog.global.system(
            '[UniverseStorage] saveSectors: sector #${updated.id} not found — '
            'change not written',
          );
          return false;
        }
      }
      await saveUniverse(existing);
      // Also bumped here, not only inside `saveUniverse`, because that is where
      // the signal logically belongs but it is also the seam test doubles
      // replace. A fake that overrides `saveUniverse` and inherits the real
      // `saveSectors` would otherwise silently stop announcing writes, and the
      // guard for "does a write reach other screens" would go quiet without
      // failing — a fake that disables the thing it is testing. Double-bumping
      // the patched path costs one extra re-read attempt, and readers coalesce.
      _markWritten();
      return true;
    } catch (e) {
      debugPrint('Error patching sectors in universe: $e');
      return false;
    }
  }

  /// Print sector connection histogram and content counts to the console.
  void logSectorStats(List<Sector> sectors) {
    final warpCounts = <int, int>{};
    int planets = 0;
    int ports = 0;
    int hardwareEmporiums = 0;

    for (final s in sectors) {
      final wc = s.warpRoutes.length;
      warpCounts[wc] = (warpCounts[wc] ?? 0) + 1;
      if (s.hasPlanet) planets++;
      if (s.hasPort) {
        ports++;
        if (s.port?.isHardwareEmporium == true) hardwareEmporiums++;
      }
    }

    debugPrint('Sector breakdown:');
    for (int i = 7; i >= 1; i--) {
      final count = warpCounts[i];
      if (count != null && count > 0) {
        debugPrint('  # sectors with $i connection(s): $count');
      }
    }
    debugPrint('  # sectors with planets: $planets');
    debugPrint('  # sectors with ports: $ports');
    debugPrint('  # Hardware Emporiums: $hardwareEmporiums');
  }
}
