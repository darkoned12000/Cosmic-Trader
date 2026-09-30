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
  ///
  /// **Zero.** These are *equipment*, not cargo: they are carried on the ship
  /// rather than in the hold, so they do not compete with ore for space and a
  /// full hold is no reason to be short of torpedoes. The Ship screen labels the
  /// distinction directly — "Cargo" is the resource types that use slots,
  /// "Equipment" is everything else.
  static const int cargoPerUnit = 0;

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
    required int nowMs,
    String? name,
  }) {
    if (player.genesisTorpedoes <= 0) {
      return (LaunchResult.noTorpedoes, null);
    }

    // Pre-launch the sector is only *full*; firing is what makes it over.
    final overStacking = sector.isFull(cap);
    final type = rollType(rng);
    final world = Planet.fromGenesis(
      name: name ?? _nameFor(type, sector, rng),
      planetType: type,
      imagePath: _imageFor(type, rng),
    );
    final added = sector.launchWorld(world, cap, nowMs);
    if (added == null) return (LaunchResult.launched, null);

    GameEventLog.global.system(
      '[Genesis] ${sector.name} gained a new $type world, ${world.name}',
    );
    // The creation is logged; the over-stack is not. Warning on every launch
    // past the cap would fire on the fourth world in a three-world sector and
    // then again every day after, and a warning that repeats forever stops being
    // read as information. The rules are the rules and the player was told once.
    // The clock is armed either way.
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
      player.copyWith(atomicDetonators: player.atomicDetonators - 1),
    );
  }

  /// Hours between gravity checks on an unstable system.
  static const int collisionIntervalMs = 24 * 60 * 60 * 1000;

  /// Runs every gravity check that has **fallen due**, and returns the number of
  /// worlds destroyed.
  ///
  /// A sector's clock starts the moment it goes over the cap (see
  /// [Sector.reconcileStability]), so this is a *due check*, not a daily alarm.
  /// A sector that went over an hour ago is not touched; one that went over
  /// yesterday is. That distinction is the entire reason the stamp exists: a
  /// global wall-clock hour would destroy a world in a system that had been
  /// unstable for three minutes, and a "time since the universe was made" check
  /// would bank a week of hazard and then resolve all of it on the first tick.
  ///
  /// Wall-clock, not game ticks, and deliberately so. Construction counts ticks
  /// because a build is *the player's own progress* and must not complete while
  /// they sleep. A collision is the opposite: a background hazard, meant to bite
  /// an abandoned sector, and the only thing that makes over-stacking a decision
  /// rather than a free bonus.
  ///
  /// The game tick calls this on every pass. Testing whether a stamp is due is
  /// arithmetic, and a 30-second tick resolves "due" to within 30 seconds of the
  /// day being up — so there is no separate scheduler to start, and none to
  /// forget. The first version of this was a rule with no clock attached: the
  /// function existed, was tested, and was never called.
  static int runDueCollisions(
    List<Sector> sectors,
    int cap,
    int nowMs,
    math.Random rng,
  ) {
    var destroyed = 0;
    for (final sector in sectors) {
      // Self-healing on the way past: clears the stamp on a sector that has been
      // brought back under the cap, so a system stabilised by a detonator and
      // then pushed over again starts a fresh day rather than inheriting the
      // old one's remaining time.
      sector.reconcileStability(cap, nowMs);
      if (!sector.isOverStacking(cap)) continue;

      final armedAt = sector.destabilisedAtMs;
      if (armedAt == null) continue;
      if (nowMs - armedAt < collisionIntervalMs) continue;

      // Re-armed *before* the roll, not after. A roll cannot throw, and doing it
      // first means a system that survives a check starts its next day from the
      // moment the check came due, rather than drifting forward by a tick
      // interval every time it is called.
      sector.destabilisedAtMs = nowMs;

      final lost = sector.rollCollision(cap, rng);
      if (lost.isEmpty) continue;
      destroyed += lost.length;
      // Loud, and the only notification there is. The player is not warned when
      // they over-stack — the rules are the rules and they were told once — so
      // the collision is announced when it happens rather than apologised for in
      // advance.
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
