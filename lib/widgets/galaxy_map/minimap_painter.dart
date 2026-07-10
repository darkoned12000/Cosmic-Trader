import 'dart:math';
import 'package:flutter/material.dart';

/// Paints the small overview map showing all local sector positions plus
/// a highlighted rectangle for the current viewport (what the main
/// GalaxyMapPainter is currently showing, given pan/zoom).
///
/// Painter only draws — it never performs hit testing and never updates
/// state.
class MinimapPainter extends CustomPainter {
  final Map<int, Offset> positions;
  final Set<int>? localSectorIds;
  final int currentSectorId;
  final int? selectedSectorId;
  final Matrix4 viewportTransform;
  final Size canvasSize;
  final ColorScheme colors;

  MinimapPainter({
    required this.positions,
    this.localSectorIds,
    required this.currentSectorId,
    this.selectedSectorId,
    required this.viewportTransform,
    required this.canvasSize,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (positions.isEmpty) return;

    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;
    for (final pos in positions.values) {
      minX = min(minX, pos.dx);
      maxX = max(maxX, pos.dx);
      minY = min(minY, pos.dy);
      maxY = max(maxY, pos.dy);
    }

    const padding = 10.0;
    final rangeX = (maxX - minX) + padding * 2;
    final rangeY = (maxY - minY) + padding * 2;
    final scale = min(size.width / rangeX, size.height / rangeY);

    Offset toMinimap(Offset pos) {
      return Offset(
          (pos.dx - minX + padding) * scale, (pos.dy - minY + padding) * scale);
    }

    final inverse = Matrix4.inverted(viewportTransform);
    final viewportCorners = [
      Offset.zero,
      Offset(canvasSize.width, 0),
      Offset(canvasSize.width, canvasSize.height),
      Offset(0, canvasSize.height),
    ].map((c) => toMinimap(MatrixUtils.transformPoint(inverse, c))).toList();

    final viewportPath = Path()..addPolygon(viewportCorners, true);
    canvas.drawPath(
        viewportPath,
        Paint()
          ..color = colors.primary.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        viewportPath,
        Paint()
          ..color = colors.primary.withValues(alpha: 0.5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1);

    for (final entry in positions.entries) {
      final id = entry.key;
      final pos = toMinimap(entry.value);
      final isCurrent = id == currentSectorId;
      final isSelected = id == selectedSectorId;

      final paint = Paint()
        ..color = isCurrent
            ? Colors.amber
            : isSelected
                ? colors.secondary
                : colors.onSurface.withValues(alpha: 0.5);
      canvas.drawCircle(pos, isCurrent ? 3 : 1.5, paint);
    }
  }

  @override
  bool shouldRepaint(MinimapPainter oldDelegate) => true;
}
