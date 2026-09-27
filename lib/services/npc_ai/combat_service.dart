import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port_defense_config.dart';
import 'package:cosmic_trader/services/npc_ai/port_combat_service.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/salvage_service.dart';

class PlayerCombatResult {
  final int damageDealt;
  final int damageTaken;
  final bool npcDestroyed;
  final int loot;
  final int lootScrapMetal;
  final int lootScrapTech;
  final Player updatedPlayer;
  final NpcShip updatedNpc;

  /// Shared outcome contract (Step 0). `CombatScreen` sets this explicitly
  /// as C1b wires retreat/surrender/parley into the player loop; until
  /// then it defaults from destruction like the NPC path.
  final CombatOutcome outcome;

  const PlayerCombatResult({
    required this.damageDealt,
    required this.damageTaken,
    required this.npcDestroyed,
    required this.loot,
    this.lootScrapMetal = 0,
    this.lootScrapTech = 0,
    required this.updatedPlayer,
    required this.updatedNpc,
    this.outcome = CombatOutcome.ongoing,
  });
}

/// How a fight ended. Shared contract for NPC-vs-NPC resolution
/// ([CombatService.resolveCombat]) and player combat (`CombatScreen`):
/// both produce these outcomes so morale, loot, bounty, and log code
/// never branches on which system ran the fight.
///
/// Direction is baked in (attacker/defender are unambiguous at every
/// call site); `ongoing` means the exchange ended without resolution.
enum CombatOutcome {
  attackerVictory,
  defenderVictory,
  attackerRetreat,
  defenderRetreat,
  defenderSurrender,
  parley,
  ongoing,
}

class CombatResult {
  final bool attackerWon;
  final int damageToDefender;
  final int damageToAttacker;
  final bool defenderDestroyed;
  final bool attackerDestroyed;
  final int lootCredits;
  final Map<String, int> lootCargo;

  /// Shared outcome contract (Step 0). Defaults to `ongoing` so existing
  /// call sites keep compiling; resolvers set it explicitly.
  final CombatOutcome outcome;

  /// Energy the retreating side paid to break contact (0 when n/a).
  final int escapeCostEnergy;

  /// Credits paid for peace when [outcome] is parley (0 when n/a).
  final int parleyCostCredits;

  const CombatResult({
    required this.attackerWon,
    required this.damageToDefender,
    required this.damageToAttacker,
    required this.defenderDestroyed,
    required this.attackerDestroyed,
    this.lootCredits = 0,
    this.lootCargo = const {},
    this.outcome = CombatOutcome.ongoing,
    this.escapeCostEnergy = 0,
    this.parleyCostCredits = 0,
  });

  /// Maps destruction flags to an outcome. Both destroyed is scored for
  /// the attacker (mutual kill still pays bounties/loot to the aggressor).
  static CombatOutcome outcomeFromDestruction({
    required bool defenderDestroyed,
    required bool attackerDestroyed,
  }) {
    if (defenderDestroyed) return CombatOutcome.attackerVictory;
    if (attackerDestroyed) return CombatOutcome.defenderVictory;
    return CombatOutcome.ongoing;
  }
}

class CombatService {
  static final math.Random _rng = math.Random();

  /// Energy cost to attempt breaking contact. Shared by willingness
  /// ([assessMorale]) and every resolution site (NPC and player combat),
  /// so the price of running never drifts between systems.
  static int escapeEnergyCost(int engineLevel) =>
      math.max(1, (6 - engineLevel) * 2);

  /// Tribute a surrendering defender pays: 10% of credits, never negative,
  /// never more than held. Shared by NPC resolution and player-combat
  /// parley offers so both sides quote the same price.
  static int surrenderTribute(int credits) =>
      (credits * 0.1).round().clamp(0, math.max(0, credits));

  /// Stage 3 — escape resolution: does the break-off attempt succeed, and
  /// can the opponent prevent it?
  ///
  /// Success is engine-relative, never free: better engines outrun,
  /// equals is a coin flip, worse needs luck (10%). The attempt always
  /// costs energy (paid by the caller via [escapeEnergyCost]).
  ///
  /// `tractorBeam` is the future hook from the C1 plan: tractor beams
  /// will prevent fleeing as a tactic. No tractor-beam content exists
  /// yet, so the flag is always false at call sites today — but every
  /// escape in the game already routes through this check, so wiring it
  /// later is a data change, not a logic change.
  static ({bool escaped, int energyCost}) resolveRetreat({
    required int escapeeEngineLevel,
    required int pursuerEngineLevel,
    bool tractorBeam = false,
    math.Random? rng,
  }) {
    final cost = escapeEnergyCost(escapeeEngineLevel);
    if (tractorBeam) return (escaped: false, energyCost: cost);
    final diff = escapeeEngineLevel - pursuerEngineLevel;
    if (diff >= 1) return (escaped: true, energyCost: cost);
    final r = rng ?? _rng;
    if (diff == 0) return (escaped: r.nextBool(), energyCost: cost);
    return (escaped: r.nextDouble() < 0.1, energyCost: cost);
  }

