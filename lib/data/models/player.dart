import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
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
  //
  // Legacy field retained for old save files only. B1 replaces it with
  // [energy] below; see [EnergyService].
  final int turns;
  final int maxTurns;

  // ── Energy ──────────────────────────────────────────────────
  /// Current ship energy — the B1 replacement for legacy turns. Actions such
  /// as warping, scanning, and port interactions spend energy; it is restored
  /// by refueling at ports.
  final int energy;

  /// Maximum ship energy capacity.
  final int maxEnergy;

  /// True when the Solar Array is deployed.
  ///
  /// A deployed array trickle-charges energy each tick but locks the ship in
  /// place — it must be retracted before warping.
  final bool solarArrayDeployed;

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

  // ── Faction Standing ─────────────────────────────────────────
  /// Persisted standing values keyed by faction name.
  final Map<String, int> factionStandings;

  // ── Hacking Record ───────────────────────────────────────────
  /// Number of successful port hacks completed by this player.
  final int successfulHacks;

  /// Unique port names successfully hacked, used by the hacking codex.
  final List<String> hackedPorts;

  /// Timestamp of the most recent successful port hack.
  final DateTime? lastHackAt;

  /// Number of failed hack sessions by port name.
  final Map<String, int> portHackFailures;

  /// Epoch timestamps for active port hack bans.
  final Map<String, int> portHackBannedUntil;

  /// Security profile of the most recent successful hack.
  final String? lastHackProfile;

  /// Human-readable reward from the most recent successful hack.
  final String? lastHackReward;

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
    this.energy = 1000,
    this.maxEnergy = 1000,
    this.solarArrayDeployed = false,
    required this.credits,
    required this.researchPoints,
    this.bankBalance = 0,
    this.lastInterestTime,
    this.ownedPorts = const [],
    this.scrapMetal = 0,
    this.scrapTech = 0,
    this.installedModules = const {},
    this.faction = FactionClass.trader,
    this.factionStandings = const {},
    this.successfulHacks = 0,
    this.hackedPorts = const [],
    this.lastHackAt,
    this.portHackFailures = const {},
    this.portHackBannedUntil = const {},
    this.lastHackProfile,
    this.lastHackReward,
    this.notoriety = 0.0,
  });

  bool ownsPort(String portName) => ownedPorts.contains(portName);

  int factionStandingWith(FactionClass target) {
    return factionStandings[target.name] ??
        FactionStanding.defaultFor(faction).standings[target] ??
        0;
  }

  Player withFactionStandingChange(FactionClass target, int delta) {
    final updated = Map<String, int>.from(factionStandings);
    updated[target.name] =
        FactionStanding.modifyStanding(factionStandingWith(target), delta);
    return copyWith(factionStandings: updated);
  }

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
    int? energy,
    int? maxEnergy,
    bool? solarArrayDeployed,
    int? credits,
    double? researchPoints,
    int? bankBalance,
    DateTime? lastInterestTime,
    List<String>? ownedPorts,
    int? scrapMetal,
    int? scrapTech,
    Map<String, int>? installedModules,
    FactionClass? faction,
    Map<String, int>? factionStandings,
    int? successfulHacks,
    List<String>? hackedPorts,
    DateTime? lastHackAt,
    Map<String, int>? portHackFailures,
    Map<String, int>? portHackBannedUntil,
    String? lastHackProfile,
    String? lastHackReward,
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
      energy: energy ?? this.energy,
      maxEnergy: maxEnergy ?? this.maxEnergy,
      solarArrayDeployed: solarArrayDeployed ?? this.solarArrayDeployed,
      credits: credits ?? this.credits,
      researchPoints: researchPoints ?? this.researchPoints,
      bankBalance: bankBalance ?? this.bankBalance,
      lastInterestTime: lastInterestTime ?? this.lastInterestTime,
      ownedPorts: ownedPorts ?? this.ownedPorts,
      scrapMetal: scrapMetal ?? this.scrapMetal,
      scrapTech: scrapTech ?? this.scrapTech,
      installedModules: installedModules ?? this.installedModules,
      faction: faction ?? this.faction,
      factionStandings: factionStandings ?? this.factionStandings,
      successfulHacks: successfulHacks ?? this.successfulHacks,
      hackedPorts: hackedPorts ?? this.hackedPorts,
      lastHackAt: lastHackAt ?? this.lastHackAt,
      portHackFailures: portHackFailures ?? this.portHackFailures,
      portHackBannedUntil: portHackBannedUntil ?? this.portHackBannedUntil,
      lastHackProfile: lastHackProfile ?? this.lastHackProfile,
      lastHackReward: lastHackReward ?? this.lastHackReward,
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
      'energy': energy,
      'maxEnergy': maxEnergy,
      'solarArrayDeployed': solarArrayDeployed,
      'credits': credits,
      'researchPoints': researchPoints,
      'bankBalance': bankBalance,
      'lastInterestTime': lastInterestTime?.toIso8601String(),
      'ownedPorts': ownedPorts,
      'scrapMetal': scrapMetal,
      'scrapTech': scrapTech,
      'installedModules': installedModules,
      'faction': faction.name,
      'factionStandings': factionStandings,
      'successfulHacks': successfulHacks,
      'hackedPorts': hackedPorts,
      'lastHackAt': lastHackAt?.toIso8601String(),
      'portHackFailures': portHackFailures,
      'portHackBannedUntil': portHackBannedUntil,
      'lastHackProfile': lastHackProfile,
      'lastHackReward': lastHackReward,
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
      energy: json['energy'] as int? ?? json['turns'] as int? ?? 1000,
      maxEnergy: json['maxEnergy'] as int? ?? json['maxTurns'] as int? ?? 1000,
      solarArrayDeployed: json['solarArrayDeployed'] as bool? ?? false,
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
      factionStandings:
          (json['factionStandings'] as Map?)?.cast<String, int>() ?? const {},
      successfulHacks: json['successfulHacks'] as int? ?? 0,
      hackedPorts: (json['hackedPorts'] as List?)?.cast<String>() ?? const [],
      lastHackAt: json['lastHackAt'] != null
          ? DateTime.parse(json['lastHackAt'] as String)
          : null,
      portHackFailures:
          (json['portHackFailures'] as Map?)?.cast<String, int>() ?? const {},
      portHackBannedUntil:
          (json['portHackBannedUntil'] as Map?)?.cast<String, int>() ??
              const {},
      lastHackProfile: json['lastHackProfile'] as String?,
      lastHackReward: json['lastHackReward'] as String?,
      notoriety: (json['notoriety'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// Check if the player has energy remaining to warp.
  bool get canWarp => energy > 0;

  /// True when the ship is free to move (a deployed Solar Array locks it).
  bool get canMove => !solarArrayDeployed;

  /// True when [cost] energy can be spent right now.
  bool hasEnergy(int cost) => energy >= cost;

  /// Returns a copy with [cost] energy deducted, clamped at zero.
  Player spendEnergy(int cost) {
    final next = energy - cost;
    return copyWith(energy: next < 0 ? 0 : next);
  }

  /// Returns a copy with [amount] energy restored, clamped to [maxEnergy].
  Player refuelEnergy(int amount) {
    final next = energy + amount;
    return copyWith(energy: next > maxEnergy ? maxEnergy : next);
  }

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
