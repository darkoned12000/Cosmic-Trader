import 'dart:math';
import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/player.dart';

class HackingWidget extends StatefulWidget {
  final Player player;
  final int failCount;
  final int maxAttempts;
  final ValueChanged<Player> onSuccess;
  final ValueChanged<int> onFailure;
  final VoidCallback onCancel;

  const HackingWidget({
    super.key,
    required this.player,
    this.failCount = 0,
    this.maxAttempts = 3,
    required this.onSuccess,
    required this.onFailure,
    required this.onCancel,
  });

  @override
  State<HackingWidget> createState() => _HackingWidgetState();
}

class _HackingWidgetState extends State<HackingWidget>
    with TickerProviderStateMixin {
  late final List<int> _secret;
  final List<_GuessRow> _history = [];

  // Each element is the digit locked in for that position, or null if not yet locked
  final List<int?> _locked = [null, null, null];

  // Current guess being built (indices into _secret)
  final List<int?> _currentInput = [null, null, null];

  int _currentSlot = 0;
  int _attemptsLeft = 5;
  bool _isGameOver = false;
  bool _isSubmitting = false;
  bool _showFailureOverlay = false;
  bool _showSuccessOverlay = false;

  late AnimationController _glitchController;

  @override
  void initState() {
    super.initState();
    _secret = _generateUniqueCode();
    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
  }

  @override
  void dispose() {
    _glitchController.dispose();
    super.dispose();
  }

  static List<int> _generateUniqueCode() {
    final digits = List<int>.generate(10, (i) => i);
    digits.shuffle();
    return digits.take(3).toList();
  }

  void _onDigitPressed(int digit) {
    if (_isGameOver || _isSubmitting) return;
    if (_currentSlot >= 3) return;
    // Skip any locked positions
    while (_currentSlot < 3 && _locked[_currentSlot] != null) {
      _currentSlot++;
    }
    if (_currentSlot >= 3) return;
    setState(() {
      _currentInput[_currentSlot] = digit;
      _currentSlot++;
    });
  }

  void _onDelete() {
    if (_isGameOver || _isSubmitting) return;
    setState(() {
      if (_currentSlot > 0) {
        _currentSlot--;
        // Skip locked positions
        while (_currentSlot > 0 && _locked[_currentSlot] != null) {
          _currentSlot--;
        }
        // Only clear if the position is not locked
        if (_locked[_currentSlot] == null) {
          _currentInput[_currentSlot] = null;
        }
      }
    });
  }

  bool get _canSubmit {
    for (var i = 0; i < 3; i++) {
      if (_locked[i] == null && _currentInput[i] == null) return false;
    }
    return true;
  }

  void _submitGuess() {
    if (!_canSubmit || _isGameOver || _isSubmitting) return;
    setState(() => _isSubmitting = true);

    final guess = <int>[];
    for (var i = 0; i < 3; i++) {
      guess.add(_locked[i] ?? _currentInput[i]!);
    }

    // Build locked result after this guess
    final newLocked = List<int?>.from(_locked);
    var allMatch = true;
    for (var i = 0; i < 3; i++) {
      if (guess[i] == _secret[i]) {
        newLocked[i] = _secret[i];
      } else {
        allMatch = false;
      }
    }

    final row =
        _GuessRow(guess: List.from(guess), locked: List.from(newLocked));
    _history.add(row);

    if (allMatch) {
      _isGameOver = true;
      _glitchController.forward().then((_) {
        if (mounted) setState(() => _showSuccessOverlay = true);
      });
      setState(() => _isSubmitting = false);
      return;
    }

    _attemptsLeft--;
    if (_attemptsLeft <= 0) {
      _isGameOver = true;
      _glitchController.forward().then((_) {
        if (mounted) setState(() => _showFailureOverlay = true);
      });
      setState(() => _isSubmitting = false);
      return;
    }

    setState(() {
      for (var pos = 0; pos < 3; pos++) {
        _locked[pos] = newLocked[pos];
      }
      _currentSlot = 0;
      while (_currentSlot < 3 && _locked[_currentSlot] != null) {
        _currentSlot++;
      }
      _currentInput[0] = null;
      _currentInput[1] = null;
      _currentInput[2] = null;
      _isSubmitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Sci-fi/cyberpunk color scheme
    final hackerGreen = const Color(0xFF00FF41);
    const hackerRed = Color(0xFFFF0040);
    const hackerCyan = Color(0xFF00FFFF);
    final darkBg = cs.surface;

    return Scaffold(
      backgroundColor: darkBg,
      body: Stack(
        children: [
          // Scanline overlay
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanlinePainter(),
              ),
            ),
          ),

          // Main content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 600;
                if (isWide) {
                  return _buildWideLayout(hackerGreen, hackerRed, hackerCyan);
                }
                return _buildNarrowLayout(hackerGreen, hackerRed, hackerCyan);
              },
            ),
          ),

          // Success overlay
          if (_showSuccessOverlay)
            _buildResultOverlay(
              hackerGreen,
              hackerCyan,
              isSuccess: true,
              secret: _secret,
            ),

          // Failure overlay
          if (_showFailureOverlay)
            _buildResultOverlay(
              hackerRed,
              hackerCyan,
              isSuccess: false,
              secret: _secret,
            ),
        ],
      ),
    );
  }

  Widget _buildWideLayout(Color green, Color red, Color cyan) {
    return Row(
      children: [
        // History panel on the left
        SizedBox(
          width: 200,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                right:
                    BorderSide(color: green.withValues(alpha: 0.15), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'LOG',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: green.withValues(alpha: 0.4),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _history.isEmpty
                      ? Center(
                          child: Text(
                            'No entries',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: green.withValues(alpha: 0.2),
                            ),
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final row = _history[_history.length - 1 - index];
                            return _buildGuessRow(row, green, red);
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // Game area in the center
        Expanded(
          child: Column(
            children: [
              _buildHeader(green, cyan),
              const SizedBox(height: 8),
              _buildAttemptCounter(green, red),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: _buildCurrentRow(green),
                ),
              ),
              _buildNumberPad(green, cyan, red),
              const SizedBox(height: 16),
            ],
          ),
        ),
        // Right panel (attempts info)
        SizedBox(
          width: 180,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border(
                left:
                    BorderSide(color: green.withValues(alpha: 0.15), width: 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'STATUS',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: green.withValues(alpha: 0.4),
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 12),
                _statusLine(green, 'Attempts', '$_attemptsLeft / 5'),
                _statusLine(green, 'Locked',
                    '${_locked.where((l) => l != null).length} / 3'),
                _statusLine(
                    green,
                    'State',
                    _isGameOver
                        ? (_showSuccessOverlay ? 'CRACKED' : 'CAUGHT')
                        : 'ACTIVE'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusLine(Color green, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: green.withValues(alpha: 0.5),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: green,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNarrowLayout(Color green, Color red, Color cyan) {
    return Column(
      children: [
        _buildHeader(green, cyan),
        const SizedBox(height: 8),
        _buildAttemptCounter(green, red),
        const SizedBox(height: 12),
        // Current input row
        _buildCurrentRow(green),
        const SizedBox(height: 12),
        // History (scrollable)
        SizedBox(
          height: 120,
          child: _history.isEmpty
              ? Center(
                  child: Text(
                    'Crack the code...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: green.withValues(alpha: 0.3),
                    ),
                  ),
                )
              : ListView.builder(
                  reverse: true,
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final row = _history[_history.length - 1 - index];
                    return _buildGuessRow(row, green, red);
                  },
                ),
        ),
        const SizedBox(height: 12),
        // Number pad
        _buildNumberPad(green, cyan, red),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildHeader(Color green, Color cyan) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: green.withValues(alpha: 0.4), width: 1),
        ),
      ),
      child: Column(
        children: [
          Text(
            '// PORT SECURITY SYSTEM \\\\',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: cyan.withValues(alpha: 0.7),
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'HACKING INTERFACE ACTIVE',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: green,
              letterSpacing: 4,
              shadows: [
                Shadow(color: green.withValues(alpha: 0.6), blurRadius: 12),
                Shadow(color: green.withValues(alpha: 0.3), blurRadius: 24),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Crack the 3-digit security code',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: green.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttemptCounter(Color green, Color red) {
    final color = _attemptsLeft <= 2 ? red : green;
    final bars = StringBuffer();
    for (var i = 0; i < 5; i++) {
      bars.write(i < _attemptsLeft ? '█' : '░');
    }
    return Column(
      children: [
        Text(
          'ATTEMPTS REMAINING',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: green.withValues(alpha: 0.5),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          bars.toString(),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 24,
            color: color,
            letterSpacing: 6,
            shadows: [
              Shadow(color: color.withValues(alpha: 0.4), blurRadius: 8),
            ],
          ),
        ),
        Text(
          '$_attemptsLeft / 5',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildGuessRow(_GuessRow row, Color green, Color red) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final digit = row.guess[i];
          final isCorrect = digit == _secret[i];
          final color = isCorrect ? green : red;
          return _digitSlot(
            digit: digit,
            color: color,
            size: 36,
            glow: isCorrect,
          );
        }),
      ),
    );
  }

  Widget _buildCurrentRow(Color green) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          if (_locked[i] != null) {
            return _digitSlot(
              digit: _locked[i]!,
              color: green,
              size: 48,
              glow: true,
            );
          }
          final digit = _currentInput[i];
          return _digitSlot(
            digit: digit,
            color: Colors.white70,
            size: 48,
            glow: false,
            isActive: i == _currentSlot && digit == null,
          );
        }),
      ),
    );
  }

  Widget _digitSlot({
    required int? digit,
    required Color color,
    required double size,
    bool glow = false,
    bool isActive = false,
  }) {
    return Container(
      width: size,
      height: size,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isActive
            ? color.withValues(alpha: 0.15)
            : color.withValues(alpha: digit != null ? 0.2 : 0.05),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? color.withValues(alpha: 0.8)
              : color.withValues(alpha: digit != null ? 0.6 : 0.15),
          width: isActive ? 2 : 1,
        ),
        boxShadow: glow && digit != null
            ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10)]
            : null,
      ),
      child: digit != null
          ? Text(
              '$digit',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: size * 0.5,
                fontWeight: FontWeight.bold,
                color: color,
                shadows: glow
                    ? [
                        Shadow(
                            color: color.withValues(alpha: 0.6), blurRadius: 8)
                      ]
                    : null,
              ),
            )
          : (isActive
              ? Text(
                  '_',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: size * 0.5,
                    color: color.withValues(alpha: 0.6),
                  ),
                )
              : null),
    );
  }

  Widget _buildNumberPad(Color green, Color cyan, Color red) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          // Digit buttons
          for (var row = 0; row < 3; row++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (col) {
                  final digit = row * 3 + col + 1;
                  return _numberButton(
                    label: '$digit',
                    onTap: () => _onDigitPressed(digit),
                    color: green,
                  );
                }),
              ),
            ),
          // Bottom row: 0, delete
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _numberButton(
                  label: '0',
                  onTap: () => _onDigitPressed(0),
                  color: green,
                ),
                const SizedBox(width: 12),
                _numberButton(
                  label: 'DEL',
                  onTap: _onDelete,
                  color: red,
                  isWide: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Submit button
          GestureDetector(
            onTap: _canSubmit ? _submitGuess : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: 48,
              decoration: BoxDecoration(
                color: _canSubmit
                    ? green.withValues(alpha: 0.15)
                    : Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _canSubmit
                      ? green.withValues(alpha: 0.8)
                      : Colors.grey.withValues(alpha: 0.2),
                  width: 1.5,
                ),
                boxShadow: _canSubmit
                    ? [
                        BoxShadow(
                          color: green.withValues(alpha: 0.2),
                          blurRadius: 8,
                        )
                      ]
                    : null,
              ),
              alignment: Alignment.center,
              child: Text(
                _isSubmitting ? 'PROCESSING...' : 'SUBMIT HACK',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color:
                      _canSubmit ? green : Colors.grey.withValues(alpha: 0.4),
                  letterSpacing: 3,
                  shadows: _canSubmit
                      ? [
                          Shadow(
                              color: green.withValues(alpha: 0.5),
                              blurRadius: 8)
                        ]
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Cancel button
          GestureDetector(
            onTap: widget.onCancel,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'ABORT HACK',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.grey.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberButton({
    required String label,
    required VoidCallback onTap,
    required Color color,
    bool isWide = false,
  }) {
    return GestureDetector(
      onTap: _isGameOver ? null : onTap,
      child: Container(
        width: isWide ? 84 : 56,
        height: 48,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color.withValues(alpha: 0.9),
          ),
        ),
      ),
    );
  }

  Widget _buildResultOverlay(
    Color accent,
    Color cyan, {
    required bool isSuccess,
    required List<int> secret,
  }) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isSuccess)
              Icon(Icons.check_circle_outline, size: 64, color: accent)
            else
              Icon(Icons.error_outline, size: 64, color: accent),
            const SizedBox(height: 16),
            Text(
              isSuccess ? 'ACCESS GRANTED' : 'INTRUSION DETECTED',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: accent,
                letterSpacing: 4,
                shadows: [
                  Shadow(color: accent.withValues(alpha: 0.5), blurRadius: 16),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Code: ${secret[0]}${secret[1]}${secret[2]}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: accent.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            if (isSuccess)
              _buildSuccessRewardOptions(accent)
            else
              _buildFailurePenalty(),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessRewardOptions(Color accent) {
    return Column(
      children: [
        Text(
          'SELECT REWARD:',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            color: accent.withValues(alpha: 0.6),
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 12),
        _rewardButton(
          icon: Icons.monetization_on_rounded,
          label: 'STEAL CREDITS',
          subtitle: '+${500 + Random().nextInt(1500)} cr',
          color: accent,
          onTap: () {
            final amount = 500 + Random().nextInt(1501);
            final updated = widget.player.copyWith(
              credits: widget.player.credits + amount,
            );
            widget.onSuccess(updated);
          },
        ),
        const SizedBox(height: 8),
        _rewardButton(
          icon: Icons.diamond_rounded,
          label: 'STEAL RESOURCES',
          subtitle: '+5 random cargo',
          color: accent,
          onTap: () {
            final commodities = ['minerals', 'organics', 'industrial'];
            final chosen = commodities[Random().nextInt(commodities.length)];
            final newCargo = Map<String, int>.from(widget.player.cargo);
            newCargo[chosen] = (newCargo[chosen] ?? 0) + 5;
            final updated = widget.player.copyWith(
              cargo: newCargo,
              cargoUsed: widget.player.cargoUsed + 5,
            );
            widget.onSuccess(updated);
          },
        ),
      ],
    );
  }

  Widget _rewardButton({
    required IconData icon,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 260,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: color.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: color.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailurePenalty() {
    final nextFailCount = widget.failCount + 1;
    final penalties = <int, int>{1: 500, 2: 2500, 3: 5000};
    final penalty = penalties[nextFailCount] ?? 0;
    final isLastChance = nextFailCount >= widget.maxAttempts;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          Text(
            'Port security has detected your intrusion.\n'
            'System lockdown initiated.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              color: Colors.white.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFF0040).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: const Color(0xFFFF0040).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: const Color(0xFFFF0040),
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'PENALTY: $penalty CREDITS LOST',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFFF0040),
                  ),
                ),
              ],
            ),
          ),
          if (isLastChance) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFF0040).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF0040).withValues(alpha: 0.5),
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.block_rounded,
                    color: const Color(0xFFFF0040),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'IP TRACED — CONNECTION BANNED',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFFFF0040),
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Blocked for 24 hours',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: const Color(0xFFFF0040).withValues(alpha: 0.7),
              ),
            ),
          ] else ...[
            const SizedBox(height: 12),
            Text(
              'Attempts: $nextFailCount / ${widget.maxAttempts}',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: const Color(0xFFFF0040).withValues(alpha: 0.7),
              ),
            ),
          ],
          const SizedBox(height: 24),
          GestureDetector(
            onTap: () {
              widget.onFailure(nextFailCount);
            },
            child: Container(
              width: 200,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFFF0040).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFFF0040).withValues(alpha: 0.5),
                ),
              ),
              child: Text(
                'ACKNOWLEDGE',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFFF0040),
                  letterSpacing: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuessRow {
  final List<int> guess;
  final List<int?> locked;

  _GuessRow({required this.guess, required this.locked});
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.015)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => false;
}
