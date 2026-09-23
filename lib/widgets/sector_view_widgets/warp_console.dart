import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/player.dart';

typedef OnWarpCallback = Future<void> Function(int sectorId);

class WarpConsole extends StatefulWidget {
  final Sector currentSector;
  final List<Sector> allSectors;
  final Player player;
  final OnWarpCallback onWarp;
  final int? highlightedSectorId;

  const WarpConsole({
    super.key,
    required this.currentSector,
    required this.allSectors,
    required this.player,
    required this.onWarp,
    this.highlightedSectorId,
  });

  @override
  State<WarpConsole> createState() => _WarpConsoleState();
}

class _WarpConsoleState extends State<WarpConsole> {
  final TextEditingController _controller = TextEditingController();
  String? _errorMessage;
  bool _isWarping = false;

  // NEW: Track the final destination to keep the Nav Computer active across hops
  int? _ultimateDestination;
  List<int> _calculatedPath = [];

  List<Sector> get _adjacentSectors {
    return widget.allSectors
        .where((s) => widget.currentSector.warpRoutes.contains(s.id))
        .toList()
      ..sort((a, b) => a.id.compareTo(b.id));
  }

  bool get _canLongRangeWarp {
    return widget.player.engineEquipmentLevel >= 3;
  }

  @override
  void didUpdateWidget(covariant WarpConsole oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle selection from the tactical map
    if (widget.highlightedSectorId != oldWidget.highlightedSectorId) {
      if (widget.highlightedSectorId != null) {
        _controller.text = widget.highlightedSectorId.toString();
        _setDestination(widget.highlightedSectorId!);
      }
    }

    // Handle player moving to a new sector
    if (widget.currentSector.id != oldWidget.currentSector.id) {
      if (_ultimateDestination != null) {
        if (widget.currentSector.id == _ultimateDestination) {
          // Arrived at final destination! Clear route.
          setState(() {
            _ultimateDestination = null;
            _calculatedPath = [];
            _controller.clear();
          });
        } else if (_calculatedPath.isNotEmpty &&
            widget.currentSector.id == _calculatedPath.first) {
          // Arrived at the next hop. Keep route active and recalculate remaining path.
          _calculatePath(_ultimateDestination!);
        } else {
          // Player warped off-route manually. Cancel the nav computer route.
          setState(() {
            _ultimateDestination = null;
            _calculatedPath = [];
          });
        }
      }
    }
  }

  List<int> _findPath(int startId, int targetId) {
    if (startId == targetId) return [];

    final Map<int, int> cameFrom = {};
    final queue = <int>[startId];
    cameFrom[startId] = -1;

    while (queue.isNotEmpty) {
      final currentId = queue.removeAt(0);

      final match = widget.allSectors.where((s) => s.id == currentId);
      if (match.isEmpty) continue;
      final sector = match.first;

      for (final neighborId in sector.warpRoutes) {
        if (!cameFrom.containsKey(neighborId)) {
          cameFrom[neighborId] = currentId;

          if (neighborId == targetId) {
            final path = <int>[];
            int step = targetId;
            while (step != -1 && step != startId) {
              path.add(step);
              step = cameFrom[step]!;
            }
            return path.reversed.toList();
          }
          queue.add(neighborId);
        }
      }
    }
    return [];
  }

  void _calculatePath(int targetId) {
    final path = _findPath(widget.currentSector.id, targetId);
    setState(() {
      _calculatedPath = path;
      _errorMessage =
          path.isEmpty ? 'No route found to Sector $targetId' : null;
    });
  }

  void _setDestination(int targetId) {
    if (targetId == widget.currentSector.id) {
      setState(() {
        _ultimateDestination = null;
        _calculatedPath = [];
        _errorMessage = null;
      });
      return;
    }
    setState(() {
      _ultimateDestination = targetId;
    });
    _calculatePath(targetId);
  }

  // NEW: Engage button logic
  void _engageWarp() {
    if (_isWarping || _ultimateDestination == null) return;

    if (_canLongRangeWarp) {
      // If they have long-range, just warp straight to the end
      _executeWarp(_ultimateDestination!);
    } else if (_calculatedPath.isNotEmpty) {
      // Otherwise, warp to the next hop
      _executeWarp(_calculatedPath.first);
    }
  }

  void _cancelRoute() {
    setState(() {
      _ultimateDestination = null;
      _calculatedPath = [];
      _controller.clear();
    });
  }

  void _executeWarp(int sectorId) async {
    if (_isWarping) return;

    final maxId = widget.allSectors.length;
    if (sectorId < 1 || sectorId > maxId) {
      setState(() {
        _errorMessage = 'Invalid sector — enter a number between 1 and $maxId';
      });
      return;
    }

    if (sectorId == widget.currentSector.id) {
      setState(() {
        _errorMessage = 'You are already in sector $sectorId';
      });
      return;
    }

    final isAdjacent = widget.currentSector.warpRoutes.contains(sectorId);
    int actualWarpTarget = sectorId;

    // If trying to warp to a non-adjacent sector without long-range capability
    if (!isAdjacent && !_canLongRangeWarp) {
      // If there is a calculated path to this destination, redirect to the first hop instead
      if (_calculatedPath.isNotEmpty && _calculatedPath.last == sectorId) {
        actualWarpTarget = _calculatedPath.first;
      } else {
        setState(() {
          _errorMessage = 'Long-range warp requires Engine Level 3+';
        });
        return;
      }
    }

    if (widget.player.turns <= 0) {
      setState(() {
        _errorMessage = 'Insufficient turns';
      });
      return;
    }

    setState(() {
      _isWarping = true;
      _errorMessage = null;
    });

    await widget.onWarp(actualWarpTarget);

    if (mounted) {
      setState(() {
        _isWarping = false;
      });
    }
  }

