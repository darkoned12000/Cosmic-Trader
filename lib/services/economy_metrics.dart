import 'package:flutter/foundation.dart';

import 'package:cosmic_trader/data/storage/economy_metrics_storage.dart';

/// Per-commodity trade totals for the B2 economy report.
class CommodityTradeStats {
  int buyUnits = 0;
  int buyCredits = 0;
  int sellUnits = 0;
  int sellCredits = 0;

  int get units => buyUnits + sellUnits;
  int get credits => buyCredits + sellCredits;

  double get avgUnitPrice => units <= 0 ? 0 : credits / units;
}

/// Per-faction trade totals (actor side: who bought/sold).
class FactionTradeStats {
  int buys = 0;
  int sells = 0;
  int buyCredits = 0;
  int sellCredits = 0;

  /// Combat/raid spoils taken (not trade volume).
  int lootCredits = 0;

  int get transactions => buys + sells;

  /// Positive when the faction earned more than it spent trading.
  /// Excludes loot — shown separately.
  int get net => sellCredits - buyCredits;

  /// All income: trade surplus plus spoils.
  int get totalEarned => net + lootCredits;
}

/// Session-scoped trade metrics backing the B2 economy report
/// (Computer → Economy Report).
///
/// Every player trade (1 unit per tap in `PortTradeView`) and every NPC
/// trade-route buy/sell records one entry. In-memory only, like
/// [GameEventLog]: restart the session to reset. Answers "is the economy
/// growing?" via volume, per-commodity average prices vs base, per-faction
/// flows, and player-vs-NPC split.
class EconomyMetrics extends ChangeNotifier {
  static EconomyMetrics get global => _instance ??= EconomyMetrics._();
  static EconomyMetrics? _instance;

  EconomyMetrics._() : sessionStart = DateTime.now();

  DateTime sessionStart;

  int tradeCount = 0;
  int totalUnits = 0;
  int totalCredits = 0;
  int playerTrades = 0;
  int npcTrades = 0;

  /// Combat/raid spoils taken across all factions (not trade volume).
  int totalLoot = 0;

  final Map<String, CommodityTradeStats> perCommodity = {};
  final Map<String, FactionTradeStats> perFaction = {};

  void recordTrade({
    required String commodity,
    required int units,
    required int credits,
    required String actorFaction,
    required bool isPlayer,
    required bool isBuy,
  }) {
    if (units <= 0) return;
    // Actor-side truth: callers pass what the trader actually paid or
    // received (net of owner fees), so net/gross reconcile with wallets.
    // Faction keys normalize to lowercase enum names.
    final faction = actorFaction.toLowerCase();
    tradeCount++;
    totalUnits += units;
    totalCredits += credits;
    if (isPlayer) {
      playerTrades++;
    } else {
      npcTrades++;
    }

    final c = perCommodity.putIfAbsent(commodity, CommodityTradeStats.new);
    if (isBuy) {
      c.buyUnits += units;
      c.buyCredits += credits;
    } else {
      c.sellUnits += units;
      c.sellCredits += credits;
    }

    final f = perFaction.putIfAbsent(faction, FactionTradeStats.new);
    if (isBuy) {
      f.buys++;
      f.buyCredits += credits;
    } else {
      f.sells++;
      f.sellCredits += credits;
    }
    notifyListeners();
  }

  /// Records combat/raid spoils (kill loot). Tracked separately from
  /// trade volume so fighter income doesn't masquerade as market flow.
  void recordLoot({
    required String actorFaction,
    required int credits,
    required bool isPlayer,
  }) {
    if (credits <= 0) return;
    totalLoot += credits;
    perFaction
        .putIfAbsent(actorFaction.toLowerCase(), FactionTradeStats.new)
        .lootCredits += credits;
    notifyListeners();
  }

  double get tradesPerMinute {
    final elapsed =
        DateTime.now().difference(sessionStart).inSeconds.clamp(1, 1 << 30);
    return tradeCount * 60.0 / elapsed;
  }

  double avgUnitPrice(String commodity) =>
      perCommodity[commodity]?.avgUnitPrice ?? 0;

  void reset() {
    tradeCount = 0;
    totalUnits = 0;
    totalCredits = 0;
    playerTrades = 0;
    npcTrades = 0;
    totalLoot = 0;
    perCommodity.clear();
    perFaction.clear();
    sessionStart = DateTime.now();
    EconomyMetricsStorage.instance.clear();
    notifyListeners();
  }

  /// Snapshot for persistence (exit) and restore (launch). On a server
  /// this same payload is the ongoing economy-health feed.
  Map<String, dynamic> toJson() => {
        'tradeCount': tradeCount,
        'totalUnits': totalUnits,
        'totalCredits': totalCredits,
        'playerTrades': playerTrades,
        'npcTrades': npcTrades,
        'totalLoot': totalLoot,
        'sessionStart': sessionStart.toIso8601String(),
        'perCommodity': perCommodity.map(
          (k, v) => MapEntry(k, {
            'buyUnits': v.buyUnits,
            'buyCredits': v.buyCredits,
            'sellUnits': v.sellUnits,
            'sellCredits': v.sellCredits,
          }),
        ),
        'perFaction': perFaction.map(
          (k, v) => MapEntry(k, {
            'buys': v.buys,
            'sells': v.sells,
            'buyCredits': v.buyCredits,
            'sellCredits': v.sellCredits,
            'lootCredits': v.lootCredits,
          }),
        ),
      };

  /// Restores a snapshot; call once at startup before any recording.
  Future<void> restore() async {
    final json = await EconomyMetricsStorage.instance.load();
    if (json == null) return;
    tradeCount = (json['tradeCount'] as num?)?.toInt() ?? 0;
    totalUnits = (json['totalUnits'] as num?)?.toInt() ?? 0;
    totalCredits = (json['totalCredits'] as num?)?.toInt() ?? 0;
    playerTrades = (json['playerTrades'] as num?)?.toInt() ?? 0;
    npcTrades = (json['npcTrades'] as num?)?.toInt() ?? 0;
    totalLoot = (json['totalLoot'] as num?)?.toInt() ?? 0;
    final start = json['sessionStart'] as String?;
    sessionStart = start != null ? DateTime.parse(start) : DateTime.now();
    perCommodity.clear();
    ((json['perCommodity'] as Map?) ?? {}).forEach((k, v) {
      final m = (v as Map).cast<String, dynamic>();
      final s = CommodityTradeStats()
        ..buyUnits = (m['buyUnits'] as num?)?.toInt() ?? 0
        ..buyCredits = (m['buyCredits'] as num?)?.toInt() ?? 0
        ..sellUnits = (m['sellUnits'] as num?)?.toInt() ?? 0
        ..sellCredits = (m['sellCredits'] as num?)?.toInt() ?? 0;
      perCommodity[k as String] = s;
    });
    perFaction.clear();
    ((json['perFaction'] as Map?) ?? {}).forEach((k, v) {
      final m = (v as Map).cast<String, dynamic>();
      final s = FactionTradeStats()
        ..buys = (m['buys'] as num?)?.toInt() ?? 0
        ..sells = (m['sells'] as num?)?.toInt() ?? 0
        ..buyCredits = (m['buyCredits'] as num?)?.toInt() ?? 0
        ..sellCredits = (m['sellCredits'] as num?)?.toInt() ?? 0
        ..lootCredits = (m['lootCredits'] as num?)?.toInt() ?? 0;
      perFaction[k as String] = s;
    });
    notifyListeners();
  }

  Future<void> persist() => EconomyMetricsStorage.instance.save(toJson());

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
}
