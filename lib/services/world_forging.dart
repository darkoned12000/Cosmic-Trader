import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
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
/// What destroying somebody else's world costs you, in reputation.
///
/// Reported rather than applied silently, so the screen can say *what* the
/// player just did to their standing instead of leaving them to notice a
/// number changed three screens later. Null when the player made the world
/// themselves — demolishing your own mistake is the whole point of the item.
class ReputationHit {
  /// The faction offended, or null when the world had no owner. Notoriety is
  /// charged either way: vaporising a world is a violent act whoever it was.
  final FactionClass? faction;

  /// Applied to standing with [faction]. Negative.
  final int standing;

  /// Added to the player's alignment. Negative — a bad deed moves a signed
  /// reputation *down*, which the old one-direction scale could not express.
  final double alignment;

  const ReputationHit({
    required this.faction,
    required this.standing,
    required this.alignment,
  });
}

class WorldForging {
  WorldForging._();

  /// Reputation for destroying a world you did not create.
  ///
  /// An alias onto [ReputationActions.destroyWorld] rather than a figure of its
  /// own: every deed is worth the same everywhere, and two tables would drift.
  static const double destructionAlignment = ReputationActions.destroyWorld;

  /// Standing with the owning faction when the world was not yours to destroy.
  ///
  /// Twice the cost of killing one of their patrols. Charged against the
  /// **owner**, never the creator: blowing up a Guild world you captured last
  /// week is still an act against the Guild, whether or not they built it.
  static const int destructionStanding = -10;

  /// Shared generator for the blast dice, so a detonation is genuinely random.
  /// Tests pass their own [math.Random] instead of seeding this one, which is
  /// what lets them drive both the hit and the miss branches deterministically.
  static final math.Random _rng = math.Random();

  /// Cargo slots one unit of each item occupies.
  ///
  /// **Zero.** These are *equipment*, not cargo: they are carried on the ship
  /// rather than in the hold, so they do not compete with ore for space and a
  /// full hold is no reason to be short of torpedoes. The Ship screen labels the
  /// distinction directly — "Cargo" is the resource types that use slots,
  /// "Equipment" is everything else.
  static const int cargoPerUnit = 0;

  /// Picks a world type at random from [Planet.allTypes].
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
  /// Consumes one torpedo. The world is created **scanned and owned by the
  /// launching pilot's faction** — see [Planet.fromGenesis] for why that rule
  /// was reversed.
  ///
  /// [name] and [type] are both supplied by the caller rather than decided
  /// here, because the player names their own world: the UI rolls the type,
  /// shows it in a naming dialog, and hands both back. [type] in particular
  /// must be the same value the dialog displayed — if `launch` rolled again it
  /// could create a world the player was told was something else, and the
  /// dialog's whole purpose is to describe what they are getting. Omit
  /// [type] only in tests and headless callers that do not show the roll.
  /// [cap] is the universe's `planetsPerSector`.
  /// `launch` is called for the *sector* a player is standing in, and
  /// [GameSettings.planetsPerSector] belongs to the universe rather than to
  /// the player, so it is a parameter for the same reason [tick] is.
  static (LaunchResult, Planet?, Player) launch({
    required Player player,
    required Sector sector,
    required int cap,
    required math.Random rng,
    required int tick,
    String? name,
    String? type,
  }) {
    if (player.genesisTorpedoes <= 0) {
      return (LaunchResult.noTorpedoes, null, player);
    }

    // Pre-launch the sector is only *full*; firing is what makes it over.
    final overStacking = sector.isFull(cap);
    final rolled = type ?? rollType(rng);
    final world = Planet.fromGenesis(
      name: name ?? suggestName(rolled, sector, rng),
      planetType: rolled,
      imagePath: _imageFor(rolled, rng),
      owner: player.faction,
      // Recorded from the pilot, not the faction: `creator` is a *name*, and
      // "who made this" is a person. Two pilots of the same faction are not
      // interchangeable for this question.
      creator: player.name,
      creatorFaction: player.faction,
    );
    final added = sector.launchWorld(world, cap, tick);
    if (added == null) return (LaunchResult.launched, null, player);

    // The torpedo is spent here, not by the caller. It used to be the caller's
    // job, while `detonate` has always spent its own item — so the two halves of
    // the loop disagreed about who owns the accounting, which is a trap waiting
    // for a second launch call site to forget. One owner per item.
    //
    // Creating a world is also the game's loudest good deed, so it is charged
    // here rather than by the caller for the same reason: the rule owns its
    // accounting on every axis. See [ReputationActions.createWorld] for the
    // launch/detonate loop this opens up.
    final spent = player
        .copyWith(genesisTorpedoes: player.genesisTorpedoes - 1)
        .withAlignmentDelta(ReputationActions.createWorld);

    GameEventLog.global.system(
      '[Genesis] ${sector.name} gained a new $rolled world, ${world.name}',
    );
    // The creation is logged; the over-stack is not. Warning on every launch
    // past the cap would fire on the fourth world in a three-world sector and
    // then again every day after, and a warning that repeats forever stops being
    // read as information. The rules are the rules and the player was told once.
    // The clock is armed either way.
    return (
      overStacking ? LaunchResult.wouldOverstack : LaunchResult.launched,
      added,
      spent,
    );
  }

