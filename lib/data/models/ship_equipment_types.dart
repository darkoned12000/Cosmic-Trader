// ship_equipment_types.dart

import './faction.dart';

// ── HULL TYPES (Faction Specific) ─────────────────────
enum HullType {
  // Duran
  chitinPlating,
  obsidianForge,
  slabBulkhead,
  rendArmor,

  // Vinari
  bioCrystalline,
  auroraWeave,
  nebulaMembrane,
  starlightShell,

  // Traders
  patchworkComposite,
  reinforcedBulk,
  modularSectional,
  scavengedPlate,
}

// ── SHIELD TYPES (Faction Specific) ───────────────────
enum ShieldType {
  // Duran
  kineticBarrier,
  plasmaForge,
  warlordWard,
  hegemonyShell,

  // Vinari
  harmonicField,
  phaseWeave,
  auroraVeil,
  symbioticWard,

  // Traders
  merchantBuckler,
  smugglingJammer,
  convoyBarrier,
  salvageMatrix,
}

// ── ENGINE TYPES (Faction Themed) ─────────────────────
enum EngineType {
  // Duran - Brutal & powerful
  volcanicThrust,
  warforgeDrive,
  rendPulse,

  // Vinari - Elegant & efficient
  bioPlasmaSail,
  harmonicDrift,
  celestialFlow,

  // Traders - Versatile & modified
  juryRiggedFusion,
  salvagedImpulse,
  convoyOverdrive,
}

// ── WEAPON TYPES (Faction Themed) ─────────────────────
enum WeaponType {
  // Duran - Heavy, destructive
  plasmaLance,
  shredderCannon,
  swarmMissile,
  ruptureTorpedo,

  // Vinari - Precise, energy-based
  energyTendril,
  harmonicPulse,
  phaseBeam,
  novaLance,

  // Traders - Mixed / practical
  autoLaser,
  railAccelerator,
  scavengedParticle,
  torpedoPod,
}

// ── FACTION COMPATIBILITY EXTENSIONS ──────────────────

extension HullFaction on HullType {
  FactionClass getFaction() {
    switch (this) {
      case HullType.chitinPlating:
      case HullType.obsidianForge:
      case HullType.slabBulkhead:
      case HullType.rendArmor:
        return FactionClass.duran;
      case HullType.bioCrystalline:
      case HullType.auroraWeave:
      case HullType.nebulaMembrane:
      case HullType.starlightShell:
        return FactionClass.vinari;
      case HullType.patchworkComposite:
      case HullType.reinforcedBulk:
      case HullType.modularSectional:
      case HullType.scavengedPlate:
        return FactionClass.trader;
    }
  }
}

extension ShieldFaction on ShieldType {
  FactionClass getFaction() {
    switch (this) {
      case ShieldType.kineticBarrier:
      case ShieldType.plasmaForge:
      case ShieldType.warlordWard:
      case ShieldType.hegemonyShell:
        return FactionClass.duran;
      case ShieldType.harmonicField:
      case ShieldType.phaseWeave:
      case ShieldType.auroraVeil:
      case ShieldType.symbioticWard:
        return FactionClass.vinari;
      case ShieldType.merchantBuckler:
      case ShieldType.smugglingJammer:
      case ShieldType.convoyBarrier:
      case ShieldType.salvageMatrix:
        return FactionClass.trader;
    }
  }
}

extension EngineFaction on EngineType {
  FactionClass getFaction() {
    switch (this) {
      case EngineType.volcanicThrust:
      case EngineType.warforgeDrive:
      case EngineType.rendPulse:
        return FactionClass.duran;
      case EngineType.bioPlasmaSail:
      case EngineType.harmonicDrift:
      case EngineType.celestialFlow:
        return FactionClass.vinari;
      case EngineType.juryRiggedFusion:
      case EngineType.salvagedImpulse:
      case EngineType.convoyOverdrive:
        return FactionClass.trader;
    }
  }
}

extension WeaponFaction on WeaponType {
  FactionClass getFaction() {
    switch (this) {
      case WeaponType.plasmaLance:
      case WeaponType.shredderCannon:
      case WeaponType.swarmMissile:
      case WeaponType.ruptureTorpedo:
        return FactionClass.duran;
      case WeaponType.energyTendril:
      case WeaponType.harmonicPulse:
      case WeaponType.phaseBeam:
      case WeaponType.novaLance:
        return FactionClass.vinari;
      case WeaponType.autoLaser:
      case WeaponType.railAccelerator:
      case WeaponType.scavengedParticle:
      case WeaponType.torpedoPod:
        return FactionClass.trader;
    }
  }
}

// ── WEAPON STATS ──────────────────────────────────────
// classTier: 1=interceptor+, 2=battleship+, 3=capitalShip only

