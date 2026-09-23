import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/faction_rankings_screen.dart';
import 'package:cosmic_trader/screens/knowledge_base_screen.dart';
import 'package:cosmic_trader/screens/ports_knowledge_base.dart';
import 'package:cosmic_trader/widgets/banking_widget.dart';

class ComputerScreen extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const ComputerScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<ComputerScreen> createState() => _ComputerScreenState();
}

class _ComputerScreenState extends State<ComputerScreen> {
  String? _selectedTool;
  List<Sector> _sectors = [];
  bool _loading = true;
  String? _filterCommodity;
  String? _sortBy;
  PortClass? _filterPortClass;
  Key _bankingKey = UniqueKey();
  Key _rankingsKey = UniqueKey();

  @override
  void initState() {
    super.initState();
    _loadUniverse();
  }

  Future<void> _loadUniverse() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (!mounted) return;
      setState(() {
        _sectors = sectors;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_selectedTool == null) {
      return _buildMenu(theme, cs);
    }

    switch (_selectedTool) {
      case 'banking':
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _selectedTool = null),
            ),
            title: const Text('Banking'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: () => setState(() => _bankingKey = UniqueKey()),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: BankingWidget(
              key: _bankingKey,
              player: widget.player,
              onPlayerUpdate: widget.onPlayerUpdate,
            ),
          ),
        );
      case 'port_report':
        return _buildPortReport(theme, cs);
      case 'knowledge_base':
        return KnowledgeBaseScreen(
          onBack: () => setState(() => _selectedTool = null),
        );
      case 'ports_guide':
        return PortsKnowledgeBaseScreen(
          onBack: () => setState(() => _selectedTool = null),
        );
      case 'faction_rankings':
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => setState(() => _selectedTool = null),
            ),
            title: const Text('Faction Power Rankings'),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Refresh',
                onPressed: () => setState(() => _rankingsKey = UniqueKey()),
              ),
            ],
          ),
          body: FactionRankingsScreen(key: _rankingsKey),
        );
      default:
        return _buildMenu(theme, cs);
    }
  }

  Widget _buildMenu(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'COMPUTER',
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Trade tools and intelligence',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 24),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.account_balance_rounded,
                        color: Colors.green.shade400, size: 22),
                  ),
                  title: const Text('Banking',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Deposit, withdraw, earn interest',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(() => _selectedTool = 'banking'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.assessment_rounded,
                        color: cs.primary, size: 22),
                  ),
                  title: const Text('Port Report',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Browse port prices with filter & sort',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(() => _selectedTool = 'port_report'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.menu_book_rounded,
                        color: Colors.deepPurple.shade400, size: 22),
                  ),
                  title: const Text('Knowledge Base',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Factions, lore, and galactic intelligence',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(() => _selectedTool = 'knowledge_base'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.store_mall_directory_rounded,
                        color: Colors.teal.shade400, size: 22),
                  ),
                  title: const Text('Ports Guide',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Hacking, stealing, purchasing, and managing ports',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => setState(() => _selectedTool = 'ports_guide'),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.bar_chart_rounded,
                        color: Colors.amber.shade400, size: 22),
                  ),
                  title: const Text('Faction Power Rankings',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    'Live faction stats, charts, and intelligence',
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 12),
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () =>
                      setState(() => _selectedTool = 'faction_rankings'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<String> get _commodities => CommodityRegistry.names;
  static const _commodityLabels = {
    'minerals': 'Minerals',
    'organics': 'Organics',
    'industrial': 'Industrial',
  };

  List<Sector> _filteredPorts() {
    var ports = _sectors.where((s) => s.hasPort && s.port != null).toList();

    if (_filterCommodity != null) {
      ports = ports.where((s) {
        final p = s.port!;
        return p.buys(_filterCommodity!) || p.sells(_filterCommodity!);
      }).toList();
    }

    if (_filterPortClass != null) {
      ports =
          ports.where((s) => s.port!.portClass == _filterPortClass).toList();
    }

    if (_sortBy == 'buy' && _filterCommodity != null) {
      ports = ports.where((s) => s.port!.buys(_filterCommodity!)).toList();
      ports.sort((a, b) {
        final pa = a.port!.getBuyPrice(_filterCommodity!);
        final pb = b.port!.getBuyPrice(_filterCommodity!);
        return pb.compareTo(pa);
      });
    } else if (_sortBy == 'sell' && _filterCommodity != null) {
      ports = ports.where((s) => s.port!.sells(_filterCommodity!)).toList();
      ports.sort((a, b) {
        final pa = a.port!.getSellPrice(_filterCommodity!);
        final pb = b.port!.getSellPrice(_filterCommodity!);
        return pa.compareTo(pb);
      });
    }

    return ports;
  }

  Widget _buildPortReport(ThemeData theme, ColorScheme cs) {
    final portSectors = _filteredPorts();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => setState(() {
            _selectedTool = null;
            _filterCommodity = null;
            _sortBy = null;
            _filterPortClass = null;
          }),
        ),
        title: const Text('Port Report'),
      ),
      body: Column(
        children: [
          _filterBar(theme, cs),
          Expanded(
            child: portSectors.isEmpty
                ? Center(
                    child: Text(
                      _buildEmptyPortsMessage(),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    itemCount: portSectors.length,
                    itemBuilder: (context, index) {
                      final sector = portSectors[index];
                      final port = sector.port!;
                      return _portReportCard(theme, cs, sector, port);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(ThemeData theme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Filters:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(width: 8),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _filterChip(cs, 'All', null),
                      ..._commodities.map((c) => _filterChip(cs, c)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('Class:',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.6))),
              const SizedBox(width: 8),
              Flexible(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _classFilterChip(cs, 'All', null),
                      _classFilterChip(cs, 'Federal', PortClass.federal),
                      _classFilterChip(
                          cs, 'Hardware', PortClass.hardwareEmporium),
                      _classFilterChip(cs, 'Free', PortClass.free),
                      _classFilterChip(
                          cs, 'Independent', PortClass.independent),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_filterCommodity != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.only(left: 52),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _sortChip(cs, 'Default', null),
                    _sortChip(cs, 'Best Buy Price', 'buy'),
                    _sortChip(cs, 'Best Sell Price', 'sell'),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 16),
        ],
      ),
    );
  }

  Widget _filterChip(ColorScheme cs, String label, [String? value]) {
    value ??= label;
    final selected = _filterCommodity == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(value == 'All' ? 'All' : _commodityLabels[value] ?? value,
            style: const TextStyle(fontSize: 12)),
        onSelected: (_) => setState(() {
          _filterCommodity = value == 'All' ? null : value;
          _sortBy = null;
        }),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _sortChip(ColorScheme cs, String label, String? value) {
    final selected = _sortBy == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onSelected: (_) => setState(() => _sortBy = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _classFilterChip(ColorScheme cs, String label, PortClass? value) {
    final selected = _filterPortClass == value;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ChoiceChip(
        selected: selected,
        label: Text(label, style: const TextStyle(fontSize: 12)),
        onSelected: (_) => setState(() => _filterPortClass = value),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  String _buildEmptyPortsMessage() {
    final parts = <String>[];
    if (_filterPortClass != null) {
      final label = switch (_filterPortClass!) {
        PortClass.federal => 'Federal',
        PortClass.free => 'Free',
        PortClass.independent => 'Independent',
        PortClass.hardwareEmporium => 'Hardware',
      };
      parts.add('$label ports');
    }
    if (_filterCommodity != null) {
      parts.add('trading ${_commodityLabels[_filterCommodity]}');
    }
    if (parts.isEmpty) return 'No ports found in the universe.';
    return 'No ${parts.join(' ')} found.';
  }

  Widget _portReportCard(
      ThemeData theme, ColorScheme cs, Sector sector, Port port) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '#${sector.id}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    port.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _classBadge(cs, port.portClass),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Commodity',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text(
                    'Buy',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade400,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 60,
                  child: Text(
                    'Sell',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.red.shade400,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 8),
            ..._commodities.where((c) => port.buys(c) || port.sells(c)).map(
                  (c) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _commodityLabels[c] ?? c,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: _filterCommodity == c
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 60,
                          child: Text(
                            port.buys(c)
                                ? '${port.getBuyPrice(c).toInt()} cr'
                                : '-',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color:
                                  port.buys(c) ? Colors.green.shade400 : null,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Text(
                            port.sells(c)
                                ? '${port.getSellPrice(c).toInt()} cr'
                                : '-',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: port.sells(c) ? Colors.red.shade400 : null,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _classBadge(ColorScheme cs, PortClass portClass) {
    final (label, color) = switch (portClass) {
      PortClass.federal => ('Federal', Colors.blue),
      PortClass.free => ('Free', Colors.green),
      PortClass.independent => ('Independent', Colors.orange),
      PortClass.hardwareEmporium => ('Hardware', Colors.deepPurpleAccent),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style:
            TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }
}
