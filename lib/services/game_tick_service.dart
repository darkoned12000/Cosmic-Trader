import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/services/npc_ai/banking_ai.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:cosmic_trader/services/combat_metrics.dart';
import 'package:cosmic_trader/widgets/dev_profiler.dart';

/// Describes an NPC-initated attack on a player during a tick.
class NpcAttackEvent {
  final NpcShip npc;
  final Player player;
  final List<int> sectorWarps;

  const NpcAttackEvent({
    required this.npc,
    required this.player,
    required this.sectorWarps,
  });
}

class GameTickService {
  static final Set<String> _lockedNpcIds = {};

  /// Consecutive per-NPC tick errors (reset on success). At 3 strikes the
  /// goal is force-cleared so one corrupted goal can't freeze an NPC.
  static final Map<String, int> _errorCounts = {};

  @visibleForTesting
  static int errorCountForTest(String npcId) => _errorCounts[npcId] ?? 0;

  @visibleForTesting
  static void resetErrorsForTest() => _errorCounts.clear();

  /// Shared RNG for per-tick price drift (B2). Random walk, not seeded —
  /// live markets shouldn't replay identically.
  static final math.Random _tickRng = math.Random();

  /// Worlds a sector may hold before it counts as over-stacked.
  ///
  /// Set once by the shell from `GameSettings.planetsPerSector` rather than read
  /// from disk each tick: the tick runs every 30 seconds, and the cap is fixed
  /// at universe creation, so re-reading it would be 2,880 identical disk reads
  /// a session to learn something that cannot change. A universe regenerated
  /// with a new cap re-sets it, because the shell reloads settings.
  int worldCap = 3;

  /// Whose completed Citadels earn reputation this tick.
  ///
  /// Set by the shell from the active player, exactly like [worldCap] and
  /// [fedSpaceEnd] — the tick loads *every* player and has no notion of which
  /// one is being played, so it cannot work this out for itself. Null credits
  /// nothing.
  FactionClass? reputationFaction;

  /// Citadel tiers that finished on the [reputationFaction]'s own worlds since the
  /// shell last drained this, and so the reputation owed for them.
  ///
  /// Single-consumption on purpose: the shell pays it out and zeroes it in the
  /// same call. A field that merely accumulated would pay for the same upgrade
  /// again on every tick, which is the same shape as the per-tick production
  /// getters that consumed a remainder — the number would look right and the
  /// side effect would be the bug.
  int _unpaidConstructionReputation = 0;

  /// Reputation accrued by completed Citadel tiers, awaiting payout. Zero after
  /// [drainConstructionReputation].
  int drainConstructionReputation() {
    final owed = _unpaidConstructionReputation;
    _unpaidConstructionReputation = 0;
    return owed;
  }

  static void lockNpc(String npcId) => _lockedNpcIds.add(npcId);
  static void unlockNpc(String npcId) => _lockedNpcIds.remove(npcId);
  static bool isNpcLocked(String npcId) => _lockedNpcIds.contains(npcId);

  /// Removes destroyed NPCs from [npcs] in place. Returns the count
  /// cleared. Faction kill totals persist in CombatMetrics and bounties
  /// live on the board — the roster itself keeps only the living.
  static int clearWrecks(List<NpcShip> npcs) {
    final before = npcs.length;
    npcs.removeWhere((n) => n.isDestroyed);
    return before - npcs.length;
  }

  Timer? _timer;
  Duration tickInterval;
  bool _isRunning = false;

  void Function()? onTickStart;
  void Function(List<NpcShip> updatedNpcs)? onTickComplete;
  void Function(Object error)? onTickError;

  /// Fires when an NPC decides to attack the player during a tick.
  /// The NPC is already locked so it won't be processed again until
  /// the combat screen calls [unlockNpc].
  void Function(NpcAttackEvent event)? onNpcAttacksPlayer;

  /// When true, the player is docked at a port (in trade UI) and
  /// cannot be attacked. Set by [GameShell] when the port tab is active.
  bool playerDocked = false;

  /// Highest sector ID considered FedSpace — a no-combat zone.
  /// Set by [GameShell] from [GameSettings.fedSpaceEnd].
  int fedSpaceEnd = 0;

  GameTickService({
    this.tickInterval = const Duration(seconds: 30),
    this.onTickStart,
    this.onTickComplete,
    this.onTickError,
  });

