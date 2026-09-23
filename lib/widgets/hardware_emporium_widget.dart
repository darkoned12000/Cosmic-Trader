import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/hardware_data.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';

import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';

class HardwareEmporiumWidget extends StatefulWidget {
  final Player player;
  final Port port;
  final Function(Player) onPlayerUpdate;

  const HardwareEmporiumWidget({
    super.key,
    required this.player,
    required this.port,
    required this.onPlayerUpdate,
  });

  @override
  State<HardwareEmporiumWidget> createState() => _HardwareEmporiumWidgetState();
}

class _HardwareEmporiumWidgetState extends State<HardwareEmporiumWidget>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final List<String> _tabLabels = [
    'SERVICES',
    'WEAPONS',
    'HULL',
    'SHIELDS',
    'ENGINES',
    'MODULES',
    'SCRAP',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabLabels.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _updatePlayer(Player p) => widget.onPlayerUpdate(p);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final faction = widget.player.faction;
    final factionData = Faction.forClass(faction);
    final p = widget.player;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(cs, factionData, p),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ServicesTab(player: p, onPlayerUpdate: _updatePlayer),
                _WeaponsTab(player: p, onPlayerUpdate: _updatePlayer),
                _EquipmentTab(
                    player: p,
                    onPlayerUpdate: _updatePlayer,
                    category: HardwareCategory.hull),
                _EquipmentTab(
                    player: p,
                    onPlayerUpdate: _updatePlayer,
                    category: HardwareCategory.shield),
                _EquipmentTab(
                    player: p,
                    onPlayerUpdate: _updatePlayer,
                    category: HardwareCategory.engine),
                _ModulesTab(player: p, onPlayerUpdate: _updatePlayer),
                _ScrapTab(player: p, onPlayerUpdate: _updatePlayer),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, Faction factionData, Player p) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
        border: Border(
          bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.build_rounded,
                  size: 20, color: Colors.deepPurpleAccent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.port.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.deepPurpleAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.deepPurpleAccent.withValues(alpha: 0.3)),
                ),
                child: Text(
                  'HARDWARE',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurpleAccent,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.person_rounded,
                  size: 12, color: cs.onSurface.withValues(alpha: 0.5)),
              const SizedBox(width: 4),
              Text(
                factionData.name,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.tertiary,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Icon(Icons.monetization_on_outlined,
                  size: 12, color: Colors.amber.shade300),
              const SizedBox(width: 4),
              Text(
                _formatCredits(p.credits),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.amber.shade300,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.calculate_outlined,
                  size: 12, color: Colors.teal.shade300),
              const SizedBox(width: 4),
              Text(
                '${p.scrapMetal}M ${p.scrapTech}T',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: Colors.teal.shade300,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            indicatorColor: Colors.deepPurpleAccent,
            indicatorWeight: 2,
            labelColor: Colors.deepPurpleAccent,
            unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
            labelStyle: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
            tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
          ),
        ],
      ),
    );
  }

  String _formatCredits(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toString();
  }
}

