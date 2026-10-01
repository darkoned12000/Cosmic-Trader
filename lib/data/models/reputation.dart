/// The reputation ladder, from TradeWars 2002.
///
/// **Signed.** Positive means the galaxy thinks you are a decent trader;
/// negative means the opposite. It is deliberately *not* the old `notoriety`,
/// which started at zero and only ever went up as a "how noticed are you"
/// counter — a scale where the worst act and the best one both pushed the same
/// direction, so there was no such thing as being well thought of.
///
/// The original called this *alignment*, and that is what this is. The field on
/// [Player] was renamed to match, because a stat called "notoriety" that goes up
/// when you do something decent is a trap for the next person to read it. Old
/// saves are migrated by negating (see `Player.fromJson`).
///
/// Flutter-free on purpose: `data/` must not import widgets, and the AI needs to
/// read a player's standing.
library;

import 'package:cosmic_trader/data/models/faction.dart';

/// Which way a reputation value points.
enum ReputationSide {
  /// Above the noise floor: the galaxy is inclined to trust you.
  good,

  /// Nobody has formed an opinion yet.
  neutral,

  /// Below the noise floor: the galaxy has a file on you.
  evil,
}

/// One rung of the ladder, with a different title for each direction.
///
/// The thresholds are the original's, doubling from 2 to 4,194,304, which is why
/// the first few ranks arrive almost immediately and the last one takes a career.
/// Transcribed rather than derived: the doubling *is* the design, and any scheme
/// of our own would have to be tuned against it anyway.
class ReputationRank {
  /// Experience required to hold this rank, as a magnitude. 0 is unranked.
  final int threshold;

  /// 1-based; index 11 is the highest rank reachable without an absolute value
  /// large enough that the ladder stops mattering.
  final int index;

  final String good;
  final String evil;

  const ReputationRank({
    required this.threshold,
    required this.index,
    required this.good,
    required this.evil,
  });

  String titleFor(ReputationSide side) => switch (side) {
        ReputationSide.good => good,
        ReputationSide.evil => evil,
        ReputationSide.neutral => 'Unranked',
      };
}

/// Reads a reputation value as a rank, a title, and a direction.
///
/// Named `Reputation` rather than `Alignment` because Flutter already exports a
/// widget called `Alignment`, and a model class that collides with it costs an
/// import prefix in every file that wants one.
class Reputation {
  const Reputation._();

  /// Largest magnitude the ladder describes.
  static const double absMax = 4194304;

  /// The original's full table, in order. A player's rank is the highest entry
  /// whose threshold their magnitude reaches.
  static const List<ReputationRank> ladder = [
    ReputationRank(
        threshold: 2, index: 1, good: 'Private', evil: 'Nuisance 3rd Class'),
    ReputationRank(
        threshold: 4,
        index: 2,
        good: 'Private 1st Class',
        evil: 'Nuisance 2nd Class'),
    ReputationRank(
        threshold: 8,
        index: 3,
        good: 'Lance Corporal',
        evil: 'Nuisance 1st Class'),
    ReputationRank(
        threshold: 16, index: 4, good: 'Corporal', evil: 'Menace 3rd Class'),
    ReputationRank(
        threshold: 32, index: 5, good: 'Sergeant', evil: 'Menace 2nd Class'),
    ReputationRank(
        threshold: 64,
        index: 6,
        good: 'Staff Sergeant',
        evil: 'Menace 1st Class'),
    ReputationRank(
        threshold: 128,
        index: 7,
        good: 'Gunnery Sergeant',
        evil: 'Smuggler 3rd Class'),
    ReputationRank(
        threshold: 256,
        index: 8,
        good: '1st Sergeant',
        evil: 'Smuggler 2nd Class'),
    ReputationRank(
        threshold: 512,
        index: 9,
        good: 'Sergeant Major',
        evil: 'Smuggler 1st Class'),
    ReputationRank(
        threshold: 1024,
        index: 10,
        good: 'Warrant Officer',
        evil: 'Smuggler Savant'),
    ReputationRank(
        threshold: 2048,
        index: 11,
        good: 'Chief Warrant Officer',
        evil: 'Robber'),
    ReputationRank(
        threshold: 4096, index: 12, good: 'Ensign', evil: 'Terrorist'),
    ReputationRank(
        threshold: 8192, index: 13, good: 'Lieutenant J.G.', evil: 'Pirate'),
    ReputationRank(
        threshold: 16384,
        index: 14,
        good: 'Lieutenant',
        evil: 'Infamous Pirate'),
    ReputationRank(
        threshold: 32768,
        index: 15,
        good: 'Lieutenant Commander',
        evil: 'Notorious Pirate'),
    ReputationRank(
        threshold: 65536, index: 16, good: 'Commander', evil: 'Dread Pirate'),
    ReputationRank(
        threshold: 131072,
        index: 17,
        good: 'Captain',
        evil: 'Galactic Scourge'),
    ReputationRank(
        threshold: 262144,
        index: 18,
        good: 'Commodore',
        evil: 'Enemy of the State'),
    ReputationRank(
        threshold: 524288,
        index: 19,
        good: 'Rear Admiral',
        evil: 'Enemy of the People'),
    ReputationRank(
        threshold: 1048576,
        index: 20,
        good: 'Vice Admiral',
        evil: 'Enemy of Humankind'),
    ReputationRank(
        threshold: 2097152,
        index: 21,
        good: 'Admiral',
        evil: 'Heinous Overlord'),
    ReputationRank(
        threshold: 4194304,
        index: 22,
        good: 'Fleet Admiral',
        evil: 'Prime Evil'),
  ];

