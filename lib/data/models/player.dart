import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';

/// Player model with ship stats for gameplay.
class Player {
  final String id;
  final String username;
  final String? passwordHash;
  final DateTime? createdAt;
  final String name;
  final int currentSectorId;

  // ── Ship Stats ──────────────────────────────────────────────
  final int hull;
  final int maxHull;
  final int shields;
  final int maxShields;
  final int cargoUsed;
  final int maxCargo;
  final int cargoSize;

  // ── Ship Identity ───────────────────────────────────────────
  final String shipDefinitionName;
  final ShipClassType shipClass;

  // ── Weapon Slots ────────────────────────────────────────────
  final Map<String, String> weaponTypes;
  final Map<String, int> weaponSlots;

  // ── Equipment ───────────────────────────────────────────────
  final String hullEquipment;
  final String shieldEquipment;
  final String engineEquipment;
  final int hullEquipmentLevel;
  final int shieldEquipmentLevel;
  final int engineEquipmentLevel;

  // ── Cargo ───────────────────────────────────────────────────
  final Map<String, int> cargo;

  // ── Drones ──────────────────────────────────────────────────
  final int drones;
  final int maxDrones;

  // ── Turns ───────────────────────────────────────────────────
  final int turns;
  final int maxTurns;

  // ── Economy ─────────────────────────────────────────────────
  final int credits;
  final double researchPoints;

  // ── Banking ─────────────────────────────────────────────────
  final int bankBalance;
  final DateTime? lastInterestTime;

  // ── Port Ownership ──────────────────────────────────────────
  final List<String> ownedPorts;

  // ── Scrap & Modules ─────────────────────────────────────────
  final int scrapMetal;
  final int scrapTech;
  final Map<String, int> installedModules; // module id → level

  // ── Faction ─────────────────────────────────────────────────
  final FactionClass faction;

  // ── Notoriety ───────────────────────────────────────────────
  /// Global reputation score (0.0 to 100.0).
  /// Higher values make NPCs more aggressive and hostile.
  final double notoriety;

  Player({
    this.id = '',
    this.username = '',
    this.passwordHash,
    this.createdAt,
    required this.name,
    required this.currentSectorId,
    required this.hull,
    required this.maxHull,
    required this.shields,
    required this.maxShields,
    required this.cargoUsed,
    required this.maxCargo,
    required this.cargoSize,
    this.shipDefinitionName = 'Starhawk Skiff',
    this.shipClass = ShipClassType.interceptor,
    this.weaponTypes = const {},
    this.weaponSlots = const {},
    this.hullEquipment = 'patchworkComposite',
    this.shieldEquipment = 'merchantBuckler',
    this.engineEquipment = 'juryRiggedFusion',
    this.hullEquipmentLevel = 1,
    this.shieldEquipmentLevel = 1,
    this.engineEquipmentLevel = 1,
    this.cargo = const {},
    this.drones = 0,
    this.maxDrones = 0,
    this.turns = 1000,
    this.maxTurns = 1000,
    required this.credits,
    required this.researchPoints,
    this.bankBalance = 0,
    this.lastInterestTime,
    this.ownedPorts = const [],
    this.scrapMetal = 0,
    this.scrapTech = 0,
    this.installedModules = const {},
    this.faction = FactionClass.trader,
    this.notoriety = 0.0,
  });

  bool ownsPort(String portName) => ownedPorts.contains(portName);

  int get effectiveEngineLevel => engineEquipmentLevel;

  int get totalWeaponPower {
    int total = 0;
    weaponSlots.forEach((slot, level) {
      total += level;
    });
    return total;
  }

