import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/screens/port_management_screen.dart';
import 'package:cosmic_trader/widgets/lottery_widget.dart';
import 'package:cosmic_trader/widgets/hold_button.dart';

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
  final int hackFailCount;
  final int maxHackAttempts;

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
    required this.hackFailCount,
    required this.maxHackAttempts,
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

    onPlayerUpdate(player.copyWith(
      cargo: newCargo,
      cargoUsed: player.cargoUsed + amount,
      credits: player.credits - transactionValue - ownerFee,
    ));
  }

  void _sell(String commodity) {
    final price = port.getEffectiveBuyPrice(commodity).toInt();
    if (price <= 0) return;
    final currentQty = player.cargo[commodity] ?? 0;
    if (currentQty <= 0) return;
    if (_remainingDemand(commodity) <= 0) return;

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

    onPlayerUpdate(player.copyWith(
      cargo: newCargo,
      cargoUsed: player.cargoUsed - amount,
      credits: player.credits + transactionValue - ownerFee,
    ));
  }

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
                    _pill(
                      (_portClassLabels[port.portClass] ?? 'unknown')
                          .toLowerCase(),
                      cs.onSurface.withValues(alpha: 0.06),
                      cs.onSurface.withValues(alpha: 0.6),
                    ),
                    if (port.ownerFaction != null) ...[
                      const SizedBox(width: 6),
                      _pill(
                        port.ownerFaction!.displayName.toLowerCase(),
                        _factionColor(port.ownerFaction!)
                            .withValues(alpha: 0.15),
                        _factionColor(port.ownerFaction!),
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

  Widget _pill(String text, Color bg, Color fg, {bool bold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          color: fg,
        ),
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
      ('turns', '${player.turns}/${player.maxTurns}', null),
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
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Container(
                color: cs.onSurface.withValues(alpha: 0.04),
                padding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: UiScale.spacing(8)),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _colHeader(cs, 'commodity')),
                    Expanded(flex: 1, child: _colHeader(cs, 'buy')),
                    Expanded(flex: 1, child: _colHeader(cs, 'sell')),
                    Expanded(flex: 2, child: _colHeader(cs, 'supply/dem')),
                    Expanded(flex: 1, child: _colHeader(cs, 'hold')),
                    Expanded(
                      flex: 3,
                      child: _colHeader(cs, 'actions', align: TextAlign.right),
                    ),
                  ],
                ),
              ),
              for (var i = 0; i < _commodities.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: cs.onSurface.withValues(alpha: 0.08),
                  ),
                _tradeRow(cs, mono, _commodities[i]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _colHeader(ColorScheme cs, String text, {TextAlign? align}) {
    return Text(
      text,
      textAlign: align ?? TextAlign.left,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
        color: cs.onSurface.withValues(alpha: 0.45),
      ),
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
                ? 'blocked 24h'
                : '${maxHackAttempts - hackFailCount}/$maxHackAttempts attempts',
            trailingColor: cs.error.withValues(alpha: 0.6),
            onTap: isBanned ? null : onHackPort,
            showDivider: true,
          ),
          _extrasRow(
            icon: Icons.flash_on_rounded,
            iconColor: Colors.orange,
            title: 'Steal resources',
            trailing: 'jam security freq',
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
    required String? trailing,
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
                    child: Text(
                      trailing,
                      style: TextStyle(
                        fontSize: 11,
                        color: trailingColor ?? Colors.grey,
                      ),
                    ),
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
