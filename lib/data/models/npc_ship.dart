import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import '../../core/npc_name_generator.dart';
import '../../services/npc_ai/npc_goal.dart';
import '../../services/npc_ai/npc_memory.dart';
import '../../services/npc_ai/npc_personality.dart';
import 'commodity.dart';
import 'faction.dart';
import 'ship_templates.dart';

class NpcShip {
  // ── Identity ─────────────────────────────────────────
  final String id;
  final String pilotName;
  final String shipName;
  final FactionClass faction;
  final ShipDefinition shipDef;

  // ── Economy / Energy (B1 fuel; pre-B1 saves migrate via fromJson) ──
  final int credits;
  final int energy;
  final int maxEnergy;
  final int currentSectorId;

  // ── Solar Array (NPC trickle-charge backup, mirrors Player) ──
  final int solarArrayLevel;
  final bool solarArrayDeployed;

  // ── Ship Stats ───────────────────────────────────────
  final int hull;
  final int maxHull;
  final int shields;
  final int maxShields;
  final int cargoUsed;
  final Map<String, int> cargo;

  // ── Banking ──────────────────────────────────────────
  final int bankBalance;
  final DateTime? lastInterestTime;

  // ── Equipment Levels ─────────────────────────────────
  final int hullEquipmentLevel;
  final int shieldEquipmentLevel;
  final int engineEquipmentLevel;

  // ── Weapons (slot name → level) ──────────────────────
  final Map<String, int> weaponSlots;

  // ── Drones ───────────────────────────────────────────
  final int drones;
  final int maxDrones;

  // ── AI State ─────────────────────────────────────────
  final NpcPersonality personality;
  final NpcGoal? currentGoal;
  final NpcMemory memory;

  // ── Scrap Loot ──────────────────────────────────────────────
  final int scrapMetal;
  final int scrapTech;

  // ── Combat History ───────────────────────────────────
  final bool isDestroyed;
  final int kills;
  final int deaths;
  final int totalDamageDealt;
  final int totalDamageTaken;

  // ── Notoriety ──────────────────────────────────────────
  /// Global reputation score (0.0 to 100.0).
  final double notoriety;

  NpcShip({
    required this.id,
    required this.pilotName,
    required this.shipName,
    required this.faction,
    required this.shipDef,
    required this.credits,
    this.energy = 1000,
    this.maxEnergy = 1000,
    this.solarArrayLevel = 0,
    this.solarArrayDeployed = false,
    required this.currentSectorId,
    required this.hull,
    required this.maxHull,
    required this.shields,
    required this.maxShields,
    this.cargoUsed = 0,
    this.cargo = const {},
    this.bankBalance = 0,
    this.lastInterestTime,
    this.hullEquipmentLevel = 1,
    this.shieldEquipmentLevel = 1,
    this.engineEquipmentLevel = 1,
    this.weaponSlots = const {},
    this.drones = 0,
    this.maxDrones = 0,
    this.scrapMetal = 0,
    this.scrapTech = 0,
    required this.personality,
    this.currentGoal,
    this.memory = const NpcMemory(),
    this.isDestroyed = false,
    this.kills = 0,
    this.deaths = 0,
    this.totalDamageDealt = 0,
    this.totalDamageTaken = 0,
    this.notoriety = 0.0,
  }) : assert(credits >= 0, 'NpcShip credits must never go negative');

  PersonalityConfig get personalityConfig =>
      PersonalityConfig.all[personality]!;

  int get totalWeaponPower {
    int total = 0;
    weaponSlots.forEach((slot, level) {
      total += level;
    });
    return total;
  }

  int get cargoHoldCapacity => shipDef.maxCargo;

  /// True when [cost] energy can be spent right now.
  bool hasEnergy(int cost) => energy >= cost;

  /// Copy with [cost] energy deducted, clamped at zero.
  NpcShip spendEnergy(int cost) {
    final next = energy - cost;
    return copyWith(energy: next < 0 ? 0 : next);
  }

  /// Copy with [amount] energy restored, clamped to [maxEnergy].
  NpcShip refuelEnergy(int amount) {
    final next = energy + amount;
    return copyWith(energy: next > maxEnergy ? maxEnergy : next);
  }

  /// Deployed arrays lock the ship in place (mirrors Player.canMove).
  bool get canMove => !solarArrayDeployed;

