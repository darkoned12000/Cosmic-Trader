import 'dart:math' as math;

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';

/// Central rules for the B1 turn → energy conversion.
///
/// Energy is the replacement for legacy turns: every costly ship action spends
/// energy, and it is restored by refueling at ports (manual refill). This class
/// owns the costs so gameplay surfaces stay thin and testable.
class EnergyService {
  EnergyService._();

  /// Base cost of a one-hop warp before engine-efficiency discounts.
  static const int baseWarpCost = 10;

  /// Energy spent by a manual planet scan.
  static const int planetScanCost = 4;

  /// Energy spent by a lightweight sector/interaction scan.
  static const int quickScanCost = 1;

  /// Credits charged per unit of energy when refueling at a port.
  static const int refuelCreditsPerUnit = 1;

  /// Installed-module key for the Solar Array (see `hardware_data.dart`).
  static const String solarArrayModuleId = 'solarArray';

  /// Energy recovered per game tick for each Solar Array module level.
  static const int solarArrayRegenPerLevelPerTick = 2;

  /// Returns the player's equipped engine, defaulting to the starter engine.
  static EngineType engineFor(Player player) {
    return EngineType.values.firstWhere(
      (e) => e.name == player.engineEquipment,
      orElse: () => EngineType.juryRiggedFusion,
    );
  }

  /// Energy required to warp [hops] sectors with the player's current engine.
  ///
  /// Cost scales with distance and is reduced by engine efficiency, so
  /// efficient engines travel further for the same pool.
  static int warpCost(Player player, {int hops = 1}) {
    final safeHops = hops < 1 ? 1 : hops;
    final efficiency = math.max(
        1, engineFor(player).efficiencyAtLevel(player.engineEquipmentLevel));
    final raw = (baseWarpCost * safeHops / efficiency).ceil();
    return raw < 1 ? 1 : raw;
  }

  /// Energy required for an NPC to warp [hops] sectors.
  ///
  /// NPCs carry only an engine *level* (no engine type name like players),
  /// so efficiency is the level itself: a level-1 NPC pays the full
  /// [baseWarpCost] per hop, matching the player starter rate.
  static int npcWarpCost(NpcShip npc, {int hops = 1}) {
    final safeHops = hops < 1 ? 1 : hops;
    final efficiency = math.max(1, npc.engineEquipmentLevel);
    final raw = (baseWarpCost * safeHops / efficiency).ceil();
    return raw < 1 ? 1 : raw;
  }

  /// True when [npc] can pay for a warp of [hops] sectors right now.
  static bool npcCanWarp(NpcShip npc, {int hops = 1}) =>
      npc.hasEnergy(npcWarpCost(npc, hops: hops));

  /// Missing NPC energy units before [NpcShip.maxEnergy] is reached.
  static int npcMissingEnergy(NpcShip npc) {
    final missing = npc.maxEnergy - npc.energy;
    return missing < 0 ? 0 : missing;
  }

  /// Credits required for [npc] to buy [units] of energy.
  static int npcRefuelCost(NpcShip npc, {int? units}) {
    final requested = units ?? npcMissingEnergy(npc);
    final amount = requested < 0 ? 0 : requested;
    return amount * refuelCreditsPerUnit;
  }

  /// Energy recovered per tick for an NPC Solar Array level.
  static int npcSolarRechargePerTick(NpcShip npc) =>
      (npc.solarArrayLevel < 0 ? 0 : npc.solarArrayLevel) *
      solarArrayRegenPerLevelPerTick;

  /// Applies one tick of NPC Solar Array regeneration. Returns the NPC
  /// unchanged when no array is installed/deployed or the tank is full.
  static ({NpcShip npc, int unitsAdded}) npcSolarRecharge(NpcShip npc) {
    final units = npcSolarRechargePerTick(npc);
    if (units <= 0 || !npc.solarArrayDeployed || npc.energy >= npc.maxEnergy) {
      return (npc: npc, unitsAdded: 0);
    }
    final missing = npcMissingEnergy(npc);
    final unitsAdded = units > missing ? missing : units;
    return (npc: npc.refuelEnergy(unitsAdded), unitsAdded: unitsAdded);
  }

