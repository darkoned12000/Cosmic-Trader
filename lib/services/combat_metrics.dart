import 'package:flutter/foundation.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/services/npc_ai/combat_service.dart';

/// Per-faction combat totals (actor side: who attacked / broke off).
class FactionCombatStats {
  /// Engagements participated in (either side).
  int engagements = 0;

  /// Fights initiated as the attacker.
  int attacks = 0;

  /// Opponents destroyed.
  int kills = 0;

  /// Deaths suffered.
  int deaths = 0;

  /// Successful break-offs (either side).
  int retreats = 0;

  /// Failed break-off attempts.
  int escapesFailed = 0;

  /// Times this faction's ships surrendered and paid tribute.
  int surrenders = 0;

  /// Tribute credits paid for peace.
  int tributePaid = 0;
}

/// Session-scoped combat metrics backing the C5 soak review
/// (Settings → Automation → Combat report).
///
/// Every NPC-vs-NPC resolution records one entry at the single choke
/// point in `_executeAttackGoal`; every player-combat ending records at
/// its `CombatScreen` path. In-memory only, like [GameEventLog]:
/// restart the session (or Reset) to clear. Faction keys normalize to
/// lowercase enum names, matching [EconomyMetrics] — loot itself stays
/// there (per-faction spoils) and is composed into the summary here.
///
/// Answers "is combat behaving?" via outcomes per faction, average hull
/// remaining at retreat, failed escapes, player kills/escapes, and
/// population samples over time.
class CombatMetrics extends ChangeNotifier {
  static CombatMetrics get global => _instance ??= CombatMetrics._();
  static CombatMetrics? _instance;

  CombatMetrics._() : sessionStart = DateTime.now();

  DateTime sessionStart;

  /// NPC-vs-NPC resolutions recorded.
  int engagements = 0;

  final Map<String, FactionCombatStats> perFaction = {};

  /// Hull fractions (0–1) held by retreating ships, all sides.
  double retreatHullSum = 0;
  int retreatHullCount = 0;

  /// Player-combat endings.
  int playerKills = 0;
  int playerDeaths = 0;
  int playerFlees = 0;

  /// NPC break-offs and accepted surrenders vs the player.
  int npcRetreatsVsPlayer = 0;
  int parleysAccepted = 0;

  /// Timestamped living-count snapshots (capped).
  final List<PopulationSample> population = [];

  /// Max retained census samples (~2h at the default 30s tick).
  static const int maxPopulationSamples = 240;

  FactionCombatStats _faction(String name) =>
      perFaction.putIfAbsent(name.toLowerCase(), FactionCombatStats.new);

  /// Post-combat hull fraction, safe for zeroed hulls.
  static double fractionOf(int hull, int maxHull) =>
      maxHull <= 0 ? 0.0 : (hull / maxHull).clamp(0.0, 1.0);

  /// Records one NPC-vs-NPC resolution. Hull fractions are post-combat.
  void recordNpc({
    required String attackerFaction,
    required String defenderFaction,
    required CombatOutcome outcome,
    required double attackerHullFraction,
    required double defenderHullFraction,
    int tribute = 0,
  }) {
    engagements++;
    final atk = _faction(attackerFaction);
    final def = _faction(defenderFaction);
    atk.engagements++;
    def.engagements++;
    atk.attacks++;
    switch (outcome) {
      case CombatOutcome.attackerVictory:
        atk.kills++;
        def.deaths++;
      case CombatOutcome.defenderVictory:
        def.kills++;
        atk.deaths++;
      case CombatOutcome.attackerRetreat:
        atk.retreats++;
        retreatHullSum += attackerHullFraction;
        retreatHullCount++;
      case CombatOutcome.defenderRetreat:
        def.retreats++;
        retreatHullSum += defenderHullFraction;
        retreatHullCount++;
      case CombatOutcome.defenderSurrender:
        def.surrenders++;
        def.tributePaid += tribute;
      case CombatOutcome.parley:
      case CombatOutcome.ongoing:
        break;
    }
    notifyListeners();
  }

