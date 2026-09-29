import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

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
  static PlanetProductionSummary process(List<Sector> sectors) {
    var colonies = 0;
    var minerals = 0;
    var organics = 0;
    var industrial = 0;
    var drones = 0;
    var starving = 0;
    var lost = 0;
    final overflow = <String>[];

    var completed = 0;
    final finished = <String>[];

    for (final sector in sectors) {
      final planet = sector.planet;
      if (planet == null || planet.isDestroyed) continue;

      // Construction advances **before** the population check, and deliberately
      // so: a build already paid for should not stall because the colony is
      // starving. Halting a Citadel halfway is the only way a starvation event
      // could feel like a punishment, and it would be the wrong one — the
      // resources are spent either way.
      if (planet.isUnderConstruction) {
        final before = planet.level;
        planet.advanceConstruction();
        if (planet.level != before) {
          completed++;
          finished.add('${planet.name} -> ${planet.level}');
        }
      }

      if (planet.population <= 0) continue;
      colonies++;
      final report = planet.produce();
      minerals += report.mineralsGained;
      organics += report.organicsGained;
      industrial += report.industrialGained;
      drones += report.dronesGained;
      lost += report.colonistsLost;

      if (report.isStarving) {
        starving++;
        GameEventLog.global.system(
          '[Colony] ${planet.name} (sector #${sector.id}) cannot feed itself: '
          '${report.organicsShortfall} organics short, '
          '${report.colonistsLost} colonist(s) lost',
        );
      }
      if (report.storageOverflowed) {
        overflow.add(planet.name);
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

    return PlanetProductionSummary(
      colonies: colonies,
      minerals: minerals,
      organics: organics,
      industrial: industrial,
      drones: drones,
      starving: starving,
      colonistsLost: lost,
      overflowed: overflow.length,
      constructionsCompleted: completed,
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
  final int starving;
  final int colonistsLost;
  final int overflowed;

  const PlanetProductionSummary({
    this.colonies = 0,
    this.minerals = 0,
    this.organics = 0,
    this.industrial = 0,
    this.drones = 0,
    this.starving = 0,
    this.colonistsLost = 0,
    this.overflowed = 0,
    this.constructionsCompleted = 0,
  });

  /// Citadel tiers finished during this pass.
  final int constructionsCompleted;

  /// Nothing to say. A galaxy with no colonies is normal, not worth a log line.
  ///
  /// A completed build counts as worth saying even where no colony exists at all,
  /// so `constructionsCompleted` is checked explicitly rather than riding on
  /// `colonies > 0`.
  bool get isQuiet =>
      colonies == 0 &&
      colonistsLost == 0 &&
      starving == 0 &&
      overflowed == 0 &&
      constructionsCompleted == 0;
}
