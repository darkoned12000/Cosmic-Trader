import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/ship_equipment_types.dart';

// ── Categories ─────────────────────────────────────────
enum HardwareCategory {
  service,
  hull,
  shield,
  engine,
  weapon,
  module,
}

// ── Hardware Item ──────────────────────────────────────
class HardwareItem {
  final String id;
  final String name;
  final String description;
  final HardwareCategory category;
  final FactionClass? faction;
  final int level;
  final int priceCredits;
  final int priceScrapMetal;
  final int priceScrapTech;
  final String? equipKey;
  final String? statLine;

  const HardwareItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    this.faction,
    required this.level,
    required this.priceCredits,
    this.priceScrapMetal = 0,
    this.priceScrapTech = 0,
    this.equipKey,
    this.statLine,
  });

  int get scrapMetalReturn {
    if (priceScrapMetal > 0) {
      return (priceScrapMetal * 0.5).round().clamp(5, priceScrapMetal);
    }
    return 5;
  }

  int get scrapTechReturn {
    if (priceScrapTech > 0) {
      return (priceScrapTech * 0.3).round().clamp(0, priceScrapTech);
    }
    return 0;
  }
}

// ── Module definitions ─────────────────────────────────
class ModuleDef {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final FactionClass? faction;
  final String Function(int level) statLine;

  const ModuleDef({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    this.faction,
    required this.statLine,
  });
}

// ── Module defs ────────────────────────────────────────
final moduleDefs = <ModuleDef>[
  ModuleDef(
    id: 'warpCoreBooster',
    name: 'Warp Core Booster',
    description: 'Enhances FTL drive efficiency for extended jumps',
    icon: Icons.rocket_rounded,
    statLine: _warpBoostStat,
  ),
  ModuleDef(
    id: 'targetingComputer',
    name: 'Targeting Computer',
    description: 'Advanced fire-control with predictive tracking',
    icon: Icons.track_changes_rounded,
    statLine: (l) => 'Accuracy +${10 * l}%',
  ),
  ModuleDef(
    id: 'cargoExpansion',
    name: 'Cargo Expansion Kit',
    description: 'Adds extra storage compartments to hold',
    icon: Icons.inventory_2_rounded,
    statLine: (l) => 'Cargo +${10 * l}',
  ),
  ModuleDef(
    id: 'autoRepair',
    name: 'Auto-Repair System',
    description: 'Nanite drones repair hull damage over time',
    icon: Icons.healing_rounded,
    statLine: (l) => 'Hull Regen +${l}/turn',
  ),
  ModuleDef(
    id: 'shieldCapacitor',
    name: 'Shield Capacitor',
    description: 'Increases maximum shield capacity',
    icon: Icons.shield_rounded,
    statLine: (l) => 'Max Shields +${15 * l}',
  ),
  ModuleDef(
    id: 'cloakGenerator',
    name: 'Cloak Generator',
    description: 'Merges hull with local space-time',
    icon: Icons.visibility_off_rounded,
    faction: FactionClass.vinari,
    statLine: (l) => 'Cloak Power ${20 * l}%',
  ),
  ModuleDef(
    id: 'afterburner',
    name: 'Afterburner',
    description: 'Emergency speed boost for combat maneuvers',
    icon: Icons.local_fire_department_rounded,
    faction: FactionClass.duran,
    statLine: (l) => 'Speed +${2 * l}',
  ),
  ModuleDef(
    id: 'cargoShield',
    name: 'Cargo Shield',
    description: 'Protects cargo from damage in combat',
    icon: Icons.lock_outline_rounded,
    faction: FactionClass.trader,
    statLine: (l) => 'Cargo Protection ${15 * l}%',
  ),
];

String _warpBoostStat(int level) {
  return 'Warp Range +$level';
}

// ── Item generation ────────────────────────────────────
String _equipName(String enumName) {
  final buf = StringBuffer();
  for (int i = 0; i < enumName.length; i++) {
    final c = enumName[i];
    if (i == 0) {
      buf.write(c.toUpperCase());
    } else if (c == c.toUpperCase() && c != c.toLowerCase()) {
      buf.write(' ');
      buf.write(c);
    } else {
      buf.write(c);
    }
  }
  return buf.toString().replaceAll('_', ' ');
}

// ── Generate weapons ───────────────────────────────────
List<HardwareItem> _generateWeapons() {
  final items = <HardwareItem>[];
  for (final w in WeaponType.values) {
    final faction = w.getFaction();
    final baseName = _equipName(w.name);
    for (int lv = 1; lv <= 5; lv++) {
      final costMult = 1 << (lv - 1);
      final scrapMetalReq = lv >= 3 ? 75 * costMult : 0;
      final scrapTechReq = lv >= 4 ? 10 * (lv - 3) : 0;
      items.add(HardwareItem(
        id: 'weapon_${w.name}_lv$lv',
        name: '$baseName Lv.$lv',
        description: _weaponDescription(w),
        category: HardwareCategory.weapon,
        faction: faction,
        level: lv,
        priceCredits: w.cost * costMult,
        priceScrapMetal: scrapMetalReq,
        priceScrapTech: scrapTechReq,
        equipKey: w.name,
        statLine: 'DMG ${w.damageAtLevel(lv)} | ROF ${w.fireRateAtLevel(lv)}',
      ));
    }
  }
  return items;
}

