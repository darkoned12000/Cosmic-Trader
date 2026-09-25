import 'package:flutter/foundation.dart';

/// Categories for the dev automation console (Settings → Automation).
enum GameEventCategory {
  combat,
  trade,
  movement,
  energy,
  banking,
  goal,
  system,
}

/// One timestamped entry in the automation event log.
class GameEventEntry {
  final DateTime timestamp;
  final GameEventCategory category;
  final String message;

  const GameEventEntry({
    required this.timestamp,
    required this.category,
    required this.message,
  });
}

/// Central ring buffer for every NPC/game action (F1).
///
/// Replaces bare `debugPrint` at AI/tick call sites: each method stores a
/// timestamped, categorized entry (newest first, capped) *and* mirrors the
/// message to `debugPrint` so console `grep` keeps working (the `NPC_ENERGY`
/// prefix format is preserved verbatim). The Automation console widget
/// listens to this singleton for searchable, filterable live history.
/// Player-facing messaging is unchanged — `ActionLogProvider` still owns
/// the in-game Sector View log.
class GameEventLog extends ChangeNotifier {
  static GameEventLog get global => _instance ??= GameEventLog._();
  static GameEventLog? _instance;

  GameEventLog._();

  /// Ring capacity — large enough for bug-hunting at high sector counts.
  static const int maxEntries = 2000;

  final List<GameEventEntry> _entries = [];

  /// Monotonic per-category totals. Unlike the ring buffer these are never
  /// evicted — the answer to "has anything traded/fought/banked *at all*?"
  /// even when high-frequency movement lines churn the visible window.
  final Map<GameEventCategory, int> _counts = {
    for (final c in GameEventCategory.values) c: 0,
  };

  List<GameEventEntry> get entries => List.unmodifiable(_entries);

  int get length => _entries.length;

  int count(GameEventCategory category) => _counts[category] ?? 0;

  Map<GameEventCategory, int> get counts => Map.unmodifiable(_counts);

  void log(String message, GameEventCategory category) {
    _entries.insert(
      0,
      GameEventEntry(
        timestamp: DateTime.now(),
        category: category,
        message: message,
      ),
    );
    _counts[category] = ((_counts[category] ?? 0) + 1);
    if (_entries.length > maxEntries) {
      _entries.removeLast();
    }
    debugPrint(message);
    notifyListeners();
  }

  /// Case-insensitive substring search over messages, optionally restricted
  /// to [categories]. Empty [query] matches everything.
  List<GameEventEntry> query({
    String query = '',
    Set<GameEventCategory>? categories,
  }) {
    final needle = query.trim().toLowerCase();
    return _entries.where((e) {
      if (categories != null && !categories.contains(e.category)) {
        return false;
      }
      if (needle.isEmpty) return true;
      return e.message.toLowerCase().contains(needle);
    }).toList();
  }

  void clear() {
    // Entries go; all-time counts stay — they are the answer to
    // "did anything happen at all?" across buffer churn.
    _entries.clear();
    notifyListeners();
  }

  @visibleForTesting
  static void resetForTest() {
    _instance?.dispose();
    _instance = null;
  }

  @override
  void dispose() {
    _instance = null;
    super.dispose();
  }

  // Convenience mirrors — one per category, same single-string shape as
  // the debugPrint calls they replace.
  void combat(String message) => log(message, GameEventCategory.combat);
  void trade(String message) => log(message, GameEventCategory.trade);
  void movement(String message) => log(message, GameEventCategory.movement);
  void energy(String message) => log(message, GameEventCategory.energy);
  void banking(String message) => log(message, GameEventCategory.banking);
  void goal(String message) => log(message, GameEventCategory.goal);
  void system(String message) => log(message, GameEventCategory.system);
}
