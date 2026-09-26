import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/widgets/shared/data_table_shell.dart';
import 'package:cosmic_trader/widgets/shared/panel_card.dart';

/// Computer → Bounty Board (B4).
///
/// Anyone may post (players pay on post; NPC survivors post from their own
/// bankroll when attacked). NPC kills pay the killer instantly; player
/// kills record the victim id and pay out through the Claim action here.
class BountyBoardScreen extends StatefulWidget {
  const BountyBoardScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
    required this.onBack,
  });

  final Player player;
  final Function(Player) onPlayerUpdate;
  final VoidCallback onBack;

  @override
  State<BountyBoardScreen> createState() => _BountyBoardScreenState();
}

class _BountyBoardScreenState extends State<BountyBoardScreen> {
  List<NpcShip> _npcs = [];
  NpcShip? _target;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  String? _formError;

  @override
  void initState() {
    super.initState();
    BountyBoard.global.ensureLoaded();
    _loadNpcs();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadNpcs() async {
    try {
      final npcs = await NpcStorage().loadAll();
      if (mounted) {
        setState(() {
          _npcs = npcs.where((n) => !n.isDestroyed).toList();
        });
      }
    } catch (_) {}
  }

  void _post() {
    final amount = int.tryParse(_amountController.text) ?? 0;
    final target = _target;
    if (target == null) {
      setState(() => _formError = 'Pick a target.');
      return;
    }
    if (amount <= 0) {
      setState(() => _formError = 'Amount must be positive.');
      return;
    }
    if (amount > widget.player.credits) {
      setState(() => _formError = 'Cannot cover $amount cr.');
      return;
    }
    final reason = _reasonController.text.trim();
    // Debit FIRST, then post: post() is infallible for validated amounts,
    // so the bounty can never exist unpaid-for. (Reverse order created
    // money from nothing if anything interrupted between the lines.)
    widget.onPlayerUpdate(
      widget.player.copyWith(credits: widget.player.credits - amount),
    );
    final posted = BountyBoard.global.post(
      targetId: target.id,
      targetName: target.pilotName,
      targetFaction: target.faction.name,
      amount: amount,
      posterId: widget.player.id,
      posterName: widget.player.name,
      posterFaction: widget.player.faction.name,
      reason: reason.isEmpty ? 'player contract' : reason,
    );
    if (posted == null) {
      // Practically unreachable (amount validated above): refund so the
      // books always balance.
      widget.onPlayerUpdate(
        widget.player.copyWith(credits: widget.player.credits + amount),
      );
      setState(() => _formError = 'Post failed — refunded.');
      return;
    }
    _amountController.clear();
    _reasonController.clear();
    setState(() {
      _target = null;
      _formError = null;
    });
  }

  void _claim(String targetId, String targetName) {
    final factions = BountyBoard.global.posterFactionsFor(targetId);
    final paid = BountyBoard.global.claim(
      targetId: targetId,
      targetName: targetName,
      killerName: widget.player.name,
      verifiedKills: widget.player.recentKills.toSet(),
    );
    if (paid <= 0) return;
    var updated = widget.player.copyWith(credits: widget.player.credits + paid);
    for (final faction in factions) {
      for (final value in FactionClass.values) {
        if (value.name == faction) {
          updated = updated.withFactionStandingChange(value, 5);
        }
      }
    }
    widget.onPlayerUpdate(updated);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Claimed $paid cr for $targetName')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Bounty Board'),
      ),
      body: ListenableBuilder(
        listenable: BountyBoard.global,
        builder: (context, _) {
          final board = BountyBoard.global;
          final kills = widget.player.recentKills.toSet();
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelCard(
                  icon: Icons.crisis_alert_rounded,
                  title: 'Active bounties (${board.active.length})',
                  subtitle: 'Claim pays out for pilots you destroyed',
                  children: [
                    if (board.active.isEmpty)
                      Text(
                        'No open contracts. Survive an attack or post one.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    else
                      DataTableShell(
                        zebra: true,
                        headers: const [
                          'Target',
                          'Faction',
                          'Amount',
                          '',
                        ],
                        flexes: const [2, 1, 1, 1],
                        itemCount: board.active.length,
                        rowBuilder: (context, i) {
                          final b = board.active[i];
                          final claimable = kills.contains(b.targetId);
                          return Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(b.targetName,
                                        style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600)),
                                    Text(
                                      '${b.posterName}${b.reason.isNotEmpty ? ' · ${b.reason}' : ''}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color:
                                            cs.onSurface.withValues(alpha: 0.5),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                  child: Text(b.targetFaction,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                  child: Text('${b.amount}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                              Expanded(
                                child: claimable
                                    ? TextButton(
                                        onPressed: () =>
                                            _claim(b.targetId, b.targetName),
                                        child: const Text('Claim',
                                            style: TextStyle(fontSize: 12)),
                                      )
                                    : const Text('—',
                                        style: TextStyle(fontSize: 12)),
                              ),
                            ],
                          );
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                PanelCard(
                  icon: Icons.add_alert_rounded,
                  title: 'Post a bounty',
                  subtitle: 'Credits leave your account on post',
                  children: [
                    Autocomplete<NpcShip>(
                      displayStringForOption: (n) =>
                          '${n.pilotName} (${n.faction.name})',
                      optionsBuilder: (query) {
                        final needle = query.text.trim().toLowerCase();
                        if (needle.isEmpty) {
                          return _npcs.take(15);
                        }
                        return _npcs.where((n) =>
                            n.pilotName.toLowerCase().contains(needle) ||
                            n.shipName.toLowerCase().contains(needle) ||
                            n.faction.name.contains(needle));
                      },
                      onSelected: (n) => setState(() => _target = n),
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) {
                        if (controller.text.isEmpty && _target != null) {
                          controller.text =
                              '${_target!.pilotName} (${_target!.faction.name})';
                        }
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Target pilot — type to search',
                            prefixIcon: Icon(Icons.search_rounded),
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          onChanged: (_) {
                            if (_target != null) {
                              setState(() => _target = null);
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText:
                            'Amount (you hold ${widget.player.credits} cr)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        errorText: _formError,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reasonController,
                      maxLength: 60,
                      decoration: const InputDecoration(
                        labelText: 'Reason (optional, short)',
                        border: OutlineInputBorder(),
                        isDense: true,
                        counterText: '',
                      ),
                    ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _post,
                      icon: const Icon(Icons.send_rounded, size: 16),
                      label: const Text('Post bounty'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (board.paid.isNotEmpty)
                  PanelCard(
                    icon: Icons.history_rounded,
                    title: 'Recently paid (${board.paid.length})',
                    children: [
                      DataTableShell(
                        headers: const ['Target', 'Killer', 'Amount'],
                        flexes: const [2, 2, 1],
                        itemCount: board.paid.length,
                        rowBuilder: (context, i) {
                          final p = board.paid[i];
                          return Row(
                            children: [
                              Expanded(
                                  flex: 2,
                                  child: Text(p.targetName,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                  flex: 2,
                                  child: Text(p.killerName,
                                      style: const TextStyle(fontSize: 12))),
                              Expanded(
                                  child: Text('${p.amount}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontFamily: 'monospace'))),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
