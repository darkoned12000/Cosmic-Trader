import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
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

  // ── Energy (B1 fuel; pre-B1 saves migrate via fromJson legacy keys) ──
  /// Current ship energy — actions such as warping, scanning, and port
  /// interactions spend energy; it is restored by refueling at ports.
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

  // ── Bounty kills ────────────────────────────────────────────
  /// Victim ids this player has destroyed (capped). The Bounty Board pays
  /// claims against these ids through its Claim action.
  final List<String> recentKills;

  // ── Appearance ──────────────────────────────────────────────
  /// Chosen pilot portrait, or `null` for accounts saved before avatars
  /// existed. Left nullable deliberately: that makes migration inert (no
  /// backfill pass over `players.json`) and self-healing, since
  /// [effectiveAvatar] resolves a valid faction default on read.
  final AvatarSelection? avatar;

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
    this.recentKills = const [],
    this.avatar,
  });

  /// Records a kill for bounty claims (newest first, capped at 50).
  Player withKill(String victimId) {
    final kills = [victimId, ...recentKills];
    while (kills.length > 50) {
      kills.removeLast();
    }
    return copyWith(recentKills: kills);
  }

  /// Clone reissue after death (no permadeath for pilots): the wreck
  /// and its cargo/credits are gone, replaced by the faction starter
  /// interceptor with starter fittings, holds, drones, energy, and
  /// credits — mirroring registration exactly. Identity and assets
  /// survive: name, faction, bank, ports, standings, notoriety, hack
  /// record, deployed arrays, research. Wakes at Terra Prime (sector 1).
  Player respawned(GameSettings settings) {
    final shipDef = ShipDefinition.getDefaultInterceptor(faction);
    final weaponTypes = <String, String>{};
    final weaponSlots = <String, int>{};
    for (int i = 0; i < shipDef.weaponSlots.length; i++) {
      final slotName = shipDef.weaponSlots[i];
      weaponTypes[slotName] = shipDef.preferredWeapons[i].name;
      weaponSlots[slotName] = 1;
    }
    return copyWith(
      currentSectorId: 1,
      hull: shipDef.maxHullCapacity,
      maxHull: shipDef.maxHullCapacity,
      shields: shipDef.shields,
      maxShields: shipDef.maxShields,
      cargoUsed: 0,
      maxCargo: shipDef.maxCargo,
      cargoSize: shipDef.maxCargo,
      shipDefinitionName: shipDef.name,
      shipClass: ShipClassType.interceptor,
      weaponTypes: weaponTypes,
      weaponSlots: weaponSlots,
      hullEquipment: shipDef.hullType.name,
      shieldEquipment: shipDef.shieldType.name,
      engineEquipment: shipDef.engineType.name,
      hullEquipmentLevel: 1,
      shieldEquipmentLevel: 1,
      engineEquipmentLevel: 1,
      cargo: const {},
      drones: settings.initDrones,
      maxDrones: settings.initDrones,
      energy: settings.initEnergy,
      maxEnergy: settings.initEnergy,
      credits: settings.initCredits,
      installedModules: const {},
    );
  }

  bool ownsPort(String portName) => ownedPorts.contains(portName);

  /// The portrait to actually draw for this player.
  ///
  /// Always a valid, renderable selection. This is the single place screens
  /// should read — it repairs a stale save whose portrait no longer exists in
  /// the catalogue, and a species that disagrees with [faction] (for example
  /// after a future faction change), rather than showing wrong-faction art or a
  /// missing-asset box. Accounts saved before avatars existed resolve here to
  /// their faction's curated default, so no migration pass is needed.
  AvatarSelection get effectiveAvatar =>
      (avatar ?? AvatarSelection.defaultFor(faction)).forFaction(faction);

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
    List<String>? recentKills,
    AvatarSelection? avatar,
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
      recentKills: recentKills ?? this.recentKills,
      // Mirrors every other field's `?? this.x` semantics. Note this means a
      // selection can never be set back to null through copyWith — which is
      // fine, because "reset" is expressed as an explicit faction default
      // rather than as an absent value.
      avatar: avatar ?? this.avatar,
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
      'recentKills': recentKills,
      'avatar': avatar?.toJson(),
    };
  }

  factory Player.fromJson(Map<String, dynamic> json) {
    // Hoisted out of the literal so the avatar decode can repair against the
    // same faction the rest of the record is built with.
    final faction = FactionClass.values.firstWhere(
      (e) => e.name == json['faction'],
      orElse: () => FactionClass.trader,
    );

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
      // Pre-energy save migration: legacy 'turns' keys seed the tank.
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
      faction: faction,
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
      recentKills: (json['recentKills'] as List?)?.cast<String>() ?? const [],
      // Pre-avatar saves have no key at all. Staying null (rather than
      // backfilling) keeps the migration inert; `effectiveAvatar` resolves a
      // faction default on read. A malformed map is handed to the tolerant
      // decoder, which repairs it against the same faction as the record.
      avatar: json['avatar'] is Map
          ? AvatarSelection.fromJson(
              (json['avatar'] as Map).cast<String, dynamic>(),
              fallbackFaction: faction,
            )
          : null,
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
