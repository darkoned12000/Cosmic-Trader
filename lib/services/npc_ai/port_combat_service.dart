import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/port_defense_config.dart';

/// Result of a port combat encounter.
class PortCombatResult {
  final bool portSurrendered;
  final bool portDestroyed;
  final bool attackerDefeated;
  final int damageToPort;
  final int damageToAttacker;
  final Port updatedPort;
  final Player? updatedPlayer;
  final NpcShip? updatedNpc;
  final String
      outcome; // "continue", "surrender", "destroyed", "attackerDefeated"

  const PortCombatResult({
    required this.portSurrendered,
    required this.portDestroyed,
    required this.attackerDefeated,
    required this.damageToPort,
    required this.damageToAttacker,
    required this.updatedPort,
    this.updatedPlayer,
    this.updatedNpc,
    required this.outcome,
  });
}

/// Handles port combat resolution.
class PortCombatService {
  static final math.Random _rng = math.Random();

  /// Calculate port firepower based on defense level.
  static int calculatePortFirepower(Port port) {
    return PortDefenseConfig.defenseStats(port.defenseLevel).firepower;
  }

  /// Calculate attacker firepower (player or NPC).
  static int calculateAttackerFirepower(Player player) {
    return player.totalWeaponPower * 50;
  }

  static int calculateNpcFirepower(NpcShip npc) {
    return npc.totalWeaponPower * 50;
  }

  /// Resolve one round of port combat (player attacking).
  static PortCombatResult resolvePortAttack(
    Player attacker,
    Port port,
    String mode,
  ) {
    final portStats = PortDefenseConfig.defenseStats(port.defenseLevel);

    // Attacker fires
    final attackerPower = calculateAttackerFirepower(attacker);
    final portFirepower = calculatePortFirepower(port);

    final damageToPort = (attackerPower * (0.8 + _rng.nextDouble() * 0.4))
        .round()
        .clamp(1, 99999);
    final baseDamageToAttacker =
        (portFirepower * (0.8 + _rng.nextDouble() * 0.4))
            .round()
            .clamp(1, 99999);

    // Apply damage to port shields
    int remainingPortShields = port.currentShields - damageToPort;
    if (remainingPortShields < 0) remainingPortShields = 0;

    // Check port special abilities
    int bonusDamageToAttacker = 0;
    if (portStats.hasCounterAttack) {
      bonusDamageToAttacker = (portFirepower * 0.3).round();
    }
    int empDrainDamage = 0;
    if (portStats.hasEmpBurst) {
      empDrainDamage = (attacker.shields * portStats.empDrainPct).round();
    }

    int totalDamageToAttacker =
        baseDamageToAttacker + bonusDamageToAttacker + empDrainDamage;

    // Check if port can still defend (shields > 5%)
    final canDefend = remainingPortShields > port.captureThreshold;
    if (!canDefend) {
      totalDamageToAttacker = 0;
    }

    // Apply damage to attacker (shields first, then hull)
    var attackerShields = attacker.shields;
    var attackerHull = attacker.hull;

    if (totalDamageToAttacker > 0) {
      if (attackerShields > 0) {
        if (totalDamageToAttacker <= attackerShields) {
          attackerShields -= totalDamageToAttacker;
          totalDamageToAttacker = 0;
        } else {
          totalDamageToAttacker -= attackerShields;
          attackerShields = 0;
        }
      }
      if (totalDamageToAttacker > 0) {
        attackerHull =
            (attackerHull - totalDamageToAttacker).clamp(0, attacker.maxHull);
      }
    }

    // Determine outcome
    String outcome;
    bool portSurrendered = false;
    bool portDestroyed = false;
    bool attackerDefeated = false;

    if (attackerHull <= 0) {
      outcome = "attackerDefeated";
      attackerDefeated = true;
    } else if (remainingPortShields <= port.captureThreshold) {
      outcome = "surrender";
      portSurrendered = true;
    } else {
      outcome = "continue";
    }

    // Update port
    final updatedPort = port.copyWith(
      currentShields: remainingPortShields,
    );

    // Update player
    final updatedPlayer = attacker.copyWith(
      shields: attackerShields,
      hull: attackerHull,
    );

    return PortCombatResult(
      portSurrendered: portSurrendered,
      portDestroyed: portDestroyed,
      attackerDefeated: attackerDefeated,
      damageToPort: damageToPort,
      damageToAttacker: baseDamageToAttacker + bonusDamageToAttacker,
      updatedPort: updatedPort,
      updatedPlayer: updatedPlayer,
      outcome: outcome,
    );
  }

