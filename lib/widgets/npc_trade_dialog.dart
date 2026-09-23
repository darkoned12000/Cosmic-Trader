import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/commodity.dart';
import 'package:tradewars_2050/data/models/npc_ship.dart';
import 'package:tradewars_2050/data/models/player.dart';

class NpcTradeDialog extends StatefulWidget {
  final Player player;
  final NpcShip npc;
  final Function(Player updatedPlayer, NpcShip updatedNpc) onTradeComplete;

  const NpcTradeDialog({
    super.key,
    required this.player,
    required this.npc,
    required this.onTradeComplete,
  });

  @override
  State<NpcTradeDialog> createState() => _NpcTradeDialogState();
}

class _NpcTradeDialogState extends State<NpcTradeDialog> {
  late Map<String, int> _buyQuantities;
  late Map<String, int> _sellQuantities;

  @override
  void initState() {
    super.initState();
    _buyQuantities = {for (final c in widget.npc.cargo.keys) c: 0};
    _sellQuantities = {for (final c in widget.player.cargo.keys) c: 0};
  }

  int get _totalCost {
    int total = 0;
    for (final e in _buyQuantities.entries) {
      if (e.value > 0) {
        total += e.value * _npcSellPrice(e.key);
      }
    }
    return total;
  }

  int get _totalRevenue {
    int total = 0;
    for (final e in _sellQuantities.entries) {
      if (e.value > 0) {
        total += e.value * _npcBuyPrice(e.key);
      }
    }
    return total;
  }

  int get _netCredits => _totalRevenue - _totalCost;

  bool get _canAfford => _totalCost <= widget.player.credits;
  bool get _hasChanges =>
      _buyQuantities.values.any((v) => v > 0) ||
      _sellQuantities.values.any((v) => v > 0);

  int _npcSellPrice(String commodity) =>
      ((CommodityRegistry.defaultsMap[commodity]?.splitPoint ?? 15) * 1.2)
          .round();

  int _npcBuyPrice(String commodity) =>
      ((CommodityRegistry.defaultsMap[commodity]?.splitPoint ?? 15) * 0.8)
          .round();

