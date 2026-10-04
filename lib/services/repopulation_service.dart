import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

/// Homeworld repopulation (C4, first slice).
///
/// Pirate predation with no respawns empties the galaxy permanently — a
/// live 20-minute session wiped Duran/Vinari to zero and traders to one
/// ship. Each tick, factions below their floor receive at most one
/// replacement, spawned at their homeworld sector (random sector fallback
/// when the homeworld is unknown). Small floors + one-per-tick keep this
/// recovery, not a flood.
class RepopulationService {
  RepopulationService._();

  /// Minimum living ships per faction before replacements spawn.
  static const Map<FactionClass, int> floors = {
    FactionClass.trader: 3,
    FactionClass.duran: 3,
    FactionClass.vinari: 3,
    FactionClass.pirate: 2,
  };

  /// Steady-state production ceilings per faction (C4a). Floors recover,
  /// production sustains — at or above the cap the yards stand down.
  /// Pirates build at their outposts (C3) under a leaner cap.
  static const Map<FactionClass, int> productionCaps = {
    FactionClass.trader: 8,
    FactionClass.duran: 8,
    FactionClass.vinari: 8,
    FactionClass.pirate: 4,
  };

  /// Chance a yard rollout is a living legend (C4c).
  static const double heroChance = 0.05;

  /// Minted bounty on a legend's head (C4c): the Guild pays for stories.
  /// Follows the Federation auto-post precedent — no bankroll debited.
  static const int heroBounty = 15000;

  static final math.Random _rng = math.Random();

  /// Counts living NPCs per faction.
  static Map<FactionClass, int> livingCounts(List<NpcShip> npcs) {
    final counts = <FactionClass, int>{
      for (final f in FactionClass.values) f: 0
    };
    for (final n in npcs) {
      if (!n.isDestroyed) counts[n.faction] = (counts[n.faction] ?? 0) + 1;
    }
    return counts;
  }

  /// Homeworld sector per faction, if one exists in [sectors] AND remains
  /// under friendly control. A captured homeworld (owner is another
  /// faction) spawns nothing — losing control means losing regeneration,
  /// and recapture restores it. Unowned homeworlds still spawn (frontier).
  /// Destroyed homeworlds (planet-killer path, C4b) never count.
  /// Primaries win over backups (C4b): a live primary idles its backup;
  /// the backup takes over only while the primary is captured, destroyed,
  /// or missing.
  static Map<FactionClass, int> homeworldSectors(List<Sector> sectors) {
    bool usable(Planet? planet, {required bool backup}) {
      return planet != null &&
          planet.isHomeworld &&
          planet.isBackupHomeworld == backup &&
          !planet.isDestroyed &&
          planet.homeworldOf != null &&
          (planet.owner == null || planet.owner == planet.homeworldOf);
    }

    final homeworlds = <FactionClass, int>{};
    for (final backup in [false, true]) {
      for (final s in sectors) {
        if (homeworlds.length >= FactionClass.values.length) break;
        // Every world, not slot 0. A capital sitting in slot 2 of a three-world
        // sector is still the capital, and reading slot 0 would let a random
        // frontier world stand in for it.
        for (final planet in s.planets) {
          if (usable(planet, backup: backup)) {
            homeworlds.putIfAbsent(planet.homeworldOf!, () => s.id);
            break;
          }
        }
      }
    }
    return homeworlds;
  }