extension WeaponStats on WeaponType {
  int get damage {
    switch (this) {
      case WeaponType.plasmaLance:
        return 35;
      case WeaponType.shredderCannon:
        return 60;
      case WeaponType.swarmMissile:
        return 95;
      case WeaponType.ruptureTorpedo:
        return 80;
      case WeaponType.energyTendril:
        return 30;
      case WeaponType.harmonicPulse:
        return 45;
      case WeaponType.phaseBeam:
        return 70;
      case WeaponType.novaLance:
        return 90;
      case WeaponType.autoLaser:
        return 25;
      case WeaponType.railAccelerator:
        return 50;
      case WeaponType.scavengedParticle:
        return 40;
      case WeaponType.torpedoPod:
        return 65;
    }
  }

  int get fireRate {
    switch (this) {
      case WeaponType.plasmaLance:
        return 40;
      case WeaponType.shredderCannon:
        return 20;
      case WeaponType.swarmMissile:
        return 10;
      case WeaponType.ruptureTorpedo:
        return 8;
      case WeaponType.energyTendril:
        return 50;
      case WeaponType.harmonicPulse:
        return 35;
      case WeaponType.phaseBeam:
        return 15;
      case WeaponType.novaLance:
        return 12;
      case WeaponType.autoLaser:
        return 55;
      case WeaponType.railAccelerator:
        return 25;
      case WeaponType.scavengedParticle:
        return 30;
      case WeaponType.torpedoPod:
        return 10;
    }
  }

  int get cost {
    switch (this) {
      case WeaponType.plasmaLance:
        return 20000;
      case WeaponType.shredderCannon:
        return 45000;
      case WeaponType.swarmMissile:
        return 75000;
      case WeaponType.ruptureTorpedo:
        return 60000;
      case WeaponType.energyTendril:
        return 15000;
      case WeaponType.harmonicPulse:
        return 35000;
      case WeaponType.phaseBeam:
        return 65000;
      case WeaponType.novaLance:
        return 80000;
      case WeaponType.autoLaser:
        return 10000;
      case WeaponType.railAccelerator:
        return 30000;
      case WeaponType.scavengedParticle:
        return 25000;
      case WeaponType.torpedoPod:
        return 50000;
    }
  }

  int get classTier {
    switch (this) {
      case WeaponType.plasmaLance:
      case WeaponType.energyTendril:
      case WeaponType.autoLaser:
        return 1;
      case WeaponType.shredderCannon:
      case WeaponType.harmonicPulse:
      case WeaponType.railAccelerator:
        return 2;
      case WeaponType.swarmMissile:
      case WeaponType.ruptureTorpedo:
      case WeaponType.phaseBeam:
      case WeaponType.novaLance:
      case WeaponType.scavengedParticle:
      case WeaponType.torpedoPod:
        return 3;
    }
  }

  String get rangeType {
    switch (this) {
      case WeaponType.plasmaLance:
      case WeaponType.energyTendril:
      case WeaponType.autoLaser:
        return 'forward';
      case WeaponType.shredderCannon:
      case WeaponType.harmonicPulse:
      case WeaponType.railAccelerator:
        return 'forward';
      case WeaponType.swarmMissile:
      case WeaponType.phaseBeam:
        return 'arc';
      case WeaponType.ruptureTorpedo:
      case WeaponType.novaLance:
      case WeaponType.scavengedParticle:
      case WeaponType.torpedoPod:
        return 'long';
    }
  }

  int damageAtLevel(int level) => damage * level;
  int fireRateAtLevel(int level) => fireRate * level;
}

// ── HULL STATS ────────────────────────────────────────

extension HullStats on HullType {
  int get baseHullBonus {
    switch (this) {
      case HullType.chitinPlating:
        return 10;
      case HullType.obsidianForge:
        return 25;
      case HullType.slabBulkhead:
        return 40;
      case HullType.rendArmor:
        return 30;
      case HullType.bioCrystalline:
        return 5;
      case HullType.auroraWeave:
        return 15;
      case HullType.nebulaMembrane:
        return 20;
      case HullType.starlightShell:
        return 25;
      case HullType.patchworkComposite:
        return 8;
      case HullType.reinforcedBulk:
        return 20;
      case HullType.modularSectional:
        return 30;
      case HullType.scavengedPlate:
        return 15;
    }
  }

