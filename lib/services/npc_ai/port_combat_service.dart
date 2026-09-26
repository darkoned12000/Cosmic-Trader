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
///
/// NOTE on [mode] ("capture"/"destroy"): it is intentionally NOT read by
/// the resolution math — a siege round plays identically either way. The
/// caller applies the distinction after the fact (capture vs destroy the
/// port on surrender). Likewise [PortCombatResult.portDestroyed] is always
/// false out of here: destruction is the caller's decision, not the
/// round's. Both are post-siege labels, kept on the result for callers.
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

  /// Shared siege-round core. Both attacker flavors run this exact math
  /// (previously duplicated per type — balance changes apply once here).
  /// Returns raw round numbers; callers wrap them into Player/NpcShip.
  static ({
    int damageToPort,
    int baseDamageToAttacker,
    int bonusDamageToAttacker,
    int remainingPortShields,
    int attackerShields,
    int attackerHull,
    bool surrendered,
    bool attackerDefeated,
    String outcome,
  }) resolveRound({
    required int attackerPower,
    required int attackerShields,
    required int attackerHull,
    required int attackerMaxHull,
    required Port port,
  }) {
    final portStats = PortDefenseConfig.defenseStats(port.defenseLevel);
    final portFirepower = calculatePortFirepower(port);

    final damageToPort = (attackerPower * (0.8 + _rng.nextDouble() * 0.4))
        .round()
        .clamp(1, 99999);
    final baseDamageToAttacker =
        (portFirepower * (0.8 + _rng.nextDouble() * 0.4))
            .round()
            .clamp(1, 99999);

    int remainingPortShields = port.currentShields - damageToPort;
    if (remainingPortShields < 0) remainingPortShields = 0;

    int bonusDamageToAttacker = 0;
    if (portStats.hasCounterAttack) {
      bonusDamageToAttacker = (portFirepower * 0.3).round();
    }
    int empDrainDamage = 0;
    if (portStats.hasEmpBurst) {
      empDrainDamage = (attackerShields * portStats.empDrainPct).round();
    }

    int totalDamageToAttacker =
        baseDamageToAttacker + bonusDamageToAttacker + empDrainDamage;

    final canDefend = remainingPortShields > port.captureThreshold;
    if (!canDefend) {
      totalDamageToAttacker = 0;
    }

    var shieldsLeft = attackerShields;
    var hullLeft = attackerHull;
    if (totalDamageToAttacker > 0) {
      if (shieldsLeft > 0) {
        if (totalDamageToAttacker <= shieldsLeft) {
          shieldsLeft -= totalDamageToAttacker;
          totalDamageToAttacker = 0;
        } else {
          totalDamageToAttacker -= shieldsLeft;
          shieldsLeft = 0;
        }
      }
      if (totalDamageToAttacker > 0) {
        hullLeft = (hullLeft - totalDamageToAttacker).clamp(0, attackerMaxHull);
      }
    }

    String outcome;
    var surrendered = false;
    var attackerDefeated = false;
    if (hullLeft <= 0) {
      outcome = "attackerDefeated";
      attackerDefeated = true;
    } else if (remainingPortShields <= port.captureThreshold) {
      outcome = "surrender";
      surrendered = true;
    } else {
      outcome = "continue";
    }

    return (
      damageToPort: damageToPort,
      baseDamageToAttacker: baseDamageToAttacker,
      bonusDamageToAttacker: bonusDamageToAttacker,
      remainingPortShields: remainingPortShields,
      attackerShields: shieldsLeft,
      attackerHull: hullLeft,
      surrendered: surrendered,
      attackerDefeated: attackerDefeated,
      outcome: outcome,
    );
  }

  /// Resolve one round of port combat (player attacking).
  static PortCombatResult resolvePortAttack(
    Player attacker,
    Port port,
    String mode,
  ) {
    final round = resolveRound(
      attackerPower: calculateAttackerFirepower(attacker),
      attackerShields: attacker.shields,
      attackerHull: attacker.hull,
      attackerMaxHull: attacker.maxHull,
      port: port,
    );

    final updatedPort = port.copyWith(
      currentShields: round.remainingPortShields,
    );

    final updatedPlayer = attacker.copyWith(
      shields: round.attackerShields,
      hull: round.attackerHull,
    );

    return PortCombatResult(
      portSurrendered: round.surrendered,
      portDestroyed: false,
      attackerDefeated: round.attackerDefeated,
      damageToPort: round.damageToPort,
      damageToAttacker:
          round.baseDamageToAttacker + round.bonusDamageToAttacker,
      updatedPort: updatedPort,
      updatedPlayer: updatedPlayer,
      outcome: round.outcome,
    );
  }

  /// Resolve one round of port combat (NPC attacking).
  static PortCombatResult resolveNpcPortAttack(
    NpcShip npc,
    Port port,
    String mode,
  ) {
    final round = resolveRound(
      attackerPower: calculateNpcFirepower(npc),
      attackerShields: npc.shields,
      attackerHull: npc.hull,
      attackerMaxHull: npc.maxHull,
      port: port,
    );

    final updatedPort = port.copyWith(
      currentShields: round.remainingPortShields,
    );

    final updatedNpc = npc.copyWith(
      shields: round.attackerShields,
      hull: round.attackerHull,
    );

    return PortCombatResult(
      portSurrendered: round.surrendered,
      portDestroyed: false,
      attackerDefeated: round.attackerDefeated,
      damageToPort: round.damageToPort,
      damageToAttacker:
          round.baseDamageToAttacker + round.bonusDamageToAttacker,
      updatedPort: updatedPort,
      updatedNpc: updatedNpc,
      outcome: round.outcome,
    );
  }

  /// Capture a port (transfer ownership). [newOwnerId] is the display
  /// name (legacy); pass [ownerId] (stable NPC/player id) for matching —
  /// display names can collide across seeded generators.
  static Port capturePort(
    Port port,
    String newOwnerId,
    String? newOwnerFaction, {
    String? ownerId,
  }) {
    return port.copyWith(
      owner: newOwnerId,
      ownerId: ownerId,
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
