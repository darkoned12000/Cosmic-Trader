import 'dart:math' as math;

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
import 'package:cosmic_trader/data/models/faction.dart';

/// Where colonists come from, and what they cost.
///
/// ## Why this is per-faction and not one central world
///
/// Colonists were originally bought at any port for a flat 20 credits, with no
/// regard for who was buying. That is both a balance problem and a lore one.
/// The Duran Hegemony are a militaristic insectoid empire built on hierarchy and
/// conquest; letting a Duran player ship in human colonists to work their mines
/// is not a neutral abstraction, it is the thing their faction is described as
/// doing. A Vulcan taking organics out of a Terran atmosphere is a supply
/// chain; it is not the same thing as a Terran settler.
/// So each faction draws its colonists from **its own homeworld**, and the
/// supply line is a real dependency.
///
/// ## What that buys mechanically
///
/// It ties three systems that were previously unrelated. The homeworld is
/// already the faction's shipyard, and it is already control-gated:
/// [RepopulationService.homeworldSectors] treats a captured or destroyed
/// homeworld as producing nothing. Making it the colonist source as well means a
/// faction that loses its capital loses its ability to *grow*, not just its
/// ability to replace losses. When invasion lands, denying a faction its
/// homeworld becomes a genuine strategic strike rather than a fleet action.
///
/// ## Why a price and not a wait
///
/// The obvious alternative is a transit timer. That worked in the game this is
/// drawn from because it was online, and every other colony was decaying while
/// you slept. This game is single-player with local saves, so a transit bar is
/// not a strategic cost — it is the player watching a bar for no reason, which
/// is exactly the tedium this is meant to remove. A price rises whether or not
/// you are watching it.
class ColonistSupply {
  ColonistSupply._();

  /// Terra Prime, in sector 1. It is the Traders' homeworld, and it is also the
  /// fallback for a faction with no capital left — see [orphanSourcePenalty].
  static const int terraPrimeSectorId = 1;

  /// Price of one colonist shipped one hop.
  static const int basePricePerColonist = 15;

  /// Curvature of the distance premium.
  ///
  /// Not 1, and that matters. The galaxy is compact: measured across 117
  /// generated planets, the BFS distance from a homeworld runs 1 to 8 hops with
  /// a median of 4. A linear premium over that range is nearly invisible — 4
  /// hops would cost barely more than 2 — so distance would not be a decision.
  /// At 1.5 the farthest worlds cost more than twenty times the nearest.
  static const double distanceExponent = 1.5;

  /// Multiplier applied when a faction has no homeworld under its control and
  /// is buying from Terra instead.
  ///
  /// This should not be reachable in normal play: losing a homeworld currently
  /// needs invasion, which does not exist yet, and the backup capital already
  /// covers the captured case. It exists so that an exiled faction is
  /// expensive rather than *stuck*, which is the difference between a dramatic
  /// setback and a dead save. Raise it, or remove the fallback and the whole
  /// exile concept, when invasion makes the first case real.
  static const double orphanSourcePenalty = 3.0;

  /// Hops used when a target genuinely cannot be reached. Priced as the worst
  /// case rather than free.
  static const int unreachableHops = 12;

