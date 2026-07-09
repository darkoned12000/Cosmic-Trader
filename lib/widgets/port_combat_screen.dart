import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/port.dart';
import 'package:tradewars_2050/data/models/port_defense_config.dart';
import 'package:tradewars_2050/services/npc_ai/port_combat_service.dart';

class PortCombatScreen extends StatefulWidget {
  final Player player;
  final Port port;
  final String attackMode;
  final int sectorId;
  final Function(Player updatedPlayer, Port updatedPort, String outcome)
      onCombatEnd;

  const PortCombatScreen({
    super.key,
    required this.player,
    required this.port,
    required this.attackMode,
    required this.sectorId,
    required this.onCombatEnd,
  });

  @override
  State<PortCombatScreen> createState() => _PortCombatScreenState();
}

class _PortCombatScreenState extends State<PortCombatScreen>
    with TickerProviderStateMixin {
  late Player _player;
  late Port _port;
  late final List<String> _combatLog;
  late AnimationController _atkAnimController;
  late AnimationController _defAnimController;
  late AnimationController _droneAnimController;
  bool _animating = false;
  bool _combatOver = false;
  bool _portSurrendered = false;
  int _dronesToSend = 0;
  int _dronesLost = 0;
  int _dronesReturned = 0;
  int _round = 0;
  int _droneSwarmCount = 0;

  static const _droneHp = 15;

  final List<double> _dronePhases = [];
  final List<double> _droneOffsets = [];
  bool _droneSeeded = false;

  void _seedDrones(int count) {
    if (_droneSeeded && _dronePhases.length >= count) return;
    _dronePhases.clear();
    _droneOffsets.clear();
    final rng = math.Random(_port.name.hashCode ^ DateTime.now().microsecondsSinceEpoch);
    for (int i = 0; i < count; i++) {
      _dronePhases.add(rng.nextDouble() * math.pi * 2);
      _droneOffsets.add((rng.nextDouble() - 0.5) * 2);
    }
    _droneSeeded = true;
  }

  @override
  void initState() {
    super.initState();
    _player = widget.player;
    _port = widget.port;
    _combatLog = [];

    _atkAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _defAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _droneAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _combatLog.add('PORT ATTACK — ${_port.name}');
    _combatLog.add('Mode: ${widget.attackMode.toUpperCase()}');
    _combatLog.add('Your hull: ${_player.hull}/${_player.maxHull}  '
        'Shields: ${_player.shields}/${_player.maxShields}');
    _combatLog.add('Port shields: ${_port.currentShields}/${_port.maxShields}  '
        'Defense L${_port.defenseLevel}');
  }

  @override
  void dispose() {
    _atkAnimController.dispose();
    _defAnimController.dispose();
    _droneAnimController.dispose();
    super.dispose();
  }

  int get _playerFirepower {
    int total = 0;
    _player.weaponSlots.forEach((slot, level) {
      final typeName = _player.weaponTypes[slot] ?? 'autoLaser';
      final wt = WeaponType.values.firstWhere(
        (w) => w.name == typeName,
        orElse: () => WeaponType.autoLaser,
      );
      total += wt.damage * level;
    });
    total += (_player.hullEquipmentLevel - 1) * 5;
    return total;
  }

  int get _portFirepower =>
      PortDefenseConfig.defenseStats(_port.defenseLevel).firepower;

  int _calcDamage(int power) =>
      (power * (0.8 + math.Random().nextDouble() * 0.4)).round().clamp(1, 99999);

  Future<void> _fire() async {
    if (_animating || _combatOver) return;

    setState(() => _animating = true);
    _round++;

    // Initialize port shields on first fire
    if (_port.currentShields <= 0 && !_port.isUnderAttack) {
      _port = _port.copyWith(
        currentShields: PortCombatService.initPortShields(_port.defenseLevel),
        isUnderAttack: true,
        attackerId: _player.id,
        attackMode: widget.attackMode,
      );
    }

    final dronesSent = _dronesToSend;
    final droneDmg = dronesSent * _droneHp;
    final weaponDmg = _calcDamage(_playerFirepower);
    final totalAtkDamage = weaponDmg + droneDmg;
    final portStats = PortDefenseConfig.defenseStats(_port.defenseLevel);

    // Apply player attack to port shields
    var portShields = _port.currentShields;
    int remainingAtk = totalAtkDamage;
    if (portShields > 0) {
      if (remainingAtk <= portShields) {
        portShields -= remainingAtk;
        remainingAtk = 0;
      } else {
        remainingAtk -= portShields;
        portShields = 0;
      }
    }

    final portSurrenderedThisRound =
        portShields <= _port.captureThreshold;

    // Only process port return fire if port still defends
    int dronesDestroyed = 0;
    int dronesReturning = 0;
    int rawPortDmg = 0;
    var playerShields = _player.shields;
    var playerHull = _player.hull;

    if (portSurrenderedThisRound) {
      // Port surrenders — no return fire, all drones return
      dronesReturning = dronesSent;
      _combatLog.add('Port shields depleted — port surrenders!');
    } else {
      rawPortDmg = _calcDamage(_portFirepower);

      // Add special ability bonuses
      if (portStats.hasCounterAttack) {
        final bonusDmg = (_portFirepower * 0.3).round();
        rawPortDmg += bonusDmg;
        _combatLog.add('Port counter-attack deals +$bonusDmg damage!');
      }
      if (portStats.hasEmpBurst) {
        final empDrain = (playerShields * portStats.empDrainPct).round();
        playerShields = (playerShields - empDrain).clamp(0, _player.maxShields);
        if (empDrain > 0) {
          _combatLog.add('EMP burst drains $empDrain shields!');
        }
      }

      // Drones intercept port fire
      if (dronesSent > 0) {
        dronesDestroyed = math.min(dronesSent, (rawPortDmg / _droneHp).ceil());
        dronesReturning = dronesSent - dronesDestroyed;
        final dmgToPlayer =
            (rawPortDmg - dronesDestroyed * _droneHp).clamp(0, rawPortDmg);
        var remainingDef = dmgToPlayer;

        if (playerShields > 0) {
          if (remainingDef <= playerShields) {
            playerShields -= remainingDef;
            remainingDef = 0;
          } else {
            remainingDef -= playerShields;
            playerShields = 0;
          }
        }
        if (remainingDef > 0) {
          playerHull = (playerHull - remainingDef).clamp(0, _player.maxHull);
        }
      } else {
        var remainingDef = rawPortDmg;
        if (playerShields > 0) {
          if (remainingDef <= playerShields) {
            playerShields -= remainingDef;
            remainingDef = 0;
          } else {
            remainingDef -= playerShields;
            playerShields = 0;
          }
        }
        if (remainingDef > 0) {
          playerHull = (playerHull - remainingDef).clamp(0, _player.maxHull);
        }
      }
    }

    // Consume & return drones
    if (dronesSent > 0) {
      _dronesLost += dronesDestroyed;
      _dronesReturned += dronesReturning;
    }
    final newDroneCount = (_player.drones - dronesSent) + dronesReturning;
    final playerDefeated = playerHull <= 0;

    // Animate drone swarm
    if (dronesSent > 0) {
      _seedDrones(dronesSent.clamp(3, 20));
      setState(() {
        _droneSwarmCount = dronesSent;
        _droneAnimController.value = 0.0;
      });
      _droneAnimController.forward();
      await Future.delayed(const Duration(milliseconds: 400));
    }

    // Animate attack
    await _atkAnimController.forward();
    await _atkAnimController.reverse();

    _combatLog.add('> Round $_round: You dealt $weaponDmg dmg | '
        'Port shields: ${portShields.clamp(0, _port.maxShields)}/${_port.maxShields}');
    if (droneDmg > 0) {
      _combatLog.add('  Drones: $dronesSent sent (+$droneDmg dmg)');
    }

    if (!portSurrenderedThisRound) {
      await _defAnimController.forward();
      await _defAnimController.reverse();
      _combatLog.add('> Port dealt $rawPortDmg dmg');
      if (dronesDestroyed > 0) {
        _combatLog.add('  Drones intercepted: $dronesDestroyed destroyed, '
            '$dronesReturning returned');
      }
      _combatLog.add('  Your shields: ${playerShields.clamp(0, _player.maxShields)}/${_player.maxShields}  '
          'hull: ${playerHull.clamp(0, _player.maxHull)}/${_player.maxHull}');
    }

    setState(() {
      _port = _port.copyWith(
        currentShields: portShields.clamp(0, _port.maxShields),
      );
      _player = _player.copyWith(
        hull: playerHull.clamp(0, _player.maxHull),
        shields: playerShields.clamp(0, _player.maxShields),
        drones: newDroneCount,
      );
      _dronesToSend = 0;
      _animating = false;
    });

    if (portSurrenderedThisRound) {
      _portSurrendered = true;
      Future.delayed(const Duration(milliseconds: 600), _showSurrenderDialog);
    } else if (playerDefeated) {
      _combatLog.add('*** YOUR SHIP IS CRITICALLY DAMAGED ***');
      _endCombat(outcome: 'attackerDefeated');
    }
  }

  void _showSurrenderDialog() {
    if (!mounted || _portSurrendered) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('PORT SURRENDERS',
            style: TextStyle(fontFamily: 'monospace', color: Colors.white)),
        content: const Text('The port has surrendered. Choose your action.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _doCapture();
            },
            child: const Text('Capture Port',
                style: TextStyle(fontFamily: 'monospace')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _doDestroy();
            },
            child: const Text('Destroy Port',
                style: TextStyle(fontFamily: 'monospace', color: Colors.red)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              _endCombat(outcome: 'spared');
            },
            child: const Text('Spare',
                style: TextStyle(fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }

  void _doCapture() {
    _combatLog.add('>>> Port captured! You are now the owner. <<<');
    _combatLog.add('+10 notoriety');
    _endCombat(outcome: 'captured');
  }

  void _doDestroy() {
    _combatLog.add('>>> Port destroyed! <<<');
    _combatLog.add('+20 notoriety');
    _endCombat(outcome: 'destroyed');
  }

  void _flee() {
    _combatLog.add('>>> You fled from the port <<<');
    _endCombat(outcome: 'fled');
  }

  void _endCombat({required String outcome}) {
    setState(() => _combatOver = true);

    Port finalPort;
    Player finalPlayer;

    switch (outcome) {
      case 'captured':
        finalPort = PortCombatService.capturePort(
          _port,
          _player.name,
          _player.faction.name,
        );
        finalPlayer = _player.copyWith(
          notoriety: (_player.notoriety + 10).clamp(0, 100),
        );
        break;
      case 'destroyed':
        finalPort = PortCombatService.destroyPort(_port);
        finalPlayer = _player.copyWith(
          notoriety: (_player.notoriety + 20).clamp(0, 100),
        );
        break;
      case 'fled':
        finalPort = PortCombatService.endCombatRetreat(_port);
        finalPlayer = _player.copyWith(
          notoriety: (_player.notoriety + 5).clamp(0, 100),
        );
        break;
      case 'attackerDefeated':
        finalPort = PortCombatService.endCombatRetreat(_port);
        finalPlayer = _player.copyWith(hull: _player.hull.clamp(0, _player.maxHull));
        break;
      default:
        finalPort = PortCombatService.endCombatRetreat(_port);
        finalPlayer = _player;
    }

    _port = finalPort;
    _player = finalPlayer;

    widget.onCombatEnd(finalPlayer, finalPort, outcome);
  }

  void _copyLog() {
    Clipboard.setData(ClipboardData(text: _combatLog.join('\n')));
    // ignore: use_build_context_synchronously
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Combat log copied to clipboard',
            style: TextStyle(fontFamily: 'monospace')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _closeCombat() {
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text('PORT ATTACK: ${_port.name.toUpperCase()}',
            style: const TextStyle(fontFamily: 'monospace', letterSpacing: 1)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 18),
            tooltip: 'Copy combat log',
            onPressed: _copyLog,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: _buildVisual(cs),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                _statColumn('YOU', Colors.cyan, _player, false),
                const SizedBox(width: 16),
                _portStatColumn(cs),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade800),
          Expanded(
            flex: 2,
            child: Container(
              color: const Color(0xFF050505),
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: _combatLog.length,
                itemBuilder: (_, i) => Text(
                  _combatLog[i],
                  style: TextStyle(
                    color: _combatLog[i].startsWith('***')
                        ? Colors.red.shade300
                        : _combatLog[i].startsWith('>>>')
                            ? Colors.amber.shade300
                            : _combatLog[i].startsWith('>')
                                ? Colors.white70
                                : Colors.white54,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade800),
          Container(
            color: Colors.grey.shade900,
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!_combatOver)
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Chip(
                        label: Text(
                          'ROUND ${_round + 1}',
                          style: const TextStyle(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.white70,
                          ),
                        ),
                        backgroundColor: Colors.white.withValues(alpha: 0.05),
                        side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (_player.drones > 0) ...[
                        _droneChip(cs),
                        _droneStepper(cs),
                      ],
                    ],
                  ),
                const SizedBox(height: 8),
                _actionButtons(cs),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVisual(ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        return Stack(
          children: [
            CustomPaint(
              size: Size(w, h),
              painter: _StarfieldPainter(),
            ),
            CustomPaint(
              size: Size(w, h),
              painter: _PortCombatPainter(
                playerHull: _player.hull / _player.maxHull,
                playerShields: _player.shields / _player.maxShields,
                portShields: _port.currentShields / _port.maxShields,
                portFirepower: _portFirepower / 300.0,
                atkProgress: _atkAnimController,
                defProgress: _defAnimController,
                droneProgress: _droneAnimController,
                droneCount: _droneSwarmCount,
                dronePhases: _dronePhases,
                droneOffsets: _droneOffsets,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statColumn(String label, Color color, Player p, bool isPort) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _bar('HULL', p.hull, p.maxHull, Colors.green.shade400),
          const SizedBox(height: 2),
          _bar('SHD', p.shields, p.maxShields, Colors.cyan.shade300),
        ],
      ),
    );
  }

  Widget _portStatColumn(ColorScheme cs) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('PORT',
              style: TextStyle(
                  color: Colors.red.shade300,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          _bar('SHD', _port.currentShields, _port.maxShields, _getShieldColor()),
          const SizedBox(height: 2),
          Row(
            children: [
              SizedBox(
                  width: 28,
                  child: Text('DEF',
                      style: const TextStyle(
                          fontSize: 9,
                          fontFamily: 'monospace',
                          color: Colors.white54))),
              const SizedBox(width: 4),
              Text('L${_port.defenseLevel}',
                  style: const TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: Colors.white54)),
            ],
          ),
        ],
      ),
    );
  }

  Color _getShieldColor() {
    final ratio = _port.currentShields / _port.maxShields;
    if (ratio > 0.6) return Colors.red.shade300;
    if (ratio > 0.3) return Colors.orange.shade300;
    return Colors.red.shade700;
  }

  Widget _bar(String label, int current, int max, Color color) {
    final pct = max > 0 ? current / max : 0.0;
    return Row(
      children: [
        SizedBox(
            width: 28,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: Colors.white54))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              backgroundColor: Colors.white.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation(color),
              minHeight: 8,
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 50,
          child: Text('$current/$max',
              style: const TextStyle(
                  fontSize: 9, fontFamily: 'monospace', color: Colors.white54)),
        ),
      ],
    );
  }

  Widget _droneChip(ColorScheme cs) {
    final active = _dronesToSend > 0;
    return FilterChip(
      label: Text(
        'DRONES',
        style: TextStyle(
          fontSize: 10,
          fontFamily: 'monospace',
          color: active ? Colors.white : Colors.white54,
        ),
      ),
      selected: active,
      onSelected: (v) => setState(() {
        _dronesToSend = v ? _player.drones.clamp(1, 99) : 0;
      }),
      selectedColor: Colors.orange.shade800.withValues(alpha: 0.3),
      checkmarkColor: Colors.orange,
      backgroundColor: Colors.white.withValues(alpha: 0.05),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      side: BorderSide(
        color: active
            ? Colors.orange.shade300
            : Colors.white.withValues(alpha: 0.15),
      ),
    );
  }

  Widget _droneStepper(ColorScheme cs) {
    final totalAvail = _player.drones + _dronesReturned - _dronesLost;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _RepeatButton(
          icon: Icons.remove_rounded,
          onStep: () => setState(
              () => _dronesToSend = (_dronesToSend - 1).clamp(0, totalAvail)),
        ),
        GestureDetector(
          onTap: () => _showDroneInputDialog(totalAvail),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$_dronesToSend',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: _dronesToSend > 0
                    ? Colors.orange.shade300
                    : Colors.white54,
              ),
            ),
          ),
        ),
        _RepeatButton(
          icon: Icons.add_rounded,
          onStep: () => setState(
              () => _dronesToSend = (_dronesToSend + 1).clamp(0, totalAvail)),
        ),
        const SizedBox(width: 6),
        Text(
          '/ $totalAvail',
          style: const TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: Colors.white38,
          ),
        ),
        if (_dronesLost > 0 || _dronesReturned > 0)
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: Text(
              '(-$_dronesLost / +$_dronesReturned)',
              style: TextStyle(
                fontSize: 9,
                fontFamily: 'monospace',
                color: Colors.white38,
              ),
            ),
          ),
      ],
    );
  }

  void _showDroneInputDialog(int max) {
    final controller = TextEditingController(text: _dronesToSend.toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey.shade900,
        title: const Text('Set Drones',
            style: TextStyle(fontSize: 14, fontFamily: 'monospace')),
        content: SizedBox(
          width: 120,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            style: const TextStyle(
                fontSize: 16, fontFamily: 'monospace', color: Colors.white),
            decoration: InputDecoration(
              hintText: '0-$max',
              hintStyle: const TextStyle(color: Colors.white38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final v = int.tryParse(controller.text);
              if (v != null) {
                setState(() => _dronesToSend = v.clamp(0, max));
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );
  }

  Widget _actionButtons(ColorScheme cs) {
    if (_combatOver) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _closeCombat,
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('CLOSE',
              style: TextStyle(fontFamily: 'monospace')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    // Port defeated — show capture/destroy/spare buttons
    final portDefeated = _port.currentShields <= _port.captureThreshold;
    if (portDefeated) {
      return Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _animating ? null : _doCapture,
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('CAPTURE',
                  style: TextStyle(fontFamily: 'monospace')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade800,
                disabledBackgroundColor: Colors.green.shade900,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton.icon(
              onPressed: _animating ? null : _doDestroy,
              icon: const Icon(Icons.gps_fixed_rounded, size: 18),
              label: const Text('DESTROY',
                  style: TextStyle(fontFamily: 'monospace')),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade800,
                disabledBackgroundColor: Colors.red.shade900,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: _animating ? null : _flee,
            icon: const Icon(Icons.exit_to_app_rounded, size: 18),
            label: const Text('SPARE',
                style: TextStyle(fontFamily: 'monospace')),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.amber.shade300,
              side: BorderSide(
                  color: Colors.amber.shade300.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      );
    }

    // Before first engagement — no cancel button, use back arrow
    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _animating ? null : _fire,
            icon: Icon(Icons.rocket_launch_rounded,
                size: 18,
                color: _animating ? Colors.white38 : Colors.white),
            label: Text(
              _animating ? 'FIRING...' : 'FIRE',
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade800,
              disabledBackgroundColor: Colors.red.shade900,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _animating ? null : _flee,
          icon: const Icon(Icons.exit_to_app_rounded, size: 18),
          label: const Text('FLEE',
              style: TextStyle(fontFamily: 'monospace')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.amber.shade300,
            side: BorderSide(
                color: Colors.amber.shade300.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      ],
    );
  }
}

class _RepeatButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onStep;

  const _RepeatButton({required this.icon, required this.onStep});

  @override
  State<_RepeatButton> createState() => _RepeatButtonState();
}

class _RepeatButtonState extends State<_RepeatButton> {
  bool _holding = false;

  void _startHold() {
    _holding = true;
    _repeat();
  }

  void _repeat() async {
    if (!_holding) return;
    widget.onStep();
    await Future.delayed(const Duration(milliseconds: 120));
    if (mounted && _holding) _repeat();
  }

  void _stopHold() => _holding = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onStep,
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _stopHold(),
      onLongPressCancel: _stopHold,
      child: Material(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(widget.icon, size: 14, color: Colors.white70),
        ),
      ),
    );
  }
}

class _PortCombatPainter extends CustomPainter {
  final double playerHull;
  final double playerShields;
  final double portShields;
  final double portFirepower;
  final Animation<double> atkProgress;
  final Animation<double> defProgress;
  final Animation<double> droneProgress;
  final int droneCount;
  final List<double> dronePhases;
  final List<double> droneOffsets;

  _PortCombatPainter({
    required this.playerHull,
    required this.playerShields,
    required this.portShields,
    required this.portFirepower,
    required this.atkProgress,
    required this.defProgress,
    required this.droneProgress,
    this.droneCount = 0,
    this.dronePhases = const [],
    this.droneOffsets = const [],
  }) : super(repaint: Listenable.merge([
          atkProgress,
          defProgress,
          droneProgress,
        ]));

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final shipSize = math.min(size.width, size.height) * 0.15;

    final playerCenter = Offset(cx - size.width * 0.25, cy);
    _drawPlayerShip(canvas, playerCenter, shipSize);

    final portCenter = Offset(cx + size.width * 0.25, cy);
    _drawPortDefenses(canvas, portCenter, shipSize);

    // Drone swarm
    if (droneProgress.isAnimating) {
      final t = droneProgress.value;
      final count = droneCount.clamp(3, 20);
      final spread = size.height * 0.25;
      final startX = playerCenter.dx + shipSize * 0.6;
      final endX = portCenter.dx - shipSize * 0.6;

      for (int i = 0; i < count; i++) {
        final phase = i < dronePhases.length
            ? dronePhases[i]
            : i * 2.399;
        final offset = i < droneOffsets.length
            ? droneOffsets[i]
            : (i % 2 == 0 ? 1.0 : -1.0);

        final converge = 1.0 - math.pow(1.0 - t, 1.5);
        final vertBase = offset * spread * (1.0 - converge * 0.8);
        final buzz = math.sin(t * math.pi * 10 + phase) * 4 +
            math.sin(t * math.pi * 17 + phase * 1.7) * 2;
        final driftX =
            math.sin(t * math.pi * 4 + phase * 0.7) * size.width * 0.03;

        final x = startX + (endX - startX) * t + driftX;
        final y = cy + vertBase + buzz;
        final sizeMod = 1.0 - t * 0.3;
        _drawDrone(canvas, Offset(x, y), 3 * sizeMod);
      }
    }

    // Attack projectile
    if (atkProgress.isAnimating) {
      final t = atkProgress.value;
      final projPos = Offset.lerp(
        playerCenter + Offset(shipSize * 0.6, 0),
        portCenter - Offset(shipSize * 0.6, 0),
        t,
      )!;
      _drawProjectile(canvas, projPos, Colors.orange.shade300);
    }

    // Port defense projectile
    if (defProgress.isAnimating) {
      final t = defProgress.value;
      final projPos = Offset.lerp(
        portCenter - Offset(shipSize * 0.6, 0),
        playerCenter + Offset(shipSize * 0.6, 0),
        t,
      )!;
      _drawProjectile(canvas, projPos, Colors.red.shade300);
    }
  }

  void _drawPlayerShip(Canvas canvas, Offset center, double size) {
    final paint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final body = Path()
      ..moveTo(center.dx + size * 0.6, center.dy)
      ..lineTo(center.dx - size * 0.4, center.dy - size * 0.5)
      ..lineTo(center.dx - size * 0.4, center.dy + size * 0.5)
      ..close();
    canvas.drawPath(body, paint);

    final enginePaint = Paint()
      ..color = Colors.orange.shade300.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center - Offset(size * 0.3, 0),
      size * 0.12,
      enginePaint,
    );

    if (playerShields > 0) {
      final shieldPaint = Paint()
        ..color = Colors.cyan.shade300.withValues(alpha: playerShields * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, size * 0.9, shieldPaint);
    }

    if (playerHull < 0.3) {
      final dangerPaint = Paint()
        ..color = Colors.red.withValues(alpha: (1.0 - playerHull) * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center, size * 0.7, dangerPaint);
    }
  }

  void _drawPortDefenses(Canvas canvas, Offset center, double size) {
    // Port base structure — square
    final basePaint = Paint()
      ..color = Colors.red.shade800.withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final base = Path()
      ..moveTo(center.dx - size * 0.45, center.dy - size * 0.45)
      ..lineTo(center.dx + size * 0.45, center.dy - size * 0.45)
      ..lineTo(center.dx + size * 0.45, center.dy + size * 0.45)
      ..lineTo(center.dx - size * 0.45, center.dy + size * 0.45)
      ..close();
    canvas.drawPath(base, basePaint);

    // Shield bubble
    if (portShields > 0) {
      final shieldPaint = Paint()
        ..color = Colors.red.shade300.withValues(alpha: portShields * 0.25)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, size * 0.9, shieldPaint);
    }

    // Defense turrets based on firepower
    final turretCount = (portFirepower * 4).round().clamp(1, 4);
    for (int i = 0; i < turretCount; i++) {
      final angle = (math.pi * 2 / turretCount) * i;
      final turretPos = center +
          Offset(
            math.cos(angle) * size * 0.5,
            math.sin(angle) * size * 0.5,
          );
      final turretPaint = Paint()
        ..color = Colors.red.shade400
        ..style = PaintingStyle.fill;
      canvas.drawCircle(turretPos, size * 0.1, turretPaint);
    }
  }

  void _drawDrone(Canvas canvas, Offset pos, double size) {
    final paint = Paint()
      ..color = Colors.amber.shade400
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(pos.dx + size, pos.dy)
      ..lineTo(pos.dx + size * 0.5, pos.dy - size * 0.866)
      ..lineTo(pos.dx - size * 0.5, pos.dy - size * 0.866)
      ..lineTo(pos.dx - size, pos.dy)
      ..lineTo(pos.dx - size * 0.5, pos.dy + size * 0.866)
      ..lineTo(pos.dx + size * 0.5, pos.dy + size * 0.866)
      ..close();
    canvas.drawPath(path, paint);
    final glow = Paint()
      ..color = Colors.orange.shade300.withValues(alpha: 0.5)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    canvas.drawCircle(pos, size * 0.8, glow);
  }

  void _drawProjectile(Canvas canvas, Offset pos, Color color) {
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 4, paint);
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(pos, 8, glowPaint);
  }

  @override
  bool shouldRepaint(_PortCombatPainter oldDelegate) => true;
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> _stars;

  _StarfieldPainter() : _stars = _generateStars();

  static List<_Star> _generateStars() {
    final rng = math.Random(42);
    return List.generate(60, (_) => _Star(
      x: rng.nextDouble(),
      y: rng.nextDouble(),
      r: 0.3 + rng.nextDouble() * 1.2,
      a: 0.2 + rng.nextDouble() * 0.5,
    ));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final star in _stars) {
      canvas.drawCircle(
        Offset(star.x * size.width, star.y * size.height),
        star.r,
        Paint()..color = Colors.white.withValues(alpha: star.a),
      );
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) => false;
}

class _Star {
  final double x, y, r, a;
  const _Star(
      {required this.x, required this.y, required this.r, required this.a});
}

/// Reusable weapon type enum from ship_equipment_types to keep the port combat
/// screen self-contained for firepower calculation.
enum WeaponType {
  autoLaser,
  pulseCannon,
  phaserArray,
  torpedoTube,
  missileRack;

  int get damage {
    switch (this) {
      case WeaponType.autoLaser:
        return 8;
      case WeaponType.pulseCannon:
        return 15;
      case WeaponType.phaserArray:
        return 25;
      case WeaponType.torpedoTube:
        return 40;
      case WeaponType.missileRack:
        return 30;
    }
  }
}