  /// Odds that a detonator's blast catches the ship that fired it.
  ///
  /// From the original: destroying a world is *almost* free, but not reliably
  /// free, and the near-miss is the point. Modelled as a chance rather than a
  /// flat damage tax so a world can be vaporised without ever costing hull.
  static const double blastChanceMin = 0.03;
  static const double blastChanceMax = 0.07;

  /// Fraction of the destroyed world's hull that reaches the firing ship when
  /// the blast does catch it, as a [min, max] band.
  ///
  /// Scaled to the world rather than a flat figure, because a level-6 Citadel
  /// going up is a different event from a scorched rock: the risk has to rise
  /// with the stakes or the biggest possible detonation is the safest one. At
  /// a level-6 hull of 70,000 this is 1,400-3,500 damage, which a mid-game
  /// shield absorbs entirely and a stripped ship will not.
  static const double blastDamageMinFraction = 0.02;
  static const double blastDamageMaxFraction = 0.05;

  /// Destroys a world, freeing its slot.
  ///
  /// [cap] and [tick] are threaded through so the sector can reconcile its
  /// own stability clock the moment the count drops — see
  /// [Sector.detonateWorld]. They are parameters rather than ambient reads for
  /// the same reason [launch] takes them: the cap belongs to the universe
  /// settings and the clock to the caller, so the rule stays testable.
  ///
  /// The returned player has the detonator **and** any blast damage applied —
  /// shields first, then hull, mirroring [PortCombatService]. Callers that want
  /// to narrate the hit diff the player's shields and hull across the call; the
  /// return type stayed a pair so the existing call sites keep working.
  static (DetonateResult, Player, ReputationHit?) detonate({
    required Player player,
    required Sector sector,
    required Planet world,
    required int cap,
    required int tick,
    math.Random? rng,
  }) {
    if (world.isDestroyed) return (DetonateResult.alreadyDead, player, null);
    if (player.atomicDetonators <= 0) {
      return (DetonateResult.noDetonators, player, null);
    }
    // Read both before the world is destroyed. `Planet.destroy()` clears
    // ownership, homeworld status and the colony, so anything read afterwards is
    // zero — the same ordering trap that made the blast damage 0 when the hull
    // was sampled after the fact.
    // Whose grievance it is: the **maker's** faction where known, else the
    // current holder. Reading `owner` alone let a capture launder the charge —
    // take the world, and there is nobody left to be offended but yourself.
    final offendingFaction = world.creatorFaction ?? world.owner;
    // **Creator, not owner, for the faction charge.** Fighting for a world and
    // taking it makes you its owner; it does not make you the person who built
    // it. Blowing up a Guild world you captured last week is still an act
    // against the Guild, so `owner` decides who is offended even though
    // `creator` decides whether you had any right.
    //
    // The alignment charge, though, is **unconditional**. It used to be skipped
    // for a world you made yourself, on the reasoning that demolishing your own
    // mistake is what the detonator is *for*. That exemption is exactly what made
    // reputation farmable: a launch paid +1024 and self-demolition was free, so
    // the pair was a +1024 cycle for 55,000 credits. With [ReputationActions
    // .createWorld] now equal and opposite to [ReputationActions.destroyWorld]
    // the loop nets zero whether or not the exemption exists — and removing it
    // also means the rule cannot be reopened by raising the creation figure.
    final madeIt = world.creator != null && world.creator == player.name;
    // Never charge your own faction for your own demolition: the standing hit is
    // meant to say "you did this to somebody else".
    final factionToCharge = (madeIt || offendingFaction == player.faction)
        ? null
        : offendingFaction;
    final reputation = ReputationHit(
      faction: factionToCharge,
      standing: factionToCharge == null ? 0 : destructionStanding,
      alignment: destructionAlignment,
    );
    // The boom size is read BEFORE the world is destroyed. `Planet.destroy`
    // zeroes the colony and the hull with it, so reading `maxHull` afterwards
    // yields 0 — every blast computed to zero damage, which made the 3-7%
    // chance a 3-7% chance of nothing at all. The comment here once claimed the
    // read was ordered first while the code did the opposite.
    final boom = world.maxHull.toDouble();
    if (!sector.detonateWorld(world, cap, tick)) {
      return (DetonateResult.notFound, player, null);
    }
    final random = rng ?? _rng;
    var spent = player
        .copyWith(atomicDetonators: player.atomicDetonators - 1)
        // Through the delta helper so the clamp and the sign live in one place.
        .withAlignmentDelta(reputation.alignment);
    if (reputation.faction != null) {
      spent = spent.withFactionStandingChange(
          reputation.faction!, reputation.standing);
    }

    final caught = random.nextDouble() <
        blastChanceMin +
            random.nextDouble() * (blastChanceMax - blastChanceMin);
    if (!caught) {
      GameEventLog.global.system(
        // No sector. This line is world news rather than a private note, and a
        // destroyed world is a thing worth hunting for — naming where it stood
        // turns the player's own detonation into a treasure map for whoever
        // reads the log.
        '[Genesis] ${world.name} was vaporised by a detonator',
      );
      return (DetonateResult.destroyed, spent, reputation);
    }

    final damage = (boom *
            (blastDamageMinFraction +
                random.nextDouble() *
                    (blastDamageMaxFraction - blastDamageMinFraction)))
        .round();
    final hurt = _applyBlast(spent, damage);
    GameEventLog.global.system(
      '[Genesis] ${world.name} was vaporised by a detonator — the blast '
      'caught the firing ship for $damage',
    );
    return (DetonateResult.destroyed, hurt, reputation);
  }