  /// Returns a refueled NPC and the credits spent, clamped by credits and
  /// remaining tank capacity.
  static ({NpcShip npc, int creditsSpent, int unitsAdded}) npcRefuel(
    NpcShip npc, {
    int? units,
  }) {
    final affordableUnits = refuelCreditsPerUnit <= 0
        ? npcMissingEnergy(npc)
        : (npc.credits / refuelCreditsPerUnit).floor();
    final requested = units ?? npcMissingEnergy(npc);
    final cappedMissing = math.min(requested, npcMissingEnergy(npc));
    final unitsAdded = math.max(0, math.min(cappedMissing, affordableUnits));
    final creditsSpent = unitsAdded * refuelCreditsPerUnit;
    final refueled = npc
        .refuelEnergy(unitsAdded)
        .copyWith(credits: npc.credits - creditsSpent);
    return (npc: refueled, creditsSpent: creditsSpent, unitsAdded: unitsAdded);
  }

  /// Emergency reserve granted to a stranded NPC (mirrors TowService for
  /// players): enough to operate once recovered.
  static int npcEmergencyEnergy(NpcShip npc) {
    final percentReserve = (npc.maxEnergy * 10 / 100).round();
    final twoWarps = npcWarpCost(npc) * 2;
    return math.max(1, math.max(percentReserve, twoWarps));
  }

  /// True when a warp of [hops] sectors can be paid for right now.
  static bool canWarp(Player player, {int hops = 1}) =>
      player.hasEnergy(warpCost(player, hops: hops));

  /// True when a manual planet scan can be paid for right now.
  static bool canScanPlanet(Player player) => player.hasEnergy(planetScanCost);

  /// True when a lightweight scan can be paid for right now.
  static bool canQuickScan(Player player) => player.hasEnergy(quickScanCost);

  /// Missing energy units before [Player.maxEnergy] is reached.
  static int missingEnergy(Player player) {
    final missing = player.maxEnergy - player.energy;
    return missing < 0 ? 0 : missing;
  }

  /// Credits required to buy [units] of energy (defaults to a full tank).
  static int refuelCost(Player player, {int? units}) {
    final requested = units ?? missingEnergy(player);
    final amount = requested < 0 ? 0 : requested;
    return amount * refuelCreditsPerUnit;
  }

  /// Installed Solar Array level (0 when not equipped).
  static int solarArrayLevel(Player player) {
    final level = player.installedModules[solarArrayModuleId] ?? 0;
    return level < 0 ? 0 : level;
  }

  /// Energy recovered per tick from the installed Solar Array.
  static int solarRechargePerTick(Player player) =>
      solarArrayLevel(player) * solarArrayRegenPerLevelPerTick;

  /// Applies one tick of Solar Array regeneration.
  ///
  /// Returns the player unchanged when no array is installed, the array is not
  /// deployed, or the tank is already full; clamps partial ticks to capacity.
  /// True when the ship is allowed to move (array retracted).
  static bool canMove(Player player) => player.canMove;

  /// Returns a player toggled between deploying and retracting the array.
  static Player setSolarArrayDeployed(Player player, bool deployed) =>
      player.copyWith(solarArrayDeployed: deployed);

  static ({Player player, int unitsAdded}) solarRecharge(Player player) {
    final units = solarRechargePerTick(player);
    if (units <= 0 ||
        !player.solarArrayDeployed ||
        player.energy >= player.maxEnergy) {
      return (player: player, unitsAdded: 0);
    }

    final missing = missingEnergy(player);
    final unitsAdded = units > missing ? missing : units;
    return (player: player.refuelEnergy(unitsAdded), unitsAdded: unitsAdded);
  }

  /// Returns a refueled player and the credits spent, clamped by both credits
  /// and remaining tank capacity.
  static ({Player player, int creditsSpent, int unitsAdded}) refuel(
    Player player, {
    int? units,
  }) {
    final affordableUnits = refuelCreditsPerUnit <= 0
        ? missingEnergy(player)
        : (player.credits / refuelCreditsPerUnit).floor();
    final requested = units ?? missingEnergy(player);
    final cappedMissing = math.min(requested, missingEnergy(player));
    final unitsAdded = math.max(0, math.min(cappedMissing, affordableUnits));
    final creditsSpent = unitsAdded * refuelCreditsPerUnit;

    final refueled = player
        .refuelEnergy(unitsAdded)
        .copyWith(credits: player.credits - creditsSpent);

    return (
      player: refueled,
      creditsSpent: creditsSpent,
      unitsAdded: unitsAdded,
    );
  }
}