  NpcShip copyWith({
    String? id,
    String? pilotName,
    String? shipName,
    FactionClass? faction,
    ShipDefinition? shipDef,
    int? credits,
    int? energy,
    int? maxEnergy,
    int? solarArrayLevel,
    bool? solarArrayDeployed,
    int? currentSectorId,
    int? hull,
    int? maxHull,
    int? shields,
    int? maxShields,
    int? cargoUsed,
    Map<String, int>? cargo,
    int? bankBalance,
    DateTime? lastInterestTime,
    int? hullEquipmentLevel,
    int? shieldEquipmentLevel,
    int? engineEquipmentLevel,
    Map<String, int>? weaponSlots,
    int? drones,
    int? maxDrones,
    int? scrapMetal,
    int? scrapTech,
    NpcPersonality? personality,
    NpcGoal? currentGoal,
    // Set true to actually clear the goal: passing `currentGoal: null`
    // would be swallowed by the `?? this.currentGoal` fallback below and
    // silently keep the old goal (this was a live stall bug — failed goals
    // never cleared, blocking all future goal selection).
    bool clearGoal = false,
    NpcMemory? memory,
    bool? isDestroyed,
    int? kills,
    int? deaths,
    int? totalDamageDealt,
    int? totalDamageTaken,
    double? notoriety,
  }) {
    return NpcShip(
      id: id ?? this.id,
      pilotName: pilotName ?? this.pilotName,
      shipName: shipName ?? this.shipName,
      faction: faction ?? this.faction,
      shipDef: shipDef ?? this.shipDef,
      credits: credits ?? this.credits,
      energy: energy ?? this.energy,
      maxEnergy: maxEnergy ?? this.maxEnergy,
      solarArrayLevel: solarArrayLevel ?? this.solarArrayLevel,
      solarArrayDeployed: solarArrayDeployed ?? this.solarArrayDeployed,
      currentSectorId: currentSectorId ?? this.currentSectorId,
      hull: hull ?? this.hull,
      maxHull: maxHull ?? this.maxHull,
      shields: shields ?? this.shields,
      maxShields: maxShields ?? this.maxShields,
      cargoUsed: cargoUsed ?? this.cargoUsed,
      cargo: cargo ?? this.cargo,
      bankBalance: bankBalance ?? this.bankBalance,
      lastInterestTime: lastInterestTime ?? this.lastInterestTime,
      hullEquipmentLevel: hullEquipmentLevel ?? this.hullEquipmentLevel,
      shieldEquipmentLevel: shieldEquipmentLevel ?? this.shieldEquipmentLevel,
      engineEquipmentLevel: engineEquipmentLevel ?? this.engineEquipmentLevel,
      weaponSlots: weaponSlots ?? this.weaponSlots,
      drones: drones ?? this.drones,
      maxDrones: maxDrones ?? this.maxDrones,
      scrapMetal: scrapMetal ?? this.scrapMetal,
      scrapTech: scrapTech ?? this.scrapTech,
      personality: personality ?? this.personality,
      currentGoal: clearGoal ? null : (currentGoal ?? this.currentGoal),
      memory: memory ?? this.memory,
      isDestroyed: isDestroyed ?? this.isDestroyed,
      kills: kills ?? this.kills,
      deaths: deaths ?? this.deaths,
      totalDamageDealt: totalDamageDealt ?? this.totalDamageDealt,
      totalDamageTaken: totalDamageTaken ?? this.totalDamageTaken,
      notoriety: notoriety ?? this.notoriety,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pilotName': pilotName,
      'shipName': shipName,
      'faction': faction.name,
      'shipDefName': shipDef.name,
      'credits': credits,
      'energy': energy,
      'maxEnergy': maxEnergy,
      'solarArrayLevel': solarArrayLevel,
      'solarArrayDeployed': solarArrayDeployed,
      'currentSectorId': currentSectorId,
      'hull': hull,
      'maxHull': maxHull,
      'shields': shields,
      'maxShields': maxShields,
      'cargoUsed': cargoUsed,
      'cargo': cargo,
      'bankBalance': bankBalance,
      'lastInterestTime': lastInterestTime?.toIso8601String(),
      'hullEquipmentLevel': hullEquipmentLevel,
      'shieldEquipmentLevel': shieldEquipmentLevel,
      'engineEquipmentLevel': engineEquipmentLevel,
      'weaponSlots': weaponSlots,
      'drones': drones,
      'maxDrones': maxDrones,
      'personality': personality.name,
      'currentGoal': currentGoal?.toJson(),
      'memory': memory.toJson(),
      'isDestroyed': isDestroyed,
      'kills': kills,
      'deaths': deaths,
      'totalDamageDealt': totalDamageDealt,
      'totalDamageTaken': totalDamageTaken,
      'notoriety': notoriety,
    };
  }

