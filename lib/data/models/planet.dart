import 'dart:math' as math;
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:uuid/uuid.dart';

/// Decodes a persisted faction name, tolerating one that no longer exists.
///
/// Uses `byName` rather than `firstWhere` **deliberately**: `firstWhere` with no
/// match throws `StateError`, not `ArgumentError`, so an `on ArgumentError`
/// clause silently never fires and a save naming a since-removed faction takes
/// the whole planet decode — and therefore the whole sector file — down with
/// it. `byName` throws `ArgumentError`, which is what the `on` clause expects.
///
/// This is the same idiom as `port.dart`'s `_parseFactionClass`; keep the two
/// in step. `FactionStanding`, `NpcShip`, and `Player` use `orElse` instead,
/// which is also correct.
FactionClass? _parseFactionClass(String? name) {
  if (name == null) return null;
  try {
    return FactionClass.values.byName(name);
  } on ArgumentError {
    return null;
  }
}

class Planet {
  /// Stable identity for this world, independent of its sector and its name.
  ///
  /// **Required since sectors hold more than one planet.** `(sectorId)` used to
  /// be the identity, because a sector had exactly one world and nothing keyed a
  /// planet by name. Both of those are now false: three worlds can share a
  /// sector, and a world can be renamed, so neither its sector nor its name can
  /// identify it. This is the one piece of save data that did not exist when the
  /// design document argued about it and correctly predicted it would be needed.
  ///
  /// A legacy save has no id, so `fromJson` **mints one** rather than defaulting
  /// to a constant: a shared placeholder id would make every old world in the
  /// galaxy look like the same world to anything that compares ids.
  String id;

  final String name;
  final String planetType;
  final String atmosphere;

  // Ownership
  FactionClass? owner;
  bool isHomeworld;
  FactionClass? homeworldOf;

  /// Whoever brought this world into existence, by name.
  ///
  /// **Null means nobody did** — a world the universe generator placed has no
  /// maker, and that is the normal case for almost every world in the galaxy.
  /// Set when a Genesis Torpedo resolves, to the launching pilot's name.
  ///
  /// `final`, and therefore **not editable by anyone** — not the player, not an
  /// NPC, not a screen. That is the whole point: it is provenance, not
  /// possession. `owner` changes hands constantly (you fight for a world, you
  /// capture it, someone retakes it) and none of those transfers create it. The
  /// distinction is load-bearing, because destroying a world you did not make is
  /// an act of aggression against whoever did, *even if you own it now* — so
  /// [WorldForging.detonate] reads this field and not `owner` when deciding
  /// whether to charge for the act.
  ///
  /// It is a **name**, not an id, which is the weakest form of provenance: a
  /// pilot who renames after creating a world would be charged for detonating
  /// it. That is accepted for now — see the note in `AGENTS.md` — because the
  /// alternative is a second identity field that nothing else in the game keys
  /// on, and the alternative failure (charging the wrong pilot) needs two pilots
  /// with the same name in one galaxy to be reachable.
  final String? creator;

  /// The faction [creator] belonged to when the world was made.
  ///
  /// Separate from `owner` because of the capture case: fight a Guild world, win,
  /// claim it, and `owner` is now you — so a rule that asks "who should be
  /// offended?" through `owner` finds nobody and lets the destroyer walk clean.
  /// The *maker's* faction is the one with a grievance, and it does not change
  /// hands when you take the planet.
  ///
  /// Null wherever [creator] is, and on legacy saves: a world the generator
  /// placed has no maker and therefore no maker's faction.
  final FactionClass? creatorFaction;

  /// Cold-standby capital (C4b): produces only while no live primary
  /// homeworld of the same faction exists. Recapture of the primary
  /// idles the backup again — capitals move back, they don't duplicate.
  bool isBackupHomeworld;

  /// Planet-killer path (C4b): a destroyed world is permanently out of
  /// play — no colony, no production, no homeworld status. Set via
  /// [destroy]; combat triggers arrive with the invasion system.
  bool isDestroyed;

  // Colony
  int population;
  int colonistsMinerals;
  int colonistsOrganics;
  int colonistsIndustrial;

  /// Colonists bought from a capital and travelling to this world.
  ///
  /// Credits are debited the moment the shipment is ordered, so the headcount
  /// has to live somewhere until it lands or the player pays for people who are
  /// not on the planet and not visibly coming either. [colonistTransitTicks] is
  /// the countdown; both are zero when nothing is in transit.
  int colonistsInTransit;

  /// Ticks left before [colonistsInTransit] joins [population].
  int colonistTransitTicks;

  /// Credits this world has **earned from sales and not yet been withdrawn**.
  ///
  /// Mirrors `Port.accumulatedRevenue`, deliberately and down to the name: a port
  /// already accumulates trade income that its owner collects, so a planet doing
  /// the same is learnable rather than novel. The player withdraws it from the
  /// planet screen; an NPC owner's is collected in the tick, exactly as
  /// `_manageOwnedPorts` does for ports.
  ///
  /// **The reason it exists at all** is that the tick may not write a player. It
  /// loads `players`, but never saves them, and a save would be a snapshot taken
  /// at the start of the pass — the read-modify-write clobber that ate colonist
  /// recruits earlier. So the tick credits the *world*, which it owns, and the
  /// screen moves the money to the *pilot*, which it owns. An int rather than the
  /// port's double because a planet's income is a whole number of credits from
  /// rounded sales, with no price multiplier to carry a fraction.
  int accumulatedRevenue;

  /// Orders this world has placed against ports, in flight.
  ///
  /// Lives on the planet because the **world** is the party that ordered: a buy
  /// fills its store, a sell draws on it. A settled job is removed rather than
  /// kept as a corpse, so this list only ever holds work still to do.
  ///
  /// Built in the initializer list rather than defaulted in the parameter, because
  /// Dart requires default parameter values to be constant and a mutable list is
  /// not — and a `const []` fallback in `fromJson` would hand back an unmodifiable
  /// list, which throws on the first `add`.
  final List<TradeJob> tradeJobs;

  /// The last few resolved freight runs — delivered **and** lost — newest
  /// last. Read by nothing but the Market section's Report.
  ///
  /// Lives here rather than on the player because the tick resolves runs and
  /// must never write a player (the read-modify-write clobber that ate colonist
  /// recruits). Bounded by [tradeIncidentHistory] and trimmed on append, so a
  /// long session cannot grow it without limit — an unbounded history on a
  /// model that re-serialises every tick is a file that grows forever.
  ///
  /// Lost runs are recorded with their cause, so "what happened to my
  /// shipment" has an answer after the fact and not only in the log line,
  /// which is a 200-entry ring the player may have scrolled past.
  final List<TradeIncident> tradeIncidents;

  /// Finished orders, newest last.
  ///
  /// A run ledger alone cannot answer "how did that order end" — it is
  /// truncated to ten entries, so a sixteen-run order's last runs have already
  /// been evicted by the time it finishes, and nothing anywhere holds the
  /// totals. This is that somewhere. Ten orders is bounded, and only worlds the
  /// player actually traded carry any, so the cost tracks player activity rather
  /// than galaxy size: 20 active worlds × 10 × ~200 bytes is ~40KB against a
  /// universe file measured in megabytes.
  final List<TradeOrderRecord> tradeOrders;

  /// How many resolved runs a world remembers. Ten is a fortnight of trade at
  /// a busy cadence and a bounded save.
  static const int tradeIncidentHistory = 10;

  /// How many finished orders a world remembers.
  static const int tradeOrderHistory = 10;

  /// Drones, not fighters: ships field drones throughout the game
  /// (`Player.drones`). The old `colonistsFighters` name survived the
  /// planet screen already being labelled "Drones", which made the model
  /// the odd one out.
  /// **LEGACY — do not read this.** Drones are *derived* from the three
  /// production tracks, not staffed: `droneOutput` is computed from what the
  /// others actually make, `PlanetClassSpec.tracks` has no drone entry, and the
  /// colony card renders three rows with no stepper for a fourth.
  ///
  /// This is the corpse of the track that stopped existing. It is kept only so
  /// that old saves round-trip, and it is deliberately **excluded from
  /// [assignedColonists]** — any colonists sitting here are free and available
  /// for real work, which is why the reserve counts them. Nothing in `lib/`
  /// reads it, and the generator no longer seeds it.
  ///
  /// A field that means nothing but looks live is how a rule ends up
  /// transcribed twice and disagreeing: the removed Gas Giant was read from
  /// `TypeMultipliers` by one test and from the class spec by another, and both
  /// suites were green.
  int colonistsDrones;
  double productionEfficiency;

  // Storage
  int storedMinerals;
  int storedOrganics;
  int storedIndustrial;
  int storedDrones;

  /// Output that has overflowed the working store and is waiting to be
  /// collected. **This is the "no waste" answer.**
  ///
  /// The first version of colony production discarded anything that did not fit
  /// the store, which made a busy colony actively harmful: a 5,400-population
  /// Lava world filled 5,000 minerals in 1.6 ticks and then threw away ~98% of
  /// everything it made from then on. Storage became a waste bin rather than a
  /// buffer.
  ///
  /// Now a full store pushes output into here instead, up to a much larger
  /// [pendingCap]. Nothing is destroyed and the colony keeps earning while you
  /// are elsewhere — the same shape as the classic system, where a world turns
  /// out its daily output continuously and you collect it in batches. Collecting
  /// for credits is a placeholder until planets can actually supply a port.
  int pendingMinerals;
  int pendingOrganics;
  int pendingIndustrial;
  int pendingDrones;

  // Level / Citadel (1-6)
  int level;

  /// Ticks left on the current build, or 0 when idle.
  ///
  /// Counted in **game ticks, not wall-clock time**, and that is the entire
  /// reason offline time costs nothing. The classic game this is drawn from was
  /// an online world where a 43-day build was fine because every other colony
  /// was decaying while you slept. This is single-player, so a wall-clock
  /// deadline would mean quitting for a week silently finishing every build and
  /// nothing else: the player would advance and the galaxy would stand still.
  /// Counting ticks means a build only progresses while the game is running,
  /// which keeps the player and the NPCs on the same clock.
  ///
  /// This is deliberately the same mechanism as the homeworld yards'
  /// [productionTimer] countdown.
  int constructionTicksRemaining;

  /// Ticks since the last colony supply draw. Reset by [produce] every
  /// [supplyInterval] ticks.
  int supplyTimer;

  /// How many supply bills this world has been charged. **Not persisted.**
  ///
  /// Exists purely to salt [supplyDrawCommodity], and it has to be its own
  /// counter rather than a reuse of [supplyTimer]: the timer is reset to 0 at the
  /// exact moment the draw happens, so `supplyTimer * 17` in the salt was
  /// **always zero**. The remaining entropy was `population * 31` plus
  /// `name.hashCode`, and population moves slowly — so a colony of a steady size
  /// was locked onto one commodity and every supply bill for the rest of the game
  /// was drawn from the same three options.
  ///
  /// Deliberately a counter and not a `Random()`: the draw has to stay
  /// reproducible for a given tick sequence, which is what lets the colony tests
  /// assert a specific outcome.
  int _supplyDrawCount = 0;

