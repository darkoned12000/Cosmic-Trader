import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
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

  /// Game tick at which interest was last paid out. Null = never.
  ///
  /// **Ticks, not a timestamp.** See `GameClock`. A DateTime here meant a
  /// player who closed the game for a week came back to seven days of
  /// interest for a week they never played, while a player who played seven
  /// hours earned almost nothing — the rate depended on how the session was
  /// cut up, which is not what a daily rate means.
  final int? lastInterestTick;

  // ── Port Ownership ──────────────────────────────────────────
  final List<String> ownedPorts;

  // ── Scrap & Modules ─────────────────────────────────────────
  final int scrapMetal;

  /// Genesis Torpedoes held. Each occupies one cargo slot, so the hold bounds
  /// the stockpile rather than a separate carrying rule.
  final int genesisTorpedoes;

  /// Atomic Detonators held. Same cargo bound as [genesisTorpedoes].
  final int atomicDetonators;
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
  /// Port name -> game tick at which its hack ban expires.
  ///
  /// **Ticks, not milliseconds.** These were epoch timestamps, which meant a
  /// 24-hour ban was a ban the player cleared by quitting and reopening: the
  /// stored deadline kept being compared against a clock that ran while the
  /// game was closed, and the comparison was the only thing enforcing it.
  final Map<String, int> portHackBannedUntilTick;

  /// Game tick at which the current lottery day began, and how many of the
  /// three allowed plays have been used.
  ///
  /// **Persisted**, which is the whole point and was the bug. Both of these
  /// lived in the lottery widget's `State`, so the daily limit reset every
  /// time the player left the tab — an unlimited number of plays by dipping
  /// in and out. A rate limit that resets when you look away is not a rate
  /// limit. See `GameClock` for why the deadline is ticks.
  final int lotteryPeriodStartTick;
  final int lotteryPlaysThisPeriod;

  /// Security profile of the most recent successful hack.
  final String? lastHackProfile;

  /// Human-readable reward from the most recent successful hack.
  final String? lastHackReward;

  // ── Reputation ───────────────────────────────────────────────
  /// Global reputation, **signed**. Positive means the galaxy is inclined to
  /// trust you; negative means it has a file on you.
  ///
  /// This replaces a `notoriety` field that started at zero and only ever rose
  /// as a "how noticed are you" counter, clamped 0-100. That scale could not
  /// express being well thought of at all — the best act and the worst pushed
  /// the same direction — and "higher makes NPCs more aggressive" was true of a
  /// threat scalar, not of a reputation. Ranged ±[Reputation.absMax] to match the
  /// TradeWars ladder; see `alignment.dart`.
  final double alignment;

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
    this.lastInterestTick,
    this.ownedPorts = const [],
    this.scrapMetal = 0,
    this.genesisTorpedoes = 0,
    this.atomicDetonators = 0,
    this.scrapTech = 0,
    this.installedModules = const {},
    this.faction = FactionClass.trader,
    this.factionStandings = const {},
    this.successfulHacks = 0,
    this.hackedPorts = const [],
    this.lastHackAt,
    this.portHackFailures = const {},
    this.portHackBannedUntilTick = const {},
    this.lotteryPeriodStartTick = 0,
    this.lotteryPlaysThisPeriod = 0,
    this.lastHackProfile,
    this.lastHackReward,
    this.alignment = 0.0,
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

  /// Moves reputation by [delta] and returns the new player.
  ///
  /// The single way alignment changes. Two reasons it is not left to a bare
  /// `copyWith(alignment: x + n)` at each call site: the clamp has to apply
  /// everywhere, or a long enough career walks off the end of its own ladder and
  /// the display has to invent an answer past the last rung; and the *sign* is
  /// the thing most likely to be got wrong by hand, so [ReputationActions] holds
  /// the signed values and callers pass one of those rather than a literal.
  Player withAlignmentDelta(double delta) =>
      copyWith(alignment: alignment + delta);

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
    int? lastInterestTick,
    List<String>? ownedPorts,
    int? scrapMetal,
    int? genesisTorpedoes,
    int? atomicDetonators,
    int? scrapTech,
    Map<String, int>? installedModules,
    FactionClass? faction,
    Map<String, int>? factionStandings,
    int? successfulHacks,
    List<String>? hackedPorts,
    DateTime? lastHackAt,
    Map<String, int>? portHackFailures,
    Map<String, int>? portHackBannedUntilTick,
    int? lotteryPeriodStartTick,
    int? lotteryPlaysThisPeriod,
    String? lastHackProfile,
    String? lastHackReward,
    double? alignment,
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
      lastInterestTick: lastInterestTick ?? this.lastInterestTick,
      ownedPorts: ownedPorts ?? this.ownedPorts,
      scrapMetal: scrapMetal ?? this.scrapMetal,
      genesisTorpedoes: genesisTorpedoes ?? this.genesisTorpedoes,
      atomicDetonators: atomicDetonators ?? this.atomicDetonators,
      scrapTech: scrapTech ?? this.scrapTech,
      installedModules: installedModules ?? this.installedModules,
      faction: faction ?? this.faction,
      factionStandings: factionStandings ?? this.factionStandings,
      successfulHacks: successfulHacks ?? this.successfulHacks,
      hackedPorts: hackedPorts ?? this.hackedPorts,
      lastHackAt: lastHackAt ?? this.lastHackAt,
      portHackFailures: portHackFailures ?? this.portHackFailures,
      portHackBannedUntilTick:
          portHackBannedUntilTick ?? this.portHackBannedUntilTick,
      lotteryPeriodStartTick:
          lotteryPeriodStartTick ?? this.lotteryPeriodStartTick,
      lotteryPlaysThisPeriod:
          lotteryPlaysThisPeriod ?? this.lotteryPlaysThisPeriod,
      lastHackProfile: lastHackProfile ?? this.lastHackProfile,
      lastHackReward: lastHackReward ?? this.lastHackReward,
      alignment: Reputation.clamp(alignment ?? this.alignment),
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
      'lastInterestTick': lastInterestTick,
      'ownedPorts': ownedPorts,
      'scrapMetal': scrapMetal,
      'scrapTech': scrapTech,
      'genesisTorpedoes': genesisTorpedoes,
      'atomicDetonators': atomicDetonators,
      'installedModules': installedModules,
      'faction': faction.name,
      'factionStandings': factionStandings,
      'successfulHacks': successfulHacks,
      'hackedPorts': hackedPorts,
      'lastHackAt': lastHackAt?.toIso8601String(),
      'portHackFailures': portHackFailures,
      'portHackBannedUntilTick': portHackBannedUntilTick,
      'lotteryPeriodStartTick': lotteryPeriodStartTick,
      'lotteryPlaysThisPeriod': lotteryPlaysThisPeriod,
      'lastHackProfile': lastHackProfile,
      'lastHackReward': lastHackReward,
      'alignment': alignment,
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
      // A pre-clock save holds a wall-clock timestamp here. Read as nothing:
      // there is no correct conversion to ticks, and guessing would either
      // pay a year of interest on load or none at all. Starting unpaid is
      // the safe reading and costs the player nothing they had.
      lastInterestTick: (json['lastInterestTick'] as num?)?.toInt(),
      ownedPorts: (json['ownedPorts'] as List?)?.cast<String>() ?? [],
      scrapMetal: json['scrapMetal'] as int? ?? 0,
      genesisTorpedoes: json['genesisTorpedoes'] as int? ?? 0,
      atomicDetonators: json['atomicDetonators'] as int? ?? 0,
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
      // A pre-tick save holds epoch milliseconds here. Dropped rather than
      // converted: the units are not comparable, and guessing would either
      // ban the player for years or free them instantly. Losing a ban on
      // migration is the right direction — it costs a cooldown, where the
      // alternative costs a fight they did not start.
      portHackBannedUntilTick:
          (json['portHackBannedUntilTick'] as Map?)?.cast<String, int>() ??
              const {},
      // Absent in every pre-clock save. 0 means "period not started", which
      // the widget reads as a fresh allowance — the same three plays a player
      // would have had anyway, so migration cannot be used to buy extra ones.
      lotteryPeriodStartTick:
          (json['lotteryPeriodStartTick'] as num?)?.toInt() ?? 0,
      lotteryPlaysThisPeriod:
          (json['lotteryPlaysThisPeriod'] as num?)?.toInt() ?? 0,
      lastHackProfile: json['lastHackProfile'] as String?,
      lastHackReward: json['lastHackReward'] as String?,
      // Migrated by **negating**. The old scale counted upwards for bad deeds;
      // this one counts downwards for them, so a save written when the worst a
      // pilot could be was "50" becomes −50 rather than being read as a good
      // reputation. A player at exactly 0 is unaffected either way, which is
      // most of them.
      alignment: Reputation.clamp(
        (json['alignment'] as num?)?.toDouble() ??
            -((json['notoriety'] as num?)?.toDouble() ?? 0.0),
      ),
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

