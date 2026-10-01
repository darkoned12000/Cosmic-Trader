import 'package:cosmic_trader/services/game_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'package:cosmic_trader/widgets/avatar/npc_portrait.dart';
import 'package:cosmic_trader/widgets/shared/data_table_shell.dart';
import 'package:cosmic_trader/widgets/shared/panel_card.dart';
import 'package:cosmic_trader/core/number_format.dart';

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

  /// Roster indexed by id, for drawing a face on a bounty target.
  ///
  /// A bounty only stores a `targetId` and a name, so a portrait needs the ship
  /// back. A target that has been destroyed, or that is somehow not in the
  /// roster, simply gets no portrait — the card is still fully usable without
  /// one, so a missing face must never be an error state.
  Map<String, NpcShip> _npcById = const {};

  NpcShip? _target;
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();
  // Autocomplete-owned search field (cleared on post, never disposed here).
  TextEditingController? _targetField;
  String? _formError;
  bool _claimableOnly = false;
  FactionClass? _factionFilter;

  /// Compact age for bounty rows (bounty review L1).
  static String _age(int createdAtTick) {
    final mins =
        GameClock.periodsSince(createdAtTick, GameClock.ticksPerMinute);
    if (mins < 1) return 'now';
    if (mins < 60) return '${mins}m';
    final hours = mins ~/ 60;
    if (hours < 48) return '${hours}h';
    return '${hours ~/ 24}d';
  }

  /// Countdown to escrow expiry (future-aware sibling of [_age]).
  static String _expiresIn(int expiresAtTick) {
    final mins =
        -GameClock.periodsSince(expiresAtTick, GameClock.ticksPerMinute);
    if (mins < 1) return 'expiring';
    if (mins < 60) return '${mins}m left';
    final hours = mins ~/ 60;
    if (hours < 48) return '${hours}h left';
    return '${hours ~/ 24}d left';
  }

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
          _npcById = {for (final n in _npcs) n.id: n};
        });
      }
    } catch (e) {
      // Never silent (repo convention): an empty target list with no
      // explanation looks like "no bounties work".
      debugPrint('[BountyBoardScreen] NPC load failed: $e');
    }
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
    _targetField?.clear();
    setState(() {
      _target = null;
      _formError = null;
    });
  }

  /// Faction color for a stored faction name (enum names on bounties),
  /// or null when unknown (Federation posters, legacy rows) so the
  /// default text style applies.
  Color? _factionColorOf(String name) {
    for (final value in FactionClass.values) {
      if (value.name == name) return factionColor(value);
    }
    return null;
  }

  /// Collects this pilot's lapsed escrow (expired/pruned/evicted marks
  /// refund their debited posts; house-minted marks evaporate instead).
  void _collectRefund() {
    final amount = BountyBoard.global.takeRefund(widget.player.id);
    if (amount <= 0) return;
    widget.onPlayerUpdate(
      widget.player.copyWith(credits: widget.player.credits + amount),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Collected $amount cr lapsed escrow')),
      );
    }
  }

  void _claim(String targetId, String targetName) {
    // H3 guard: self-posted marks pay out (money was debited at post)
    // but never mint reputation.
    final factions = BountyBoard.global
        .posterFactionsFor(targetId, excludePosterId: widget.player.id);
    final targets =
        BountyBoard.global.active.where((b) => b.targetId == targetId);
    final paid = BountyBoard.global.claim(
      targetId: targetId,
      targetName: targetName,
      killerName: widget.player.name,
      verifiedKills: widget.player.recentKills.toSet(),
      killerFaction: widget.player.faction.name,
      targetFaction: targets.isEmpty ? '' : targets.first.targetFaction,
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

  /// One grouped target card: colored name, stacked total, per-poster
  /// breakdown, single Claim. Claimable marks get the button; the rest
  /// show the nearest expiry.
  Widget _targetCard(BuildContext context, ColorScheme cs, BountyBoard board,
      Set<String> kills, BountyTargetGroup g) {
    final claimable = kills.contains(g.targetId);
    // `min`, not `reduce`: the old form needed a comparator that compared two
    // `DateTime`s by `.isBefore`, which cannot be lifted to a `min` on ticks.
    // Taking the min of the ticks is the same answer with less ceremony.
    final soonest =
        g.marks.map((b) => b.expiresAtTick).reduce((a, b) => a < b ? a : b);
    final targetNpc = _npcById[g.targetId];
    // A mark can be posted on a **player** — the Federation does exactly that
    // from a pilot's alignment — and a player is not in the NPC roster, so
    // resolving the face purely from `_npcById` left the one row the player is
    // most likely to be looking at as the only one without a face on the board.
    // It read as a rendering fault rather than as a fact about the target.
    final isPlayerTarget = g.targetId == widget.player.id;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
      ),
      child: ExpansionTile(
        dense: true,
        // A face when the target is still in the roster; nothing when it is not.
        leading: targetNpc != null
            ? AvatarPortraitView(
                portrait: NpcPortraits.of(targetNpc),
                size: 40,
              )
            : isPlayerTarget
                ? AvatarCanvas(
                    selection: widget.player.effectiveAvatar,
                    size: 40,
                  )
                : null,
        title: Row(
          children: [
            Expanded(
              child: Text(
                g.targetName,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _factionColorOf(g.targetFaction),
                ),
              ),
            ),
            Text(
              grouped(g.total),
              style: const TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
        subtitle: Text(
          '${g.targetFaction} · ${g.marks.length} mark${g.marks.length == 1 ? '' : 's'} · exp ${_expiresIn(soonest)}',
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: claimable
            ? TextButton(
                onPressed: () => _claim(g.targetId, g.targetName),
                child: const Text('Claim', style: TextStyle(fontSize: 12)),
              )
            : null,
        children: [
          for (final b in g.marks)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${b.posterName}${b.reason.isNotEmpty ? ' · ${b.reason}' : ''} · ${_age(b.createdAtTick)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: _factionColorOf(b.posterFaction) ??
                            cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  Text(
                    grouped(b.amount),
                    style:
                        const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
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
          // Grouped richest-first (grouped-view rev); filters apply on
          // top: claimable-only toggle + faction chips.
          var groups = board.groupedTargets();
          if (_claimableOnly) {
            groups = groups.where((g) => kills.contains(g.targetId)).toList();
          }
          if (_factionFilter != null) {
            groups = groups
                .where((g) => g.targetFaction == _factionFilter!.name)
                .toList();
          }
          final markCount = groups.fold(0, (a, g) => a + g.marks.length);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PanelCard(
                  icon: Icons.crisis_alert_rounded,
                  title:
                      'Active bounties ($markCount marks · ${groups.length} targets)',
                  subtitle: 'Claim pays out for pilots you destroyed',
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        FilterChip(
                          label: const Text('Claimable',
                              style: TextStyle(fontSize: 12)),
                          selected: _claimableOnly,
                          onSelected: (v) => setState(() => _claimableOnly = v),
                        ),
                        ChoiceChip(
                          label:
                              const Text('All', style: TextStyle(fontSize: 12)),
                          selected: _factionFilter == null,
                          onSelected: (_) =>
                              setState(() => _factionFilter = null),
                        ),
                        for (final f in FactionClass.values)
                          ChoiceChip(
                            label: Text(f.name,
                                style: const TextStyle(fontSize: 12)),
                            selected: _factionFilter == f,
                            onSelected: (_) =>
                                setState(() => _factionFilter = f),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (groups.isEmpty)
                      Text(
                        _claimableOnly || _factionFilter != null
                            ? 'No contracts match these filters.'
                            : 'No open contracts. Survive an attack or post one.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    else
                      for (final g in groups)
                        _targetCard(context, cs, board, kills, g),
                  ],
                ),
                const SizedBox(height: 12),
                if (board.pendingRefundFor(widget.player.id) > 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: OutlinedButton.icon(
                      onPressed: _collectRefund,
                      icon: const Icon(Icons.savings_rounded, size: 16),
                      label: Text(
                        'Collect ${grouped(board.pendingRefundFor(widget.player.id))} cr lapsed escrow',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
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
                        _targetField = controller;
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
                    title: 'Recently paid (${board.paid.length} shown · '
                        '${board.paidLifetime} lifetime)',
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
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _factionColorOf(
                                              p.targetFaction)))),
                              Expanded(
                                  flex: 2,
                                  child: Text(p.killerName,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: _factionColorOf(
                                              p.killerFaction)))),
                              Expanded(
                                  child: Text(grouped(p.amount),
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
