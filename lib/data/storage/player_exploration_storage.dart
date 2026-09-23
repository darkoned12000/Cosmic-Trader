// lib/data/storage/player_exploration_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists which sectors the player has visited across sessions, along
/// with a last-visited timestamp for each one.
///
/// Adapt the I/O layer (file, Hive, SharedPreferences, etc.) to match
/// your existing storage architecture — the public API stays the same.
class PlayerExplorationStorage {
  PlayerExplorationStorage._();
  static final PlayerExplorationStorage instance = PlayerExplorationStorage._();

  // sectorId -> last-visited time (UTC millisecondsSinceEpoch).
  Map<int, int> _lastVisited = {};
  bool _loaded = false;

  /// Returns an unmodifiable view of every visited sector id. Call [load] first.
  Set<int> get visited => Set.unmodifiable(_lastVisited.keys);

  /// The last time [sectorId] was visited, or null if never visited.
  DateTime? lastVisitedAt(int sectorId) {
    final ms = _lastVisited[sectorId];
    return ms == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      // NOTE: must match the directory used in _persist(), or saves from a
      // previous session will never be found on the next launch.
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/player_exploration.json');
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = json.decode(content) as Map<String, dynamic>;
        if (data['lastVisited'] is Map) {
          // Current format: {"lastVisited": {"12": 1719999999999, ...}}
          final raw = (data['lastVisited'] as Map).cast<String, dynamic>();
          _lastVisited = raw.map(
            (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
          );
        } else if (data['visited'] is List) {
          // Legacy format from before last-visited tracking existed:
          // {"visited": [1, 2, 3]}. Migrate ids over; exact times are
          // unknown, so stamp them with "now" rather than losing the data.
          final legacyIds = (data['visited'] as List).cast<int>();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          _lastVisited = {for (final id in legacyIds) id: now};
        }
      }
    } catch (e) {
      debugPrint('Exploration load failed, starting fresh: $e');
      _lastVisited = {};
    }
    _loaded = true;
  }

  /// Mark a sector visited (or revisited), stamping it with the current time.
  Future<void> markVisited(int sectorId) async {
    _lastVisited[sectorId] = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _persist();
  }

  /// Mark multiple sectors visited/revisited in one write, all stamped with
  /// the same timestamp.
  Future<void> markVisitedBatch(Set<int> sectorIds) async {
    if (sectorIds.isEmpty) return;
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final id in sectorIds) {
      _lastVisited[id] = now;
    }
    await _persist();
  }

  /// Clear all exploration data (new game / debug).
  Future<void> reset() async {
    _lastVisited = {};
    await _persist();
  }

  // The 'player_exploration.json' file should be located in the following directories:
  // Windows: C:\Users\<You>\AppData\Roaming\com.cosmictrader.app\
  // Mac: ~/Library/Application Support/com.cosmictrader.app/
  // Linux: ~/.local/share/com.cosmictrader.app/
  Future<void> _persist() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/player_exploration.json');
      await file.writeAsString(json.encode({
        'lastVisited':
            _lastVisited.map((key, value) => MapEntry(key.toString(), value)),
      }));
    } catch (e) {
      debugPrint('Exploration save failed: $e');
    }
  }
}