// ── Services Tab ───────────────────────────────────────
class _ServicesTab extends StatelessWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const _ServicesTab({required this.player, required this.onPlayerUpdate});

  @override
  Widget build(BuildContext context) {
    final shieldCost =
        (player.maxShields - player.shields) * shieldRechargeCostPerPoint;
    final hullCost = (player.maxHull - player.hull) * hullRepairCostPerPoint;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ServiceCard(
          icon: Icons.bolt_rounded,
          iconColor: Colors.cyan,
          title: 'Shield Recharge',
          description:
              'Restore shields to full capacity (${player.shields}/${player.maxShields})',
          cost: shieldCost > 0 ? '$shieldCost cr' : 'Fully charged',
          canAfford: player.credits >= shieldCost,
          disabled: shieldCost <= 0,
          onTap: () {
            final updated = player.copyWith(
              shields: player.maxShields,
              credits: player.credits - shieldCost,
            );
            onPlayerUpdate(updated);
            ScaffoldMessenger.of(context).showSnackBar(
              _snack('Shields fully recharged ($shieldCost cr)'),
            );
          },
          actionLabel: 'RECHARGE',
        ),
        const SizedBox(height: 8),
        _ServiceCard(
          icon: Icons.shield_rounded,
          iconColor: Colors.red,
          title: 'Hull Repair',
          description: 'Repair hull damage (${player.hull}/${player.maxHull})',
          cost: hullCost > 0 ? '$hullCost cr' : 'No damage',
          canAfford: player.credits >= hullCost,
          disabled: hullCost <= 0,
          onTap: () {
            final updated = player.copyWith(
              hull: player.maxHull,
              credits: player.credits - hullCost,
            );
            onPlayerUpdate(updated);
            ScaffoldMessenger.of(context).showSnackBar(
              _snack('Hull fully repaired ($hullCost cr)'),
            );
          },
          actionLabel: 'REPAIR',
        ),
        const SizedBox(height: 8),
        _ServiceCard(
          icon: Icons.rocket_rounded,
          iconColor: Colors.orange,
          title: 'Purchase Drone',
          description:
              'Add a combat/utility drone (${player.drones}/${player.maxDrones})',
          cost:
              '$droneCostCredits cr${droneCostScrapMetal > 0 ? ' + ${droneCostScrapMetal}M' : ''}${droneCostScrapTech > 0 ? ' + ${droneCostScrapTech}T' : ''}',
          canAfford: player.credits >= droneCostCredits &&
              player.scrapMetal >= droneCostScrapMetal &&
              player.scrapTech >= droneCostScrapTech,
          disabled: false,
          onTap: () {
            final updated = player.copyWith(
              drones: player.drones + 1,
              maxDrones: player.maxDrones + 1,
              credits: player.credits - droneCostCredits,
              scrapMetal: player.scrapMetal - droneCostScrapMetal,
              scrapTech: player.scrapTech - droneCostScrapTech,
            );
            onPlayerUpdate(updated);
            ScaffoldMessenger.of(context).showSnackBar(
              _snack('Drone purchased'),
            );
          },
          actionLabel: 'BUY DRONE',
        ),
      ],
    );
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      );
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String cost;
  final bool canAfford;
  final bool disabled;
  final VoidCallback? onTap;
  final String actionLabel;

  const _ServiceCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.cost,
    required this.canAfford,
    required this.disabled,
    this.onTap,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: cs.onSurface)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(description,
              style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.monetization_on_rounded,
                  size: 14, color: Colors.amber.shade300),
              const SizedBox(width: 4),
              Text(cost,
                  style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: canAfford
                          ? Colors.amber.shade300
                          : cs.error.withValues(alpha: 0.6))),
              const Spacer(),
              SizedBox(
                height: 28,
                child: ElevatedButton.icon(
                  onPressed: disabled ? null : onTap,
                  icon: Icon(Icons.shopping_cart_rounded, size: 12),
                  label: Text(actionLabel,
                      style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                          fontFamily: 'monospace')),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    backgroundColor: canAfford && !disabled
                        ? Colors.deepPurpleAccent
                        : cs.surfaceContainerHighest,
                    foregroundColor: canAfford && !disabled
                        ? Colors.white
                        : cs.onSurface.withValues(alpha: 0.4),
                    disabledBackgroundColor: cs.surfaceContainerHighest,
                    disabledForegroundColor:
                        cs.onSurface.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Weapons Tab ────────────────────────────────────────
class _WeaponsTab extends StatelessWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const _WeaponsTab({required this.player, required this.onPlayerUpdate});

  @override
  Widget build(BuildContext context) {
    final items = itemsForFaction(HardwareCategory.weapon, player.faction);
    final shipDef = ShipDefinition.getShipByName(player.shipDefinitionName);
    final slots = shipDef?.weaponSlots ?? player.weaponSlots.keys.toList();
    final emptySlots =
        slots.where((s) => !player.weaponSlots.containsKey(s)).toList();
    final maxTier = shipDef?.shipClass.maxWeaponTier ?? 1;

    final cs = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined,
                size: 32, color: cs.onSurface.withValues(alpha: 0.2)),
            const SizedBox(height: 8),
            Text('No weapons available',
                style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withValues(alpha: 0.4))),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: items.map((item) {
        final restriction = _tierRestriction(item, maxTier);
        return _ItemCard(
          item: item,
          player: player,
          onBuy: restriction == null
              ? () => _buyWeapon(context, item, slots, emptySlots)
              : null,
          restrictionReason: restriction,
        );
      }).toList(),
    );
  }

  String? _tierRestriction(HardwareItem item, int maxTier) {
    final equipKey = item.equipKey;
    if (equipKey == null) return null;
    try {
      final wt = WeaponType.values.firstWhere((w) => w.name == equipKey);
      if (wt.classTier > maxTier) {
        switch (wt.classTier) {
          case 2:
            return 'Requires Battleship+';
          case 3:
            return 'Requires Capital Ship';
        }
      }
    } catch (_) {}
    return null;
  }

  void _buyWeapon(BuildContext context, HardwareItem item, List<String> slots,
      List<String> emptySlots) {
    if (player.credits < item.priceCredits) {
      _showError(context, 'Insufficient credits');
      return;
    }
    if (player.scrapMetal < item.priceScrapMetal) {
      _showError(context, 'Insufficient scrap metal');
      return;
    }
    if (player.scrapTech < item.priceScrapTech) {
      _showError(context, 'Insufficient scrap tech');
      return;
    }

    if (emptySlots.isNotEmpty) {
      _installWeapon(context, item, emptySlots.first);
    } else {
      _showSlotPicker(context, item, slots);
    }
  }

  void _installWeapon(BuildContext context, HardwareItem item, String slot) {
    final newTypes = Map<String, String>.from(player.weaponTypes);
    final newLevels = Map<String, int>.from(player.weaponSlots);

    int scrapMetalReturn = 0;
    int scrapTechReturn = 0;
    final oldKey = newTypes[slot];
    final oldLv = newLevels[slot];
    if (oldKey != null && oldLv != null) {
      final oldItem = itemFor(oldKey, HardwareCategory.weapon, oldLv);
      if (oldItem != null) {
        scrapMetalReturn = oldItem.scrapMetalReturn;
        scrapTechReturn = oldItem.scrapTechReturn;
      }
    }

    newTypes[slot] = item.equipKey!;
    newLevels[slot] = item.level;

    final updated = player.copyWith(
      weaponTypes: newTypes,
      weaponSlots: newLevels,
      credits: player.credits - item.priceCredits,
      scrapMetal: player.scrapMetal - item.priceScrapMetal + scrapMetalReturn,
      scrapTech: player.scrapTech - item.priceScrapTech + scrapTechReturn,
    );
    onPlayerUpdate(updated);
    final msg = scrapMetalReturn > 0
        ? '${item.name} installed — scrapped old weapon for ${scrapMetalReturn}M${scrapTechReturn > 0 ? " ${scrapTechReturn}T" : ""}'
        : '${item.name} installed in $slot slot';
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(msg),
    );
  }

  void _showSlotPicker(
      BuildContext context, HardwareItem item, List<String> slots) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Slot'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: slots.map((slot) {
            final current = player.weaponTypes[slot];
            return ListTile(
              title: Text(_formatSlotName(slot)),
              subtitle: current != null
                  ? Text('Replace: ${_formatEquipName(current)}')
                  : null,
              onTap: () {
                Navigator.pop(ctx);
                _installWeapon(context, item, slot);
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  String _formatSlotName(String s) =>
      s[0].toUpperCase() + s.substring(1).replaceAll('_', ' ');
  String _formatEquipName(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (i == 0) {
        buf.write(c.toUpperCase());
      } else if (c == c.toUpperCase() && c != c.toLowerCase()) {
        buf.write(' ');
        buf.write(c);
      } else {
        buf.write(c);
      }
    }
    return buf.toString();
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      );
}