  /// Spawns at most one replacement per under-floor faction. Returns the
  /// newcomers (caller appends them to the NPC list and saves).
  static List<NpcShip> repopulate(
    List<Sector> sectors,
    List<NpcShip> npcs, {
    int startingCredits = 10000,
    math.Random? rng,
  }) {
    final random = rng ?? _rng;
    if (sectors.isEmpty) return const [];
    final counts = livingCounts(npcs);
    final homeworlds = homeworldSectors(sectors);
    final spawned = <NpcShip>[];

    for (final entry in floors.entries) {
      if ((counts[entry.key] ?? 0) >= entry.value) continue;
      final homeId = homeworlds[entry.key];
      if (homeId == null && entry.key != FactionClass.pirate) {
        // No controlled homeworld (captured or destroyed): the faction
        // cannot regenerate. Loud in the log — this is an extinction
        // event in progress, reversible only by recapture.
        GameEventLog.global.system(
          '[Repopulation] ${entry.key.name} has no controlled homeworld '
          '— no spawn (recapture to restore)',
        );
        continue;
      }
      // Pirates hold no homeworlds, only outposts (C3): random-sector
      // fallback when every outpost is captured or destroyed.
      final sectorId = homeId ?? sectors[random.nextInt(sectors.length)].id;
      final ship = NpcShip.create(
        faction: entry.key,
        shipDef: ShipDefinition
            .allShips[random.nextInt(ShipDefinition.allShips.length)],
        currentSectorId: sectorId,
        startingCredits: startingCredits,
        seed: random.nextInt(1 << 30),
      );
      spawned.add(ship);
      // Backup-yard tag (soak instrumentation): which capital launched.
      var backupTag = '';
      for (final s in sectors) {
        if (s.id == sectorId &&
            s.planets.any((p) => p.isBackupHomeworld && !p.isDestroyed)) {
          backupTag = ' (backup yards)';
          break;
        }
      }
      GameEventLog.global.system(
        '[Repopulation] ${ship.pilotName} (${entry.key.name}) '
        'launched from sector #$sectorId$backupTag',
      );
    }
    return spawned;
  }

  /// Controlled-homeworld **colonist** infusion. See
  /// [Planet.colonistInfusionTicks] for why a capital makes its own colonists.
  ///
  /// The gating is deliberately identical to [produce]: same worlds, same
  /// captured-yard freeze, same live-primary-idles-backup rule. Two passes over
  /// the same list rather than one shared loop, because [produce] returns the
  /// ships it built and naming that method "produce" while it also grew
  /// populations would make the name lie — the same reason the ship and colonist
  /// timers are separate fields.
  ///
  /// The infusion is **capped at [Planet.colonistMax]**, and it is worth being
  /// precise about what that cap is for: **it is a guard rail, not a balance
  /// lever.** `colonistMaxByType` runs from 2,000,000 (Terran) to 100,000
  /// (Toxic), scaled up to 12x by Citadel level — so a capital would need on the
  /// order of 120,000 ticks to fill a level-1 Terran one. The clamp will not bind
  /// in normal play.
  ///
  /// It binds for one honest reason: to guarantee no state exists in which
  /// `population > colonistMax`, which the colony card would render as "400% of
  /// cap" and which nothing else in the model defends against. Reusing the
  /// existing derived cap is cheaper than inventing a second ceiling, and the
  /// alternative — letting a capital accumulate without bound — has no upside.
  ///
  /// Mutates [Planet.population] in place. The tick saves the universe, so both
  /// the countdown and the colonists it produced survive a restart.
  ///
  /// Returns the worlds that infused, for logging and for tests that need to
  /// know the pass did something.
  static List<Planet> produceColonists(List<Sector> sectors) {
    final infused = <Planet>[];
    if (sectors.isEmpty) return infused;

    bool livePrimary(FactionClass f) => sectors.any((s) => s.planets.any((p) =>
        p.isHomeworld &&
        !p.isBackupHomeworld &&
        !p.isDestroyed &&
        p.homeworldOf == f &&
        (p.owner == null || p.owner == f)));

    // Iterate worlds, not sectors, for the reason [produce] does: a sector can
    // hold a capital and a frontier world, or capitals for two factions.
    for (final s in sectors) {
      for (final planet in s.planets) {
        if (!planet.isHomeworld ||
            planet.isDestroyed ||
            planet.homeworldOf == null) {
          continue;
        }
        final faction = planet.homeworldOf!;
        // Captured yards run cold — same as ships.
        if (planet.owner != null && planet.owner != faction) continue;
        if (planet.isBackupHomeworld && livePrimary(faction)) continue;

        planet.colonistTimer--;
        if (planet.colonistTimer > 0) continue;
        planet.colonistTimer = planet.colonistInterval;

        final room = planet.colonistMax - planet.population;
        // Nothing to give, or a cadence that has nothing to do. Note the timer is
        // still reset: an infusion is a cadence, not a queue, exactly as the ship
        // yards behave when a faction is at its cap.
        if (room <= 0) continue;
        final added =
            planet.colonistInfusion < room ? planet.colonistInfusion : room;
        planet.population += added;
        infused.add(planet);
      }
    }
    return infused;
  }

