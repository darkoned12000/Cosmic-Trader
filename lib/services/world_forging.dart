import 'dart:math' as math;

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

/// Why a launch ended the way it did.
///
/// A sealed enum rather than a string, so the UI has to handle every case rather
/// than falling through on one it has not heard of.
enum LaunchResult {
  /// Fired. The sector may now be over-stacked.
  launched,

  /// The player has no torpedoes.
  noTorpedoes,

  /// The hold is full, so there is nowhere to put one.
  holdFull,

  /// Already at the cap. **This is not a refusal** — see
  /// [Sector.launchWorld], which allows over-stacking deliberately. The result
  /// exists so the screen can show the gravity warning after the fact.
  wouldOverstack,
}

/// Outcome of a detonation.
enum DetonateResult { destroyed, noDetonators, notFound, alreadyDead }

/// Genesis Torpedo and Atomic Detonator rules.
///
/// Deliberately a service rather than methods on `Planet`. The two items are the
/// first things in the game that **create and destroy** the thing the rest of
/// the planet system is built around, so the rules that decide when that is
/// allowed — the slot cap, the cargo bound, the over-stack warning, the
/// collision dice — need one home that a screen cannot half-implement.
class WorldForging {
  WorldForging._();

  /// Cargo slots one unit of each item occupies.
  static const int cargoPerUnit = 1;

  /// Picks a world type at random from the ten.
  ///
  /// Random rather than chosen, and the reason is the **Atomic Detonator**: if
  /// the player picked the type there would be nothing to re-roll, and the
  /// torpedo would be a one-shot purchase rather than a repeatable sink. The
  /// lottery is the cost and the sector you fire into is the bet.
  ///
  /// The cost of that choice is recorded in the design document: ten types means
  /// an expected **ten rolls** to get a specific one, each costing a torpedo and
  /// a detonator. Type *profiles* are the proposed mitigation and are not built.
  static String rollType(math.Random rng) =>
      Planet.allTypes[rng.nextInt(Planet.allTypes.length)];

  /// Fires a torpedo into [sector].
  ///
  /// Consumes one torpedo and one cargo slot. The world is created **unscanned**
  /// and unowned, so the player still has to scan and claim it — a torpedoed
  /// world is a raw orbit, not a colony.
  ///
  /// [name] is supplied by the caller rather than generated here, because the
  /// name pool is a presentation concern and the caller usually wants to show
  /// the result. [cap] is the universe's `planetsPerSector`.
  static (LaunchResult, Planet?) launch({
    required Player player,
    required Sector sector,
    required int cap,
    required math.Random rng,
    String? name,
  }) {
    if (player.genesisTorpedoes <= 0) {
      return (LaunchResult.noTorpedoes, null);
    }
    if (player.cargoUsed >= player.maxCargo) {
      return (LaunchResult.holdFull, null);
    }

    // Pre-launch the sector is only *full*; firing is what makes it over.
    final overStacking = sector.isFull(cap);
    final type = rollType(rng);
    final world = Planet.fromGenesis(
      name: name ?? _nameFor(type, sector, rng),
      planetType: type,
      imagePath: _imageFor(type, rng),
    );
    final added = sector.launchWorld(world);
    if (added == null) return (LaunchResult.launched, null);

    GameEventLog.global.system(
      '[Genesis] ${sector.name} gained a new $type world, ${world.name}',
    );
    if (overStacking) {
      // Unmissable on purpose. A silent destabilisation that destroys a
      // million-colonist colony overnight reads as a bug, not as a risk the
      // player accepted.
      GameEventLog.global.system(
        '[Genesis] WARNING: ${sector.name} now holds ${sector.worldSlotsUsed} '
        'worlds against a limit of $cap. Unstable orbits collide — a check is '
        'rolled every 24 hours and the pair can be lost.',
      );
    }
    return (
      overStacking ? LaunchResult.wouldOverstack : LaunchResult.launched,
      added,
    );
  }

  /// Destroys a world, freeing its slot.
  static (DetonateResult, Player) detonate({
    required Player player,
    required Sector sector,
    required Planet world,
  }) {
    if (world.isDestroyed) return (DetonateResult.alreadyDead, player);
    if (player.atomicDetonators <= 0) {
      return (DetonateResult.noDetonators, player);
    }
    if (!sector.detonateWorld(world)) {
      return (DetonateResult.notFound, player);
    }
    GameEventLog.global.system(
      '[Genesis] ${world.name} was vaporised in ${sector.name} by a detonator',
    );
    return (
      DetonateResult.destroyed,
      player.copyWith(
        atomicDetonators: player.atomicDetonators - 1,
        // Clamped: the two counters are meant to stay in step, but a save edit
        // or a legacy value can desync them, and a *negative* hold reads as a
        // nonsense figure on the HUD and would then be used as the space budget
        // for every other purchase.
        cargoUsed: (player.cargoUsed - cargoPerUnit).clamp(0, player.maxCargo),
      ),
    );
  }

  /// Runs one 24-hour gravity check over the galaxy.
  ///
  /// Wall-clock, not game ticks, and deliberately so. Construction counts ticks
  /// because a build is *the player's own progress* and must not complete while
  /// they sleep. A collision is the opposite: it is a background hazard, it is
  /// meant to bite an abandoned sector, and it is the only thing that makes
  /// over-stacking a decision rather than a free bonus.
  ///
  /// Callers drive this from a once-a-day check; it is not on the game tick.
  static int runDailyCollisions(
    List<Sector> sectors,
    int cap,
    math.Random rng,
  ) {
    var destroyed = 0;
    for (final sector in sectors) {
      if (sector.freeSlots(cap) > 0) continue;
      final lost = sector.rollCollision(cap, rng);
      if (lost.isEmpty) continue;
      destroyed += lost.length;
      GameEventLog.global.system(
        '[Gravity] ${sector.name}: ${lost.map((p) => p.name).join(' and ')} '
        'collided and were destroyed. ${sector.worldSlotsUsed} worlds remain '
        'against a limit of $cap.',
      );
    }
    return destroyed;
  }

  /// Picks a display name for a new world, avoiding the names already in use.
  static String _nameFor(String type, Sector sector, math.Random rng) {
    final pool = List<String>.from(Planet.planetNames);
    pool.shuffle(rng);
    final taken = sector.planets.map((p) => p.name).toSet();
    for (final n in pool) {
      if (!taken.contains(n)) return n;
    }
    // The name pool is 100 entries and a sector holds at most a handful, so
    // this is unreachable in practice — but a collision would be a visible
    // duplicate label on two worlds in the same list.
    return '$type ${sector.id}-${rng.nextInt(9999)}';
  }

  static String? _imageFor(String type, math.Random rng) {
    final pool = Planet.imagePool[type];
    if (pool == null || pool.isEmpty) return null;
    return pool[rng.nextInt(pool.length)];
  }
}
