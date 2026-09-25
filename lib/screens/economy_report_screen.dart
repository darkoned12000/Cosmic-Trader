import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/widgets/shared/data_table_shell.dart';
import 'package:cosmic_trader/widgets/shared/panel_card.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';

/// Computer → Economy Report (B2 measurement).
///
/// Session-scoped trade metrics from [EconomyMetrics.global]: total volume,
/// player-vs-NPC split, per-commodity average prices vs base midpoint,
/// per-faction flows (trade net kept separate from combat loot), and an
/// in-flight holdings estimate so mid-route inventory doesn't masquerade
/// as losses. Answers "is the trading economy working/growing?"
class EconomyReportScreen extends StatefulWidget {
  const EconomyReportScreen({super.key, required this.onBack});

  final VoidCallback onBack;

  @override
  State<EconomyReportScreen> createState() => _EconomyReportScreenState();
}

class _EconomyReportScreenState extends State<EconomyReportScreen> {
  /// Estimated cargo value per faction (units × base midpoint), loaded
  /// from live NPC holds. Explains negative trade nets: wealth in flight.
  Map<String, int> _holdings = {};
  bool _holdingsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHoldings();
  }

  Future<void> _loadHoldings() async {
    try {
      final npcs = await NpcStorage().loadAll();
      final holdings = <String, int>{};
      for (final npc in npcs) {
        if (npc.isDestroyed) continue;
        var value = 0;
        npc.cargo.forEach((commodity, units) {
          final mid = CommodityRegistry.defaultsMap[commodity]?.splitPoint ?? 0;
          value += (units * mid).round();
        });
        if (value > 0) {
          holdings[npc.faction.name] =
              (holdings[npc.faction.name] ?? 0) + value;
        }
      }
      if (mounted) {
        setState(() {
          _holdings = holdings;
          _holdingsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _holdingsLoading = false);
    }
  }

  String _cr(int value) => value.toString();

  /// Copies the full report (totals + commodity + faction tables) as plain
  /// text for sharing/debugging — same shape as shown on screen.
  void _copyReport(BuildContext context) {
    final m = EconomyMetrics.global;
    final lines = <String>[
      '=== Cosmic Trader Economy Report ===',
      'Session: ${m.tradeCount} trades, ${m.totalUnits} units, '
          '${m.totalCredits} cr volume, '
          '${m.tradesPerMinute.toStringAsFixed(1)}/min '
          '(player ${m.playerTrades}, NPC ${m.npcTrades}, '
          'loot ${m.totalLoot} cr)',
      '',
      '--- Commodities (units / volume cr / avg vs base) ---',
    ];
    final commodities = m.perCommodity.keys.toList()..sort();
    if (commodities.isEmpty) {
      lines.add('(no trades yet)');
    }
    for (final name in commodities) {
      final s = m.perCommodity[name]!;
      final base = CommodityRegistry.defaultsMap[name]?.splitPoint ?? 0;
      final delta = base <= 0
          ? '—'
          : '${(((s.avgUnitPrice - base) / base) * 100).toStringAsFixed(1)}%';
      lines.add('$name: ${s.units} units / ${s.credits} cr / $delta');
    }
    lines.add('');
    lines.add('--- Factions (buys / sells / net / loot / holdings est.) ---');
    final factions = m.perFaction.keys.toList()..sort();
    if (factions.isEmpty) {
      lines.add('(no faction activity yet)');
    }
    for (final name in factions) {
      final s = m.perFaction[name]!;
      lines.add('$name: buys ${s.buys} / sells ${s.sells} / '
          'net ${s.net} / loot ${s.lootCredits} / '
          'holdings ${_holdings[name] ?? 0}');
    }
    Clipboard.setData(ClipboardData(text: lines.join('\n')));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Economy report copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Economy Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'Copy report as text',
            onPressed: () => _copyReport(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reset session metrics',
            onPressed: () => EconomyMetrics.global.reset(),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: EconomyMetrics.global,
        builder: (context, _) {
          final m = EconomyMetrics.global;
          final commodities = m.perCommodity.keys.toList()..sort();
          final factions = m.perFaction.keys.toList()..sort();

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelCard(
                  icon: Icons.show_chart_rounded,
                  title: 'Session totals',
                  subtitle:
                      'Trades/min ${m.tradesPerMinute.toStringAsFixed(1)} · '
                      'player ${m.playerTrades} · NPC ${m.npcTrades}',
                  children: [
                    StatBar(
                      label: 'Volume',
                      value:
                          '${_cr(m.totalCredits)} cr / ${m.tradeCount} trades',
                      percent: m.tradeCount <= 0 ? 0 : 1,
                      color: Colors.green,
                    ),
                    StatBar(
                      label: 'Units moved',
                      value: '${m.totalUnits}',
                      percent: m.totalUnits <= 0 ? 0 : 1,
                      color: cs.primary,
                    ),
                    StatBar(
                      label: 'NPC share',
                      value: m.tradeCount <= 0
                          ? '—'
                          : '${(100 * m.npcTrades / m.tradeCount).toStringAsFixed(0)}%',
                      percent:
                          m.tradeCount <= 0 ? 0 : m.npcTrades / m.tradeCount,
                      color: Colors.amber,
                    ),
                    StatBar(
                      label: 'Spoils (loot)',
                      value: '${_cr(m.totalLoot)} cr',
                      percent: m.totalLoot <= 0 ? 0 : 1,
                      color: Colors.redAccent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PanelCard(
                  icon: Icons.inventory_2_rounded,
                  title: 'Commodities',
                  subtitle: 'Avg unit price vs base midpoint',
                  children: [
                    if (commodities.isEmpty)
                      Text(
                        'No trades recorded yet this session.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    else
                      DataTableShell(
                        zebra: true,
                        headers: const [
                          'Commodity',
                          'Units',
                          'Volume',
                          'Avg vs base',
                        ],
                        flexes: const [2, 1, 1, 1],
                        itemCount: commodities.length,
                        rowBuilder: (context, i) {
                          final name = commodities[i];
                          final s = m.perCommodity[name]!;
                          final base =
                              CommodityRegistry.defaultsMap[name]?.splitPoint ??
                                  0;
                          final avg = s.avgUnitPrice;
                          final delta = base <= 0
                              ? '—'
                              : '${(((avg - base) / base) * 100).toStringAsFixed(0)}%';
                          return Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text(name,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                  child: Text('${s.units}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                  child: Text('${s.credits}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                  child: Text(delta,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                            ],
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                PanelCard(
                  icon: Icons.groups_rounded,
                  title: 'Faction flows',
                  subtitle: 'Net = trade surplus · Loot = combat spoils · '
                      'Holdings = cargo in flight (est.)',
                  children: [
                    if (factions.isEmpty)
                      Text(
                        'No faction activity yet this session.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    else
                      DataTableShell(
                        zebra: true,
                        headers: const [
                          'Faction',
                          'Buys',
                          'Sells',
                          'Net',
                          'Loot',
                          'Holdings',
                        ],
                        flexes: const [2, 1, 1, 1, 1, 1],
                        itemCount: factions.length,
                        rowBuilder: (context, i) {
                          final name = factions[i];
                          final s = m.perFaction[name]!;
                          final net = s.net;
                          return Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text(name,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                  child: Text('${s.buys}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                  child: Text('${s.sells}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                  child: Text(
                                '${net >= 0 ? '+' : ''}$net',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  color: net >= 0
                                      ? Colors.green
                                      : Colors.redAccent,
                                ),
                              )),
                              Expanded(
                                  child: Text('${s.lootCredits}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                  child: Text('${_holdings[name] ?? 0}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                            ],
                          );
                        },
                      ),
                    if (_holdingsLoading)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Loading live cargo holdings…',
                          style: TextStyle(
                            fontSize: 11,
                            fontStyle: FontStyle.italic,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
