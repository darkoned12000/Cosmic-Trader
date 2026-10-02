import 'package:uuid/uuid.dart';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';

/// One share of an order, filled by one port.
class TradeAllocation {
  const TradeAllocation({
    required this.portSectorId,
    required this.units,
    required this.hops,
    required this.ticksPerRun,
    required this.unitPrice,
  });

  final int portSectorId;
  final int units;
  final int hops;
  final int ticksPerRun;
  final int unitPrice;
}

/// The result of [PlanetTradeService.plan]: nearest-first shares plus what
/// the galaxy could not absorb.
class TradePlan {
  const TradePlan({
    required this.allocations,
    required this.unitsRequested,
    required this.unitsAllocated,
  });

  final List<TradeAllocation> allocations;
  final int unitsRequested;
  final int unitsAllocated;

  int get shortfall => unitsRequested - unitsAllocated;
}

/// One verb, one owner for planet trade jobs.
///
/// A job is a bulk order placed against a port. It takes several ticks to
/// deliver, and the countdown is driven here so the tick and the screen
/// cannot disagree about when goods arrive.
///
/// The tick owns the *world*, the screen owns the *pilot*: a buy delivery
/// lands in the planet's store (via [Planet.deposit], so overflow spills to
/// the shipment pool exactly as production does), and a sell delivery earns
/// into the world's `accumulatedRevenue`, which the owner withdraws. The tick
/// never touches a player, so there is no read-modify-write clobber.
class PlanetTradeService {
  const PlanetTradeService._();

  /// Ticks per hop of a cargo run. One hop is a minute of play at the 30s
  /// tick, so the median four-hop port is a four-minute run. Distance sets
  /// the cadence; order size sets the number of runs; the two do not interact.
  static const int ticksPerHop = 2;

  /// Units one port-freighter run carries.
  ///
  /// The player's hold and engine are deliberately not involved — the job is
  /// a credit-and-time cost — so this is the port's hull, not the pilot's.
  /// Sized so the documented order (80,000 minerals across a median four-hop
  /// run) lands in 16 runs over about an hour, with a delivery every four
  /// minutes.
  static const int freighterHold = 5000;

  /// Places an order on [planet]. Returns the job, so the caller can report it.
  ///
  /// Sell goods leave the store at order time — a sell of goods still sitting
  /// in the store is a reservation the world cannot keep. Returns null when
  /// the order cannot be placed (nothing to sell, unknown commodity).
  static TradeJob? create({
    required Planet planet,
    required String playerId,
    required int portSectorId,
    required String commodity,
    required TradeDirection direction,
    required int units,
    required int ticksPerRun,
    int unitPrice = 0,
    int? unitsPerRun,
    String? orderId,
    int? escrowed,
    String? jobId,
  }) {
    if (units <= 0 || ticksPerRun <= 0) return null;
    if (direction == TradeDirection.sell) {
      if (!_takesFromStore(planet, commodity, units)) return null;
    }
    final job = TradeJob(
      id: jobId,
      playerId: playerId,
      planetId: planet.id,
      portSectorId: portSectorId,
      commodity: commodity,
      direction: direction,
      unitsTotal: units,
      ticksPerRun: ticksPerRun,
      unitPrice: unitPrice,
      unitsPerRun: unitsPerRun,
      orderId: orderId,
      escrowed: escrowed,
    );
    planet.tradeJobs.add(job);
    return job;
  }

  /// Cancels one in-flight job by id. A buy refund is the caller's business
  /// (it paid up front); a sell returns the undelivered remainder to the store.
  ///
  /// Returns true when a job was removed.
  static bool cancel(Planet planet, String jobId) {
    final index = planet.tradeJobs.indexWhere((j) => j.id == jobId);
    if (index < 0) return false;
    final job = planet.tradeJobs.removeAt(index);
    if (job.direction == TradeDirection.sell && job.unitsRemaining > 0) {
      planet.deposit(job.commodity, job.unitsRemaining);
    }
    return true;
  }

  /// Advances every job in [universe] by one tick.
  ///
  /// Returns the loads that landed this tick, keyed by job id. A job stays
  /// listed until its final run lands — removing it on the first partial
  /// delivery would strand the remainder and report the order complete early.
  static Map<String,
          ({Planet planet, TradeJob job, int units, TradeDirection direction})>
      advanceAll(List<Sector> universe) {
    final landed = <String,
        ({Planet planet, TradeJob job, int units, TradeDirection direction})>{};

    for (final sector in universe) {
      for (final planet in sector.planets) {
        if (planet.tradeJobs.isEmpty) continue;

        // Iterate a copy: a job that completes is removed from the planet,
        // and mutating a list while walking it skips entries.
        for (final job in List<TradeJob>.from(planet.tradeJobs)) {
          final units = job.advance();
          if (units <= 0) continue;

          _applyLanding(planet, job, units);
          if (job.isComplete) {
            planet.tradeJobs.remove(job);
          }
          landed[job.id] = (
            planet: planet,
            job: job,
            units: units,
            direction: job.direction,
          );
        }
      }
    }

    return landed;
  }