// ── Equipment Tab (Hull / Shield / Engine) ─────────────
class _EquipmentTab extends StatelessWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;
  final HardwareCategory category;

  const _EquipmentTab({
    required this.player,
    required this.onPlayerUpdate,
    required this.category,
  });

  @override
  Widget build(BuildContext context) {
    final items = itemsForFaction(category, player.faction);
    final currentEquipKey = _currentEquipKey();
    final currentLevel = _currentLevel();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (currentEquipKey != null)
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primaryContainer
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.2)),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Equipped: ${_formatEquipName(currentEquipKey)} Lv.$currentLevel',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ...items.map((item) => _ItemCard(
              item: item,
              player: player,
              isCurrentEquipment: item.equipKey == currentEquipKey &&
                  item.level == currentLevel,
              onBuy: () => _buyEquipment(context, item),
            )),
      ],
    );
  }

  String? _currentEquipKey() {
    switch (category) {
      case HardwareCategory.hull:
        return player.hullEquipment;
      case HardwareCategory.shield:
        return player.shieldEquipment;
      case HardwareCategory.engine:
        return player.engineEquipment;
      default:
        return null;
    }
  }

  int _currentLevel() {
    switch (category) {
      case HardwareCategory.hull:
        return player.hullEquipmentLevel;
      case HardwareCategory.shield:
        return player.shieldEquipmentLevel;
      case HardwareCategory.engine:
        return player.engineEquipmentLevel;
      default:
        return 0;
    }
  }

  void _buyEquipment(BuildContext context, HardwareItem item) {
    if (player.credits < item.priceCredits) {
      _showError(context, 'Insufficient credits');
      return;
    }
    if (player.scrapMetal < item.priceScrapMetal) {
      _showError(context, 'Insufficient scrap metal');
      return;
    }
    if (player.scrapTech < item.priceScrapTech) {
      _showError(context, 'Insufficient scrap tech');
      return;
    }

    int scrapMetalReturn = 0;
    int scrapTechReturn = 0;
    final oldKey = _currentEquipKey();
    final oldLv = _currentLevel();
    if (oldKey != null && oldLv > 0) {
      final oldItem = itemFor(oldKey, category, oldLv);
      if (oldItem != null) {
        scrapMetalReturn = oldItem.scrapMetalReturn;
        scrapTechReturn = oldItem.scrapTechReturn;
      }
    }

    Player updated;
    switch (category) {
      case HardwareCategory.hull:
        updated = player.copyWith(
          hullEquipment: item.equipKey,
          hullEquipmentLevel: item.level,
          credits: player.credits - item.priceCredits,
          scrapMetal:
              player.scrapMetal - item.priceScrapMetal + scrapMetalReturn,
          scrapTech: player.scrapTech - item.priceScrapTech + scrapTechReturn,
        );
        break;
      case HardwareCategory.shield:
        updated = player.copyWith(
          shieldEquipment: item.equipKey,
          shieldEquipmentLevel: item.level,
          credits: player.credits - item.priceCredits,
          scrapMetal:
              player.scrapMetal - item.priceScrapMetal + scrapMetalReturn,
          scrapTech: player.scrapTech - item.priceScrapTech + scrapTechReturn,
        );
        break;
      case HardwareCategory.engine:
        updated = player.copyWith(
          engineEquipment: item.equipKey,
          engineEquipmentLevel: item.level,
          credits: player.credits - item.priceCredits,
          scrapMetal:
              player.scrapMetal - item.priceScrapMetal + scrapMetalReturn,
          scrapTech: player.scrapTech - item.priceScrapTech + scrapTechReturn,
        );
        break;
      default:
        return;
    }
    onPlayerUpdate(updated);
    final msg = scrapMetalReturn > 0
        ? '${item.name} installed — scrapped old for ${scrapMetalReturn}M${scrapTechReturn > 0 ? " ${scrapTechReturn}T" : ""}'
        : '${item.name} installed';
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(msg),
    );
  }

  String _formatEquipName(String s) {
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final c = s[i];
      if (i == 0) {
        buf.write(c.toUpperCase());
      } else if (c == c.toUpperCase() && c != c.toLowerCase()) {
        buf.write(' ');
        buf.write(c);
      } else {
        buf.write(c);
      }
    }
    return buf.toString().replaceAll('_', ' ');
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      );
}

