import 'dart:math' as math;

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/port.dart';

/// Represents a sector in the game universe.
class Sector {
  final int id;
  final String name;
  double x;
  double y;
  final List<int> warpRoutes;

  // Content fields are mutable so the generator can populate them
  bool hasPort;
  String? anomaly;
  int traderCount;
  int duranCount;
  int vinariCount;
  int pirateCount;

  bool navHaz;
  bool hasBeacon;
  String? beaconOwner;
  String? beaconText;

  // --- New structured content ---
  Port? port;

  /// Every world in this sector, up to the universe's `planetsPerSector`.
  ///
  /// Was a single `Planet?`. Three worlds per sector is the point: the
  /// complementarity loop (an Ocean feeding a Lava, an Earth feeding both) only
  /// feels good when the worlds are adjacent, and hauling organics to the next
  /// world in your own sector is trivial where hauling across the galaxy is a
  /// chore you route around.
  ///
  /// A destroyed world is **removed** from this list. This reverses an
  /// earlier decision to mark it `isDestroyed` and keep it, so a corpse could
  /// "still be drawn and argued about" — which in practice left a vaporised
  /// world in the sector contents, landable, and claimable again. Destroying
  /// something and then being able to fly to it and take it back is not
  /// destruction. Both destruction paths agree: [detonateWorld] and
  /// [rollCollision] remove.
  ///
  /// The consequence to keep in mind is that `isDestroyed` on a world *in this
  /// list* is now an invariant violation rather than a normal state. It still
  /// means something on a detached instance — which [Planet.produce] checks —
  /// and `_planetsFromJson` purges corpses from older saves so the invariant
  /// survives a reload.
  ///
  /// (There used to be a second source of detached instances: every screen held
  /// its own parse of the universe. Storage shares one graph now, so this list
  /// has one owner.)
  List<Planet> planets;

  /// Worlds still fit to colonise. Identical to [planets] in practice, since
  /// destroyed worlds are removed, but kept as the filter because a detached or
  /// legacy instance can still carry the flag.
  List<Planet> get livingPlanets =>
      planets.where((p) => !p.isDestroyed).toList(growable: false);

  bool get hasPlanet => planets.isNotEmpty;

  /// The first world in the sector, for UI summaries that do not care which.
  ///
  /// **Never use this to find a homeworld or a capital.** A sector can hold a
  /// faction's capital *and* a frontier world, and `repopulation` and
  /// `colonist_supply` both need the capital specifically — reading slot 0 would
  /// silently pick a neighbour. Those go through `RepopulationService
  /// .homeworldSectors`, which searches every world in every sector.
  Planet? get primaryPlanet => planets.isEmpty ? null : planets.first;

  /// The world's homeworld if this sector holds one, else null.
  ///
  /// A convenience over `planets.firstWhereOrNull((p) => p.isHomeworld)`, which
  /// is the only correct way to ask the question now.
  Planet? get homeworld {
    for (final p in planets) {
      if (p.isHomeworld) return p;
    }
    return null;
  }

