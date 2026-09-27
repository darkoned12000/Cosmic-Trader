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

  /// Clears a sticky load failure: generation authors brand-new truth.
  /// Called by [generateWithSettings].
  void clearLoadFailure() {
    _lastLoadFailed = false;
  }

  /// Load the full universe from disk. Corrupt files are quarantined
  /// aside (recoverable) with a loud log instead of silently becoming
  /// an empty universe that later writes would cement.
  Future<List<Sector>> loadUniverse() async {
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

  /// Save the full universe to disk.
  Future<void> saveUniverse(List<Sector> sectors) async {
    try {
      final path = await _filePath;
      final file = File(path);
      final content = jsonEncode(sectors.map((s) => s.toJson()).toList());
      await FileSafe.writeString(file, content);
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

  /// Save a subset of sectors by patching them into the existing file.
  /// Loads the full file, merges [updatedSectors] by ID, and writes back.
  /// More efficient than a full save when only a few sectors changed.
  /// Refuses when the preceding load failed or the base is empty
  /// (storage review C1/H1): patching onto a failed read would cement
  /// the emptiness over the good file.
  Future<void> saveSectors(List<Sector> updatedSectors) async {
    try {
      final existing = await loadUniverse();
      if (_lastLoadFailed || existing.isEmpty) {
        final reason = _lastLoadFailed ? 'failed load' : 'empty universe';
        debugPrint('[UniverseStorage] saveSectors refused ($reason) — '
            'not overwriting the file');
        GameEventLog.global
            .system('[UniverseStorage] saveSectors refused ($reason)');
        return;
      }
      for (final updated in updatedSectors) {
        final idx = existing.indexWhere((s) => s.id == updated.id);
        if (idx >= 0) {
          existing[idx] = updated;
        }
      }
      await saveUniverse(existing);
    } catch (e) {
      debugPrint('Error patching sectors in universe: $e');
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