// ── Modules Tab ────────────────────────────────────────
class _ModulesTab extends StatelessWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const _ModulesTab({required this.player, required this.onPlayerUpdate});

  @override
  Widget build(BuildContext context) {
    final items = itemsForFaction(HardwareCategory.module, player.faction);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (player.installedModules.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .tertiaryContainer
                  .withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .tertiary
                      .withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Installed Modules',
                    style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.tertiary)),
                const SizedBox(height: 4),
                ...player.installedModules.entries.map((e) {
                  final def =
                      moduleDefs.where((m) => m.id == e.key).firstOrNull;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle_outline,
                            size: 12,
                            color: Theme.of(context).colorScheme.tertiary),
                        const SizedBox(width: 6),
                        Text(
                          '${def?.name ?? e.key} Lv.${e.value}',
                          style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.7)),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ...items.map((item) => _ItemCard(
              item: item,
              player: player,
              onBuy: () => _buyModule(context, item),
              isCurrentEquipment:
                  player.installedModules[item.equipKey] == item.level,
            )),
      ],
    );
  }

  void _buyModule(BuildContext context, HardwareItem item) {
    if (player.credits < item.priceCredits) {
      _showError(context, 'Insufficient credits');
      return;
    }
    if (player.scrapMetal < item.priceScrapMetal) {
      _showError(context, 'Insufficient scrap metal');
      return;
    }
    if (player.scrapTech < item.priceScrapTech) {
      _showError(context, 'Insufficient scrap tech');
      return;
    }

    final newModules = Map<String, int>.from(player.installedModules);
    final oldLv = newModules[item.equipKey!];

    int scrapMetalReturn = 0;
    int scrapTechReturn = 0;
    if (oldLv != null) {
      final oldItem = itemFor(item.equipKey!, HardwareCategory.module, oldLv);
      if (oldItem != null) {
        scrapMetalReturn = oldItem.scrapMetalReturn;
        scrapTechReturn = oldItem.scrapTechReturn;
      }
    }

    newModules[item.equipKey!] = item.level;

    final updated = player.copyWith(
      installedModules: newModules,
      credits: player.credits - item.priceCredits,
      scrapMetal: player.scrapMetal - item.priceScrapMetal + scrapMetalReturn,
      scrapTech: player.scrapTech - item.priceScrapTech + scrapTechReturn,
    );
    onPlayerUpdate(updated);
    final msg = scrapMetalReturn > 0
        ? '${item.name} installed — scrapped old for ${scrapMetalReturn}M${scrapTechReturn > 0 ? " ${scrapTechReturn}T" : ""}'
        : '${item.name} installed';
    ScaffoldMessenger.of(context).showSnackBar(
      _snack(msg),
    );
  }

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      );
}