  bool get isRunning => _isRunning;

  void start() {
    if (_isRunning) return;
    _isRunning = true;
    GameEventLog.global
        .system('[TickService] Started — interval: ${tickInterval.inSeconds}s');
    _timer = Timer.periodic(tickInterval, (_) => processTickNow());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _isRunning = false;
    GameEventLog.global.system('[TickService] Stopped');
  }

  void updateInterval(Duration newInterval) {
    tickInterval = newInterval;
    if (_isRunning) {
      stop();
      start();
    }
  }

  /// Runs a single game tick. Re-entrant calls (a previous tick still in
  /// flight — common at 1s dev intervals with BFS-heavy selections) are
  /// skipped and counted: concurrent ticks load/save the same JSON files,
  /// so overlapping runs double-count metrics while last-write-wins
  /// storage silently discards one run's NPC/cargo updates (phantom trade
  /// volume with no matching holdings). Public so tests can drive ticks
  /// without a timer.
  int overlapSkips = 0;
  bool _tickInProgress = false;

  Future<void> processTickNow() async {
    if (_tickInProgress) {
      overlapSkips++;
      GameEventLog.global
          .system('[TickService] Tick skipped — previous still running '
              '($overlapSkips overlaps so far)');
      return;
    }
    _tickInProgress = true;
    try {
      await _runTickBody();
    } finally {
      _tickInProgress = false;
    }
  }