  int get defenseRating {
    switch (this) {
      case HullType.chitinPlating:
        return 3;
      case HullType.obsidianForge:
        return 5;
      case HullType.slabBulkhead:
        return 7;
      case HullType.rendArmor:
        return 6;
      case HullType.bioCrystalline:
        return 2;
      case HullType.auroraWeave:
        return 4;
      case HullType.nebulaMembrane:
        return 5;
      case HullType.starlightShell:
        return 6;
      case HullType.patchworkComposite:
        return 2;
      case HullType.reinforcedBulk:
        return 5;
      case HullType.modularSectional:
        return 6;
      case HullType.scavengedPlate:
        return 3;
    }
  }

  int hullBonusAtLevel(int level) => baseHullBonus * level;
  int defenseAtLevel(int level) => defenseRating * level;
}

// ── SHIELD STATS ──────────────────────────────────────

extension ShieldStats on ShieldType {
  int get baseShieldBonus {
    switch (this) {
      case ShieldType.kineticBarrier:
        return 10;
      case ShieldType.plasmaForge:
        return 20;
      case ShieldType.warlordWard:
        return 30;
      case ShieldType.hegemonyShell:
        return 35;
      case ShieldType.harmonicField:
        return 8;
      case ShieldType.phaseWeave:
        return 18;
      case ShieldType.auroraVeil:
        return 25;
      case ShieldType.symbioticWard:
        return 30;
      case ShieldType.merchantBuckler:
        return 6;
      case ShieldType.smugglingJammer:
        return 12;
      case ShieldType.convoyBarrier:
        return 20;
      case ShieldType.salvageMatrix:
        return 15;
    }
  }

  int get regenRate {
    switch (this) {
      case ShieldType.kineticBarrier:
        return 3;
      case ShieldType.plasmaForge:
        return 5;
      case ShieldType.warlordWard:
        return 4;
      case ShieldType.hegemonyShell:
        return 6;
      case ShieldType.harmonicField:
        return 5;
      case ShieldType.phaseWeave:
        return 7;
      case ShieldType.auroraVeil:
        return 6;
      case ShieldType.symbioticWard:
        return 8;
      case ShieldType.merchantBuckler:
        return 2;
      case ShieldType.smugglingJammer:
        return 4;
      case ShieldType.convoyBarrier:
        return 5;
      case ShieldType.salvageMatrix:
        return 3;
    }
  }

  int shieldBonusAtLevel(int level) => baseShieldBonus * level;
  int regenAtLevel(int level) => regenRate * level;
}

// ── ENGINE STATS ──────────────────────────────────────

extension EngineStats on EngineType {
  int get speedBonus {
    switch (this) {
      case EngineType.volcanicThrust:
        return 5;
      case EngineType.warforgeDrive:
        return 8;
      case EngineType.rendPulse:
        return 10;
      case EngineType.bioPlasmaSail:
        return 8;
      case EngineType.harmonicDrift:
        return 10;
      case EngineType.celestialFlow:
        return 12;
      case EngineType.juryRiggedFusion:
        return 6;
      case EngineType.salvagedImpulse:
        return 8;
      case EngineType.convoyOverdrive:
        return 10;
    }
  }

  int get warpCapacity {
    switch (this) {
      case EngineType.volcanicThrust:
        return 3;
      case EngineType.warforgeDrive:
        return 5;
      case EngineType.rendPulse:
        return 7;
      case EngineType.bioPlasmaSail:
        return 4;
      case EngineType.harmonicDrift:
        return 6;
      case EngineType.celestialFlow:
        return 8;
      case EngineType.juryRiggedFusion:
        return 3;
      case EngineType.salvagedImpulse:
        return 5;
      case EngineType.convoyOverdrive:
        return 6;
    }
  }

  int get efficiency {
    switch (this) {
      case EngineType.volcanicThrust:
        return 4;
      case EngineType.warforgeDrive:
        return 3;
      case EngineType.rendPulse:
        return 2;
      case EngineType.bioPlasmaSail:
        return 7;
      case EngineType.harmonicDrift:
        return 8;
      case EngineType.celestialFlow:
        return 9;
      case EngineType.juryRiggedFusion:
        return 5;
      case EngineType.salvagedImpulse:
        return 4;
      case EngineType.convoyOverdrive:
        return 6;
    }
  }

  int speedAtLevel(int level) => speedBonus * level;
  int warpAtLevel(int level) => warpCapacity * level;
  int efficiencyAtLevel(int level) => efficiency * level;
}

// ── HELPER: Validate faction equipment compatibility ──

bool isFactionEquipmentCompatible(Enum equipment, FactionClass faction) {
  FactionClass? equipFaction;
  if (equipment is HullType) equipFaction = equipment.getFaction();
  if (equipment is ShieldType) equipFaction = equipment.getFaction();
  if (equipment is EngineType) equipFaction = equipment.getFaction();
  if (equipment is WeaponType) equipFaction = equipment.getFaction();
  return equipFaction == faction;
}
