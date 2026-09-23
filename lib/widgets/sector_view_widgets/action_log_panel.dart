import 'package:flutter/material.dart';
import 'action_log_provider.dart';

class ActionLogPanel extends StatefulWidget {
  const ActionLogPanel({super.key});

  @override
  State<ActionLogPanel> createState() => _ActionLogPanelState();
}

class _ActionLogPanelState extends State<ActionLogPanel> {
  late final ActionLogProvider _provider;

  @override
  void initState() {
    super.initState();
    _provider = ActionLogProvider.global;
    _provider.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onLogChanged);
    super.dispose();
  }

  void _onLogChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = _provider.entries;
    final rawCount = _provider.rawCount;
    final visibleTypes = _provider.visibleTypes;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.history_rounded, size: 18, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'ACTION LOG',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                        letterSpacing: 1,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${entries.length}/$rawCount',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.5),
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _FilterChip(
                      label: 'ALL',
                      selected: visibleTypes.length == LogType.values.length,
                      onTap: () {
                        if (visibleTypes.length == LogType.values.length) {
                          _provider.hideAllTypes();
                        } else {
                          _provider.showAllTypes();
                        }
                      },
                    ),
                    ...LogType.values.map((type) => _FilterChip(
                          label: type.name.toUpperCase(),
                          selected: _provider.isVisible(type),
                          color: _logTypeColor(type),
                          onTap: () => _provider.toggleType(type),
                        )),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(
                    child: Text(
                      'No log entries',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    padding: const EdgeInsets.all(12),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      return _LogEntryTile(entry: entry);
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c : cs.outline.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? c : cs.onSurface.withValues(alpha: 0.6),
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;

  const _LogEntryTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final color = _logTypeColor(entry.type);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatTime(entry.timestamp),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurface.withValues(alpha: 0.4),
              fontSize: 10,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 5),
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.5),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              entry.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.85),
                height: 1.3,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

Color _logTypeColor(LogType type) {
  switch (type) {
    case LogType.info:
      return const Color(0xFF00FFFF);
    case LogType.success:
      return const Color(0xFF00FF41);
    case LogType.warning:
      return Colors.amber.shade300;
    case LogType.error:
      return const Color(0xFFFF0040);
    case LogType.combat:
      return Colors.redAccent;
    case LogType.trade:
      return Colors.amber;
    case LogType.movement:
      return const Color(0xFF00FFFF);
    case LogType.system:
      return Colors.purpleAccent;
  }
}

String _formatTime(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  final s = dt.second.toString().padLeft(2, '0');
  return '$h:$m:$s';
}
