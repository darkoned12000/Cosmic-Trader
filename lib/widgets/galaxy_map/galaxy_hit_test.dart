import 'package:flutter/material.dart';

/// Responsible for determining which sector (if any)
/// the user clicked on.
///
/// GalaxyMap should never perform hit-testing itself.
/// It simply asks this class.
///
/// This keeps all coordinate calculations in one place.
class GalaxyHitTester {
  const GalaxyHitTester({
    required this.nodeRadius,
  });

  final double nodeRadius;

  /// Returns the id of the clicked sector or null.
  int? hitTest({
    required Offset canvasPosition,
    required Map<int, Offset> sectorPositions,
  }) {
    double closestDistance = double.infinity;
    int? closestSector;

    for (final entry in sectorPositions.entries) {
      final distance = (entry.value - canvasPosition).distance;

      if (distance <= nodeRadius && distance < closestDistance) {
        closestDistance = distance;
        closestSector = entry.key;
      }
    }

    return closestSector;
  }
}