  void _confirm() {
    final player = widget.player;
    final npc = widget.npc;

    final newPlayerCargo = Map<String, int>.from(player.cargo);
    final newNpcCargo = Map<String, int>.from(npc.cargo);

    // Player buys from NPC
    for (final e in _buyQuantities.entries) {
      if (e.value <= 0) continue;
      newPlayerCargo[e.key] = (newPlayerCargo[e.key] ?? 0) + e.value;
      newNpcCargo[e.key] = (newNpcCargo[e.key] ?? 0) - e.value;
      if (newNpcCargo[e.key]! <= 0) newNpcCargo.remove(e.key);
    }

    // Player sells to NPC
    for (final e in _sellQuantities.entries) {
      if (e.value <= 0) continue;
      newPlayerCargo[e.key] = (newPlayerCargo[e.key] ?? 0) - e.value;
      if (newPlayerCargo[e.key]! <= 0) newPlayerCargo.remove(e.key);
      newNpcCargo[e.key] = (newNpcCargo[e.key] ?? 0) + e.value;
    }

    final playerCargoUsed = newPlayerCargo.values.fold(0, (a, b) => a + b);
    final npcCargoUsed = newNpcCargo.values.fold(0, (a, b) => a + b);

    final netChange = _netCredits;
    final updatedPlayer = player.copyWith(
      credits: (player.credits + netChange).clamp(0, 9999999),
      cargo: newPlayerCargo,
      cargoUsed: playerCargoUsed.clamp(0, player.maxCargo),
    );

    final updatedNpc = npc.copyWith(
      credits: (npc.credits - netChange).clamp(0, 9999999),
      cargo: newNpcCargo,
      cargoUsed: npcCargoUsed.clamp(0, 999),
    );

    widget.onTradeComplete(updatedPlayer, updatedNpc);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bothCommodities = <String>{
      ...widget.npc.cargo.keys,
      ...widget.player.cargo.keys,
    };

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.shopping_cart_rounded, color: cs.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'TRADE — ${widget.npc.shipName}',
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Player credits display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.monetization_on_rounded,
                      size: 16, color: Colors.green.shade300),
                  const SizedBox(width: 8),
                  Text(
                    'Your credits: ${widget.player.credits} cr',
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Commodity rows
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                              color: cs.outline.withValues(alpha: 0.3)),
                        ),
                      ),
                      child: Row(
                        children: [
                          const SizedBox(
                              width: 70,
                              child: Text('Item',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold))),
                          const Expanded(
                              child: Text('NPC has',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center)),
                          const Expanded(
                              child: Text('You have',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center)),
                          const SizedBox(
                              width: 80,
                              child: Text('Buy↓ / Sell↑',
                                  style: TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center)),
                        ],
                      ),
                    ),
                    for (final commodity in bothCommodities) ...[
                      _commodityRow(commodity, cs),
                      const Divider(height: 1),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Summary
            if (_hasChanges)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    if (_totalCost > 0)
                      _summaryRow(
                          'Buying:', '-$_totalCost cr', Colors.red.shade300),
                    if (_totalRevenue > 0)
                      _summaryRow('Selling:', '+$_totalRevenue cr',
                          Colors.green.shade300),
                    Divider(color: cs.outline.withValues(alpha: 0.3)),
                    _summaryRow(
                      'Net:',
                      '${_netCredits >= 0 ? '+' : ''}$_netCredits cr',
                      _netCredits >= 0
                          ? Colors.green.shade300
                          : Colors.red.shade300,
                    ),
                    if (!_canAfford && _totalCost > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'Not enough credits!',
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _hasChanges && _canAfford ? _confirm : null,
          child: const Text('Confirm Trade'),
        ),
      ],
    );
  }

  Widget _commodityRow(String commodity, ColorScheme cs) {
    final npcHas = widget.npc.cargo[commodity] ?? 0;
    final playerHas = widget.player.cargo[commodity] ?? 0;
    final buyQty = _buyQuantities[commodity] ?? 0;
    final sellQty = _sellQuantities[commodity] ?? 0;
    final buyPrice = _npcSellPrice(commodity);
    final availableHolds = widget.player.maxCargo -
        widget.player.cargoUsed -
        (_buyQuantities.values.fold(0, (a, b) => a + b) -
            _sellQuantities.values.fold(0, (a, b) => a + b));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              commodity.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
            ),
          ),
          Expanded(
            child: Text(
              '$npcHas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: npcHas > 0 ? Colors.white : Colors.white38,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$playerHas',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: playerHas > 0 ? Colors.white : Colors.white38,
              ),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Buy from NPC (player buys what NPC has)
                if (npcHas > 0 && npcHas > buyQty)
                  _stepperButton(Icons.remove, () {
                    if (buyQty > 0) {
                      setState(() => _buyQuantities[commodity] = buyQty - 1);
                    }
                  }),
                if (npcHas > 0)
                  Text(
                    buyQty > 0 ? '$buyQty↑' : '',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.green.shade300,
                    ),
                  ),
                if (npcHas > 0 &&
                    widget.player.credits >= buyPrice &&
                    availableHolds > 0)
                  _stepperButton(Icons.add, () {
                    if (buyQty < npcHas) {
                      setState(() => _buyQuantities[commodity] = buyQty + 1);
                    }
                  }),
                // Sell to NPC (player sells what player has)
                if (playerHas > 0 && playerHas > sellQty)
                  _stepperButton(Icons.remove, () {
                    if (sellQty > 0) {
                      setState(() => _sellQuantities[commodity] = sellQty - 1);
                    }
                  }),
                if (playerHas > 0)
                  Text(
                    sellQty > 0 ? '$sellQty↓' : '',
                    style: TextStyle(
                      fontSize: 11,
                      fontFamily: 'monospace',
                      color: Colors.red.shade300,
                    ),
                  ),
                if (playerHas > 0 && playerHas > sellQty)
                  _stepperButton(Icons.add, () {
                    if (sellQty < playerHas) {
                      setState(() => _sellQuantities[commodity] = sellQty + 1);
                    }
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(icon, size: 12, color: Colors.white70),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