// ── Scrap Exchange Tab ─────────────────────────────────
class _ScrapTab extends StatelessWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const _ScrapTab({required this.player, required this.onPlayerUpdate});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Scrap Inventory',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: cs.onSurface)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.calculate_outlined,
                      size: 18, color: Colors.teal.shade300),
                  const SizedBox(width: 6),
                  Text('${player.scrapMetal}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal.shade300)),
                  const SizedBox(width: 4),
                  Text('Scrap Metal',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.6))),
                  const Spacer(),
                  Icon(Icons.sell_rounded,
                      size: 14, color: Colors.amber.shade300),
                  const SizedBox(width: 4),
                  Text('$scrapMetalSellPrice cr/unit',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade300,
                          fontFamily: 'monospace')),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.memory_rounded,
                      size: 18, color: Colors.purple.shade300),
                  const SizedBox(width: 6),
                  Text('${player.scrapTech}',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.purple.shade300)),
                  const SizedBox(width: 4),
                  Text('Scrap Tech',
                      style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.6))),
                  const Spacer(),
                  Icon(Icons.sell_rounded,
                      size: 14, color: Colors.amber.shade300),
                  const SizedBox(width: 4),
                  Text('$scrapTechSellPrice cr/unit',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.amber.shade300,
                          fontFamily: 'monospace')),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (player.scrapMetal > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SellScrapCard(
              label: 'Sell All Scrap Metal',
              amount: player.scrapMetal,
              totalCredits: player.scrapMetal * scrapMetalSellPrice,
              icon: Icons.calculate_outlined,
              color: Colors.teal,
              onSell: () {
                final updated = player.copyWith(
                  scrapMetal: 0,
                  credits:
                      player.credits + player.scrapMetal * scrapMetalSellPrice,
                );
                onPlayerUpdate(updated);
                ScaffoldMessenger.of(context).showSnackBar(
                  _snack(
                      'Sold ${player.scrapMetal} scrap metal for ${player.scrapMetal * scrapMetalSellPrice} cr'),
                );
              },
            ),
          ),
        if (player.scrapTech > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SellScrapCard(
              label: 'Sell All Scrap Tech',
              amount: player.scrapTech,
              totalCredits: player.scrapTech * scrapTechSellPrice,
              icon: Icons.memory_rounded,
              color: Colors.purple,
              onSell: () {
                final updated = player.copyWith(
                  scrapTech: 0,
                  credits:
                      player.credits + player.scrapTech * scrapTechSellPrice,
                );
                onPlayerUpdate(updated);
                ScaffoldMessenger.of(context).showSnackBar(
                  _snack(
                      'Sold ${player.scrapTech} scrap tech for ${player.scrapTech * scrapTechSellPrice} cr'),
                );
              },
            ),
          ),
        if (player.scrapMetal <= 0 && player.scrapTech <= 0)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined,
                      size: 32, color: cs.onSurface.withValues(alpha: 0.2)),
                  const SizedBox(height: 8),
                  Text('No scrap to exchange',
                      style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: cs.onSurface.withValues(alpha: 0.4))),
                  Text('Destroy enemy ships to collect scrap',
                      style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: cs.onSurface.withValues(alpha: 0.3))),
                ],
              ),
            ),
          ),
      ],
    );
  }

  SnackBar _snack(String msg) => SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'monospace')),
        backgroundColor: Colors.deepPurpleAccent,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      );
}

