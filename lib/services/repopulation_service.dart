import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
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
  static Map<FactionClass, int> homeworldSectors(List<Sector> sectors) {
    final homeworlds = <FactionClass, int>{};
    for (final s in sectors) {
      final planet = s.planet;
      if (planet != null &&
          planet.isHomeworld &&
          planet.homeworldOf != null &&
          (planet.owner == null || planet.owner == planet.homeworldOf)) {
        homeworlds.putIfAbsent(planet.homeworldOf!, () => s.id);
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
      // Pirates hold no homeworlds: random-sector fallback (outposts later).
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
      GameEventLog.global.system(
        '[Repopulation] ${ship.pilotName} (${entry.key.name}) '
        'launched from sector #$sectorId',
      );
    }
    return spawned;
  }
}
