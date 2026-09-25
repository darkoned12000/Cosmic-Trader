import 'dart:math' as math;

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/salvage_service.dart';

class CombatResult {
  final bool attackerWon;
  final int damageToDefender;
  final int damageToAttacker;
  final bool defenderDestroyed;
  final bool attackerDestroyed;
  final int lootCredits;
  final Map<String, int> lootCargo;

  const CombatResult({
    required this.attackerWon,
    required this.damageToDefender,
    required this.damageToAttacker,
    required this.defenderDestroyed,
    required this.attackerDestroyed,
    this.lootCredits = 0,
    this.lootCargo = const {},
  });
}

class PlayerCombatResult {
  final int damageDealt;
  final int damageTaken;
  final bool npcDestroyed;
  final int loot;
  final int lootScrapMetal;
  final int lootScrapTech;
  final Player updatedPlayer;
  final NpcShip updatedNpc;

  const PlayerCombatResult({
    required this.damageDealt,
    required this.damageTaken,
    required this.npcDestroyed,
    required this.loot,
    this.lootScrapMetal = 0,
    this.lootScrapTech = 0,
    required this.updatedPlayer,
    required this.updatedNpc,
  });
}

class CombatService {
  static final math.Random _rng = math.Random();

  /// Resolve one round of combat between two ships.
  /// Returns updated copies of both ships and the combat result.
  static ({NpcShip attacker, NpcShip defender, CombatResult result})
      resolveCombat(NpcShip attacker, NpcShip defender) {
    final atkPower = calculateFirepower(attacker);
    final defPower = calculateFirepower(defender);

    final atkDamage =
        (atkPower * (0.8 + _rng.nextDouble() * 0.4)).round().clamp(1, 99999);
    final defDamage =
        (defPower * (0.8 + _rng.nextDouble() * 0.4)).round().clamp(1, 99999);

    // Apply damage: shields first, then hull
    var defShields = defender.shields;
    var defHull = defender.hull;
    var atkShields = attacker.shields;
    var atkHull = attacker.hull;

    // Damage to defender
    int remainingAtk = atkDamage;
    if (defShields > 0) {
      if (remainingAtk <= defShields) {
        defShields -= remainingAtk;
        remainingAtk = 0;
      } else {
        remainingAtk -= defShields;
        defShields = 0;
      }
    }
    if (remainingAtk > 0) {
      defHull = (defHull - remainingAtk).clamp(0, defender.maxHull);
    }

    // Damage to attacker (return fire)
    int remainingDef = defDamage;
    if (atkShields > 0) {
      if (remainingDef <= atkShields) {
        atkShields -= remainingDef;
        remainingDef = 0;
      } else {
        remainingDef -= atkShields;
        atkShields = 0;
      }
    }
    if (remainingDef > 0) {
      atkHull = (atkHull - remainingDef).clamp(0, attacker.maxHull);
    }

    final defenderDestroyed = defHull <= 0;
    final attackerDestroyed = atkHull <= 0;

    int lootCredits = 0;
    final lootCargo = <String, int>{};

    if (defenderDestroyed) {
      // Credits floor: a debt-ridden defender (legacy of the pre-fix
      // buy-phase clamp bug) pays nothing instead of billing the killer.
      lootCredits = (defender.credits * 0.5).round().clamp(0, 1 << 30);
      lootCargo.addAll(defender.cargo);
    }

    final lootResult = _mergeLootCargo(attacker, lootCargo);
    final updatedAttacker = attacker.copyWith(
      hull: atkHull,
      shields: atkShields,
      credits: attacker.credits + lootCredits,
      kills: attacker.kills + (defenderDestroyed ? 1 : 0),
      totalDamageDealt: attacker.totalDamageDealt + atkDamage,
      totalDamageTaken: attacker.totalDamageTaken + defDamage,
      cargo: lootResult.cargo,
      cargoUsed: attacker.cargoUsed + lootResult.unitsTaken,
    );

    final updatedDefender = defender.copyWith(
      hull: defHull,
      shields: defShields,
      credits: defenderDestroyed ? 0 : defender.credits,
      cargo: defenderDestroyed ? {} : defender.cargo,
      cargoUsed: defenderDestroyed ? 0 : defender.cargoUsed,
      isDestroyed: defenderDestroyed,
      deaths: defender.deaths + (defenderDestroyed ? 1 : 0),
      totalDamageDealt: defender.totalDamageDealt + defDamage,
      totalDamageTaken: defender.totalDamageTaken + atkDamage,
    );

    if (defenderDestroyed) {
      GameEventLog.global.combat(
          '[${attacker.pilotName}] Destroyed ${defender.pilotName} — looted $lootCredits cr');
      EconomyMetrics.global.recordLoot(
        actorFaction: attacker.faction.name,
        credits: lootCredits,
        isPlayer: false,
      );
    }

    return (
      attacker: updatedAttacker,
      defender: updatedDefender,
      result: CombatResult(
        attackerWon: defenderDestroyed && !attackerDestroyed,
        damageToDefender: atkDamage,
        damageToAttacker: defDamage,
        defenderDestroyed: defenderDestroyed,
        attackerDestroyed: attackerDestroyed,
        lootCredits: lootCredits,
        lootCargo: lootCargo,
      ),
    );
  }

