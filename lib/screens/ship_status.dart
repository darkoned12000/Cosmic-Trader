import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/tw_layout.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';

import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/shared/panel_card.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/tow_service.dart';

class ShipStatusView extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const ShipStatusView({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<ShipStatusView> createState() => _ShipStatusViewState();
}

class _ShipStatusViewState extends State<ShipStatusView> {
  List<Sector> _sectors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUniverse();
  }

  Future<void> _loadUniverse() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (mounted) {
        setState(() {
          _sectors = sectors;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  int? _getSectorIdForPort(String portName) {
    try {
      final sector = _sectors.firstWhere(
        (s) => s.port?.name == portName,
      );
      return sector.id;
    } catch (e) {
      return null;
    }
  }

  String _formatEquipmentName(String equipKey) {
    final formatted = equipKey.replaceAllMapped(
      RegExp(r'[A-Z][a-z]+'),
      (m) => ' ${m.group(0)}',
    );
    return formatted[0].toUpperCase() + formatted.substring(1);
  }

  HullType? _parseHullType(String equipKey) {
    try {
      return HullType.values.firstWhere((e) => e.name == equipKey);
    } catch (e) {
      return null;
    }
  }

  ShieldType? _parseShieldType(String equipKey) {
    try {
      return ShieldType.values.firstWhere((e) => e.name == equipKey);
    } catch (e) {
      return null;
    }
  }

  EngineType? _parseEngineType(String equipKey) {
    try {
      return EngineType.values.firstWhere((e) => e.name == equipKey);
    } catch (e) {
      return null;
    }
  }

  WeaponType? _parseWeaponType(String equipKey) {
    try {
      return WeaponType.values.firstWhere((e) => e.name == equipKey);
    } catch (e) {
      return null;
    }
  }

  String _formatClassName(ShipClassType cls) {
    return cls.name[0].toUpperCase() + cls.name.substring(1);
  }

  String _formatSlotName(String slot) {
    return slot[0].toUpperCase() + slot.substring(1);
  }

  Future<void> _editShipName() async {
    final controller = TextEditingController(text: widget.player.name);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Ship'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Ship Name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('SAVE'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty && mounted) {
      widget.onPlayerUpdate(widget.player.copyWith(name: result));
    }
  }

  Future<void> _changePassword() async {
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text('Change Password'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (error != null) ...[
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(ctx).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Current Password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New Password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm New Password',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () async {
                final current = currentController.text;
                final newPass = newController.text;
                final confirm = confirmController.text;

                if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
                  setModalState(() => error = 'All fields are required');
                  return;
                }
                if (newPass != confirm) {
                  setModalState(() => error = 'Passwords do not match');
                  return;
                }
                if (newPass.length < 6) {
                  setModalState(
                      () => error = 'Password must be at least 6 characters');
                  return;
                }
                if (!widget.player.verifyPassword(current)) {
                  setModalState(() => error = 'Current password is incorrect');
                  return;
                }

                try {
                  final updatedPlayer = widget.player.copyWith(
                    passwordHash: Player.hashPassword(newPass),
                  );
                  await PlayerStorage.instance.updatePlayer(updatedPlayer);
                  widget.onPlayerUpdate(updatedPlayer);
                } catch (e) {
                  setModalState(
                      () => error = e.toString().replaceAll('Exception: ', ''));
                  return;
                }
                // ignore: use_build_context_synchronously
                Navigator.pop(ctx);
              },
              child: const Text('SAVE'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isLarge = constraints.maxWidth > TWLayout.largeScreenMinWidth;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: isLarge
              ? TWLayout.constrainContentWidth(
                  _buildContent(context, theme, cs, true),
                )
              : _buildContent(context, theme, cs, false),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    ThemeData theme,
    ColorScheme cs,
    bool isLarge,
  ) {
    if (isLarge) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _shipHeaderCard(theme, cs),
          const SizedBox(height: 16),
          _buildTwoColumnGrid(theme, cs),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _shipHeaderCard(theme, cs),
        const SizedBox(height: 16),
        _playerInfoCard(theme, cs),
        const SizedBox(height: 16),
        _solarArrayCard(cs),
        const SizedBox(height: 16),
        _emergencyTowCard(cs),
        const SizedBox(height: 16),
        _shipResourcesCard(theme, cs),
        const SizedBox(height: 16),
        _hullShieldCard(theme, cs),
        const SizedBox(height: 16),
        _shipWeaponsCard(theme, cs),
        const SizedBox(height: 16),
        _shipCargoCard(theme, cs),
      ],
    );
  }

  Widget _buildTwoColumnGrid(ThemeData theme, ColorScheme cs) {
    final cards = <Widget>[
      _playerInfoCard(theme, cs),
      _solarArrayCard(cs),
      _emergencyTowCard(cs),
      _shipResourcesCard(theme, cs),
      _hullShieldCard(theme, cs),
      _shipWeaponsCard(theme, cs),
      _shipCargoCard(theme, cs),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: cards.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        mainAxisExtent: 440,
      ),
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget _shipHeaderCard(ThemeData theme, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.primaryContainer.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.rocket_launch_rounded,
                size: 40,
                color: cs.primary,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SHIP STATUS',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Overview of your vessel',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _playerInfoCard(ThemeData theme, ColorScheme cs) {
    return PanelCard(
      icon: Icons.person_rounded,
      title: 'Player Info',
      children: [
        _detailRow(cs, 'Username', widget.player.username),
        _shipNameRow(cs),
        _detailRow(cs, 'Ship Class', _formatClassName(widget.player.shipClass)),
        _detailRow(
            cs, 'Credits', '\$${widget.player.credits.toStringAsFixed(0)}'),
        _detailRow(
            cs, 'Energy', '${widget.player.energy}/${widget.player.maxEnergy}'),
        _detailRow(cs, 'Scrap Metal', '${widget.player.scrapMetal}'),
        _detailRow(cs, 'Scrap Tech', '${widget.player.scrapTech}'),
        const SizedBox(height: 8),
        Divider(color: cs.surfaceContainerHighest),
        const SizedBox(height: 8),
        ListTile(
          leading: Icon(Icons.lock_rounded,
              size: 20, color: cs.onSurface.withValues(alpha: 0.6)),
          title: const Text('Change Password'),
          trailing: Icon(Icons.chevron_right_rounded,
              size: 20, color: cs.onSurface.withValues(alpha: 0.4)),
          onTap: _changePassword,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }

  Widget _solarArrayCard(ColorScheme cs) {
    final level = EnergyService.solarArrayLevel(widget.player);
    final installed = level > 0;
    final deployed = widget.player.solarArrayDeployed;
    final regen = EnergyService.solarRechargePerTick(widget.player);

    return PanelCard(
      icon: Icons.wb_sunny_rounded,
      title: 'Solar Array',
      children: [
        Row(
          children: [
            Icon(
              deployed ? Icons.lock_rounded : Icons.power_rounded,
              size: 18,
              color: installed
                  ? (deployed ? Colors.amber.shade700 : cs.primary)
                  : cs.onSurface.withValues(alpha: 0.4),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                installed
                    ? (deployed ? 'DEPLOYED' : 'RETRACTED')
                    : 'NOT INSTALLED',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: installed
                      ? (deployed ? Colors.amber.shade700 : cs.primary)
                      : cs.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!installed)
          Text(
            'Purchase a Solar Array module from a Hardware Emporium to enable '
            'slow off-grid recharging.',
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          )
        else ...[
          _detailRow(cs, 'Module Level', 'Lv.$level'),
          _detailRow(cs, 'Recharge Rate', '$regen energy / tick'),
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            value: deployed,
            onChanged: (value) {
              widget.onPlayerUpdate(
                EnergyService.setSolarArrayDeployed(widget.player, value),
              );
            },
            title: const Text('Deploy Solar Array'),
            subtitle: Text(
              deployed
                  ? 'Ship cannot warp while the array is deployed.'
                  : 'Retracted — the ship can move freely.',
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ],
    );
  }

  Widget _emergencyTowCard(ColorScheme cs) {
    final stranded = TowService.needsTow(widget.player);
    final plan = _sectors.isEmpty
        ? null
        : TowService.findTowPlan(_sectors, widget.player.currentSectorId);

    return PanelCard(
      icon: Icons.local_shipping_rounded,
      title: 'Emergency Tow',
      children: [
        Text(
          stranded
              ? 'Insufficient energy to warp. A tug can tow the ship to the '
                  'nearest refuel-capable port.'
              : 'Ship has enough energy to warp normally.',
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        if (plan != null) ...[
          const SizedBox(height: 8),
          _detailRow(cs, 'Destination', plan.targetSectorName),
          _detailRow(cs, 'Port', plan.targetPortName),
          _detailRow(
              cs, 'Distance', '${plan.hops} hop${plan.hops == 1 ? '' : 's'}'),
          _detailRow(
            cs,
            'Can Refuel',
            plan.isRefuelStation ? 'Yes' : 'Emergency stop only',
          ),
          _detailRow(
            cs,
            'Tow Fee',
            '${TowService.towCost(widget.player, plan)} cr',
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'No reachable port found for an emergency tow.',
            style: TextStyle(fontSize: 12, color: cs.error),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: stranded && plan != null ? () => _callTow(plan) : null,
            icon: const Icon(Icons.local_shipping_rounded, size: 18),
            label: const Text('CALL EMERGENCY TOW'),
          ),
        ),
      ],
    );
  }

  void _callTow(TowPlan plan) {
    final result = TowService.tow(widget.player, plan);
    widget.onPlayerUpdate(result.player);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Towed ${result.hops} hop${result.hops == 1 ? '' : 's'} to '
          '${result.targetName} — ${result.creditsSpent} cr, emergency energy '
          'restored',
          style: const TextStyle(fontFamily: 'monospace'),
        ),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _shipNameRow(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Ship Name',
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.player.name,
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: Icon(Icons.edit_rounded, size: 14, color: cs.primary),
                onPressed: _editShipName,
                tooltip: 'Rename ship',
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hullShieldCard(ThemeData theme, ColorScheme cs) {
    final hullPercent =
        (widget.player.hull / widget.player.maxHull * 100).round();
    final shieldPercent =
        (widget.player.shields / widget.player.maxShields * 100).round();

    Color hullColor;
    IconData hullIcon;
    if (hullPercent > 75) {
      hullColor = cs.primary;
      hullIcon = Icons.verified_user_rounded;
    } else if (hullPercent > 50) {
      hullColor = Colors.blue.shade300;
      hullIcon = Icons.shield_rounded;
    } else if (hullPercent > 25) {
      hullColor = Colors.amber.shade300;
      hullIcon = Icons.warning_amber_rounded;
    } else {
      hullColor = cs.error;
      hullIcon = Icons.error_rounded;
    }

    Color shieldColor;
    IconData shieldIcon;
    if (shieldPercent > 75) {
      shieldColor = cs.primary;
      shieldIcon = Icons.brightness_1_rounded;
    } else if (shieldPercent > 50) {
      shieldColor = Colors.blue.shade300;
      shieldIcon = Icons.brightness_2_rounded;
    } else if (shieldPercent > 25) {
      shieldColor = Colors.amber.shade300;
      shieldIcon = Icons.brightness_3_rounded;
    } else {
      shieldColor = cs.error;
      shieldIcon = Icons.brightness_4_rounded;
    }

    return PanelCard(
      icon: Icons.domain_rounded,
      title: 'Hull & Shields',
      children: [
        // Hull section
        _equipmentNameRow(cs, Icons.shield_outlined,
            _formatEquipmentName(widget.player.hullEquipment)),
        _equipmentStatsRow(
            cs,
            _getHullStats(
                widget.player.hullEquipment, widget.player.hullEquipmentLevel)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$hullPercent%',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: hullColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(hullIcon, color: hullColor),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: widget.player.hull / widget.player.maxHull,
          backgroundColor: cs.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(hullColor),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 2),
        Text(
          '${widget.player.hull.toStringAsFixed(0)} / ${widget.player.maxHull.toStringAsFixed(0)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 12),
        // Shield section
        _equipmentNameRow(cs, Icons.bolt_outlined,
            _formatEquipmentName(widget.player.shieldEquipment)),
        _equipmentStatsRow(
            cs,
            _getShieldStats(widget.player.shieldEquipment,
                widget.player.shieldEquipmentLevel)),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '$shieldPercent%',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: shieldColor,
                fontWeight: FontWeight.bold,
              ),
            ),
            Icon(shieldIcon, color: shieldColor),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: widget.player.shields / widget.player.maxShields,
          backgroundColor: cs.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(shieldColor),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 2),
        Text(
          '${widget.player.shields.toStringAsFixed(0)} / ${widget.player.maxShields.toStringAsFixed(0)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  Widget _equipmentNameRow(ColorScheme cs, IconData icon, String name) {
    return Row(
      children: [
        Icon(icon, size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
        const SizedBox(width: 4),
        Text(
          name,
          style: TextStyle(
            fontSize: 12,
            color: cs.onSurface.withValues(alpha: 0.7),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _equipmentStatsRow(ColorScheme cs, List<String> stats) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: stats.map((s) {
          final parts = s.split(':');
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              '${parts[0]}: ${parts[1]}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _shipWeaponsCard(ThemeData theme, ColorScheme cs) {
    final shipDef =
        ShipDefinition.getShipByName(widget.player.shipDefinitionName);
    final slots =
        shipDef?.weaponSlots ?? widget.player.weaponSlots.keys.toList();

    return PanelCard(
      icon: Icons.auto_awesome_rounded,
      title: 'Engine & Weapons',
      children: [
        _equipmentNameRow(
          cs,
          Icons.speed_rounded,
          _formatEquipmentName(widget.player.engineEquipment),
        ),
        _equipmentStatsRow(
          cs,
          _getEngineStats(
            widget.player.engineEquipment,
            widget.player.engineEquipmentLevel,
          ),
        ),
        const SizedBox(height: 8),
        Divider(color: cs.surfaceContainerHighest),
        const SizedBox(height: 8),
        Text(
          'Weapons',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        ...slots.map((slot) {
          final weaponType = widget.player.weaponTypes[slot];
          final level = widget.player.weaponSlots[slot] ?? 0;
          final weaponName =
              weaponType != null ? _formatEquipmentName(weaponType) : '—';
          final List<String> weaponStats =
              weaponType != null ? _getWeaponStats(weaponType, level) : [];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatSlotName(slot),
                            style: TextStyle(
                              color: cs.onSurface.withValues(alpha: 0.6),
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            weaponName,
                            style: TextStyle(
                              fontSize: 11,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          if (weaponStats.isNotEmpty)
                            _equipmentStatsRow(cs, weaponStats),
                        ],
                      ),
                    ),
                    Text(
                      'Lv.$level',
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _shipCargoCard(ThemeData theme, ColorScheme cs) {
    return PanelCard(
      icon: Icons.inventory_2_rounded,
      title: 'Cargo Hold & Components',
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Capacity',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            Text(
              '${widget.player.cargoSize}',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _shipResourcesCard(ThemeData theme, ColorScheme cs) {
    return PanelCard(
      icon: Icons.monetization_on_rounded,
      title: 'Reputation & Research',
      children: [
        _resourceRow(cs, Icons.science_rounded, 'Research',
            '${widget.player.researchPoints.toStringAsFixed(0)} RP'),
        const SizedBox(height: 12),
        _notorietyRow(cs),
        const SizedBox(height: 12),
        _factionStandingSection(theme, cs),
        _ownedPortsSection(theme, cs),
      ],
    );
  }

  Widget _resourceRow(
    ColorScheme cs,
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: cs.onSurface.withValues(alpha: 0.6),
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notorietyRow(ColorScheme cs) {
    final p = widget.player;
    final notorietyPct = (p.notoriety / 100.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.local_fire_department_rounded,
                size: 16, color: p.notorietyColor),
            const SizedBox(width: 8),
            Text(
              'Notoriety',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const Spacer(),
            Text(
              '${p.notoriety.toStringAsFixed(0)}/100',
              style: TextStyle(
                fontWeight: FontWeight.w500,
                fontSize: 13,
                color: p.notorietyColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: notorietyPct,
          backgroundColor: cs.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(p.notorietyColor),
          minHeight: 6,
          borderRadius: BorderRadius.circular(3),
        ),
        const SizedBox(height: 2),
        Text(
          '${p.notorietyLabel} notoriety',
          style: TextStyle(
            fontSize: 11,
            color: p.notorietyColor.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _factionStandingSection(ThemeData theme, ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.groups_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Faction Standing',
              style: TextStyle(
                color: cs.onSurface.withValues(alpha: 0.6),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...FactionClass.values.map((faction) {
          final standing = widget.player.factionStandingWith(faction);
          final color = _standingColor(standing);
          final progress = ((standing + 100) / 200).clamp(0.0, 1.0);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      faction.displayName,
                      style: const TextStyle(fontSize: 11),
                    ),
                    const Spacer(),
                    Text(
                      '$standing',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: cs.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(color),
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Color _standingColor(int standing) {
    if (standing >= 25) return Colors.green;
    if (standing <= -30) return Colors.red;
    return Colors.orange;
  }

  Widget _ownedPortsSection(ThemeData theme, ColorScheme cs) {
    final ownedPorts = widget.player.ownedPorts;
    if (ownedPorts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.home_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              'Owned Ports (${ownedPorts.length})',
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...ownedPorts.map((portName) {
          final sectorId = _getSectorIdForPort(portName);
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: InkWell(
              onTap: sectorId != null ? () => _navigateToPort(sectorId) : null,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.store_rounded,
                        size: 14,
                        color: cs.primary
                            .withValues(alpha: sectorId != null ? 1.0 : 0.4)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        portName,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.8),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (sectorId != null)
                      Text(
                        'Sector $sectorId',
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    if (sectorId != null)
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  void _navigateToPort(int sectorId) {
    widget.onPlayerUpdate(widget.player.copyWith(currentSectorId: sectorId));
  }

  List<String> _getHullStats(String equipKey, int level) {
    final hullType = _parseHullType(equipKey);
    if (hullType == null) return [];
    return [
      'Hull: ${hullType.hullBonusAtLevel(level)}',
      'Def: ${hullType.defenseAtLevel(level)}',
    ];
  }

  List<String> _getShieldStats(String equipKey, int level) {
    final shieldType = _parseShieldType(equipKey);
    if (shieldType == null) return [];
    return [
      'Shield: ${shieldType.shieldBonusAtLevel(level)}',
      'Regen: ${shieldType.regenAtLevel(level)}',
    ];
  }

  List<String> _getEngineStats(String equipKey, int level) {
    final engineType = _parseEngineType(equipKey);
    if (engineType == null) return [];
    return [
      'Speed: ${engineType.speedAtLevel(level)}',
      'Warp: ${engineType.warpAtLevel(level)}',
      'Eff: ${engineType.efficiencyAtLevel(level)}',
    ];
  }

  List<String> _getWeaponStats(String equipKey, int level) {
    final weaponType = _parseWeaponType(equipKey);
    if (weaponType == null) return [];
    return [
      'Dmg: ${weaponType.damageAtLevel(level)}',
      'Rate: ${weaponType.fireRateAtLevel(level)}',
    ];
  }
}