  /// Pure port selection: nearest first, split across ports when one cannot
  /// absorb the order.
  ///
  /// No mutation — no jobs, no port stock, no credits. The caller decides
  /// what to do with the shares ([createOrder] is the order path). Pure so
  /// the Port Report and the order path cannot disagree about who can trade.
  ///
  /// A port qualifies only when it actually trades the commodity in the
  /// needed direction with stock on the shelf: a buy needs `sells()` plus
  /// `supply`, a sell needs `buys()` plus `demand`. Capacity is the live
  /// quantity, not the max — a reservation against a cap nobody holds is a
  /// promise the port cannot keep.
  static TradePlan plan({
    required List<Sector> universe,
    required Planet planet,
    required String commodity,
    required TradeDirection direction,
    required int volume,
  }) {
    if (volume <= 0) {
      return TradePlan(
          allocations: const [], unitsRequested: volume, unitsAllocated: 0);
    }
    final homeId = _sectorOf(universe, planet.id);
    if (homeId == null) {
      return TradePlan(
          allocations: const [], unitsRequested: volume, unitsAllocated: 0);
    }

    // One BFS pass answers every distance query out of the world's sector.
    final parents = PathfindingService.bfsParents(universe, homeId);
    final candidates = <({int sectorId, int hops, int capacity, int price})>[];
    for (final sector in universe) {
      final port = sector.port;
      if (port == null || port.isDestroyed) continue;
      final int capacity;
      final int price;
      if (direction == TradeDirection.buy) {
        if (!port.sells(commodity)) continue;
        capacity = port.getSupply(commodity);
        if (capacity <= 0) continue;
        price = port.getEffectiveSellPrice(commodity).round();
      } else {
        if (!port.buys(commodity)) continue;
        capacity = port.getDemand(commodity);
        if (capacity <= 0) continue;
        price = port.getEffectiveBuyPrice(commodity).round();
      }
      final hops = sector.id == homeId
          ? 0
          : PathfindingService.distanceInTree(parents, sector.id);
      if (hops == null) continue;
      candidates.add(
          (sectorId: sector.id, hops: hops, capacity: capacity, price: price));
    }

    // Nearest first; sector id breaks ties so the order is deterministic
    // rather than input-order dependent.
    candidates.sort((a, b) {
      final byHops = a.hops.compareTo(b.hops);
      return byHops != 0 ? byHops : a.sectorId.compareTo(b.sectorId);
    });

    var remaining = volume;
    var allocated = 0;
    final shares = <TradeAllocation>[];
    for (final c in candidates) {
      if (remaining <= 0) break;
      final take = c.capacity < remaining ? c.capacity : remaining;
      if (take <= 0) continue;
      shares.add(TradeAllocation(
        portSectorId: c.sectorId,
        units: take,
        hops: c.hops,
        ticksPerRun: c.hops <= 0 ? 1 : c.hops * ticksPerHop,
        unitPrice: c.price,
      ));
      remaining -= take;
      allocated += take;
    }
    return TradePlan(
        allocations: shares, unitsRequested: volume, unitsAllocated: allocated);
  }