  /// Victim cargo merged into the attacker's holds, capped by free space.
  /// Contraband and other black-market goods transfer like anything else —
  /// killing smugglers is a supply line.
  static ({Map<String, int> cargo, int unitsTaken}) _mergeLootCargo(
      NpcShip attacker, Map<String, int> loot) {
    var free = attacker.cargoHoldCapacity - attacker.cargoUsed;
    final merged = Map<String, int>.from(attacker.cargo);
    var taken = 0;
    if (free > 0) {
      for (final entry in loot.entries) {
        if (free <= 0) break;
        final take = entry.value.clamp(0, free);
        if (take <= 0) continue;
        merged[entry.key] = (merged[entry.key] ?? 0) + take;
        free -= take;
        taken += take;
      }
    }
    return (cargo: merged, unitsTaken: taken);
  }

  /// Quick estimation: can [attacker] reliably win against [defender]?
  static bool canWin(NpcShip attacker, NpcShip defender) {
    final atkPower = calculateFirepower(attacker);
    final defPower = calculateFirepower(defender);
    final atkEffective = _calculateEffectiveHull(attacker);
    final defEffective = _calculateEffectiveHull(defender);

    final powerRatio = atkPower / (defPower + 1);
    final hullRatio = atkEffective / (defEffective + 1);
    return powerRatio > hullRatio * 0.8;
  }

  /// Estimate if NPC can overcome [defenseLevel] port defenses.
  static bool canRaidPort(NpcShip npc, int defenseLevel) {
    final atkPower = calculateFirepower(npc);
    final portDefense = (defenseLevel + 1) * 500;
    return atkPower > portDefense * 1.2;
  }

  static WeaponType _npcWeaponForSlot(NpcShip ship, String slot) {
    final idx = ship.shipDef.weaponSlots.indexOf(slot);
    if (idx < 0 || idx >= ship.shipDef.preferredWeapons.length) {
      return WeaponType.autoLaser;
    }
    return ship.shipDef.preferredWeapons[idx];
  }

  static WeaponType _playerWeaponForSlot(String slotName, String typeName) {
    return WeaponType.values.firstWhere(
      (w) => w.name == typeName,
      orElse: () => WeaponType.autoLaser,
    );
  }

  static int calculateFirepower(NpcShip ship) {
    int total = 0;
    ship.weaponSlots.forEach((slot, level) {
      final wt = _npcWeaponForSlot(ship, slot);
      total += wt.damage * level;
    });
    total += (ship.hullEquipmentLevel - 1) * 5;
    return total;
  }