  /// A break-off attempt failed (caller: the escapee's faction).
  void recordFailedEscape(String faction) {
    _faction(faction).escapesFailed++;
    notifyListeners();
  }

  void recordPlayerKill() {
    playerKills++;
    notifyListeners();
  }

  void recordPlayerDeath() {
    playerDeaths++;
    notifyListeners();
  }

  void recordPlayerFlee() {
    playerFlees++;
    notifyListeners();
  }

  void recordNpcYield({required bool retreated, required bool parleyed}) {
    if (retreated) npcRetreatsVsPlayer++;
    if (parleyed) parleysAccepted++;
    notifyListeners();
  }

  /// Census sample for population-over-time. Oldest samples evict past
  /// [maxPopulationSamples].
  void samplePopulation(Map<FactionClass, int> counts) {
    population.add(PopulationSample(
      at: DateTime.now(),
      counts: {for (final e in counts.entries) e.key.name: e.value},
    ));
    while (population.length > maxPopulationSamples) {
      population.removeAt(0);
    }
    notifyListeners();
  }

  double get avgRetreatHull =>
      retreatHullCount <= 0 ? 0 : retreatHullSum / retreatHullCount;

  /// Multi-line session summary for the Automation report and clipboard
  /// (paste into AI review). Loot composes from [EconomyMetrics]-style
  /// per-faction spoils passed in by the caller (null skips the column).
  String summary({Map<String, int>? lootByFaction}) {
    final buf = StringBuffer();
    final elapsed = DateTime.now().difference(sessionStart);
    buf.writeln(
        'Combat session (${elapsed.inMinutes}m, $engagements NPC engagements):');
    buf.writeln('FACTION    atk  kills deaths retreats surr  escFail');
    final names = perFaction.keys.toList()..sort();
    for (final name in names) {
      final s = perFaction[name]!;
      final loot = lootByFaction?[name];
      buf.writeln(
          '${name.padRight(10)} ${s.attacks.toString().padLeft(4)} '
          '${s.kills.toString().padLeft(5)} ${s.deaths.toString().padLeft(6)} '
          '${s.retreats.toString().padLeft(7)} ${s.surrenders.toString().padLeft(4)} '
          '${s.escapesFailed.toString().padLeft(7)}'
          '${loot != null ? '  loot $loot' : ''}');
    }
    buf.writeln(
        'Retreat hull avg: ${(avgRetreatHull * 100).toStringAsFixed(0)}% '
        '(n=$retreatHullCount)');
    buf.writeln(
        'Player: kills $playerKills, deaths $playerDeaths, fled $playerFlees, '
        'NPC yields retreated $npcRetreatsVsPlayer parleyed $parleysAccepted');
    if (population.isNotEmpty) {
      final factions = population.first.counts.keys.toList()..sort();
      for (final f in factions) {
        var min = 1 << 30, max = 0;
        for (final s in population) {
          final v = s.counts[f] ?? 0;
          if (v < min) min = v;
          if (v > max) max = v;
        }
        final last = population.last.counts[f] ?? 0;
        buf.writeln(
            'Population $f: now $last (min $min, max $max, samples ${population.length})');
      }
    } else {
      buf.writeln('Population: no census samples yet');
    }
    return buf.toString();
  }

  void reset() {
    engagements = 0;
    perFaction.clear();
    retreatHullSum = 0;
    retreatHullCount = 0;
    playerKills = 0;
    playerDeaths = 0;
    playerFlees = 0;
    npcRetreatsVsPlayer = 0;
    parleysAccepted = 0;
    population.clear();
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

/// One census snapshot of living NPC counts per faction (lowercase names).
class PopulationSample {
  final DateTime at;
  final Map<String, int> counts;

  const PopulationSample({required this.at, required this.counts});
}
