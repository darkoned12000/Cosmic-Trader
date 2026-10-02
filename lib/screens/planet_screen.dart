import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/widgets/planet/planet_colony_card.dart';
import 'package:cosmic_trader/widgets/planet/planet_construction_panel.dart';
import 'package:cosmic_trader/widgets/planet/planet_defense_card.dart';
import 'package:cosmic_trader/widgets/planet/planet_info_row.dart';
import 'package:cosmic_trader/widgets/planet/planet_resources_card.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/scan_service.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';

/// One placed market order awaiting confirmation, as data rather than as
/// live job objects: the poll re-reads the universe into a fresh graph, so
/// holding object references would pin the stale copy.
class _PendingShare {
  _PendingShare({
    required this.jobId,
    required this.portSectorId,
    required this.commodity,
    required this.direction,
    required this.units,
    required this.ticksPerRun,
    required this.unitPrice,
  });

  final String jobId;
  final int portSectorId;
  final String commodity;
  final TradeDirection direction;
  final int units;
  final int ticksPerRun;
  final int unitPrice;
}

/// An order this screen placed that the stored universe has not yet
/// confirmed — reconciled in [_syncFromDisk].
class _PendingOrder {
  _PendingOrder({
    required this.planetId,
    required this.orderId,
    required this.shares,
  });

  final String planetId;
  final String orderId;
  final List<_PendingShare> shares;
  int age = 0;
}

/// One tappable request and the port-runs it split into.
///
/// A record would do, but the same four fields are named in three places and
/// named-record field order is part of the type — one transposed pair is a
/// compile error in triplicate. A class names them once.
class _OrderGroup {
  _OrderGroup({
    required this.cancelId,
    required this.direction,
    required this.commodity,
    required this.jobs,
  });

  final String cancelId;
  final TradeDirection direction;
  final String commodity;
  final List<TradeJob> jobs;
}

class PlanetScreen extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  /// Construction-speed preference, passed in rather than read from storage.
  ///
  /// `GameShell` already holds the loaded [GameSettings], so handing the value
  /// down keeps the level-up button synchronous. Reading storage inside the tap
  /// handler made levelling a world depend on an async disk load for no benefit,
  /// and in a widget test that await never completes at all.
  final double constructionTimeScale;

  /// The universe's `planetsPerSector`. A detonation has to reconcile the
  /// sector's stability clock, and that needs the cap — so it is passed in
  /// from the shell like [constructionTimeScale] rather than read from
  /// storage inside the tap handler.
  final int worldCap;

  /// Whether the Transfers panel offers bulk Buy/Sell market orders.
  ///
  /// The Settings → Modules gate, passed in like [constructionTimeScale] so
  /// the screen never reads storage in a tap handler. Off means the controls
  /// are absent, not disabled — a gate that leaks is worse than no gate.
  final bool planetTradingEnabled;

  /// Leaves the Planet tab for the Sector view.
  ///
  /// A detonation ends with the world **gone from the sector**, so there is
  /// nothing left on this tab to show: it would fall back to a neighbour world,
  /// or to an empty sector, and either way the player is left looking at a
  /// screen whose subject they just deleted. Returning them to the sector they
  /// acted on puts the change where it happened — the contents list they will
  /// look for the world in, to confirm it is gone.
  ///
  /// A callback rather than a route push: the tab bar is the shell's business,
  /// and pushing a `SectorView` from here would give the player a *second* one
  /// with its own copy of the universe and its own nav bar.
  final VoidCallback? onExitToSector;

  const PlanetScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
    this.constructionTimeScale = 1.0,
    this.planetTradingEnabled = false,
    this.worldCap = 3,
    this.onExitToSector,
  });

  @override
  State<PlanetScreen> createState() => _PlanetScreenState();
}

class _PlanetScreenState extends State<PlanetScreen> {
  List<Sector> _allSectors = [];
  bool _loading = true;

  /// Live refresh. Colony production runs on the game tick, which mutates the
  /// planet in place — the screen already holds the same object references, so
  /// the numbers were *current* and simply never repainted. That made a live
  /// colony look frozen until you left the tab and came back.
  ///
  /// A poll rather than a push, because the tick service has no notifier for
  /// this and adding one just for this screen is not worth the coupling. Guarded
  /// by [_fingerprint] so `setState` only fires when something actually moved —
  /// the tick is 30s, so the alternative is ~30 pointless rebuilds a minute.
  Timer? _refresh;

  /// Cheap digest of everything on the planet screen that the tick can change.
  int _fingerprint = 0;

  /// True while this screen has a write in flight.
  ///
  /// The reload in [_syncFromDisk] must not run during one, or it can read the
  /// file *before* the screen's own write lands and swap in a stale sector,
  /// visibly undoing the action the player just took.
  bool _writeInFlight = false;

  /// Writes this screen's copy of [sector] to disk, suppressing the poll.
  ///
  /// Every mutating action on this screen has to go through here rather than
  /// calling [UniverseStorage.saveSectors] directly, because the poll and the
  /// write race each other.
  /// Writes one sector back and reports whether it landed.
  ///
  /// The bool is the point. This used to be `Future<void>`, and
  /// `UniverseStorage.saveSectors` has two silent exits — it refuses outright
  /// when the last load failed, and it drops a sector whose id it cannot find in
  /// the file it just read — plus a `catch` that only `debugPrint`s. A caller
  /// that cannot tell "written" from "quietly dropped" cannot tell the player
  /// either, which is how a purchase came to take the credits and show nothing.
  ///
  /// A failure is **remembered**, not just reported: see [_pendingWrite].
  Future<bool> _persist(Sector sector) async {
    _writeInFlight = true;
    try {
      final ok = await UniverseStorage.instance.saveSectors([sector]);
      _pendingWrite = ok ? null : sector;
      return ok;
    } catch (e) {
      debugPrint('[PlanetScreen] persist failed: $e');
      _pendingWrite = sector;
      return false;
    } finally {
      _writeInFlight = false;
    }
  }

  /// Writes several sectors back and reports whether they landed.
  ///
  /// The multi-sector counterpart to [_persist]: a market order mutates the
  /// world's sector *and* every port sector that fills it, and persisting
  /// only the first would strand the reservations — paid for, never written,
  /// resurrected on the next load.
  Future<bool> _persistAll(List<Sector> sectors) async {
    _writeInFlight = true;
    try {
      final ok = await UniverseStorage.instance.saveSectors(sectors);
      if (ok) {
        _pendingWrite = null;
        _pendingWriteSectors = null;
      } else {
        _pendingWriteSectors = sectors;
      }
      return ok;
    } catch (e) {
      debugPrint('[PlanetScreen] persistAll failed: $e');
      _pendingWriteSectors = sectors;
      return false;
    } finally {
      _writeInFlight = false;
    }
  }

  /// Which world in this sector the screen is showing.
  ///
  /// `null` means "the first one", which is the right default for a
  /// single-world sector and the only sane fallback before the universe loads.
  /// A sector can hold up to `planetsPerSector` worlds, and the screen can only
  /// show one at a time, so this is state the player controls.
  String? _selectedPlanetId;

  /// A sector whose last write did **not** land, kept so the 1-second refresh
  /// cannot revert it. Null means disk agrees with this screen.
  ///
  /// This is the mitigation for `saveSectors`'s silent failure modes, not a
  /// substitute for them: a retry is attempted on every refresh, so a transient
  /// refusal self-heals, and the player is told when it does not.
  Sector? _pendingWrite;

  /// Sectors from a multi-sector write (a market order touches the world's
  /// sector *and* every port sector that fills it) that did not land.
  ///
  /// Same contract as [_pendingWrite]: retried on every refresh until disk
  /// agrees, and the refresh keeps this screen's copies while any of it is
  /// outstanding.
  List<Sector>? _pendingWriteSectors;

  /// Withdrawals this screen made that the stored universe has not yet
  /// confirmed — reconciled in [_syncFromDisk] like [_unconfirmedShipments].
  ///
  /// The tick loads the whole universe, works it for seconds, then writes it
  /// back. A withdrawal landing inside that window is overwritten by a
  /// snapshot taken before it existed: the treasury jumps back to its
  /// pre-withdrawal value and the same credits can be withdrawn again — an
  /// infinite-money glitch with no error anywhere. Reproduced in
  /// `test/planet_revenue_withdrawal_test.dart` with a stale write-back.
  ///
  /// Held as intent (which world, how much left, what it held at dispatch)
  /// and re-asserted onto each fresh read until the stored value drops below
  /// its pre-withdrawal figure — which proves the deduction survived. The
  /// fixed amount cannot eat legitimate earnings: it subtracts what left and
  /// never zeroes, so a sale landing meanwhile stays in the treasury. The
  /// pilot is credited exactly once, in the tap handler, never here.
  final List<({String planetId, int withdrawn, int revenueAtDispatch})>
      _unconfirmedWithdrawals = [];

  bool _hasPendingWithdrawal(String planetId) =>
      _unconfirmedWithdrawals.any((w) => w.planetId == planetId);

  /// Orders this screen placed that the stored universe has not yet
  /// confirmed — reconciled in [_syncFromDisk].
  ///
  /// The withdraw intent above closes the money glitch; this closes the
  /// order side of the same race: a tick snapshot taken before the order
  /// existed overwrites it, leaving paid-for jobs that never were (the
  /// likely true story behind "credits gone, no jobs"). Unlike withdrawals
  /// the re-dispatch is bounded: a missing share is re-created only while
  /// the order is younger than [_orderConfirmPolls] polls, because no share
  /// can legitimately complete inside that window (one run is at least one
  /// 30-second tick; the window is ~8 seconds) — so a missing job is
  /// clobbered, never landed. Past the bound the order is assumed landed
  /// and logged, because re-creating blindly could duplicate goods.
  final List<_PendingOrder> _unconfirmedOrders = [];

  /// Polls a placed order stays guarded. See [_unconfirmedOrders] for why
  /// the bound is also the correctness argument.
  static const int _orderConfirmPolls = 8;

  /// Settled withdrawals still being watched for a late stale write-back.
  ///
  /// Settling on the first confirming poll proves the deduction survived the
  /// one snapshot that was read — not that no older, still-in-flight tick
  /// pass will land afterwards and restore it (a pass can run seconds while
  /// the poll is 1s). Each entry carries the job digest at settle time: a
  /// treasury climbing back with an unchanged digest cannot be earnings (a
  /// sale landing always moves a countdown), so it is a restore and the
  /// intent is re-registered. A changed digest means real landings happened
  /// meanwhile — accept, possibly wrongly if a restore raced the same pass,
  /// which is the documented residual. Bounded by age: entries expire after
  /// [_withdrawWatchPolls] polls rather than accumulating forever.
  final List<
      ({
        String planetId,
        int withdrawn,
        int revenueAtDispatch,
        int jobDigest,
        int age
      })> _watchingWithdrawals = [];

  /// Polls a settled withdrawal stays watched. Covers any tick pass that was
  /// already in flight at settle time: passes are seconds-long, polls are
  /// 1s, so a stale save lands (or doesn't) well inside the window.
  static const int _withdrawWatchPolls = 10;

  /// Which jobs were in flight, as one int. A sale landing always moves a
  /// countdown or removes a finished job, so an unchanged digest across a
  /// treasury increase rules earnings out.
  int _jobDigest(Planet planet) {
    var digest = planet.tradeJobs.length;
    for (final j in planet.tradeJobs) {
      digest = Object.hash(digest, j.id, j.unitsRemaining, j.ticksRemaining);
    }
    return digest;
  }

  /// Shipments this screen dispatched that the stored universe has not yet
  /// confirmed **landed** — see the reconciliation in [_syncFromDisk].
  ///
  /// Held as the *intent* (which world, how many, and the population it started
  /// from) rather than as a snapshot of the sector, because the tick legitimately
  /// owns the rest of that sector: re-writing a whole stale sector would revert
  /// its port restock and any NPC that moved through. Re-dispatching onto the
  /// freshly-read world touches only the one field the player actually changed.
  ///
  /// Settled by the **population** moving, not by a single sighting of
  /// `colonistsInTransit > 0`. The first version cleared the intent as soon as
  /// disk agreed once, which left the shipment unguarded for the rest of its
  /// flight — and the clobber that matters happens *after* the write, when the
  /// tick finishes its pass. A guard that stops guarding one tick too early is
  /// not a guard.
  final List<({String planetId, int headcount, int populationAtDispatch})>
      _unconfirmedShipments = [];

  /// The world to display: the selection if it still exists, else the first
  /// living one, else the first of any.
  ///
  /// Falls back rather than going blank. A world can be destroyed or removed
  /// while its id is selected, and a screen that renders nothing at all is a
  /// far worse outcome than one that quietly shows a neighbour.
  Planet? _resolvePlanet(Sector? sector) =>
      sector == null ? null : _selectFrom(sector.planets);

  /// Picks the world to display out of [planets], honouring the selection.
  Planet? _selectFrom(List<Planet> planets) {
    if (planets.isEmpty) return null;
    final id = _selectedPlanetId;
    if (id != null) {
      for (final p in planets) {
        if (p.id == id) return p;
      }
    }
    return planets.where((p) => !p.isDestroyed).isNotEmpty
        ? planets.firstWhere((p) => !p.isDestroyed)
        : planets.first;
  }