  Future<void> _runTickBody() async {
    onTickStart?.call();

    try {
      final stopwatch = Stopwatch()..start();

      // Load fresh state from storage
      final sectors = await DevProfiler.instance.traceAsync(
          'tick_load_sectors', () => UniverseStorage.instance.loadUniverse());
      final npcs = await DevProfiler.instance
          .traceAsync('tick_load_npcs', () => NpcStorage().loadAll());
      final players = await DevProfiler.instance.traceAsync(
          'tick_load_players', () => PlayerStorage.instance.loadPlayers());

      if (sectors.isEmpty) {
        GameEventLog.global.system('[TickService] No sectors to process');
        onTickComplete?.call(npcs);
        return;
      }

      // An **empty roster is not a reason to skip the tick.** This guard used to
      // read `sectors.isEmpty || npcs.isEmpty`, and the second term quietly
      // switched off every colony in the galaxy: `PlanetProductionService` runs
      // below, so an empty NPC list meant no production, no supply bill, no
      // construction advance, and no colonist arrivals. A pilot working the
      // bounty board kills ships faster than the homeworld yards replace them,
      // so the roster can be driven to zero — and a purchased shipment then waits
      // forever on a tick that never runs the code which would deliver it.
      // Reported as "I waited ten minutes and the colonists never turned up".
      //
      // Colonies need no NPCs. The roster being empty makes the NPC loop a
      // no-op, which it already handles. What the roster *should* do is recover,
      // and `RepopulationService.produce` below does that once it is allowed to
      // run.

      // **The clock moves here and nowhere else.** `GameClock` is persisted, so
      // game time survives a restart instead of resetting to zero and
      // invalidating every stored cooldown deadline in the save.
      final tick = await GameClock.advance();

      // Regenerate port supply/demand + drift prices before NPC processing
      int portsRegened = 0;
      DevProfiler.instance.trace('tick_port_regen', () {
        for (final sector in sectors) {
          if (sector.hasPort && sector.port != null) {
            // One tick, one step. The tick service is the *only* thing that
            // advances a port's stock — closing the game stops the clock,
            // so a port that sold out overnight is still sold out on reopen.
            final regenerated = sector.port!.regenTick();
            if (regenerated != sector.port) {
              sector.port = regenerated;
              portsRegened++;
            }
            final drifted = sector.port!.applyDrift(_tickRng);
            if (!identical(drifted, sector.port)) {
              sector.port = drifted;
              portsRegened++;
            }
          }
        }
      });

      // Build proximity sets: sector IDs within 2 hops of ANY player
      // (single-player today, but the model already holds List<Player>).
      final closeSectors = <int>{};
      for (final p in players) {
        closeSectors.addAll(_reachableWithin(p.currentSectorId, sectors, 2));
      }

      // Owner index for the tick: O(sectors) once instead of per NPC.
      // _manageOwnedPorts reads it; null (tests) falls back to scanning.
      NpcAiService.ownedPortIndex = _buildOwnerIndex(sectors);

      // P2 roster + topology indices (same null-fallback contract).
      // Built from the pre-tick roster; see the staleness contract on
      // the index fields. try/finally: a throwing tick must never leak
      // a stale index into the next one.
      NpcAiService.beginTick(sectors, npcs, playerProximity: closeSectors);
      // Find NPCs with energy remaining and process them
      int processed = 0;
      int skipped = 0;
      int stranded = 0;
      int destroyed = 0;
      int errored = 0;
      final log = ActionLogProvider.global;

      try {
        DevProfiler.instance.trace('tick_npc_processing (${npcs.length} npcs)',
            () {
          for (int i = 0; i < npcs.length; i++) {
            final npc = npcs[i];
            if (npc.isDestroyed) {
              destroyed++;
              continue;
            }
            if (npc.energy <= 0) {
              // Pre-tick reading: processTurn may resolve this same tick via
              // the emergency-reserve path, so the counter can overcount
              // relative to end-of-tick reality. Log-scale only.
              stranded++;
            }
            if (isNpcLocked(npc.id)) {
              skipped++;
              continue;
            }

            final before = npc;
            try {
              npcs[i] = NpcAiService.processTurn(npc, sectors, players, npcs);
              _errorCounts.remove(npc.id);
            } catch (e) {
              // One bad NPC (bad data, failed assert) must never abort the
              // whole tick — keep its pre-tick state and move on. After 3
              // consecutive failures the goal is force-cleared so one
              // corrupted goal can't freeze an NPC for the session.
              errored++;
              final strikes = (_errorCounts[npc.id] ?? 0) + 1;
              _errorCounts[npc.id] = strikes;
              GameEventLog.global
                  .system('[TickService] NPC error (${npc.pilotName}): $e');
              if (strikes >= 3) {
                _errorCounts.remove(npc.id);
                npcs[i] = npc.copyWith(clearGoal: true);
                GameEventLog.global
                    .system('[TickService] ${npc.pilotName}: goal reset after '
                        '$strikes errors');
              }
              continue;
            }
            final after = npcs[i];
            processed++;

            // Log significant state changes (with proximity filter for non-combat)
            if (after.isDestroyed && !before.isDestroyed) {
              log.combat('${npc.pilotName} (${npc.shipName}) was destroyed');
            } else if (after.currentSectorId != before.currentSectorId) {
              // Only log movement if within 2 hops of player
              if (_isNearPlayer(after.currentSectorId, closeSectors) ||
                  _isNearPlayer(before.currentSectorId, closeSectors)) {
                log.movement(
                    '${npc.pilotName} warped to sector #${after.currentSectorId}');
              }
            }
            if (after.credits > before.credits + 5000) {
              // Only log trade if within 2 hops of player
              if (_isNearPlayer(after.currentSectorId, closeSectors)) {
                log.trade(
                    '${npc.pilotName} earned ${after.credits - before.credits} cr trading');
              }
            }
            if (after.kills > before.kills) {
              log.combat('${npc.pilotName} destroyed another vessel');
            }
          }
          if (errored > 0) {
            GameEventLog.global.system(
                '[TickService] $errored NPC(s) errored this tick (state kept)');
          }
        });
      } finally {
        NpcAiService.endTick();
      }

      // No turn replenishment: NPCs refuel at Hardware Emporiums, trickle-
      // charge via Solar Arrays, or take an emergency reserve when stranded
      // (see NpcAiService._handleStranded). Zero-energy NPCs are still
      // processed so they can recover.

      // Homeworld repopulation: without it, predation empties the galaxy
      // permanently (live: pirates wiped Duran/Vinari to zero in 20 min).
      DevProfiler.instance.trace('tick_repopulate', () {
        final spawned = RepopulationService.repopulate(sectors, npcs);
        if (spawned.isNotEmpty) {
          npcs.addAll(spawned);
          log.system(
              '${spawned.length} replacement ship(s) launched from homeworlds');
        }
      });

      // Homeworld production (C4a): controlled yards build on cadence
      // (productionTimer/spawnInterval) up to their caps. Floors recover,
      // production sustains.
      DevProfiler.instance.trace('tick_produce', () {
        final built = RepopulationService.produce(sectors, npcs);
        if (built.isNotEmpty) {
          npcs.addAll(built);
          log.system('${built.length} ship(s) rolled out from homeworld yards');
        }
      });

      // Homeworld colonist infusion: a capital grows its own colonists in bulk,
      // which is what makes buying them affordable — colonists cost
      // `ColonistSupply.costFor` PER colonist, so without a local supply two
      // identical colonies differed by 23x purely on capital distance.
      //
      // **Separate from the yard pass above**, though the gating is identical.
      // Folding it in would make `produce` grow populations as well as build
      // ships, and the name would then be wrong. The extra sweep is a few hundred
      // comparisons.
      DevProfiler.instance.trace('tick_colonist_infusion', () {
        final infused = RepopulationService.produceColonists(sectors);
        if (infused.isNotEmpty) {
          log.system('${infused.length} capital(s) produced colonists');
        }
      });

      // Colony production: the planet screen has always displayed a per-tick
      // rate, and until this existed nothing applied it — the only code that
      // wrote a planet's stores was the credits-based transfer in the screen.
      DevProfiler.instance.trace('tick_colony_production', () {
        final colonies = PlanetProductionService.process(
          sectors,
          // Scoped to the playing faction: the galaxy is full of Citadels the
          // player did not commission, and paying for those would be reputation
          // for free.
          creditFaction: reputationFaction,
        );
        if (colonies.constructionsCompleted > 0) {
          _unpaidConstructionReputation +=
              (colonies.constructionsCompleted * ReputationActions.upgradeWorld)
                  .round();
        }
        if (!colonies.isQuiet) {
          log.system(
            'Colonies: +${colonies.minerals} minerals, '
            '+${colonies.organics} organics, '
            '+${colonies.industrial} industrial, '
            '+${colonies.drones} drones'
            '${colonies.unsupplied > 0 ? ' · ${colonies.unsupplied} short of supply' : ''}',
          );
        }
        // No explicit save needed for a finished upgrade: this same pass ends
        // with a whole-universe write, so a level granted here is durable on
        // exactly the same footing as a tick of production.
      });

      // Trade jobs: a world's buy and sell orders, stepped one run at a time.
      //
      // Deliberately **its own pass** rather than folded into colony production,
      // so the whole feature hangs off one call. Removing it means deleting this
      // block and the service — nothing else changes.
      //
      // After colony production, so a delivery tops up a store that has already
      // taken this tick's output rather than being counted as part of it.
      //
      // **No player is passed, and that is the point.** The tick loads `players`
      // but never saves them, so crediting one here would be discarded. Sell
      // proceeds land in the *world's* `accumulatedRevenue` and its owner
      // withdraws them. See `PlanetTradeService.advanceAll`.
      //
      // This is **not** the clobber the shared universe fixed, and the
      // difference matters. `Sector` and `Planet` are mutable objects in one
      // shared graph, so a tick pass and a screen are looking at the same
      // instances. `Player` is immutable: every update is a `copyWith`, and each
      // holder has its own copy. `players` here is therefore a start-of-pass
      // snapshot in exactly the old way, and writing one back would discard any
      // screen-side update made since — the same class of bug the shared graph
      // removed for the universe, still fully live for players. Crediting a
      // player from the tick means holding an owed amount and draining it
      // somewhere the player actually is, which is what
      // `_applyFreightIndemnity` does in the shell.
      DevProfiler.instance.trace('tick_trade_jobs', () {
        // The shared `_tickRng` is threaded in so the per-run failure roll is
        // testable against a fixed generator and shares the tick's one
        // random stream (a probability tested with a live Random is a test of
        // the weather).
        final landed = PlanetTradeService.advanceAll(sectors, rng: _tickRng);
        if (landed.isNotEmpty) {
          var unitsArrived = 0;
          var unitsCollected = 0;
          for (final entry in landed.values) {
            // A delayed run delivers nothing *this* pass and is not lost — its
            // units are back on the order and the run is simply later. Counting
            // it here would report freight that has not arrived as if it had.
            if (entry.outcome == TradeRunOutcome.delayed) continue;
            if (entry.direction == TradeDirection.buy) {
              unitsArrived += entry.deliveredUnits;
            } else {
              unitsCollected += entry.deliveredUnits;
            }
          }
          // Every disruption is reported on its own line, in the player's
          // feed, naming what, how much and **why** — a silent loss reads as a
          // bug rather than a risk the player accepted, and an unnamed one
          // reads as a bug even when it is announced.
          //
          // **Three voices, because they are three different events.** A loss
          // is a warning and says the units are gone; a diversion is
          // informational, because nothing was lost and the only consequence
          // is a longer wait; a seizure is a warning but says the run *did*
          // arrive, less than quoted. Writing one template for all three is
          // what made the reason cosmetic — a player told "5.0K minerals lost"
          // when customs took a quarter of a run that otherwise landed has been
          // told something false, and a log that lies is worse than no log.
          for (final entry in landed.values) {
            final verb =
                entry.direction == TradeDirection.buy ? 'bought' : 'sold';
            final where = 'port #${entry.job.portSectorId}';
            switch (entry.outcome) {
              case TradeRunOutcome.delivered:
                break;
              case TradeRunOutcome.lost:
                // Whether cover paid out belongs in the same line as the loss. A
                // silent payout is as bad as a silent loss: the player sees a
                // warning, then credits they did not earn, and has no way to
                // connect the two — which is exactly the "it credits, but why"
                // report this whole feature exists to prevent.
                final covered = entry.insuredUnits > 0
                    ? ' Cover returned ${compact(entry.insuredUnits)} of it'
                        '${entry.direction == TradeDirection.buy ? ' in credits' : ' to stores'}.'
                    : '';
                log.warning(
                  'Freight lost: ${compact(entry.units)} '
                  '${entry.job.commodity} bound for $where — '
                  '${entry.cause?.label ?? 'lost in transit'}.'
                  '$covered The $verb order continues.',
                );
              case TradeRunOutcome.delayed:
                log.info(
                  'Freight diverted: ${compact(entry.units)} '
                  '${entry.job.commodity} bound for $where — '
                  '${entry.cause?.label ?? 'rerouted'}. '
                  'Nothing lost; arrival ${GameClock.estimate(entry.delayTicks)} later.',
                );
              case TradeRunOutcome.seized:
                log.warning(
                  'Freight impounded: ${compact(entry.seizedUnits)} of '
                  '${compact(entry.units)} ${entry.job.commodity} held at $where '
                  '— ${entry.cause?.label ?? 'seized by customs'}. '
                  '${compact(entry.deliveredUnits)} still delivered.',
                );
            }
          }
          if (unitsArrived > 0 || unitsCollected > 0) {
            log.system(
              'Trade: $unitsArrived units delivered, '
              '$unitsCollected collected'
              '${landed.isNotEmpty ? ' · ${landed.length} order(s) complete' : ''}',
            );
          }
        }
      });
      // Gravity checks on over-stacked systems. A sector's 24-hour clock starts
      // the moment it goes over the cap, so this is a due check rather than a
      // daily alarm, and calling it every pass is just arithmetic on a
      // timestamp.
      //
      // This is the call that was missing. The rule existed, was unit-tested,
      // and was never reached from anywhere in the app — so over-stacking
      // warned about a hazard that could not happen. A rule with no clock
      // attached to it is not a hazard, and its tests were measuring the rule
      // rather than the game.
      DevProfiler.instance.trace('tick_gravity_checks', () {
        WorldForging.runDueCollisions(
          sectors,
          worldCap,
          tick,
          _tickRng,
        );
      });

      // Combat census (C5): population-over-time for the soak review.
      // Capped ring — the steady state costs one count per tick.
      DevProfiler.instance.trace('tick_census', () {
        CombatMetrics.global
            .samplePopulation(RepopulationService.livingCounts(npcs));
      });

      // Bounty hygiene (bounty review M2 + escrow): drop marks on
      // vanished targets and lapsed TTLs (both refund escrow), then pay
      // queued refunds to roster NPCs before the save.
      DevProfiler.instance.trace('tick_bounty_prune', () {
        BountyBoard.global.pruneAbsent({
          for (final p in players) p.id,
          for (final n in npcs)
            if (!n.isDestroyed) n.id,
        });
        BountyBoard.global.pruneExpired();
        BountyBoard.global.settleNpcRefunds(npcs);
      });

      // Federation auto-posting (B4 enforcement): notorious pilots get
      // Federation bounties without anyone lifting a finger. This is the
      // Fed response to federal crimes — no police force, just money on
      // heads that any hunter can claim.
      DevProfiler.instance.trace('tick_fed_bounties', () {
        var posted = 0;
        void consider({
          required String id,
          required String name,
          required String faction,
          required bool isPlayer,
          required double evilness,
        }) {
          if (posted >= 3) return;
          final amount = BountyBoard.fedAmount(evilness);
          if (amount <= 0) return;
          if (BountyBoard.global.totalFor(id) > 0) return;
          BountyBoard.global.post(
            targetId: id,
            targetName: name,
            targetFaction: faction,
            targetIsPlayer: isPlayer,
            amount: amount,
            posterId: 'FEDERATION',
            posterName: 'Federation Marshal',
            reason: 'reputation -${evilness.toStringAsFixed(0)}',
          );
          // Bounty review: the player always learns their own mark —
          // Action Log warning, never hunter positions (those stay
          // behind an equipment upgrade, if ever).
          if (isPlayer) {
            ActionLogProvider.global.warning(
              'WANTED: Federation Marshal posted $amount cr on your head — '
              'hunters will come',
            );
          }
          posted++;
        }

        for (final player in players) {
          consider(
            id: player.id,
            name: player.name,
            faction: player.faction.name,
            isPlayer: true,
            evilness: player.threatRating,
          );
        }
        for (final npc in npcs) {
          if (npc.isDestroyed) continue;
          consider(
            id: npc.id,
            name: npc.pilotName,
            faction: npc.faction.name,
            isPlayer: false,
            evilness: npc.notoriety,
          );
        }
      });

      // NPC bank interest (Guild-rate parity with players).
      DevProfiler.instance.trace('tick_npc_interest', () {
        for (int i = 0; i < npcs.length; i++) {
          final npc = npcs[i];
          if (npc.isDestroyed || npc.bankBalance <= 0) continue;
          final rate = BankingAi.interestRateFor(
            npc.faction,
            npc.memory.factionStandings,
          );
          final accrual = BankingAi.accrueInterest(
            bankBalance: npc.bankBalance,
            lastInterestTick: npc.lastInterestTick,
            rate: rate,
            nowTick: tick,
          );
          if (accrual == null) continue;
          npcs[i] = npc.copyWith(
            bankBalance: npc.bankBalance + accrual.interest,
            lastInterestTick: accrual.stamp,
          );
          if (accrual.interest > 0) {
            GameEventLog.global.banking(
              '[${npc.pilotName}] Banking: +${accrual.interest} cr interest '
              '(${(rate * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      });

      // Wreckage clearing (soak fix, ex-P3#22): destroyed hulls used to
      // accumulate in the roster and every save (118 corpses vs 92 living
      // in one soak). All post-death consumers key off living ids and
      // faction totals persist in CombatMetrics — nothing reads a corpse
      // after its death tick.
      DevProfiler.instance.trace('tick_clear_wrecks', () {
        final cleared = GameTickService.clearWrecks(npcs);
        if (cleared > 0) {
          log.system('[TickService] Cleared $cleared wreck(s)');
        }
      });

      // Save all updated NPCs (wrecks cleared just above, so the save
      // only persists the living)
      await DevProfiler.instance
          .traceAsync('tick_save_npcs', () => NpcStorage().saveAll(npcs));

      // Save the universe. **Unconditionally.**
      //
      // This used to be gated on `portsRegened > 0 || processed > 0 ||
      // collided > 0`, a hand-maintained list of "things the tick might have
      // changed". Every entry was a way for a real mutation to be silently
      // discarded on the next read. The tick no longer re-parses between passes
      // — it shares one graph — so the mechanism is narrower than it was, but
      // not gone: the next read after a restart comes from the file, and
      // anything unwritten is lost then.
      //
      //  * `collided` was added after a collision happened in the object graph,
      //    was logged as having happened, and was resurrected on the next load —
      //    the player was told they lost two worlds and woke up to find both.
      //  * A colonist shipment's **countdown** was missing, which is worse than
      //    losing the arrival: nothing is logged when a counter decrements, so
      //    the countdown reset to its full delay on every tick and the shipment
      //    could never land at all. Reported as "I waited ten minutes and the
      //    colonists never turned up."
      //
      // A list of counters is not a substitute for saving. The pass mutates
      // sectors nearly every time — port drift alone is enough — so the gate was
      // saving by luck on most ticks and hiding its own failure on the rest,
      // which is the worst of both: it looks like an optimisation and behaves
      // like a coin flip. One JSON write per tick is not a cost worth optimising
      // against a correctness bug.
      await DevProfiler.instance.traceAsync('tick_save_sectors',
          () => UniverseStorage.instance.saveUniverse(sectors));

      // ── Check for NPC attacks on players (all of them, not just first) ──
      NpcAttackEvent? attackEvent;
      if (!playerDocked && players.isNotEmpty && onNpcAttacksPlayer != null) {
        DevProfiler.instance.trace('tick_attack_check', () {
          for (final player in players) {
            if (attackEvent != null) break; // One attack at a time
            final playerSectorId = player.currentSectorId;

            // No combat in FedSpace
            if (fedSpaceEnd > 0 && playerSectorId <= fedSpaceEnd) continue;
            for (final npc in npcs) {
              if (npc.isDestroyed || npc.energy <= 0) continue;
              if (isNpcLocked(npc.id)) continue;
              if (npc.currentSectorId != playerSectorId) continue;
              if (!NpcAiService.shouldAttackPlayer(npc, player)) continue;

              lockNpc(npc.id);
              Sector? sector;
              for (final s in sectors) {
                if (s.id == playerSectorId) {
                  sector = s;
                  break;
                }
              }
              if (sector == null) {
                // Data inconsistency: attacker and victim agree on a
                // sector the universe doesn't have. Log loudly instead of
                // fabricating an empty dummy (a combats screen built on
                // fake warp routes would silently break fleeing).
                GameEventLog.global.system(
                    '[TickService] Attack in unknown sector '
                    '#$playerSectorId (${npc.pilotName} vs ${player.name})');
                continue;
              }
              attackEvent = NpcAttackEvent(
                npc: npc,
                player: player,
                sectorWarps: List.from(sector.warpRoutes),
              );
              log.combat(
                  '${npc.pilotName} (${npc.shipName}) is attacking you in sector #$playerSectorId!');
              break;
            }
          }
        });
      }

      stopwatch.stop();
      DevProfiler.instance
          .record('tick_total', stopwatch.elapsedMicroseconds / 1000.0);
      GameEventLog.global
          .system('[TickService] Tick complete: $processed processed, '
              '$skipped skipped, $stranded stranded, $destroyed destroyed, '
              '$errored errored (${stopwatch.elapsedMilliseconds}ms) '
              '[$portsRegened ports regened]');

      onTickComplete?.call(npcs);

      // Fire attack callback after onTickComplete so GameShell is ready
      final finalAttackEvent = attackEvent;
      if (finalAttackEvent != null) {
        onNpcAttacksPlayer?.call(finalAttackEvent);
      }
    } catch (e) {
      GameEventLog.global.system('[TickService] Error: $e');
      onTickError?.call(e);
    }
  }

  /// Owner key (stable id, display-name fallback) → owned sectors.
  /// Built once per tick so owner management isn't O(sectors) per NPC.
  static Map<String, List<Sector>> _buildOwnerIndex(List<Sector> sectors) {
    final index = <String, List<Sector>>{};
    for (final s in sectors) {
      final port = s.port;
      if (port == null || !port.isOwned) continue;
      final id = port.ownerId;
      if (id != null && id.isNotEmpty) {
        (index[id] ??= []).add(s);
      }
      final name = port.owner;
      if (name != null && name.isNotEmpty) {
        (index[name] ??= []).add(s);
      }
    }
    return index;
  }

  /// Returns set of sector IDs within [maxHops] warps of [fromId].
  Set<int> _reachableWithin(int fromId, List<Sector> sectors, int maxHops) {
    final map = {for (final s in sectors) s.id: s};
    final visited = <int>{fromId};
    var edge = <int>[fromId];

    for (int hop = 0; hop < maxHops; hop++) {
      final next = <int>[];
      for (final id in edge) {
        final s = map[id];
        if (s == null) continue;
        for (final nid in s.warpRoutes) {
          if (visited.add(nid)) {
            next.add(nid);
          }
        }
      }
      edge = next;
    }

    return visited;
  }

  bool _isNearPlayer(int sectorId, Set<int> closeSectors) =>
      closeSectors.contains(sectorId);
}