/// Display helpers for a signed [Player.alignment].
///
/// The colour and the sign have to agree or the bar lies: a well-liked pilot
/// whose reputation reads as alarming is worse than no readout at all.
extension AlignmentX on Player {
  ReputationSide get alignmentSide => Reputation.sideOf(alignment);

  ReputationRank get alignmentRank => Reputation.rankFor(alignment);

  String get alignmentTitle => alignmentRank.titleFor(alignmentSide);

  /// Next rank up in this direction, or null at the top of the ladder.
  ReputationRank? get nextAlignmentRank => Reputation.nextRank(alignment);

  int? get alignmentPointsToNext => Reputation.pointsToNext(alignment);

  /// 0..1 through the current band.
  double get alignmentProgress => Reputation.progressToNext(alignment);

  /// Signed magnitude, because a bar drawn from zero has to grow either way.
  double get alignmentMagnitude => alignment.abs();

  /// How dangerous the galaxy finds this pilot: zero for the best-liked, rising
  /// as alignment falls.
  ///
  /// Deliberately **one-sided**. Every consumer of the old `notoriety` was
  /// asking "should I be afraid of this person", and under a signed scale the
  /// honest answer for a well-liked pilot is not "equally not" but *less*: being
  /// regarded is supposed to make you safer. Folding that into one number keeps
  /// the three AI call sites from each re-deciding it.
  double get threatRating => alignment <= 0 ? -alignment : 0.0;

  Color get alignmentColor => switch (alignmentSide) {
        ReputationSide.good => Colors.green.shade400,
        ReputationSide.neutral => Colors.blueGrey,
        ReputationSide.evil => Colors.red.shade400,
      };

  /// Plain-language reading of the sign, for the reputation card.
  String get alignmentDescriptor => switch (alignmentSide) {
        ReputationSide.good => 'Law-abiding',
        ReputationSide.neutral => 'Unknown to the galaxy',
        ReputationSide.evil => 'Notorious',
      };
}
