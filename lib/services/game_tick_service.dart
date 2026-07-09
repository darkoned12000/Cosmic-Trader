import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:tradewars_2050/data/models/npc_ship.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/sector.dart';
import 'package:tradewars_2050/data/storage/npc_storage.dart';
import 'package:tradewars_2050/data/storage/player_storage.dart';
import 'package:tradewars_2050/data/storage/universe_storage.dart';
import 'package:tradewars_2050/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:tradewars_2050/services/npc_ai/npc_ai_service.dart';
import 'package:tradewars_2050/widgets/dev_profiler.dart';

/// Describes an NPC-initated attack on a player during a tick.

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
    debugPrint('[TickService] Started — interval: ${tickInterval.inSeconds}s');
    _timer = Timer.periodic(tickInterval, (_) => _processTick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _isRunning = false;
    debugPrint('[TickService] Stopped');
  }

  void updateInterval(Duration newInterval) {
    tickInterval = newInterval;
    if (_isRunning) {
      stop();
      start();
    }
  }

  Future<void> _processTick() async {
    if (!_isRunning) return;

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
        debugPrint('[TickService] No sectors or NPCs to process');
        onTickComplete?.call(npcs);
        return;
      }

      // Regenerate port supply/demand before NPC processing
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
          }
        }
      });

      // Build proximity set: sector IDs within 2 hops of the player
      final playerSector =
          players.isNotEmpty ? players.first.currentSectorId : 0;
      final closeSectors = _reachableWithin(playerSector, sectors, 2);

      // Find NPCs with turns remaining and process them
      int processed = 0;
      int skipped = 0;
      int destroyed = 0;
      final log = ActionLogProvider.global;

      DevProfiler.instance.trace('tick_npc_processing (${npcs.length} npcs)',
          () {
        for (int i = 0; i < npcs.length; i++) {
          final npc = npcs[i];
          if (npc.isDestroyed) {
            destroyed++;
            continue;
          }
          if (npc.turns <= 0) {
            skipped++;
            continue;
          }
          if (isNpcLocked(npc.id)) {
            skipped++;
            continue;
          }

          final before = npc;
          npcs[i] = NpcAiService.processTurn(npc, sectors, players, npcs);
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
      });

      // Replenish turns for NPCs that have run out (every 60 ticks ~ 30min at 30s)
      // This prevents NPCs from going permanently idle
      if (skipped > 0 && _runsSinceLastReplenish++ % 60 == 0) {
        DevProfiler.instance.trace('tick_replenish_turns', () {
          int replenished = 0;
          for (int i = 0; i < npcs.length; i++) {
            if (npcs[i].turns <= 0 && !npcs[i].isDestroyed) {
              npcs[i] = npcs[i].copyWith(turns: 200);
              replenished++;
            }
          }
          if (replenished > 0) {
            debugPrint(
                '[TickService] Replenished turns for $replenished idle NPCs');
          }
        });
      }

      // Save all updated NPCs (destroyed ones retained for stats/history)
      await DevProfiler.instance
          .traceAsync('tick_save_npcs', () => NpcStorage().saveAll(npcs));

      // Save sectors if ports were regenerated or NPCs mutated them
      if (portsRegened > 0 || processed > 0) {
        await DevProfiler.instance.traceAsync('tick_save_sectors',
            () => UniverseStorage.instance.saveUniverse(sectors));
      }

      // ── Check for NPC attacks on the player ──
      NpcAttackEvent? attackEvent;
      if (!playerDocked && players.isNotEmpty && onNpcAttacksPlayer != null) {
        DevProfiler.instance.trace('tick_attack_check', () {
          final player = players.first;
          final playerSectorId = player.currentSectorId;

          // No combat in FedSpace
          if (fedSpaceEnd <= 0 || playerSectorId > fedSpaceEnd) {
            for (final npc in npcs) {
              if (npc.isDestroyed || npc.turns <= 0) continue;
              if (isNpcLocked(npc.id)) continue;
              if (npc.currentSectorId != playerSectorId) continue;
              if (!NpcAiService.shouldAttackPlayer(npc, player)) continue;

              lockNpc(npc.id);
              final sector = sectors.firstWhere(
                (s) => s.id == playerSectorId,
                orElse: () =>
                    Sector(id: 0, name: '', x: 0, y: 0, warpRoutes: const []),
              );
              attackEvent = NpcAttackEvent(
                npc: npc,
                player: player,
                sectorWarps: List.from(sector.warpRoutes),
              );
              log.combat(
                  '${npc.pilotName} (${npc.shipName}) is attacking you in sector #$playerSectorId!');
              break; // One attack at a time
            }
          }
        });
      }

      stopwatch.stop();
      DevProfiler.instance
          .record('tick_total', stopwatch.elapsedMicroseconds / 1000.0);
      debugPrint('[TickService] Tick complete: $processed processed, '
          '$skipped skipped, $destroyed destroyed '
          '(${stopwatch.elapsedMilliseconds}ms) '
          '[$portsRegened ports regened]');

      onTickComplete?.call(npcs);

      // Fire attack callback after onTickComplete so GameShell is ready
      final finalAttackEvent = attackEvent;
      if (finalAttackEvent != null) {
        onNpcAttacksPlayer?.call(finalAttackEvent);
      }
    } catch (e) {
      debugPrint('[TickService] Error: $e');
      onTickError?.call(e);
    }
  }

  int _runsSinceLastReplenish = 0;

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
