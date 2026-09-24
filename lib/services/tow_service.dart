import 'dart:math' as math;

import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';

/// A reachable Emergency Tow destination.
class TowPlan {
  final int targetSectorId;
  final String targetSectorName;
  final String targetPortName;
  final int hops;

  /// True when the destination can actually refuel the player. Hardware
  /// Emporiums are the only normal refuel stations; other ports are fallback
  /// emergency stops only.
  final bool isRefuelStation;

  const TowPlan({
    required this.targetSectorId,
    required this.targetSectorName,
    required this.targetPortName,
    required this.hops,
    required this.isRefuelStation,
  });
}

/// Result of calling an Emergency Tow.
class TowResult {
  final Player player;
  final int creditsSpent;
  final int hops;
  final String targetName;
  final bool arrivedAtRefuelStation;

  const TowResult({
    required this.player,
    required this.creditsSpent,
    required this.hops,
    required this.targetName,
    required this.arrivedAtRefuelStation,
  });
}

/// Emergency recovery for a stranded ship.
///
/// Refueling is intentionally scarce — Hardware Emporium only — so this
/// service exists to prevent a hard dead-end: a player who runs out of energy
/// with no Solar Array installed still has a paid, distance-scaled recovery
/// route to the nearest refuel-capable port.
class TowService {
  TowService._();

  /// Base call-out fee for an Emergency Tow.
  static const int baseTowCredits = 2500;

  /// Additional credits charged per warp hop to the destination.
  static const int towCreditsPerHop = 750;

  /// Emergency energy reserve granted on arrival, as a percent of tank size.
  static const int emergencyEnergyPercent = 10;

  /// True when the player cannot pay for a warp right now.
  static bool needsTow(Player player) {
    return !player.hasEnergy(EnergyService.warpCost(player));
  }

  /// Finds the nearest usable tow destination.
  ///
  /// Hardware Emporiums are preferred because they can refuel. If none are
  /// reachable, falls back to the nearest port so the ship is still recovered
  /// instead of being stuck forever.
  static TowPlan? findTowPlan(List<Sector> sectors, int currentSectorId) {
    if (sectors.isEmpty) return null;

    final refuelSectorId = PathfindingService.findNearestWhere(
      sectors,
      currentSectorId,
      (s) => s.hasPort && s.port != null && s.port!.isHardwareEmporium,
    );

    final fallbackSectorId = PathfindingService.findNearestWhere(
      sectors,
      currentSectorId,
      (s) => s.hasPort && s.port != null,
    );

    final targetSectorId = refuelSectorId ?? fallbackSectorId;
    if (targetSectorId == null) return null;

    final targetSector = sectors.firstWhere(
      (s) => s.id == targetSectorId,
      orElse: () => sectors[currentSectorId - 1],
    );
    final path =
        PathfindingService.findPath(sectors, currentSectorId, targetSectorId);
    if (path == null) return null;

    return TowPlan(
      targetSectorId: targetSectorId,
      targetSectorName: targetSector.name,
      targetPortName: targetSector.port?.name ?? 'Unknown Port',
      hops: math.max(1, path.length - 1),
      isRefuelStation: refuelSectorId != null,
    );
  }

  /// Credits charged for [plan]. Never exceeds the player's credits so the
  /// tow stays available even when nearly broke.
  static int towCost(Player player, TowPlan plan) {
    final raw = baseTowCredits + towCreditsPerHop * plan.hops;
    return math.min(raw, player.credits);
  }

  /// Emergency energy granted on arrival so the ship can act after the tow.
  static int emergencyEnergy(Player player) {
    final percentReserve =
        (player.maxEnergy * emergencyEnergyPercent / 100).round();
    final twoWarps = EnergyService.warpCost(player) * 2;
    return math.max(1, math.max(percentReserve, twoWarps));
  }

  /// Performs the tow: pay, move to the destination, retract the array, and
  /// receive enough emergency energy to operate once there.
  static TowResult tow(Player player, TowPlan plan) {
    final creditsSpent = towCost(player, plan);

    final updated = player
        .copyWith(
          currentSectorId: plan.targetSectorId,
          credits: player.credits - creditsSpent,
          solarArrayDeployed: false,
        )
        .refuelEnergy(emergencyEnergy(player));

    return TowResult(
      player: updated,
      creditsSpent: creditsSpent,
      hops: plan.hops,
      targetName: plan.targetSectorName,
      arrivedAtRefuelStation: plan.isRefuelStation,
    );
  }
}
