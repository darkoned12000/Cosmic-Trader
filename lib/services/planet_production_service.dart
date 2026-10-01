import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/core/number_format.dart';

/// Colony production, once per game tick.
///
/// Until this existed the planet screen displayed a per-tick production rate
/// for every track and that number could never change: the only code in `lib/`
/// that wrote a planet's stores was the credits-based transfer in
/// `PlanetScreen`. A displayed feature that silently does nothing is worse than
/// an absent one, so this is the minimum needed to make the screen honest.
///
/// The arithmetic lives on [Planet.produce] rather than here, so the tick and
/// the screen cannot disagree about what a colony produced. This service is
/// only the iteration, the bookkeeping, and the reporting.
///
/// Mutates planets in place; the tick saves the universe afterwards, so
/// production persists across restarts the same way homeworld spawn timers do.
class PlanetProductionService {
  PlanetProductionService._();

  /// Advances every populated colony by one tick.
  ///
  /// Skips destroyed worlds and empty colonies — there is nothing to produce
  /// and a corpse must never look busy in the log. Returns what happened so
  /// the tick can summarise it without re-walking every sector.
  /// [creditFaction] scopes [PlanetProductionSummary.constructionsCompleted] to
  /// worlds that faction owns, because the caller pays reputation for the count
  /// and the galaxy holds worlds the player never paid to build. Null counts
  /// every completion, which is what the headless callers and most tests want.
  static PlanetProductionSummary process(
    List<Sector> sectors, {
    FactionClass? creditFaction,
  }) {
    var colonies = 0;
    var minerals = 0;
    var organics = 0;
    var industrial = 0;
    var drones = 0;
    var supplyPaid = 0;
    var unsupplied = 0;
    final overflow = <String>[];

    var completed = 0;
    final finished = <String>[];

    // Colonists that reached their world this pass, and where they landed. The
    // colony card already shows a live "in transit" row, so this is the arrival
    // notice for a shipment the player ordered while looking at something else.
    var arrivedColonists = 0;
    final settled = <String>[];

    for (final sector in sectors) {
      // Every world in the sector, not just the first. A three-world sector is
      // three colonies earning, and the whole design is that they complement
      // each other — ticking only slot 0 would run the complementarity loop at a
      // third of its value and hide the rest entirely.
      for (final planet in sector.planets) {
        if (planet.isDestroyed) continue;

        // Construction advances **before** the population check, and deliberately
        // so: a build already paid for should not stall because the colony is
        // unfed. Halting a Citadel halfway is the only way an unpaid supply
        // bill could feel like a punishment, and it would be the wrong one —
        // the resources are spent either way.
        if (planet.isUnderConstruction) {
          final before = planet.level;
          planet.advanceConstruction();
          if (planet.level != before) {
            // Counted only when the caller is paying for it. A Citadel the
            // player did not commission must not put reputation in their
            // pocket, and `creditFaction` is how the tick says who they are.
            if (creditFaction == null || planet.owner == creditFaction) {
              completed++;
            }
            finished.add('${planet.name} -> ${planet.level}');
          }
        }

        // Colonist arrivals advance here for the same reason construction does,
        // and the same trap: **a world with no colonists yet is exactly the world
        // a first shipment is going to.** Behind the `population <= 0` skip below,
        // the one world guaranteed to be buying its first colonists would be the
        // one world whose shipment never lands.
        final arrived = planet.advanceColonistTransit();
        if (arrived > 0) {
          arrivedColonists += arrived;
          settled.add('${planet.name} +${compact(arrived)}');
        }

        if (planet.population <= 0) continue;
        colonies++;
        final report = planet.produce();
        minerals += report.mineralsGained;
        organics += report.organicsGained;
        industrial += report.industrialGained;
        drones += report.dronesGained;
        supplyPaid += report.supplyPaid;

        if (report.isUnsupplied) {
          unsupplied++;
          GameEventLog.global.system(
            '[Colony] ${planet.name} (sector #${sector.id}) cannot cover its '
            'supply: ${report.supplyShortfall} units short of a '
            '${compact(planet.supplyDraw)} unit draw. Haul goods in, or '
            'plant a world beside it that makes what it cannot.',
          );
        }
        if (report.storageOverflowed) {
          overflow.add(planet.name);
        }
      }
    }

    if (overflow.isNotEmpty) {
      GameEventLog.global.system(
        '[Colony] ${overflow.length} colony/capies at storage capacity — '
        'output was discarded: ${overflow.take(5).join(', ')}'
        '${overflow.length > 5 ? ', ...' : ''}',
      );
    }

    if (finished.isNotEmpty) {
      GameEventLog.global.system(
        '[Colony] ${finished.length} citadel upgrade(s) completed: '
        '${finished.take(5).join(', ')}${finished.length > 5 ? ', ...' : ''}',
      );
    }

    if (settled.isNotEmpty) {
      GameEventLog.global.system(
        '[Colony] ${settled.length} colonist shipment(s) arrived: '
        '${settled.take(5).join(', ')}${settled.length > 5 ? ', ...' : ''}',
      );
    }

    return PlanetProductionSummary(
      colonies: colonies,
      minerals: minerals,
      organics: organics,
      industrial: industrial,
      drones: drones,
      supplyPaid: supplyPaid,
      unsupplied: unsupplied,
      overflowed: overflow.length,
      constructionsCompleted: completed,
      colonistsArrived: arrivedColonists,
    );
  }
}

/// Aggregate result of one production pass, for the tick's own log line.
class PlanetProductionSummary {
  final int colonies;
  final int minerals;
  final int organics;
  final int industrial;
  final int drones;

  /// Total units taken across every colony supply draw this tick.
  final int supplyPaid;

  /// Colonies that could not cover a supply draw.
  final int unsupplied;
  final int overflowed;

  /// Citadel tiers finished during this pass.
  final int constructionsCompleted;

  /// Purchased colonists that reached their world this pass.
  ///
  /// Its own field rather than a fold-in: an arrival is the one colony event a
  /// player spent money to cause, and it can happen on a world with no colony
  /// yet — which is exactly the case [isQuiet] would otherwise swallow, since
  /// `colonies` counts only worlds that pass the population check.
  final int colonistsArrived;

  const PlanetProductionSummary({
    this.colonies = 0,
    this.minerals = 0,
    this.organics = 0,
    this.industrial = 0,
    this.drones = 0,
    this.supplyPaid = 0,
    this.unsupplied = 0,
    this.overflowed = 0,
    this.constructionsCompleted = 0,
    this.colonistsArrived = 0,
  });

  /// Nothing to say. A galaxy with no colonies is normal, not worth a log line.
  ///
  /// A completed build counts as worth saying even where no colony exists at all,
  /// so `constructionsCompleted` is checked explicitly rather than riding on
  /// `colonies > 0`.
  bool get isQuiet =>
      colonies == 0 &&
      unsupplied == 0 &&
      overflowed == 0 &&
      constructionsCompleted == 0 &&
      colonistsArrived == 0;
}