  void _onTextChanged(String value) {
    final sectorId = int.tryParse(value.trim());
    if (sectorId != null) {
      _setDestination(sectorId);
    } else {
      setState(() {
        _ultimateDestination = null;
        _calculatedPath = [];
        _errorMessage = null;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = Theme.of(context).colorScheme;

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
            child: Row(
              children: [
                Icon(Icons.input_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'WARP CONSOLE',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _canLongRangeWarp
                            ? cs.tertiary.withValues(alpha: 0.2)
                            : cs.errorContainer.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _canLongRangeWarp
                            ? 'LONG-RANGE ENABLED'
                            : 'ADJACENT ONLY',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _canLongRangeWarp ? cs.tertiary : cs.error,
                          fontFamily: 'monospace',
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _controller,
                  keyboardType: TextInputType.number,
                  onChanged: _onTextChanged,
                  enabled: !_isWarping,
                  decoration: InputDecoration(
                    labelText: 'DESTINATION SECTOR',
                    hintText: 'Enter sector # (1-${widget.allSectors.length})',
                    prefixIcon:
                        Icon(Icons.input_rounded, size: 20, color: cs.primary),
                    suffixIcon: _isWarping
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: Icon(Icons.send_rounded, color: cs.primary),
                            onPressed: () {
                              final text = _controller.text.trim();
                              final value = int.tryParse(text);
                              if (value == null) {
                                setState(() {
                                  _errorMessage = 'Enter a valid sector number';
                                });
                                return;
                              }
                              _executeWarp(value);
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          BorderSide(color: cs.outline.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: cs.primary, width: 2),
                    ),
                  ),
                  onSubmitted: (value) {
                    final text = value.trim();
                    final sectorId = int.tryParse(text);
                    if (sectorId == null) {
                      setState(() {
                        _errorMessage = 'Enter a valid sector number';
                      });
                      return;
                    }
                    _executeWarp(sectorId);
                  },
                ),

                // NEW: Persistent Nav Computer Box
                if (_ultimateDestination != null &&
                    _calculatedPath.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: cs.primary.withAlpha(100)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'NAV COMPUTER: ${_calculatedPath.length} HOPS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: cs.primary,
                                fontFamily: 'monospace',
                              ),
                            ),
                            // Cancel Route X Button
                            GestureDetector(
                              onTap: _cancelRoute,
                              child: Icon(Icons.close,
                                  size: 16, color: cs.onSurface.withAlpha(150)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children:
                              _calculatedPath.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final sectorId = entry.value;
                            final isNextHop = idx == 0;

                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (idx > 0)
                                  Icon(Icons.arrow_forward,
                                      size: 12,
                                      color: cs.onSurface.withAlpha(120)),
                                if (idx > 0) const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: isNextHop
                                        ? cs.primary.withAlpha(100)
                                        : cs.surfaceContainerHighest
                                            .withAlpha(100),
                                    borderRadius: BorderRadius.circular(4),
                                    border: isNextHop
                                        ? Border.all(color: cs.primary)
                                        : null,
                                  ),
                                  child: Text(
                                    '$sectorId',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: isNextHop
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontFamily: 'monospace',
                                      color: isNextHop
                                          ? cs.primary
                                          : cs.onSurface.withAlpha(180),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isWarping ? null : _engageWarp,
                            icon: _isWarping
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Icon(Icons.near_me_rounded, size: 16),
                            label: Text(
                              _isWarping
                                  ? 'WARPING...'
                                  : _canLongRangeWarp
                                      ? 'ENGAGE LONG WARP'
                                      : 'ENGAGE NEXT HOP',
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: cs.primary,
                              foregroundColor: cs.onPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: cs.errorContainer.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_rounded, size: 16, color: cs.error),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: cs.error,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Text(
                  'ADJACENT SECTORS',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _adjacentSectors.map((s) {
                    final isHighlighted = s.id == widget.highlightedSectorId;

                    return ChoiceChip(
                      label: Text(
                        '${s.id}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isHighlighted ? FontWeight.w800 : FontWeight.w600,
                          fontFamily: 'monospace',
                          color: isHighlighted
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                      selected: isHighlighted,
                      onSelected: (v) {
                        if (!_isWarping) _executeWarp(s.id);
                      },
                      selectedColor: cs.primary.withValues(alpha: 0.2),
                      backgroundColor:
                          cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      side: BorderSide(
                        color: isHighlighted
                            ? cs.primary
                            : cs.outline.withValues(alpha: 0.2),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    );
                  }).toList(),
                ),

                const SizedBox(height: 12),

                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.timer_rounded, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'TURNS REMAINING: ',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSurface.withValues(alpha: 0.6),
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Text(
                        '${widget.player.turns}/${widget.player.maxTurns}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.primary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      if (widget.player.engineEquipmentLevel >= 3)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.tertiary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'ENG LVL ${widget.player.engineEquipmentLevel}',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: cs.tertiary,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                    ],
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