  /// Ticks controlled-homeworld production (C4a): each friendly-controlled,
  /// intact homeworld counts down [Planet.productionTimer]; at zero it
  /// rolls out one ship of its faction and resets to [Planet.spawnInterval].
  /// Captured yards freeze (no countdown, no spawn); destroyed worlds are
  /// silent; populations at/above [productionCaps] stand the yards down
  /// (timer still resets — production is a cadence, not a queue).
  /// Planet timers mutate in place; the tick loop saves the universe, so
  /// the countdown persists across restarts. Returns the newcomers.
  static List<NpcShip> produce(
    List<Sector> sectors,
    List<NpcShip> npcs, {
    int startingCredits = 10000,
    math.Random? rng,
  }) {
    final random = rng ?? _rng;
    final spawned = <NpcShip>[];
    if (sectors.isEmpty) return spawned;
    final counts = livingCounts(npcs);

    int living(FactionClass f) =>
        (counts[f] ?? 0) + spawned.where((n) => n.faction == f).length;

    // Live primaries idle their backups (C4b): capitals move back, they
    // don't duplicate. A backup produces only while no controlled,
    // intact primary of the same faction exists.
    bool livePrimary(FactionClass f) => sectors.any((s) => s.planets.any((p) =>
        p.isHomeworld &&
        !p.isBackupHomeworld &&
        !p.isDestroyed &&
        p.homeworldOf == f &&
        (p.owner == null || p.owner == f)));

    // Iterate worlds, not sectors. A sector can hold two capitals for two
    // factions, or a capital and a frontier world, and both need to be visited.
    for (final s in sectors) {
      for (final planet in s.planets) {
        if (!planet.isHomeworld ||
            planet.isDestroyed ||
            planet.homeworldOf == null) {
          continue;
        }
        final faction = planet.homeworldOf!;
        final cap = productionCaps[faction];
        if (cap == null) continue;
        // Captured yards run cold.
        if (planet.owner != null && planet.owner != faction) continue;
        if (planet.isBackupHomeworld && livePrimary(faction)) continue;
        planet.productionTimer--;
        if (planet.productionTimer > 0) continue;
        planet.productionTimer = planet.spawnInterval;
        if (living(faction) >= cap) continue;
        var ship = NpcShip.create(
          faction: faction,
          shipDef: ShipDefinition
              .allShips[random.nextInt(ShipDefinition.allShips.length)],
          currentSectorId: s.id,
          startingCredits: startingCredits,
          seed: random.nextInt(1 << 30),
        );
        ship = _maybeHero(ship, npcs, spawned, random);
        spawned.add(ship);
        GameEventLog.global.system(
          '[Production] ${planet.name} rolled out ${ship.pilotName} '
          '(${faction.name}) in sector #${s.id}'
          '${planet.isBackupHomeworld ? ' (backup yards)' : ''}',
        );
      }
    }
    return spawned;
  }

  /// Living legends (C4c, revised review batch 1): rarely a yard rollout
  /// is a lore hero from [Faction.notableHeroes] — buffed hull/shields/
  /// guns, marked notorious, roster-unique by hero name. The Guild bounty
  /// is EARNED, not minted: a legend's first kill posts it (see the kill
  /// path), so newborn heroes aren't beelined by every greedy hull in
  /// range before they've done anything legendary. Factions without a
  /// lore table sail no legends.
  static NpcShip _maybeHero(
    NpcShip ship,
    List<NpcShip> npcs,
    List<NpcShip> spawned,
    math.Random random,
  ) {
    if (random.nextDouble() >= heroChance) return ship;
    List<Hero> heroes;
    try {
      heroes = Faction.forClass(ship.faction).notableHeroes;
    } on StateError {
      return ship;
    }
    final candidates = heroes
        .where((h) =>
            !npcs.any((n) => n.heroName == h.name) &&
            !spawned.any((n) => n.heroName == h.name))
        .toList();
    if (candidates.isEmpty) return ship;
    final hero = candidates[random.nextInt(candidates.length)];
    GameEventLog.global.system(
      '[Production] Living legend ${hero.name} (${hero.title}) takes '
      'the helm in sector #${ship.currentSectorId}',
    );
    return ship.copyWith(
      pilotName: hero.name,
      heroName: hero.name,
      heroTitle: hero.title,
      hull: (ship.hull * 1.5).round(),
      maxHull: (ship.maxHull * 1.5).round(),
      shields: (ship.shields * 1.5).round(),
      maxShields: (ship.maxShields * 1.5).round(),
      weaponSlots: {
        for (final e in ship.weaponSlots.entries) e.key: e.value + 1,
      },
      notoriety: 15.0,
    );
  }
}
