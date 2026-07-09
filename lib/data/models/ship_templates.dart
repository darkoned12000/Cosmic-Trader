// ship_templates.dart

import './faction.dart';
import './ship_equipment_types.dart';

enum ShipClassType { interceptor, battleship, freighter, capitalShip }

extension ShipClassWeaponTier on ShipClassType {
  int get maxWeaponTier {
    switch (this) {
      case ShipClassType.interceptor:
        return 1;
      case ShipClassType.battleship:
      case ShipClassType.freighter:
        return 2;
      case ShipClassType.capitalShip:
        return 3;
    }
  }
}

class ShipDefinition {
  final String name;
  final ShipClassType shipClass;
  final FactionClass faction;
  final int maxHullCapacity;
  final int shields;
  final int maxShields;
  final int maxCargo;
  final int speed;
  final int shipCost;
  final List<String> weaponSlots;
  final List<WeaponType> preferredWeapons;
  final HullType hullType;
  final ShieldType shieldType;
  final EngineType engineType;

  const ShipDefinition({
    required this.name,
    required this.shipClass,
    required this.faction,
    required this.maxHullCapacity,
    required this.shields,
    required this.maxShields,
    required this.maxCargo,
    required this.speed,
    required this.shipCost,
    required this.weaponSlots,
    required this.preferredWeapons,
    required this.hullType,
    required this.shieldType,
    required this.engineType,
  });