  Sector({
    required this.id,
    required this.name,
    required this.x,
    required this.y,
    required this.warpRoutes,
    this.hasPort = false,
    this.anomaly,
    this.traderCount = 0,
    this.duranCount = 0,
    this.vinariCount = 0,
    this.pirateCount = 0,
    this.navHaz = false,
    this.hasBeacon = false,
    this.beaconOwner,
    this.beaconText,
    this.port,
    List<Planet>? planets,
    // Legacy single-world constructor argument. Still accepted so the generator
    // and every test fixture read naturally; folded into [planets] below.
    Planet? planet,
  }) : planets = planets ?? (planet == null ? <Planet>[] : <Planet>[planet]);

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'x': x,
      'y': y,
      'warpRoutes': warpRoutes,
      'hasPort': hasPort,
      'anomaly': anomaly,
      'traderCount': traderCount,
      'duranCount': duranCount,
      'vinariCount': vinariCount,
      'pirateCount': pirateCount,
      'navHaz': navHaz,
      'hasBeacon': hasBeacon,
      'beaconOwner': beaconOwner,
      'beaconText': beaconText,
      if (port != null) 'port': port!.toJson(),
      if (planets.isNotEmpty)
        'planets': planets.map((p) => p.toJson()).toList(),
      // Nullable is the *normal* state for a stable sector, so it is omitted
      // rather than written as null. A sector only carries a stamp while it is
      // over-stacked.
      if (destabilisedAtTick != null) 'destabilisedAtTick': destabilisedAtTick,
    };
  }

  factory Sector.fromJson(Map<String, dynamic> json) {
    final sector = Sector(
      id: json['id'] as int,
      name: json['name'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      warpRoutes:
          (json['warpRoutes'] as List<dynamic>).map((e) => e as int).toList(),
      hasPort: json['hasPort'] as bool? ?? false,
      anomaly: json['anomaly'] as String?,
      traderCount: json['traderCount'] as int? ?? 0,
      duranCount: json['duranCount'] as int? ?? 0,
      vinariCount: json['vinariCount'] as int? ?? 0,
      pirateCount: json['pirateCount'] as int? ?? 0,
      navHaz: json['navHaz'] as bool? ?? false,
      hasBeacon: json['hasBeacon'] as bool? ?? false,
      beaconOwner: json['beaconOwner'] as String?,
      beaconText: json['beaconText'] as String?,
      port: json['port'] != null
          ? Port.fromJson(json['port'] as Map<String, dynamic>)
          : null,
      planets: _planetsFromJson(json),
    );
    // Assigned rather than passed to the constructor: the stamp is mutable (it
    // arms and clears as the sector crosses the cap), and a mutable field cannot
    // be a constructor parameter.
    // A pre-clock save carries the millisecond stamp. It is read as nothing:
    // the two units are not comparable and inventing a conversion would either
    // destroy a world immediately or grant immunity. An unstable sector simply
    // starts its day again, which is the same as being newly over-stacked.
    sector.destabilisedAtTick = (json['destabilisedAtTick'] as num?)?.toInt();
    return sector;
  }

  /// Reads the world list, migrating a pre-multi-planet save.
  ///
  /// A legacy sector has a single `planet` object and no `planets` array. It
  /// loads into a one-element list, which is exactly right: that save *did* have
  /// one world, and pretending otherwise would lose it.
  ///
  /// `hasPlanet` is deliberately ignored rather than trusted. It is a second
  /// source of truth for something [planets] already answers, and in a legacy
  /// save it can disagree with `planet` — a sector flagged `hasPlanet: true`
  /// with a missing `planet` object would otherwise lose its world silently.
  /// Deriving it from the list is the same lesson as `hasPlanet` becoming a
  /// getter: one source of truth for a fact that is stored twice.
  static List<Planet> _planetsFromJson(Map<String, dynamic> json) {
    final raw = json['planets'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map(Planet.fromJson)
          // Drop worlds an older build already destroyed. Destruction now removes
          // the record outright, but a save written before that change carries
          // corpses, and they would otherwise reload as landable worlds with
          // `isDestroyed: true` — the "fly to the dead planet and claim it" bug,
          // resurrected from disk. Purging here makes the invariant "no destroyed
          // world is ever in the list" hold across a reload rather than only for
          // sectors nobody has saved since.
          .where((p) => !p.isDestroyed)
          .toList(growable: true);
    }
    final legacy = json['planet'];
    if (legacy is Map<String, dynamic>) {
      final world = Planet.fromJson(legacy);
      return world.isDestroyed ? <Planet>[] : <Planet>[world];
    }
    return <Planet>[];
  }

  // ---------------------------------------------------------------------------
  // Genesis Torpedo / Atomic Detonator
  // ---------------------------------------------------------------------------

  /// How many **living** worlds the sector's physics allows.
  ///
  /// Living, not total: a destroyed world is kept in [planets] so it can still
  /// be drawn and argued about, but it is not occupying orbital real estate.
  /// That is what makes the detonate-then-re-roll loop work — the slot the
  /// detonator frees is the one the next torpedo fills.
  int get worldSlotsUsed => livingPlanets.length;

  /// Slots left before the sector is over-stacked.
  int freeSlots(int cap) {
    final left = cap - worldSlotsUsed;
    return left < 0 ? 0 : left;
  }

  /// Whether the sector is **full** — every slot the universe allows is taken.
  ///
  /// This is the pre-launch question: firing here would exceed the cap. It is
  /// deliberately not the same predicate as [isOverStacking], and conflating the
  /// two is a real bug this was caught by. A sector holding exactly [cap] worlds
  /// is at capacity, not over it, so its gravity is still fine and it should not
  /// be described as unstable.
  bool isFull(int cap) => worldSlotsUsed >= cap;

  /// Whether the sector is **over** the cap and therefore gravitationally
  /// unstable. This is the state the 24-hour collision roll acts on, and it is
  /// strictly past the cap — a legal system cannot collide, so there is nothing
  /// to decide about one.
  bool isOverStacking(int cap) => worldSlotsUsed > cap;

  /// When this system became over-stacked, in epoch milliseconds, or null while
  /// it is stable.
  ///
  /// The clock starts **the moment the sector goes over** — a torpedo lands, or
  /// a world arrives some other way — and 24 hours later the first gravity check
  /// falls due. Not a global wall-clock hour, and not "time since the universe
  /// was made": a player who over-stacks at 3am should not find a collision
  /// waiting on them at midnight, and a sector left over for a week should not
  /// accumulate a week of un-rolled hazard and then resolve all of it at once.
  ///
  /// It is re-armed after every roll, so an unstable system stays on a daily
  /// cycle for as long as it stays unstable. Clearing a world back under the cap
  /// clears the stamp, and going over again starts a fresh day.
  int? destabilisedAtTick;

  /// Sets or clears [destabilisedAtTick] to match the sector's current state.
  ///
  /// Idempotent and **self-healing**, and that is the point: it is called from
  /// every path that can change the world count, including the daily sweep, so
  /// the stamp cannot drift out of agreement with the thing it describes. A
  /// stamp that had to be maintained by hand at each call site is a stamp that
  /// will eventually be wrong, and a wrong stamp is either a sector that never
  /// rolls or one that rolls on a sector that never should.
  ///
  /// [tick] is injected rather than read from the clock so the whole rule is
  /// testable without waiting a day.
  void reconcileStability(int cap, int tick) {
    if (isOverStacking(cap)) {
      destabilisedAtTick ??= tick;
    } else {
      destabilisedAtTick = null;
    }
  }

  /// Adds a torpedoed world. Returns it, or null if there is nothing to add to.
  ///
  /// Over-stacking is **allowed on purpose**. The classic game made it a weapon:
  /// a fourth world in a three-world sector destabilises the system, and the
  /// owner has to clear it before the dice roll comes up. Hard-blocking it would
  /// remove the only offensive use of the torpedo and make the detonator
  /// pointless — a capacity limit can be waited out, a hazard has to be answered.
  Planet? launchWorld(Planet world, int cap, int nowMs) {
    if (world.isDestroyed) return null;
    planets.add(world);
    // Arm here rather than at the call site, so a world arriving by any future
    // route starts the same clock and the caller never has to know the rule
    // exists. [cap] and [nowMs] are parameters rather than reads of ambient
    // state: the cap belongs to the universe settings and the clock belongs to
    // the caller, and neither is this sector's business to go looking for.
    reconcileStability(cap, nowMs);
    return world;
  }

  /// Detonates [world], freeing its slot. Returns false if it is not here.
  ///
  /// Takes [cap] and [nowMs] and reconciles, mirroring [launchWorld]. A
  /// detonation drops a world out of [livingPlanets], so it is the one way the
  /// count can fall back **under** the cap, and the stamp has to learn that
  /// immediately: a sector stabilised by a detonator and then pushed over again
  /// must start a fresh day, not inherit the old one's remaining time.
  ///
  /// It previously could not do this — the method had no cap and no clock — and
  /// the invariant held only because [WorldForging.runDueCollisions] happens to
  /// sweep every sector each tick. That is self-healing by luck, not by
  /// construction: the moment the sweep is filtered to "only sectors flagged
  /// unstable" (the obvious optimisation once the sector count is large), or
  /// anything calls [Planet.destroy] directly, a stale stamp survives for
  /// however long it takes the next full sweep to reach that sector. A rule
  /// that only holds because a bystander happens to sweep past is not a rule.
  bool detonateWorld(Planet world, int cap, int nowMs) {
    final i = planets.indexWhere((p) => p.id == world.id);
    if (i < 0) return false;
    // Neutralise, *then* remove. `destroy()` zeroes the colony and flips
    // `isDestroyed`, which is what stops [Planet.produce] paying out — and every
    // screen holds its own copy of the universe, so the object the detonation
    // was fired from is a *different instance* from the one in this list. Dropping
    // it without destroying it would leave that detached copy with 500,000
    // colonists still producing into a world that no longer exists, and still
    // rendering in whatever screen is holding it.
    //
    // Removing rather than marking is deliberate: a destroyed world is gone from
    // the records, not a corpse left in the list. That reverses an earlier
    // decision to keep it "so it can still be drawn and argued about", which in
    // practice meant a dead world stayed landable — you could fly to a vaporised
    // planet and claim it again, which is the opposite of destroying it.
    planets[i].destroy();
    planets.removeAt(i);
    reconcileStability(cap, nowMs);
    return true;
  }

  /// Rolls one 24-hour gravity check on an over-stacked system.
  ///
  /// Returns the worlds **destroyed** by a collision, empty when the system
  /// holds. Only over-stacked sectors roll at all — a legal system cannot
  /// collide, so there is nothing to decide.
  ///
  /// The odds worsen with each world past the cap, and a collision takes the
  /// **pair** rather than a lone world: two bodies meeting is the fiction, and
  /// losing a pair makes over-stacking a real gamble instead of a slow tax.
  /// Living worlds only, so a corpse is never the casualty.
  List<Planet> rollCollision(int cap, math.Random rng) {
    final over = worldSlotsUsed - cap;
    if (over <= 0) return <Planet>[];
    // 1-in-N per day per world past the cap. At 3 the cap, one extra world is a
    // 1-in-8 daily loss; three extras is 1-in-2, which is a sector that eats
    // itself within a week of being abandoned.
    final chance = 1.0 / (8 * over);
    if (rng.nextDouble() >= chance) return <Planet>[];

    final living = livingPlanets.toList();
    if (living.length < 2) return <Planet>[];
    living.shuffle(rng);
    final lost = <Planet>[living.first, living[1]];
    for (final p in lost) {
      // Same contract as [detonateWorld]: neutralise the object, then remove it
      // from the records. A collision that left a corpse behind while a
      // detonator did not would mean two different meanings for "destroyed",
      // and the player's world would come back or not depending on which one
      // got it.
      p.destroy();
      planets.removeWhere((q) => q.id == p.id);
    }
    return lost;
  }

  static const int _gridSize = 5;
  static const int _offset = 100;

  static String _colLetter(int n) {
    String result = '';
    int m = n;
    while (true) {
      result = String.fromCharCode(65 + m % 26) + result;
      m = m ~/ 26;
      if (m <= 0) break;
      m--;
    }
    return result;
  }

  /// Quadrant name derived from the coordinate grid.
  String get quadrant {
    int col = (x / _gridSize).floor();
    int row = (y / _gridSize).floor();
    return '${_colLetter(col + _offset)}${row + _offset}';
  }

  int get totalNpcs => traderCount + duranCount + vinariCount + pirateCount;
}