  static int calculatePlayerFirepower(Player player) {
    int total = 0;
    player.weaponSlots.forEach((slot, level) {
      final typeName = player.weaponTypes[slot] ?? 'autoLaser';
      final wt = _playerWeaponForSlot(slot, typeName);
      total += wt.damage * level;
    });
    total += (player.hullEquipmentLevel - 1) * 5;
    return total;
  }

  /// Player attacks an NPC ship. Returns updated player + combat details.
  static PlayerCombatResult resolvePlayerCombat(Player player, NpcShip npc) {
    final playerPower = calculatePlayerFirepower(player);
    final npcPower = calculateFirepower(npc);

    final damageDealt =
        (playerPower * (0.8 + _rng.nextDouble() * 0.4)).round().clamp(1, 99999);
    final damageTaken =
        (npcPower * (0.8 + _rng.nextDouble() * 0.4)).round().clamp(1, 99999);

    // Damage NPC: shields then hull
    var npcShields = npc.shields;
    var npcHull = npc.hull;
    int remaining = damageDealt;
    if (npcShields > 0) {
      if (remaining <= npcShields) {
        npcShields -= remaining;
        remaining = 0;
      } else {
        remaining -= npcShields;
        npcShields = 0;
      }
    }
    if (remaining > 0) {
      npcHull = (npcHull - remaining).clamp(0, npc.maxHull);
    }

    // Damage player: shields then hull
    var playerShields = player.shields;
    var playerHull = player.hull;
    int remainingDef = damageTaken;
    if (playerShields > 0) {
      if (remainingDef <= playerShields) {
        playerShields -= remainingDef;
        remainingDef = 0;
      } else {
        remainingDef -= playerShields;
        playerShields = 0;
      }
    }
    if (remainingDef > 0) {
      playerHull = (playerHull - remainingDef).clamp(0, player.maxHull);
    }

    final npcDestroyed = npcHull <= 0;
    int loot = 0;
    var lootScrapMetal = 0;
    var lootScrapTech = 0;
    if (npcDestroyed) {
      loot = (npc.credits * 0.5).round();
      final salvage = SalvageService.rollForNpc(npc);
      lootScrapMetal = salvage.scrapMetal;
      lootScrapTech = salvage.scrapTech;
    }

    final updatedPlayer = SalvageService.applyToPlayer(
      player.copyWith(
        hull: playerHull,
        shields: playerShields,
        credits: player.credits + loot,
      ),
      SalvageReward(
        scrapMetal: lootScrapMetal,
        scrapTech: lootScrapTech,
      ),
    );

    final updatedNpc = npc.copyWith(
      hull: npcHull,
      shields: npcShields,
      isDestroyed: npcDestroyed,
      credits: npcDestroyed ? 0 : npc.credits,
      cargo: npcDestroyed ? {} : npc.cargo,
      cargoUsed: npcDestroyed ? 0 : npc.cargoUsed,
      scrapMetal: npcDestroyed ? 0 : npc.scrapMetal,
      scrapTech: npcDestroyed ? 0 : npc.scrapTech,
    );

    GameEventLog.global
        .combat('[PlayerCombat] Dealt $damageDealt to ${npc.pilotName}, '
            'took $damageTaken, ${npcDestroyed ? 'destroyed' : 'damaged'}');

    return PlayerCombatResult(
      damageDealt: damageDealt,
      damageTaken: damageTaken,
      npcDestroyed: npcDestroyed,
      loot: loot,
      lootScrapMetal: lootScrapMetal,
      lootScrapTech: lootScrapTech,
      updatedPlayer: updatedPlayer,
      updatedNpc: updatedNpc,
    );
  }

  static int _calculateEffectiveHull(NpcShip ship) {
    return ship.hull + ship.shields + (ship.hullEquipmentLevel - 1) * 10;
  }
}