  /// Plans, reserves, and places a paid order: the full T5 transaction in one
  /// call, so the screen cannot half-implement it.
  ///
  /// Each share is reserved at its port ([reserveShare]) and then created;
  /// a share whose reservation fails is shortfall, not a job. Sell volume is
  /// clamped to the store first, so creation cannot fail mid-loop and strand
  /// a reservation. Returns the order id (one request, one row), the jobs,
  /// the credits that changed hands with ports, the units placed, the
  /// shortfall, and every port sector touched (for the caller's write-back).
  ///
  /// This replaced `planAndCreate`, which is deleted rather than kept beside
  /// it: that path created sell jobs (spending planet goods) without ever
  /// reserving the port side, manufacturing value from nothing, and two order
  /// paths sharing `create` is how they disagree. One seam.
  static ({
    String orderId,
    List<TradeJob> jobs,
    int spent,
    int placedUnits,
    int shortfall,
    List<int> portSectorIds,
  }) createOrder({
    required Planet planet,
    required List<Sector> universe,
    required String playerId,
    required String commodity,
    required TradeDirection direction,
    required int volume,
    required String actorFaction,
  }) {
    final clamped = direction == TradeDirection.sell
        ? (volume < planet.storedFor(commodity)
            ? volume
            : planet.storedFor(commodity))
        : volume;
    final planResult = plan(
        universe: universe,
        planet: planet,
        commodity: commodity,
        direction: direction,
        volume: clamped);
    final orderId = const Uuid().v4();
    final jobs = <TradeJob>[];
    final touched = <int>{};
    var spent = 0;
    var placedUnits = 0;
    for (final share in planResult.allocations) {
      final reservation = reserveShare(
        universe: universe,
        share: share,
        commodity: commodity,
        direction: direction,
        actorFaction: actorFaction,
      );
      if (reservation == null) continue;
      final job = create(
        planet: planet,
        playerId: playerId,
        portSectorId: share.portSectorId,
        commodity: commodity,
        direction: direction,
        units: share.units,
        ticksPerRun: share.ticksPerRun,
        unitPrice: share.unitPrice,
        unitsPerRun: freighterHold,
        orderId: orderId,
        escrowed: reservation.escrowed,
      );
      if (job == null) {
        // Unreachable: sell volume was clamped to the store above and buy
        // creation cannot fail — but a stranded reservation (paid for, no
        // job) is worse than dead code, so release rather than trust it.
        releaseReservation(
          universe: universe,
          portSectorId: share.portSectorId,
          commodity: commodity,
          direction: direction,
          units: share.units,
          unitPrice: share.unitPrice,
          escrowed: reservation.escrowed,
        );
        continue;
      }
      spent += reservation.value;
      placedUnits += share.units;
      touched.add(share.portSectorId);
      jobs.add(job);
    }
    return (
      orderId: orderId,
      jobs: jobs,
      spent: spent,
      placedUnits: placedUnits,
      shortfall: clamped - placedUnits,
      portSectorIds: touched.toList(),
    );
  }

  /// Cancels a whole order — every share placed by one request — by order id
  /// (or, for pre-grouping jobs with none, by job id).
  ///
  /// Releases each share's unlanded remainder to its port, returns sell goods
  /// to the store, and reports the buy refund owed to the pilot plus every
  /// port sector touched. Delivered runs stay delivered on both sides.
  static ({int refund, List<int> portSectorIds}) cancelOrder(
    Planet planet,
    List<Sector> universe,
    String orderId,
  ) {
    final group = planet.tradeJobs
        .where((j) => j.orderId == orderId || j.id == orderId)
        .toList();
    var refund = 0;
    final touched = <int>{};
    for (final job in group) {
      refund += refundFor(job);
      releaseShare(universe, job);
      touched.add(job.portSectorId);
      cancel(planet, job.id);
    }
    return (refund: refund, portSectorIds: touched.toList());
  }

  static int? _sectorOf(List<Sector> universe, String planetId) {
    for (final sector in universe) {
      for (final world in sector.planets) {
        if (world.id == planetId) return sector.id;
      }
    }
    return null;
  }

