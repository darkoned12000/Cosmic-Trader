// lib/data/storage/player_exploration_storage.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'file_safe.dart';

/// Persists which sectors each player has visited across sessions, along
/// with a last-visited timestamp for each one.
///
/// Per-player isolation (storage review H2): the old single global map
/// let two accounts share and overwrite each other's visited sets
/// despite the name, docs, and AGENTS.md all claiming per-player.
/// Schema v2 nests maps by player id; legacy flat files migrate to
/// whichever player logs in first.
class PlayerExplorationStorage {
  PlayerExplorationStorage._();
  static final PlayerExplorationStorage instance = PlayerExplorationStorage._();

  // playerId -> sectorId -> last-visited time (UTC millisecondsSinceEpoch).
  Map<String, Map<int, int>> _byPlayer = {};

  /// Flat legacy payload awaiting adoption by the first player to log
  /// in after migration (single-account reality: always correct).
  Map<int, int>? _legacyFlat;
  bool _loaded = false;

  /// Currently scoped player. Empty means "unscoped" (tests, early
  /// startup): reads/writes hit a throwaway bucket, never the file's
  /// player maps and never each other's.
  String _activePlayerId = '';

  /// Scope all subsequent reads/writes to [playerId], adopting any
  /// legacy flat payload on first call.
  void setActivePlayer(String playerId) {
    _activePlayerId = playerId;
    if (_legacyFlat != null && !_byPlayer.containsKey(playerId)) {
      _byPlayer[playerId] = Map<int, int>.from(_legacyFlat!);
      _legacyFlat = null;
      _persist();
    }
  }

  Map<int, int> get _active => _byPlayer.putIfAbsent(_activePlayerId, () => {});

  /// Returns an unmodifiable view of the active player's visited sector
  /// ids. Call [load] first.
  Set<int> get visited => Set.unmodifiable(_active.keys);

  /// The last time [sectorId] was visited, or null if never visited.
  DateTime? lastVisitedAt(int sectorId) {
    final ms = _active[sectorId];
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
        if (data['players'] is Map) {
          // Current format: {"players": {"<id>": {"lastVisited": {...}}}}.
          final players = (data['players'] as Map).cast<String, dynamic>();
          _byPlayer = {};
          for (final entry in players.entries) {
            final inner = (entry.value as Map?)?.cast<String, dynamic>() ?? {};
            final raw =
                (inner['lastVisited'] as Map?)?.cast<String, dynamic>() ?? {};
            _byPlayer[entry.key] = raw.map(
              (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
            );
          }
        } else if (data['lastVisited'] is Map) {
          // Legacy flat format: adopt on first setActivePlayer.
          final raw = (data['lastVisited'] as Map).cast<String, dynamic>();
          _legacyFlat = raw.map(
            (key, value) => MapEntry(int.parse(key), (value as num).toInt()),
          );
        } else if (data['visited'] is List) {
          // Older legacy: {"visited": [1, 2, 3]}. Migrate ids over;
          // exact times are unknown, so stamp "now".
          final legacyIds = (data['visited'] as List).cast<int>();
          final now = DateTime.now().toUtc().millisecondsSinceEpoch;
          _legacyFlat = {for (final id in legacyIds) id: now};
        }
      }
      _loaded = true;
    } catch (e) {
      // Never lock in failure (storage review H3): the old code set
      // _loaded = true in the failure path, so the store never retried
      // and the next markVisited clobbered the good file with emptiness.
      debugPrint('Exploration load failed, will retry: $e');
    }
  }

  /// Mark a sector visited (or revisited), stamping it with the current
  /// time. Ensures a load first so a racing call can't persist a
  /// partial map over the good file (storage review H3).
  Future<void> markVisited(int sectorId) async {
    await load();
    _active[sectorId] = DateTime.now().toUtc().millisecondsSinceEpoch;
    await _persist();
  }

  /// Mark multiple sectors visited/revisited in one write, all stamped
  /// with the same timestamp.
  Future<void> markVisitedBatch(Set<int> sectorIds) async {
    if (sectorIds.isEmpty) return;
    await load();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    for (final id in sectorIds) {
      _active[id] = now;
    }
    await _persist();
  }

  /// Clear exploration data for one player (or everything when
  /// [playerId] is null, e.g. universe regen).
  Future<void> reset({String? playerId}) async {
    final target = playerId ?? _activePlayerId;
    if (playerId == null && target.isEmpty) {
      _byPlayer.clear();
      _legacyFlat = null;
    } else {
      _byPlayer.remove(target);
    }
    await _persist();
  }

  /// Test seam: clear all in-memory state (file untouched).
  @visibleForTesting
  static void resetForTest() {
    instance._byPlayer.clear();
    instance._legacyFlat = null;
    instance._loaded = false;
    instance._activePlayerId = '';
  }

  // The 'player_exploration.json' file should be located in the following directories:
  // Windows: C:\Users\<You>\AppData\Roaming\com.cosmictrader.app\
  // Mac: ~/Library/Application Support/com.cosmictrader.app/
  // Linux: ~/.local/share/com.cosmictrader.app/
  Future<void> _persist() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/player_exploration.json');
      await FileSafe.writeString(
          file,
          json.encode({
            'players': _byPlayer.map((pid, visited) => MapEntry(pid, {
                  'lastVisited': visited
                      .map((key, value) => MapEntry(key.toString(), value)),
                })),
          }));
    } catch (e) {
      debugPrint('Exploration save failed: $e');
    }
  }
}
