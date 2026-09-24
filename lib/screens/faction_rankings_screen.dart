import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/core/faction_colors.dart' as fcol;
import 'package:cosmic_trader/widgets/shared/hud_pill.dart';

String _formatCredits(int credits) {
  if (credits >= 1000000000) {
    return '${(credits / 1000000000).toStringAsFixed(1)}B';
  }
  if (credits >= 1000000) return '${(credits / 1000000).toStringAsFixed(1)}M';
  if (credits >= 1000) return '${(credits / 1000).toStringAsFixed(1)}K';
  return credits.toString();
}

class FactionRankingsScreen extends StatefulWidget {
  const FactionRankingsScreen({super.key});

  @override
  State<FactionRankingsScreen> createState() => _FactionRankingsScreenState();
}

class _FactionRankingsScreenState extends State<FactionRankingsScreen> {
  List<Player> _players = [];
  List<Sector> _sectors = [];
  List<NpcShip> _npcs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final players = await PlayerStorage.instance.loadPlayers();
      final sectors = await UniverseStorage.instance.loadUniverse();
      final npcs = await NpcStorage().loadAll();
      if (!mounted) return;
      setState(() {
        _players = players;
        _sectors = sectors;
        _npcs = npcs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Map<FactionClass, FactionStats> _computeStats() {
    final stats = <FactionClass, FactionStats>{};
    final factionClasses = Faction.allFactions()
        .map((f) => f.factionClass)
        .toList()
      ..add(FactionClass.pirate);
    for (final fc in factionClasses) {
      stats[fc] = FactionStats(faction: fc);
    }

    for (final player in _players) {
      final fc = player.faction;
      final s = stats[fc]!;
      s.shipCount++;
      s.totalCredits += player.credits;
      s.totalBankCredits += player.bankBalance;
      s.ownedPortsCount += player.ownedPorts.length;

      final shipClass = player.shipClass;
      s.shipByClass[shipClass] = (s.shipByClass[shipClass] ?? 0) + 1;
    }

    for (final npc in _npcs) {
      final fc = npc.faction;
      final s = stats[fc];
      if (s == null) continue;
      s.shipCount++;
      s.totalCredits += npc.credits;
      s.totalBankCredits += npc.bankBalance;
      s.kills += npc.kills;
      s.deaths += npc.deaths;
      s.totalDamageDealt += npc.totalDamageDealt;
      s.totalDamageTaken += npc.totalDamageTaken;

      final shipClass = npc.shipDef.shipClass;
      s.shipByClass[shipClass] = (s.shipByClass[shipClass] ?? 0) + 1;
    }

    for (final sector in _sectors) {
      if (sector.port != null && sector.port!.isOwned) {
        final ownerName = sector.port!.owner!;
        final humanMatches = _players
            .where((p) => p.username.toLowerCase() == ownerName.toLowerCase());
        if (humanMatches.isNotEmpty) {
          final s = stats[humanMatches.first.faction];
          if (s != null) s.portsControlled++;
        } else {
          final npcMatches = _npcs.where(
              (n) => n.pilotName.toLowerCase() == ownerName.toLowerCase());
          if (npcMatches.isNotEmpty) {
            final s = stats[npcMatches.first.faction];
            if (s != null) s.portsControlled++;
          }
        }
      }
    }

    for (final s in stats.values) {
      s._computePowerScore();
    }
    return stats;
  }

  List<_TopEntity> _topEntities = [];

  List<_TopEntity> _computeTopEntities() {
    final entities = <_TopEntity>[];

    for (final player in _players) {
      final shipPower = player.maxHull * 10 + player.maxShields * 5;
      final weaponPower = player.weaponSlots.values.fold<int>(
        0,
        (sum, level) => sum + level * 20,
      );
      final totalCredits = player.credits + player.bankBalance;
      final powerScore = shipPower +
          weaponPower +
          (totalCredits * 0.001) +
          (player.ownedPorts.length * 200);

      entities.add(_TopEntity(
        name: player.username,
        faction: player.faction,
        powerScore: powerScore,
        credits: totalCredits,
        portsOwned: player.ownedPorts.length,
        kills: 0,
        isNpc: false,
      ));
    }

    for (final npc in _npcs) {
      final shipPower = npc.maxHull * 10 + npc.maxShields * 5;
      final weaponPower = npc.weaponSlots.values.fold<int>(
        0,
        (sum, level) => sum + level * 20,
      );
      final totalCredits = npc.credits + npc.bankBalance;
      final powerScore =
          shipPower + weaponPower + (totalCredits * 0.001) + (npc.kills * 50);

      entities.add(_TopEntity(
        name: npc.pilotName,
        faction: npc.faction,
        powerScore: powerScore,
        credits: totalCredits,
        portsOwned: 0,
        kills: npc.kills,
        isNpc: true,
      ));
    }

    entities.sort((a, b) => b.powerScore.compareTo(a.powerScore));
    return entities.take(10).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_players.isEmpty && _npcs.isEmpty) {
      return Center(
        child: Text(
          'No ships in the galaxy yet.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );
    }

    final stats = _computeStats();
    _topEntities = _computeTopEntities();
    final sorted = stats.values.toList()
      ..sort((a, b) => b.powerScore.compareTo(a.powerScore));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSummaryHeader(theme, cs, sorted),
          const SizedBox(height: 24),
          _buildTopPilotsSection(theme, cs),
          const SizedBox(height: 24),
          _buildRankingsList(theme, cs, sorted),
          const SizedBox(height: 24),
          _buildShipBreakdownChart(theme, cs, stats),
          const SizedBox(height: 24),
          _buildCreditsChart(theme, cs, stats),
          const SizedBox(height: 24),
          _buildPortsChart(theme, cs, stats),
          const SizedBox(height: 24),
          _buildCombatStatsChart(theme, cs, stats),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(
    ThemeData theme,
    ColorScheme cs,
    List<FactionStats> sorted,
  ) {
    final totalShips = _players.length + _npcs.length;
    final leader = sorted.first;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 48,
              color: fcol.factionColor(leader.faction),
            ),
            const SizedBox(height: 12),
            Text(
              'GALACTIC INTELLIGENCE REPORT',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_formatCredits(leader.totalCredits + leader.totalBankCredits)} cr total wealth • $totalShips ships tracked',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color:
                    fcol.factionColor(leader.faction).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Dominant: ${_getFactionName(leader.faction)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: fcol.factionColor(leader.faction),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopPilotsSection(
    ThemeData theme,
    ColorScheme cs,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Top 10 Pilots',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: _topEntities.take(5).map((entity) {
                      return _TopPilotCard(
                        rank: _topEntities.indexOf(entity) + 1,
                        entity: entity,
                        maxScore: _topEntities.isNotEmpty
                            ? _topEntities.first.powerScore
                            : 1,
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: _topEntities.skip(5).take(5).map((entity) {
                      return _TopPilotCard(
                        rank: _topEntities.indexOf(entity) + 1,
                        entity: entity,
                        maxScore: _topEntities.isNotEmpty
                            ? _topEntities.first.powerScore
                            : 1,
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingsList(
    ThemeData theme,
    ColorScheme cs,
    List<FactionStats> sorted,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Power Rankings',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          ...sorted.asMap().entries.map((entry) {
            final idx = entry.key;
            final s = entry.value;
            return _RankingCard(
              rank: idx + 1,
              stats: s,
              maxScore: sorted.first.powerScore,
            );
          }),
        ],
      ),
    );
  }

  Widget _buildShipBreakdownChart(
    ThemeData theme,
    ColorScheme cs,
    Map<FactionClass, FactionStats> stats,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ship Class Breakdown',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _StackedBarChart(
              factions: [
                ...Faction.allFactions().map((f) => f.factionClass),
                FactionClass.pirate,
              ],
              getStats: (fc) => stats[fc]!.shipByClass,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: ShipClassType.values.map((sc) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _getShipClassColor(sc),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _getShipClassLabel(sc),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreditsChart(
    ThemeData theme,
    ColorScheme cs,
    Map<FactionClass, FactionStats> stats,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Total Wealth (Credits + Banking)',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _BarChart(
              data: stats.values.map((s) {
                final total = s.totalCredits + s.totalBankCredits;
                return _BarEntry(
                  label: _getFactionName(s.faction),
                  value: total.toDouble(),
                  color: fcol.factionColor(s.faction),
                  formattedValue: '${_formatCredits(total)} cr',
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPortsChart(
    ThemeData theme,
    ColorScheme cs,
    Map<FactionClass, FactionStats> stats,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ports Controlled',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _BarChart(
              data: stats.values.map((s) {
                return _BarEntry(
                  label: _getFactionName(s.faction),
                  value: s.portsControlled.toDouble(),
                  color: fcol.factionColor(s.faction),
                  formattedValue: '${s.portsControlled} ports',
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCombatStatsChart(
    ThemeData theme,
    ColorScheme cs,
    Map<FactionClass, FactionStats> stats,
  ) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Combat Statistics',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _BarChart(
              data: stats.values.map((s) {
                final totalCombat = s.kills + s.deaths;
                return _BarEntry(
                  label: _getFactionName(s.faction),
                  value: totalCombat.toDouble(),
                  color: fcol.factionColor(s.faction),
                  formattedValue: '${s.kills}K / ${s.deaths}D',
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class FactionStats {
  final FactionClass faction;
  int shipCount = 0;
  int totalCredits = 0;
  int totalBankCredits = 0;
  int ownedPortsCount = 0;
  int portsControlled = 0;
  Map<ShipClassType, int> shipByClass = {};
  int kills = 0;
  int deaths = 0;
  int totalDamageDealt = 0;
  int totalDamageTaken = 0;
  double powerScore = 0;

  FactionStats({required this.faction});

  void _computePowerScore() {
    powerScore = (shipCount * 100.0) +
        (totalCredits * 0.001) +
        (totalBankCredits * 0.0005) +
        (portsControlled * 500.0) +
        (ownedPortsCount * 200.0) +
        (kills * 50.0) +
        (totalDamageDealt * 0.01);
  }
}

class _RankingCard extends StatelessWidget {
  final int rank;
  final FactionStats stats;
  final double maxScore;

  const _RankingCard({
    required this.rank,
    required this.stats,
    required this.maxScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final factionColor = fcol.factionColor(stats.faction);
    final factionName = _getFactionName(stats.faction);
    final scorePct = maxScore > 0 ? stats.powerScore / maxScore : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border(
            left: BorderSide(
              width: 4,
              color: factionColor,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: factionColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '#$rank',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: factionColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          factionName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Power Score: ${stats.powerScore.toStringAsFixed(0)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: scorePct,
                  backgroundColor: factionColor.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation(factionColor),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _statPill(cs, Icons.flight, '${stats.shipCount} ships'),
                  const SizedBox(width: 8),
                  _statPill(
                    cs,
                    Icons.account_balance_wallet_rounded,
                    '${_formatCredits(stats.totalCredits + stats.totalBankCredits)} cr',
                  ),
                  const SizedBox(width: 8),
                  _statPill(cs, Icons.hail, '${stats.portsControlled} ports'),
                ],
              ),
              if (stats.kills > 0 || stats.deaths > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _statPill(cs, Icons.local_fire_department_rounded,
                        '${stats.kills} kills'),
                    const SizedBox(width: 8),
                    _statPill(cs, Icons.do_not_disturb_off_rounded,
                        '${stats.deaths} deaths'),
                    const SizedBox(width: 8),
                    _statPill(cs, Icons.bolt_rounded,
                        '${_formatCredits(stats.totalDamageDealt)} dmg'),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _statPill(ColorScheme cs, IconData icon, String label) {
    return Expanded(
      child: HudPill(
        text: label,
        background: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        foreground: cs.onSurface.withValues(alpha: 0.7),
        icon: icon,
        iconColor: cs.onSurface.withValues(alpha: 0.5),
        iconSize: 12,
        fontSize: 11,
        radius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _BarChart extends StatelessWidget {
  final List<_BarEntry> data;

  const _BarChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final max = data.fold<double>(0, (s, e) => s > e.value ? s : e.value);
    if (max <= 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 160,
      child: Column(
        children: data.map((entry) {
          final pct = entry.value / max;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        entry.label,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: pct,
                          backgroundColor: entry.color.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(entry.color),
                          minHeight: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      entry.formattedValue,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: entry.color,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _BarEntry {
  final String label;
  final double value;
  final Color color;
  final String formattedValue;

  _BarEntry({
    required this.label,
    required this.value,
    required this.color,
    required this.formattedValue,
  });
}

class _StackedBarChart extends StatelessWidget {
  final List<FactionClass> factions;
  final Map<ShipClassType, int> Function(FactionClass) getStats;

  const _StackedBarChart({
    required this.factions,
    required this.getStats,
  });

  @override
  Widget build(BuildContext context) {
    int globalMax = 0;
    final totals = <FactionClass, int>{};
    for (final fc in factions) {
      final stats = getStats(fc);
      final total = stats.values.fold<int>(0, (s, v) => s + v);
      totals[fc] = total;
      if (total > globalMax) globalMax = total;
    }

    if (globalMax <= 0) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 180,
      child: Column(
        children: factions.map((f) {
          final stats = getStats(f);
          final total = totals[f] ?? 0;
          final factionColor = fcol.factionColor(f);

          return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 80,
                      child: Text(
                        _getFactionName(f),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: factionColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          height: 24,
                          color: factionColor.withValues(alpha: 0.08),
                          child: Row(
                            children: ShipClassType.values.map((sc) {
                              final count = stats[sc] ?? 0;
                              if (count <= 0) return const SizedBox.shrink();
                              return Expanded(
                                flex: count,
                                child: Container(
                                  color: _getShipClassColor(sc)
                                      .withValues(alpha: 0.7),
                                  child: count >= 2
                                      ? Center(
                                          child: Text(
                                            '$count',
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        )
                                      : null,
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$total',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

Color _getShipClassColor(ShipClassType sc) {
  switch (sc) {
    case ShipClassType.interceptor:
      return const Color(0xFF29B6F6);
    case ShipClassType.battleship:
      return const Color(0xFFFF5252);
    case ShipClassType.freighter:
      return const Color(0xFF69F0AE);
    case ShipClassType.capitalShip:
      return const Color(0xFFB388FF);
  }
}

String _getFactionName(FactionClass fc) {
  try {
    return Faction.forClass(fc).name;
  } catch (e) {
    return fc == FactionClass.pirate ? 'Pirates' : fc.name;
  }
}

String _getShipClassLabel(ShipClassType sc) {
  switch (sc) {
    case ShipClassType.interceptor:
      return 'Interceptor';
    case ShipClassType.battleship:
      return 'Battleship';
    case ShipClassType.freighter:
      return 'Freighter';
    case ShipClassType.capitalShip:
      return 'Capital';
  }
}

class _TopEntity {
  final String name;
  final FactionClass faction;
  final double powerScore;
  final int credits;
  final int portsOwned;
  final int kills;
  final bool isNpc;

  _TopEntity({
    required this.name,
    required this.faction,
    required this.powerScore,
    required this.credits,
    required this.portsOwned,
    required this.kills,
    required this.isNpc,
  });
}

class _TopPilotCard extends StatelessWidget {
  final int rank;
  final _TopEntity entity;
  final double maxScore;

  const _TopPilotCard({
    required this.rank,
    required this.entity,
    required this.maxScore,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final factionColor = fcol.factionColor(entity.faction);
    final scorePct = maxScore > 0 ? entity.powerScore / maxScore : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            width: 3,
            color: factionColor,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '#$rank',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: factionColor,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entity.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entity.isNpc ? 'NPC' : 'Player'} • ${_getFactionName(entity.faction)}',
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entity.powerScore.toStringAsFixed(0),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: scorePct,
                    backgroundColor: factionColor.withValues(alpha: 0.1),
                    valueColor: AlwaysStoppedAnimation(factionColor),
                    minHeight: 3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