  /// Reserves one planned share against its port: the paid order owns the
  /// goods, not the race for them.
  ///
  /// Buy takes `supply` off the shelf and pays the port; sell takes `demand`
  /// off the book and escrows the payout from `portCredits` (clamped at 0,
  /// the player-port sell convention — a port can go broke paying). The
  /// port's object is replaced via `copyWith`; the sector list itself is the
  /// caller's to save. Records the trade in the session metrics at the live
  /// price, like a player-port trade does.
  ///
  /// Returns the nominal value plus what the pool actually moved, or null
  /// when the port can no longer honor the share (gone, destroyed, or stock
  /// moved since the plan). The caller skips null shares — a reservation
  /// that cannot be made is shortfall, not a job.
  ///
  /// `value` and `escrowed` differ exactly when the pool cannot cover the
  /// order: the pilot still pays (buy) or earns (sell landing) the nominal
  /// price — the player-port convention — but only `escrowed` left the pool,
  /// and only `escrowed` comes back on release. Releasing the nominal figure
  /// instead mints the difference on every reserve-then-cancel against a
  /// cash-poor port.
  static ({int value, int escrowed})? reserveShare({
    required List<Sector> universe,
    required TradeAllocation share,
    required String commodity,
    required TradeDirection direction,
    required String actorFaction,
  }) {
    Sector? sector;
    for (final s in universe) {
      if (s.id == share.portSectorId) {
        sector = s;
        break;
      }
    }
    final port = sector?.port;
    if (sector == null || port == null || port.isDestroyed) return null;
    final value = share.units * share.unitPrice;
    if (direction == TradeDirection.buy) {
      if (!port.sells(commodity) || port.getSupply(commodity) < share.units) {
        return null;
      }
      sector.port = port.copyWith(
        supply: {
          ...port.supply,
          commodity: port.getSupply(commodity) - share.units
        },
        portCredits: port.portCredits + value,
      );
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: share.units,
        credits: value,
        actorFaction: actorFaction,
        isPlayer: true,
        isBuy: true,
      );
      return (value: value, escrowed: value);
    } else {
      if (!port.buys(commodity) || port.getDemand(commodity) < share.units) {
        return null;
      }
      // What actually left the pool: the rest was never there to escrow.
      final escrowed =
          value < port.portCredits ? value : port.portCredits.toInt();
      sector.port = port.copyWith(
        demand: {
          ...port.demand,
          commodity: port.getDemand(commodity) - share.units
        },
        portCredits: port.portCredits - escrowed,
      );
      EconomyMetrics.global.recordTrade(
        commodity: commodity,
        units: share.units,
        credits: value,
        actorFaction: actorFaction,
        isPlayer: true,
        isBuy: false,
      );
      return (value: value, escrowed: escrowed);
    }
  }

  /// Credits the pilot is owed for cancelling [job]: the undelivered remainder
  /// of a buy (paid up front). A sell refunds goods, not credits — see
  /// [cancel], which returns those to the store.
  static int refundFor(TradeJob job) => job.direction == TradeDirection.buy
      ? job.unitsRemaining * job.unitPrice
      : 0;

  /// Releases a cancelled job's reservation back to its port: stock returns
  /// to the shelf and escrowed credits move back.
  ///
  /// Only the *unlanded* remainder is released — delivered runs already left
  /// the port for good. Restores the recorded `escrowed` amount exactly and
  /// unclamped: the clamp belongs to the reservation (a pool cannot pay what
  /// it does not hold), not to the release, where re-clamping mints or eats
  /// the difference whenever another reservation moved the pool meanwhile.
  /// A negative pool after a buy release means other reservations are holding
  /// its money, not that money vanished — the books balance across the port,
  /// and the next purchase refills it. No-op when the port is gone.
  ///
  /// Pre-accounting jobs carry no recorded escrow and fall back to the
  /// nominal remainder, which is the pre-fix behavior (and its mint risk,
  /// confined to jobs already in flight).
  static void releaseShare(List<Sector> universe, TradeJob job) {
    if (job.unitsRemaining <= 0) return;
    releaseReservation(
      universe: universe,
      portSectorId: job.portSectorId,
      commodity: job.commodity,
      direction: job.direction,
      units: job.unitsRemaining,
      unitPrice: job.unitPrice,
      escrowed: job.escrowed,
    );
  }

  /// Returns a raw reservation to its port without needing the job object.
  ///
  /// The primitive [releaseShare] and the order-creation fallback share, so
  /// there is exactly one place that knows how a reservation unwinds. A null
  /// `escrowed` is the legacy path: the nominal value, unclamped, as before.
  static void releaseReservation({
    required List<Sector> universe,
    required int portSectorId,
    required String commodity,
    required TradeDirection direction,
    required int units,
    required int unitPrice,
    int? escrowed,
  }) {
    Sector? sector;
    for (final s in universe) {
      if (s.id == portSectorId) {
        sector = s;
        break;
      }
    }
    final port = sector?.port;
    if (sector == null || port == null || port.isDestroyed) return;
    if (units <= 0) return;
    final giveBack = (escrowed ?? units * unitPrice).toDouble();
    if (direction == TradeDirection.buy) {
      sector.port = port.copyWith(
        supply: {...port.supply, commodity: port.getSupply(commodity) + units},
        portCredits: port.portCredits - giveBack,
      );
    } else {
      sector.port = port.copyWith(
        demand: {...port.demand, commodity: port.getDemand(commodity) + units},
        portCredits: port.portCredits + giveBack,
      );
    }
  }

  static void _applyLanding(Planet planet, TradeJob job, int units) {
    if (job.direction == TradeDirection.buy) {
      planet.deposit(job.commodity, units);
    } else {
      planet.accumulatedRevenue += units * job.unitPrice;
    }
  }

  /// Deducts sell goods from the store at order time. Unknown commodities
  /// (drones have no market row) cannot be sold.
  static bool _takesFromStore(Planet planet, String commodity, int units) {
    // takeStored clamps; an order must be fillable in full or not at all.
    if (planet.storedFor(commodity) < units) return false;
    return planet.takeStored(commodity, units) == units;
  }
}