String _weaponDescription(WeaponType w) {
  switch (w) {
    case WeaponType.plasmaLance:
      return 'Heavy plasma bolt projector';
    case WeaponType.shredderCannon:
      return 'Rapid-fire kinetic shredder';
    case WeaponType.swarmMissile:
      return 'Homing missile swarm launcher';
    case WeaponType.ruptureTorpedo:
      return 'Armor-piercing torpedo tube';
    case WeaponType.energyTendril:
      return 'Precision energy tendril array';
    case WeaponType.harmonicPulse:
      return 'Resonance field harmonic projector';
    case WeaponType.phaseBeam:
      return 'Phased particle beam cannon';
    case WeaponType.novaLance:
      return 'Nova-grade energy lance';
    case WeaponType.autoLaser:
      return 'Standard auto-tracking laser';
    case WeaponType.railAccelerator:
      return 'Magnetic rail accelerator';
    case WeaponType.scavengedParticle:
      return 'Retrofitted particle blaster';
    case WeaponType.torpedoPod:
      return 'Remote torpedo pod system';
  }
}

// ── Generate hulls ─────────────────────────────────────
List<HardwareItem> _generateHulls() {
  final items = <HardwareItem>[];
  for (final h in HullType.values) {
    final faction = h.getFaction();
    final baseName = _equipName(h.name);
    final baseCost = h.baseHullBonus * 800;
    for (int lv = 1; lv <= 5; lv++) {
      final costMult = 1 << (lv - 1);
      final scrapMetalReq = lv >= 2 ? 50 * costMult : 0;
      final scrapTechReq = lv >= 4 ? 5 * (lv - 3) : 0;
      items.add(HardwareItem(
        id: 'hull_${h.name}_lv$lv',
        name: '$baseName Lv.$lv',
        description: _hullDescription(h),
        category: HardwareCategory.hull,
        faction: faction,
        level: lv,
        priceCredits: baseCost * costMult,
        priceScrapMetal: scrapMetalReq,
        priceScrapTech: scrapTechReq,
        equipKey: h.name,
        statLine: 'HULL +${h.hullBonusAtLevel(lv)} | DEF ${h.defenseAtLevel(lv)}',
      ));
    }
  }
  return items;
}

String _hullDescription(HullType h) {
  switch (h) {
    case HullType.chitinPlating:
      return 'Chitin-reinforced insectoid plating';
    case HullType.obsidianForge:
      return 'Forged obsidian composite armor';
    case HullType.slabBulkhead:
      return 'Heavy slab bulkhead sections';
    case HullType.rendArmor:
      return 'Advanced rend-forged armor';
    case HullType.bioCrystalline:
      return 'Living bio-crystalline structure';
    case HullType.auroraWeave:
      return 'Energy-woven aurora membrane';
    case HullType.nebulaMembrane:
      return 'Nebula-infused adaptive membrane';
    case HullType.starlightShell:
      return 'Starlight-hardened crystalline shell';
    case HullType.patchworkComposite:
      return 'Patched composite alloy hull';
    case HullType.reinforcedBulk:
      return 'Reinforced bulkhead plating';
    case HullType.modularSectional:
      return 'Modular sectional armor plates';
    case HullType.scavengedPlate:
      return 'Salvaged plate overlay armor';
  }
}

// ── Generate shields ───────────────────────────────────
List<HardwareItem> _generateShields() {
  final items = <HardwareItem>[];
  for (final s in ShieldType.values) {
    final faction = s.getFaction();
    final baseName = _equipName(s.name);
    final baseCost = s.baseShieldBonus * 1000;
    for (int lv = 1; lv <= 5; lv++) {
      final costMult = 1 << (lv - 1);
      final scrapMetalReq = lv >= 2 ? 40 * costMult : 0;
      final scrapTechReq = lv >= 4 ? 5 * (lv - 3) : 0;
      items.add(HardwareItem(
        id: 'shield_${s.name}_lv$lv',
        name: '$baseName Lv.$lv',
        description: _shieldDescription(s),
        category: HardwareCategory.shield,
        faction: faction,
        level: lv,
        priceCredits: baseCost * costMult,
        priceScrapMetal: scrapMetalReq,
        priceScrapTech: scrapTechReq,
        equipKey: s.name,
        statLine:
            'SHIELD +${s.shieldBonusAtLevel(lv)} | REGEN ${s.regenAtLevel(lv)}',
      ));
    }
  }
  return items;
}