  /// Stage 1+2 of disengagement (C1a): willingness + eligibility.
  ///
  /// Returns a retreat/surrender outcome plus the energy cost to escape,
  /// or null outcome when the ship fights on. Willingness blends hull
  /// state, shields, personality, faction tendencies, and perceived odds;
  /// eligibility requires the engine and energy to actually break contact
  /// (a ship that wants out but cannot escape fights on).
  ///
  /// Faction tendencies (modified per-pilot by caution/aggression):
  /// Duran resist retreat, Vinari disengage early, Traders surrender
  /// (defenders) rather than die, Pirates press an advantage.
  static ({CombatOutcome? outcome, int escapeCost}) assessMorale({
    required NpcShip self,
    required double selfPower,
    required double foePower,
    required double foeHullFraction,
    required bool isDefender,
  }) {
    const ({CombatOutcome? outcome, int escapeCost}) none =
        (outcome: null, escapeCost: 0);
    final config = self.personalityConfig;
    final hullFraction = self.maxHull <= 0 ? 0.0 : self.hull / self.maxHull;
    final shieldsFraction =
        self.maxShields <= 0 ? 0.0 : self.shields / self.maxShields;

    // Soak-tuned (2nd run: 43 Duran deaths, 0 retreats — stubborn read
    // as suicidal, not flavorful): Duran break off below ~15–25% hull
    // depending on archetype, still the boldest faction by far.
    final base = switch (self.faction) {
      FactionClass.duran => 0.25,
      FactionClass.vinari => 0.55,
      FactionClass.trader => 0.40,
      FactionClass.pirate => 0.30,
    };
    final limit = (base + config.caution * 0.2 - config.aggression * 0.15)
        .clamp(0.05, 0.8);

    // Pressing an advantage: a pirate beating down a dying foe never
    // breaks off, and nobody retreats from a nearly-dead enemy while
    // still above half their own limit.
    if (foeHullFraction < 0.15 && hullFraction > limit * 0.5) {
      return none;
    }

    final outmatched = foePower > selfPower * (2.0 + (1.0 - config.caution)) &&
        shieldsFraction < 0.25;

    final bool surrender;
    if (hullFraction < limit) {
      surrender = isDefender && self.faction == FactionClass.trader;
    } else if (outmatched) {
      surrender = false;
    } else {
      return none;
    }

    if (surrender) {
      return (outcome: CombatOutcome.defenderSurrender, escapeCost: 0);
    }
    final escapeCost = escapeEnergyCost(self.engineEquipmentLevel);
    if (!self.hasEnergy(escapeCost)) return none;
    return (
      outcome: isDefender
          ? CombatOutcome.defenderRetreat
          : CombatOutcome.attackerRetreat,
      escapeCost: escapeCost,
    );
  }

