import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/services/audio_service.dart';

enum _LotteryStage { menu, picking, drawing, results }

const int _ticketCost = 2500;
const int _maxPlaysPerPeriod = 3;
const Duration _periodDuration = Duration(hours: 24);
const Map<int, int> _prizeTiers = {
  0: 0,
  1: 0,
  2: 100,
  3: 10000,
  4: 50000,
  5: 200000,
  6: 10000000,
};

class LotteryWidget extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const LotteryWidget({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<LotteryWidget> createState() => _LotteryWidgetState();
}

class _LotteryWidgetState extends State<LotteryWidget> {
  _LotteryStage _stage = _LotteryStage.menu;
  final Set<String> _pickedNumbers = {};
  List<String> _drawnNumbers = [];
  List<String?> _revealedDigits = [];
  int _matches = 0;
  int _winnings = 0;
  int _playsThisPeriod = 0;
  DateTime _lastPlayTime = DateTime.now();
  Timer? _drawTimer;
  bool _exactOrder = false;

  @override
  void dispose() {
    _drawTimer?.cancel();
    super.dispose();
  }

  int get _playsLeft => _maxPlaysPerPeriod - _playsThisPeriod;

  bool get _periodElapsed =>
      DateTime.now().difference(_lastPlayTime) > _periodDuration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_periodElapsed) {
      _playsThisPeriod = 0;
      _lastPlayTime = DateTime.now();
    }

    switch (_stage) {
      case _LotteryStage.menu:
        return _buildMenu(theme, cs);
      case _LotteryStage.picking:
        return _buildPicking(theme, cs);
      case _LotteryStage.drawing:
        return _buildDrawing(theme, cs);
      case _LotteryStage.results:
        return _buildResults(theme, cs);
    }
  }

  // ---------------------------------------------------------------------------
  // Menu
  // ---------------------------------------------------------------------------

  Widget _buildMenu(ThemeData theme, ColorScheme cs) {
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
                Icon(Icons.shuffle_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('Port Lottery',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Pick 6 unique digits (0-9) and match the draw to win big!',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 8),
            _infoRow(cs, 'Ticket Cost', '$_ticketCost cr'),
            _infoRow(cs, 'Plays Left', '$_playsLeft / $_maxPlaysPerPeriod'),
            _infoRow(cs, 'Your Credits', '${widget.player.credits} cr'),
            if (_playsLeft <= 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Max plays reached. Resets in 24h.',
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.error,
                      fontWeight: FontWeight.w500),
                ),
              ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _playsLeft > 0 &&
                            widget.player.credits >= _ticketCost
                        ? () => setState(() => _stage = _LotteryStage.picking)
                        : null,
                    child: const Text('Play Lottery'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _showPrizeTiers,
                  child: const Text('Prize Tiers'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showPrizeTiers() {
    showDialog(
      context: context,
      builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return AlertDialog(
          title: const Text('Prize Tiers'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (int i = 2; i <= 6; i++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('$i Matches: ${_prizeTiers[i]!} cr'),
                ),
              const SizedBox(height: 4),
              Text('Less than 2: No prize',
                  style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
              const SizedBox(height: 8),
              Text('6 matches in exact order: 10x prize!',
                  style: TextStyle(
                      color: cs.primary, fontWeight: FontWeight.w500)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Picking
  // ---------------------------------------------------------------------------

  Widget _buildPicking(ThemeData theme, ColorScheme cs) {
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
                Icon(Icons.shuffle_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('Pick 6 Digits',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Select ${_pickedNumbers.length}/6 unique digits (0-9)',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(10, (i) {
                final digit = i.toString();
                final selected = _pickedNumbers.contains(digit);
                return ChoiceChip(
                  selected: selected,
                  label: Text(digit,
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  onSelected: (_) {
                    setState(() {
                      if (selected) {
                        _pickedNumbers.remove(digit);
                      } else if (_pickedNumbers.length < 6) {
                        _pickedNumbers.add(digit);
                      }
                    });
                  },
                );
              }),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _pickedNumbers.length == 6 ? _startDraw : null,
                    child: const Text('Confirm Numbers'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _pickedNumbers.clear();
                    _stage = _LotteryStage.menu;
                  }),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _startDraw() {
    widget.onPlayerUpdate(widget.player.copyWith(
      credits: widget.player.credits - _ticketCost,
    ));
    _playsThisPeriod++;
    _lastPlayTime = DateTime.now();

    final available = List<String>.generate(10, (i) => i.toString());
    available.shuffle();
    _drawnNumbers = available.take(6).toList();
    _revealedDigits = List.filled(6, null);
    _matches = 0;
    _winnings = 0;
    _exactOrder = false;

    setState(() => _stage = _LotteryStage.drawing);
    _revealNextDigit(0);
  }

  // ---------------------------------------------------------------------------
  // Drawing animation
  // ---------------------------------------------------------------------------

  Widget _buildDrawing(ThemeData theme, ColorScheme cs) {
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
                Icon(Icons.shuffle_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('Drawing...',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(6, (i) {
                  final digit = _revealedDigits[i];
                  final container = Container(
                    width: 36,
                    height: 44,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: digit == null
                          ? const Text('?',
                              style: TextStyle(
                                  fontSize: 20, fontWeight: FontWeight.bold))
                          : Text(digit,
                              style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: _pickedNumbers.contains(digit)
                                      ? Colors.green
                                      : cs.onSurface)),
                    ),
                  );
                  return container;
                }),
              ),
            ),
            const SizedBox(height: 16),
            if (_revealedDigits.any((d) => d == null))
              const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _revealNextDigit(int index) {
    if (index >= 6) {
      Future.delayed(const Duration(milliseconds: 500), _calculateResults);
      return;
    }

    _animateDigit(index, 0);
  }

  void _animateDigit(int index, int step) {
    const fastSteps = 20;
    const slowSteps = 5;
    final totalSteps = fastSteps + slowSteps;

    if (step >= totalSteps) {
      if (!mounted) return;
      setState(() => _revealedDigits[index] = _drawnNumbers[index]);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (mounted) _revealNextDigit(index + 1);
      });
      return;
    }

    final digit = (step % 10).toString();
    setState(() => _revealedDigits[index] = digit);

    final intervalMs = step < fastSteps ? 80 : 200;
    _drawTimer = Timer(Duration(milliseconds: intervalMs), () {
      if (mounted) _animateDigit(index, step + 1);
    });
  }

  // ---------------------------------------------------------------------------
  // Results
  // ---------------------------------------------------------------------------

  Widget _buildResults(ThemeData theme, ColorScheme cs) {
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
                Icon(Icons.emoji_events_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Text('Results',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            _resultRow(cs, 'Your Numbers', _pickedNumbers.join('  ')),
            _resultRow(cs, 'Drawn Numbers', _drawnNumbers.join('  ')),
            _resultRow(cs, 'Matches', '$_matches'),
            const SizedBox(height: 8),
            if (_winnings > 0) ...[
              Text(
                'You won $_winnings cr!',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green.shade600),
              ),
              if (_matches == 6 && _exactOrder)
                Text(
                  'PERFECT ORDER JACKPOT! 10x Prize!',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade700),
                ),
              if (_matches == 6 && !_exactOrder)
                Text(
                  'JACKPOT!',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade700),
                ),
            ] else
              Text(
                'No prize this time. Better luck next draw!',
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.5)),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                setState(() {
                  _pickedNumbers.clear();
                  _drawnNumbers = [];
                  _revealedDigits = [];
                  _stage = _LotteryStage.menu;
                });
              },
              child: const Text('Back to Menu'),
            ),
          ],
        ),
      ),
    );
  }

  void _calculateResults() {
    final userNumbers = _pickedNumbers.toList();
    var temp = List<String>.from(userNumbers);
    int matches = 0;

    for (final d in _drawnNumbers) {
      final idx = temp.indexOf(d);
      if (idx != -1) {
        matches++;
        temp.removeAt(idx);
      }
    }

    _matches = matches;
    _winnings = _prizeTiers[matches] ?? 0;
    AudioService.instance.playSfx('assets/sfx/lottery.ogg');

    _exactOrder = _pickedNumbers.join() == _drawnNumbers.join();
    if (matches == 6 && _exactOrder) {
      _winnings *= 10;
    }

    if (_winnings > 0) {
      widget.onPlayerUpdate(widget.player.copyWith(
        credits: widget.player.credits + _winnings,
      ));
    }

    if (mounted) setState(() => _stage = _LotteryStage.results);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  Widget _infoRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _resultRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const Spacer(),
          Text(value,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
