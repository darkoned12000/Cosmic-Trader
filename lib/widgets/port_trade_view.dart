import 'package:flutter/material.dart';
import 'dart:async';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/screens/port_management_screen.dart';
import 'package:cosmic_trader/services/audio_service.dart';
import 'package:cosmic_trader/widgets/lottery_widget.dart';
import 'package:cosmic_trader/widgets/hold_button.dart';
import 'package:cosmic_trader/widgets/shared/data_table_shell.dart';
import 'package:cosmic_trader/widgets/shared/hud_pill.dart';

/// Compact, HUD-styled trade view. Same trading logic as before -- only the
/// layout changed: single-row header, one stat strip, and the three
/// commodity cards collapsed into a dense table.
class PortTradeView extends StatelessWidget {
  final Port port;
  final Player player;
  final Function(Player) onPlayerUpdate;
  final void Function(Port) onPortUpdated;
  final VoidCallback onHackPort;
  final VoidCallback onStealResources;
  final VoidCallback onBuyPort;
  final VoidCallback onAttackPort;
  final VoidCallback onOpenHackCodex;
  final int hackFailCount;
  final int maxHackAttempts;
  final int? hackBannedUntilEpoch;
  final VoidCallback? onBanExpired;

  const PortTradeView({
    super.key,
    required this.port,
    required this.player,
    required this.onPlayerUpdate,
    required this.onPortUpdated,
    required this.onHackPort,
    required this.onStealResources,
    required this.onBuyPort,
    required this.onAttackPort,
    required this.onOpenHackCodex,
    required this.hackFailCount,
    required this.maxHackAttempts,
    this.hackBannedUntilEpoch,
    this.onBanExpired,
  });

  static List<String> get _commodities => CommodityRegistry.names;
  static const _commodityIcons = {
    'minerals': Icons.diamond_rounded,
    'organics': Icons.eco_rounded,
    'industrial': Icons.precision_manufacturing_rounded,
  };
  static const _commodityLabels = {
    'minerals': 'Minerals',
    'organics': 'Organics',
    'industrial': 'Industrial',
  };
  static const _portClassLabels = {
    PortClass.federal: 'Federal',
    PortClass.free: 'Free',
    PortClass.independent: 'Independent',
    PortClass.hardwareEmporium: 'Hardware',
  };

  int _remainingSupply(String commodity) => port.getSupply(commodity);
  int _remainingDemand(String commodity) => port.getDemand(commodity);

  int _playerAmount(String commodity) => player.cargo[commodity] ?? 0;