String _shieldDescription(ShieldType s) {
  switch (s) {
    case ShieldType.kineticBarrier:
      return 'Kinetic barrier deflector array';
    case ShieldType.plasmaForge:
      return 'Plasma-forged energy shield';
    case ShieldType.warlordWard:
      return 'Warlord-grade defensive ward';
    case ShieldType.hegemonyShell:
      return 'Hegemony-class shell barrier';
    case ShieldType.harmonicField:
      return 'Harmonic resonance field';
    case ShieldType.phaseWeave:
      return 'Phase-shifted energy weave';
    case ShieldType.auroraVeil:
      return 'Aurora-grade energy veil';
    case ShieldType.symbioticWard:
      return 'Symbiotic living ward';
    case ShieldType.merchantBuckler:
      return 'Standard merchant buckler';
    case ShieldType.smugglingJammer:
      return 'Smuggler frequency jammer';
    case ShieldType.convoyBarrier:
      return 'Convoy-rated barrier shield';
    case ShieldType.salvageMatrix:
      return 'Salvaged matrix deflector';
  }
}

// ── Generate engines ───────────────────────────────────
List<HardwareItem> _generateEngines() {
  final items = <HardwareItem>[];
  for (final e in EngineType.values) {
    final faction = e.getFaction();
    final baseName = _equipName(e.name);
    final baseCost = e.speedBonus * 1200;
    for (int lv = 1; lv <= 5; lv++) {
      final costMult = 1 << (lv - 1);
      final scrapMetalReq = lv >= 2 ? 60 * costMult : 0;
      final scrapTechReq = lv >= 4 ? 8 * (lv - 3) : 0;
      items.add(HardwareItem(
        id: 'engine_${e.name}_lv$lv',
        name: '$baseName Lv.$lv',
        description: _engineDescription(e),
        category: HardwareCategory.engine,
        faction: faction,
        level: lv,
        priceCredits: baseCost * costMult,
        priceScrapMetal: scrapMetalReq,
        priceScrapTech: scrapTechReq,
        equipKey: e.name,
        statLine:
            'SPD ${e.speedAtLevel(lv)} | WARP ${e.warpAtLevel(lv)} | EFF ${e.efficiencyAtLevel(lv)}',
      ));
    }
  }
  return items;
}

String _engineDescription(EngineType e) {
  switch (e) {
    case EngineType.volcanicThrust:
      return 'Volcanic-force thrust engine';
    case EngineType.warforgeDrive:
      return 'Warforge combat drive system';
    case EngineType.rendPulse:
      return 'Rend-pulse FTL drive';
    case EngineType.bioPlasmaSail:
      return 'Bio-plasma solar sail drive';
    case EngineType.harmonicDrift:
      return 'Harmonic drift FTL drive';
    case EngineType.celestialFlow:
      return 'Celestial flow drive';
    case EngineType.juryRiggedFusion:
      return 'Jury-rigged fusion engine';
    case EngineType.salvagedImpulse:
      return 'Salvaged impulse drive';
    case EngineType.convoyOverdrive:
      return 'Convoy overdrive engine';
  }
}

// ── Generate modules ───────────────────────────────────
List<HardwareItem> _generateModules() {
  final items = <HardwareItem>[];
  for (final m in moduleDefs) {
    for (int lv = 1; lv <= 5; lv++) {
      final costMult = 1 << (lv - 1);
      final scrapMetalReq = 30 * costMult;
      final scrapTechReq = 5 * lv;
      items.add(HardwareItem(
        id: 'module_${m.id}_lv$lv',
        name: '${m.name} Lv.$lv',
        description: m.description,
        category: HardwareCategory.module,
        faction: m.faction,
        level: lv,
        priceCredits: 75000 * costMult,
        priceScrapMetal: scrapMetalReq,
        priceScrapTech: scrapTechReq,
        equipKey: m.id,
        statLine: m.statLine(lv),
      ));
    }
  }
  return items;
}

// ── Service pricing ────────────────────────────────────
const int shieldRechargeCostPerPoint = 3;
const int hullRepairCostPerPoint = 5;
const int droneCostCredits = 15000;
const int droneCostScrapMetal = 100;
const int droneCostScrapTech = 5;

// ── Scrap exchange rates ───────────────────────────────
const int scrapMetalSellPrice = 5;
const int scrapTechSellPrice = 50;

// ── Master item list ───────────────────────────────────
List<HardwareItem> _allItems = [];

List<HardwareItem> get allHardwareItems {
  if (_allItems.isEmpty) {
    _allItems = [
      ..._generateWeapons(),
      ..._generateHulls(),
      ..._generateShields(),
      ..._generateEngines(),
      ..._generateModules(),
    ];
  }
  return _allItems;
}

List<HardwareItem> itemsForCategory(HardwareCategory cat) {
  return allHardwareItems.where((i) => i.category == cat).toList();
}

List<HardwareItem> itemsForFaction(
    HardwareCategory cat, FactionClass? faction) {
  return allHardwareItems.where((i) {
    if (i.category != cat) return false;
    if (i.faction != null && i.faction != faction) return false;
    return true;
  }).toList();
}

HardwareItem? findItemById(String id) {
  try {
    return allHardwareItems.firstWhere((i) => i.id == id);
  } catch (_) {
    return null;
  }
}

HardwareItem? itemFor(String equipKey, HardwareCategory category, int level) {
  try {
    return allHardwareItems.firstWhere(
      (i) =>
          i.equipKey == equipKey &&
          i.category == category &&
          i.level == level,
    );
  } catch (_) {
    return null;
  }
}