class _SellScrapCard extends StatelessWidget {
  final String label;
  final int amount;
  final int totalCredits;
  final IconData icon;
  final Color color;
  final VoidCallback onSell;

  const _SellScrapCard({
    required this.label,
    required this.amount,
    required this.totalCredits,
    required this.icon,
    required this.color,
    required this.onSell,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                        color: cs.onSurface)),
                Text('$amount units → $totalCredits cr',
                    style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'monospace',
                        color: Colors.amber.shade300)),
              ],
            ),
          ),
          SizedBox(
            height: 28,
            child: ElevatedButton.icon(
              onPressed: onSell,
              icon: Icon(Icons.sell_rounded, size: 12),
              label: Text('SELL',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'monospace')),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                backgroundColor: Colors.deepPurpleAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared Item Card ───────────────────────────────────
class _ItemCard extends StatelessWidget {
  final HardwareItem item;
  final Player player;
  final VoidCallback? onBuy;
  final bool isCurrentEquipment;
  final String? restrictionReason;

  const _ItemCard({
    required this.item,
    required this.player,
    this.onBuy,
    this.isCurrentEquipment = false,
    this.restrictionReason,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canAffordCredits = player.credits >= item.priceCredits;
    final canAffordScrapMetal = player.scrapMetal >= item.priceScrapMetal;
    final canAffordScrapTech = player.scrapTech >= item.priceScrapTech;
    final canAfford = canAffordCredits &&
        canAffordScrapMetal &&
        canAffordScrapTech &&
        restrictionReason == null;
    final showScrapCost = item.priceScrapMetal > 0 || item.priceScrapTech > 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentEquipment
            ? cs.primaryContainer.withValues(alpha: 0.12)
            : cs.surfaceContainerHighest.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentEquipment
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: cs.primary.withValues(alpha: 0.2)),
                ),
                child: Text(
                  'Lv ${item.level}',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                    color: cs.primary,
                  ),
                ),
              ),
            ],
          ),
          if (item.description.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              item.description,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          if (item.statLine != null) ...[
            const SizedBox(height: 4),
            Text(
              item.statLine!,
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: Colors.cyan.shade300.withValues(alpha: 0.7),
              ),
            ),
          ],
          if (restrictionReason != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.priority_high_rounded,
                    size: 12, color: Colors.orange.shade300),
                const SizedBox(width: 4),
                Text(
                  restrictionReason!,
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade300,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.monetization_on_rounded,
                  size: 14, color: Colors.amber.shade300),
              const SizedBox(width: 4),
              Text(
                _formatCredits(item.priceCredits),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: canAffordCredits
                      ? Colors.amber.shade300
                      : cs.error.withValues(alpha: 0.6),
                ),
              ),
              if (showScrapCost) ...[
                const SizedBox(width: 8),
                Icon(Icons.calculate_outlined,
                    size: 12, color: Colors.teal.shade300),
                const SizedBox(width: 2),
                Text(
                  '${item.priceScrapMetal}M',
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w500,
                    color: canAffordScrapMetal
                        ? Colors.teal.shade300
                        : cs.error.withValues(alpha: 0.6),
                  ),
                ),
                if (item.priceScrapTech > 0) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.memory_rounded,
                      size: 12, color: Colors.purple.shade300),
                  const SizedBox(width: 2),
                  Text(
                    '${item.priceScrapTech}T',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w500,
                      color: canAffordScrapTech
                          ? Colors.purple.shade300
                          : cs.error.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ],
              const Spacer(),
              if (isCurrentEquipment)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'EQUIPPED',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                      fontFamily: 'monospace',
                      color: cs.primary,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 28,
                  child: ElevatedButton.icon(
                    onPressed: canAfford ? onBuy : null,
                    icon: Icon(Icons.shopping_cart_rounded, size: 12),
                    label: Text(
                      'BUY',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                        fontFamily: 'monospace',
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      backgroundColor: canAfford
                          ? Colors.deepPurpleAccent
                          : cs.surfaceContainerHighest,
                      foregroundColor: canAfford
                          ? Colors.white
                          : cs.onSurface.withValues(alpha: 0.4),
                      disabledBackgroundColor: cs.surfaceContainerHighest,
                      disabledForegroundColor:
                          cs.onSurface.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6)),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatCredits(int value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M cr';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K cr';
    }
    return '$value cr';
  }
}