  /// The level this build will produce when it finishes. 0 when idle.
  int constructionTarget;
  int requiredMinerals;
  int requiredOrganics;
  int requiredIndustrial;
  int requiredColonists;

  // Defense
  int defenseLevel;
  double shield;
  double maxShield;
  double hull;
  double maxHull;

  // NPC spawning (homeworld only)
  int productionTimer;
  int spawnInterval;

  // Visual
  String? imagePath;

  // Scanning
  bool scanned;

  Planet({
    required this.name,
    required this.planetType,
    String? id,
    this.atmosphere = 'Unknown',
    this.owner,
    this.isHomeworld = false,
    this.homeworldOf,
    this.population = 0,
    this.accumulatedRevenue = 0,
    List<TradeJob>? tradeJobs,
    List<TradeIncident>? tradeIncidents,
    List<TradeOrderRecord>? tradeOrders,
    this.colonistsInTransit = 0,
    this.colonistTransitTicks = 0,
    this.colonistsMinerals = 0,
    this.colonistsOrganics = 0,
    this.colonistsIndustrial = 0,
    this.colonistsDrones = 0,
    this.productionEfficiency = 1.0,
    Map<String, double>? productionRemainder,
    this.storedMinerals = 0,
    this.storedOrganics = 0,
    this.storedIndustrial = 0,
    this.storedDrones = 0,
    this.pendingMinerals = 0,
    this.pendingOrganics = 0,
    this.pendingIndustrial = 0,
    this.pendingDrones = 0,
    this.level = 1,
    this.constructionTicksRemaining = 0,
    this.supplyTimer = 0,
    this.constructionTarget = 0,
    this.requiredMinerals = 500,
    this.requiredOrganics = 300,
    this.requiredIndustrial = 200,
    this.requiredColonists = 1000,
    this.defenseLevel = 0,
    this.shield = 0,
    this.maxShield = 0,
    this.hull = 1000,
    this.maxHull = 1000,
    this.productionTimer = 0,
    this.spawnInterval = 10,
    this.isBackupHomeworld = false,
    this.isDestroyed = false,
    this.imagePath,
    this.scanned = false,
    this.creator,
    this.creatorFaction,
  })  : id = id ?? const Uuid().v4(),
        // A **mutable** map, and deliberately not a `const {}` default:
        // `_drawProduction` writes to it on every tick, so an unmodifiable one
        // throws `Cannot modify unmodifiable map` the first time any colony
        // produces anything. It also cannot be a mutable default *parameter*,
        // because Dart requires a default parameter value to be constant — hence
        // the initializer list, where a non-constant expression is legal.
        productionRemainder = productionRemainder ?? <String, double>{},
        tradeJobs = tradeJobs ?? <TradeJob>[],
        tradeIncidents = tradeIncidents ?? <TradeIncident>[],
        tradeOrders = tradeOrders ?? <TradeOrderRecord>[];

  /// Builds a world from a Genesis Torpedo: empty, unowned, unpopulated.
  ///
  /// Deliberately the bare minimum. A generated world carries an efficiency
  /// roll, a defence level, a starting store and an image, all of which are
  /// *differences between worlds*; a torpedoed one has no history to differ by,
  /// so it starts at the honest baseline — 1.0 efficiency, no defence, nothing
  /// stored, not yet scanned. Everything it becomes, the player does.
  /// Builds a world out of nothing: the Genesis Torpedo's payload.
  ///
  /// It arrives **scanned and owned by [owner]** rather than as an anonymous
  /// rock. This reverses the original rule, which made a torpedoed world an
  /// unscanned orbit the player then had to survey and claim — and that rule
  /// fought the rest of the feature. The player *made* this world, they paid a
  /// torpedo for it, and the loop it exists to serve (launch, over-stack,
  /// detonate the one you regret) only means something if launching is an act
  /// you perform on a world you own. Handing them an unclaimed rock also made
  /// the launch feel broken: the sector contents listed a new world exactly
  /// like any other, with `NOT SCANNED` where a freshly claimed one reads
  /// `OWNED`, so the thing you had just paid for looked like someone else's.
  ///
  /// [owner] is nullable so a caller with no faction in hand (a generator
  /// seeding a neutral world, a test) can still get the unscanned behaviour by
  /// passing null — it is not a way to opt out silently, and every real call
  /// site passes the launching pilot's faction.
  factory Planet.fromGenesis({
    required String name,
    required String planetType,
    String? id,
    String? imagePath,
    FactionClass? owner,
    String? creator,
    FactionClass? creatorFaction,
  }) =>
      Planet(
        id: id,
        name: name,
        planetType: planetType,
        atmosphere: planetAtmospheres[planetType]?.atmosphere ?? 'Unknown',
        productionEfficiency: 1.0,
        defenseLevel: 0,
        hull: 0,
        maxHull: 0,
        shield: 0,
        maxShield: 0,
        imagePath: imagePath,
        scanned: owner != null,
        owner: owner,
        // Provenance, recorded once at creation and never touched again. Set
        // from the launching pilot so the world has a maker from the moment it
        // exists rather than becoming the player's property by a later claim.
        creator: creator,
        creatorFaction: creatorFaction,
      );

  /// Renders the world permanently uninhabitable (C4b planet-killer
  /// path): colony zeroed, homeworld status and ownership cleared,
  /// defenses gone. Regeneration tied to this world never resumes —
  /// backup homeworlds (if any) take over via the usual control rules.
  void destroy() {
    isDestroyed = true;
    isHomeworld = false;
    homeworldOf = null;
    isBackupHomeworld = false;
    owner = null;
    population = 0;
    // A shipment in transit dies with the world. Leaving it queued would let a
    // destroyed world still be owed colonists, and the arrival path would put
    // them into a population this method just zeroed.
    colonistsInTransit = 0;
    colonistTransitTicks = 0;
    // Orders die with the world. Leaving them queued would let a destroyed world
    // still be owed a delivery, and the arrival path would deposit into a store
    // this method just zeroed.
    tradeJobs.clear();
    // So does the freight history: a vaporised world has no shipments left to
    // have delivered or lost, and a report reading "Pirates destroyed the
    // freighter" for a world that no longer exists is a ghost entry.
    tradeIncidents.clear();
    // And its order history: a vaporised world has no commerce to report, and
    // a ledger naming ports and earnings on a world that no longer exists is
    // the same ghost entry one layer up.
    tradeOrders.clear();
    // The treasury goes with the world. A destroyed colony's earnings are not
    // something the player can still withdraw, and leaving them would let a
    // detonated world keep paying out.
    accumulatedRevenue = 0;
    colonistsMinerals = 0;
    colonistsOrganics = 0;
    colonistsIndustrial = 0;
    colonistsDrones = 0;
    storedMinerals = 0;
    storedOrganics = 0;
    storedIndustrial = 0;
    storedDrones = 0;
    defenseLevel = 0;
    shield = 0;
    maxShield = 0;
    hull = 0;
    maxHull = 0;
    // Review batch 2: stale timers on a corpse invite any future reader
    // that forgets the isDestroyed check to schedule ghosts.
    productionTimer = 0;
    spawnInterval = 0;
    // Same reasoning for a build: a corpse with a running construction timer
    // would quietly finish an upgrade the tick then granted to a dead world.
    constructionTicksRemaining = 0;
    constructionTarget = 0;
  }