  /// Resolve one round of combat between two ships.
  /// Returns updated copies of both ships and the combat result.
  static ({NpcShip attacker, NpcShip defender, CombatResult result})
      resolveCombat(NpcShip attacker, NpcShip defender) {
    final atkPower = calculateFirepower(attacker);
    final defPower = calculateFirepower(defender);

    final atkHullFraction =
        attacker.maxHull <= 0 ? 0.0 : attacker.hull / attacker.maxHull;
    final defHullFraction =
        defender.maxHull <= 0 ? 0.0 : defender.hull / defender.maxHull;

    // C1a morale, evaluated pre-round. Defender decides first.
    final defMorale = assessMorale(
      self: defender,
      selfPower: defPower.toDouble(),
      foePower: atkPower.toDouble(),
      foeHullFraction: atkHullFraction,
      isDefender: true,
    );

    // Surrender preempts the exchange: tribute instead of blows.
    if (defMorale.outcome == CombatOutcome.defenderSurrender) {
      final tribute = surrenderTribute(defender.credits);
      GameEventLog.global.combat(
          '[${defender.pilotName}] Surrendered to ${attacker.pilotName} — '
          'paid $tribute cr tribute');
      return (
        attacker: attacker.copyWith(credits: attacker.credits + tribute),
        defender: defender.copyWith(credits: defender.credits - tribute),
        result: CombatResult(
          attackerWon: false,
          damageToDefender: 0,
          damageToAttacker: 0,
          defenderDestroyed: false,
          attackerDestroyed: false,
          outcome: CombatOutcome.defenderSurrender,
          parleyCostCredits: tribute,
        ),
      );
    }

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

    // Defender breaks contact first when willing and surviving.
    if (defMorale.outcome == CombatOutcome.defenderRetreat &&
        !defenderDestroyed) {
      final defenderEnergy =
          math.max(0, defender.energy - defMorale.escapeCost);
      GameEventLog.global.combat(
          '[${defender.pilotName}] Broke off from ${attacker.pilotName} '
          '(−${defMorale.escapeCost} energy)');
      final updatedAttacker = attacker.copyWith(
        hull: atkHull,
        shields: atkShields,
        totalDamageDealt: attacker.totalDamageDealt + atkDamage,
        totalDamageTaken: attacker.totalDamageTaken + defDamage,
      );
      final updatedDefender = defender.copyWith(
        hull: defHull,
        shields: defShields,
        energy: defenderEnergy,
        totalDamageDealt: defender.totalDamageDealt + defDamage,
        totalDamageTaken: defender.totalDamageTaken + atkDamage,
      );
      return (
        attacker: updatedAttacker,
        defender: updatedDefender,
        result: CombatResult(
          attackerWon: false,
          damageToDefender: atkDamage,
          damageToAttacker: defDamage,
          defenderDestroyed: false,
          attackerDestroyed: false,
          outcome: CombatOutcome.defenderRetreat,
          escapeCostEnergy: defMorale.escapeCost,
        ),
      );
    }

    // Otherwise the attacker may break off (same rules, mirrored) —
    // but never from a corpse: a destroyed defender means destruction
    // stands, loot flows, kills count.
    final atkMorale = !defenderDestroyed
        ? assessMorale(
            self: attacker,
            selfPower: atkPower.toDouble(),
            foePower: defPower.toDouble(),
            foeHullFraction: defHullFraction,
            isDefender: false,
          )
        : (outcome: null, escapeCost: 0);
    if (atkMorale.outcome == CombatOutcome.attackerRetreat &&
        !attackerDestroyed) {
      final attackerEnergy =
          math.max(0, attacker.energy - atkMorale.escapeCost);
      GameEventLog.global.combat(
          '[${attacker.pilotName}] Broke off from ${defender.pilotName} '
          '(−${atkMorale.escapeCost} energy)');
      final updatedAttacker = attacker.copyWith(
        hull: atkHull,
        shields: atkShields,
        energy: attackerEnergy,
        totalDamageDealt: attacker.totalDamageDealt + atkDamage,
        totalDamageTaken: attacker.totalDamageTaken + defDamage,
      );
      final updatedDefender = defender.copyWith(
        hull: defHull,
        shields: defShields,
        totalDamageDealt: defender.totalDamageDealt + defDamage,
        totalDamageTaken: defender.totalDamageTaken + atkDamage,
      );
      return (
        attacker: updatedAttacker,
        defender: updatedDefender,
        result: CombatResult(
          attackerWon: false,
          damageToDefender: atkDamage,
          damageToAttacker: defDamage,
          defenderDestroyed: false,
          attackerDestroyed: false,
          outcome: CombatOutcome.attackerRetreat,
          escapeCostEnergy: atkMorale.escapeCost,
        ),
      );
    }

    if (defenderDestroyed) {
      // Credits floor: a debt-ridden defender (legacy of the pre-fix
      // buy-phase clamp bug) pays nothing instead of billing the killer.
      // Rate is 25%: full-half loot snowballed predators (one live pirate
      // parlayed kills into 16M) faster than victims could ever recover.
      lootCredits = (defender.credits * 0.25).round().clamp(0, 1 << 30);
      lootCargo.addAll(defender.cargo);
    }

    final lootResult = _mergeLootCargo(attacker, lootCargo);
    final updatedAttacker = attacker.copyWith(
      hull: atkHull,
      shields: atkShields,
      // A 0-hull attacker is a wreck, not a combatant: flag it so the
      // tick loop and goal logic stop treating the corpse as alive.
      isDestroyed: attackerDestroyed,
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
        outcome: CombatResult.outcomeFromDestruction(
          defenderDestroyed: defenderDestroyed,
          attackerDestroyed: attackerDestroyed,
        ),
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

  /// Estimate if NPC can overcome [defenseLevel] port defenses via a
  /// multi-round siege, using the SAME formulas the siege actually runs:
  /// NPC power via [PortCombatService.calculateNpcFirepower] (NOT the
  /// ship-vs-ship formula — weapon tiers scale differently in each),
  /// incoming damage including counter-attack and EMP bursts when the
  /// defense level fields those abilities, plus the free finishing round
  /// once the port drops to capture threshold. Mixing formulas previously
  /// cleared ships the real siege would kill and rejected ships that
  /// would win.
  static bool canRaidPort(NpcShip npc, int defenseLevel) {
    final stats = PortDefenseConfig.defenseStats(defenseLevel);
    final npcPower = PortCombatService.calculateNpcFirepower(npc);
    if (npcPower <= 0) return false;
    final incoming = stats.firepower +
        (stats.hasCounterAttack ? (stats.firepower * 0.3).round() : 0) +
        (stats.hasEmpBurst ? (npc.shields * stats.empDrainPct).round() : 0);
    final perRound = incoming <= 0 ? 1 : incoming;
    final effective =
        npc.hull + npc.shields + (npc.hullEquipmentLevel - 1) * 10;
    final rounds = effective / perRound + 1;
    return npcPower * rounds > stats.shieldCapacity;
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
      outcome:
          npcDestroyed ? CombatOutcome.attackerVictory : CombatOutcome.ongoing,
    );
  }

  static int _calculateEffectiveHull(NpcShip ship) {
    return ship.hull + ship.shields + (ship.hullEquipmentLevel - 1) * 10;
  }
}
