import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/hardware_emporium_widget.dart';
import 'package:cosmic_trader/widgets/frequency_jamming_widget.dart';
import 'package:cosmic_trader/widgets/hacking_widget.dart';
import 'package:cosmic_trader/widgets/port_combat_screen.dart';
import 'package:cosmic_trader/widgets/buy_port_dialog.dart';
import 'package:cosmic_trader/widgets/port_trade_view.dart';

class PortScreen extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const PortScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<PortScreen> createState() => _PortScreenState();
}

class _PortScreenState extends State<PortScreen> {
  List<Sector> _allSectors = [];
  bool _loading = true;
  bool _showHacking = false;
  bool _showStealing = false;
  bool _showBuyPort = false;
  static const _maxHackAttempts = 3;
  static const _maxHackSessionAttempts = 5;

  Timer? _saveTimer;
  bool _dirty = false;

  // The parent persists player updates asynchronously. Keep the latest hack
  // state locally so the port UI updates immediately after a failed session.
  int? _pendingHackFailCount;
  int? _pendingHackBanUntil;

  @override
  void initState() {
    super.initState();
    _loadUniverse();
  }

  @override
  void didUpdateWidget(covariant PortScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.player != oldWidget.player) {
      _pendingHackFailCount = null;
      _pendingHackBanUntil = null;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _flushSave();
    super.dispose();
  }

