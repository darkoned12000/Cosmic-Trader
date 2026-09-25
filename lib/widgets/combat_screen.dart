import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/services/audio_service.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/services/npc_ai/npc_death_cries.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';
import 'package:cosmic_trader/services/salvage_service.dart';

class CombatScreen extends StatefulWidget {
  final Player player;
  final NpcShip npc;
  final Function(Player updatedPlayer, NpcShip updatedNpc) onCombatEnd;

  /// Warp routes from the sector where combat started — used to
  /// send the player (and NPC on flee) to a random adjacent sector.
  final List<int> sectorWarps;

  const CombatScreen({
    super.key,
    required this.player,
    required this.npc,
    required this.onCombatEnd,
    this.sectorWarps = const [],
  });

  @override
  State<CombatScreen> createState() => _CombatScreenState();
}

class _CombatScreenState extends State<CombatScreen>
    with TickerProviderStateMixin {
  late Player _player;
  late NpcShip _npc;
  late Set<String> _selectedWeapons;
  final List<String> _combatLog = [];
  late AnimationController _atkAnimController;
  late AnimationController _defAnimController;
  late AnimationController _droneAnimController;
  int _droneSwarmCount = 0;
  bool _animating = false;
  bool _combatOver = false;
  int _dronesToSend = 0;
  int _dronesLost = 0;
  int _dronesReturned = 0;

  static const _droneHp = 15;

  final List<double> _dronePhases = [];
  final List<double> _droneOffsets = [];
  bool _droneSeeded = false;

  void _seedDrones(int count) {
    if (_droneSeeded && _dronePhases.length >= count) return;
    _dronePhases.clear();
    _droneOffsets.clear();
    final rng =
        math.Random(_npc.id.hashCode ^ DateTime.now().microsecondsSinceEpoch);
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
    _npc = widget.npc;
    _selectedWeapons = _player.weaponSlots.keys.toSet();
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
    _combatLog.add('COMBAT ENGAGED — ${_npc.shipName}');
    _combatLog.add('Your hull: ${_player.hull}/${_player.maxHull}  '
        'Shields: ${_player.shields}/${_player.maxShields}');
    _combatLog.add('Enemy hull: ${_npc.hull}/${_npc.maxHull}  '
        'Shields: ${_npc.shields}/${_npc.maxShields}');
  }

  @override
  void dispose() {
    _atkAnimController.dispose();
    _defAnimController.dispose();
    _droneAnimController.dispose();
    super.dispose();
  }

  WeaponType? _playerWeaponType(String slot) {
    final typeName = _player.weaponTypes[slot];
    if (typeName == null) return null;
    return WeaponType.values.firstWhere(
      (w) => w.name == typeName,
      orElse: () => WeaponType.autoLaser,
    );
  }

  WeaponType _npcWeaponType(String slot) {
    final idx = _npc.shipDef.weaponSlots.indexOf(slot);
    if (idx < 0 || idx >= _npc.shipDef.preferredWeapons.length) {
      return WeaponType.autoLaser;
    }
    return _npc.shipDef.preferredWeapons[idx];
  }

  int _slotDamage(String slot, {bool npc = false}) {
    final wt = npc ? _npcWeaponType(slot) : _playerWeaponType(slot);
    if (wt == null) return 0;
    final level =
        npc ? (_npc.weaponSlots[slot] ?? 1) : (_player.weaponSlots[slot] ?? 1);
    return wt.damage * level;
  }

  int get _playerFirepower {
    int total = 0;
    for (final slot in _selectedWeapons) {
      total += _slotDamage(slot);
    }
    return total;
  }

  int get _npcFirepower {
    int total = 0;
    for (final slot in _npc.weaponSlots.keys) {
      total += _slotDamage(slot, npc: true);
    }
    return total;
  }

  int _calcDamage(int power) =>
      (power * (0.8 + math.Random().nextDouble() * 0.4))
          .round()
          .clamp(1, 99999);

  Future<void> _fire() async {
    if (_animating || _combatOver) return;

    setState(() => _animating = true);
    AudioService.instance.playSfx('assets/sfx/laser.ogg');

    final dronesSent = _dronesToSend;
    final droneAtkDmg = dronesSent * _droneHp;
    final weaponDmg = _calcDamage(_playerFirepower);
    final totalAtkDamage = weaponDmg + droneAtkDmg;

    // Apply player attack damage to NPC first
    var npcShields = _npc.shields;
    var npcHull = _npc.hull;
    int remainingAtk = totalAtkDamage;
    if (npcShields > 0) {
      if (remainingAtk <= npcShields) {
        npcShields -= remainingAtk;
        remainingAtk = 0;
      } else {
        remainingAtk -= npcShields;
        npcShields = 0;
      }
    }
    if (remainingAtk > 0) {
      npcHull = (npcHull - remainingAtk).clamp(0, _npc.maxHull);
    }

    final npcDestroyed = npcHull <= 0;

    // Only process enemy return fire if NPC survived
    int dronesDestroyed = 0;
    int dronesReturning = 0;
    int rawEnemyDmg = 0;
    var playerShields = _player.shields;
    var playerHull = _player.hull;
    int remainingDef = 0;

    if (npcDestroyed) {
      // NPC destroyed — no return fire, all drones return
      dronesReturning = dronesSent;
      _combatLog.add('${_npc.shipName} destroyed before it could return fire');
    } else {
      rawEnemyDmg = _calcDamage(_npcFirepower);

      // Drones intercept enemy fire
      if (dronesSent > 0) {
        dronesDestroyed = math.min(dronesSent, (rawEnemyDmg / _droneHp).ceil());
        dronesReturning = dronesSent - dronesDestroyed;
        final enemyDmgToPlayer =
            (rawEnemyDmg - dronesDestroyed * _droneHp).clamp(0, rawEnemyDmg);
        remainingDef = enemyDmgToPlayer;
      } else {
        remainingDef = rawEnemyDmg;
      }

      // Apply to player shields then hull
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

    // Consume & return drones
    if (dronesSent > 0) {
      _dronesLost += dronesDestroyed;
      _dronesReturned += dronesReturning;
    }
    final newDroneCount = (_player.drones - dronesSent) + dronesReturning;
    final playerDestroyed = playerHull <= 0;

    // Animate drone swarm
    if (dronesSent > 0) {
      _seedDrones(dronesSent.clamp(3, 20));
      setState(() => _droneSwarmCount = dronesSent.clamp(3, 20));
      await _droneAnimController.forward();
      await _droneAnimController.reverse();
    }

    // Animate attack projectiles
    await _atkAnimController.forward();
    await _atkAnimController.reverse();

    _combatLog.add('> You dealt $weaponDmg damage from weapons');
    if (droneAtkDmg > 0) {
      _combatLog.add('  Drones: $dronesSent sent (+$droneAtkDmg damage)');
    }
    if (npcDestroyed) {
      _combatLog.add('  *** ${_npc.shipName} DESTROYED ***');
    } else if (remainingAtk > 0) {
      _combatLog.add(
          '  Enemy hull: ${npcHull.clamp(0, _npc.maxHull)}/${_npc.maxHull}');
    }

    // Animate return fire only if NPC survived
    if (!npcDestroyed) {
      await _defAnimController.forward();
      await _defAnimController.reverse();

      _combatLog.add('> Enemy dealt $rawEnemyDmg damage');
      if (dronesDestroyed > 0) {
        _combatLog.add('  Drones intercepted: $dronesDestroyed destroyed, '
            '$dronesReturning returned');
      }
      if (remainingDef > 0) {
        _combatLog.add(
            '  Your hull: ${playerHull.clamp(0, _player.maxHull)}/${_player.maxHull}');
      }
    }

    setState(() {
      _npc = _npc.copyWith(
        hull: npcHull.clamp(0, _npc.maxHull),
        shields: npcShields.clamp(0, _npc.maxShields),
        isDestroyed: npcDestroyed,
      );
      _player = _player.copyWith(
        hull: playerHull.clamp(0, _player.maxHull),
        shields: playerShields.clamp(0, _player.maxShields),
        drones: newDroneCount,
      );
      _dronesToSend = 0;
      _droneSwarmCount = 0;
      _animating = false;
    });

    if (npcDestroyed) {
      ActionLogProvider.global.combat(
          'Destroyed ${_npc.pilotName} (${_npc.shipName}) in sector #${_npc.currentSectorId}');
      ActionLogProvider.global
          .combat(NpcDeathCries.formatDeathCry(_npc.pilotName, _npc.faction));
      _endCombat(victory: true);
      return;
    }

    if (playerDestroyed) {
      _combatLog.add('*** YOUR SHIP IS CRITICALLY DAMAGED ***');
      _endCombat(victory: false);
      return;
    }
  }

  void _flee() {
    _combatLog.add('>>> You fled from combat <<<');

    // Send player to a random adjacent sector; the NPC stays put.
    if (widget.sectorWarps.isNotEmpty) {
      final rng = math.Random();
      final dest = widget.sectorWarps[rng.nextInt(widget.sectorWarps.length)];
      _player = _player.copyWith(currentSectorId: dest);
      _combatLog.add('>>> Emergency warp to sector #$dest <<<');
    }

    _endCombat(victory: false, fled: true);
  }

  void _endCombat({required bool victory, bool fled = false}) {
    setState(() => _combatOver = true);

    int loot = 0;
    SalvageReward salvage = const SalvageReward(scrapMetal: 0, scrapTech: 0);
    var lootedUnits = 0;
    if (victory) {
      loot = (_npc.credits * 0.5).round();
      salvage = SalvageService.rollForNpc(_npc);
      EconomyMetrics.global.recordLoot(
        actorFaction: _player.faction.name,
        credits: loot,
        isPlayer: true,
      );
      // Victim cargo transfers up to free hold space — contraband first,
      // so killing smugglers pays in black-market goods. Overflow is lost.
      final lootedCargo = Map<String, int>.from(_player.cargo);
      var freeHolds = _player.maxCargo - _player.cargoUsed;
      final victimCargo = Map<String, int>.from(_npc.cargo);
      final ordered = victimCargo.keys.toList()
        ..sort((a, b) =>
            (b == 'contraband' ? 1 : 0) - (a == 'contraband' ? 1 : 0));
      for (final commodity in ordered) {
        if (freeHolds <= 0) break;
        final take = (victimCargo[commodity] ?? 0).clamp(0, freeHolds);
        if (take <= 0) continue;
        lootedCargo[commodity] = (lootedCargo[commodity] ?? 0) + take;
        lootedUnits += take;
        freeHolds -= take;
      }
      _player = SalvageService.applyToPlayer(
        _player.withFactionStandingChange(_npc.faction, -5).copyWith(
              credits: _player.credits + loot,
              cargo: lootedCargo,
              cargoUsed: _player.cargoUsed + lootedUnits,
              notoriety: math.min(100.0, _player.notoriety + 3).toDouble(),
            ),
        salvage,
      );
      _npc = _npc.copyWith(
        credits: 0,
        cargo: {},
        cargoUsed: 0,
        scrapMetal: 0,
        scrapTech: 0,
        isDestroyed: true,
      );
      _combatLog.add(
        'Loot recovered: $loot cr, '
        '${salvage.scrapMetal} scrap metal, '
        '${salvage.scrapTech} scrap tech'
        '${lootedUnits > 0 ? ', $lootedUnits cargo' : ''}',
      );
    } else if (fled) {
      _player = _player.copyWith(
        notoriety: math.min(100.0, _player.notoriety + 1).toDouble(),
      );
    }

    if (victory) {
      ActionLogProvider.global.combat(
          'Destroyed ${_npc.pilotName} (${_npc.shipName}) in sector #${_npc.currentSectorId} — '
          'looted $loot cr, ${salvage.scrapMetal} scrap metal, '
          '${salvage.scrapTech} scrap tech'
          '${lootedUnits > 0 ? ', $lootedUnits cargo' : ''}');
    } else if (fled) {
      ActionLogProvider.global.combat(
          'Fled from ${_npc.pilotName} (${_npc.shipName}) in sector #${_npc.currentSectorId}');
    } else {
      ActionLogProvider.global.combat(
          'Disabled by ${_npc.pilotName} (${_npc.shipName}) in sector #${_npc.currentSectorId}');
    }

    GameTickService.unlockNpc(_npc.id);
  }

  void _copyLog() {
    final text = _combatLog.join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Combat log copied to clipboard',
            style: TextStyle(fontFamily: 'monospace')),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _closeCombat() {
    widget.onCombatEnd(_player, _npc);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final npcColor = factionColor(_npc.faction);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('COMBAT',
            style: TextStyle(fontFamily: 'monospace', letterSpacing: 2)),
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
            child: _buildShipVisual(cs, npcColor),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                _statColumn('YOU', Colors.cyan, _player),
                const SizedBox(width: 16),
                _statColumn(
                    _npc.shipName.toUpperCase(), npcColor, _npc as dynamic,
                    isNpc: true),
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
                      ..._weaponChips(cs),
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

  Widget _buildShipVisual(ColorScheme cs, Color npcColor) {
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
              painter: _CombatShipPainter(
                playerHull: _player.hull / _player.maxHull,
                playerShields: _player.shields / _player.maxShields,
                npcHull: _npc.hull / _npc.maxHull,
                npcShields: _npc.shields / _npc.maxShields,
                npcColor: npcColor,
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

  Widget _statColumn(String label, Color color, dynamic ship,
      {bool isNpc = false}) {
    final hull = isNpc ? ship.hull : _player.hull;
    final maxHull = isNpc ? ship.maxHull : _player.maxHull;
    final shields = isNpc ? ship.shields : _player.shields;
    final maxShields = isNpc ? ship.maxShields : _player.maxShields;

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
          _bar('HULL', hull, maxHull, Colors.green.shade400),
          const SizedBox(height: 2),
          _bar('SHD', shields, maxShields, Colors.cyan.shade300),
        ],
      ),
    );
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

  String _weaponLabel(String slot) {
    final wt = _playerWeaponType(slot);
    if (wt == null) return slot.toUpperCase();
    final name = wt.name.replaceAllMapped(
      RegExp(r'[A-Z]'),
      (m) => ' ${m.group(0)}',
    );
    final level = _player.weaponSlots[slot] ?? 1;
    return '${name.trim()} Lv$level  ${wt.damage * level}dmg';
  }

  List<Widget> _weaponChips(ColorScheme cs) {
    return _player.weaponSlots.entries.map((slot) {
      final selected = _selectedWeapons.contains(slot.key);
      return FilterChip(
        label: Text(
          _weaponLabel(slot.key),
          style: TextStyle(
            fontSize: 10,
            fontFamily: 'monospace',
            color: selected ? Colors.white : Colors.white54,
          ),
        ),
        selected: selected,
        onSelected: _selectedWeapons.length > 1
            ? (v) => setState(() {
                  if (v) {
                    _selectedWeapons.add(slot.key);
                  } else {
                    _selectedWeapons.remove(slot.key);
                  }
                })
            : null,
        selectedColor: cs.primary.withValues(alpha: 0.3),
        checkmarkColor: cs.primary,
        backgroundColor: Colors.white.withValues(alpha: 0.05),
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: BorderSide(
          color: selected ? cs.primary : Colors.white.withValues(alpha: 0.15),
        ),
      );
    }).toList();
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
                color:
                    _dronesToSend > 0 ? Colors.orange.shade300 : Colors.white54,
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
          label: const Text('CLOSE', style: TextStyle(fontFamily: 'monospace')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: _animating ? null : _fire,
            icon: Icon(Icons.rocket_launch_rounded,
                size: 18, color: _animating ? Colors.white38 : Colors.white),
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
          label: const Text('FLEE', style: TextStyle(fontFamily: 'monospace')),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.amber.shade300,
            side:
                BorderSide(color: Colors.amber.shade300.withValues(alpha: 0.5)),
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

class _CombatShipPainter extends CustomPainter {
  final double playerHull;
  final double playerShields;
  final double npcHull;
  final double npcShields;
  final Color npcColor;
  final Animation<double> atkProgress;
  final Animation<double> defProgress;
  final Animation<double> droneProgress;
  final int droneCount;
  final List<double> dronePhases;
  final List<double> droneOffsets;

  _CombatShipPainter({
    required this.playerHull,
    required this.playerShields,
    required this.npcHull,
    required this.npcShields,
    required this.npcColor,
    required this.atkProgress,
    required this.defProgress,
    required this.droneProgress,
    this.droneCount = 0,
    this.dronePhases = const [],
    this.droneOffsets = const [],
  }) : super(
            repaint: Listenable.merge([
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
    _drawShip(canvas, playerCenter, shipSize, Colors.cyan, 1.0, playerShields,
        playerHull, false);

    final npcCenter = Offset(cx + size.width * 0.25, cy);
    _drawShip(
        canvas, npcCenter, shipSize, npcColor, -1.0, npcShields, npcHull, true);

    // Drone swarm — bee-like cloud
    if (droneProgress.isAnimating) {
      final t = droneProgress.value;
      final count = droneCount.clamp(3, 20);
      final spread = size.height * 0.25;
      final startX = playerCenter.dx + shipSize * 0.6;
      final endX = npcCenter.dx - shipSize * 0.6;

      for (int i = 0; i < count; i++) {
        final phase = i < dronePhases.length ? dronePhases[i] : i * 2.399;
        final offset = i < droneOffsets.length
            ? droneOffsets[i]
            : (i % 2 == 0 ? 1.0 : -1.0);

        // Cloud convergence: spread wide at start, tighten on target
        final converge = 1.0 - math.pow(1.0 - t, 1.5);
        final vertBase = offset * spread * (1.0 - converge * 0.8);

        // Bee-like buzzing: fast oscillation
        final buzz = math.sin(t * math.pi * 10 + phase) * 4 +
            math.sin(t * math.pi * 17 + phase * 1.7) * 2;

        // Individual drift within the cloud
        final driftX =
            math.sin(t * math.pi * 4 + phase * 0.7) * size.width * 0.03;

        final x = startX + (endX - startX) * t + driftX;
        final y = cy + vertBase + buzz;

        // Drones shrink as they close in
        final sizeMod = 1.0 - t * 0.3;
        _drawDrone(canvas, Offset(x, y), 3 * sizeMod);
      }
    }

    if (atkProgress.isAnimating) {
      final t = atkProgress.value;
      final projPos = Offset.lerp(
        playerCenter + Offset(shipSize * 0.6, 0),
        npcCenter - Offset(shipSize * 0.6, 0),
        t,
      )!;
      _drawProjectile(canvas, projPos, Colors.orange.shade300);
    }

    if (defProgress.isAnimating) {
      final t = defProgress.value;
      final projPos = Offset.lerp(
        npcCenter - Offset(shipSize * 0.6, 0),
        playerCenter + Offset(shipSize * 0.6, 0),
        t,
      )!;
      _drawProjectile(canvas, projPos, Colors.red.shade300);
    }
  }

  void _drawShip(Canvas canvas, Offset center, double size, Color color,
      double direction, double shieldsPct, double hullPct, bool isNpc) {
    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;

    final noseX = center.dx + direction * size * 0.6;
    final body = Path()
      ..moveTo(noseX, center.dy)
      ..lineTo(center.dx - direction * size * 0.4, center.dy - size * 0.5)
      ..lineTo(center.dx - direction * size * 0.4, center.dy + size * 0.5)
      ..close();
    canvas.drawPath(body, paint);

    final enginePaint = Paint()
      ..color = Colors.orange.shade300.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      center - Offset(direction * size * 0.3, 0),
      size * 0.12,
      enginePaint,
    );

    if (shieldsPct > 0) {
      final shieldPaint = Paint()
        ..color = Colors.cyan.shade300.withValues(alpha: shieldsPct * 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawCircle(center, size * 0.9, shieldPaint);
    }

    if (hullPct < 0.3) {
      final dangerPaint = Paint()
        ..color = Colors.red.withValues(alpha: (1.0 - hullPct) * 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
      canvas.drawCircle(center, size * 0.7, dangerPaint);
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
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(pos, 4, paint);
    final glowPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawCircle(pos, 8, glowPaint);
  }

  @override
  bool shouldRepaint(_CombatShipPainter oldDelegate) => true;
}

class _StarfieldPainter extends CustomPainter {
  final List<_Star> _stars;

  _StarfieldPainter() : _stars = _generateStars();

  static List<_Star> _generateStars() {
    final rng = math.Random(42);
    return List.generate(
        60,
        (_) => _Star(
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