  static int _fingerprintOf(Planet? p) {
    if (p == null) return 0;
    // Trade jobs contribute their countdowns, so a landing run repaints the
    // job rows without anything calling setState when the tick advances them.
    //
    // A run that resolves with nothing delivered still moves `unitsRemaining`
    // (the units are consumed), so the units/ticks pair repaints on a loss
    // too — but the *lost* figure is separate state, and a ledger entry is
    // what the Report reads, so both are folded in here or the notice would
    // appear a second late.
    var jobUnits = 0;
    var jobTicks = 0;
    var jobLost = 0;
    for (final j in p.tradeJobs) {
      jobUnits += j.unitsRemaining;
      jobTicks += j.ticksRemaining;
      jobLost += j.unitsLost;
    }
    // One local rather than three: `Object.hash` takes at most 20 positional
    // arguments, and the 21st is a compile error rather than a silent drop.
    final jobDigest = Object.hash(jobUnits, jobTicks, jobLost);
    final incidentDigest = Object.hash(p.tradeIncidents.length,
        p.tradeIncidents.isEmpty ? 0 : p.tradeIncidents.last.tick);
    return Object.hash(
      p.storedMinerals,
      p.storedOrganics,
      p.storedIndustrial,
      p.storedDrones,
      p.population,
      p.colonistsMinerals,
      p.colonistsOrganics,
      p.colonistsIndustrial,
      p.level,
      p.shield,
      p.hull,
      p.owner,
      // The build countdown, so a running construction shows progress without
      // anything having to call setState when the tick decrements it.
      p.constructionTicksRemaining,
      p.constructionTarget,
      // Same reason, for a shipment in the air. Without these two the transit
      // row is pinned at whatever it read when the order was placed: the
      // countdown would sit at "1m" through the whole flight and the headcount
      // would not clear on arrival, because `population` alone cannot tell a
      // repaint apart from the ordering that is already finished.
      p.colonistsInTransit,
      p.colonistTransitTicks,
      // Same reason, for market orders: revenue lands and countdowns move on
      // the tick's copy, and the rows must follow without a tap.
      p.accumulatedRevenue,
      p.tradeJobs.length,
      jobDigest,
      incidentDigest,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUniverse();
    // Reload from disk rather than fingerprinting a private copy.
    //
    // This screen and [GameTickService] each call `loadUniverse()`, which
    // **parses a fresh object graph every time**. The tick decrements the
    // countdown on *its* copy and saves it; this screen was fingerprinting
    // *its own* copy, which nothing else mutates. So a running build appeared
    // frozen at whatever it was set to, forever, and then vanished on the way
    // out. The same divergence hid every production change made by the tick.
    //
    // Reading every second is affordable next to a tick that already re-reads
    // the whole file every 30s, and it is what makes the progress bar move
    // promptly: the countdown only actually changes once per tick, so this
    // polls for a change and repaints within a second of it happening.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncFromDisk();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Re-reads the universe and swaps in the current sector if it changed.
  ///
  /// Swaps the whole list rather than merging, so the screen holds exactly what
  /// the tick last wrote. Only the selected world's id is carried across, since
  /// a re-parse produces new object identities and would otherwise reset the
  /// selection to slot 0 on every poll.
  Future<void> _syncFromDisk() async {
    if (_writeInFlight) return;

    // **A write we could not land must not be reverted by a read.**
    //
    // Disk is behind memory here: the player made a change, the save silently
    // refused (or threw), and the file still holds the old value. Adopting the
    // fresh read would undo what they just did — which is precisely the reported
    // bug: credits deducted, no panel, and one second later the purchase gone
    // without a word. `saveSectors` has two silent exits and a swallowed
    // `catch`, so this is reachable without anything looking broken.
    //
    // So retry the write, and while it is outstanding, keep our own copy. The
    // refresh resumes the moment a write lands, which is the only condition
    // under which disk is trustworthy again.
    final pending = _pendingWrite;
    if (pending != null) {
      await _persist(pending);
      if (_pendingWrite != null) return;
    }
    final pendingAll = _pendingWriteSectors;
    if (pendingAll != null) {
      await _persistAll(pendingAll);
      if (_pendingWriteSectors != null) return;
    }

    final previousId = _currentSector?.id;
    final List<Sector> fresh;
    try {
      fresh = await UniverseStorage.instance.loadUniverse();
    } catch (_) {
      return; // a transient read failure must not blank the screen
    }
    if (!mounted || fresh.isEmpty) return;
    // A write that started while we were reading wins: the file we just read may
    // predate it, and clobbering it would make a button look inert.
    if (_writeInFlight) return;

    // **A change this screen made must survive the tick's write-back.**
    //
    // `GameTickService` loads the whole universe, runs the NPC pass over the
    // roster (seconds of BFS-heavy work at scale), then writes that snapshot
    // back unconditionally. A recruit landing inside that window is overwritten
    // by a copy taken before it existed — no error, no log, and indistinguishable
    // from the feature never having worked. Reproduced in
    // `test/concurrent_write_clobber_test.dart`.
    //
    // So the screen holds its own intent until the stored universe agrees. If
    // the stored world has the shipment, the intent is settled; if it does not,
    // the shipment is re-dispatched onto the freshly-read world and written
    // again. It converges rather than fighting: the next tick loads what we just
    // wrote, so it cannot clobber the same shipment twice.
    final intent = _unconfirmedShipments;
    if (intent.isNotEmpty) {
      var rewrote = false;
      final settled =
          <({String planetId, int headcount, int populationAtDispatch})>[];
      for (final s in intent) {
        final stored = _planetById(fresh, s.planetId);
        // Gone, or the population has moved: either way there is nothing left to
        // guard. Population is the settle signal because it is what the shipment
        // *becomes* — a single sighting of `colonistsInTransit > 0` only proves
        // the write landed, not that it will survive the tick now in flight.
        if (stored == null || stored.population > s.populationAtDispatch) {
          settled.add(s);
          continue;
        }
        // Still on its way, and the write landed: nothing to do this pass.
        if (stored.colonistsInTransit > 0) continue;
        stored.dispatchColonists(s.headcount);
        final sector = _sectorHolding(fresh, s.planetId);
        if (sector != null) {
          await _persist(sector);
          rewrote = true;
        }
      }
      intent.removeWhere(settled.contains);
      if (rewrote) {
        if (!mounted) return;
        _allSectors = fresh;
        _fingerprint = _fingerprintOf(_resolvePlanetFrom(fresh));
        setState(() {});
        return;
      }
    }

    // **A withdrawal must survive the same write-back.** Same mechanism as
    // above, smaller settle signal: the stored treasury dropping below its
    // pre-withdrawal figure proves the deduction is in the file. Anything at
    // or above it means a stale snapshot overwrote us (or landed on top of
    // us), so the fixed amount is subtracted again — never to zero, so a
    // sale landing in the same window keeps its earnings. Converges because
    // every tick pass starts from a fresh load: the first pass that starts
    // after a re-assert carries it, and the next poll settles.
    //
    // Settling starts a short watch rather than ending the story (see
    // [_watchingWithdrawals]): a still-in-flight stale pass can land after
    // the confirming poll and restore the treasury with no intent left to
    // catch it.
    final withdrawals = _unconfirmedWithdrawals;
    if (withdrawals.isNotEmpty) {
      var rewrote = false;
      final settledW =
          <({String planetId, int withdrawn, int revenueAtDispatch})>[];
      for (final w in withdrawals) {
        final stored = _planetById(fresh, w.planetId);
        // Gone, or the deduction is visible: watch briefly, then let go.
        if (stored == null || stored.accumulatedRevenue < w.revenueAtDispatch) {
          settledW.add(w);
          if (stored != null) {
            _watchingWithdrawals.add((
              planetId: w.planetId,
              withdrawn: w.withdrawn,
              revenueAtDispatch: w.revenueAtDispatch,
              jobDigest: _jobDigest(stored),
              age: 0,
            ));
          }
          continue;
        }
        stored.accumulatedRevenue -= w.withdrawn;
        if (stored.accumulatedRevenue < 0) stored.accumulatedRevenue = 0;
        final sector = _sectorHolding(fresh, w.planetId);
        if (sector != null) {
          await _persist(sector);
          rewrote = true;
        }
      }
      withdrawals.removeWhere(settledW.contains);
      if (rewrote) {
        if (!mounted) return;
        _allSectors = fresh;
        _fingerprint = _fingerprintOf(_resolvePlanetFrom(fresh));
        setState(() {});
        return;
      }
    }

    // The settled-withdrawal watch: a late stale restore re-registers the
    // intent (the pilot was credited once, at the tap — this only moves the
    // treasury back down). Entries expire by age so the list cannot grow.
    if (_watchingWithdrawals.isNotEmpty) {
      final keep = <({
        String planetId,
        int withdrawn,
        int revenueAtDispatch,
        int jobDigest,
        int age
      })>[];
      for (final w in _watchingWithdrawals) {
        final stored = _planetById(fresh, w.planetId);
        if (stored == null || w.age + 1 >= _withdrawWatchPolls) continue;
        if (stored.accumulatedRevenue >= w.revenueAtDispatch &&
            _jobDigest(stored) == w.jobDigest) {
          // Restored with no landing to explain it: guard again.
          _unconfirmedWithdrawals.add((
            planetId: w.planetId,
            withdrawn: w.withdrawn,
            revenueAtDispatch: w.revenueAtDispatch,
          ));
          continue;
        }
        keep.add((
          planetId: w.planetId,
          withdrawn: w.withdrawn,
          revenueAtDispatch: w.revenueAtDispatch,
          jobDigest: _jobDigest(stored),
          age: w.age + 1,
        ));
      }
      _watchingWithdrawals
        ..clear()
        ..addAll(keep);
    }

    // Placed-order confirmation: re-dispatch shares a stale snapshot erased.
    //
    // Presence is the settle signal — every share's job id in the stored
    // planet means the write landed. A missing share younger than
    // [_orderConfirmPolls] polls is re-reserved and re-created under the same
    // job id (no recharge: the pilot already paid), because no share can
    // legitimately complete inside the window — one run is at least one
    // 30-second tick and the window is ~8 seconds — so a missing job is
    // clobbered, never landed. Past the bound the order is assumed landed
    // and logged, since re-creating blindly could duplicate goods the tick
    // already delivered.
    if (_unconfirmedOrders.isNotEmpty) {
      var rewrote = false;
      final keepOrders = <_PendingOrder>[];
      for (final o in _unconfirmedOrders) {
        final stored = _planetById(fresh, o.planetId);
        if (stored == null) continue;
        final have = {for (final j in stored.tradeJobs) j.id};
        final missing = [
          for (final s in o.shares)
            if (!have.contains(s.jobId)) s
        ];
        if (missing.isEmpty) continue;
        if (o.age + 1 >= _orderConfirmPolls) {
          ActionLogProvider.global.warning(
            'Order ${o.orderId} unconfirmed after $_orderConfirmPolls polls — '
            'assuming its runs landed.',
          );
          continue;
        }
        final touched = <Sector>[];
        final homeSector = _sectorHolding(fresh, o.planetId);
        if (homeSector != null) touched.add(homeSector);
        for (final m in missing) {
          final reservation = PlanetTradeService.reserveShare(
            universe: fresh,
            share: TradeAllocation(
              portSectorId: m.portSectorId,
              units: m.units,
              hops: 0,
              ticksPerRun: m.ticksPerRun,
              unitPrice: m.unitPrice,
            ),
            commodity: m.commodity,
            direction: m.direction,
            actorFaction: widget.player.faction.name,
          );
          if (reservation == null) continue;
          final job = PlanetTradeService.create(
            planet: stored,
            playerId: widget.player.id,
            portSectorId: m.portSectorId,
            commodity: m.commodity,
            direction: m.direction,
            units: m.units,
            ticksPerRun: m.ticksPerRun,
            unitPrice: m.unitPrice,
            unitsPerRun: PlanetTradeService.freighterHold,
            orderId: o.orderId,
            escrowed: reservation.escrowed,
            jobId: m.jobId,
          );
          if (job == null) {
            PlanetTradeService.releaseReservation(
              universe: fresh,
              portSectorId: m.portSectorId,
              commodity: m.commodity,
              direction: m.direction,
              units: m.units,
              unitPrice: m.unitPrice,
              escrowed: reservation.escrowed,
            );
            continue;
          }
          for (final s in fresh) {
            if (s.id == m.portSectorId && !touched.any((t) => t.id == s.id)) {
              touched.add(s);
            }
          }
        }
        o.age++;
        keepOrders.add(o);
        if (touched.isNotEmpty) {
          await _persistAll(touched);
          rewrote = true;
        }
      }
      _unconfirmedOrders
        ..clear()
        ..addAll(keepOrders);
      if (rewrote) {
        if (!mounted) return;
        _allSectors = fresh;
        _fingerprint = _fingerprintOf(_resolvePlanetFrom(fresh));
        setState(() {});
        return;
      }
    }

    final next = _fingerprintOf(_resolvePlanetFrom(fresh));
    if (next == _fingerprint && previousId == _currentSector?.id) {
      _allSectors = fresh;
      return;
    }
    _fingerprint = next;
    setState(() {
      _allSectors = fresh;
    });
  }

  /// The world with [planetId] anywhere in [all], or null.
  ///
  /// By **id**, not by `planets.first`: a sector holds several worlds and the
  /// one the shipment belongs to is not necessarily slot 0.
  Planet? _planetById(List<Sector> all, String planetId) {
    for (final sector in all) {
      for (final planet in sector.planets) {
        if (planet.id == planetId) return planet;
      }
    }
    return null;
  }

  /// The sector holding [planetId], or null.
  Sector? _sectorHolding(List<Sector> all, String planetId) {
    for (final sector in all) {
      for (final planet in sector.planets) {
        if (planet.id == planetId) return sector;
      }
    }
    return null;
  }

  /// The selected world, resolving against an explicit sector list.
  Planet? _resolvePlanetFrom(List<Sector> all) {
    if (all.isEmpty) return null;
    final sector = all.firstWhere(
      (s) => s.id == widget.player.currentSectorId,
      orElse: () => all.first,
    );
    return _selectFrom(sector.planets);
  }

  Future<void> _loadUniverse() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (mounted) {
        setState(() {
          _allSectors = sectors;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Sector? get _currentSector {
    if (_allSectors.isEmpty) return null;
    return _allSectors.firstWhere(
      (s) => s.id == widget.player.currentSectorId,
      orElse: () => _allSectors.first,
    );
  }

  Future<void> _scanPlanet() async {
    final sector = _currentSector;
    final planet = _resolvePlanet(sector);
    if (sector == null || planet == null) return;

    // The rule lives in [ScanService] so this screen and the sector panel cannot
    // drift into charging different prices for the same act — which is exactly
    // what happened (4 energy here, 1 there, identical result).
    final result = await ScanService.scanPlanet(
      player: widget.player,
      planet: planet,
      onPersist: () => _persist(sector),
    );
    if (!result.performed) return;
    widget.onPlayerUpdate(result.player);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sector = _currentSector;
    final planet = _resolvePlanet(sector);

    if (sector == null || planet == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 64,
                  color: cs.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No planet in this sector.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Travel to a sector with a planet to view it here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!planet.scanned) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: 64,
                  color: cs.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'Planet detected in this sector.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Requires scan to identify.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed:
                      EnergyService.canScan(widget.player) ? _scanPlanet : null,
                  icon: const Icon(Icons.science_rounded),
                  label: Text('Scan Planet (${EnergyService.scanCost} energy)'),
                ),
                if (!EnergyService.canScan(widget.player))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Not enough energy',
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Scanned planet display
    return Scaffold(
      appBar: AppBar(
        title: Text(planet.name),
        forceMaterialTransparency: true,
        // The detonator lives here rather than on the world row because it acts
        // on a *specific* world, and the AppBar is the one place on this screen
        // that is unambiguously about the world being shown. Red because it is
        // the only irreversible control in the game, and greyed rather than
        // hidden when the player has none, so the capability is discoverable
        // before they buy one.
        actions: [
          if (!planet.isDestroyed)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _destroyPlanetButton(cs),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sector.planets.length > 1) ...[
              _buildWorldSelector(sector, planet),
              const SizedBox(height: 12),
            ],
            // Planet header card — info left, image right
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Planet Type: ${planet.planetType}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (planet.isHomeworld) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.amber
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        'HOMEWORLD',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Atmosphere: ${planet.atmosphere}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Status, Colonists, Level, Creator, Owner — the
                              // world's whole situation in one block, so
                              // "whose is this and did I make it" is answerable
                              // without scrolling to the ownership card.
                              PlanetInfoRow('Status', _statusLabel(planet)),
                              PlanetInfoRow(
                                  'Colonists', compact(planet.population)),
                              PlanetInfoRow('Level',
                                  '${planet.level} ${_levelTitle(planet.level)}'),
                              // Blank for a generator-placed world, which is
                              // nearly all of them. Deliberately not a
                              // placeholder like "unknown": nobody made it, and
                              // a word there would imply somebody did.
                              PlanetInfoRow('Creator', planet.creator ?? ''),
                              PlanetInfoRow(
                                'Owner',
                                planet.owner == null
                                    ? 'Unclaimed'
                                    : '${planet.owner!.displayName} '
                                        '(${planet.owner!.name.toUpperCase()})',
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (planet.imagePath != null)
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                planet.imagePath!,
                                height: 100,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 100,
                                  color: cs.surfaceContainerHighest,
                                  child: Center(
                                    child: Icon(
                                        Icons.image_not_supported_rounded,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.3)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Same narrow-width fallback as Transfers / Level Up below. Two
            // halves of a 430px phone leaves each card ~198px, which is enough
            // for the bar but not for the "9.0K / 25.0K" readout beside it —
            // that had to be ellipsised to stop it overflowing, which made a
            // player's own stores unreadable. Stacking gives each card the
            // full width and the readout fits properly.
            LayoutBuilder(
              builder: (context, constraints) {
                final resources = PlanetResourcesCard(
                    planet: planet,
                    cs: cs,
                    onSweep: () => _sweepShipment(planet));
                final defense = PlanetDefenseCard(planet: planet, cs: cs);
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      resources,
                      const SizedBox(height: 12),
                      defense,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: resources),
                    const SizedBox(width: 12),
                    Expanded(child: defense),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            // Not gated on `population > 0`. It used to be, and that made the
            // card *disappear* rather than read as empty — so the two states a
            // player most needs told apart, "no colonists" and "the panel is
            // broken", rendered identically: nothing. It also meant the one
            // world guaranteed to be buying its first shipment was the one world
            // with no colony panel to show the shipment arriving in. Empty state,
            // plainly labelled, is the fix; the card is cheap and always has a
            // Recruit control on it.
            PlanetColonyCard(
                planet: planet,
                cs: cs,
                canAssign: planet.owner == widget.player.faction,
                onAdjust: (t, d) => _adjustWorkforce(planet, t, d)),
            const SizedBox(height: 12),
            // Actions / Management
            _buildActions(planet, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Planet planet, ColorScheme cs) {
    final isOwner = planet.owner == widget.player.faction;

    if (isOwner) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_rounded,
                      size: 18, color: Colors.green.shade400),
                  const SizedBox(width: 8),
                  // Flexible: the faction display name is the only variable
                  // width part of this row, and at 430px it overflowed by
                  // 153px. The icon stays natural and the name ellipsises, so
                  // a long faction name can never push the header off-screen.
                  Expanded(
                    child: Text(
                      'Owned by ${widget.player.faction.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green.shade400,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Transfers and the level-up panel sit side by side on a wide
              // screen and stack on a narrow one.
              //
              // Pre-existing overflow, found by rendering this screen at 430px
              // rather than by reading it: two `Expanded` halves leave each
              // panel ~198px, and a transfer row needs its 80px label, the
              // stored/max readout, and two buttons. That overflowed by up to
              // 84px. It is the same `LayoutBuilder` fallback the faction
              // rankings screen uses for the same reason.
              LayoutBuilder(
                builder: (context, constraints) {
                  final transfers = _buildTransfersSection(planet, cs);
                  final levelUp = _buildLevelUpSection(planet, cs);
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        transfers,
                        const SizedBox(height: 12),
                        levelUp,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: transfers),
                      const SizedBox(width: 12),
                      Expanded(child: levelUp),
                    ],
                  );
                },
              ),
              // Bulk orders against live port markets. Gated, not disabled:
              // with the Modules toggle off this whole block is absent.
              if (widget.planetTradingEnabled) ...[
                const SizedBox(height: 12),
                _buildMarketSection(planet, cs),
              ],
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        if (planet.owner == null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _claimPlanet(planet),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Claim'),
            ),
          ),
        if (planet.owner == null) const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              ActionLogProvider.global.info('Attacking ${planet.name}...');
            },
            icon: const Icon(Icons.local_fire_department_rounded, size: 18),
            label: const Text('Attack'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }

  final Map<String, int> _transferAmounts = {
    'colonists': 10,
    'minerals': 10,
    'organics': 10,
    'industrial': 10,
    'drones': 10,
  };

  int _storedFor(String type, Planet planet) {
    switch (type) {
      case 'minerals':
        return planet.storedMinerals;
      case 'organics':
        return planet.storedOrganics;
      case 'industrial':
        return planet.storedIndustrial;
      case 'drones':
        return planet.storedDrones;
      case 'colonists':
        return planet.population;
      default:
        return 0;
    }
  }

  int _maxFor(String type, Planet planet) {
    if (type == 'colonists') return planet.colonistMax;
    return planet.capFor(type);
  }

  Widget _buildTransfersSection(Planet planet, ColorScheme cs) {
    const resourceTypes = [
      'minerals',
      'organics',
      'industrial',
      'drones',
      'colonists'
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfers',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final type in resourceTypes) ...[
              _transferRow(type, planet, cs),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// BFS hops from the faction's colonist source to this planet, cached per
  /// sector so a rebuild does not re-walk the graph on every row.
  int? _cachedHops;
  ColonistSource? _cachedSource;

  ColonistSource _sourceFor() => _cachedSource ??=
      ColonistSupply.sourceFor(_allSectors, widget.player.faction);

  int _hopsFor(Sector sector) => _cachedHops ??=
      ColonistSupply.hopsBetween(_allSectors, _sourceFor().sectorId, sector.id);

  /// Price per colonist from the faction's capital. Colonists are the **only**
  /// transfer that has a price any more.
  ///
  /// The flat resource table that used to live here is **deleted rather than
  /// retuned**. It priced goods that no longer change hands: `Dep` and `Wdr`
  /// now move units between the hold and the store, and a per-unit credit rate
  /// for a haul that costs nothing is an invented number on screen. Worse, it
  /// gave the same minerals three different values within one screen — 5 cr on
  /// this row, 42.5 cr on the Collect shipment pool, and a live demand-driven
  /// price at any port.
  int _priceFor(String type, Sector sector) =>
      ColonistSupply.pricePerColonist(_hopsFor(sector),
          orphan: _sourceFor().isOrphan);

  /// The explanation behind the colonists row's amber info bubble.
  ///
  /// Colonists are the one transfer whose price is not a flat rate, and all
  /// three reasons for it used to be crammed into the price cell — which made
  /// the row read `5.4K / 200.0K  405cr · 9 hops from Vionis`. That is a
  /// sentence, not a number, and on a phone it ellipsised away the part that
  /// explains *why* the price is what it is.
  String _colonistTooltipText(Sector sector, int shipmentEnergy) {
    final source = _sourceFor();
    final hops = _hopsFor(sector);
    final price =
        ColonistSupply.pricePerColonist(hops, orphan: source.isOrphan);
    final buffer = <String>[
      'Colonists ship from ${source.label}.',
      '$price cr each, $hops ${hops == 1 ? 'hop' : 'hops'} away.',
      'Each shipment costs $shipmentEnergy energy, whatever the size — so send '
          'them in one lot rather than many.',
    ];
    if (source.isOrphan) {
      buffer.add(
        'With no capital under your control you are buying from Terra Prime at '
        'an exile rate. Recapture your homeworld to end it.',
      );
    }
    return buffer.join('\n\n');
  }

  Widget _transferRow(String type, Planet planet, ColorScheme cs) {
    final sector = _currentSector;
    final stored = _storedFor(type, planet);
    final max = _maxFor(type, planet);
    final amount = _transferAmounts[type] ?? 10;
    final isColonists = type == 'colonists';

    // Colonists still ship through ColonistSupply: distance-priced credits plus
    // a per-shipment energy cost, and the physical cargo half is still to come.
    // Everything else is now a plain haul between the hold and the store.
    final pricePerUnit =
        isColonists && sector != null ? _priceFor(type, sector) : 0;
    final depositCost = amount * pricePerUnit;
    final shipmentEnergy = sector == null
        ? 0
        : ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    final inHold = isColonists ? 0 : (widget.player.cargo[type] ?? 0);
    final holdSpace = widget.player.maxCargo - widget.player.cargoUsed;
    // The most that can move in one action: enough goods in the right place, and
    // enough room on the receiving side. Shared by the `+` ceiling and the Max
    // button so the number on screen is the number that will be transferred.
    final storeRoom = max - stored;
    final maxMovable = isColonists
        ? 0
        : (inHold < storeRoom ? inHold : storeRoom).clamp(0, holdSpace);

    // A deposit needs units in the hold and any room on the world; a withdrawal
    // needs units on the world and any free hold space. Both are gated on
    // "is this possible **at all**", not on the current stepper amount.
    //
    // Gating on the amount made the buttons lie. With 5 free slots and a stepper
    // reading 10, `10 <= 5` is false, so a player with 1,000 minerals on a
    // nearby world and a nearly-empty hold saw a dead button and no way to make
    // the one load that would have fitted. The handlers clamp to
    // `min(stored, space)`, so the button only has to say "yes, some of this
    // can move".
    final canDeposit = isColonists
        ? (widget.player.credits >= depositCost &&
            stored + planet.colonistsInTransit < max &&
            widget.player.energy >= shipmentEnergy)
        : (inHold > 0 && stored < max);
    final canWithdraw = !isColonists && stored > 0 && holdSpace > 0;
    final label = type[0].toUpperCase() + type.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  // Colonists are the only row whose price is not a flat rate,
                  // and the reasons are worth explaining rather than cramming
                  // into the row. The source, the distance and the per-shipment
                  // fuel cost all live here instead.
                  if (type == 'colonists' && sector != null)
                    Tooltip(
                      message: _colonistTooltipText(sector, shipmentEnergy),
                      waitDuration: const Duration(milliseconds: 400),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 12,
                          color: Colors.amber.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            // Both trailing readouts flex and ellipsise. The colonist row grew a
            // hop count and overflowed by 8.6px at 430px, which is the same
            // two-natural-width-Texts-in-a-Row trap that has bitten this screen
            // three times now.
            Flexible(
              child: Text(
                '${compact(stored)} / ${compact(max)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                // For resources this used to read a price, which was a lie: no
                // credits change hands on an unload or a load. What the player
                // actually needs to see is how much of the goods is already in
                // the hold, because that is what bounds a deposit.
                isColonists ? '${pricePerUnit}cr' : 'hold ${compact(inHold)}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _miniStepper(Icons.remove_rounded, () {
              setState(() {
                _transferAmounts[type] = (amount - 10).clamp(1, max);
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '$amount',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _miniStepper(Icons.add_rounded, () {
              // Bounded by whatever can actually move, so the figure is always
              // actionable on at least one button rather than reachable on
              // neither. Colonists have their own ceiling: they cost credits.
              final int ceiling;
              if (isColonists) {
                final byCredits = widget.player.credits ~/
                    (pricePerUnit > 0 ? pricePerUnit : 1);
                ceiling = (storeRoom < byCredits ? storeRoom : byCredits)
                    .clamp(0, max);
              } else {
                ceiling = maxMovable;
              }
              final next = amount + 10 > ceiling ? ceiling : amount + 10;
              if (next > amount) {
                setState(() => _transferAmounts[type] = next.clamp(1, max));
              }
            }),
            // One action instead of a held button's worth of taps. Sets the
            // amount rather than transferring directly, so the player can see
            // what is about to move and then press Unload or Load.
            if (!isColonists && maxMovable > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 2),
                child: InkWell(
                  onTap: () => _setTransferMax(type, maxMovable),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Max',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (isColonists)
              _miniActionButton(
                  'Recruit', Colors.green, canDeposit && depositCost > 0, () {
                _recruitColonists(type, amount, depositCost, planet);
              })
            else ...[
              // Labels say which way the goods move, because "Dep"/"Wdr" is
              // ambiguous about whether it is the planet or the ship that is
              // being unloaded. The icons carry the same information.
              _miniActionButton('Unload', Colors.blue, canDeposit, () {
                _depositToPlanet(type, amount, planet);
              }),
              const SizedBox(width: 4),
              _miniActionButton('Load', Colors.orange, canWithdraw, () {
                _withdrawToShip(type, amount, planet);
              }),
            ],
          ],
        ),
      ],
    );
  }

  /// A compact `-`/`+` control that repeats while held.
  ///
  /// Press-and-hold is not a convenience here, it is the difference between
  /// setting a transfer amount and giving up on it. Absorbing a colony's
  /// production into a hold takes hundreds of taps of `+10`, and a player who
  /// cannot do it will simply not use the feature — which is the same failure as
  /// the feature not existing.
  ///
  /// The repeat rate is the same 400ms delay / 80ms interval as
  /// `lib/widgets/hold_button.dart`, but this is a bare icon rather than a
  /// labelled button, and `HoldButton` is a `SizedBox(height: 36)` with a
  /// `FittedBox` label — wrong shape for a 24px square inside a dense row.
  Widget _miniStepper(IconData icon, VoidCallback onPressed) {
    return _HoldRepeatIcon(
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14),
      ),
    );
  }

  /// Sets a transfer row's amount to everything that can actually move.
  ///
  /// Bounded by the *same* constraint the button will apply, so the number on
  /// screen is the number that will be transferred: the smaller of what is in
  /// the hold and what has room on the world, and never more than the free
  /// cargo space. Pressing it twice is harmless, which is the point.
  void _setTransferMax(String type, int max) {
    setState(() => _transferAmounts[type] = max < 1 ? 1 : max);
  }

  // ── Market orders (T5) ─────────────────────────────────────────────

  /// Order sizes per commodity. Steps of 100 from 100: a Citadel tier costs
  /// tens of thousands, so the ±10 hauling step would be 8,000 taps to the
  /// same place.
  final Map<String, int> _marketAmounts = {
    'minerals': 1000,
    'organics': 1000,
    'industrial': 1000,
  };

  static const _marketCommodities = ['minerals', 'organics', 'industrial'];

  TradePlan _marketPlan(
          String type, TradeDirection dir, int volume, Planet planet) =>
      PlanetTradeService.plan(
        universe: _allSectors,
        planet: planet,
        commodity: type,
        direction: dir,
        volume: volume,
      );

  Widget _buildMarketSection(Planet planet, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Market',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Bulk orders against live port markets. The port sends its own '
              'freighter — you pay credits and time, not cargo space.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            _buildTreasuryVault(planet, cs),
            const SizedBox(height: 8),
            for (final type in _marketCommodities) ...[
              _marketRow(type, planet, cs),
              const SizedBox(height: 6),
            ],
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Open orders',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                // One button rather than one per order: the log line lives in a
                // 200-entry ring the player may have scrolled past, and a
                // per-row Report would be a third control on a row that
                // already carries a Cancel and a countdown bar. The history
                // belongs to the world, so it is read from the world.
                _miniActionButton(
                    'Report',
                    Colors.teal,
                    planet.tradeIncidents.isNotEmpty,
                    () => _showTradeReport(planet),
                    key: const Key('market-report'),
                    disabledReason: 'No shipments yet'),
              ],
            ),
            const SizedBox(height: 6),
            if (planet.tradeJobs.isEmpty)
              Text(
                'No open orders yet.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            // One row per request, not per port-run: a split order is one
            // job with one Cancel, so N taps always read as N rows.
            for (final group in _orderGroups(planet)) ...[
              _marketOrderRow(planet, group, cs),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// The world's freight ledger: finished orders, then the last
  /// [Planet.tradeIncidentHistory] resolved runs.
  ///
  /// Two sections because they answer two different questions. **Orders** is
  /// the one a player asks an hour later — "what did that 80,000-mineral order
  /// actually get me?" — and only `Planet.tradeOrders` holds the totals,
  /// because the run ledger is truncated to ten entries and an order's early
  /// runs are long gone by the time it finishes. **Runs** answers "what
  /// happened just now", with the cause attached.
  ///
  /// A plain `Column` inside a `SingleChildScrollView`, deliberately **not** a
  /// `ListView`: both lists are bounded by construction, so a lazy list would
  /// buy nothing and cost the lazy-build trap (rows below the fold reporting as
  /// "missing" in a test because they were never built).
  Future<void> _showTradeReport(Planet planet) async {
    final incidents = planet.tradeIncidents.reversed.toList();
    final orders = planet.tradeOrders.reversed.toList();
    // Both empty is the only case with nothing to say. Before an order record
    // existed this was `incidents.isEmpty`, which meant a world that traded and
    // finished would open to a blank dialog once its ten runs rolled over.
    if (incidents.isEmpty && orders.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        final dialogCs = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Freight Report', style: TextStyle(fontSize: 18)),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (orders.isNotEmpty) ...[
                    _reportHeading(dialogCs, 'Orders'),
                    for (final o in orders) _reportOrderRow(o, dialogCs),
                    const SizedBox(height: 4),
                  ],
                  if (incidents.isNotEmpty) ...[
                    _reportHeading(dialogCs, 'Recent runs'),
                    for (final i in incidents) _reportRunRow(i, dialogCs),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _reportHeading(ColorScheme cs, String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 10,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      );

  /// One finished order: what it was for, what it got, and what went wrong.
  Widget _reportOrderRow(TradeOrderRecord o, ColorScheme cs) {
    final clean = o.status == 'COMPLETE';
    final cancelled = o.status == 'CANCELLED';
    final tone = clean
        ? Colors.green.shade400
        : cancelled
            ? cs.onSurface.withValues(alpha: 0.5)
            : cs.error;
    final verb = o.direction == TradeDirection.buy ? 'Buy' : 'Sell';
    // The shortfall is split rather than summed: "lost" and "impounded" are
    // different events and a single figure would hide which one happened,
    // which is the whole reason the four outcome classes exist.
    final shortfall = <String>[
      if (o.unitsLost > 0) '${compact(o.unitsLost)} lost',
      if (o.unitsSeized > 0) '${compact(o.unitsSeized)} impounded',
      if (o.unitsCancelled > 0) '${compact(o.unitsCancelled)} cancelled',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                clean
                    ? Icons.check_circle_rounded
                    : cancelled
                        ? Icons.cancel_rounded
                        : Icons.report_gmailerrorred_rounded,
                size: 14,
                color: tone,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '$verb ${compact(o.unitsTotal)} ${o.commodity}'
                  '${o.ports.length > 1 ? ' · ${o.ports.length} ports' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 1),
            child: Text(
              '${o.status} · ${compact(o.unitsDelivered)} delivered'
              '${shortfall.isEmpty ? '' : ' · $shortfall'}'
              '${o.runs > 0 ? ' · ${o.runs} runs' : ''}',
              maxLines: 2,
              style: TextStyle(fontSize: 11, color: tone),
            ),
          ),
        ],
      ),
    );
  }

  /// One resolved run. The line reads what became of the freight, not whether
  /// it "succeeded" — four outcomes, and a seizure is a delivery.
  Widget _reportRunRow(TradeIncident i, ColorScheme cs) {
    final icon = switch (i.outcome) {
      TradeRunOutcome.delivered => Icons.check_circle_rounded,
      TradeRunOutcome.lost => Icons.report_gmailerrorred_rounded,
      TradeRunOutcome.delayed => Icons.schedule_rounded,
      TradeRunOutcome.seized => Icons.gavel_rounded,
    };
    final tone = switch (i.outcome) {
      TradeRunOutcome.delivered => Colors.green.shade400,
      TradeRunOutcome.lost => cs.error,
      // A diversion costs nothing but patience, so it is not an error tone —
      // painting it red would train the player to ignore the warning colour.
      TradeRunOutcome.delayed => Colors.amber.shade400,
      TradeRunOutcome.seized => cs.error,
    };
    final status = switch (i.outcome) {
      TradeRunOutcome.delivered => 'Delivered',
      TradeRunOutcome.lost => 'LOST — ${i.cause?.label ?? 'cause unrecorded'}',
      TradeRunOutcome.delayed => 'DIVERTED — '
          '${i.cause?.label ?? 'rerouted'} (+${i.delayTicks}t)',
      TradeRunOutcome.seized => 'PARTIAL — ${compact(i.deliveredUnits)} of '
          '${compact(i.units)} delivered, ${i.cause?.label ?? 'impounded'}',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: tone),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${i.direction == TradeDirection.buy ? 'Buy' : 'Sell'} '
                  '${compact(i.units)} ${i.commodity} '
                  '→ port #${i.portSectorId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 20, top: 1),
            child: Text(
              status,
              maxLines: 2,
              style: TextStyle(fontSize: 11, color: tone),
            ),
          ),
        ],
      ),
    );
  }

  /// The world's unsettled sales, always rendered — even at zero.
  ///
  /// Two reasons it is a bordered vault rather than a conditional row. It is
  /// the same idiom as the Resources card's shipment-pool box (tinted fill,
  /// header, full-width actions), so a withdrawal reads as moving money that
  /// is already earned. And it never appears or disappears: the row used to
  /// pop in the moment the first sale landed, shifting every control below
  /// it mid-tap — which is the shape most of the "I had to tap twice"
  /// reports take.
  Widget _buildTreasuryVault(Planet planet, ColorScheme cs) {
    final revenue = planet.accumulatedRevenue;
    final pending = _hasPendingWithdrawal(planet.id);
    final canTake = revenue > 0 && !pending;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_balance_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              const Text('Treasury',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            revenue > 0
                ? '${compact(revenue)} cr earned, awaiting collection'
                : pending
                    ? 'Confirming last withdrawal…'
                    : 'No sales collected yet — sell runs land here.',
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _miniActionButton('Withdraw', Colors.green, canTake,
                    () => _withdrawRevenue(planet),
                    key: const Key('market-withdraw'),
                    disabledReason: pending
                        ? 'Confirming last withdrawal…'
                        : 'No revenue to withdraw yet'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniActionButton('Send to Bank', Colors.teal, canTake,
                    () => _bankRevenue(planet),
                    key: const Key('market-bank'),
                    disabledReason: pending
                        ? 'Confirming last withdrawal…'
                        : 'No revenue to bank yet'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _marketRow(String type, Planet planet, ColorScheme cs) {
    final stored = _storedFor(type, planet);
    final amount = _marketAmounts[type] ?? 1000;
    final label = type[0].toUpperCase() + type.substring(1);
    // A sell cannot promise what the store does not hold: clamp the volume
    // before planning, so every planned share is creatable.
    final sellVolume = amount < stored ? amount : stored;
    final buyPlan = _marketPlan(type, TradeDirection.buy, amount, planet);
    final sellPlan = sellVolume > 0
        ? _marketPlan(type, TradeDirection.sell, sellVolume, planet)
        : null;
    var buyTotal = 0;
    for (final s in buyPlan.allocations) {
      buyTotal += s.units * s.unitPrice;
    }
    var sellTotal = 0;
    if (sellPlan != null) {
      for (final s in sellPlan.allocations) {
        sellTotal += s.units * s.unitPrice;
      }
    }
    final canBuy = buyPlan.unitsAllocated > 0 &&
        widget.player.credits >= buyTotal &&
        buyTotal > 0;
    final canSell = sellPlan != null && sellPlan.unitsAllocated > 0;
    final buyDisabledReason = buyPlan.unitsAllocated <= 0
        ? 'No port is selling $label right now'
        : 'Need ${compact(buyTotal)} cr for that order';
    final sellDisabledReason = sellVolume <= 0
        ? 'Nothing stored to sell'
        : 'No port is buying $label right now';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '${compact(stored)} / ${compact(_maxFor(type, planet))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _miniStepper(Icons.remove_rounded, () {
              setState(() {
                _marketAmounts[type] =
                    (amount - 100).clamp(minimumMarketAmount, 1 << 30);
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                compact(amount),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _miniStepper(Icons.add_rounded, () {
              setState(() {
                _marketAmounts[type] =
                    (amount + 100).clamp(minimumMarketAmount, 1 << 30);
              });
            }),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              // A menu, not a bare "Max". The two maxima are usually wildly
              // different — one is bounded by the galaxy's stock and the other
              // by this world's store — and a single button has to pick one,
              // so it either fills the field with a number the other button
              // cannot honour or it guesses wrong half the time. Naming both
              // directions *and their figures* teaches the asymmetry, which is
              // the thing that made the old button confusing rather than
              // merely wrong.
              child: PopupMenuButton<TradeDirection>(
                key: Key('market-max-$type'),
                tooltip: 'Set the maximum order size',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 0),
                offset: const Offset(0, 18),
                position: PopupMenuPosition.under,
                onSelected: (d) => _setMarketMax(type, d, planet),
                itemBuilder: (ctx) => [
                  for (final d in TradeDirection.values)
                    PopupMenuItem<TradeDirection>(
                      value: d,
                      height: 30,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            d == TradeDirection.buy
                                ? 'Max buy  '
                                : 'Max sell  ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: d == TradeDirection.buy
                                  ? Colors.blue
                                  : Colors.orange,
                            ),
                          ),
                          Text(
                            // Quoted live, not cached: the two maxima move
                            // every tick as ports regen and the store fills,
                            // so a value captured when the row was built
                            // would be a stale promise.
                            compact(_marketMaxFor(type, d, planet)),
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Max',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_rounded,
                          size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            _miniActionButton('Buy', Colors.blue, canBuy, () {
              _placeMarketOrder(type, TradeDirection.buy, amount, planet);
            }, key: Key('market-buy-$type'), disabledReason: buyDisabledReason),
            const SizedBox(width: 4),
            _miniActionButton('Sell', Colors.orange, canSell, () {
              _placeMarketOrder(type, TradeDirection.sell, amount, planet);
            },
                key: Key('market-sell-$type'),
                disabledReason: sellDisabledReason),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _marketPreview(
              buyPlan, buyTotal, sellPlan, sellTotal, sellVolume, _portNames()),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// One honest line per direction: what it costs, who fills it, and what the
  /// galaxy could not cover. Shown *before* paying, because a paid order is a
  /// reservation and the player should see the shortfall while it is still
  /// a quote. Ports are named, not counted: "1 port(s)" says where to look
  /// without saying what it is called.
  String _marketPreview(TradePlan buyPlan, int buyTotal, TradePlan? sellPlan,
      int sellTotal, int sellVolume, Map<int, String> portNames) {
    String portsOf(TradePlan p) {
      final names = [
        for (final a in p.allocations)
          portNames[a.portSectorId] ?? '#${a.portSectorId}'
      ];
      if (names.isEmpty) return '';
      if (names.length == 1) return ' · ${names.first}';
      return ' · ${names.first} +${names.length - 1} more';
    }

    // Per-run loss risk across the order, as a percentage: a chance a run is
    // intercepted on the way. Shown on the quote so a failure is a risk the
    // player *accepted* (the design's requirement — a silent loss reads as a
    // bug) and so splitting a large order into smaller ones is visibly worth
    // something. `1 - Π(1 - p)` over the order's runs, so it is the chance of
    // losing at least one run, not per-run.
    String riskOf(TradePlan p) {
      if (p.allocations.isEmpty) return '';
      var survive = 1.0;
      for (final a in p.allocations) {
        final runs = (a.units / PlanetTradeService.freighterHold).ceil();
        for (var r = 0; r < runs; r++) {
          survive *= 1 - PlanetTradeService.failureChanceForHops(a.hops);
        }
      }
      final pct = ((1 - survive) * 100).round();
      if (pct <= 0) return '';
      return ' · $pct% run risk';
    }

    final buy = buyPlan.unitsAllocated <= 0
        ? 'Buy: no port selling'
        : 'Buy ${compact(buyPlan.unitsAllocated)} → ${compact(buyTotal)} cr'
            '${portsOf(buyPlan)}${riskOf(buyPlan)}'
            '${buyPlan.shortfall > 0 ? ' · short ${compact(buyPlan.shortfall)}' : ''}';
    final sell = sellVolume <= 0
        ? 'Sell: nothing stored'
        : sellPlan == null || sellPlan.unitsAllocated <= 0
            ? 'Sell: no port buying'
            : 'Sell ${compact(sellPlan.unitsAllocated)} → ${compact(sellTotal)} cr'
                '${portsOf(sellPlan)}${riskOf(sellPlan)}'
                '${sellPlan.shortfall > 0 ? ' · short ${compact(sellPlan.shortfall)}' : ''}';
    return '$buy\n$sell';
  }

  Map<int, String> _portNames() => {
        for (final s in _allSectors)
          if (s.port != null) s.id: s.port!.name,
      };

  /// The most a [direction] order of [type] could actually place right now.
  ///
  /// **Direction-specific, and that is the whole point.** The two maxima are
  /// routinely different by an order of magnitude: buying is capped by what
  /// ports hold across the galaxy, selling by what this world's stores hold.
  /// A single "Max" that took the larger of the two — which is what this did —
  /// put a number in the field that the *other* button could not honour, so
  /// pressing Max then Sell silently sold less than Max promised. The preview
  /// line already quoted each side separately, so the player had no way to
  /// tell the field had been filled for the wrong direction.
  ///
  /// Never below [minimumMarketAmount], so Max on an empty market still leaves a
  /// placeable order rather than zero.
  int _marketMaxFor(String type, TradeDirection direction, Planet planet) {
    final stored = _storedFor(type, planet);
    if (direction == TradeDirection.sell) {
      if (stored <= 0) return minimumMarketAmount;
      // Capped by the store: a sell cannot promise goods the world does not
      // have, so an over-large volume would plan shares the order then cannot
      // create.
      final plan = _marketPlan(type, TradeDirection.sell, stored, planet);
      final max = plan.unitsAllocated;
      return max < minimumMarketAmount ? minimumMarketAmount : max;
    }
    final plan = _marketPlan(type, TradeDirection.buy, 1 << 30, planet);
    final max = plan.unitsAllocated;
    return max < minimumMarketAmount ? minimumMarketAmount : max;
  }

  void _setMarketMax(String type, TradeDirection direction, Planet planet) {
    final max = _marketMaxFor(type, direction, planet);
    setState(() => _marketAmounts[type] = max);
  }

  /// Smallest order the amount field will hold. Also the floor every "max"
  /// falls back to, so an empty market leaves a placeable number rather than 0.
  static const int minimumMarketAmount = 100;

  /// In-flight jobs grouped by request: one tap on Buy/Sell is one order,
  /// possibly split across ports. Legacy jobs with no order id group alone.
  List<_OrderGroup> _orderGroups(Planet planet) {
    final groups = <_OrderGroup>[];
    final index = <String, int>{};
    for (final job in planet.tradeJobs) {
      final key =
          job.orderId.isEmpty ? 'job:${job.id}' : 'order:${job.orderId}';
      final at = index[key];
      if (at == null) {
        index[key] = groups.length;
        groups.add(_OrderGroup(
          cancelId: job.orderId.isEmpty ? job.id : job.orderId,
          direction: job.direction,
          commodity: job.commodity,
          jobs: [job],
        ));
      } else {
        groups[at].jobs.add(job);
      }
    }
    return groups;
  }

  /// One request, one row, one Cancel: aggregate units up top, one countdown
  /// per port-run below (each run has its own cadence, so they cannot share
  /// a bar), and the slowest run sets the ETA.
  Widget _marketOrderRow(
    Planet planet,
    _OrderGroup group,
    ColorScheme cs,
  ) {
    final isBuy = group.direction == TradeDirection.buy;
    var total = 0;
    var delivered = 0;
    var lost = 0;
    var seized = 0;
    var ticksLeft = 0;
    for (final job in group.jobs) {
      total += job.unitsTotal;
      // `unitsDelivered`, not `unitsTotal - unitsRemaining`: the latter counts
      // a lost run as delivered, so an order that lost its only run read
      // "5.0K / 10.0K" while the store gained nothing. A counter that
      // overstates delivery is worse than no counter.
      delivered += job.unitsDelivered;
      lost += job.unitsLost;
      seized += job.unitsSeized;
      if (job.ticksLeft > ticksLeft) ticksLeft = job.ticksLeft;
    }
    final eta = GameClock.estimate(ticksLeft);
    final commodity =
        group.commodity[0].toUpperCase() + group.commodity.substring(1);
    final ports = group.jobs.map((j) => j.portSectorId).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 12,
              color: isBuy ? Colors.blue : Colors.orange,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${isBuy ? 'Buy' : 'Sell'} $commodity'
                '${ports > 1 ? ' · $ports ports' : ' · port #${group.jobs.first.portSectorId}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                // Shortfall is named, not silently subtracted: the player needs
                // to see that the gap between "of" and "delivered" has a name,
                // and the Report says which one. Lost and impounded are
                // reported separately because they are different events —
                // pirates and customs call for different decisions — and a
                // single "LOST" for both would tell the player their goods were
                // destroyed when most of them arrived.
                '${compact(delivered)} / ${compact(total)}'
                '${lost > 0 ? ' · ${compact(lost)} LOST' : ''}'
                '${seized > 0 ? ' · ${compact(seized)} HELD' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: lost > 0 || seized > 0 ? FontWeight.bold : null,
                  color: lost > 0 || seized > 0
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            _miniActionButton('Cancel', cs.error, true, () {
              _cancelMarketOrder(planet, group.cancelId);
            }),
          ],
        ),
        if (lost > 0 || seized > 0) ...[
          const SizedBox(height: 2),
          _lostNotice(cs, lost, seized),
        ],
        const SizedBox(height: 4),
        for (final job in group.jobs) ...[
          _marketRunRow(job, cs),
          const SizedBox(height: 4),
        ],
        Text(
          eta.isEmpty ? 'arriving' : 'done $eta of play',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// The standing warning under an order that has come up short.
  ///
  /// Always present once anything is gone rather than a transient flash: the
  /// count is on the order until it completes, and a marker that appeared for
  /// one tick and vanished is a thing the player would not have read.
  Widget _lostNotice(ColorScheme cs, int lost, int seized) {
    final parts = <String>[
      if (lost > 0) '${compact(lost)} destroyed',
      if (seized > 0) '${compact(seized)} held by customs',
    ];
    return Row(
      children: [
        Icon(Icons.warning_amber_rounded, size: 11, color: cs.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${parts.join(' · ')} — see Report for the cause',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.error,
            ),
          ),
        ),
      ],
    );
  }

  /// One port-run's countdown: which port, which run of how many, and a bar
  /// that moves every second without ever claiming a tick that has not landed
  /// (see [TickProgressBar]).
  Widget _marketRunRow(TradeJob job, ColorScheme cs) {
    final currentRun =
        job.runsDone + 1 > job.runsTotal ? job.runsTotal : job.runsDone + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'port #${job.portSectorId} · run $currentRun of ${job.runsTotal}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        TickProgressBar(
          remaining: job.ticksRemaining,
          total: job.ticksPerRun,
          secondsPerTick: GameClock.secondsPerTick,
        ),
      ],
    );
  }

  /// Places a bulk order: one tap is one request, possibly split across
  /// ports, shown as one row with one Cancel.
  ///
  /// Credits move before the write, and the screen repaints before either —
  /// the same ordering the colonist purchase uses, for the same reason: a
  /// change made in memory must be visible in memory, and a failed write is
  /// reported rather than silently reverting the purchase a second later.
  Future<void> _placeMarketOrder(
      String type, TradeDirection dir, int amount, Planet planet) async {
    final home = _currentSector;
    if (home == null || amount <= 0) return;
    if (dir == TradeDirection.sell && _storedFor(type, planet) <= 0) return;

    final result = PlanetTradeService.createOrder(
      planet: planet,
      universe: _allSectors,
      playerId: widget.player.id,
      commodity: type,
      direction: dir,
      volume: amount,
      actorFaction: widget.player.faction.name,
    );
    if (result.jobs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(dir == TradeDirection.buy
              ? 'No port is selling $type right now.'
              : 'No port is buying $type right now.'),
        ),
      );
      return;
    }
    if (dir == TradeDirection.buy) {
      if (widget.player.credits < result.spent) {
        // Affordability is checked before placing, so this is a race with a
        // concurrent spend rather than a normal path: unwind the whole order
        // rather than leaving paid-for jobs behind.
        PlanetTradeService.cancelOrder(planet, _allSectors, result.orderId);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Need ${compact(result.spent)} cr for that order.')),
        );
        return;
      }
      widget.onPlayerUpdate(widget.player
          .copyWith(credits: widget.player.credits - result.spent));
    }
    // Guard the order until the stored universe confirms it (see
    // [_unconfirmedOrders]): a tick snapshot taken before it existed would
    // otherwise erase paid-for jobs without a word.
    _unconfirmedOrders.add(_PendingOrder(
      planetId: planet.id,
      orderId: result.orderId,
      shares: [
        for (final j in result.jobs)
          _PendingShare(
            jobId: j.id,
            portSectorId: j.portSectorId,
            commodity: j.commodity,
            direction: j.direction,
            units: j.unitsTotal,
            ticksPerRun: j.ticksPerRun,
            unitPrice: j.unitPrice,
          ),
      ],
    ));
    if (mounted) setState(() {});

    final touched = <Sector>[home];
    for (final id in result.portSectorIds) {
      for (final s in _allSectors) {
        if (s.id == id && s.id != home.id) touched.add(s);
      }
    }
    final wrote = await _persistAll(touched);
    if (!wrote && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Order placed, but the universe could not be saved — '
            'it may not survive a restart.',
          ),
        ),
      );
    }
    ActionLogProvider.global.trade(
      '${dir == TradeDirection.buy ? 'Bought' : 'Sold'} '
      '${compact(result.placedUnits)} $type for ${planet.name} '
      '(${compact(result.spent)} cr, ${result.jobs.length} run(s))'
      '${result.shortfall > 0 ? ' · short ${compact(result.shortfall)}' : ''}',
    );
  }

  /// Cancels a whole order — every port-run placed by one request.
  ///
  /// The port reservations are released, sell goods return to the store, and
  /// undelivered buy credits come back to the pilot. Delivered runs stay
  /// delivered on both sides.
  Future<void> _cancelMarketOrder(Planet planet, String orderId) async {
    final home = _currentSector;
    if (home == null) return;
    // A cancelled order needs no confirmation guard any more.
    _unconfirmedOrders.removeWhere((o) => o.orderId == orderId);
    final result = PlanetTradeService.cancelOrder(planet, _allSectors, orderId);
    if (result.refund > 0) {
      widget.onPlayerUpdate(widget.player
          .copyWith(credits: widget.player.credits + result.refund));
    }
    if (mounted) setState(() {});
    final touched = <Sector>[home];
    for (final id in result.portSectorIds) {
      for (final s in _allSectors) {
        if (s.id == id && s.id != home.id) touched.add(s);
      }
    }
    await _persistAll(touched);
  }

  /// Moves earned sale revenue from the world to the pilot's wallet.
  ///
  /// A withdrawal, not a price: the credits were already earned at live port
  /// prices when the runs landed, so this moves money rather than valuing
  /// goods — which is why retiring `Collect` (T6) does not contradict it.
  ///
  /// Registers an unconfirmed-withdrawal intent first (see
  /// [_unconfirmedWithdrawals]): without it a tick write-back landing inside
  /// the persist window restores the treasury and the same credits withdraw
  /// twice. The pilot is credited exactly once, here, never in the poll.
  Future<void> _withdrawRevenue(Planet planet) async {
    await _moveRevenue(planet, toBank: false);
  }

  /// Moves earned sale revenue from the world into the pilot's Guild account,
  /// where it earns the usual daily interest.
  ///
  /// Same money movement as [_withdrawRevenue] with a different destination:
  /// the banking deposit convention (`lastInterestTick` stamped only when
  /// unset, so a first deposit starts the clock without discarding a partial
  /// day) is mirrored rather than reinvented.
  Future<void> _bankRevenue(Planet planet) async {
    await _moveRevenue(planet, toBank: true);
  }

  Future<void> _moveRevenue(Planet planet, {required bool toBank}) async {
    final home = _currentSector;
    if (home == null) return;
    if (_hasPendingWithdrawal(planet.id)) return;
    final amount = planet.accumulatedRevenue;
    if (amount <= 0) return;
    planet.accumulatedRevenue = 0;
    _unconfirmedWithdrawals.add((
      planetId: planet.id,
      withdrawn: amount,
      revenueAtDispatch: amount,
    ));
    if (toBank) {
      widget.onPlayerUpdate(widget.player.copyWith(
        bankBalance: widget.player.bankBalance + amount,
        lastInterestTick: widget.player.lastInterestTick ?? GameClock.tick,
      ));
    } else {
      widget.onPlayerUpdate(
          widget.player.copyWith(credits: widget.player.credits + amount));
    }
    if (mounted) setState(() {});
    final wrote = await _persist(home);
    if (!wrote && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Revenue moved, but the universe could not be saved — '
            'it may not survive a restart.',
          ),
        ),
      );
    }
    ActionLogProvider.global.trade(
      '${toBank ? 'Banked' : 'Withdrew'} ${compact(amount)} cr trade revenue '
      'from ${planet.name}',
    );
  }

  Widget _miniActionButton(
      String label, Color color, bool enabled, VoidCallback onPressed,
      {Key? key, String? disabledReason}) {
    final button = Material(
      key: key,
      color: enabled ? color.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: enabled ? color : color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
    // A dead button with no reason reads as a broken button. The playtest
    // report for these exact controls was "nothing happens" — twice, once
    // for genuinely-disabled buttons whose reason was invisible.
    if (!enabled && disabledReason != null) {
      return Tooltip(message: disabledReason, child: button);
    }
    return button;
  }

  /// Buys colonists from the faction's capital and settles them on the world.
  ///
  /// The one transfer that is **not** a haul. Colonists are priced by distance
  /// from the faction's own homeworld (`15 x hops^1.5`) and every shipment burns
  /// the energy of flying there, whatever its size, so batching pays. They are
  /// still an abstract count rather than cargo — the physical hold half is
  /// outstanding work, recorded in the design doc.
  Future<void> _recruitColonists(
      String type, int amount, int cost, Planet planet) async {
    final sector = _currentSector;
    if (sector == null || widget.player.credits < cost) return;

    // Every shipment burns the energy of flying there, whatever its size. Charged
    // per shipment rather than per unit, so batching pays and a distant empire is
    // a fuel problem rather than a credit problem alone.
    final energy =
        ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    if (widget.player.energy < energy) return;

    // A purchase is a **shipment**, not an edit to the population figure: the
    // credits leave now and the colonists land a tick or two later, with the
    // colony card showing the headcount in transit so the player can watch it
    // arrive. It also means the room check has to count what is already on its
    // way — two orders placed against the same free space would otherwise both
    // pass and overrun the cap on arrival.
    final sending = planet.dispatchColonists(amount);
    if (sending <= 0) return;
    // `sending > 0` above already implies `amount > 0` (`sending` is `amount` or
    // something smaller than it), so the divide cannot throw — but the ordering
    // could still be wrong. `cost ~/ amount * sending` divides *first*, so a
    // 10-credit colonist moved 3 at a time costs 9 for the full step instead of
    // 10: the player quietly underpays by the remainder, once per step.
    final actualCost = (cost * sending) ~/ amount;

    var updated = widget.player.copyWith(
      credits: widget.player.credits - actualCost,
    );
    if (energy > 0) {
      updated = updated.copyWith(energy: widget.player.energy - energy);
    }
    widget.onPlayerUpdate(updated);

    // **The screen repaints before the write, not after.** `setState` used to sit
    // below `await _persist(...)`, which made the UI's acknowledgement of a
    // purchase depend on a disk write succeeding. `UniverseStorage.saveSectors`
    // can *refuse* — it declines to merge when the last load failed, and it
    // silently drops a sector whose id it cannot find in the freshly-loaded file
    // — and it swallows its own errors. Any of those left the player with credits
    // deducted and no panel, because the one line that would have shown the
    // shipment never ran. A purchase that happened in memory must be visible in
    // memory; durability is a separate question, and a failure to persist is
    // reported rather than swallowed.
    if (mounted) setState(() {});

    // Held until the stored universe confirms the shipment **landed**. A
    // successful write is not enough: the tick can overwrite it seconds later
    // with a snapshot taken before this purchase existed, and the player would
    // watch the panel vanish.
    _unconfirmedShipments.add((
      planetId: planet.id,
      headcount: sending,
      // `dispatchColonists` moves nobody into `population` yet, so this is the
      // pre-shipment figure — the baseline the landing has to beat.
      populationAtDispatch: planet.population,
    ));

    final wrote = await _persist(sector);
    if (!wrote && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Colonists dispatched, but the universe could not be saved — '
            'they may not survive a restart.',
          ),
        ),
      );
    }
  }

  /// Moves units from the ship's hold into the planet's store. Free.
  ///
  /// This used to debit credits and energy and then credit the goods into the
  /// store **without ever touching `player.cargo`**, which made it a
  /// credits-to-goods printer rather than a transfer: it ignored
  /// `maxCargo` entirely, so a million minerals went into a hold that fits fifty,
  /// and there was nothing in the galaxy to haul.
  ///
  /// Unloading is free because the ship is already in orbit — the cost of
  /// getting the goods here was paid at the port, or earned on a colony.
  Future<void> _depositToPlanet(String type, int amount, Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final held = widget.player.cargo[type] ?? 0;
    final room = _maxFor(type, planet) - _storedFor(type, planet);
    final moved = amount < held ? amount : held;
    final movedFits = moved < room ? moved : room;
    if (movedFits <= 0) return;

    _applyToStore(type, planet, movedFits);
    final cargo = Map<String, int>.from(widget.player.cargo);
    final left = held - movedFits;
    if (left > 0) {
      cargo[type] = left;
    } else {
      cargo.remove(type);
    }
    widget.onPlayerUpdate(widget.player.copyWith(
      cargo: cargo,
      cargoUsed: widget.player.cargoUsed - movedFits,
    ));

    await _persist(sector);
    ActionLogProvider.global.info(
      'Unloaded ${compact(movedFits)} $type to ${planet.name}'
      '${movedFits < amount ? ' (store was full)' : ''}',
    );
    if (mounted) setState(() {});
  }

  /// Moves units from the planet's store into the ship's hold. Free.
  ///
  /// The counterpart to [_depositToPlanet], and it used to be worse: it paid the
  /// player credits, never touched the hold, and — unlike deposit — charged no
  /// energy at all. So the same goods had two invented prices (5 cr here, 42.5 cr
  /// on the Collect button, and a live price at a port) and neither moved a
  /// single unit into a ship.
  ///
  /// Bounded by free cargo space, which is what makes a hauler worth flying.
  Future<void> _withdrawToShip(String type, int amount, Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final stored = _storedFor(type, planet);
    final space = widget.player.maxCargo - widget.player.cargoUsed;
    final moved = amount < stored ? amount : stored;
    final movedFits = moved < space ? moved : space;
    if (movedFits <= 0) return;

    _applyToStore(type, planet, -movedFits);
    final cargo = Map<String, int>.from(widget.player.cargo);
    cargo[type] = (cargo[type] ?? 0) + movedFits;
    widget.onPlayerUpdate(widget.player.copyWith(
      cargo: cargo,
      cargoUsed: widget.player.cargoUsed + movedFits,
    ));

    await _persist(sector);
    ActionLogProvider.global.info(
      'Loaded ${compact(movedFits)} $type from ${planet.name}'
      '${movedFits < amount ? ' (hold is full)' : ''}',
    );
    if (mounted) setState(() {});
  }

  /// Adds (or, for a negative [delta], removes) units on a named store.
  ///
  /// Clamped at zero so a withdraw can never drive a store negative if two
  /// actions land in the same frame.
  void _applyToStore(String type, Planet planet, int delta) {
    int apply(int current) {
      final next = current + delta;
      return next < 0 ? 0 : next;
    }

    switch (type) {
      case 'minerals':
        planet.storedMinerals = apply(planet.storedMinerals);
      case 'organics':
        planet.storedOrganics = apply(planet.storedOrganics);
      case 'industrial':
        planet.storedIndustrial = apply(planet.storedIndustrial);
      case 'drones':
        planet.storedDrones = apply(planet.storedDrones);
    }
  }

  Future<void> _claimPlanet(Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final previousOwner = planet.owner;
    planet.owner = widget.player.faction;
    var updatedPlayer = widget.player;
    if (previousOwner != null && previousOwner != widget.player.faction) {
      updatedPlayer =
          updatedPlayer.withFactionStandingChange(previousOwner, -3);
    }
    // Settling a world you found: half of what *creating* one is worth, so
    // making something outweighs taking it.
    updatedPlayer =
        updatedPlayer.withAlignmentDelta(ReputationActions.buildWorld);
    widget.onPlayerUpdate(updatedPlayer);
    await _persist(sector);
    ActionLogProvider.global.info(
      '${widget.player.faction.displayName} has claimed ${planet.name} '
      '(reputation +${ReputationActions.buildWorld.toInt()})',
    );
    if (mounted) {
      setState(() {});
    }
  }

  String _levelTitle(int level) {
    return level >= 1 && level <= 6 ? Planet.levelTitles[level - 1] : 'Unknown';
  }

  /// A level-gate row: `have / need`, with the **requirement** coloured.
  ///
  /// Two iterations on this. It started as a trailing `✓` glyph, which only
  /// appeared on success — a missed requirement showed nothing, so the two states
  /// were told apart by the absence of a character. That became a green tick or
  /// a red cross, which was unambiguous but noisy: a fourth icon column on every
  /// row, for a binary the numbers already carry.
  ///
  /// It is now just the colour of the **required** figure. Red means not yet,
  /// green means met, and the first number — what the world actually has — stays
  /// in the normal text colour, because colouring the total too would colour
  /// every cell in the card and tell you nothing the numbers do not.
  ///
  /// Colour alone is not an accessible signal, so the row also carries a
  /// semantic label; see the comment on the test that checks it.
  Widget _requirementRow(String label, int have, int need, ColorScheme cs) {
    final met = have >= need;
    return Semantics(
      // `container: true` is what makes this its **own** node. Without it
      // `Semantics` only annotates, and the label merges into an ancestor's
      // node — where it is indistinguishable from every other row and cannot be
      // addressed on its own. `excludeSemantics` then drops the inner Text so
      // the raw "250 / 250" is not announced as well.
      container: true,
      label: '$label requirement ${met ? 'met' : 'not met'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${compact(have)} / ${compact(need)}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  // Only the *need* is coloured, so the eye lands on the
                  // target rather than on the number that is merely your
                  // current position.
                  color: met
                      ? Colors.green.shade400
                      : cs.error.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What is going on with this world, derived rather than assumed.
  ///
  /// It used to be `isHomeworld ? 'Homeworld' : 'Colony'`, which called an
  /// unclaimed rock with no colonists on it a *colony* — the one word a player
  /// scanning this block most needs to be correct about. Derived from the actual
  /// state instead, in the order that answers "can I use it".
  String _statusLabel(Planet world) {
    if (world.isDestroyed) return 'Destroyed';
    if (world.isHomeworld) {
      final of = world.homeworldOf;
      return of == null ? 'Homeworld' : 'Homeworld of ${of.displayName}';
    }
    if (world.owner == null) return 'Unclaimed';
    // Claimed but nobody living on it: not yet a colony, and saying so is the
    // difference between "I own this" and "this is producing for me".
    if (world.population <= 0) return 'Claimed, unsettled';
    if (world.isBackupHomeworld) return 'Reserve capital';
    return 'Colony';
  }

  Future<void> _adjustWorkforce(Planet planet, String track, int delta) async {
    final sector = _currentSector;
    if (sector == null) return;
    if (planet.owner != widget.player.faction) return;

    final reserve = planet.reserveColonists;
    // Three tracks, because three tracks exist. `trackRow` is only ever called
    // with these names, so a fourth arm here was reachable-looking dead code —
    // and it read the legacy `colonistsDrones`, which is exactly the kind of
    // vestigial arm that later gets "fixed" into a live one.
    final current = switch (track) {
      'minerals' => planet.colonistsMinerals,
      'organics' => planet.colonistsOrganics,
      'industrial' => planet.colonistsIndustrial,
      _ => 0,
    };

    // Moving into a track: only as many as are idling in the reserve.
    final into = delta > 0 ? delta.clamp(0, reserve) : delta;
    if (into == 0) return;
    final applied = current + into;
    if (applied < 0) return;

    switch (track) {
      case 'minerals':
        planet.colonistsMinerals = applied;
      case 'organics':
        planet.colonistsOrganics = applied;
      case 'industrial':
        planet.colonistsIndustrial = applied;
      // No drone case: `trackRow` is only ever called with the three real
      // track names, because drones are derived rather than staffed. This
      // branch was unreachable and reachable-looking, which is worse than
      // absent — it invited someone to add a fourth row.
    }

    await _persist(sector);
    if (mounted) setState(() {});
  }

  Widget _buildLevelUpSection(Planet planet, ColorScheme cs) {
    final cost = planet.levelUpCost;
    if (cost == null) {
      return Text(
        'MAX LEVEL — ${Planet.levelTitles.last}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.amber.shade400,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      );
    }

    // A build already under way takes the whole card over. The gate rows below
    // describe work that has already been paid for, so showing them again next
    // to a progress bar would invite the player to think they still had a choice.
    if (planet.isUnderConstruction) {
      return PlanetConstructionPanel(planet: planet, cs: cs);
    }

    final canLevel = planet.canStartConstruction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // **Both sides flex.** This is the fourth instance of the same bug
            // on this screen: two natural-width `Text`s in a `Row` overflow as
            // soon as either gets long, and `"Level 3 → 4  "` beside
            // `"Fortified Colony"` is over by 23px at 430px. It never showed up
            // before because the level-up header only renders for a world that
            // is *not* already building — which is most of the time, so this was
            // live, not latent. Found by asserting no overflow at phone width
            // with the resource figures, not by looking at the header.
            Flexible(
              child: Text(
                'Level ${planet.level} → ${planet.level + 1}  ',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.amber.shade400,
                ),
              ),
            ),
            Flexible(
              child: Text(
                Planet.levelTitles[planet.level],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _requirementRow(
            'Colonists', planet.population, cost.requiredColonists, cs),
        _requirementRow(
            'Minerals', planet.storedMinerals, cost.requiredMinerals, cs),
        _requirementRow(
            'Organics', planet.storedOrganics, cost.requiredOrganics, cs),
        _requirementRow(
            'Industrial', planet.storedIndustrial, cost.requiredIndustrial, cs),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canLevel ? () => _levelUpPlanet(planet) : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            label: const Text('Level Up'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: () => _showLevelPreview(context, planet),
            icon: const Icon(Icons.help_outline_rounded, size: 15),
            label: const Text('What does this give me?',
                style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(alpha: 0.7),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ],
    );
  }

  /// Quick "what do I get" preview, shown under the level-up button.
  ///
  /// **Only the next tier, not all six.** The argument for that is the framing,
  /// not the space: a player standing at a level gate has one question, and the
  /// useful answer is a *delta* — "defence: none -> light". A six-row table
  /// cannot show a delta, and a delta is strictly more informative than the
  /// column it came from. Reference material belongs in the Planet Guide, which
  /// already generates the full table from the same model.
  ///
  /// The population row deliberately shows the new cap against the gate beside
  /// it. That pairing is the whole point of the derived cap, and it is the one
  /// place a player would otherwise have to check it by hand.
  void _showLevelPreview(BuildContext context, Planet planet) {
    final from = planet.level;
    final to = from + 1;
    // The bound is "can this world still upgrade", not "is `to` inside the
    // title list". `levelTitles` is 0-indexed, so its length is 6 while the
    // highest *level* is also 6 — and `to >= length` therefore rejected the
    // 5→6 preview, which is a real upgrade with a real cost, silently and with
    // no error. `levelUpCost` is the model's own answer and is null exactly when
    // there is no next tier.
    if (planet.levelUpCost == null) return;

    // levelTitles is 0-indexed from level 1, so a level L is titles[L - 1].
    // Getting this wrong labels the whole dialog one tier ahead, and it is
    // invisible unless a test names the expected string.
    final fromTitle = Planet.levelTitles[from - 1];
    final toTitle = Planet.levelTitles[to - 1];

    Future<void> show() => showDialog<void>(
          context: context,
          builder: (ctx) {
            final dialogCs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Text('$fromTitle -> $toTitle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _benefitRow(
                        ctx,
                        'Development',
                        '${(Planet.levelDevelopment[from] ?? 1.0).toStringAsFixed(2)}x',
                        '${(Planet.levelDevelopment[to] ?? 1.0).toStringAsFixed(2)}x'),
                    _benefitRow(
                        ctx,
                        'Defence',
                        _defenceWord(planet.defenseLevel),
                        _defenceWord(Planet.levelDefense[to] ?? 0)),
                    _benefitRow(ctx, 'Armour', compact(planet.maxHull.round()),
                        compact(Planet.levelArmour[to] ?? 0)),
                    _benefitRow(
                        ctx,
                        'Shields',
                        planet.maxShield.round() <= 0
                            ? 'none'
                            : compact(planet.maxShield.round()),
                        (Planet.levelShield[to] ?? 0) <= 0
                            ? 'none'
                            : compact(Planet.levelShield[to] ?? 0)),
                    _benefitRow(
                        ctx,
                        'Storage',
                        'x${_scale(Planet.levelStorageScale[from])}',
                        'x${_scale(Planet.levelStorageScale[to])}'),
                    const SizedBox(height: 12),
                    _previewStat(
                      ctx,
                      'New population cap',
                      compact((planet.baseColonistMax *
                              (Planet.levelColonistScale[to] ?? 1.0))
                          .round()),
                    ),
                    _previewStat(
                      ctx,
                      'Needed for this level',
                      compact(planet.levelUpCost!.requiredColonists),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The full tier table is in the Planet Guide '
                      '(Computer -> Planet Guide).',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: dialogCs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );

    // Fire and forget: the dialog owns its own lifetime, and nothing on the
    // planet screen needs to wait for it or react to its dismissal.
    show();
  }

  /// A "current -> next" line. The arrow is what makes this a delta rather
  /// than a lookup, so it is never elided and the row is allowed to wrap.
  Widget _benefitRow(
    BuildContext context,
    String label,
    String from,
    String to,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(from,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6))),
                Icon(Icons.arrow_right_alt_rounded,
                    size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                Text(to,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A plain "label: value" line for figures with no "before" to show.
  Widget _previewStat(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Defence levels are a 0-4 scale. Numbers mean nothing to a player.
  static String _defenceWord(int level) {
    const words = ['none', 'light', 'moderate', 'heavy', 'fortified'];
    return level < words.length ? words[level] : '$level';
  }

  static String _scale(double? v) => v == null
      ? '1'
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  /// Chip row for choosing which world in this sector to work with.
  ///
  /// Only rendered when the sector holds more than one. Its absence in a
  /// single-world sector is deliberate: a one-chip selector that can only be
  /// tapped to select what is already selected is pure noise.
  ///
  /// A destroyed world stays in the list rather than disappearing. Removing it
  /// would shift every chip under the player's finger mid-session, and the
  /// collision roll can destroy a world while they are looking at it — so it is
  /// shown struck through and unselectable instead.
  Widget _buildWorldSelector(Sector sector, Planet current) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Worlds in this sector',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.7))),
            const Spacer(),
            Text('${sector.livingPlanets.length} / ${sector.planets.length}',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in sector.planets) ...[
                ChoiceChip(
                  label: Text(p.name,
                      style: TextStyle(
                        fontSize: 12,
                        decoration:
                            p.isDestroyed ? TextDecoration.lineThrough : null,
                      )),
                  selected: p.id == current.id,
                  onSelected: p.isDestroyed
                      ? null
                      : (_) => setState(() => _selectedPlanetId = p.id),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Progress panel shown in place of the level gate while a build runs.
  ///
  /// The wording is deliberate on one point: the countdown is **game ticks, not
  /// wall-clock time**. "40 ticks" is honest about what the player can actually
  /// affect; an "ETA" in hours would quietly lie every time they closed the game.
  Future<void> _levelUpPlanet(Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    // Instant when the player has asked for instant construction, otherwise a
    // real build. Both paths share one cost table, so a build at 0 seconds and
    // a build at 4 hours are the same transaction with a different wait.
    final scale = widget.constructionTimeScale;
    if (scale <= 0) {
      if (!planet.levelUp()) return;
      await _persist(sector);
      ActionLogProvider.global.info(
        '${planet.name} reached level ${planet.level}',
      );
    } else {
      if (!planet.startConstruction(timeScale: scale)) return;
      // **Persist before returning.** Omitting this was a live bug: the
      // countdown and the spent resources existed only in this screen's
      // in-memory copy of the sector, so leaving the tab threw the build away
      // and the level gate came back armed, at the same level, with the
      // resources back in the store. The countdown is the *authoritative*
      // state of a running build, so it has to reach disk before the player
      // can navigate away.
      await _persist(sector);
      final mins = GameClock.estimate(planet.constructionTicksRemaining);
      ActionLogProvider.global.info(
        '${planet.name} began building level ${planet.level + 1}'
        '${mins.isEmpty ? '' : ' ($mins of play time)'}',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  /// Sweeps the shipment pool into the working stores, bounded by room.
  ///
  /// Free and priceless: the pool is overflow, so moving it pays nothing and
  /// the credits line is gone with the `Collect` button (T6). Set state
  /// before the write, like every other purchase-shaped action on this
  /// screen, so the acknowledgement never depends on the disk landing.
  Future<void> _sweepShipment(Planet planet) async {
    final sector = _currentSector;
    if (sector == null || planet.pendingTotal <= 0) return;

    final moved = planet.sweepShipmentPool();
    if (moved.isEmpty) return;
    final units = moved.values.fold<int>(0, (a, b) => a + b);
    if (mounted) setState(() {});
    await _persist(sector);
    ActionLogProvider.global.info(
      'Swept ${compact(units)} units of pooled output into the stores on '
      '${planet.name}'
      '${planet.pendingTotal > 0 ? ' (${compact(planet.pendingTotal)} still pooled)' : ''}',
    );
  }

  // ── Atomic Detonator ─────────────────────────────────────────────

  /// The red control in the title bar.
  ///
  /// Enabled on possession alone: a player holding a detonator may use it on
  /// any world they can reach, because ordnance is ordnance and the harsh-type
  /// design explicitly wants a bad roll to be undoable. The warning dialog is
  /// where the cost is stated.
  Widget _destroyPlanetButton(ColorScheme cs) {
    final armed = widget.player.atomicDetonators > 0;
    // `TextButton.icon` has no tooltip parameter, so the explanation is a
    // wrapper rather than an argument — and on a disabled button a Tooltip is
    // the only thing that can still say *why* it is disabled.
    return Tooltip(
      message: armed
          ? 'Vaporise this world with an Atomic Detonator'
          : 'No Atomic Detonators aboard — emporiums stock them',
      child: TextButton.icon(
        icon: const Icon(Icons.dangerous_rounded, size: 18),
        label: const Text('Destroy Planet'),
        style: TextButton.styleFrom(
          // Red when live, and visibly inert when not. Never hidden — a control
          // the player has not unlocked yet should be discoverable, or the
          // detonator in the emporium is a purchase with no visible purpose.
          foregroundColor:
              armed ? cs.error : cs.onSurface.withValues(alpha: 0.3),
          disabledForegroundColor: cs.onSurface.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(horizontal: 10),
        ),
        onPressed: armed ? _confirmDestroyPlanet : null,
      ),
    );
  }

  /// The warning. It states what is about to be lost, because "are you sure?"
  /// on an irreversible action is not consent — and the thing being destroyed is
  /// frequently a colony the player spent hours populating.
  Future<void> _confirmDestroyPlanet() async {
    final sector = _currentSector;
    final planet = _resolvePlanet(sector);
    if (sector == null || planet == null) return;

    final before = widget.player;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.warning_amber_rounded,
            color: Theme.of(ctx).colorScheme.error, size: 32),
        title: Text('Destroy ${planet.name}?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'An Atomic Detonator vaporises this world and everything on it. '
                'This cannot be undone.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              _destroyStat(ctx, 'Type', planet.planetType),
              _destroyStat(ctx, 'Owner', _ownerLabel(planet)),
              _destroyStat(ctx, 'Citadel level', '${planet.level}'),
              _destroyStat(ctx, 'Population', compact(planet.population)),
              _destroyStat(ctx, 'Minerals', compact(planet.storedMinerals)),
              _destroyStat(ctx, 'Organics', compact(planet.storedOrganics)),
              _destroyStat(ctx, 'Industrial', compact(planet.storedIndustrial)),
              _destroyStat(ctx, 'Drones', compact(planet.storedDrones)),
              const SizedBox(height: 12),
              Text(
                'Blast risk: a detonator sometimes catches the firing ship — '
                'around '
                '${(WorldForging.blastChanceMin * 100).round()}–'
                '${(WorldForging.blastChanceMax * 100).round()}%. Shields '
                'usually absorb it.',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abort'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Launch Detonator'),
          ),
        ],
      ),
    );
    if (proceed != true || !mounted) return;

    final (result, after, reputation) = WorldForging.detonate(
      player: before,
      sector: sector,
      world: planet,
      cap: widget.worldCap,
      tick: GameClock.tick,
    );
    if (!mounted) return;
    if (result != DetonateResult.destroyed) {
      _notify(result == DetonateResult.alreadyDead
          ? '${planet.name} is already destroyed.'
          : 'The detonator did not fire.');
      return;
    }

    // The transaction is committed **before** the animation, not after.
    //
    // It used to be the other way round, with a comment claiming the animation
    // was "theatre after the fact" — which was true of the *model* and false of
    // everything that mattered. `_DetonationSequence` had no pop path at all, so
    // this `await` never returned: no `onPlayerUpdate`, no `_persist`, no log.
    // The player got a permanent full-screen overlay, the detonator was never
    // spent, and the world was never written — so it came straight back on the
    // next login. One missing `Navigator.pop` silently discarded an
    // irreversible action, and it was invisible in testing because every
    // detonator test drives the rule, not this screen.
    //
    // Ordering it this way makes the destruction durable no matter what the
    // animation does, whether it is interrupted, crashes, or is later given a
    // skip button. Theatre must not gate a transaction.
    widget.onPlayerUpdate(after);
    // Write through, or the destruction is resurrected: the tick re-reads the
    // universe from disk every cycle, so a change living only in this screen's
    // copy is undone on the next load and the player finds the colony they were
    // just told they lost. `_persist` guards the poll with `_writeInFlight`.
    await _persist(sector);

    final hurt = _blastDamage(before, after);
    // No sector number. The log is the player's own feed today, so this is not
    // leaking anything *yet* — but the reason stands on its own: a destroyed
    // world is something people hunt for, and a message naming where one stood
    // is a map to it. `WorldForging` scrubs the same detail from its
    // world-news line, which is the one a future shared log would expose.
    ActionLogProvider.global.error(
      'Atomic Detonator vaporised ${planet.name}'
      '${hurt > 0 ? ' — the blast caught your ship for $hurt' : ''}'
      '${_reputationNote(reputation)}',
    );
    setState(() {});

    // Now the theatre, with the outcome already committed and logged. The
    // snackbar is deliberately shown *before* the overlay rather than after it:
    // it is the confirmation that will still be on screen when the overlay
    // closes, and it does not depend on the animation finishing.
    _notify(hurt > 0
        ? '${planet.name} destroyed. The blast caught you for $hurt.'
        : '${planet.name} destroyed. The blast missed you.');
    if (!mounted) return;

    // **Nothing about getting out of here may depend on the animation finishing.**
    //
    // The overlay used to be dismissed by an `AnimationStatusListener`, so if the
    // ticker was ever suspended — `TickerMode` does exactly that for an offstage
    // `IndexedStack` child, and this screen *is* one, since a detonation leaves
    // for the Sector tab — the controller never completed, the listener never
    // fired, and the dialog sat there. The exit now runs on a plain `Timer`,
    // which ticks regardless of TickerMode, and a watchdog force-pops the route
    // if the overlay is somehow still up long after it should have gone. A report
    // the player cannot dismiss is a trap, and the only escape being "kill the
    // process" is a soft-lock.
    // One owner for the exit, and it is guarded. It used to be reached twice —
    // from `onFinished` and from a bare `onExitToSector?.call()` after the
    // `await` — so the callback fired twice and the flag between them meant
    // nothing. The overlay fires `onFinished` from `CLOSE`, from the automatic
    // end, and from its own ticker-independent timer, so every real exit is
    // covered; this local is just the single place the flag lives.
    var left = false;
    void leave() {
      if (left) return;
      left = true;
      widget.onExitToSector?.call();
    }

    // **Every** way out of this dialog goes through `_DetonationSequence
    // ._finish`, which is the only caller of `onFinished`. The barrier is not
    // dismissible on purpose: a tap outside pops a route *silently*, so it would
    // be a third exit that navigates nowhere — and the one the player is most
    // likely to try. With `CLOSE`, the automatic end, and the watchdog all going
    // through one method, there is nothing to keep in agreement.
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (ctx) => _DetonationSequence(
        worldName: planet.name,
        onFinished: leave,
      ),
    );
    // Belt and braces: if the route somehow popped without `onFinished`, the
    // player still leaves rather than sitting on a tab with nothing on it.
    leave();
  }

  /// Damage the blast actually landed, shields first. Zero when it missed or
  /// was fully absorbed — which is the common case, and the dialog says so
  /// rather than leaving the player bracing for damage that never came.
  int _blastDamage(Player before, Player after) =>
      (before.shields - after.shields) + (before.hull - after.hull);

  /// Trailing clause for the destruction log line, when the act cost something.
  ///
  /// Named rather than left to the player to notice on the reputation card three
  /// screens later: the whole point of charging for this is that destroying a
  /// world is *not* a neutral action, and a silent deduction teaches nothing.
  ///
  /// "Falls", not "rises" — reputation is signed and this is a bad deed. The
  /// wording was written against the old one-direction scale and would have been
  /// the loudest possible lie on the screen.
  String _reputationNote(ReputationHit? hit) {
    if (hit == null) return '';
    final faction = hit.faction;
    final standing =
        faction == null ? '' : ' The ${faction.name} will remember this.';
    // Unconditional now, so this always has something to say — including for a
    // world the player made themselves. Demolishing a populated world is a
    // violent act whoever signed for it, and the number is shown every time so
    // the cost is never a surprise discovered on the reputation card later.
    return ' Your reputation falls by ${hit.alignment.abs().toInt()}.$standing';
  }

  String _ownerLabel(Planet world) {
    final owner = world.owner;
    if (owner == null) return 'Unclaimed';
    return '${owner.name}${world.isHomeworld ? ' (homeworld)' : ''}';
  }

  Widget _destroyStat(BuildContext ctx, String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            Text(value,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// The detonation, as a two-beat sequence: the ordnance travels, then the
/// world goes up.
///
/// Kept as one small widget with its own controller rather than a pile of
/// `setState` calls on the screen, so the timing lives in one readable place
/// and disposing it is a single `dispose`. A `Ticker`-driven `AnimationController`
/// is used with a `CurvedAnimation` per beat so the travel eases in and the
/// flash snaps — the difference between something that looks mechanical and
/// something that looks like it was aimed.
///
/// Total ~1.5s, and it cannot be skipped: `barrierDismissible: false`, because
/// letting a player tap past the end of a world disappearing invites a
/// "did that actually happen?" moment.
class _DetonationSequence extends StatefulWidget {
  final String worldName;

  /// Called once, when the overlay has finished — whether that is the automatic
  /// end, the `CLOSE` button, or a tap outside. The caller uses it to leave for
  /// the Sector tab, so **both** ways out of this widget lead somewhere. It used
  /// to be dismissed by a status listener alone and navigation happened after
  /// the caller's `await`, so a suspended ticker meant no exit at all.
  final VoidCallback onFinished;

  const _DetonationSequence({
    required this.worldName,
    required this.onFinished,
  });

  /// Animation plus the hold — published so the caller's watchdog can be set
  /// from the same number rather than a second guess at it.
  static const Duration totalDuration = Duration(milliseconds: 3900);

  @override
  State<_DetonationSequence> createState() => _DetonationSequenceState();
}

class _DetonationSequenceState extends State<_DetonationSequence>
    with SingleTickerProviderStateMixin {
  /// Travel is the first half of the timeline, the blast the rest.
  ///
  /// Half rather than the original 45% because the two beats want comparable
  /// screen time: the detonator closing and the flash decaying are the two
  /// things worth watching, and the flash needs longer than the approach to
  /// read as an explosion rather than a flicker.
  static const double _impactAt = 0.5;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  /// Dismisses the overlay on a **plain timer**, scheduled at init.
  ///
  /// This is the second exit path and it does not consult the ticker at all,
  /// which is the whole point: a `TickerMode` offstage subtree suspends
  /// [AnimationController] indefinitely, and a dismissal that waits for
  /// `completed` then never arrives. `Timer` fires regardless. The status
  /// listener below is kept as the tidy path so the frame is not held for a
  /// tenth of a second longer than it needs to be.
  Timer? _watchdog;

  bool _finished = false;

  void _finish() {
    if (_finished) return;
    _finished = true;
    _watchdog?.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onFinished();
  }

  late final Animation<double> _travel = CurvedAnimation(
    parent: _c,
    curve: const Interval(0, _impactAt, curve: Curves.easeInCubic),
  );

  late final Animation<double> _blast = CurvedAnimation(
    parent: _c,
    curve: const Interval(_impactAt, 1, curve: Curves.easeOut),
  );

  @override
  void initState() {
    super.initState();
    _c.addStatusListener(_onStatus);
    _watchdog = Timer(_DetonationSequence.totalDuration, () {
      // Only reached if the status listener did not get there first, which is
      // the case that used to strand the player.
      _finish();
    });
    _c.forward();
  }

  /// Closes itself when the sequence ends.
  ///
  /// This widget used to have **no** pop path at all — it ran an animation and
  /// stopped. Because the caller awaited this dialog before persisting, that one
  /// omission silently discarded the entire detonation: no write, no spent
  /// detonator, and a full-screen overlay with no exit, so the game had to be
  /// killed from the task manager. The `Close` button below is the second
  /// guarantee; this is the one that means the common case needs no click.
  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_closing) return;
    _closing = true;
    // Held for a beat past the last frame so the outcome line can actually be
    // read. Popping the instant the animation hits 1.0 means the flash's tail
    // and the message are on screen for roughly one frame, which is a flicker
    // rather than a report.
    _hold = Timer(_holdAfterSequence, _finish);
  }

  /// How long the finished frame stays up. Long enough to read, short enough
  /// that the overlay never feels like something is being taken from you.
  static const Duration _holdAfterSequence = Duration(milliseconds: 1100);

  bool _closing = false;
  Timer? _hold;

  @override
  void dispose() {
    _hold?.cancel();
    _watchdog?.cancel();
    _c.removeStatusListener(_onStatus);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      // Present from the first frame, not once the animation finishes. An
      // escape that appears only after the thing you might want to skip has
      // already played is not an escape.
      actions: [
        TextButton(
          onPressed: _finish,
          child: const Text('CLOSE'),
        ),
      ],
      actionsPadding: const EdgeInsets.only(bottom: 4),
      content: SizedBox(
        width: 320,
        height: 220,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            final t = _travel.value;
            final b = _blast.value;
            // The world shrinks away as the detonator closes, then the flash
            // takes the frame. 1.0 -> 0 over the travel, so at impact there is
            // nothing left to be hit by the flash — it reads as the blast
            // destroying the thing, not covering it.
            final worldScale = 1 - t;
            final flash = (b * (1 - b) * 4).clamp(0.0, 1.0);
            return Stack(
              alignment: Alignment.center,
              children: [
                // The world.
                if (worldScale > 0.01)
                  Transform.scale(
                    scale: worldScale,
                    child: Opacity(
                      opacity: worldScale.clamp(0.0, 1.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.public_rounded,
                              size: 120, color: cs.primary),
                          const SizedBox(height: 8),
                          Text(widget.worldName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                  color: Colors.white70)),
                        ],
                      ),
                    ),
                  ),
                // The detonator, rising from the bottom edge toward the world.
                if (t < 1)
                  Positioned(
                    bottom: 8 + t * 130,
                    child: Opacity(
                      opacity:
                          (1 - (t - 0.75).clamp(0.0, 1.0) * 4).clamp(0.0, 1.0),
                      child: const Icon(Icons.rocket_launch_rounded,
                          size: 30, color: Colors.amberAccent),
                    ),
                  ),
                // The flash.
                if (flash > 0.01)
                  Container(
                    width: 40 + b * 300,
                    height: 40 + b * 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: flash),
                          Colors.amber.withValues(alpha: flash * 0.7),
                          Colors.orange
                              .withValues(alpha: flash * 0.25 * (1 - b)),
                        ],
                        stops: const [0, 0.45, 1],
                      ),
                    ),
                  ),
                // The outcome line, once the light is gone.
                if (b > 0.55)
                  Opacity(
                    opacity: ((b - 0.55) / 0.45).clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 60),
                        Text('${widget.worldName} destroyed',
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// A bare icon button that fires once on press and repeats while held.
///
/// Mirrors `lib/widgets/hold_button.dart`'s timing (400ms before the first
/// repeat, 80ms between) but takes a [child] instead of a label, because these
/// sit as 24px squares inside a dense table row where a 36px labelled button
/// would not fit and a `FittedBox` label is pointless on a `+` glyph.
class _HoldRepeatIcon extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _HoldRepeatIcon({required this.onPressed, required this.child});

  @override
  State<_HoldRepeatIcon> createState() => _HoldRepeatIconState();
}

class _HoldRepeatIconState extends State<_HoldRepeatIcon> {
  static const _delay = Duration(milliseconds: 400);
  static const _interval = Duration(milliseconds: 80);

  Timer? _timer;

  void _start() {
    widget.onPressed();
    _timer = Timer(_delay, () {
      _timer = Timer.periodic(_interval, (_) {
        if (!mounted) {
          _stop();
          return;
        }
        widget.onPressed();
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: widget.child,
    );
  }
}