  static const allShips = [
    // ── DURAN ──────────────────────────────────────────
    ShipDefinition(
      name: 'Skarva Fang',
      shipClass: ShipClassType.interceptor,
      faction: FactionClass.duran,
      maxHullCapacity: 120,
      shields: 80,
      maxShields: 80,
      maxCargo: 20,
      speed: 7,
      shipCost: 0,
      weaponSlots: ['main_forward'],
      preferredWeapons: [WeaponType.plasmaLance],
      hullType: HullType.chitinPlating,
      shieldType: ShieldType.kineticBarrier,
      engineType: EngineType.volcanicThrust,
    ),
    ShipDefinition(
      name: 'Rendmaw Destroyer',
      shipClass: ShipClassType.battleship,
      faction: FactionClass.duran,
      maxHullCapacity: 250,
      shields: 150,
      maxShields: 150,
      maxCargo: 40,
      speed: 5,
      shipCost: 750000,
      weaponSlots: ['main_forward', 'starboard', 'port'],
      preferredWeapons: [
        WeaponType.shredderCannon,
        WeaponType.plasmaLance,
        WeaponType.plasmaLance,
      ],
      hullType: HullType.obsidianForge,
      shieldType: ShieldType.plasmaForge,
      engineType: EngineType.warforgeDrive,
    ),
    ShipDefinition(
      name: 'Obsidian Hauler',
      shipClass: ShipClassType.freighter,
      faction: FactionClass.duran,
      maxHullCapacity: 200,
      shields: 100,
      maxShields: 100,
      maxCargo: 100,
      speed: 4,
      shipCost: 500000,
      weaponSlots: ['main_forward', 'aft'],
      preferredWeapons: [WeaponType.plasmaLance, WeaponType.plasmaLance],
      hullType: HullType.slabBulkhead,
      shieldType: ShieldType.warlordWard,
      engineType: EngineType.volcanicThrust,
    ),
    ShipDefinition(
      name: 'Hegemony Dreadnought',
      shipClass: ShipClassType.capitalShip,
      faction: FactionClass.duran,
      maxHullCapacity: 500,
      shields: 300,
      maxShields: 300,
      maxCargo: 60,
      speed: 3,
      shipCost: 2500000,
      weaponSlots: [
        'main_forward',
        'starboard',
        'port',
        'aft',
        'dorsal',
      ],
      preferredWeapons: [
        WeaponType.ruptureTorpedo,
        WeaponType.shredderCannon,
        WeaponType.shredderCannon,
        WeaponType.plasmaLance,
        WeaponType.plasmaLance,
      ],
      hullType: HullType.rendArmor,
      shieldType: ShieldType.hegemonyShell,
      engineType: EngineType.rendPulse,
    ),

    // ── VINARI ─────────────────────────────────────────
    ShipDefinition(
      name: 'Sylvara Wisp',
      shipClass: ShipClassType.interceptor,
      faction: FactionClass.vinari,
      maxHullCapacity: 100,
      shields: 100,
      maxShields: 100,
      maxCargo: 25,
      speed: 8,
      shipCost: 0,
      weaponSlots: ['main_forward'],
      preferredWeapons: [WeaponType.energyTendril],
      hullType: HullType.bioCrystalline,
      shieldType: ShieldType.harmonicField,
      engineType: EngineType.bioPlasmaSail,
    ),
    ShipDefinition(
      name: 'Aurora Runner',
      shipClass: ShipClassType.battleship,
      faction: FactionClass.vinari,
      maxHullCapacity: 180,
      shields: 200,
      maxShields: 200,
      maxCargo: 35,
      speed: 7,
      shipCost: 600000,
      weaponSlots: ['main_forward', 'starboard', 'port'],
      preferredWeapons: [
        WeaponType.harmonicPulse,
        WeaponType.energyTendril,
        WeaponType.energyTendril,
      ],
      hullType: HullType.auroraWeave,
      shieldType: ShieldType.phaseWeave,
      engineType: EngineType.harmonicDrift,
    ),
    ShipDefinition(
      name: 'Symbiosis Freighter',
      shipClass: ShipClassType.freighter,
      faction: FactionClass.vinari,
      maxHullCapacity: 160,
      shields: 150,
      maxShields: 150,
      maxCargo: 90,
      speed: 5,
      shipCost: 450000,
      weaponSlots: ['main_forward', 'aft'],
      preferredWeapons: [WeaponType.energyTendril, WeaponType.energyTendril],
      hullType: HullType.nebulaMembrane,
      shieldType: ShieldType.auroraVeil,
      engineType: EngineType.bioPlasmaSail,
    ),
    ShipDefinition(
      name: 'Celestial Arbiter',
      shipClass: ShipClassType.capitalShip,
      faction: FactionClass.vinari,
      maxHullCapacity: 350,
      shields: 400,
      maxShields: 400,
      maxCargo: 50,
      speed: 4,
      shipCost: 2000000,
      weaponSlots: [
        'main_forward',
        'starboard',
        'port',
        'aft',
        'dorsal',
      ],
      preferredWeapons: [
        WeaponType.novaLance,
        WeaponType.phaseBeam,
        WeaponType.phaseBeam,
        WeaponType.harmonicPulse,
        WeaponType.energyTendril,
      ],
      hullType: HullType.starlightShell,
      shieldType: ShieldType.symbioticWard,
      engineType: EngineType.celestialFlow,
    ),

    // ── TRADERS ────────────────────────────────────────
    ShipDefinition(
      name: 'Starhawk Skiff',
      shipClass: ShipClassType.interceptor,
      faction: FactionClass.trader,
      maxHullCapacity: 110,
      shields: 70,
      maxShields: 70,
      maxCargo: 30,
      speed: 6,
      shipCost: 0,
      weaponSlots: ['main_forward'],
      preferredWeapons: [WeaponType.autoLaser],
      hullType: HullType.patchworkComposite,
      shieldType: ShieldType.merchantBuckler,
      engineType: EngineType.juryRiggedFusion,
    ),
    ShipDefinition(
      name: 'Ironmaw Raider',
      shipClass: ShipClassType.battleship,
      faction: FactionClass.trader,
      maxHullCapacity: 200,
      shields: 120,
      maxShields: 120,
      maxCargo: 45,
      speed: 5,
      shipCost: 650000,
      weaponSlots: ['main_forward', 'starboard', 'port'],
      preferredWeapons: [
        WeaponType.railAccelerator,
        WeaponType.autoLaser,
        WeaponType.autoLaser,
      ],
      hullType: HullType.reinforcedBulk,
      shieldType: ShieldType.convoyBarrier,
      engineType: EngineType.salvagedImpulse,
    ),
    ShipDefinition(
      name: 'Scavenger Hauler',
      shipClass: ShipClassType.freighter,
      faction: FactionClass.trader,
      maxHullCapacity: 180,
      shields: 80,
      maxShields: 80,
      maxCargo: 120,
      speed: 4,
      shipCost: 550000,
      weaponSlots: ['main_forward', 'aft'],
      preferredWeapons: [WeaponType.autoLaser, WeaponType.autoLaser],
      hullType: HullType.modularSectional,
      shieldType: ShieldType.salvageMatrix,
      engineType: EngineType.juryRiggedFusion,
    ),
    ShipDefinition(
      name: 'Void Baron Galleon',
      shipClass: ShipClassType.capitalShip,
      faction: FactionClass.trader,
      maxHullCapacity: 400,
      shields: 200,
      maxShields: 200,
      maxCargo: 80,
      speed: 3,
      shipCost: 1800000,
      weaponSlots: [
        'main_forward',
        'starboard',
        'port',
        'aft',
        'dorsal',
      ],
      preferredWeapons: [
        WeaponType.torpedoPod,
        WeaponType.railAccelerator,
        WeaponType.railAccelerator,
        WeaponType.scavengedParticle,
        WeaponType.autoLaser,
      ],
      hullType: HullType.scavengedPlate,
      shieldType: ShieldType.smugglingJammer,
      engineType: EngineType.convoyOverdrive,
    ),
  ];

  static ShipDefinition? getShipByName(String name) {
    try {
      return allShips.firstWhere((s) => s.name == name);
    } catch (_) {
      return null;
    }
  }

  static List<ShipDefinition> getShipsForFaction(FactionClass faction) {
    return allShips.where((s) => s.faction == faction).toList();
  }

  static ShipDefinition? getShipByFactionAndClass(
    FactionClass faction,
    ShipClassType shipClass,
  ) {
    try {
      return allShips.firstWhere(
        (s) => s.faction == faction && s.shipClass == shipClass,
      );
    } catch (_) {
      return null;
    }
  }

  static ShipDefinition getDefaultInterceptor(FactionClass faction) {
    return getShipByFactionAndClass(faction, ShipClassType.interceptor) ??
        allShips.first;
  }
}