  /// Below this magnitude nobody has formed an opinion, so the side is
  /// [ReputationSide.neutral] and the title is "Unranked". Exactly 1 point keeps
  /// the first rank within reach of a single small act, as the original intended.
  static const double noiseFloor = 1.0;

  /// Keeps a value inside the ladder's range.
  ///
  /// Every movement goes through here. A reputation scale that can be walked off
  /// the end of its own table is a scale where the display has to invent an
  /// answer past the last rung.
  static double clamp(double value) => value.clamp(-absMax, absMax).toDouble();

  /// Which way this value points.
  static ReputationSide sideOf(double value) {
    if (value >= noiseFloor) return ReputationSide.good;
    if (value <= -noiseFloor) return ReputationSide.evil;
    return ReputationSide.neutral;
  }

  /// The highest rank this magnitude reaches, or the rank-zero placeholder.
  static ReputationRank rankFor(double value) {
    final magnitude = value.abs();
    // Iterates the **whole** ladder rather than returning on the first match. An
    // early return reads the *lowest* rung a pilot qualifies for: 64 came back as
    // "Private" instead of "Staff Sergeant", because 2 is also <= 64, so every
    // value past the first rung was pinned to rank 1.
    ReputationRank best = const ReputationRank(
      threshold: 0,
      index: 0,
      good: 'Unranked',
      evil: 'Unranked',
    );
    for (final rank in ladder) {
      if (magnitude < rank.threshold) break;
      best = rank;
    }
    return best;
  }

  /// The next rank up, or null once the ladder is exhausted in that direction.
  static ReputationRank? nextRank(double value) {
    final magnitude = value.abs();
    for (final rank in ladder) {
      if (rank.threshold > magnitude) return rank;
    }
    return null;
  }

  /// Progress from [value] to [Reputation.nextRank], 0..1.
  ///
  /// Measured from the *bottom of the current band*, not from the previous
  /// threshold's absolute value, so a player sitting at exactly a threshold sees
  /// 0% rather than appearing to have already earned the next rank.
  static double progressToNext(double value) {
    final next = nextRank(value);
    if (next == null) return 1.0;
    final magnitude = value.abs();
    final floor = _floorFor(magnitude);
    final span = next.threshold - floor;
    if (span <= 0) return 1.0;
    return ((magnitude - floor) / span).clamp(0.0, 1.0);
  }

  static int _floorFor(double magnitude) {
    var floor = 0;
    for (final rank in ladder) {
      if (rank.threshold <= magnitude) {
        floor = rank.threshold;
      } else {
        break;
      }
    }
    return floor;
  }

  /// Points still needed for the next rank in this direction; null at the top.
  static int? pointsToNext(double value) {
    final next = nextRank(value);
    if (next == null) return null;
    return (next.threshold - value.abs()).round();
  }
}

/// What each deed is worth, in one place.
///
/// Signed by hand: **negative is a bad deed, positive a good one.** The old scale
/// had one direction only, so there was nowhere to put "doing the right thing" —
/// these constants are the first place both signs exist, and they are the thing
/// to retune when balancing reputation.
///
/// Magnitudes are chosen against the ladder's doubling curve rather than by
/// feel. `scanPilot` sits at the bottom so a new player's first act registers;
/// `destroyWorld` at 128 is a quarter of the way to the mid ranks, which is where
/// "you blew up a populated world" belongs; `capturePort` at 512 is roughly a
/// Sergeant/Menace, comparable to seizing a port outright.
class ReputationActions {
  const ReputationActions._();

  // ── Bad deeds ──────────────────────────────────────────────────────────

  /// Scanning another pilot's ship. Barely registers.
  static const double scanPilot = -2;

  /// Port hack. You read their systems; that is not forgotten.
  static const double hackPort = -16;

  /// Sabotage. Deliberate damage to someone's port.
  static const double sabotagePort = -64;

  /// Destroying an NPC that was hostile to you — a raider, or one already coming
  /// for you. A legitimate target.
  static const double killPatrol = -32;