  Player copyWith({
    String? id,
    String? username,
    String? passwordHash,
    DateTime? createdAt,
    String? name,
    int? currentSectorId,
    int? hull,
    int? maxHull,
    int? shields,
    int? maxShields,
    int? cargoUsed,
    int? maxCargo,
    int? cargoSize,
    String? shipDefinitionName,
    ShipClassType? shipClass,
    Map<String, String>? weaponTypes,
    Map<String, int>? weaponSlots,
    String? hullEquipment,
    String? shieldEquipment,
    String? engineEquipment,
    int? hullEquipmentLevel,
    int? shieldEquipmentLevel,
    int? engineEquipmentLevel,
    Map<String, int>? cargo,
    int? drones,
    int? maxDrones,
    int? turns,
    int? maxTurns,
    int? credits,
    double? researchPoints,
    int? bankBalance,
    DateTime? lastInterestTime,
    List<String>? ownedPorts,
    int? scrapMetal,
    int? scrapTech,
    Map<String, int>? installedModules,
    FactionClass? faction,
    double? notoriety,
  }) {
    return Player(
      id: id ?? this.id,
      username: username ?? this.username,
      passwordHash: passwordHash ?? this.passwordHash,
      createdAt: createdAt ?? this.createdAt,
      name: name ?? this.name,
      currentSectorId: currentSectorId ?? this.currentSectorId,
      hull: hull ?? this.hull,
      maxHull: maxHull ?? this.maxHull,
      shields: shields ?? this.shields,
      maxShields: maxShields ?? this.maxShields,
      cargoUsed: cargoUsed ?? this.cargoUsed,
      maxCargo: maxCargo ?? this.maxCargo,
      cargoSize: cargoSize ?? this.cargoSize,
      shipDefinitionName: shipDefinitionName ?? this.shipDefinitionName,
      shipClass: shipClass ?? this.shipClass,
      weaponTypes: weaponTypes ?? this.weaponTypes,
      weaponSlots: weaponSlots ?? this.weaponSlots,
      hullEquipment: hullEquipment ?? this.hullEquipment,
      shieldEquipment: shieldEquipment ?? this.shieldEquipment,
      engineEquipment: engineEquipment ?? this.engineEquipment,
      hullEquipmentLevel: hullEquipmentLevel ?? this.hullEquipmentLevel,
      shieldEquipmentLevel: shieldEquipmentLevel ?? this.shieldEquipmentLevel,
      engineEquipmentLevel: engineEquipmentLevel ?? this.engineEquipmentLevel,
      cargo: cargo ?? this.cargo,
      drones: drones ?? this.drones,
      maxDrones: maxDrones ?? this.maxDrones,
      turns: turns ?? this.turns,
      maxTurns: maxTurns ?? this.maxTurns,
      credits: credits ?? this.credits,
      researchPoints: researchPoints ?? this.researchPoints,
      bankBalance: bankBalance ?? this.bankBalance,
      lastInterestTime: lastInterestTime ?? this.lastInterestTime,
      ownedPorts: ownedPorts ?? this.ownedPorts,
      scrapMetal: scrapMetal ?? this.scrapMetal,
      scrapTech: scrapTech ?? this.scrapTech,
      installedModules: installedModules ?? this.installedModules,
      faction: faction ?? this.faction,
      notoriety: notoriety ?? this.notoriety,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'passwordHash': passwordHash,
      'createdAt': createdAt?.toIso8601String(),
      'name': name,
      'currentSectorId': currentSectorId,
      'hull': hull,
      'maxHull': maxHull,
      'shields': shields,
      'maxShields': maxShields,
      'cargoUsed': cargoUsed,
      'maxCargo': maxCargo,
      'cargoSize': cargoSize,
      'shipDefinitionName': shipDefinitionName,
      'shipClass': shipClass.name,
      'weaponTypes': weaponTypes,
      'weaponSlots': weaponSlots,
      'hullEquipment': hullEquipment,
      'shieldEquipment': shieldEquipment,
      'engineEquipment': engineEquipment,
      'hullEquipmentLevel': hullEquipmentLevel,
      'shieldEquipmentLevel': shieldEquipmentLevel,
      'engineEquipmentLevel': engineEquipmentLevel,
      'cargo': cargo,
      'drones': drones,
      'maxDrones': maxDrones,
      'turns': turns,
      'maxTurns': maxTurns,
      'credits': credits,
      'researchPoints': researchPoints,
      'bankBalance': bankBalance,
      'lastInterestTime': lastInterestTime?.toIso8601String(),
      'ownedPorts': ownedPorts,
      'scrapMetal': scrapMetal,
      'scrapTech': scrapTech,
      'installedModules': installedModules,
      'faction': faction.name,
      'notoriety': notoriety,
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    return Player(
      id: json['id'] as String? ?? '',
      username: json['username'] as String? ?? '',
      passwordHash: json['passwordHash'] as String?,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : null,
      name: json['name'] as String? ?? '',
      currentSectorId: json['currentSectorId'] as int? ?? 1,
      hull: json['hull'] as int? ?? 100,
      maxHull: json['maxHull'] as int? ?? 100,
      shields: json['shields'] as int? ?? 100,
      maxShields: json['maxShields'] as int? ?? 100,
      cargoUsed: json['cargoUsed'] as int? ?? 0,
      maxCargo: json['maxCargo'] as int? ?? 50,
      cargoSize: json['cargoSize'] as int? ?? 50,
      shipDefinitionName:
          json['shipDefinitionName'] as String? ?? 'Starhawk Skiff',
      shipClass: ShipClassType.values.firstWhere(
        (e) => e.name == json['shipClass'],
        orElse: () => ShipClassType.interceptor,
      ),
      weaponTypes: (json['weaponTypes'] as Map<String, dynamic>?)
              ?.cast<String, String>() ??
          {},
      weaponSlots:
          (json['weaponSlots'] as Map<String, dynamic>?)?.cast<String, int>() ??
              {},
      hullEquipment: json['hullEquipment'] as String? ?? 'patchworkComposite',
      shieldEquipment: json['shieldEquipment'] as String? ?? 'merchantBuckler',
      engineEquipment: json['engineEquipment'] as String? ?? 'juryRiggedFusion',
      hullEquipmentLevel: json['hullEquipmentLevel'] as int? ?? 1,
      shieldEquipmentLevel: json['shieldEquipmentLevel'] as int? ?? 1,
      engineEquipmentLevel: json['engineEquipmentLevel'] as int? ?? 1,
      cargo:
          (json['cargo'] as Map<String, dynamic>?)?.cast<String, int>() ?? {},
      drones: json['drones'] as int? ?? 0,
      maxDrones: json['maxDrones'] as int? ?? 0,
      turns: json['turns'] as int? ?? 1000,
      maxTurns: json['maxTurns'] as int? ?? 1000,
      credits: json['credits'] as int? ?? 1000,
      researchPoints: (json['researchPoints'] as num?)?.toDouble() ?? 0.0,
      bankBalance: json['bankBalance'] as int? ?? 0,
      lastInterestTime: json['lastInterestTime'] != null
          ? DateTime.parse(json['lastInterestTime'] as String)
          : null,
      ownedPorts: (json['ownedPorts'] as List?)?.cast<String>() ?? [],
      scrapMetal: json['scrapMetal'] as int? ?? 0,
      scrapTech: json['scrapTech'] as int? ?? 0,
      installedModules: (json['installedModules'] as Map<String, dynamic>?)
              ?.cast<String, int>() ??
          {},
      faction: FactionClass.values.firstWhere(
        (e) => e.name == json['faction'],
        orElse: () => FactionClass.trader,
      ),
      notoriety: (json['notoriety'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Check if the player has turns remaining to warp.
  bool get canWarp => turns > 0;

  /// Check if the ship is critically damaged.
  bool get criticalHull => hull <= 25;

  /// Hash a password using SHA-256.
  static String hashPassword(String password) {
    return sha256.convert(utf8.encode(password)).toString();
  }

  /// Verify a password against the stored hash.
  bool verifyPassword(String password) {
    if (passwordHash == null) return false;
    return passwordHash == hashPassword(password);
  }
}

/// Extension on [Player] providing notoriety level helpers.
extension NotorietyX on Player {
  bool get isLowNotoriety => notoriety < 25.0;
  bool get isMediumNotoriety => notoriety >= 25.0 && notoriety < 50.0;
  bool get isHighNotoriety => notoriety >= 50.0 && notoriety < 75.0;
  bool get isExtremeNotoriety => notoriety >= 75.0;

  Color get notorietyColor {
    if (isLowNotoriety) return Colors.green;
    if (isMediumNotoriety) return Colors.yellow.shade700;
    if (isHighNotoriety) return Colors.orange;
    return Colors.red;
  }

  String get notorietyLabel {
    if (isLowNotoriety) return 'Low';
    if (isMediumNotoriety) return 'Medium';
    if (isHighNotoriety) return 'High';
    return 'Extreme';
  }
}