  factory NpcShip.fromJson(Map<String, dynamic> json) {
    final shipDefName = json['shipDefName'] as String;
    final shipDef = ShipDefinition.getShipByName(shipDefName) ??
        ShipDefinition.allShips.first;

    return NpcShip(
      id: json['id'] as String,
      pilotName: json['pilotName'] as String? ?? 'Unknown Pilot',
      shipName: json['shipName'] as String? ?? 'Unknown Ship',
      faction: FactionClass.values.firstWhere(
        (e) => e.name == json['faction'],
        orElse: () => FactionClass.trader,
      ),
      shipDef: shipDef,
      credits: json['credits'] as int? ?? 10000,
      // Pre-energy save migration: legacy 'turns' seeds the tank.
      energy: json['energy'] as int? ?? json['turns'] as int? ?? 1000,
      maxEnergy: json['maxEnergy'] as int? ?? json['maxTurns'] as int? ?? 1000,
      solarArrayLevel: json['solarArrayLevel'] as int? ?? 0,
      solarArrayDeployed: json['solarArrayDeployed'] as bool? ?? false,
      currentSectorId: json['currentSectorId'] as int? ?? 1,
      hull: json['hull'] as int? ?? shipDef.maxHullCapacity,
      maxHull: json['maxHull'] as int? ?? shipDef.maxHullCapacity,
      shields: json['shields'] as int? ?? shipDef.maxShields,
      maxShields: json['maxShields'] as int? ?? shipDef.maxShields,
      cargoUsed: json['cargoUsed'] as int? ?? 0,
      cargo: Map<String, int>.from(json['cargo'] ?? {}),
      bankBalance: json['bankBalance'] as int? ?? 0,
      lastInterestTime: json['lastInterestTime'] != null
          ? DateTime.parse(json['lastInterestTime'] as String)
          : null,
      hullEquipmentLevel: json['hullEquipmentLevel'] as int? ?? 1,
      shieldEquipmentLevel: json['shieldEquipmentLevel'] as int? ?? 1,
      engineEquipmentLevel: json['engineEquipmentLevel'] as int? ?? 1,
      weaponSlots:
          (json['weaponSlots'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {},
      drones: json['drones'] as int? ?? 0,
      maxDrones: json['maxDrones'] as int? ?? 0,
      personality: NpcPersonality.values.firstWhere(
        (e) => e.name == json['personality'],
        orElse: () => NpcPersonality.traderMerchant,
      ),
      currentGoal: json['currentGoal'] != null
          ? NpcGoal.fromJson(json['currentGoal'] as Map<String, dynamic>)
          : null,
      memory: json['memory'] != null
          ? NpcMemory.fromJson(json['memory'] as Map<String, dynamic>)
          : NpcMemory.empty(),
      isDestroyed: json['isDestroyed'] as bool? ?? false,
      kills: json['kills'] as int? ?? 0,
      deaths: json['deaths'] as int? ?? 0,
      totalDamageDealt: json['totalDamageDealt'] as int? ?? 0,
      totalDamageTaken: json['totalDamageTaken'] as int? ?? 0,
      notoriety: (json['notoriety'] as num?)?.toDouble() ?? 0.0,
    );
  }

  static NpcShip create({
    required FactionClass faction,
    required ShipDefinition shipDef,
    required int currentSectorId,
    required int startingCredits,
    required int seed,
  }) {
    final rng = math.Random(seed);
    final uuid = const Uuid();

    // Build weapon slots from ship definition
    final weaponSlots = <String, int>{};
    for (int i = 0; i < shipDef.weaponSlots.length; i++) {
      weaponSlots[shipDef.weaponSlots[i]] = 1;
    }

    return NpcShip(
      id: uuid.v4(),
      pilotName: NpcNameGenerator.generatePilotName(
        isPirate: faction == FactionClass.pirate,
        seed: seed,
      ),
      shipName: NpcNameGenerator.generateShipName(seed: seed + 1),
      faction: faction,
      shipDef: shipDef,
      credits: startingCredits,
      energy: 1000,
      maxEnergy: 1000,
      currentSectorId: currentSectorId,
      hull: shipDef.maxHullCapacity,
      maxHull: shipDef.maxHullCapacity,
      shields: shipDef.maxShields,
      maxShields: shipDef.maxShields,
      cargo: {for (final name in CommodityRegistry.names) name: 0},
      weaponSlots: weaponSlots,
      personality: assignPersonalityForFaction(faction, rng),
      memory: const NpcMemory(),
    );
  }
}