  /// Destroying a pilot who is **wanted** — carrying a live bounty on the board.
  ///
  /// **Positive**, and it *replaces* [killPatrol] / [killUnprovoked] rather than
  /// sitting on top of them. A bounty is the galaxy saying out loud that this
  /// kill is wanted, so the question "was this pilot hostile?" stops being the
  /// question. That is the case that read worst: a Guild pilot collecting on a
  /// wanted **Duran** trader — at peace with the Guild, so [killUnprovoked] —
  /// was billed as a murderer for doing the one thing the board had paid him to
  /// do. The override is also what stops the deed being unanswerable: the
  /// hostility split is a rule about *factions*, and a bounty is a fact about
  /// one individual, so no faction table can express it.
  ///
  /// The caller decides "wanted" from the bounty board's own answer rather than
  /// from a second lookup: if [BountyBoard.claim] paid out, there was a live
  /// mark, and that is the one fact both the credits and this charge must agree
  /// on. Two reads of the board could disagree, and the player would be charged
  /// murder for a kill the board had already settled.
  static const double killWanted = 48;

  /// Destroying a pilot who was **not** hostile: a trader, a hauler, anyone
  /// minding their own business.
  ///
  /// Exactly twice [killPatrol], and the doubling is the point rather than a
  /// rounding. A patrol dies fighting; a peaceful pilot dies because you opened
  /// fire, and the galaxy keeps a longer memory of the second. It is also what
  /// stops −32 as a *tax on playing* — every unprovoked shot against a
  /// neighbour would otherwise cost the same as shooting back at a raider, so
  /// there is no price at all for being the aggressor.
  static const double killUnprovoked = -64;

  /// Vaporising a world and everything on it.
  ///
  /// Charged **whether or not you made it** — see [WorldForging.detonate]. The
  /// exemption for your own worlds is what allowed the create/destroy loop, and
  /// demolishing a populated world is a violent act whoever signed for it.
  static const double destroyWorld = -128;

  /// Taking a port by force.
  static const double capturePort = -512;

  /// Razing a port you have already taken. Worse than taking it: this one is
  /// destruction rather than conquest.
  static const double destroyPort = -1024;

  /// Running from a fight. A small mark — the original docked pirates for it too,
  /// so it belongs on the scale even though it is barely a crime.
  static const double fleePort = -8;

  // ── Good deeds ─────────────────────────────────────────────────────────

  /// Bringing a new world into existence with a Genesis Torpedo.
  ///
  /// Deliberately *equal and opposite* to [destroyWorld]. That symmetry is what
  /// closes the farming loop: launch then demolish nets zero, so there is no
  /// reason to buy ordnance you do not intend to keep. An earlier figure of 1024
  /// against a free self-demolition was a +1024 cycle for 55,000 credits, which
  /// cleared the first nine ranks (512 in total) in one go.
  static const double createWorld = 128;

  /// Completing a Citadel tier.
  ///
  /// Small and repeated: a full run from Outpost to level 6 is five upgrades,
  /// so a world built from nothing is worth roughly the same again on top of its
  /// creation. Slow enough that it cannot be rushed for reputation.
  static const double upgradeWorld = 24;

  /// Settling a world you found: claiming or clearing land.
  ///
  /// Half of [createWorld], so making something is worth twice what taking it
  /// is — and both are dwarfed by the cost of demolishing either.
  static const double buildWorld = 64;

  /// Collecting revenue from a port you own, per collection.
  ///
  /// Small and repeatable, so a player who keeps a working port drifts upward
  /// without a single dramatic act.
  static const double portRevenue = 8;

  /// What killing a pilot of [victimFaction] is worth to [killerFaction].
  ///
  /// Hostility is read from [FactionHostility.areHostile] rather than
  /// re-derived here, and that is the whole point of this function existing:
  /// the hostility the *player is charged under* must be the hostility the *tick
  /// acts on*. A private chooser inside the combat screen would have been the
  /// third copy of that rule in the codebase, and untestable without pumping a
  /// fight.
  ///
  /// A hostile target is a legitimate kill. A pilot who was not shooting at you
  /// is a murder, and costs [killUnprovoked] — see its note for why the doubling
  /// is the mechanic rather than a rounding.
  ///
  /// [wanted] short-circuits both. See [killWanted] for why a bounty has to
  /// override the faction split rather than add to it, and why the caller
  /// decides it from the board's payout rather than from a second lookup.
  static double forKilling({
    required FactionClass victimFaction,
    required FactionClass killerFaction,
    bool wanted = false,
  }) {
    if (wanted) return killWanted;
    final hostile = FactionHostility.areHostile(victimFaction, killerFaction);
    return hostile ? killPatrol : killUnprovoked;
  }
}

/// The one place the "are these two factions at war" rule is written down.
///
/// Lives in the data layer rather than on [NpcAiService] because the data layer
/// must not import services, and because *charging the player* is not an AI
/// decision — it is a rule about the galaxy, and both the AI and the reputation
/// table have to read the same one.
class FactionHostility {
  const FactionHostility._();

  /// Pirates are hostile to everyone; Duran and Vinari to each other; everyone
  /// else is at peace.
  static bool areHostile(FactionClass a, FactionClass b) {
    if (a == b) return false;
    if (a == FactionClass.pirate || b == FactionClass.pirate) return true;
    return (a == FactionClass.duran && b == FactionClass.vinari) ||
        (a == FactionClass.vinari && b == FactionClass.duran);
  }
}