  /// Blast damage onto a ship: shields absorb first, hull takes the rest.
  ///
  /// The same order every other damage path in the game uses, so "my shields
  /// held" reads identically whether a port shot me or my own torpedo did.
  static Player _applyBlast(Player player, int damage) {
    if (damage <= 0) return player;
    final toShields = damage.clamp(0, player.shields);
    final toHull = (damage - toShields).clamp(0, player.hull);
    return player.copyWith(
      shields: player.shields - toShields,
      hull: (player.hull - toHull).clamp(0, player.hull),
    );
  }

  /// Hours between gravity checks on an unstable system.
  /// One game day — in **ticks**. See `GameClock` for why every duration in
  /// the game is counted this way and none of them in milliseconds.
  static const int collisionIntervalTicks = GameClock.ticksPerDay;

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
    int tick,
    math.Random rng,
  ) {
    var destroyed = 0;
    for (final sector in sectors) {
      // Self-healing on the way past: clears the stamp on a sector that has been
      // brought back under the cap, so a system stabilised by a detonator and
      // then pushed over again starts a fresh day rather than inheriting the
      // old one's remaining time.
      sector.reconcileStability(cap, tick);
      if (!sector.isOverStacking(cap)) continue;

      final armedAt = sector.destabilisedAtTick;
      if (armedAt == null) continue;
      if (tick - armedAt < collisionIntervalTicks) continue;

      // Re-armed *before* the roll, not after, and the reason is
      // exception-safety rather than schedule-keeping. `tick` is a value, not a
      // clock read, and it was captured at the top of this sweep — so assigning
      // it on either side of [Sector.rollCollision] leaves the same final state
      // in every successful call, and the original comment's claim that ordering
      // is what stops the window creeping forward was simply wrong.
      //
      // What the ordering actually buys: if the roll ever throws, the stamp has
      // already moved, so the check is not left permanently overdue and
      // re-firing on every subsequent tick. A crash costs one skipped day
      // instead of an unbounded pile of pending rolls.
      sector.destabilisedAtTick = tick;

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
  /// A name the world could have, avoiding names already used in [sector].
  ///
  /// Public because the naming dialog needs to *offer* something: an empty
  /// text field in front of a player who has just paid for a world reads as a
  /// chore, and the field is prefilled with this so accepting it is the
  /// cheapest path. It consumes RNG draws, so a caller that rolls the type and
  /// then calls this has spent the generator in a deliberate order — pass the
  /// name to [launch] and it will not roll a second one.
  static String suggestName(String type, Sector sector, math.Random rng) {
    final pool = List<String>.from(Planet.planetNames);
    pool.shuffle(rng);
    final taken = sector.planets.map((p) => p.name).toSet();
    for (final n in pool) {
      if (!taken.contains(n)) return n;
    }
    // The name pool is 100 entries and a sector holds at most a handful, so
    // this is unreachable in practice — but a collision would be a visible
    // duplicate label on two worlds in the same list.
    //
    // No type in the fallback. This string is prefilled into the naming dialog,
    // which is shown *before* the launch is committed — a name reading
    // "Ice 7-4182" would hand over the roll to a player who is still free to
    // abort, which is the one thing that dialog must not do.
    return 'Sector ${sector.id}-${rng.nextInt(9999)}';
  }

  /// Delegates to [Planet.randomImageFor]. It used to return the **bare file
  /// name** — `Terran_World_1.gif`, with no `assets/images/planets/` prefix — so
  /// `Image.asset` could never resolve it and every torpedo-launched world
  /// rendered with no picture at all, for every type. The universe generator had
  /// the prefix right; there were two copies of one rule and only one was
  /// correct, which is the whole argument for this being a single function.
  static String? _imageFor(String type, math.Random rng) =>
      Planet.randomImageFor(type, rng);
}
