import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/banking_ai.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';

const Duration _interestPeriod = Duration(hours: 24);

enum _BankStage { menu, deposit, withdraw }

class BankingWidget extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const BankingWidget({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  /// Daily bank rate for [player]: base 1%, scaled by Trade Guild
  /// (trader-faction) standing — beloved clients earn up to 1.2%,
  /// blacklisted ones as little as 0.5%. Shared with NPC accrual.
  static double rateFor(Player player) =>
      BankingAi.interestRateFor(player.faction, player.factionStandings);

  @override
  State<BankingWidget> createState() => _BankingWidgetState();
}

class _BankingWidgetState extends State<BankingWidget> {
  _BankStage _stage = _BankStage.menu;
  final _amountController = TextEditingController();
  int _accountHolders = 0;
  int _totalDeposits = 0;

  @override
  void initState() {
    super.initState();
    _loadBankStats();
  }

  Future<void> _loadBankStats() async {
    try {
      final players = await PlayerStorage.instance.loadPlayers();
      final npcs = await NpcStorage().loadAll();
      if (mounted) {
        final npcDepositors = npcs.where((n) => n.bankBalance > 0);
        setState(() {
          _accountHolders = players.where((p) => p.bankBalance > 0).length +
              npcDepositors.length;
          _totalDeposits = players.fold(0, (sum, p) => sum + p.bankBalance) +
              npcs.fold(0, (sum, n) => sum + n.bankBalance);
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    switch (_stage) {
      case _BankStage.menu:
        return _buildMenu(theme, cs);
      case _BankStage.deposit:
        return _buildForm(theme, cs, 'Deposit Credits', true);
      case _BankStage.withdraw:
        return _buildForm(theme, cs, 'Withdraw Credits', false);
    }
  }

  // ---------------------------------------------------------------------------
  // Interest
  // ---------------------------------------------------------------------------

  int _calculateInterest() {
    final lastTime = widget.player.lastInterestTime;
    if (lastTime == null) return 0;

    final elapsed = DateTime.now().difference(lastTime);
    if (elapsed < _interestPeriod) return 0;

    final days = elapsed.inMicroseconds / _interestPeriod.inMicroseconds;
    return (widget.player.bankBalance *
            BankingWidget.rateFor(widget.player) *
            days)
        .floor();
  }

  void _applyInterest() {
    final interest = _calculateInterest();
    if (interest > 0) {
      widget.onPlayerUpdate(widget.player.copyWith(
        bankBalance: widget.player.bankBalance + interest,
        lastInterestTime: DateTime.now(),
      ));
      GameEventLog.global.banking(
        'Interest +$interest cr @ '
        '${(BankingWidget.rateFor(widget.player) * 100).toStringAsFixed(1)}% '
        '(Trade Guild standing '
        '${widget.player.factionStandingWith(FactionClass.trader)})',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------

  Widget _buildMenu(ThemeData theme, ColorScheme cs) {
    _applyInterest();
    final player = widget.player;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.account_balance_rounded,
                    color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('Terran Galactic Bank',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Secure your credits across the galaxy.\n'
              'Earn ${(BankingWidget.rateFor(player) * 100).toStringAsFixed(1)}% interest every 24h '
              '(Trade Guild standing).',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 12),
            _infoRow(cs, Icons.account_balance_wallet_rounded, 'Bank Balance',
                '${player.bankBalance} cr'),
            _infoRow(cs, Icons.monetization_on_rounded, 'On Hand',
                '${player.credits} cr'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: player.credits > 0
                        ? () {
                            _amountController.text = player.credits.toString();
                            setState(() => _stage = _BankStage.deposit);
                          }
                        : null,
                    child: const Text('Deposit'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: player.bankBalance > 0
                        ? () {
                            _amountController.text =
                                player.bankBalance.toString();
                            setState(() => _stage = _BankStage.withdraw);
                          }
                        : null,
                    child: const Text('Withdraw'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Text('Statistics',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _infoRow(cs, Icons.trending_up_rounded, 'Your Daily Interest',
                '${(player.bankBalance * BankingWidget.rateFor(player)).floor()} cr'),
            _infoRow(cs, Icons.people_rounded, 'Bank Account Holders',
                '$_accountHolders'),
            _infoRow(cs, Icons.account_balance_rounded, 'Total Bank Deposits',
                '$_totalDeposits cr'),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Deposit / Withdraw form
  // ---------------------------------------------------------------------------

  Widget _buildForm(
      ThemeData theme, ColorScheme cs, String title, bool isDeposit) {
    final maxAmount =
        isDeposit ? widget.player.credits : widget.player.bankBalance;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(isDeposit ? Icons.login_rounded : Icons.logout_rounded,
                    color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text(title,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Amount (max: $maxAmount)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => _submitTransaction(isDeposit, maxAmount),
                    child: Text(isDeposit ? 'Deposit' : 'Withdraw'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    _amountController.clear();
                    setState(() => _stage = _BankStage.menu);
                  },
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submitTransaction(bool isDeposit, int maxAmount) {
    final amount = int.tryParse(_amountController.text) ?? 0;
    if (amount <= 0) return;

    final clamped = amount > maxAmount ? maxAmount : amount;

    if (isDeposit) {
      widget.onPlayerUpdate(widget.player.copyWith(
        credits: widget.player.credits - clamped,
        bankBalance: widget.player.bankBalance + clamped,
        lastInterestTime: widget.player.lastInterestTime ?? DateTime.now(),
      ));
    } else {
      widget.onPlayerUpdate(widget.player.copyWith(
        credits: widget.player.credits + clamped,
        bankBalance: widget.player.bankBalance - clamped,
        lastInterestTime: widget.player.lastInterestTime ?? DateTime.now(),
      ));
    }

    _amountController.clear();
    setState(() => _stage = _BankStage.menu);
    _loadBankStats();
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _infoRow(ColorScheme cs, IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: cs.onSurface.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6))),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
