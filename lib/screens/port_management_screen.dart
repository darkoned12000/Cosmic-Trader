import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/commodity.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/port.dart';

class PortManagementScreen extends StatefulWidget {
  final Port port;
  final Player player;
  final void Function(Player) onPlayerUpdate;
  final void Function(Port) onPortUpdated;

  const PortManagementScreen({
    super.key,
    required this.port,
    required this.player,
    required this.onPlayerUpdate,
    required this.onPortUpdated,
  });

  @override
  State<PortManagementScreen> createState() => _PortManagementScreenState();
}

class _PortManagementScreenState extends State<PortManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Port _localPort;

  Port get _port => _localPort;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _localPort = widget.port;
  }

  @override
  void didUpdateWidget(PortManagementScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.port != oldWidget.port) {
      _localPort = widget.port;
    }
  }

  void _updatePort(Port updated) {
    setState(() => _localPort = updated);
    widget.onPortUpdated(updated);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _fmt(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        title: Text(
          _port.name,
          style: TextStyle(fontWeight: FontWeight.bold, color: cs.onSurface),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: cs.onSurface),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: cs.primary,
          labelColor: cs.primary,
          unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_rounded), text: 'Overview'),
            Tab(icon: Icon(Icons.shield_rounded), text: 'Defenses'),
            Tab(icon: Icon(Icons.inventory_2_rounded), text: 'Storage'),
            Tab(icon: Icon(Icons.tune_rounded), text: 'Pricing'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _overviewTab(theme, cs),
          _defensesTab(theme, cs),
          _storageTab(theme, cs),
          _pricingTab(theme, cs),
        ],
      ),
    );
  }

  // ── Overview Tab ──────────────────────────────────────────────

  Widget _overviewTab(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(theme, cs),
          const SizedBox(height: 16),
          _revenueCard(theme, cs),
          const SizedBox(height: 16),
          _statsCard(theme, cs),
        ],
      ),
    );
  }

  Widget _infoCard(ThemeData theme, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.tertiary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.store_rounded, size: 32, color: cs.tertiary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _port.portType != null
                        ? '${_port.name} (${_port.portType})'
                        : _port.name,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _portClassLabel(_port.portClass),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  if (_port.ownerFaction != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _factionColor(_port.ownerFaction!)
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _port.ownerFaction!.displayName,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _factionColor(_port.ownerFaction!),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Net: ${_fmt(_port.netWorth)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: cs.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _revenueCard(ThemeData theme, ColorScheme cs) {
    final revenue = _port.accumulatedRevenue;
    final canCollect = revenue > 0;

    return Card(
      elevation: 0,
      color: Colors.green.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up_rounded,
                    size: 28, color: Colors.green.shade300),
                const SizedBox(width: 12),
                Text(
                  'Accumulated Revenue',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${_fmt(revenue)} cr',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade300,
                  ),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: canCollect ? _collectRevenue : null,
                  icon: const Icon(Icons.account_balance_wallet_rounded,
                      size: 18),
                  label: Text(canCollect ? 'Collect' : 'Empty'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        cs.onSurface.withValues(alpha: 0.1),
                    disabledForegroundColor:
                        cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Earned from your ${_port.ownerTaxRate * 100}% cut of port trades',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statsCard(ThemeData theme, ColorScheme cs) {
    final ratio = _port.cashRatio;
    final healthColor = ratio < 0.7
        ? Colors.deepOrange
        : ratio < 1.3
            ? Colors.green
            : Colors.amber;
    final healthLabel = ratio < 0.7
        ? 'Distressed'
        : ratio < 1.3
            ? 'Healthy'
            : 'Flush';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Port Statistics',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _statRow(cs, 'Port Credits', _fmt(_port.portCredits)),
            _statRow(cs, 'Cash Health', '$healthLabel (${(ratio * 100).round()}%)',
                valueColor: healthColor.shade300),
            _statRow(cs, 'Defense Level', '${_port.defenseLevel}/4'),
            _statRow(cs, 'Storage Level', '${_port.storageLevel}/10'),
            _statRow(cs, 'Trade Tax', '${(_port.ownerTaxRate * 100).round()}%'),
            _statRow(
                cs, 'Desired Credits', _fmt(_port.desiredCredits)),
          ],
        ),
      ),
    );
  }

  Widget _statRow(ColorScheme cs, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withValues(alpha: 0.6))),
          Text(value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: valueColor ?? cs.onSurface,
              )),
        ],
      ),
    );
  }

  // ── Defenses Tab ──────────────────────────────────────────────

  static const _defenseDescriptions = [
    'No defensive systems installed.',
    'Basic laser turrets — deters minor pirate activity.',
    'Laser turrets + drone swarm — moderate threat deterrence.',
    'Full battery: lasers, drones, missiles — strong defense.',
    'Maximum security: lasers, drones, missiles, EMP array.',
  ];

  static const _defenseEffects = [
    'No protection',
    '-10% NPC raid chance',
    '-25% NPC raid chance',
    '-50% NPC raid chance',
    '-80% NPC raid chance',
  ];

  Widget _defensesTab(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Port Defenses',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Upgrade defenses to protect your investment from pirates and rival factions.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(5, (i) => _defenseLevelCard(theme, cs, i)),
        ],
      ),
    );
  }

  Widget _defenseLevelCard(ThemeData theme, ColorScheme cs, int level) {
    final isCurrent = level == _port.defenseLevel;
    final isOwned = level <= _port.defenseLevel;
    final isUpgrade = level == _port.defenseLevel + 1 && _port.canUpgradeDefense;
    final cost = level > 0 ? level * 250000.0 : 0.0;

    Color borderColor;
    Color bgColor;
    if (isOwned) {
      borderColor = Colors.green.shade700;
      bgColor = Colors.green.withValues(alpha: 0.08);
    } else if (isUpgrade) {
      borderColor = cs.primary;
      bgColor = cs.primary.withValues(alpha: 0.08);
    } else {
      borderColor = cs.onSurface.withValues(alpha: 0.1);
      bgColor = cs.surface;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: isCurrent || isUpgrade ? 1.5 : 1),
          color: bgColor,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isOwned ? Icons.check_circle_rounded : Icons.lock_rounded,
                  size: 20,
                  color: isOwned
                      ? Colors.green.shade400
                      : cs.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
                Text(
                  'Level $level',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: isOwned
                        ? Colors.green.shade400
                        : cs.onSurface,
                  ),
                ),
                if (isCurrent) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.shade700,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'ACTIVE',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isUpgrade)
                  FilledButton(
                    onPressed: () => _upgradeDefense(cost),
                    style: FilledButton.styleFrom(
                      backgroundColor: cs.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                    child: Text('${_fmt(cost)} cr'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _defenseDescriptions[level],
              style: TextStyle(
                fontSize: 13,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _defenseEffects[level],
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: level <= _port.defenseLevel
                    ? Colors.green.shade300
                    : cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _upgradeDefense(double cost) {
    if (widget.player.credits < cost) {
      _showError('Insufficient credits. Need ${_fmt(cost)} cr.');
      return;
    }
    _showConfirm(
      'Upgrade Defenses',
      'Upgrade to Level ${_port.defenseLevel + 1} for ${_fmt(cost)} cr?',
      () {
        _updatePort(_port.copyWith(
          defenseLevel: _port.defenseLevel + 1,
        ));
        widget.onPlayerUpdate(widget.player.copyWith(
          credits: widget.player.credits - cost.toInt(),
        ));
      },
    );
  }

  // ── Storage Tab ───────────────────────────────────────────────

  Widget _storageTab(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storage Capacity',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Each storage level increases max supply and demand by 50%. More capacity means more trade throughput.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          _storageLevelCard(theme, cs),
          const SizedBox(height: 16),
          _storagePreviewCard(theme, cs),
        ],
      ),
    );
  }

  Widget _storageLevelCard(ThemeData theme, ColorScheme cs) {
    final level = _port.storageLevel;
    final multiplier = math.pow(1.5, level);
    final nextMultiplier = math.pow(1.5, level + 1);
    final cost = _port.storageUpgradeCost;
    final canUpgrade = _port.canUpgradeStorage &&
        widget.player.credits >= cost;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.inventory_2_rounded,
                    size: 28, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Level $level / 10',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${multiplier.toStringAsFixed(1)}× capacity multiplier',
                        style: TextStyle(
                          fontSize: 13,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_port.canUpgradeStorage) ...[
              const SizedBox(height: 20),
              LinearProgressIndicator(
                value: level / 10,
                backgroundColor: cs.onSurface.withValues(alpha: 0.1),
                color: cs.primary,
              ),
              const SizedBox(height: 8),
              Text(
                'Next level: ${nextMultiplier.toStringAsFixed(1)}× capacity',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: canUpgrade
                      ? () => _upgradeStorage(cost)
                      : null,
                  icon: const Icon(Icons.add_circle_rounded, size: 20),
                  label: Text(
                    cost.isFinite
                        ? 'Upgrade — ${_fmt(cost)} cr'
                        : 'MAX LEVEL',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: canUpgrade ? cs.primary : null,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              if (!canUpgrade && _port.canUpgradeStorage)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Not enough credits (need ${_fmt(cost)} cr)',
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.error,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _storagePreviewCard(ThemeData theme, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Capacity',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            ...CommodityRegistry.names.map((c) {
              final base = _port.maxSupply[c] ?? 0;
              final effective = _port.effectiveMaxSupply(c);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c[0].toUpperCase() + c.substring(1),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      '$base → $effective',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: effective > base
                            ? Colors.green.shade300
                            : cs.onSurface,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _upgradeStorage(double cost) {
    _showConfirm(
      'Upgrade Storage',
      'Upgrade to Level ${_port.storageLevel + 1} for ${_fmt(cost)} cr?\n\n'
      'Supply/Demand capacity will increase by 50%.',
      () {
        _updatePort(_port.copyWith(
          storageLevel: _port.storageLevel + 1,
        ));
        widget.onPlayerUpdate(widget.player.copyWith(
          credits: widget.player.credits - cost.toInt(),
        ));
      },
    );
  }

  // ── Pricing Tab ───────────────────────────────────────────────

  Widget _pricingTab(ThemeData theme, ColorScheme cs) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pricing Controls',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Override automatic pricing to set custom margins per commodity. '
            'Lower values attract traders, higher values maximize profit.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 20),
          _taxRateCard(theme, cs),
          const SizedBox(height: 16),
          _pricingOverrideCard(theme, cs),
          const SizedBox(height: 16),
          _pricingPreviewCard(theme, cs),
        ],
      ),
    );
  }

  Widget _taxRateCard(ThemeData theme, ColorScheme cs) {
    final rate = _port.ownerTaxRate;

    return Card(
      elevation: 0,
      color: cs.secondaryContainer.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.receipt_rounded, size: 24, color: cs.secondary),
                const SizedBox(width: 12),
                Text(
                  'Trade Tax Rate',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  '${(rate * 100).round()}%',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.secondary,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 200,
                  child: Slider(
                    value: rate,
                    min: 0,
                    max: 0.15,
                    divisions: 15,
                    label: '${(rate * 100).round()}%',
                    onChanged: (v) {
                      _updatePort(_port.copyWith(
                        ownerTaxRate: double.parse(v.toStringAsFixed(2)),
                      ));
                    },
                  ),
                ),
              ],
            ),
            Text(
              'Higher tax = more revenue per trade, but may drive traders away',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pricingOverrideCard(ThemeData theme, ColorScheme cs) {
    final override = _port.pricingOverride ?? {};

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 24, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Price Overrides',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'Set a custom price multiplier per commodity (null = automatic)',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...CommodityRegistry.names.map((c) {
              final current = override[c];
              final basePrice = _port.getSellPrice(c);
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          c[0].toUpperCase() + c.substring(1),
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '(Base: ${basePrice.toInt()} cr)',
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          current != null
                              ? '${(current * 100).round()}%'
                              : 'Auto',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: current != null
                                ? cs.primary
                                : cs.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Slider(
                            value: current ?? 1.0,
                            min: 0.2,
                            max: 3.0,
                            divisions: 28,
                            label: current != null
                                ? '${(current * 100).round()}%'
                                : 'Auto',
                            onChanged: (v) {
                              final newOverride = Map<String, double>.from(override);
                              newOverride[c] = double.parse(v.toStringAsFixed(2));
                              _updatePort(_port.copyWith(
                                pricingOverride: newOverride,
                              ));
                            },
                          ),
                        ),
                        if (current != null)
                          IconButton(
                            icon: Icon(Icons.clear_rounded,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.4)),
                            onPressed: () {
                              final newOverride = Map<String, double>.from(override);
                              newOverride.remove(c);
                              _updatePort(_port.copyWith(
                                pricingOverride: newOverride.isEmpty
                                    ? null
                                    : newOverride,
                              ));
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            if (override.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () {
                    _updatePort(_port.copyWith(
                      clearPricingOverride: true,
                    ));
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset to Auto'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _pricingPreviewCard(ThemeData theme, ColorScheme cs) {
    return Card(
      elevation: 0,
      color: cs.tertiaryContainer.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Current Effective Prices',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: cs.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            ...CommodityRegistry.names.map((c) {
              final buy = _port.getEffectiveBuyPrice(c);
              final sell = _port.getEffectiveSellPrice(c);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c[0].toUpperCase() + c.substring(1),
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                    Text(
                      'Buy: ${buy > 0 ? '${buy.toInt()} cr' : 'N/A'}  '
                      'Sell: ${sell > 0 ? '${sell.toInt()} cr' : 'N/A'}',
                      style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────

  Color _factionColor(FactionClass fc) {
    switch (fc) {
      case FactionClass.duran:
        return const Color(0xFF00BCD4);
      case FactionClass.vinari:
        return const Color(0xFF9C27B0);
      case FactionClass.trader:
        return const Color(0xFF4CAF50);
      case FactionClass.pirate:
        return const Color(0xFFFF5722);
    }
  }

  String _portClassLabel(PortClass pc) {
    switch (pc) {
      case PortClass.federal:
        return 'Federal Port';
      case PortClass.free:
        return 'Free Port';
      case PortClass.independent:
        return 'Independent Port';
      case PortClass.hardwareEmporium:
        return 'Hardware Emporium';
    }
  }

  void _collectRevenue() {
    final revenue = _port.accumulatedRevenue;
    if (revenue <= 0) return;

    _showConfirm(
      'Collect Revenue',
      'Withdraw ${_fmt(revenue)} cr from port earnings?',
      () {
        _updatePort(_port.copyWith(
          accumulatedRevenue: 0,
          portCredits: _port.portCredits - revenue,
        ));
        widget.onPlayerUpdate(widget.player.copyWith(
          credits: widget.player.credits + revenue.toInt(),
          bankBalance: widget.player.bankBalance,
        ));
      },
    );
  }

  void _showConfirm(String title, String message, VoidCallback onConfirm) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
