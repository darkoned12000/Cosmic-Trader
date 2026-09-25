import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cosmic_trader/services/game_event_log.dart';

/// Settings → Automation log viewer (F1) plus dev controls (F2).
///
/// Searchable, category-filterable live view over [GameEventLog.global]:
/// every NPC action (combat, trade, movement, energy, banking, goal changes)
/// plus tick-system lines. Newest first. Display is capped to the latest 200
/// matches so the list stays smooth at high sector counts; the buffer itself
/// holds [GameEventLog.maxEntries].
///
/// The Copy button copies exactly what is on screen (current search +
/// category filters + display cap), not the whole buffer.
///
/// Dev controls (tick speed, resource grants, energy drains) appear only
/// when the corresponding callbacks are provided — the widget stays usable
/// standalone without them.
class AutomationConsoleWidget extends StatefulWidget {
  const AutomationConsoleWidget({
    super.key,
    this.tickIntervalSeconds,
    this.tickPaused = false,
    this.onTickIntervalChanged,
    this.onTickPausedChanged,
    this.playerCredits,
    this.playerScrapMetal,
    this.playerScrapTech,
    this.playerEnergy,
    this.playerMaxEnergy,
    this.onGrantCredits,
    this.onGrantScrapMetal,
    this.onGrantScrapTech,
    this.onDrainPlayerEnergy,
    this.onDrainNpcEnergy,
    this.onDumpDiagnostics,
  });

  final int? tickIntervalSeconds;
  final bool tickPaused;
  final ValueChanged<int>? onTickIntervalChanged;
  final ValueChanged<bool>? onTickPausedChanged;

  final int? playerCredits;
  final int? playerScrapMetal;
  final int? playerScrapTech;
  final int? playerEnergy;
  final int? playerMaxEnergy;
  final VoidCallback? onGrantCredits;
  final VoidCallback? onGrantScrapMetal;
  final VoidCallback? onGrantScrapTech;
  final VoidCallback? onDrainPlayerEnergy;
  final VoidCallback? onDrainNpcEnergy;
  final VoidCallback? onDumpDiagnostics;

  /// True when the shell wired dev controls into this instance.
  bool get hasDevControls => onTickIntervalChanged != null;

  @override
  State<AutomationConsoleWidget> createState() =>
      _AutomationConsoleWidgetState();
}

class _AutomationConsoleWidgetState extends State<AutomationConsoleWidget> {
  static const int _displayLimit = 200;

  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  final Set<GameEventCategory> _hidden = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Color _categoryColor(GameEventCategory category) {
    return switch (category) {
      GameEventCategory.combat => Colors.redAccent,
      GameEventCategory.trade => Colors.green,
      GameEventCategory.movement => Colors.blue,
      GameEventCategory.energy => Colors.amber,
      GameEventCategory.banking => Colors.teal,
      GameEventCategory.goal => Colors.purple,
      GameEventCategory.system => Colors.grey,
    };
  }

  /// Copies exactly what is on screen (current filters + display cap) as
  /// `[time] [category] message` lines — never the whole buffer.
  void _copyShown(BuildContext context, List<GameEventEntry> shown) {
    final text = shown
        .map((e) =>
            '[${e.timestamp.toIso8601String()}] [${e.category.name}] ${e.message}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${shown.length} visible events')),
    );
  }

  /// F2 dev controls: tick speed + pause, resource grants, energy drains.
  /// Rendered only when the shell provided callbacks.
  Widget _buildDevControls(BuildContext context, ColorScheme cs) {
    const tickPresets = [30, 5, 1];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Tick controls',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final seconds in tickPresets)
              ChoiceChip(
                label:
                    Text('${seconds}s', style: const TextStyle(fontSize: 12)),
                selected:
                    widget.tickIntervalSeconds == seconds && !widget.tickPaused,
                onSelected: (_) => widget.onTickIntervalChanged?.call(seconds),
              ),
            FilterChip(
              label: Text(widget.tickPaused ? 'Resume' : 'Pause',
                  style: const TextStyle(fontSize: 12)),
              selected: widget.tickPaused,
              onSelected: (_) =>
                  widget.onTickPausedChanged?.call(!widget.tickPaused),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Player resources',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        if (widget.playerCredits != null ||
            widget.playerScrapMetal != null ||
            widget.playerEnergy != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'Credits ${widget.playerCredits ?? '—'} · '
              'Metal ${widget.playerScrapMetal ?? '—'} · '
              'Tech ${widget.playerScrapTech ?? '—'} · '
              'Energy ${widget.playerEnergy ?? '—'}'
              '${widget.playerMaxEnergy != null ? '/${widget.playerMaxEnergy}' : ''}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onGrantCredits,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+100k cr', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: widget.onGrantScrapMetal,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+500 metal', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: widget.onGrantScrapTech,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('+50 tech', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Energy drains',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: widget.onDrainNpcEnergy,
              icon: const Icon(Icons.battery_0_bar_rounded, size: 16),
              label: const Text('NPCs → 10%', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: widget.onDrainPlayerEnergy,
              icon: const Icon(Icons.battery_0_bar_rounded, size: 16),
              label: const Text('Player → 0', style: TextStyle(fontSize: 12)),
            ),
            OutlinedButton.icon(
              onPressed: widget.onDumpDiagnostics,
              icon: const Icon(Icons.bug_report_rounded, size: 16),
              label: const Text('Diagnose trading',
                  style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          leading: const Icon(Icons.terminal_rounded, color: Colors.lightGreen),
          title: const Text('Automation (Dev)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          subtitle: const Text('NPC action log — search & filter'),
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: ListenableBuilder(
                listenable: GameEventLog.global,
                builder: (context, _) {
                  final log = GameEventLog.global;
                  final matches = log.query(
                    query: _query,
                    categories: GameEventCategory.values.toSet()
                      ..removeAll(_hidden),
                  );
                  final shown = matches.take(_displayLimit).toList();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.hasDevControls) ...[
                        _buildDevControls(context, cs),
                        const Divider(height: 24),
                      ],
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText:
                              'Search pilot, sector, event… (e.g. NPC_ENERGY, refuel_buy)',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: GameEventCategory.values.map((c) {
                          final visible = !_hidden.contains(c);
                          return FilterChip(
                            label: Text(c.name,
                                style: const TextStyle(fontSize: 12)),
                            selected: visible,
                            onSelected: (_) => setState(() {
                              if (visible) {
                                _hidden.add(c);
                              } else {
                                _hidden.remove(c);
                              }
                            }),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            '${matches.length} of ${log.length} events'
                            '${matches.length > _displayLimit ? ' (showing latest $_displayLimit)' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: shown.isEmpty
                                ? null
                                : () => _copyShown(context, shown),
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            label: const Text('Copy view',
                                style: TextStyle(fontSize: 12)),
                          ),
                          TextButton.icon(
                            onPressed: () => log.clear(),
                            icon: const Icon(Icons.delete_outline_rounded,
                                size: 16),
                            label: const Text('Clear',
                                style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'All-time (never evicted): ${GameEventCategory.values.map((c) => '${c.name} ${log.count(c)}').join(' · ')}',
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: cs.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No matching events yet. Run the game with NPCs '
                            'active (ticks fire every 30s) and entries will '
                            'appear here live.',
                            style: TextStyle(
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        )
                      else
                        Container(
                          height: 320,
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: cs.outline.withValues(alpha: 0.4),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListView.builder(
                            itemCount: shown.length,
                            itemBuilder: (context, i) {
                              final entry = shown[i];
                              final color = _categoryColor(entry.category);
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(top: 4),
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        entry.message,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