  String _formatCredits(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  bool get _isOwner => player.ownsPort(port.name);

  double get _ownerFeeRate => port.isOwned && !_isOwner ? port.ownerTaxRate : 0;

  bool _canBuy(String commodity) {
    if (!port.sells(commodity)) return false;
    if (_remainingSupply(commodity) <= 0) return false;
    final price = port.getEffectiveSellPrice(commodity);
    if (price <= 0) return false;
    final totalCost = price * (1 + _ownerFeeRate);
    if (player.credits < totalCost) return false;
    if (player.cargoUsed >= player.maxCargo) return false;
    return true;
  }

  bool _canSell(String commodity) {
    if (!port.buys(commodity)) return false;
    if (_remainingDemand(commodity) <= 0) return false;
    final price = port.getEffectiveBuyPrice(commodity);
    if (price <= 0) return false;
    if ((player.cargo[commodity] ?? 0) <= 0) return false;
    return true;
  }

  void _buy(String commodity) {
    final price = port.getEffectiveSellPrice(commodity).toInt();
    if (price <= 0) return;
    if (_remainingSupply(commodity) <= 0) return;
    AudioService.instance.playSfx('assets/sfx/buy.ogg');

    final amount = 1;
    final newCargo = Map<String, int>.from(player.cargo);
    newCargo[commodity] = (newCargo[commodity] ?? 0) + amount;

    final transactionValue = price * amount;
    final ownerFee = port.isOwned && !_isOwner
        ? (transactionValue * port.ownerTaxRate).round()
        : 0;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    onPortUpdated(port.copyWith(
      supply: <String, int>{
        ...port.supply,
        commodity: _remainingSupply(commodity) - amount,
      },
      portCredits: port.portCredits + transactionValue,
      accumulatedRevenue: port.accumulatedRevenue + ownerFee,
      lastRegenTime: nowMs,
    ));

    onPlayerUpdate(_withTradeReputation(player.copyWith(
      cargo: newCargo,
      cargoUsed: player.cargoUsed + amount,
      credits: player.credits - transactionValue - ownerFee,
    )));
  }

  void _sell(String commodity) {
    final price = port.getEffectiveBuyPrice(commodity).toInt();
    if (price <= 0) return;
    final currentQty = player.cargo[commodity] ?? 0;
    if (currentQty <= 0) return;
    if (_remainingDemand(commodity) <= 0) return;
    AudioService.instance.playSfx('assets/sfx/sell.ogg');

    final amount = 1;
    final newCargo = Map<String, int>.from(player.cargo);
    newCargo[commodity] = currentQty - amount;
    if (newCargo[commodity] == 0) newCargo.remove(commodity);

    final transactionValue = price * amount;
    final ownerFee = port.isOwned && !_isOwner
        ? (transactionValue * port.ownerTaxRate).round()
        : 0;

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    onPortUpdated(port.copyWith(
      demand: <String, int>{
        ...port.demand,
        commodity: _remainingDemand(commodity) - amount,
      },
      portCredits:
          (port.portCredits - transactionValue).clamp(0, double.infinity),
      accumulatedRevenue: port.accumulatedRevenue + ownerFee,
      lastRegenTime: nowMs,
    ));

    onPlayerUpdate(_withTradeReputation(player.copyWith(
      cargo: newCargo,
      cargoUsed: player.cargoUsed - amount,
      credits: player.credits + transactionValue - ownerFee,
    )));
  }

  Player _withTradeReputation(Player updated) {
    final ownerFaction = port.ownerFaction;
    if (ownerFaction == null) return updated;
    return updated.withFactionStandingChange(ownerFaction, 1);
  }

  @override
  Widget build(BuildContext context) {
    const mono = 'monospace';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: EdgeInsets.all(UiScale.spacing(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _headerBar(theme, cs),
          SizedBox(height: UiScale.spacing(10)),
          _statsStrip(cs, mono),
          SizedBox(height: UiScale.spacing(20)),
          _sectionLabel(cs, 'TRADE'),
          SizedBox(height: UiScale.spacing(6)),
          _tradeTable(cs, mono),
          SizedBox(height: UiScale.spacing(24)),
          _sectionLabel(cs, 'EXTRAS'),
          SizedBox(height: UiScale.spacing(6)),
          LotteryWidget(player: player, onPlayerUpdate: onPlayerUpdate),
          SizedBox(height: UiScale.spacing(8)),
          _extrasSection(context, cs),
        ],
      ),
    );
  }