  String get dominantCommodity {
    final mults = typeMultipliers[planetType];
    if (mults == null) return 'minerals';
    if (mults.minerals >= mults.organics &&
        mults.minerals >= mults.industrial) {
      return 'minerals';
    }
    if (mults.organics >= mults.minerals &&
        mults.organics >= mults.industrial) {
      return 'organics';
    }
    return 'industrial';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'planetType': planetType,
      'atmosphere': atmosphere,
      'owner': owner?.name,
      'isHomeworld': isHomeworld,
      'homeworldOf': homeworldOf?.name,
      'population': population,
      // Only written when non-empty, so a world with no orders adds nothing to a
      // file that is already ~59MB at 20,000 sectors.
      if (accumulatedRevenue != 0) 'accumulatedRevenue': accumulatedRevenue,
      if (tradeJobs.isNotEmpty)
        'tradeJobs': tradeJobs.map((j) => j.toJson()).toList(growable: false),
      if (tradeIncidents.isNotEmpty)
        'tradeIncidents':
            tradeIncidents.map((i) => i.toJson()).toList(growable: false),
      if (tradeOrders.isNotEmpty)
        'tradeOrders':
            tradeOrders.map((o) => o.toJson()).toList(growable: false),
      'colonistsInTransit': colonistsInTransit,
      'colonistTransitTicks': colonistTransitTicks,
      'colonistsMinerals': colonistsMinerals,
      'colonistsOrganics': colonistsOrganics,
      'colonistsIndustrial': colonistsIndustrial,
      'colonistsDrones': colonistsDrones,
      'productionEfficiency': productionEfficiency,
      // Rounded to 6dp: a raw double in [0,1) is ~17 characters of float noise
      // per track per save and drifts as it is recomputed, while 6dp bounds the
      // loss at 5e-7 units against a 1-unit quantum. Omitted when empty, so the
      // overwhelming majority of worlds pay nothing for it.
      'productionRemainder': productionRemainder.isEmpty
          ? null
          : productionRemainder
              .map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(6)))),
      'storedMinerals': storedMinerals,
      'storedOrganics': storedOrganics,
      'storedIndustrial': storedIndustrial,
      'storedDrones': storedDrones,
      'pendingMinerals': pendingMinerals,
      'pendingOrganics': pendingOrganics,
      'pendingIndustrial': pendingIndustrial,
      'pendingDrones': pendingDrones,
      'level': level,
      'constructionTicksRemaining': constructionTicksRemaining,
      'supplyTimer': supplyTimer,
      'constructionTarget': constructionTarget,
      'requiredMinerals': requiredMinerals,
      'requiredOrganics': requiredOrganics,
      'requiredIndustrial': requiredIndustrial,
      'requiredColonists': requiredColonists,
      'defenseLevel': defenseLevel,
      'shield': shield,
      'maxShield': maxShield,
      'hull': hull,
      'maxHull': maxHull,
      'productionTimer': productionTimer,
      'spawnInterval': spawnInterval,
      'isBackupHomeworld': isBackupHomeworld,
      'isDestroyed': isDestroyed,
      'imagePath': imagePath,
      'scanned': scanned,
      // Omitted when absent, matching the house style: a generated world
      // carrying `"creator": null` on every one of a thousand planets is noise
      // in a file the player never opens.
      if (creator != null) 'creator': creator,
      if (creatorFaction != null) 'creatorFaction': creatorFaction!.name,
    };
  }

  factory Planet.fromJson(Map<String, dynamic> json) {
    return Planet(
      name: json['name'] as String? ?? 'Unknown Planet',
      // A pre-id save gets a fresh identity. Defaulting to a shared placeholder
      // would make every legacy world in the galaxy compare equal, which is
      // exactly the bug the id exists to prevent.
      id: json['id'] as String? ?? const Uuid().v4(),
      planetType: json['planetType'] as String? ?? 'Terran',
      atmosphere: json['atmosphere'] as String? ?? 'Unknown',
      owner: _parseFactionClass(json['owner'] as String?),
      isHomeworld: json['isHomeworld'] as bool? ?? false,
      homeworldOf: _parseFactionClass(json['homeworldOf'] as String?),
      population: json['population'] as int? ?? 0,
      accumulatedRevenue: json['accumulatedRevenue'] as int? ?? 0,
      tradeJobs: (json['tradeJobs'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(TradeJob.fromJson)
          .toList(),
      // Absent in every pre-T7 save, and empty is the correct reading: there
      // is no history to invent, and a fabricated "delivered" entry would be a
      // trade the player never made.
      tradeIncidents: (json['tradeIncidents'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(TradeIncident.fromJson)
          .toList(),
      // Absent in every save predating finished-order history, and empty is
      // correct: nothing has finished yet under the new bookkeeping, and
      // inventing an order the player never placed is worse than an empty
      // ledger.
      tradeOrders: (json['tradeOrders'] as List?)
          ?.cast<Map<String, dynamic>>()
          .map(TradeOrderRecord.fromJson)
          .toList(),
      colonistsInTransit: json['colonistsInTransit'] as int? ?? 0,
      colonistTransitTicks: json['colonistTransitTicks'] as int? ?? 0,
      colonistsMinerals: json['colonistsMinerals'] as int? ?? 0,
      colonistsOrganics: json['colonistsOrganics'] as int? ?? 0,
      colonistsIndustrial: json['colonistsIndustrial'] as int? ?? 0,
      // Pre-rename migration: legacy 'colonistsFighters' seeds the drone
      // track, so existing saves keep their colony. Rewritten on next save.
      colonistsDrones:
          (json['colonistsDrones'] ?? json['colonistsFighters']) as int? ?? 0,
      productionEfficiency:
          (json['productionEfficiency'] as num?)?.toDouble() ?? 1.0,
      // Absent in every pre-fix save, and an empty map is the correct reading:
      // the colony simply starts accruing from zero, which costs it at most one
      // tick's fraction. Inventing a value here would be worse — a remainder
      // restored from nothing is a colony that skips a tick of work it did not do.
      productionRemainder: (json['productionRemainder'] as Map?)?.map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
      storedMinerals: json['storedMinerals'] as int? ?? 0,
      storedOrganics: json['storedOrganics'] as int? ?? 0,
      storedIndustrial: json['storedIndustrial'] as int? ?? 0,
      storedDrones:
          (json['storedDrones'] ?? json['storedFighters']) as int? ?? 0,
      pendingMinerals: json['pendingMinerals'] as int? ?? 0,
      pendingOrganics: json['pendingOrganics'] as int? ?? 0,
      pendingIndustrial: json['pendingIndustrial'] as int? ?? 0,
      pendingDrones: json['pendingDrones'] as int? ?? 0,
      level: json['level'] as int? ?? 1,
      constructionTicksRemaining:
          json['constructionTicksRemaining'] as int? ?? 0,
      supplyTimer: json['supplyTimer'] as int? ?? 0,
      constructionTarget: json['constructionTarget'] as int? ?? 0,
      requiredMinerals: json['requiredMinerals'] as int? ?? 500,
      requiredOrganics: json['requiredOrganics'] as int? ?? 300,
      requiredIndustrial: json['requiredIndustrial'] as int? ?? 200,
      // Matches the constructor (1000) and `levelUpCosts.first.requiredColonists`
      // (1000). This used to default to 100 here and 1000 in the constructor, so
      // the same missing key produced a different planet depending on how it was
      // built. Nothing reads the field today — all gating goes through the static
      // cost table — which is exactly why the drift went unnoticed.
      requiredColonists: json['requiredColonists'] as int? ?? 1000,
      defenseLevel: json['defenseLevel'] as int? ?? 0,
      shield: (json['shield'] as num?)?.toDouble() ?? 0,
      maxShield: (json['maxShield'] as num?)?.toDouble() ?? 0,
      hull: (json['hull'] as num?)?.toDouble() ?? 1000,
      maxHull: (json['maxHull'] as num?)?.toDouble() ?? 1000,
      productionTimer: json['productionTimer'] as int? ?? 0,
      spawnInterval: json['spawnInterval'] as int? ?? 10,
      isBackupHomeworld: json['isBackupHomeworld'] as bool? ?? false,
      isDestroyed: json['isDestroyed'] as bool? ?? false,
      imagePath: json['imagePath'] as String?,
      scanned: json['scanned'] as bool? ?? false,
      // Absent on every pre-existing save, and absent is the correct reading:
      // those worlds were placed by the generator, so nobody made them.
      creator: json['creator'] as String?,
      // Absent on every pre-existing save, which is correct: those worlds were
      // generator-placed or predate the field, and inventing a maker's faction
      // would be worse than having none.
      creatorFaction: _parseFactionClass(json['creatorFaction'] as String?),
    );
  }

  // ---------------------------------------------------------------------------
  // Colonist & level-up configuration
  // ---------------------------------------------------------------------------

  /// Maximum colonists by planet type (doubled from base values).
  static const Map<String, int> colonistMaxByType = {
    'Terran': 2000000,
    'Jungle': 1500000,
    'Ocean': 1000000,
    'Desert': 600000,
    'Ice': 400000,
    'Lava': 200000,
    'Moon': 200000,
    'Mountain': 400000,
    'Barren': 150000,
    'Toxic': 100000,
  };

  /// Resource & colonist gate for each level-up (index 0 = 1→2, …, 4 = 5→6).
  /// Colonists are a minimum requirement (not consumed); resources are consumed.
  ///
  /// **Re-derived.** The previous table was priced when colonists were a flat 20
  /// credits, which made a full 1→6 cost ~36.8M. Colonists are now priced by
  /// distance from the faction's homeworld at 15 x hops^1.5, so the same gates
  /// cost 28.7M at one hop, ~198M at the median four, and ~551M at eight. The
  /// last two steps were 94% of the total and read as a wall rather than a
  /// difficulty setting, and the resource half had stopped mattering — 3.65M of
  /// resources against 120M of colonists.
  ///
  /// The colonist requirements are cut so the arc is roughly 2, 12, 60 and 250
  /// times cheaper, landing a full 1→6 at ~4.9M / ~33M / ~92M by distance.
  /// Resources are kept in the same proportion to each other so the import
  /// decision still bites: a big colony genuinely needs organics shipped to it,
  /// because its own upkeep is proportional to population.
  static const List<LevelUpCost> levelUpCosts = [
    LevelUpCost(250, 250, 150, 100), // 1→2
    LevelUpCost(1000, 1000, 600, 400), // 2→3
    LevelUpCost(4000, 4000, 2500, 1500), // 3→4
    LevelUpCost(15000, 20000, 12000, 7000), // 4→5
    LevelUpCost(50000, 80000, 50000, 30000), // 5→6
  ];

  /// Ticks to complete a build from each level, at time scale 1.
  ///
  /// Sized for a single-player game rather than the classic 34-52 *days*: at the
  /// 30s game tick these run 7.5 minutes to 80 minutes, so a full 1→6 is about
  /// four hours of **actual play**, and nothing at all while the game is closed.
  /// That is the point — see [constructionTicksRemaining].
  static const Map<int, int> levelConstructionTicks = {
    1: 15, // 1→2   7.5 min
    2: 30, // 2→3  15 min
    3: 60, // 3→4  30 min
    4: 120, // 4→5   1 hr
    5: 160, // 5→6  80 min
  };

  /// Defence level conferred by reaching each tier.
  ///
  /// This is what a Citadel is *for*. Previously defence was set once at
  /// generation and never changed, so every tier defended identically and the
  /// six levels bought nothing but a slightly better yield multiplier.
  static const Map<int, int> levelDefense = {
    1: 0,
    2: 1,
    3: 2,
    4: 3,
    5: 4,
    6: 4,
  };

  /// Shield rating conferred by reaching each tier.
  static const Map<int, int> levelShield = {
    1: 0,
    2: 2000,
    3: 5000,
    4: 8000,
    5: 14000,
    6: 22000,
  };

  /// Hull (armour) rating conferred by reaching each tier.
  static const Map<int, int> levelArmour = {
    1: 1000,
    2: 4000,
    3: 10000,
    4: 20000,
    5: 40000,
    6: 70000,
  };

  /// How much larger a developed world's population ceiling is.
  ///
  /// The cap used to be a flat per-type number while the level gate demanded up
  /// to a million colonists, so **7 of the 10 planet types could never reach
  /// Citadel** and every Duran homeworld was capped below the 4→5 gate. The two
  /// numbers were mutually unsatisfiable.
  ///
  /// Deriving the cap from the level is the same fix as the storage floor: a
  /// single fixed number cannot serve both a small and a very large colony, so
  /// the gate grows with the colony and can never contradict the cap printed
  /// beside it. Every type can now reach every tier.
  static const Map<int, double> levelColonistScale = {
    1: 1.00,
    2: 1.60,
    3: 2.80,
    4: 5.00,
    5: 8.00,
    6: 12.00,
  };

  static const List<String> levelTitles = [
    'Outpost',
    'Settlement',
    'Colony',
    'Fortified Colony',
    'Planetary Base',
    'Citadel',
  ];

  /// Population ceiling: the type's figure, scaled by how developed the world
  /// is. See [levelColonistScale] for why this is not a flat number.
  int get colonistMax {
    final base = colonistMaxByType[planetType] ?? 100000;
    final scale =
        levelColonistScale[level.clamp(1, levelColonistScale.length)] ?? 1.0;
    return (base * scale).round();
  }

  /// The type's base cap before development, for display and tests.
  int get baseColonistMax => colonistMaxByType[planetType] ?? 100000;
  LevelUpCost? get levelUpCost => level < 6 ? levelUpCosts[level - 1] : null;

  // ---------------------------------------------------------------------------
  // Production
  //
  // This is the single source of truth for the production formula. It used to
  // live inline in the planet screen, written out four times, which meant the
  // number on screen and the number a tick applied could not be checked against
  // each other — and neither existed. `PlanetProductionService` calls
  // [produce]; the screen calls the [mineralOutput]-style getters. Same code.
  // ---------------------------------------------------------------------------

  // ---------------------------------------------------------------------------

  /// Ticks a purchased colonist shipment spends in transit: **two**.
  ///
  /// At one tick per 30 seconds that is one real minute, which is long enough
  /// that the departure is a thing the player watches rather than a number that
  /// changes under the cursor, and short enough that nobody comes back later
  /// wondering whether the purchase went through. The point of the delay is that
  /// a purchase reads as a shipment — buying 2,000 people is not an instant edit
  /// to a population figure — not that it is a logistical puzzle.
  ///
  /// Named for the *delay* so it cannot collide with the per-shipment countdown
  /// it initialises, which is a different number on every world.
  static const int colonistTransitDelayTicks = 2;

  /// Queues a purchased shipment and starts its countdown.
  ///
  /// Clamped to the room actually left on the world **including what is already
  /// on its way**, because two shipments in flight can each have been affordable
  /// when ordered and together overrun the cap. Returns the headcount actually
  /// sent, so the caller charges for that and not for what was asked for — a
  /// clamp here and a price computed on the request is a silent overcharge.
  int dispatchColonists(int headcount) {
    final room = colonistMax - population - colonistsInTransit;
    final sending = headcount < room ? headcount : room;
    if (sending <= 0) return 0;

    colonistsInTransit += sending;
    // Restarted rather than added, so a second purchase made while the first is
    // still in the air ships with the first instead of queueing behind it. Two
    // shipments, one flight.
    colonistTransitTicks = colonistTransitDelayTicks;
    return sending;
  }

  /// True while a purchased shipment is on its way.
  bool get hasColonistsInTransit => colonistsInTransit > 0;

  /// Total ticks this shipment was given, for the progress bar's denominator.
  ///
  /// [colonistTransitDelayTicks] rather than a stored total, because a second
  /// order **restarts** the countdown rather than queueing behind the first
  /// (see [dispatchColonists]) — so the total is always the delay, and storing
  /// it would be a second copy of a constant that could drift from it.
  int get colonistTransitTotalTicks =>
      hasColonistsInTransit ? colonistTransitDelayTicks : 0;

  /// 0.0 to 1.0 through the current shipment, for a determinate progress bar.
  ///
  /// Deliberately the same shape as [constructionProgress] so the two read the
  /// same way on screen: a purchase and a build are both "work already paid for
  /// that advances one step per tick", and a player who has watched one should
  /// not have to learn a second idiom for the other.
  double get colonistTransitProgress {
    if (!hasColonistsInTransit) return 0;
    final total = colonistTransitTotalTicks;
    if (total <= 0) return 1;
    return (1 - (colonistTransitTicks / total)).clamp(0.0, 1.0);
  }

  /// Advances an in-transit shipment by one tick, landing it when it arrives.
  ///
  /// Returns the headcount that landed, so a caller can tell an arrival from a
  /// tick that merely counted down. Called by `PlanetProductionService`, which
  /// runs it **before** the `population <= 0` skip — a world with no colonists
  /// yet is exactly the world a first shipment is going to, so putting this
  /// behind that check would strand it forever.
  int advanceColonistTransit() {
    if (colonistsInTransit <= 0) return 0;

    // `colonistTransitTicks <= 0` with colonists still aboard is a state the
    // rules never produce, so it lands them rather than returning 0. The
    // alternative — trusting the invariant — strands a paid-for shipment
    // forever on any save that caught the pair inconsistent, which is precisely
    // the "I paid and nothing happened" failure the transit row exists to end.
    if (colonistTransitTicks > 0) {
      colonistTransitTicks--;
      if (colonistTransitTicks > 0) return 0;
    }

    final room = colonistMax - population;
    final landed = colonistsInTransit < room ? colonistsInTransit : room;
    colonistsInTransit = 0;
    population += landed;
    return landed;
  }

  // ---------------------------------------------------------------------------

  /// Ticks between colony-supply draws: **one game day**.
  ///
  /// Was 10 ticks, chosen when the bill was a share of a single tick's output.
  /// That only ever worked because the per-tick figures were ~29x the class
  /// caps; once production came down to the caps, 288 draws a day of an eighth of
  /// each tick's output demanded 23x what a colony earned in a day. The cadence
  /// and the share have to be quoted in the same unit, and a game day is the
  /// unit the share is now expressed in.
  ///
  /// A bill rather than a per-tick tax either way: the colony breathes between
  /// draws instead of having a slice shaved off its output thirty times a minute.
  static const int supplyInterval = PlanetClock.ticksPerDay;

  /// Share of one **day's** own output that a supply draw consumes.
  ///
  /// Expressed against the colony's **own production**, never as a per-capita
  /// figure, and that is the whole point. A fixed per-colonist rate is either
  /// trivial for a world of a hundred or ruinous for a world of two million —
  /// the same trap as the storage floor and the level-scaled colonist cap, met
  /// for the third time in this model. Deriving it from output holds the burden
  /// at the same *relative* size at every scale.
  static const double supplyShareOfOutput = 0.08;

  /// Fallback divisor when a colony's own output is zero, so a world with every
  /// track empty has a finite, tiny bill rather than dividing by zero.
  static const int supplyFallbackPerPop = 10;

  /// Units of a commodity one colonist produces per tick, before type, world
  /// efficiency and level bonuses.
  ///
  /// This is a pure **scale** factor and it is the one number that makes the
  /// storage numbers mean anything. At 1.0 per colonist per tick a full Terran
  /// colony turned out 1,600,000 minerals a tick against a 200,000 store — it
  /// filled the store in 0.6 ticks and then overflowed the rest for the other
  /// 99.4% of the time. No storage cap, and no shipment pool on top of it, can
  /// make sense against an output that large.
  ///
  /// At 0.01 a mid-sized colony turns out a few hundred units a tick, and
  /// [minimumTicksOfOutput] guarantees its store is always sized to hold at
  /// least that much — so a colony can never out-produce its own infrastructure
  /// no matter how large it grows. The shipment pool then holds days rather
  /// than hours —
  /// which is the shape the classic game had, where a world quietly produced its
  /// daily output and you collected it in batches, and where ignoring a planet
  /// too long genuinely cost you the goods.
  ///
  /// The colony supply draw is scaled by this constant too, so supply and output
  /// move together and the burden stays a fixed share of what the colony makes
  /// at every scale.
  static const double baseOutputPerColonist = 0.01;

  /// Development multiplier by level — how much a colony's *workforce* is worth
  /// per colonist.
  ///
  /// Deliberately shallow. A steeper curve compounds with the type multiplier
  /// and the colonist caps into a ~110x spread between the best and worst
  /// possible colony, which erases planet identity: everything worth having
  /// would end up on one planet type. Level is instead meant to buy **capacity
  /// and defence**, which scale hard — and both now do: `levelStorageScale`
  /// grows storage 200x across the six tiers, and a completed build applies
  /// `levelDefense` / `levelShield` / `levelArmour`. (This comment used to say
  /// they "are currently set once at generation and do not move with level,
  /// which is the next piece of work (planets.md, phase F)" — that work landed;
  /// phase F is done.) Extraction per colonist stays
  /// close to flat so an Ocean world remains the best food producer and a Lava
  /// world the best mineral source no matter how developed either gets.
  static const Map<int, double> levelDevelopment = {
    1: 1.00,
    2: 1.15,
    3: 1.30,
    4: 1.50,
    5: 1.70,
    6: 2.00,
  };

  double get developmentMultiplier =>
      levelDevelopment[level.clamp(1, levelDevelopment.length)] ?? 1.0;

  /// How well this colony exploits its world, applied on top of the class caps.
  ///
  /// A multiplier on a **capped** figure, not a multiplier on the colonists. The
  /// old formula scaled the workforce directly, so `productionEfficiency` could
  /// lift a colony past the peak that the cap exists to enforce — the two rules
  /// contradicted each other. Applied to the output instead, efficiency can make
  /// a colony approach its cap faster but never exceed it.
  double get yieldScale => productionEfficiency * developmentMultiplier;

  /// Per-day output for one track, with the colony's own yield applied.
  ///
  /// This is the figure to display, to log and to compare against a cap: it is
  /// what the colony actually yields, bounded by what the world can possibly do.
  int outputPerDayFor(String track) {
    final base = baseOutputPerDayFor(track);
    if (base <= 0) return 0;
    // Clamped to the class ceiling. The comment above promises this and the
    // first implementation did not do it: efficiency scaled a figure that was
    // already the peak, so a colony with 2.0 efficiency produced twice the
    // maximum the cap exists to enforce. Two rules that contradict is exactly
    // what the cap was introduced to stop.
    final scaled = (base * yieldScale).round();
    final ceiling = maxDailyOutputFor(track);
    return scaled > ceiling ? ceiling : scaled;
  }

  /// Per-tick output for one track. A double, because the triangle's figures are
  /// small once divided by the 2,880 ticks in a day, and truncating each tick
  /// would throw most of it away.
  double perTickFor(String track) =>
      PlanetClock.perDayToPerTick(outputPerDayFor(track).toDouble());

  /// This world's production and lore class.
  ///
  /// Resolved through [PlanetClassTuning], so a value edited in Settings wins
  /// over the shipped default. The *rule* never comes from there — only the
  /// numbers do — which is why editing a ratio cannot produce a world whose
  /// behaviour no longer matches the guide.
  PlanetClassSpec get classSpec => PlanetClassTuning.specFor(planetType);

  /// The **raw triangle** for one track: peak at half the maximum, falling to
  /// zero at the maximum, before this colony's own yield is applied.
  ///
  /// Named `base...` on purpose. It was called `outputPerDayFor`, which reads as
  /// "what this planet produces" and is not — it ignores efficiency and
  /// development, and it ignores the clamp. Callers almost always want the
  /// scaled figure, so the unscaled one is the one that should be harder to
  /// reach for. See [ProductSpec.outputPerDay].
  int baseOutputPerDayFor(String track) => switch (track) {
        'minerals' => classSpec.ore.outputPerDay(colonistsMinerals),
        'organics' => classSpec.organics.outputPerDay(colonistsOrganics),
        'industrial' => classSpec.equipment.outputPerDay(colonistsIndustrial),
        _ => 0,
      };

  /// Default ticks between ships from a major faction's homeworld.
  ///
  /// The generator sets this on each homeworld; named here so the Planet Guide
  /// quotes the model rather than a literal. It read `${10}` — an interpolation
  /// of a constant, which is a hand-typed number wearing a string's clothes.
  static const int defaultSpawnInterval = 10;

  /// Ticks between ships from a pirate outpost, which the generator sets
  /// separately from a faction capital's cadence.
  static const int pirateOutpostSpawnInterval = 12;

  /// The range [productionEfficiency] is rolled in when the galaxy is generated.
  ///
  /// Named rather than inline in the generator because the Planet Guide quotes
  /// the range, and a help screen quoting a number the model does not name is
  /// exactly how the supply bill came to be wrong by a factor of 2,880 — the
  /// text said "one tick's output" and nothing tied it to the code.
  static const double minEfficiency = 0.5;
  static const double maxEfficiency = 1.5;

  /// Fractional units produced so far and not yet delivered into storage, one
  /// slot per track.
  ///
  /// Per-**tick** output is a fraction of a unit — the triangle's per-day figures
  /// divided by the 2,880 ticks in a day — so a Volcanic ore track peaks at 17.36
  /// per tick and a Glacial organics track at 0.17. Rounding each tick would throw
  /// away most of what the colony makes; without this, **any track under 2,880
  /// units/day banks nothing at all, ever**, and the world looks broken rather
  /// than slow.
  ///
  /// **Persisted, and that is load-bearing rather than tidy.** The tick service
  /// re-parses the whole universe on every pass, so a remainder that lived only
  /// in memory arrived empty every tick and `_drawProduction` computed
  /// `floor(0 + perTick)` forever — 13 of 26 tracks banking literally nothing, and
  /// no colony able to bank the organics or industrial for even a 1→2 build.
  /// Every production test held a single long-lived `Planet` across its ticks, so
  /// the suite was green throughout and could not see it by construction.
  final Map<String, double> productionRemainder;

  /// Units of one track produced this tick, carrying the remainder forward.
  ///
  /// The single place production is turned into whole units, so the tick and the
  /// screen cannot disagree about it.
  int _drawProduction(String track) {
    final exact = perTickFor(track);
    if (exact <= 0) {
      productionRemainder[track] = 0;
      return 0;
    }
    final carried = (productionRemainder[track] ?? 0) + exact;
    final whole = carried.floor();
    productionRemainder[track] = carried - whole;
    return whole;
  }

  int get mineralOutput => _drawProduction('minerals');
  int get organicOutput => _drawProduction('organics');
  int get industrialOutput => _drawProduction('industrial');

  /// Drones per tick.
  ///
  /// **Derived, not staffed.** There is no drone track and no drone stepper:
  /// drones come from what the other three tracks actually produce, which is why
  /// the fighter ceiling falls out of the production caps instead of being a
  /// separate number someone has to keep in balance with them. See
  /// [PlanetClassSpec.droneOutputPerDay].
  int get droneOutput {
    final perDay = classSpec.droneOutputPerDay(
      orePerDay: outputPerDayFor('minerals'),
      organicsPerDay: outputPerDayFor('organics'),
      equipmentPerDay: outputPerDayFor('industrial'),
    );
    if (perDay <= 0) return 0;
    final carried = (productionRemainder['drones'] ?? 0) +
        PlanetClock.perDayToPerTick(perDay.toDouble());
    final whole = carried.floor();
    productionRemainder['drones'] = carried - whole;
    return whole;
  }

  /// Output for a named track, before any storage limit is applied.
  ///
  /// **These getters advance the production remainder.** That is not a side
  /// effect to be tidied away: it is what makes them a faithful preview of what
  /// the next tick will bank. Reading one is therefore not free, and a caller
  /// that only wants a *display* figure should use [outputPerDayFor], which does
  /// not consume anything.
  int outputFor(String commodity) => switch (commodity) {
        'minerals' => mineralOutput,
        'organics' => organicOutput,
        'industrial' => industrialOutput,
        'drones' => droneOutput,
        _ => 0,
      };

  /// What a track would produce in a whole day at its current staffing.
  ///
  /// The honest figure to show a player, and the one the "per tick" column
  /// divides: it is what a well-run world actually yields, and it does not
  /// change between ticks just because a fractional remainder completed.
  int dailyOutputFor(String track) => outputPerDayFor(track);

  /// The most of a track this world can produce in a day, at its optimum.
  ///
  /// This is the **class** ceiling: the published TradeWars figure for the
  /// type. It is not what this colony produces — see
  /// [achievableMaxPerDayFor] for that, which is the number a player should
  /// ever be shown.
  int maxDailyOutputFor(String track) =>
      classSpec.productFor(track).maxOutputPerDay;

  /// The most per day **this colony** can produce on [track], which is what
  /// the screen must label "max".
  ///
  /// [maxDailyOutputFor] with the colony's own [yieldScale] applied. The two
  /// are the same number only for a colony whose yield reaches 1.0, and the
  /// gap is not a rounding detail: `productionEfficiency` is rolled in
  /// [0.5, 1.5) at generation and `developmentMultiplier` is **1.00 at level
  /// 1**, so a level-1 world with a below-average roll has a yield of about
  /// 0.5 and the class figure is roughly **double** what that colony can ever
  /// produce, at any staffing level.
  ///
  /// Labelling that unreachable number "max" was worse than showing no ceiling
  /// at all. The track row puts "of {optimum}" under the count and "/ max N"
  /// beside a per-day figure, so at correct staffing the row said *correctly
  /// staffed* and *you are N short of max* at the same time — and the only way
  /// to close that gap is to add colonists past the optimum, which is the one
  /// move the triangle punishes. The display was steering the player into the
  /// trap. With this, "at the optimum" and "at max" are the same statement,
  /// which is what the shape of the curve already said.
  ///
  /// Clamped to the class ceiling for the same reason [outputPerDayFor] is: a
  /// high-yield colony approaches the cap faster but never exceeds it.
  int achievableMaxPerDayFor(String track) {
    final ceiling = maxDailyOutputFor(track);
    if (ceiling <= 0) return 0;
    final scaled = (ceiling * yieldScale).round();
    return scaled > ceiling ? ceiling : scaled;
  }

  /// The most drones per day this world can produce.
  ///
  /// The **class** figure, pinned to the published TradeWars value — see
  /// [achievableMaxDroneOutputPerDay] for this colony's own reach.
  int get maxDroneOutputPerDay => classSpec.maxDroneOutputPerDay;

  /// The most drones per day **this colony** can produce: its three tracks'
  /// achievable maxima, on the same derivation as the class figure.
  ///
  /// Drones are derived from output, so an aggregate of three *unreachable*
  /// ceilings is unreachable three times over. Built from
  /// [achievableMaxPerDayFor] so the number the player is shown is one they
  /// could actually hit by staffing all three tracks to their optima.
  int get achievableMaxDroneOutputPerDay => classSpec.droneOutputPerDay(
        orePerDay: achievableMaxPerDayFor('minerals'),
        organicsPerDay: achievableMaxPerDayFor('organics'),
        equipmentPerDay: achievableMaxPerDayFor('industrial'),
      );

  /// Moves the shipment pool into the working stores, bounded by room.
  ///
  /// The pool is overflow, not a sale: sweeping is free and priceless, which
  /// is what retires the last invented price on the planet screen (T6 — the
  /// flat per-unit payout table is deleted, not retuned, exactly like
  /// `_transferPrices` before it). Anything that does not fit stays pooled.
  /// Drones sweep like everything else: they are fielded from the store.
  ///
  /// Returns what moved per commodity.
  Map<String, int> sweepShipmentPool() {
    const commodities = ['minerals', 'organics', 'industrial', 'drones'];
    final moved = <String, int>{};
    for (final c in commodities) {
      final pending = pendingFor(c);
      if (pending <= 0) continue;
      final room = capFor(c) - storedFor(c);
      final take = pending < room ? pending : room;
      if (take <= 0) continue;
      _setStored(c, storedFor(c) + take);
      _setPending(c, pending - take);
      moved[c] = take;
    }
    return moved;
  }

  /// Puts one tick of a commodity somewhere useful.
  ///
  /// Working store fills first, then the surplus spills into the shipment pool
  /// rather than being discarded. The only genuine loss is a shipment pool that
  /// has itself been allowed to fill, which is reported so the tick can say so
  /// — that is a world left completely ignored, not normal operation.
  ///
  /// Returns what actually landed, and whether anything was lost.
  ({int stored, int spilled, int lost}) deposit(String commodity, int amount) {
    if (amount <= 0) return (stored: 0, spilled: 0, lost: 0);

    final cap = capFor(commodity);
    final current = storedFor(commodity);
    // An existing save can hold more than the new cap allows. Clamping the
    // store downward would destroy a player's goods, so the store is simply not
    // topped up and the surplus goes to pending instead.
    final room = cap - current;
    final intoStore = room <= 0 ? 0 : (amount < room ? amount : room);
    _setStored(commodity, current + intoStore);

    final overflow = amount - intoStore;
    if (overflow <= 0) return (stored: intoStore, spilled: 0, lost: 0);

    final pendingCap = capFor(commodity) * pendingCapMultiple;
    final currentPending = pendingFor(commodity);
    final roomPending = pendingCap - currentPending;
    final intoPending = roomPending <= 0
        ? 0
        : (overflow < roomPending ? overflow : roomPending);
    _setPending(commodity, currentPending + intoPending);

    return (
      stored: intoStore,
      spilled: intoPending,
      lost: overflow - intoPending,
    );
  }

  // ---------------------------------------------------------------------------
  // Storage
  //
  // Per commodity, and derived from planet type + level rather than stored.
  //
  // It was a single `maxStorage` shared by everything, which produced two
  // separate problems. It was far too small for the output a colony actually
  // makes (see [pendingMinerals]), and it was also *displayed* as a single
  // cap against a sum of three stores, so a perfectly legal planet read as
  // overfull — "10.7K / 5.0K" — purely because of how the row was written.
  //
  // The caps follow the classic game's shape: storage is a property of the
  // world and what it produces, so a Volcanic world is vast for minerals and
  // almost useless for organics, an Oceanic world is the reverse, and a
  // Glacial world, and the source table's Class U, are cramped across the
  // board. A colony therefore needs a reason to exist per commodity, not just
  // a reason to exist.
  //
  // The Class U reference is a citation of the source table's shape, not a type
  // a player can encounter: its ratios are N-A on every product, so the world it
  // described produced nothing at all, and it was removed rather than left as a
  // dead end (see `planet_classes.dart`).
  // ---------------------------------------------------------------------------

  /// Working store per commodity at level 1: minerals, organics, industrial.
  ///
  /// Modelled on the classic game's per-product limits, which are wildly
  /// differentiated (Volcanic 1,000,000 ore / 10,000 organics; Oceanic
  /// 1,000,000 organics / 50,000 equipment; source Class U 10,000 of
  /// everything).
  /// Drones are not a classic product, so they are derived from the mineral
  /// store rather than given a hand-picked row.
  static const Map<String, List<int>> baseStorageByType = {
    'Terran': [100000, 100000, 100000],
    'Jungle': [80000, 600000, 60000],
    'Desert': [200000, 50000, 10000],
    'Ocean': [100000, 1000000, 50000],
    'Ice': [20000, 50000, 10000],
    'Lava': [1000000, 10000, 100000],
    'Moon': [30000, 15000, 25000],
    'Mountain': [200000, 200000, 100000],
    'Barren': [250000, 12000, 40000],
    'Toxic': [300000, 10000, 60000],
  };

  /// Storage growth by Citadel level. This is the storage half of what levelling
  /// is supposed to buy — the other half is development, and defence is still
  /// outstanding.
  static const Map<int, double> levelStorageScale = {
    1: 1.00,
    2: 1.40,
    3: 2.00,
    4: 3.00,
    5: 4.50,
    6: 6.50,
  };

  /// How much overflow the shipment pool holds, as a multiple of the working
  /// store. Generous on purpose: the pool exists so a colony keeps earning
  /// while you are elsewhere, so it should only ever fill on a world that has
  /// been completely ignored for a very long time.
  static const int pendingCapMultiple = 250;

  /// A store always holds at least this many ticks of its own output.
  ///
  /// This is what makes "no waste" structural rather than a matter of picking
  /// good numbers. A fixed per-type cap cannot serve a colony of a hundred and a
  /// colony of two million — the latter out-produced any fixed cap within
  /// seconds, and every scale constant I chose to paper over that just moved
  /// the problem. So the cap is `max(typeCap, outputPerTick x this)`.
  ///
  /// A small colony therefore keeps its type's character (an Ocean world really
  /// does hold a great deal of organics), and a very large one is automatically
  /// given infrastructure proportionate to what it is producing. Losing goods
  /// now requires ignoring a world for days, which is the intent.
  static const int minimumTicksOfOutput = 120;

  List<int> get _baseStorage {
    final row = baseStorageByType[planetType];
    if (row != null) return row;
    // Unknown type: a modest flat default rather than a crash.
    return const [50000, 50000, 50000];
  }

  double get storageScale =>
      levelStorageScale[level.clamp(1, levelStorageScale.length)] ?? 1.0;

  /// The working store for a commodity: the type's own figure, scaled by level,
  /// but never smaller than [minimumTicksOfOutput] of what the colony currently
  /// makes. See [minimumTicksOfOutput] for why the second half is not optional.
  /// The working store for a commodity: the type's figure scaled by level, or
  /// [minimumTicksOfOutput] of what the colony currently makes — whichever is
  /// larger.
  ///
  /// **Uses [perTickFor], not [outputFor].** `outputFor` routes through
  /// `_drawProduction`, which advances and floors the production remainder, so
  /// reading it *consumes* production. This getter sits on the `deposit` path,
  /// which put it inside every tick's write:
  ///
  /// ```
  /// deposit('minerals', mineralOutput);   // draw 1, kept
  ///   -> capFor('minerals') -> maxMinerals -> _cap -> outputFor  // draw 2, discarded
  /// deposit('drones', droneOutput);
  ///   -> capFor('drones') -> maxDrones -> maxMinerals -> _cap -> outputFor  // draw 3
  /// ```
  ///
  /// Minerals were drawn three times a tick, organics and industrial twice, and
  /// every discarded draw still floored whole units out of the accumulator — so a
  /// track yielding 1.7/tick banked 1 and threw 3 away. Worse, `maxMinerals` is
  /// an ordinary-looking read-only getter that the colony card's storage bar
  /// calls, so *looking* at a colony drained it, with no bound.
  ///
  /// `perTickFor` is the same number with no side effect. See
  /// `test/planet_production_test.dart` for the guard.
  int _cap(int baseIndex, String commodity) {
    final byType = (_baseStorage[baseIndex] * storageScale).round();
    final byOutput = (perTickFor(commodity) * minimumTicksOfOutput).round();
    return byOutput > byType ? byOutput : byType;
  }

  int get maxMinerals => _cap(0, 'minerals');
  int get maxOrganics => _cap(1, 'organics');
  int get maxIndustrial => _cap(2, 'industrial');

  /// Drones are a defence product, so their store tracks the mineral store
  /// rather than getting an invented row that could drift away from it.
  int get maxDrones => (maxMinerals * 0.25).round();

  int get pendingCapMinerals => maxMinerals * pendingCapMultiple;
  int get pendingCapOrganics => maxOrganics * pendingCapMultiple;
  int get pendingCapIndustrial => maxIndustrial * pendingCapMultiple;
  int get pendingCapDrones => maxDrones * pendingCapMultiple;

  int get pendingTotal =>
      pendingMinerals + pendingOrganics + pendingIndustrial + pendingDrones;

  /// Working store for a named commodity.
  int capFor(String commodity) => switch (commodity) {
        'minerals' => maxMinerals,
        'organics' => maxOrganics,
        'industrial' => maxIndustrial,
        'drones' => maxDrones,
        _ => 0,
      };

  int storedFor(String commodity) => switch (commodity) {
        'minerals' => storedMinerals,
        'organics' => storedOrganics,
        'industrial' => storedIndustrial,
        'drones' => storedDrones,
        _ => 0,
      };

  /// Removes up to [amount] of [commodity] from the **working store** and returns
  /// what was actually taken.
  ///
  /// The public counterpart to [_setStored], which is private. A caller outside
  /// this file that needs to move goods out of a store — a trade job committing
  /// its goods at order time — has to go through something, and the alternative
  /// is a public setter that can write any number, including a negative one.
  ///
  /// Clamped at what is there, and **deliberately does not touch the shipment
  /// pool.** The pool is output awaiting collection, not working stock; drawing a
  /// trade order from it would let a player sell goods the colony has not finished
  /// producing into a store. `_takeFrom` (used by the supply bill) does draw from
  /// both, and that difference is on purpose: the supply bill is a colony feeding
  /// itself, and this is a sale.
  int takeStored(String commodity, int amount) {
    if (amount <= 0) return 0;
    final have = storedFor(commodity);
    final taken = amount < have ? amount : have;
    if (taken <= 0) return 0;
    _setStored(commodity, have - taken);
    return taken;
  }

  /// Stored units **plus** the sub-unit production carried but not yet banked.
  ///
  /// **Read-only, and that is load-bearing.** The `mineralOutput`-style getters
  /// *consume* the remainder — `_drawProduction` moves it into storage as a side
  /// effect — so a screen that displayed one of those would bank production just
  /// by looking at the planet. This reads the same state without advancing it,
  /// which is the only reason it is allowed near a UI.
  ///
  /// It is also the number a player needs in order to see a slow track working.
  /// Per-tick output is a fraction of a unit: a Jungle minerals track staffed
  /// with 5,000 colonists yields **0.376 per tick**, so `storedMinerals` moves by
  /// 1 only every third tick and reads as dead in between. The carried fraction
  /// is what moves every tick, and showing it is the difference between "this
  /// colony is slow" and "this colony is broken".
  double storedPlusRemainder(String commodity) =>
      storedFor(commodity) + (productionRemainder[commodity] ?? 0);

  int pendingFor(String commodity) => switch (commodity) {
        'minerals' => pendingMinerals,
        'organics' => pendingOrganics,
        'industrial' => pendingIndustrial,
        'drones' => pendingDrones,
        _ => 0,
      };

  void _setStored(String commodity, int value) {
    // Clamped at zero: supply can ask for more than a store holds, and a
    // negative store would read as a nonsense figure on the colony card.
    value = value < 0 ? 0 : value;
    switch (commodity) {
      case 'minerals':
        storedMinerals = value;
      case 'organics':
        storedOrganics = value;
      case 'industrial':
        storedIndustrial = value;
      case 'drones':
        storedDrones = value;
    }
  }

  void _setPending(String commodity, int value) {
    value = value < 0 ? 0 : value;
    switch (commodity) {
      case 'minerals':
        pendingMinerals = value;
      case 'organics':
        pendingOrganics = value;
      case 'industrial':
        pendingIndustrial = value;
      case 'drones':
        pendingDrones = value;
    }
  }

  /// Colonists currently on a production track. Never exceeds [population].
  /// Colonists on the three staffed tracks. Excludes [colonistsDrones] on
  /// purpose — drones are derived, so that field is legacy and any colonists
  /// nominally on it are free. See the field's documentation.
  int get assignedColonists =>
      colonistsMinerals + colonistsOrganics + colonistsIndustrial;

  /// Colonists in the colony but not on a track. They still eat, and they are
  /// the pool a player draws from when re-assigning the workforce.
  ///
  /// Clamped at zero because [population] can fall below [assignedColonists]
  /// after a starvation tick, and the track counts are only rebalanced at the
  /// end of [produce]. Showing a negative reserve in that window would be
  /// nonsense; a negative *workforce* is fixed before anything reads it.
  int get reserveColonists =>
      (population - assignedColonists).clamp(0, population);

  /// Commodities a colony can be supplied from, in the order supply falls back
  /// through them.
  ///
  /// Drones are deliberately excluded: they are combat units, not a consumable,
  /// and a colony that "eats" its drone force is nonsense. The order is fixed
  /// rather than random so a shortfall drains predictably — the *choice* of
  /// commodity is the random part, and where the money comes from is not.
  static const List<String> supplyCommodities = [
    'minerals',
    'organics',
    'industrial',
  ];

  /// Whether this world can produce [commodity] at all.
  ///
  /// False for a harsh world's missing track, and the workforce UI locks its
  /// steppers on it. Assigning colonists to a track whose type multiplier is
  /// zero produces nothing forever, and a stepper that quietly accepts it looks
  /// like a bug rather than a dead end.
  bool canProduce(String commodity) {
    final m = typeMultipliers[planetType];
    if (m == null) return true;
    return switch (commodity) {
      'minerals' => m.minerals > 0,
      'organics' => m.organics > 0,
      'industrial' => m.industrial > 0,
      'drones' => m.drones > 0,
      _ => true,
    };
  }

  /// Units a supply draw takes right now.
  ///
  /// [supplyShareOfOutput] of one tick's total production, so the bill is the
  /// same relative size for a colony of a hundred and a colony of two million.
  /// Falls back to a per-capita figure when every track is empty, so a world
  /// with nobody working still has a finite bill instead of dividing by zero.
  int get supplyDraw {
    if (isDestroyed || population <= 0) return 0;
    // Of a **day's** output, not a tick's. The bill used to be a share of one
    // tick's production charged every 10 ticks, which under the old inflated
    // per-tick figures was merely generous; once production came down to the
    // class caps, 288 bills a day of an eighth of each tick's output came to
    // 23x the daily yield — a colony could never break even, let alone feed
    // itself. The share is of what a day actually produces.
    final perDay = outputPerDayFor('minerals') +
        outputPerDayFor('organics') +
        outputPerDayFor('industrial');
    if (perDay > 0) {
      return (perDay * supplyShareOfOutput).round().clamp(1, perDay);
    }
    return ((population / supplyFallbackPerPop) * baseOutputPerColonist)
        .ceil()
        .clamp(1, population);
  }

  /// True when every consumable store is empty, so a supply draw cannot be paid.
  ///
  /// Worth exposing rather than recomputing: the screen needs it to decide
  /// whether to warn, and the warning is only meaningful when the colony is
  /// actually drawing on nothing.
  bool get storesEmpty =>
      storedMinerals <= 0 &&
      storedOrganics <= 0 &&
      storedIndustrial <= 0 &&
      pendingMinerals <= 0 &&
      pendingOrganics <= 0 &&
      pendingIndustrial <= 0;

  /// Ticks until the next supply draw.
  int get ticksToSupply =>
      supplyInterval - supplyTimer.toInt().clamp(0, supplyInterval);

  /// Advances the colony by one tick: produces into storage, pays upkeep, and
  /// starves the population if it cannot feed itself.
  ///
  /// Order matters: production lands **before** upkeep is charged, so a colony
  /// that farms its own food stands still instead of spiralling. That is the
  /// equilibrium the upkeep rule is meant to produce.
  ///
  /// Mutates in place. Returns what happened, so the tick can log it and the
  /// screen can explain it.
  PlanetTickReport produce() {
    if (isDestroyed || population <= 0) return const PlanetTickReport();

    final gainedMinerals = deposit('minerals', mineralOutput);
    final gainedOrganics = deposit('organics', organicOutput);
    final gainedIndustrial = deposit('industrial', industrialOutput);
    final gainedDrones = deposit('drones', droneOutput);

    // Colony supply: an occasional bill, drawn every [supplyInterval] ticks.
    //
    // This replaced a per-capita organics upkeep with a starvation bleed, and
    // both halves of that were wrong for a world that cannot make organics at
    // all. A harsh type would have bled to death on a mechanic it was designed
    // to be unable to pay, and the only two answers were "haul organics forever"
    // and "watch your colonists die", neither of which is a decision.
    //
    // The bill is a share of the colony's **own output**, so it is the same
    // relative size at every scale, and the commodity is drawn at random from
    // the three consumables. A world short of the drawn one falls back through
    // [supplyCommodities], so it is paid in whatever it actually has.
    var supplyPaid = 0;
    var supplyShortfall = 0;
    String? supplyFrom;
    supplyTimer++;
    if (supplyTimer >= supplyInterval) {
      supplyTimer = 0;
      _supplyDrawCount++;
      supplyFrom = _drawSupplyCommodity();
      supplyPaid = _paySupply();
      supplyShortfall = supplyDraw - supplyPaid;
    }

    return PlanetTickReport(
      mineralsGained: gainedMinerals.stored,
      organicsGained: gainedOrganics.stored,
      industrialGained: gainedIndustrial.stored,
      dronesGained: gainedDrones.stored,
      shipmentQueued: gainedMinerals.spilled +
          gainedOrganics.spilled +
          gainedIndustrial.spilled +
          gainedDrones.spilled,
      supplyPaid: supplyPaid,
      supplyShortfall: supplyShortfall,
      supplyFrom: supplyFrom,
      // Only a full *shipment pool* is real loss now. Overflowing the working
      // store is normal, expected operation and is not worth a warning.
      storageOverflowed: gainedMinerals.lost +
              gainedOrganics.lost +
              gainedIndustrial.lost +
              gainedDrones.lost >
          0,
      population: population,
    );
  }

  /// Picks the commodity a supply draw will be charged in.
  ///
  /// Random among the three consumables, salted by the world's name so two
  /// colonies of identical size do not draw in lockstep. A world that cannot
  /// make the drawn commodity is not punished for it — the payment falls through
  /// to what it does have, which is the whole reason this is random rather than
  /// fixed on organics.
  String _drawSupplyCommodity() {
    final options = supplyCommodities;
    if (options.isEmpty) return 'minerals';
    // Salts on the draw counter, not on `supplyTimer`. Passing the *elapsed*
    // timer in instead would not help: the timer is reset exactly when this is
    // called, so the value it had reached is always `supplyInterval` — constant,
    // and the salt would be just as dead as it was.
    final n =
        (population * 31 + _supplyDrawCount * 17 + name.hashCode) & 0x7fffffff;
    return options[n % options.length];
  }

  /// Takes up to [supplyDraw], falling back through [supplyCommodities].
  ///
  /// Draws from the working store first and the **shipment pool second**: goods
  /// already produced and waiting to be collected are still goods, and a world
  /// whose output is merely queued should not be told it cannot feed itself.
  /// Returns what was actually taken.
  int _paySupply() {
    var owed = supplyDraw;
    if (owed <= 0) return 0;
    var paid = 0;
    for (final c in supplyCommodities) {
      if (owed <= 0) break;
      final take = _takeFrom(c, owed);
      paid += take;
      owed -= take;
    }
    return paid;
  }

  /// Removes up to [want] of [commodity] from the store, then the pool.
  int _takeFrom(String commodity, int want) {
    var owed = want;
    final store = storedFor(commodity);
    final fromStore = owed <= store ? owed : store;
    _setStored(commodity, store - fromStore);
    owed -= fromStore;
    if (owed <= 0) return fromStore;

    final pending = pendingFor(commodity);
    final fromPending = owed <= pending ? owed : pending;
    _setPending(commodity, pending - fromPending);
    return fromStore + fromPending;
  }

  /// Whether a build can be started: not already building, and able to pay.
  ///
  /// Colonists are a **minimum, not a cost** — a gate you satisfy by having
  /// enough people. Resources are the part you spend.
  bool get canStartConstruction {
    if (isUnderConstruction) return false;
    final cost = levelUpCost;
    if (cost == null) return false;
    if (population < cost.requiredColonists) return false;
    if (storedMinerals < cost.requiredMinerals) return false;
    if (storedOrganics < cost.requiredOrganics) return false;
    if (storedIndustrial < cost.requiredIndustrial) return false;
    return true;
  }

  /// True while a build is in progress.
  bool get isUnderConstruction => constructionTicksRemaining > 0;

  /// Ticks the current build started with, for a progress bar. 0 when idle.
  int get constructionTotalTicks =>
      isUnderConstruction ? constructionLengthFor(level) : 0;

  /// 0.0 to 1.0 through the current build.
  double get constructionProgress {
    if (!isUnderConstruction) return 0;
    final total = constructionTotalTicks;
    if (total <= 0) return 1;
    return (1 - (constructionTicksRemaining / total)).clamp(0.0, 1.0);
  }

  /// Ticks required to build from [from] up one level, scaled.
  ///
  /// The scale is applied **here, at the moment the build starts**, not when it
  /// finishes. A player who speeds construction up halfway through does not
  /// retroactively shorten it, and the tick loop stays free of any dependency on
  /// settings.
  static int constructionLengthFor(int from, {double timeScale = 1.0}) {
    final base = levelConstructionTicks[from];
    if (base == null) return 0;
    // A scale of 0 is the "I would rather not wait" preference and means instant.
    // Dividing by it instead would produce an enormous number, which is the
    // opposite of what the player asked for and reads as a bug rather than a
    // setting. One tick, not zero: a zero-length build would complete inside
    // the tick that started it and never show a frame of progress.
    if (timeScale <= 0) return 1;
    // Multiply, do not divide. A scale of 0.5 means "twice as fast as designed",
    // which is a *shorter* build; dividing here silently made the "faster"
    // setting twice as slow instead. The user-facing number and this arithmetic
    // have to read the same way round, which is what the guard below pins.
    final scaled = (base * timeScale).round();
    return scaled < 1 ? 1 : scaled;
  }

  /// Spends the resources and begins a build. Returns true if it started.
  ///
  /// Resources are consumed **at the start**, not on completion, and that is
  /// deliberate: it makes the build a commitment rather than a purchase. A world
  /// two hours into a Citadel upgrade is holding an investment an attacker can
  /// cost you, which is the point of the mechanic.
  bool startConstruction({double timeScale = 1.0}) {
    if (!canStartConstruction) return false;
    final cost = levelUpCost!;
    storedMinerals -= cost.requiredMinerals;
    storedOrganics -= cost.requiredOrganics;
    storedIndustrial -= cost.requiredIndustrial;
    constructionTarget = level + 1;
    constructionTicksRemaining =
        constructionLengthFor(level, timeScale: timeScale);
    return true;
  }

  /// Advances a build by one tick. Called by the game tick.
  ///
  /// Completing a build is what finally grants the level's benefits. Storage needs
  /// no code here because it is derived from `level`; defence and armour do,
  /// because the generator used to set them once and nothing ever changed them,
  /// so a level-6 Citadel defended exactly as well as a level-1 Outpost.
  void advanceConstruction() {
    if (!isUnderConstruction) return;
    constructionTicksRemaining--;
    if (constructionTicksRemaining > 0) return;

    level = constructionTarget;
    constructionTarget = 0;
    constructionTicksRemaining = 0;
    _applyLevelGrants();
  }

  /// Applies what a completed level confers.
  ///
  /// Locals are named `new*` rather than after the field they assign. Shadowing
  /// `shield` with a local `shield` made `shield = shield` a self-assignment on
  /// a final local, which the compiler caught — but the fix is a clearer name,
  /// not a cast.
  void _applyLevelGrants() {
    final newDefence = levelDefense[level] ?? defenseLevel;
    defenseLevel = newDefence;

    final newArmour = levelArmour[level] ?? 0;
    if (newArmour > 0) {
      maxHull = newArmour.toDouble();
      if (hull > newArmour) hull = newArmour.toDouble();
      if (hull <= 0) hull = newArmour.toDouble();
    }

    final newShield = levelShield[level] ?? 0;
    if (newShield > 0) {
      maxShield = newShield.toDouble();
      shield = newShield.toDouble();
    }
  }

  /// Instant level-up. Kept as a distinct path so the cost table and the grant
  /// table have exactly one implementation: a timed build is this, plus a wait.
  bool levelUp() {
    if (!canStartConstruction) return false;
    final cost = levelUpCost!;
    storedMinerals -= cost.requiredMinerals;
    storedOrganics -= cost.requiredOrganics;
    storedIndustrial -= cost.requiredIndustrial;
    level++;
    constructionTarget = 0;
    constructionTicksRemaining = 0;
    _applyLevelGrants();
    return true;
  }

  // ---------------------------------------------------------------------------
  // Planet type configuration
  // ---------------------------------------------------------------------------

  static const Map<String, AtmosphereConfig> planetAtmospheres = {
    'Terran': AtmosphereConfig('N2-O2', 'Earth-like, habitable'),
    'Jungle': AtmosphereConfig('N2-O2', 'Dense vegetation'),
    'Desert': AtmosphereConfig('Thin', 'Arid, sandy'),
    'Ocean': AtmosphereConfig('N2-O2', 'Water world'),
    'Ice': AtmosphereConfig('Thin', 'Frozen wasteland'),
    'Lava': AtmosphereConfig('CO2', 'Volcanic, molten'),
    'Moon': AtmosphereConfig('None', 'Small rocky body'),
    'Mountain': AtmosphereConfig('Thin', 'Thin, cold highland air'),
    'Barren': AtmosphereConfig('None', 'Rocky, lifeless'),
    'Toxic': AtmosphereConfig('Acid', 'Corrosive atmosphere'),
  };

  static const Map<String, TypeMultipliers> typeMultipliers = {
    'Terran': TypeMultipliers(1.0, 1.0, 1.2, 1.0),
    'Jungle': TypeMultipliers(0.6, 1.8, 0.6, 0.8),
    'Desert': TypeMultipliers(1.4, 0.4, 0.8, 1.2),
    'Ocean': TypeMultipliers(0.4, 2.0, 0.6, 0.6),
    // A harsh world cannot make organics **at all**, matching the classic
    // Volcanic world which produced none. The previous values were 0.2-0.4 —
    // small but non-zero — and they only existed to feed a per-capita upkeep
    // tax this design has dropped. A gap, not a penalty: a harsh type is not
    // punished for existing, it is structurally incapable of feeding itself, so
    // the answer is to haul organics in or plant an Ocean beside it.
    'Ice': TypeMultipliers(0.8, 0.0, 0.6, 0.8),
    'Lava': TypeMultipliers(2.0, 0.0, 1.4, 1.4),
    'Moon': TypeMultipliers(1.0, 0.0, 0.6, 0.8),
    // Mountain is a *flavour* row, not a second copy of the production maths.
    // The triangle in `planet_classes.dart` is the live rule; this table says
    // what a world is known for, and it feeds `canProduce` (which locks a
    // workforce stepper), `dominantCommodity`, and the Planet Guide's
    // "strongest at" line. Kept in agreement with the triangle's *direction*:
    // Mountain's ore peak is its largest (10,000/day), organics second
    // (4,000/day) and equipment last (1,000/day), so minerals must read as its
    // headline or the help screen would contradict the numbers beside it.
    'Mountain': TypeMultipliers(1.5, 1.2, 1.0, 1.2),
    'Barren': TypeMultipliers(1.2, 0.0, 0.8, 1.0),
    'Toxic': TypeMultipliers(1.6, 0.0, 1.0, 1.2),
  };

  static const List<String> allTypes = [
    'Terran',
    'Jungle',
    'Mountain',
    'Desert',
    'Ocean',
    'Ice',
    'Lava',
    'Moon',
    'Barren',
    'Toxic',
  ];

  /// Folder every entry in [imagePool] lives in.
  ///
  /// **The prefix lives here, once.** `imagePool` holds bare file names because
  /// that is the shape of the data, but `Image.asset` needs a path from the
  /// asset root. Two callers each built that path independently — the universe
  /// generator prefixed it and `WorldForging._imageFor` did not — so a
  /// generator-placed world showed its picture and a **torpedo-launched one
  /// silently showed nothing**, for every type, forever. One function that both
  /// call is the fix; a comment on one of them would not have been.
  static const String imageFolder = 'assets/images/planets/';

  /// A randomly chosen image asset path for a world of [type], or null when the
  /// type has no pool.
  ///
  /// Null rather than a plausible-looking path: both planet views guard on
  /// `imagePath != null` and render nothing, so "no picture" degrades cleanly and
  /// a wrong path degrades into a broken-image box.
  static String? randomImageFor(String type, math.Random rng) {
    final pool = imagePool[type];
    if (pool == null || pool.isEmpty) return null;
    return '$imageFolder${pool[rng.nextInt(pool.length)]}';
  }

  static const Map<String, List<String>> imagePool = {
    'Terran': [
      'Terran_World_1.gif',
      'Terran_World_2.gif',
      'Terran_World_3.gif'
    ],
    'Jungle': [
      'Jungle_World_1.gif',
      'Jungle_World_2.gif',
      'Jungle_World_3.gif'
    ],
    'Desert': [
      'Desert_World_1.gif',
      'Desert_World_2.gif',
      'Desert_World_3.gif'
    ],
    'Ocean': ['Ocean_World_1.gif', 'Ocean_World_2.gif', 'Ocean_World_3.gif'],
    'Ice': ['Ice_World_1.gif', 'Ice_World_2.gif', 'Ice_world_3.gif'],
    'Lava': ['Lava_World_1.gif', 'Lava_World_2.gif', 'Lava_World_3.gif'],
    'Moon': ['Moon_1.gif', 'Moon_2.gif', 'Moon_3.gif'],
    // Reuses the pool that used to be orphaned under `Unknown_World_*.gif`.
    // The files were renamed to match the convention every other type follows
    // (`<Type>_World_N.gif`); nothing referenced them before, because
    // `imagePool` had no `Unknown` key and the `Unknown` class spec is a
    // private fallback rather than a real type.
    'Mountain': [
      'Mountain_World_1.gif',
      'Mountain_World_2.gif',
      'Mountain_World_3.gif'
    ],
    'Barren': ['Moon_1.gif', 'Moon_2.gif', 'Moon_3.gif'],
    'Toxic': ['Toxic_World_1.gif', 'Toxic_World_2.gif', 'Toxic_World_3.gif'],
  };

  static const List<String> planetNames = [
    'Xandor',
    'Elara',
    'Sygnara',
    'Voryn',
    'Celestara',
    'Rynara',
    'Thalys',
    'Orwyn',
    'Glavara',
    'Zephyron',
    'Tyria',
    'Axion',
    'Nebulon',
    'Valthor',
    'Saronis',
    'Elyx',
    'Corvus',
    'Zantara',
    'Oberyn',
    'Krythos',
    'Selara',
    'Phaeton',
    'Ecliptor',
    'Astralis',
    'Vionis',
    'Nexilon',
    'Caelum',
    'Sypher',
    'Galeth',
    'Xeridia',
    'Lumora',
    'Tychon',
    'Velara',
    'Myriad',
    'Arctura',
    'Novex',
    'Zephyris',
    'Calyx',
    'Orithyia',
    'Sylvara',
    'Aetherion',
    'Draconis',
    'Quasys',
    'Solara',
    'Erebos',
    'Thalara',
    'Kryon',
    'Vylis',
    'Nexara',
    'Zorath',
    'Ilythar',
    'Vexalon',
    'Synthera',
    'Auralis',
    'Zypheron',
    'Tarsys',
    'Elion',
    'Gravara',
    'Nyxara',
    'Corynth',
    'Xylara',
    'Praxon',
    'Vionara',
    'Zelthar',
    'Astron',
    'Kytheris',
    'Sylion',
    'Eryndor',
    'Valthys',
    'Orythia',
    'Nebula',
    'Xerath',
    'Tylara',
    'Cygnara',
    'Aethys',
    'Zorwyn',
    'Vexara',
    'Sylthara',
    'Klyon',
    'Ecthara',
    'Rynther',
    'Galara',
    'Zyron',
    'Velithor',
    'Naxara',
    'Thalith',
    'Orionis',
    'Clythera',
    'Voryth',
    'Aelara',
    'Xynara',
    'Krylara',
    'Zentara',
    'Elythar',
    'Sovara',
    'Nyxion',
    'Tethys',
    'Vionth',
    'Astrara',
  ];

  static const List<String> romanNumerals = [
    'I',
    'II',
    'III',
    'IV',
    'V',
    'VI',
  ];

  static const List<String> greekPrefixes = [
    'Alpha',
    'Beta',
    'Delta',
    'Gamma',
  ];

  /// Generates a varied planet name from a base name, optionally appending
  /// Roman numeral and/or Greek prefix for variety.
  /// Formats: "Lumora", "Lumora III", "Lumora Alpha", "Lumora Alpha V"
  static String generateVariantName(String baseName, int seed) {
    final rng = int.parse(
        (seed.abs() % 100000).toString().padLeft(5, '0').substring(0, 3));
    final variant = rng % 4;
    switch (variant) {
      case 1: // name + numeral
        return '$baseName ${romanNumerals[rng % romanNumerals.length]}';
      case 2: // name + prefix
        return '$baseName ${greekPrefixes[rng % greekPrefixes.length]}';
      case 3: // name + prefix + numeral
        return '$baseName ${greekPrefixes[(rng + 2) % greekPrefixes.length]} ${romanNumerals[(rng + 3) % romanNumerals.length]}';
      default: // 0 — plain name
        return baseName;
    }
  }
}

class AtmosphereConfig {
  final String atmosphere;
  final String description;
  const AtmosphereConfig(this.atmosphere, this.description);
}

class TypeMultipliers {
  final double minerals;
  final double organics;
  final double industrial;
  final double drones;
  const TypeMultipliers(
      this.minerals, this.organics, this.industrial, this.drones);
}

/// What one production tick did to a colony.
///
/// Returned rather than merely logged so the tick can summarise it, the action
/// log can report it, and a test can assert on it without reaching into four
/// storage fields and hoping it checked all of them.
class PlanetTickReport {
  final int mineralsGained;
  final int organicsGained;
  final int industrialGained;
  final int dronesGained;

  /// Output that overflowed the working store and is now waiting in the
  /// shipment pool. Not a loss — it is still owed to the player.
  final int shipmentQueued;

  /// Units actually taken for this tick's colony supply draw. Zero on the nine
  /// ticks in ten where no draw is due.
  final int supplyPaid;

  /// Supply the colony could not pay. Non-zero means it is running on nothing
  /// and needs goods hauled in, or a complement planted beside it.
  final int supplyShortfall;

  /// The commodity the draw was charged in, or null when no draw was due.
  final String? supplyFrom;

  /// Some output did not fit in storage and was discarded.
  final bool storageOverflowed;

  /// Population after the tick, so a caller can report a loss without
  /// re-reading the planet.
  final int population;

  const PlanetTickReport({
    this.mineralsGained = 0,
    this.organicsGained = 0,
    this.industrialGained = 0,
    this.dronesGained = 0,
    this.shipmentQueued = 0,
    this.supplyPaid = 0,
    this.supplyShortfall = 0,
    this.supplyFrom,
    this.storageOverflowed = false,
    this.population = 0,
  });

  /// True when the tick changed anything a player would want told about.
  bool get isInteresting =>
      mineralsGained > 0 ||
      organicsGained > 0 ||
      industrialGained > 0 ||
      dronesGained > 0 ||
      supplyShortfall > 0 ||
      storageOverflowed;

  /// True when a supply draw happened and the colony could not cover it.
  ///
  /// Worth its own log line, because it is the one outcome a player must act on
  /// rather than merely enjoy. It no longer means anyone is dying — starvation is
  /// gone — it means the colony is drawing on nothing and its stores are empty.
  bool get isUnsupplied => supplyShortfall > 0;
}

class LevelUpCost {
  final int requiredColonists;
  final int requiredMinerals;
  final int requiredOrganics;
  final int requiredIndustrial;
  const LevelUpCost(this.requiredColonists, this.requiredMinerals,
      this.requiredOrganics, this.requiredIndustrial);
}

/// Typed access to a resource by name, for the UI layers that drive rows from
/// a string key.
///
/// One source on purpose. The planet screen and the market panel both render
/// resource rows keyed by commodity name, and this started as a private method
/// on the screen — which meant the panel needed its own copy the moment it was
/// extracted. Two copies of a commodity switch drift: the `default: 0` branch is
/// what hides it, because a missing case reads as an empty cell rather than as an
/// error.
extension PlanetResources on Planet {
  /// Units of [type] currently in stores. `colonists` is a population, not a
  /// store, and the transfer rows rely on that reading.
  int storedFor(String type) {
    switch (type) {
      case 'minerals':
        return storedMinerals;
      case 'organics':
        return storedOrganics;
      case 'industrial':
        return storedIndustrial;
      case 'drones':
        return storedDrones;
      case 'colonists':
        return population;
      default:
        return 0;
    }
  }

  /// The ceiling for [type]. Colonists are capped by the level gate rather than
  /// by a store.
  int capacityFor(String type) {
    if (type == 'colonists') return colonistMax;
    return capFor(type);
  }
}
