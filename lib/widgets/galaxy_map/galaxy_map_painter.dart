import 'dart:math';
import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/npc_ship.dart';
import 'package:tradewars_2050/data/models/sector.dart';

/// Paints the main galaxy map: warp-route connections, sector nodes (with
/// fog-of-war for unvisited sectors), the current-sector pulse animation,
/// port/planet indicators, and NPC presence dots.
///
/// Painter only draws — it never performs hit testing and never updates
/// state. Coordinate math for "what did the player click" lives in
/// GalaxyHitTester instead.
class GalaxyMapPainter extends CustomPainter {
  final List<Sector> sectors;
  final Map<int, Offset> positions;
  final Set<int>? localSectorIds;
  final int? selectedSectorId;
  final int currentSectorId;
  final String searchQuery;
  final ColorScheme colors;
  final double nodeRadius;
  final List<NpcShip> npcs;

  final double pulseValue;
  final Set<int> visitedSectors;
  final int fedSpaceEnd;

  GalaxyMapPainter({
    required this.sectors,
    required this.positions,
    this.localSectorIds,
    this.selectedSectorId,
    required this.currentSectorId,
    this.searchQuery = '',
    required this.colors,
    required this.nodeRadius,
    this.npcs = const [],
    required this.pulseValue,
    required this.visitedSectors,
    required this.fedSpaceEnd,
  });

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final dx = end.dx - start.dx;
    final dy = end.dy - start.dy;
    final totalDist = sqrt(dx * dx + dy * dy);
    if (totalDist == 0) return;
    final ux = dx / totalDist;
    final uy = dy / totalDist;
    var drawn = 0.0;
    while (drawn < totalDist) {
      final segEnd = min(drawn + dashLength, totalDist);
      canvas.drawLine(
        Offset(start.dx + ux * drawn, start.dy + uy * drawn),
        Offset(start.dx + ux * segEnd, start.dy + uy * segEnd),
        paint,
      );
      drawn = segEnd + gapLength;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (sectors.isEmpty) return;

    final drawnConnections = <String>{};

    // Draw connections
    for (final sector in sectors) {
      final startPos = positions[sector.id];
      if (startPos == null) continue;

      for (final warpId in sector.warpRoutes) {
        final endPos = positions[warpId];
        if (endPos == null) continue;

        final key = sector.id < warpId
            ? '${sector.id}-$warpId'
            : '$warpId-${sector.id}';
        if (drawnConnections.contains(key)) continue;
        drawnConnections.add(key);

        final isFedLane = sector.id <= fedSpaceEnd && warpId <= fedSpaceEnd;

        final paint = Paint()
          ..strokeWidth = isFedLane ? 2.0 : 1.0
          ..color = isFedLane
              ? colors.primary.withValues(alpha: 0.4)
              : colors.onSurface.withValues(alpha: 0.1);

        if (!isFedLane) {
          _drawDashedLine(canvas, startPos, endPos, paint);
        } else {
          canvas.drawLine(startPos, endPos, paint);
        }
      }
    }

    // Draw nodes
    for (final sector in sectors) {
      final pos = positions[sector.id];
      if (pos == null) continue;

      final isCurrent = sector.id == currentSectorId;
      final isSelected = sector.id == selectedSectorId;
      final isHighlighted = searchQuery.isNotEmpty &&
          (sector.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
              sector.id.toString().contains(searchQuery));

      final bool isVisited = visitedSectors.contains(sector.id);

      const currentSectorColor = Color(0xFFFFC107); // Amber stands out well
      final fedSpaceColor = colors.primary;
      final otherSectorColor = colors.onSurface.withValues(alpha: 0.4);
      final selectedColor = colors.secondary;
      final highlightColor = colors.secondaryContainer;

      if (!isVisited) {
        // Draw unexplored sector as a dim "?"
        final unknownPaint = Paint()
          ..color = colors.onSurface.withValues(alpha: 0.15);
        canvas.drawCircle(pos, nodeRadius, unknownPaint);

        final textPainter = TextPainter(
          text: TextSpan(
            text: '?',
            style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.3),
                fontSize: nodeRadius),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        textPainter.paint(
            canvas,
            Offset(pos.dx - textPainter.width / 2,
                pos.dy - textPainter.height / 2));
        continue; // Skip other drawing for unexplored sectors
      }

      Color nodeColor;
      if (isCurrent) {
        nodeColor = currentSectorColor;
      } else if (isSelected) {
        nodeColor = selectedColor;
      } else if (isHighlighted) {
        nodeColor = highlightColor;
      } else if (sector.id <= fedSpaceEnd) {
        nodeColor = fedSpaceColor;
      } else {
        nodeColor = otherSectorColor;
      }

      final paint = Paint()..color = nodeColor;
      canvas.drawCircle(pos, nodeRadius, paint);

      // Animated pulse on current sector
      if (isCurrent) {
        final pulseScale = 1.0 + 0.3 * sin(pulseValue * 2 * pi);
        final pulseAlpha = 0.3 + 0.2 * sin(pulseValue * 2 * pi);

        final pulsePaint = Paint()
          ..color = currentSectorColor.withValues(alpha: pulseAlpha)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(pos, nodeRadius * pulseScale + 8, pulsePaint);

        final pulseScale2 = 1.0 + 0.3 * sin(pulseValue * 2 * pi + pi);
        final pulseAlpha2 = 0.2 + 0.15 * sin(pulseValue * 2 * pi + pi);
        final pulsePaint2 = Paint()
          ..color = currentSectorColor.withValues(alpha: pulseAlpha2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawCircle(pos, nodeRadius * pulseScale2 + 14, pulsePaint2);
      }

      if (isSelected && !isCurrent) {
        final ringPaint = Paint()
          ..color = selectedColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        canvas.drawCircle(pos, nodeRadius + 4, ringPaint);
      }

      final textPainter = TextPainter(
        text: TextSpan(
          text: sector.id.toString(),
          style: TextStyle(
            color: Colors.white,
            fontSize: max(8.0, nodeRadius * 0.9),
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      );

      textPainter.layout();
      textPainter.paint(
          canvas,
          Offset(
              pos.dx - textPainter.width / 2, pos.dy - textPainter.height / 2));

      // Port indicator (diamond)
      if (sector.hasPort) {
        final portPaint = Paint()
          ..color = Colors.greenAccent
          ..style = PaintingStyle.fill;
        final portPos =
            Offset(pos.dx + nodeRadius + 4, pos.dy - nodeRadius - 4);
        final path = Path()
          ..moveTo(portPos.dx, portPos.dy - 4)
          ..lineTo(portPos.dx + 3, portPos.dy)
          ..lineTo(portPos.dx, portPos.dy + 4)
          ..lineTo(portPos.dx - 3, portPos.dy)
          ..close();
        canvas.drawPath(path, portPaint);
      }

      // Planet indicator (circled dot)
      if (sector.hasPlanet) {
        final planetPaint = Paint()
          ..color = Colors.cyanAccent
          ..style = PaintingStyle.fill;
        final planetPos =
            Offset(pos.dx - nodeRadius - 4, pos.dy - nodeRadius - 4);
        canvas.drawCircle(planetPos, 4, planetPaint);
        canvas.drawCircle(
          planetPos,
          6,
          Paint()
            ..color = Colors.cyanAccent.withValues(alpha: 0.4)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }

      // NPC presence dots
      final npcsHere = npcs
          .where((n) => n.currentSectorId == sector.id && !n.isDestroyed)
          .toList();
      if (npcsHere.isNotEmpty) {
        int dotIndex = 0;
        const dotOffsets = [
          Offset(4, -4),
          Offset(-4, -4),
          Offset(4, 4),
          Offset(-4, 4)
        ];
        for (final npc in npcsHere) {
          if (dotIndex >= dotOffsets.length) break;
          Color npcColor;
          switch (npc.faction) {
            case FactionClass.trader:
              npcColor = Colors.lightBlueAccent;
            case FactionClass.duran:
              npcColor = Colors.redAccent;
            case FactionClass.vinari:
              npcColor = Colors.tealAccent;
            case FactionClass.pirate:
              npcColor = Colors.orange;
          }
          final dotPos = pos + dotOffsets[dotIndex];
          canvas.drawCircle(
              dotPos,
              2.5,
              Paint()
                ..color = npcColor
                ..style = PaintingStyle.fill);
          dotIndex++;
        }
      }
    }
  }

  @override
  bool shouldRepaint(GalaxyMapPainter oldDelegate) {
    return oldDelegate.positions != positions ||
        oldDelegate.localSectorIds != localSectorIds ||
        oldDelegate.selectedSectorId != selectedSectorId ||
        oldDelegate.currentSectorId != currentSectorId ||
        oldDelegate.searchQuery != searchQuery ||
        oldDelegate.nodeRadius != nodeRadius ||
        oldDelegate.npcs.length != npcs.length ||
        oldDelegate.pulseValue != pulseValue ||
        oldDelegate.visitedSectors != visitedSectors;
  }
}
