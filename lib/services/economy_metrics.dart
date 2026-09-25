import 'package:flutter/foundation.dart';

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

    final f = perFaction.putIfAbsent(actorFaction, FactionTradeStats.new);
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
    perFaction.putIfAbsent(actorFaction, FactionTradeStats.new).lootCredits +=
        credits;
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
}
