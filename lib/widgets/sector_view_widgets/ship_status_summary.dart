import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';

class ShipStatusSummary extends StatefulWidget {
  final Player player;

  const ShipStatusSummary({
    super.key,
    required this.player,
  });

  @override
  State<ShipStatusSummary> createState() => _ShipStatusSummaryState();
}

class _ShipStatusSummaryState extends State<ShipStatusSummary> {
  bool _cargoExpanded = false;

  Widget _buildCargoContents(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cargo = widget.player.cargo;
    final items = cargo.entries.where((e) => e.value > 0).toList();
    final hasCargo = items.isNotEmpty;

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => setState(() => _cargoExpanded = !_cargoExpanded),
          child: Padding(
            padding: EdgeInsets.symmetric(
                vertical: UiScale.spacing(4), horizontal: 4),
            child: Row(
              children: [
                Icon(
                  _cargoExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 14,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 4),
                Text(
                  'CARGO HOLD',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                Text(
                  '${items.length} type${items.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 9,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: hasCargo
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final entry in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              Text(
                                '\u2022',
                                style: TextStyle(
                                  color: Colors.amber.shade300,
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  entry.key.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontFamily: 'monospace',
                                    color: cs.onSurface.withValues(alpha: 0.75),
                                  ),
                                ),
                              ),
                              Text(
                                '${entry.value}',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  )
                : Text(
                    'EMPTY',
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                  ),
          ),
          crossFadeState: _cargoExpanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final hullPercent =
        (widget.player.hull / widget.player.maxHull * 100).round();
    final shieldPercent =
        (widget.player.shields / widget.player.maxShields * 100).round();
    final cargoPercent =
        (widget.player.cargoUsed / widget.player.maxCargo * 100).round();

    Color hullColor;
    if (hullPercent > 75) {
      hullColor = const Color(0xFF00FF41);
    } else if (hullPercent > 50) {
      hullColor = Colors.blue.shade300;
    } else if (hullPercent > 25) {
      hullColor = Colors.amber.shade300;
    } else {
      hullColor = const Color(0xFFFF0040);
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(UiScale.spacing(12)),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.rocket_launch_rounded,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'SHIP STATUS',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 1,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(UiScale.spacing(12)),
            child: Column(
              children: [
                // Hull
                StatBar(
                  label: 'HULL',
                  value: '${widget.player.hull}/${widget.player.maxHull}',
                  percent: hullPercent / 100,
                  color: hullColor,
                  icon: Icons.verified_user_rounded,
                ),
                SizedBox(height: UiScale.spacing(10)),

                // Shields
                StatBar(
                  label: 'SHIELDS',
                  value: '${widget.player.shields}/${widget.player.maxShields}',
                  percent: shieldPercent / 100,
                  color: Colors.blue.shade300,
                  icon: Icons.shield_rounded,
                ),
                SizedBox(height: UiScale.spacing(10)),

                // Drones
                StatBar(
                  label: 'DRONES',
                  value: '${widget.player.drones}/${widget.player.maxDrones}',
                  percent: widget.player.maxDrones > 0
                      ? widget.player.drones / widget.player.maxDrones
                      : 0,
                  color: Colors.purpleAccent,
                  icon: Icons.hexagon_rounded,
                ),
                SizedBox(height: UiScale.spacing(10)),

                // Cargo
                StatBar(
                  label: 'CARGO',
                  value: '${widget.player.cargoUsed}/${widget.player.maxCargo}',
                  percent: cargoPercent / 100,
                  color: Colors.amber.shade300,
                  icon: Icons.inventory_2_rounded,
                ),
                SizedBox(height: UiScale.spacing(6)),

                // Cargo contents (collapsible)
                _buildCargoContents(context),

                // Weapons summary
                Divider(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
                SizedBox(height: UiScale.spacing(8)),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _WeaponChip(
                        label: 'MFW',
                        level: widget.player.weaponSlots['main_forward'] ?? 0),
                    _WeaponChip(
                        label: 'STB',
                        level: widget.player.weaponSlots['starboard'] ?? 0),
                    _WeaponChip(
                        label: 'PRT',
                        level: widget.player.weaponSlots['port'] ?? 0),
                    _WeaponChip(
                        label: 'AFT',
                        level: widget.player.weaponSlots['aft'] ?? 0),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WeaponChip extends StatelessWidget {
  final String label;
  final int level;

  const _WeaponChip({
    required this.label,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasWeapon = level > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: hasWeapon
            ? cs.primary.withValues(alpha: 0.15)
            : cs.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasWeapon
              ? cs.primary.withValues(alpha: 0.3)
              : cs.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Text(
        '$label ${level > 0 ? 'L$level' : '---'}',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          fontFamily: 'monospace',
          color: hasWeapon ? cs.primary : cs.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}