  /// Where [faction] draws its colonists from, and what that costs.
  ///
  /// Resolution order is the faction's **primary** homeworld, then its
  /// **backup** capital, then Terra at [orphanSourcePenalty]. Primary-over-
  /// backup is not reimplemented here: [RepopulationService.homeworldSectors]
  /// already encodes the control rules (not destroyed, owner is the faction or
  /// nobody, primaries win over backups) and ship production uses them, so
  /// colonist supply and ship production can never disagree about who has a
  /// capital.
  static ColonistSource sourceFor(
    List<Sector> sectors,
    FactionClass faction,
  ) {
    final homeworlds = RepopulationService.homeworldSectors(sectors);
    final homeId = homeworlds[faction];

    if (homeId == null) {
      return ColonistSource(
        sectorId: terraPrimeSectorId,
        name: 'Terra Prime',
        isHomeworld: false,
        isOrphan: true,
      );
    }

    // The capital is *this faction's* world in that sector, not the sector's
    // first world flagged `isHomeworld`. A sector can hold more than one, and
    // it can hold a backup for one faction beside a primary for another — so
    // `s.homeworld`, which takes the first hit with no faction filter, returns
    // the *Vinari* capital for a Duran query: right sector, wrong name, and
    // `isBackup` false on a world that is precisely the reserve. The sector id
    // came from `homeworldSectors`, which is per-faction, so the detail has to
    // be resolved per-faction too or the two halves disagree.
    //
    // Primary before reserve, matching `homeworldSectors`' own preference.
    Planet? home;
    for (final p in sectors) {
      if (p.id != homeId) continue;
      for (final candidate in p.planets) {
        if (candidate.isDestroyed) continue;
        if (candidate.homeworldOf != faction) continue;
        if (!candidate.isHomeworld) continue;
        if (!candidate.isBackupHomeworld) {
          home = candidate;
          break;
        }
        home ??= candidate;
      }
      break;
    }
    return ColonistSource(
      sectorId: homeId,
      name: home?.name ?? 'homeworld',
      isHomeworld: true,
      isBackup: home?.isBackupHomeworld ?? false,
      isOrphan: false,
    );
  }

  /// BFS hops from [sourceSectorId] to [targetSectorId].
  ///
  /// **The unreachable clamp used to be dead code.** It guarded on
  /// `distance(...) <= 0`, and `PathfindingService.distance` returns the sentinel
  /// **9999** for unreachable — never zero — so the guard never fired. An existing
  /// but unreachable capital therefore priced colonists at
  /// `15 x 9999^1.5` = **14,997,750 cr each**, against 624 at the intended
  /// [unreachableHops] of 12, and 1,000 colonists came to 15 billion credits.
  ///
  /// It also meant the *orphan* fallback never engaged for this case, because
  /// `isOrphan` is about having no capital at all rather than having an
  /// unreachable one — two different failures with one guard between them.
  ///
  /// `findPath` returns null properly, so the check is on that.
  static int hopsBetween(
      List<Sector> sectors, int sourceSectorId, int targetSectorId) {
    if (sourceSectorId == targetSectorId) return 1;
    final path =
        PathfindingService.findPath(sectors, sourceSectorId, targetSectorId);
    if (path == null) return unreachableHops;
    final d = path.length - 1;
    return d < 1 ? 1 : d;
  }

  /// Credits per colonist at [hops] distance.
  static int pricePerColonist(int hops, {bool orphan = false}) {
    final safe = hops < 1 ? 1 : hops;
    final base = basePricePerColonist * math.pow(safe, distanceExponent);
    return (base * (orphan ? orphanSourcePenalty : 1.0)).round();
  }

  /// Credits for shipping [count] colonists [hops] away.
  static int costFor(int count, int hops, {bool orphan = false}) =>
      (pricePerColonist(hops, orphan: orphan) * count).round();

  /// Energy for one shipment of any size.
  ///
  /// Reuses the real engine-aware warp cost rather than an invented rate, so the
  /// same engine upgrade that helps you travel helps you supply an empire, and
  /// the two systems can never disagree. Per-shipment rather than per-colonist
  /// means batching pays, and energy is what limits how far an empire can
  /// spread.
  static int energyPerShipment(Player player, int hops) =>
      EnergyService.warpCost(player, hops: hops < 1 ? 1 : hops);
}

/// The place a faction draws colonists from.
class ColonistSource {
  final int sectorId;
  final String name;

  /// False when this is the Terra fallback rather than a real capital.
  final bool isHomeworld;

  /// True when the capital in use is the cold-standby backup.
  final bool isBackup;

  /// True when the faction has no capital of its own and is buying from Terra.
  final bool isOrphan;

  const ColonistSource({
    required this.sectorId,
    required this.name,
    this.isHomeworld = false,
    this.isBackup = false,
    this.isOrphan = false,
  });

  /// How to describe the source to the player.
  ///
  /// Kept short deliberately: this string sits on a dense trade row that
  /// ellipsises rather than overflows, so anything verbose here is a label the
  /// player cannot read. The exile rate is explained in the guide rather than
  /// in the row.
  String get label {
    if (isOrphan) return '$name (exile)';
    if (isBackup) return '$name (reserve)';
    return name;
  }
}