  Widget _sectionLabel(ColorScheme cs, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 1,
        color: cs.onSurface.withValues(alpha: 0.5),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Header
  // ---------------------------------------------------------------------

  Widget _headerBar(ThemeData theme, ColorScheme cs) {
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: 14, vertical: UiScale.spacing(12)),
      decoration: BoxDecoration(
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.store_rounded, size: 22, color: cs.tertiary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        port.name,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (port.portType != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        port.portType!,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                    const SizedBox(width: 6),
                    HudPill(
                      text: (_portClassLabels[port.portClass] ?? 'unknown')
                          .toLowerCase(),
                      background: cs.onSurface.withValues(alpha: 0.06),
                      foreground: cs.onSurface.withValues(alpha: 0.6),
                    ),
                    if (port.ownerFaction != null) ...[
                      const SizedBox(width: 6),
                      HudPill(
                        text: port.ownerFaction!.displayName.toLowerCase(),
                        background: factionColor(port.ownerFaction!)
                            .withValues(alpha: 0.15),
                        foreground: factionColor(port.ownerFaction!),
                        bold: true,
                      ),
                    ],
                    if (port.isSecurityCompromised) ...[
                      const SizedBox(width: 6),
                      HudPill(
                        text: 'sabotaged',
                        background: Colors.orange.withValues(alpha: 0.15),
                        foreground: Colors.orange,
                        bold: true,
                      ),
                    ],
                  ],
                ),
                if (port.owner != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'owner: ${port.owner}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 6),
            child: _headerButton(
              icon: Icons.menu_book_rounded,
              label: 'Codex',
              color: cs.primary,
              onPressed: onOpenHackCodex,
            ),
          ),
          if (port.portClass != PortClass.federal &&
              !player.ownsPort(port.name))
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _headerButton(
                icon: Icons.shopping_cart_rounded,
                label: 'Buy port',
                color: cs.primary,
                onPressed: onBuyPort,
              ),
            ),
          if (!Port.isInSafeZone(player.currentSectorId) &&
              !player.ownsPort(port.name) &&
              port.defenseLevel > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: _headerButton(
                icon: Icons.local_fire_department_rounded,
                label: 'Attack',
                color: Colors.red.shade400,
                onPressed: onAttackPort,
              ),
            ),
        ],
      ),
    );
  }

  Widget _headerButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: const Size(0, 28),
        side: BorderSide(color: color.withValues(alpha: 0.4)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Stats strip
  // ---------------------------------------------------------------------

  Widget _statsStrip(ColorScheme cs, String mono) {
    final ratio = port.cashRatio;
    final pct = (ratio * 100).round();
    final cashColor = ratio < 0.7
        ? Colors.deepOrange
        : ratio < 1.3
            ? Colors.green
            : Colors.amber;
    final cashLabel = ratio < 0.7
        ? 'distressed'
        : ratio < 1.3
            ? 'healthy'
            : 'flush';

    final chips = <(String, String, Color?)>[
      ('credits', '${player.credits}', null),
      ('cargo', '${player.cargoUsed}/${player.maxCargo}', null),
      ('energy', '${player.energy}/${player.maxEnergy}', null),
      ('net worth', _formatCredits(port.netWorth), null),
      ('defense', '${port.defenseLevel}/4', null),
      ('cash', '$pct% $cashLabel', cashColor.shade300),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: EdgeInsets.symmetric(vertical: UiScale.spacing(10)),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0)
              SizedBox(
                height: 28,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: cs.onSurface.withValues(alpha: 0.1),
                ),
              ),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    chips[i].$1,
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    chips[i].$2,
                    style: TextStyle(
                      fontFamily: mono,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: chips[i].$3 ?? cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Trade table
  // ---------------------------------------------------------------------

  Widget _tradeTable(ColorScheme cs, String mono) {
    final cashRatio = port.cashRatio;
    final showPricingNote = (cashRatio - 1.0).abs() > 0.15;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPricingNote || _ownerFeeRate > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                if (showPricingNote)
                  _noteChip(
                    cashRatio < 0.85
                        ? Icons.local_fire_department_rounded
                        : Icons.trending_up_rounded,
                    cashRatio < 0.85
                        ? 'Distressed pricing active'
                        : 'Premium pricing active',
                    cashRatio < 0.85
                        ? Colors.deepOrange.shade300
                        : Colors.amber.shade300,
                  ),
                if (_ownerFeeRate > 0)
                  _noteChip(
                    Icons.account_balance_wallet_rounded,
                    'Includes ${(_ownerFeeRate * 100).round()}% owner fee',
                    Colors.amber.shade400,
                  ),
              ],
            ),
          ),
        DataTableShell(
          zebra: true,
          headers: const [
            'commodity',
            'buy',
            'sell',
            'supply/dem',
            'hold',
            'actions'
          ],
          flexes: const [3, 1, 1, 2, 1, 3],
          headerAlignments: const [
            null,
            null,
            null,
            null,
            null,
            TextAlign.right
          ],
          itemCount: _commodities.length,
          rowBuilder: (context, i) => _tradeRow(cs, mono, _commodities[i]),
        ),
      ],
    );
  }

  Widget _noteChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _tradeRow(ColorScheme cs, String mono, String commodity) {
    final buyPrice = port.getEffectiveBuyPrice(commodity);
    final sellPrice = port.getEffectiveSellPrice(commodity);
    final icon = _commodityIcons[commodity] ?? Icons.shopping_cart_rounded;
    final label = _commodityLabels[commodity] ?? commodity;
    final amount = _playerAmount(commodity);
    final remainingSupply = _remainingSupply(commodity);
    final remainingDemand = _remainingDemand(commodity);

    String supplyDemandText;
    Color supplyDemandColor;
    if (port.sells(commodity)) {
      supplyDemandText = 'S $remainingSupply';
      supplyDemandColor =
          remainingSupply > 0 ? cs.onSurface.withValues(alpha: 0.6) : cs.error;
    } else if (port.buys(commodity)) {
      supplyDemandText = 'D $remainingDemand';
      supplyDemandColor =
          remainingDemand > 0 ? cs.onSurface.withValues(alpha: 0.6) : cs.error;
    } else {
      supplyDemandText = '—';
      supplyDemandColor = cs.onSurface.withValues(alpha: 0.4);
    }

    return Padding(
      padding:
          EdgeInsets.symmetric(horizontal: 10, vertical: UiScale.spacing(6)),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Icon(icon, size: 15, color: cs.primary),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              sellPrice > 0 ? sellPrice.toInt().toString() : '—',
              style: TextStyle(
                fontFamily: mono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sellPrice > 0
                    ? cs.error
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              buyPrice > 0 ? buyPrice.toInt().toString() : '—',
              style: TextStyle(
                fontFamily: mono,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: buyPrice > 0
                    ? Colors.green
                    : cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              supplyDemandText,
              style: TextStyle(
                  fontFamily: mono, fontSize: 12, color: supplyDemandColor),
            ),
          ),
          Expanded(
            flex: 1,
            child: Text(
              '$amount',
              style: TextStyle(
                fontFamily: mono,
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Row(
              children: [
                Expanded(
                  child: HoldButton(
                    enabled: _canSell(commodity),
                    onPressed: () => _sell(commodity),
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                    label: 'sell',
                    height: 28,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: HoldButton(
                    enabled: _canBuy(commodity),
                    onPressed: () => _buy(commodity),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    label: 'buy',
                    height: 28,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Extras
  // ---------------------------------------------------------------------

  Widget _extrasSection(BuildContext context, ColorScheme cs) {
    final isBanned = hackFailCount >= maxHackAttempts;
    final ownsThisPort = player.ownsPort(port.name);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _extrasRow(
            icon: isBanned ? Icons.block_rounded : Icons.security_rounded,
            iconColor: isBanned ? Colors.grey : cs.error,
            title: isBanned ? 'Port banned' : 'Hack port',
            trailing: isBanned
                ? _LiveBanCountdown(
                    banUntilEpoch: hackBannedUntilEpoch ??
                        player.portHackBannedUntil[port.name],
                    onExpired: onBanExpired,
                    color: cs.error.withValues(alpha: 0.6),
                  )
                : Text(
                    '${maxHackAttempts - hackFailCount}/$maxHackAttempts attempts',
                    style: TextStyle(
                      fontSize: 11,
                      color: cs.error.withValues(alpha: 0.6),
                    ),
                  ),
            trailingColor: cs.error.withValues(alpha: 0.6),
            onTap: isBanned ? null : onHackPort,
            showDivider: true,
          ),
          _extrasRow(
            icon: Icons.flash_on_rounded,
            iconColor: Colors.orange,
            title: 'Steal resources',
            trailing: const Text(
              'jam security freq',
              style: TextStyle(fontSize: 11),
            ),
            trailingColor: Colors.orange.withValues(alpha: 0.6),
            onTap: onStealResources,
            showDivider: ownsThisPort,
          ),
          if (ownsThisPort)
            _extrasRow(
              icon: Icons.admin_panel_settings_rounded,
              iconColor: cs.primary,
              title: 'Port management',
              trailing: null,
              trailingColor: null,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PortManagementScreen(
                      port: port,
                      player: player,
                      onPlayerUpdate: onPlayerUpdate,
                      onPortUpdated: onPortUpdated,
                    ),
                  ),
                );
              },
              showDivider: false,
            ),
        ],
      ),
    );
  }

  Widget _extrasRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required Widget? trailing,
    required Color? trailingColor,
    required VoidCallback? onTap,
    required bool showDivider,
  }) {
    final disabled = onTap == null;
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: 12, vertical: UiScale.spacing(11)),
            child: Row(
              children: [
                Icon(icon, size: 18, color: disabled ? Colors.grey : iconColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: disabled ? Colors.grey : null,
                    ),
                  ),
                ),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: trailing,
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: Colors.grey.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(
              height: 1,
              thickness: 1,
              color: Colors.grey.withValues(alpha: 0.15)),
      ],
    );
  }
}

class _LiveBanCountdown extends StatefulWidget {
  const _LiveBanCountdown({
    required this.banUntilEpoch,
    required this.color,
    this.onExpired,
  });

  final int? banUntilEpoch;
  final Color color;
  final VoidCallback? onExpired;

  @override
  State<_LiveBanCountdown> createState() => _LiveBanCountdownState();
}

class _LiveBanCountdownState extends State<_LiveBanCountdown> {
  Timer? _timer;
  bool _didNotify = false;

  Duration get _remaining {
    final until = widget.banUntilEpoch;
    if (until == null) return Duration.zero;
    final value = until - DateTime.now().millisecondsSinceEpoch;
    return value > 0 ? Duration(milliseconds: value) : Duration.zero;
  }

  String get _formatted {
    final remaining = _remaining;
    final hours = remaining.inHours.toString().padLeft(2, '0');
    final minutes = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remaining == Duration.zero) {
        _timer?.cancel();
        _timer = null;
        if (!_didNotify) {
          _didNotify = true;
          widget.onExpired?.call();
        }
        setState(() {});
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatted,
      style: TextStyle(
        fontFamily: 'monospace',
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: widget.color,
      ),
    );
  }
}
