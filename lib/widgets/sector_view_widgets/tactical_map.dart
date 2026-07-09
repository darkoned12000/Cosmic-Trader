import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/npc_ship.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/sector.dart';
import 'package:tradewars_2050/widgets/star_field.dart';

class TacticalMap extends StatefulWidget {
  final Sector currentSector;
  final List<Sector> allSectors;
  final Player player;
  final List<NpcShip> npcs;
  final ValueChanged<int>?
      onWarpTargetSelected; // NEW: Callback for tapped sectors

  const TacticalMap({
    super.key,
    required this.currentSector,
    required this.allSectors,
    required this.player,
    this.npcs = const [],
    this.onWarpTargetSelected, // NEW
  });

  @override
  State<TacticalMap> createState() => _TacticalMapState();
}

class _TacticalMapState extends State<TacticalMap>
    with SingleTickerProviderStateMixin {
  bool _showStarfield = true;
  bool _effectsEnabled = true;
  int? _selectedTargetId; // NEW: Track selected warp target

  late final AnimationController _starAnimController;
  final TransformationController _transformController =
      TransformationController();

  @override
  void initState() {
    super.initState();
    _starAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _starAnimController.dispose();
    _transformController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TacticalMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSector.id != widget.currentSector.id) {
      _transformController.value = Matrix4.identity();
      _selectedTargetId = null; // Reset target on sector change
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final connectedSectors = widget.allSectors
        .where((s) => widget.currentSector.warpRoutes.contains(s.id))
        .toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // --- HEADER ---
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.gps_fixed_rounded, size: 16, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  'TACTICAL DISPLAY',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.primary,
                        letterSpacing: 1.5,
                      ),
                ),
                const Spacer(),
                // IMPROVEMENT: Clean, compact Effects Switch
                Text('FX',
                    style: TextStyle(
                        color: _effectsEnabled
                            ? cs.primary
                            : cs.onSurface.withAlpha(150),
                        fontSize: 10,
                        fontWeight: FontWeight.bold)),
                // Wrapping in Transform.scale shrinks the visual size
                Transform.scale(
                  scale:
                      0.5, // Adjust this number to make it smaller/larger (1.0 is default)
                  child: Switch(
                    value: _effectsEnabled,
                    onChanged: (v) => setState(() => _effectsEnabled = v),
                    activeColor: cs.primary,
                    activeTrackColor: cs.primary.withValues(alpha: 0.5),
                    inactiveThumbColor: cs.onSurface.withValues(alpha: 0.5),
                    inactiveTrackColor: cs.onSurface.withValues(alpha: 0.2),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.center_focus_strong_rounded, size: 16),
                  onPressed: () =>
                      _transformController.value = Matrix4.identity(),
                  tooltip: 'Refocus',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                  ),
                ),
                IconButton(
                  icon: Icon(
                      _showStarfield
                          ? Icons.stars_rounded
                          : Icons.stars_outlined,
                      size: 16),
                  onPressed: () =>
                      setState(() => _showStarfield = !_showStarfield),
                  tooltip: 'Starfield',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    foregroundColor: cs.primary,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(28, 28),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: cs.tertiary.withAlpha(50)),
                  ),
                  child: Text(
                    'SEC ${widget.currentSector.id} // ${widget.currentSector.quadrant}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: cs.tertiary,
                          fontFamily: 'monospace',
                        ),
                  ),
                ),
              ],
            ),
          ),
          // --- MAP ---
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final stackSize =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return Stack(
                  children: [
                    if (_showStarfield)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: CustomPaint(
                            painter: StarfieldPainter(
                              size: stackSize,
                              animation: _starAnimController,
                            ),
                          ),
                        ),
                      ),
                    InteractiveViewer(
                      transformationController: _transformController,
                      minScale: 0.5,
                      maxScale: 3.0,
                      boundaryMargin: const EdgeInsets.all(500),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final canvasSize =
                              Size(constraints.maxWidth, constraints.maxHeight);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapUp: (details) {
                              // Convert tap to canvas space
                              final transform =
                                  _transformController.value.clone()..invert();
                              final canvasPos = MatrixUtils.transformPoint(
                                  transform, details.localPosition);

                              // Check if a node was tapped (using same logic as painter)
                              final center = Offset(
                                  canvasSize.width / 2, canvasSize.height / 2);
                              final effective =
                                  math.min(canvasSize.width, canvasSize.height);
                              final radius = effective * 0.38;
                              const maxPerRing = 8;
                              final totalNodes = connectedSectors.length;
                              final totalRings =
                                  ((totalNodes - 1) ~/ maxPerRing) + 1;
                              final ringCount = totalRings.clamp(2, 5);

                              double ringR(int index) {
                                final minR = radius * 0.35;
                                final maxR = radius * 0.92;
                                if (ringCount <= 1) return (minR + maxR) / 2;
                                return minR +
                                    (index / (ringCount - 1)) * (maxR - minR);
                              }

                              int? tappedId;
                              for (var i = 0;
                                  i < connectedSectors.length;
                                  i++) {
                                final ringIndex = i ~/ maxPerRing;
                                final posInRing = i % maxPerRing;
                                final ringStart = ringIndex * maxPerRing;
                                final ringEnd = (ringStart + maxPerRing) >
                                        connectedSectors.length
                                    ? connectedSectors.length
                                    : ringStart + maxPerRing;
                                final countInRing = ringEnd - ringStart;
                                final angle =
                                    (posInRing / countInRing) * 2 * math.pi -
                                        math.pi / 2;
                                final r =
                                    ringR(ringIndex.clamp(0, ringCount - 1));
                                final pos = center +
                                    Offset(r * math.cos(angle),
                                        r * math.sin(angle));

                                final dist = (canvasPos - pos).distance;
                                if (dist <= 14.0) {
                                  // tap target radius
                                  tappedId = connectedSectors[i].id;
                                  break;
                                }
                              }

                              setState(() {
                                _selectedTargetId = tappedId;
                              });
                              if (tappedId != null) {
                                widget.onWarpTargetSelected?.call(tappedId);
                              }
                            },
                            child: CustomPaint(
                              size: canvasSize,
                              painter: _TacticalMapPainter(
                                animation: _effectsEnabled
                                    ? _starAnimController
                                    : null,
                                currentSector: widget.currentSector,
                                connectedSectors: connectedSectors,
                                allSectors: widget.allSectors,
                                playerSectorId: widget.player.currentSectorId,
                                canvasSize: canvasSize,
                                npcs: widget.npcs,
                                effectsEnabled: _effectsEnabled,
                                selectedTargetId: _selectedTargetId,
                              ),
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
          // --- LEGEND ---
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [
                _LegendItem(color: const Color(0xFF00FF41), label: 'YOU'),
                _LegendItem(color: const Color(0xFF00FFFF), label: 'WARP'),
                _LegendItem(color: Colors.amber.shade300, label: 'PORT'),
                _LegendItem(color: Colors.blue, label: 'TRADER'),
                _LegendItem(color: Colors.red, label: 'DURAN'),
                _LegendItem(color: Colors.teal, label: 'VINARI'),
                _LegendItem(
                    color: Colors.pinkAccent,
                    label: 'PIRATE'), // IMPROVEMENT: Pink to be visible
                _LegendItem(color: Colors.orange, label: 'HAZARD'),
                _LegendItem(color: Colors.deepPurpleAccent, label: 'HARDWARE'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TacticalMapPainter extends CustomPainter {
  final Sector currentSector;
  final List<Sector> connectedSectors;
  final List<Sector> allSectors;
  final int playerSectorId;
  final Size canvasSize;
  final List<NpcShip> npcs;
  final Animation<double>? animation;
  final bool effectsEnabled;
  final int? selectedTargetId; // NEW

  _TacticalMapPainter({
    required this.currentSector,
    required this.connectedSectors,
    required this.allSectors,
    required this.playerSectorId,
    required this.canvasSize,
    required this.npcs,
    this.animation,
    this.effectsEnabled = false,
    this.selectedTargetId,
  }) : super(repaint: animation);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final effective = math.min(canvasSize.width, canvasSize.height);
    final radius = effective * 0.38;
    final animValue = animation?.value ?? 0;

    // --- Grid & Crosshairs ---
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var r = 0.2; r <= 1.0; r += 0.2) {
      canvas.drawCircle(center, radius * r, gridPaint);
    }

    // IMPROVEMENT: Crosshairs
    canvas.drawLine(Offset(center.dx - radius * 1.1, center.dy),
        Offset(center.dx + radius * 1.1, center.dy), gridPaint);
    canvas.drawLine(Offset(center.dx, center.dy - radius * 1.1),
        Offset(center.dx, center.dy + radius * 1.1), gridPaint);

    // IMPROVEMENT: Radar Sweep Effect
    if (effectsEnabled) {
      final sweepAngle = animValue * 2 * math.pi;

      // Sweep Gradient Cone
      final sweepPaint = Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: math.pi / 4, // 45 degree cone
          colors: [
            const Color(0xFF00FFFF).withOpacity(0.0),
            const Color(0xFF00FFFF).withOpacity(0.15),
          ],
          transform: GradientRotation(sweepAngle - math.pi / 4),
        ).createShader(Rect.fromCircle(center: center, radius: radius * 0.92));

      canvas.drawCircle(center, radius * 0.92, sweepPaint);

      // Sweep Line
      final sweepLinePaint = Paint()
        ..color = const Color(0xFF00FFFF).withOpacity(0.6)
        ..strokeWidth = 2;
      canvas.drawLine(
          center,
          center +
              Offset(radius * 0.92 * math.cos(sweepAngle),
                  radius * 0.92 * math.sin(sweepAngle)),
          sweepLinePaint);

      // Ping ripple
      for (var i = 0; i < 3; i++) {
        final phase = ((animValue + i * 0.33) % 1.0);
        final r = phase * radius * 1.1;
        final alpha = 0.3 * (1 - phase);
        final pingPaint = Paint()
          ..color = const Color(0xFF00FFFF).withValues(alpha: alpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(center, r, pingPaint);
      }
    }

    // Build set of 1-hop sector ids
    final oneHopIds = <int>{};
    for (final s in connectedSectors) {
      oneHopIds.add(s.id);
    }

    final sectorPositions = <int, Offset>{};

    const int maxPerRing = 8;
    final totalNodes = connectedSectors.length;
    final totalRings = ((totalNodes - 1) ~/ maxPerRing) + 1;
    final ringCount = totalRings.clamp(2, 5);

    double ringR(int index) {
      final minR = radius * 0.35;
      final maxR = radius * 0.92;
      if (ringCount <= 1) return (minR + maxR) / 2;
      return minR + (index / (ringCount - 1)) * (maxR - minR);
    }

    final allNodes = <_NodeInfo>[];
    for (final s in connectedSectors) {
      allNodes.add(_NodeInfo(s, hop: 1));
    }

    for (var i = 0; i < allNodes.length; i++) {
      final ringIndex = i ~/ maxPerRing;
      final posInRing = i % maxPerRing;
      final ringStart = ringIndex * maxPerRing;
      final ringEnd = (ringStart + maxPerRing) > allNodes.length
          ? allNodes.length
          : ringStart + maxPerRing;
      final countInRing = ringEnd - ringStart;
      final angle = (posInRing / countInRing) * 2 * math.pi - math.pi / 2;
      final r = ringR(ringIndex.clamp(0, ringCount - 1));
      sectorPositions[allNodes[i].sector.id] =
          center + Offset(r * math.cos(angle), r * math.sin(angle));
    }

    // Inter-1-hop connections
    final hopLinePaint = Paint()
      ..color = const Color(0xFF00FFFF).withValues(alpha: 0.12)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < connectedSectors.length; i++) {
      for (var j = i + 1; j < connectedSectors.length; j++) {
        final a = connectedSectors[i];
        final b = connectedSectors[j];
        if (a.warpRoutes.contains(b.id)) {
          final posA = sectorPositions[a.id];
          final posB = sectorPositions[b.id];
          if (posA != null && posB != null) {
            canvas.drawLine(posA, posB, hopLinePaint);
          }
        }
      }
    }

    // Center to 1-hop lines
    for (final sector in connectedSectors) {
      final pos = sectorPositions[sector.id];
      if (pos != null) {
        final isTarget = sector.id == selectedTargetId;

        // IMPROVEMENT: Highlight selected target warp line
        final linePaint = Paint()
          ..color = isTarget
              ? const Color(0xFF00FF41).withOpacity(0.8)
              : const Color(0xFF00FFFF).withValues(alpha: 0.3)
          ..strokeWidth = isTarget ? 3.0 : 1.5
          ..style = PaintingStyle.stroke;

        canvas.drawLine(center, pos, linePaint);

        // Draw movement indicator chevrons if target selected
        if (isTarget && effectsEnabled) {
          final midPoint =
              Offset((center.dx + pos.dx) / 2, (center.dy + pos.dy) / 2);
          final tp = TextPainter(
            text: TextSpan(
                text: '>> WARP <<',
                style: TextStyle(
                    color: const Color(0xFF00FF41),
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace')),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, midPoint - Offset(tp.width / 2, tp.height / 2));
        }
      }
    }

    // Draw 1-hop sector nodes
    for (final sector in connectedSectors) {
      final pos = sectorPositions[sector.id];
      if (pos != null) {
        _drawSectorNode(canvas, pos, sector, false);
      }
    }

    // Draw current sector (center)
    _drawSectorNode(canvas, center, currentSector, true);

    // Data scroll
    if (effectsEnabled) {
      _drawDataScroll(canvas, size, animValue);
    }
  }

  void _drawDataScroll(Canvas canvas, Size size, double animValue) {
    final scrollLines = _dataScrollLines;
    final offset =
        (animValue * scrollLines.length * 2).toInt() % scrollLines.length;
    final lineHeight = 10.0;
    final leftX = 4.0;
    final rightX = size.width - 80.0;
    for (var i = 0; i < 8; i++) {
      final idx = (offset + i) % scrollLines.length;
      final y = size.height - (i + 1) * lineHeight;
      final alpha = (1 - i / 8) * 0.3;
      final tp = TextPainter(
        text: TextSpan(
          text: scrollLines[idx],
          style: TextStyle(
            color: const Color(0xFF00FF41).withValues(alpha: alpha),
            fontSize: 8,
            fontFamily: 'monospace',
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(leftX, y));
      tp.paint(canvas, Offset(rightX, y));
    }
  }

  static const List<String> _dataScrollLines = [
    'SIG_SCAN: OK',
    'WARP: STABLE',
    'LINK: ACTIVE',
    'PWR: 98.2%',
    'SHIELD: NOM',
    'TGT: ACQ',
    'SYS: ONLINE',
    'SCAN: IDLE',
    'RNG: 1.2AU',
    'DRF: 0.03',
    'VEC: 284.7',
    'ALT: NOM',
    'BEACON: LOCK',
    'NAV: SYNC',
    'COMM: OPEN',
    'SENSOR: ARRAY',
  ];

  void _drawSectorNode(
      Canvas canvas, Offset pos, Sector sector, bool isCurrent) {
    final nodeRadius = isCurrent ? 18.0 : 12.0;
    final isTarget = !isCurrent && sector.id == selectedTargetId;

    Color nodeColor;
    Color borderColor;

    if (isCurrent) {
      nodeColor = const Color(0xFF00FF41);
      borderColor = const Color(0xFF00FF41);
    } else if (sector.port?.isHardwareEmporium == true) {
      nodeColor = Colors.deepPurpleAccent;
      borderColor = Colors.deepPurpleAccent;
    } else if (sector.hasPort) {
      nodeColor = Colors.amber.shade300;
      borderColor = Colors.amber.shade300;
    } else {
      nodeColor = const Color(0xFF00FFFF);
      borderColor = const Color(0xFF00FFFF);
    }

    // Highlight target node
    if (isTarget) {
      borderColor = const Color(0xFF00FF41);
      final glowPaint = Paint()
        ..color = const Color(0xFF00FF41).withOpacity(0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, nodeRadius + 8, glowPaint);
    } else if (isCurrent) {
      final glowPaint = Paint()
        ..color = nodeColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(pos, nodeRadius + 8, glowPaint);
    }

    final nodePaint = Paint()
      ..color = nodeColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, nodeRadius, nodePaint);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = isCurrent || isTarget ? 3 : 2;
    canvas.drawCircle(pos, nodeRadius, borderPaint);

    if (sector.hasPort) {
      final portColor = sector.port?.isHardwareEmporium == true
          ? Colors.deepPurpleAccent
          : Colors.amber.shade300;
      final portPaint = Paint()
        ..color = portColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        pos + Offset(nodeRadius * 0.7, -nodeRadius * 0.7),
        4,
        portPaint,
      );
    }

    if (sector.navHaz || sector.anomaly != null) {
      final hazardPaint = Paint()
        ..color = Colors.orange
        ..style = PaintingStyle.fill;
      final path = Path()
        ..moveTo(pos.dx, pos.dy - nodeRadius * 0.6)
        ..lineTo(pos.dx + nodeRadius * 0.5, pos.dy)
        ..lineTo(pos.dx, pos.dy + nodeRadius * 0.6)
        ..lineTo(pos.dx - nodeRadius * 0.5, pos.dy)
        ..close();
      canvas.drawPath(path, hazardPaint);
    }

    // Draw live NPC dots per sector
    final npcsHere = npcs
        .where((n) => n.currentSectorId == sector.id && !n.isDestroyed)
        .toList();

    int traderCount = 0;
    int duranCount = 0;
    int vinariCount = 0;
    int pirateCount = 0;
    for (final npc in npcsHere) {
      switch (npc.faction) {
        case FactionClass.trader:
          traderCount++;
        case FactionClass.duran:
          duranCount++;
        case FactionClass.vinari:
          vinariCount++;
        case FactionClass.pirate:
          pirateCount++;
      }
    }

    int dotIndex = 0;

    void drawDots(int count, Color color) {
      for (int i = 0; i < count && dotIndex < _dotOffsets.length; i++) {
        final dotPos = pos + _dotOffsets[dotIndex];
        canvas.drawCircle(
          dotPos,
          3,
          Paint()
            ..color = color
            ..style = PaintingStyle.fill,
        );
        dotIndex++;
      }
    }

    drawDots(traderCount, Colors.blue);
    drawDots(duranCount, Colors.red);
    drawDots(vinariCount, Colors.teal);
    drawDots(
        pirateCount,
        Colors
            .pinkAccent); // IMPROVEMENT: Changed from Colors.black to be visible

    final textPainter = TextPainter(
      text: TextSpan(
        text: sector.id.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      pos - Offset(textPainter.width / 2, textPainter.height / 2),
    );
  }

  static const List<Offset> _dotOffsets = [
    Offset(-7, 7),
    Offset(-7, -7),
    Offset(7, 7),
    Offset(7, -7),
    Offset(-10, 0),
    Offset(10, 0),
    Offset(0, -10),
    Offset(0, 10),
  ];

  @override
  bool shouldRepaint(covariant _TacticalMapPainter oldDelegate) {
    if (oldDelegate.currentSector.id != currentSector.id ||
        oldDelegate.canvasSize != canvasSize ||
        oldDelegate.connectedSectors.length != connectedSectors.length ||
        oldDelegate.npcs.length != npcs.length ||
        oldDelegate.selectedTargetId != selectedTargetId) {
      return true;
    }
    if (effectsEnabled || oldDelegate.effectsEnabled) {
      return oldDelegate.animation?.value != animation?.value ||
          oldDelegate.effectsEnabled != effectsEnabled;
    }
    return false;
  }
}

class _NodeInfo {
  final Sector sector;
  final int hop;

  const _NodeInfo(this.sector, {required this.hop});
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6),
                blurRadius: 4,
              ),
            ],
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            fontFamily: 'monospace',
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(200),
          ),
        ),
      ],
    );
  }
}