  Future<void> _flushSave() async {
    if (!_dirty) return;
    _dirty = false;
    try {
      await UniverseStorage.instance.saveUniverse(_allSectors);
    } catch (_) {}
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), _flushSave);
  }

  void _updatePort(Port updatedPort) {
    final sector = _currentSector;
    if (sector == null) return;
    sector.port = updatedPort;
    if (mounted) setState(() {});
    _scheduleSave();
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
    } catch (e) {
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

  Port? get _port => _currentSector?.port;

  int get _hackFailCount {
    final portName = _port?.name;
    if (portName == null) return 0;

    if (_pendingHackFailCount != null) {
      final pendingBanUntil = _pendingHackBanUntil;
      if (pendingBanUntil != null &&
          pendingBanUntil <= DateTime.now().millisecondsSinceEpoch) {
        return 0;
      }
      return _pendingHackFailCount!;
    }

    final bannedUntil = widget.player.portHackBannedUntil[portName];
    if (bannedUntil != null &&
        bannedUntil <= DateTime.now().millisecondsSinceEpoch) {
      return 0;
    }
    return widget.player.portHackFailures[portName] ?? 0;
  }

  int? get _hackBanUntilEpoch {
    if (_pendingHackFailCount != null) return _pendingHackBanUntil;
    final portName = _port?.name;
    return portName == null
        ? null
        : widget.player.portHackBannedUntil[portName];
  }

  void _applyHackPenalty(int failCount) {
    final penalties = <int, int>{1: 500, 2: 2500, 3: 5000, 4: 7500, 5: 10000};
    final penalty = penalties[failCount] ?? 0;
    final player = widget.player;
    final actualPenalty = min(penalty, player.credits);
    final portName = _port?.name;
    final failures = Map<String, int>.from(player.portHackFailures);
    final bannedUntil = Map<String, int>.from(player.portHackBannedUntil);

    if (portName != null) {
      failures[portName] = failCount;
      if (failCount >= _maxHackAttempts) {
        bannedUntil[portName] = DateTime.now()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch;
      } else {
        bannedUntil.remove(portName);
      }
    }

    final newBanUntil = portName == null ? null : bannedUntil[portName];
    if (mounted) {
      setState(() {
        _pendingHackFailCount = failCount;
        _pendingHackBanUntil = newBanUntil;
      });
    }

    final updated = player.copyWith(
      credits: player.credits - actualPenalty,
      portHackFailures: failures,
      portHackBannedUntil: bannedUntil,
    );
    widget.onPlayerUpdate(updated);

    if (failCount >= _maxHackAttempts) {
      _showBanDialog();
    }
  }

  void _showBanDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0008),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFFF0040), width: 1.5),
        ),
        title: Row(
          children: [
            Icon(Icons.block_rounded, color: const Color(0xFFFF0040), size: 28),
            const SizedBox(width: 12),
            Text(
              'CONNECTION BANNED',
              style: TextStyle(
                fontFamily: 'monospace',
                color: const Color(0xFFFF0040),
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Port security has located your IP address.',
              style: TextStyle(
                fontFamily: 'monospace',
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0040).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF0040).withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.timer_rounded,
                    color: const Color(0xFFFF0040),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Blocked for 24 hours',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      color: const Color(0xFFFF0040),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'ACKNOWLEDGE',
              style: TextStyle(
                fontFamily: 'monospace',
                color: const Color(0xFFFF0040),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showPortAttackDialog(Port port) {
    _startPortCombat(port, 'capture');
  }

  void _startPortCombat(Port port, String mode) {
    final player = widget.player;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => PortCombatScreen(
          player: player,
          port: port,
          attackMode: mode,
          sectorId: player.currentSectorId,
          onCombatEnd:
              (Player updatedPlayer, Port updatedPort, String outcome) {
            var playerAfterCombat = updatedPlayer;
            if ((outcome == 'captured' || outcome == 'destroyed') &&
                updatedPort.ownerFaction != null) {
              playerAfterCombat = playerAfterCombat.withFactionStandingChange(
                updatedPort.ownerFaction!,
                -5,
              );
            }
            if (outcome == 'captured') {
              final newList = List<String>.from(playerAfterCombat.ownedPorts)
                ..add(updatedPort.name);
              widget.onPlayerUpdate(playerAfterCombat.copyWith(
                ownedPorts: newList,
              ));
            } else {
              widget.onPlayerUpdate(playerAfterCombat);
            }
            _updatePort(updatedPort);

            switch (outcome) {
              case 'captured':
                _showSnackBar(
                    'Port captured! You are now the owner. +10 notoriety.');
                break;
              case 'destroyed':
                _showSnackBar('Port destroyed! +20 notoriety.');
                break;
              case 'fled':
                _showSnackBar('You fled from the port. +5 notoriety.');
                break;
              case 'attackerDefeated':
                _showSnackBar('You were defeated! Port restored shields.');
                break;
              case 'spared':
                _showSnackBar('You spared the port.');
                break;
            }
          },
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showHackCodex() {
    final player = widget.player;
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.menu_book_rounded, size: 22),
              SizedBox(width: 8),
              Text('HACK CODEX'),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
            child: player.hackedPorts.isEmpty
                ? const Text('No successful port intrusions recorded.')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${player.successfulHacks} successful breach${player.successfulHacks == 1 ? '' : 'es'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (player.lastHackAt != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Last breach: ${player.lastHackAt!.toLocal()}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                      if (player.lastHackProfile != null ||
                          player.lastHackReward != null) ...[
                        const SizedBox(height: 8),
                        if (player.lastHackProfile != null)
                          Text(
                            'Last profile: ${player.lastHackProfile}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        if (player.lastHackReward != null)
                          Text(
                            'Last extraction: ${player.lastHackReward}',
                            style: const TextStyle(fontSize: 11),
                          ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        'FACTION STANDING',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          color: Theme.of(dialogContext)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final faction in FactionClass.values)
                            _factionStandingChip(
                              faction,
                              player.factionStandingWith(faction),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (var index = 0;
                                  index < player.hackedPorts.length;
                                  index++) ...[
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.lock_open_rounded),
                                  title: Text(player.hackedPorts[index]),
                                  subtitle:
                                      const Text('Security code bypassed'),
                                ),
                                if (index < player.hackedPorts.length - 1)
                                  const Divider(height: 1),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CLOSE'),
            ),
          ],
        );
      },
    );
  }

  Widget _factionStandingChip(
    FactionClass faction,
    int standing,
  ) {
    final color = standing >= 25
        ? Colors.green
        : standing <= -30
            ? Colors.red
            : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        '${faction.displayName}: $standing',
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 10,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_port == null) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.store_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No port in this sector',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_port!.isHardwareEmporium) {
      return HardwareEmporiumWidget(
        player: widget.player,
        port: _port!,
        onPlayerUpdate: widget.onPlayerUpdate,
      );
    }

    if (_showHacking) {
      return HackingWidget(
        player: widget.player,
        port: _port,
        failCount: _hackFailCount,
        maxAttempts: _maxHackSessionAttempts,
        maxFailures: _maxHackAttempts,
        banUntilEpoch: _hackBanUntilEpoch,
        onSuccess: (updated) {
          final hackedPorts = List<String>.from(updated.hackedPorts);
          final portName = _port?.name;
          if (portName != null && !hackedPorts.contains(portName)) {
            hackedPorts.add(portName);
          }

          final isSabotage =
              updated.lastHackReward?.startsWith('SABOTAGE') ?? false;
          final factionStandings =
              Map<String, int>.from(updated.factionStandings);
          final ownerFaction = _port?.ownerFaction;
          if (ownerFaction != null) {
            final delta = isSabotage ? -8 : -2;
            factionStandings[ownerFaction.name] =
                (updated.factionStandingWith(ownerFaction) + delta)
                    .clamp(-100, 100)
                    .toInt();
          }

          widget.onPlayerUpdate(updated.copyWith(
            successfulHacks: updated.successfulHacks + 1,
            hackedPorts: hackedPorts,
            lastHackAt: DateTime.now(),
            factionStandings: factionStandings,
            notoriety: updated.notoriety + (isSabotage ? 5 : 1),
          ));
          if (ownerFaction != null) {
            _showSnackBar(
              '${ownerFaction.displayName} standing ${isSabotage ? '-8' : '-2'} from the intrusion.',
            );
          }
          setState(() {
            _pendingHackFailCount = null;
            _pendingHackBanUntil = null;
            _showHacking = false;
          });
        },
        onPortModified: _updatePort,
        onFailure: (failCount) {
          setState(() => _showHacking = false);
          _applyHackPenalty(failCount);
        },
        onCancel: () => setState(() => _showHacking = false),
      );
    }

    if (_showStealing) {
      return FrequencyJammingWidget(
        player: widget.player,
        onSuccess: (updated) {
          widget.onPlayerUpdate(updated);
          setState(() => _showStealing = false);
        },
        onFailure: () {
          setState(() => _showStealing = false);
        },
        onCancel: () => setState(() => _showStealing = false),
      );
    }

    if (_showBuyPort) {
      return BuyPortDialog(
        port: _port!,
        player: widget.player,
        onPlayerUpdate: widget.onPlayerUpdate,
        onPortUpdated: _updatePort,
        onCancel: () => setState(() => _showBuyPort = false),
      );
    }

    return PortTradeView(
      port: _port!,
      player: widget.player,
      onPlayerUpdate: widget.onPlayerUpdate,
      onPortUpdated: _updatePort,
      onHackPort: () => setState(() => _showHacking = true),
      onStealResources: () => setState(() => _showStealing = true),
      onBuyPort: () => setState(() => _showBuyPort = true),
      onAttackPort: () => _showPortAttackDialog(_port!),
      onOpenHackCodex: _showHackCodex,
      hackFailCount: _hackFailCount,
      maxHackAttempts: _maxHackAttempts,
      hackBannedUntilEpoch: _hackBanUntilEpoch,
      onBanExpired: () => setState(() {}),
    );
  }
}