  /// Resolve one round of port combat (NPC attacking).
  static PortCombatResult resolveNpcPortAttack(
    NpcShip npc,
    Port port,
    String mode,
  ) {
    final portStats = PortDefenseConfig.defenseStats(port.defenseLevel);

    final npcPower = calculateNpcFirepower(npc);
    final portFirepower = calculatePortFirepower(port);

    final damageToPort =
        (npcPower * (0.8 + _rng.nextDouble() * 0.4)).round().clamp(1, 99999);
    final baseDamageToNpc = (portFirepower * (0.8 + _rng.nextDouble() * 0.4))
        .round()
        .clamp(1, 99999);

    int remainingPortShields = port.currentShields - damageToPort;
    if (remainingPortShields < 0) remainingPortShields = 0;

    int bonusDamageToNpc = 0;
    if (portStats.hasCounterAttack) {
      bonusDamageToNpc = (portFirepower * 0.3).round();
    }
    int empDrainDamage = 0;
    if (portStats.hasEmpBurst) {
      empDrainDamage = (npc.shields * portStats.empDrainPct).round();
    }

    int totalDamageToNpc = baseDamageToNpc + bonusDamageToNpc + empDrainDamage;

    final canDefend = remainingPortShields > port.captureThreshold;
    if (!canDefend) {
      totalDamageToNpc = 0;
    }

    var npcShields = npc.shields;
    var npcHull = npc.hull;

    if (totalDamageToNpc > 0) {
      if (npcShields > 0) {
        if (totalDamageToNpc <= npcShields) {
          npcShields -= totalDamageToNpc;
          totalDamageToNpc = 0;
        } else {
          totalDamageToNpc -= npcShields;
          npcShields = 0;
        }
      }
      if (totalDamageToNpc > 0) {
        npcHull = (npcHull - totalDamageToNpc).clamp(0, npc.maxHull);
      }
    }

    String outcome;
    bool portSurrendered = false;
    bool npcDefeated = false;

    if (npcHull <= 0) {
      outcome = "attackerDefeated";
      npcDefeated = true;
    } else if (remainingPortShields <= port.captureThreshold) {
      outcome = "surrender";
      portSurrendered = true;
    } else {
      outcome = "continue";
    }

    final updatedPort = port.copyWith(
      currentShields: remainingPortShields,
    );

    final updatedNpc = npc.copyWith(
      shields: npcShields,
      hull: npcHull,
    );

    return PortCombatResult(
      portSurrendered: portSurrendered,
      portDestroyed: false,
      attackerDefeated: npcDefeated,
      damageToPort: damageToPort,
      damageToAttacker: baseDamageToNpc + bonusDamageToNpc,
      updatedPort: updatedPort,
      updatedNpc: updatedNpc,
      outcome: outcome,
    );
  }

  /// Capture a port (transfer ownership).
  static Port capturePort(
    Port port,
    String newOwnerId,
    String? newOwnerFaction,
  ) {
    return port.copyWith(
      owner: newOwnerId,
      ownerFaction:
          newOwnerFaction != null ? _parseFactionClass(newOwnerFaction) : null,
      isUnderAttack: false,
      currentShields: port.maxShields,
      attackerId: null,
      attackMode: null,
    );
  }

  /// Destroy a port.
  static Port destroyPort(Port port) {
    return port.copyWith(
      isDestroyed: true,
      isUnderAttack: false,
      currentShields: 0,
      attackerId: null,
      attackMode: null,
    );
  }

  /// End combat with attacker retreat (port restores shields).
  static Port endCombatRetreat(Port port) {
    return port.copyWith(
      isUnderAttack: false,
      currentShields: port.maxShields,
      attackerId: null,
      attackMode: null,
    );
  }

  /// Initialize port shields to max (for new ports).
  static int initPortShields(int defenseLevel) {
    return PortDefenseConfig.defenseStats(defenseLevel).shieldCapacity;
  }

  static FactionClass? _parseFactionClass(String name) {
    try {
      return FactionClass.values.firstWhere(
        (f) => f.name == name,
      );
    } catch (_) {
      return null;
    }
  }
}
