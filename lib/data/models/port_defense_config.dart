/// Port defense configuration.
/// Single source of truth for balancing port combat stats.
class PortDefenseStats {
  final int shieldCapacity;
  final int firepower;
  final PortSpecialAbility specialAbility;
  final double shieldRegenPct;
  final double empDrainPct;

  const PortDefenseStats({
    required this.shieldCapacity,
    required this.firepower,
    required this.specialAbility,
    this.shieldRegenPct = 0.0,
    this.empDrainPct = 0.0,
  });
}

enum PortSpecialAbility {
  none,
  counterAttack,
  shieldRegen,
  empBurst,
  allAbilities,
}

/// Static configuration for port defense stats per level.
class PortDefenseConfig {
  static const Map<int, PortDefenseStats> _defaults = {
    0: PortDefenseStats(
      shieldCapacity: 500,
      firepower: 30,
      specialAbility: PortSpecialAbility.none,
    ),
    1: PortDefenseStats(
      shieldCapacity: 1000,
      firepower: 60,
      specialAbility: PortSpecialAbility.none,
    ),
    2: PortDefenseStats(
      shieldCapacity: 2000,
      firepower: 120,
      specialAbility: PortSpecialAbility.counterAttack,
    ),
    3: PortDefenseStats(
      shieldCapacity: 3500,
      firepower: 200,
      specialAbility: PortSpecialAbility.shieldRegen,
      shieldRegenPct: 0.05,
    ),
    4: PortDefenseStats(
      shieldCapacity: 6000,
      firepower: 300,
      specialAbility: PortSpecialAbility.allAbilities,
      shieldRegenPct: 0.05,
      empDrainPct: 0.15,
    ),
  };

  static PortDefenseStats defenseStats(int level) =>
      _defaults[level] ?? _defaults[0]!;
}

/// Extension helpers for [PortSpecialAbility].
extension PortSpecialAbilityX on PortSpecialAbility {
  bool get hasCounterAttack =>
      this == PortSpecialAbility.counterAttack ||
      this == PortSpecialAbility.allAbilities;

  bool get hasShieldRegen =>
      this == PortSpecialAbility.shieldRegen ||
      this == PortSpecialAbility.allAbilities;

  bool get hasEmpBurst => this == PortSpecialAbility.empBurst;
}

/// Extension helpers for [PortDefenseStats].
extension PortDefenseStatsX on PortDefenseStats {
  bool get hasCounterAttack => specialAbility.hasCounterAttack;
  bool get hasShieldRegen => specialAbility.hasShieldRegen;
  bool get hasEmpBurst => specialAbility.hasEmpBurst;
}
