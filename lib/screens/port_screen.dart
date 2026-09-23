import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
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
  int _hackFailCount = 0;
  static const _maxHackAttempts = 3;
  static const _maxHackSessionAttempts = 5;

  Timer? _saveTimer;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _loadUniverse();
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

  void _applyHackPenalty(int failCount) {
    final penalties = <int, int>{1: 500, 2: 2500, 3: 5000, 4: 7500, 5: 10000};
    final penalty = penalties[failCount] ?? 0;
    final actualPenalty = min(penalty, widget.player.credits);
    final updated = widget.player.copyWith(
      credits: widget.player.credits - actualPenalty,
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
            if (outcome == 'captured') {
              final newList = List<String>.from(updatedPlayer.ownedPorts)
                ..add(updatedPort.name);
              widget.onPlayerUpdate(updatedPlayer.copyWith(
                ownedPorts: newList,
              ));
            } else {
              widget.onPlayerUpdate(updatedPlayer);
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
        onSuccess: (updated) {
          widget.onPlayerUpdate(updated);
          setState(() => _showHacking = false);
        },
        onFailure: (failCount) {
          setState(() {
            _hackFailCount = failCount;
            _showHacking = false;
          });
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
      hackFailCount: _hackFailCount,
      maxHackAttempts: _maxHackAttempts,
    );
  }
}
