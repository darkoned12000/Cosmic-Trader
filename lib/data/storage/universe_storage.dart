import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';

/// Handles reading/writing universe.json to persistent storage.
class UniverseStorage {
  UniverseStorage._();

  static UniverseStorage? _instance;
  static UniverseStorage get instance => _instance ??= UniverseStorage._();

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

  /// Load the full universe from disk.
  Future<List<Sector>> loadUniverse() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      return list
          .map((e) => Sector.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading universe: $e');
      return [];
    }
  }

  /// Save the full universe to disk.
  Future<void> saveUniverse(List<Sector> sectors) async {
    try {
      final path = await _filePath;
      final file = File(path);
      final content = jsonEncode(sectors.map((s) => s.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Error saving universe: $e');
    }
  }

  /// Check if a universe has been generated.
  Future<bool> hasUniverse() async {
    try {
      final path = await _filePath;
      return await File(path).exists();
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

  /// Generate a new universe if one doesn't already exist.
  ///
  /// Uses saved settings if available, otherwise defaults.
  Future<void> ensureUniverse() async {
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
    final generator = UniverseGenerator(actualSettings);
    final sectors = generator.generate();
    await saveUniverse(sectors);
    logSectorStats(sectors);
    debugPrint('Universe generated: ${sectors.length} sectors saved.');
    return actualSettings;
  }

  /// Save a subset of sectors by patching them into the existing file.
  /// Loads the full file, merges [updatedSectors] by ID, and writes back.
  /// More efficient than a full save when only a few sectors changed.
  Future<void> saveSectors(List<Sector> updatedSectors) async {
    try {
      final existing = await loadUniverse();
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
