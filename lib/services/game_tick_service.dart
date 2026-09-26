import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/banking_ai.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
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

  static void lockNpc(String npcId) => _lockedNpcIds.add(npcId);
  static void unlockNpc(String npcId) => _lockedNpcIds.remove(npcId);
  static bool isNpcLocked(String npcId) => _lockedNpcIds.contains(npcId);

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

      if (sectors.isEmpty || npcs.isEmpty) {
        GameEventLog.global
            .system('[TickService] No sectors or NPCs to process');
        onTickComplete?.call(npcs);
        return;
      }

      // Regenerate port supply/demand + drift prices before NPC processing
      int portsRegened = 0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      DevProfiler.instance.trace('tick_port_regen', () {
        for (final sector in sectors) {
          if (sector.hasPort && sector.port != null) {
            final regenerated = sector.port!.regen(now: nowMs);
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

      // Find NPCs with energy remaining and process them
      int processed = 0;
      int skipped = 0;
      int stranded = 0;
      int destroyed = 0;
      int errored = 0;
      final log = ActionLogProvider.global;

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
          required double notoriety,
        }) {
          if (posted >= 3) return;
          final amount = BountyBoard.fedAmount(notoriety);
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
            reason: 'notoriety ${notoriety.toStringAsFixed(0)}',
          );
          posted++;
        }

        for (final player in players) {
          consider(
            id: player.id,
            name: player.name,
            faction: player.faction.name,
            isPlayer: true,
            notoriety: player.notoriety,
          );
        }
        for (final npc in npcs) {
          if (npc.isDestroyed) continue;
          consider(
            id: npc.id,
            name: npc.pilotName,
            faction: npc.faction.name,
            isPlayer: false,
            notoriety: npc.notoriety,
          );
        }
      });

      // NPC bank interest (Guild-rate parity with players).
      DevProfiler.instance.trace('tick_npc_interest', () {
        final now = DateTime.now();
        for (int i = 0; i < npcs.length; i++) {
          final npc = npcs[i];
          if (npc.isDestroyed || npc.bankBalance <= 0) continue;
          final rate = BankingAi.interestRateFor(
            npc.faction,
            npc.memory.factionStandings,
          );
          final accrual = BankingAi.accrueInterest(
            bankBalance: npc.bankBalance,
            lastInterestTime: npc.lastInterestTime,
            rate: rate,
            now: now,
          );
          if (accrual == null) continue;
          npcs[i] = npc.copyWith(
            bankBalance: npc.bankBalance + accrual.interest,
            lastInterestTime: accrual.stamp,
          );
          if (accrual.interest > 0) {
            GameEventLog.global.banking(
              '[${npc.pilotName}] Banking: +${accrual.interest} cr interest '
              '(${(rate * 100).toStringAsFixed(1)}%)',
            );
          }
        }
      });

      // Save all updated NPCs (destroyed ones retained for stats/history)
      await DevProfiler.instance
          .traceAsync('tick_save_npcs', () => NpcStorage().saveAll(npcs));

      // Save sectors if ports were regenerated or NPCs mutated them
      if (portsRegened > 0 || processed > 0) {
        await DevProfiler.instance.traceAsync('tick_save_sectors',
            () => UniverseStorage.instance.saveUniverse(sectors));
      }

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
