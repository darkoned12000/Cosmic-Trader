import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';

class HackingWidget extends StatefulWidget {
  final Player player;
  final Port? port;
  final int failCount;
  final int maxAttempts;
  final int maxFailures;
  final ValueChanged<Player> onSuccess;
  final ValueChanged<int> onFailure;
  final VoidCallback onCancel;

  const HackingWidget({
    super.key,
    required this.player,
    this.port,
    this.failCount = 0,
    this.maxAttempts = 5,
    this.maxFailures = 3,
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
  late final List<String> _terminalMessages;

  // Each element is the digit locked in for that position, or null if not yet locked
  final List<int?> _locked = [null, null, null];

  // Current guess being built (indices into _secret)
  final List<int?> _currentInput = [null, null, null];

  int _currentSlot = 0;
  late int _attemptsLeft;
  bool _isGameOver = false;
  bool _isSubmitting = false;
  bool _showFailureOverlay = false;
  bool _showSuccessOverlay = false;
  int? _creditReward;
  String? _cargoReward;

  late final FocusNode _keyboardFocus;
  late AnimationController _glitchController;
  late AnimationController _cursorController;
  late AnimationController _atmosphereController;
  Timer? _packetTimer;
  int _packetCounter = 0;

  static const _digitKeys = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit0,
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
    LogicalKeyboardKey.numpad0,
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  _HackPalette get _palette {
    final port = widget.port;
    if (port?.ownerFaction == FactionClass.pirate) {
      return const _HackPalette(
        green: Color(0xFFFF7A00),
        red: Color(0xFFFF0040),
        cyan: Color(0xFFFFC857),
      );
    }

    return switch (port?.portClass) {
      PortClass.federal => const _HackPalette(
          green: Color(0xFF42D6FF),
          red: Color(0xFFFF5C5C),
          cyan: Color(0xFF00E5FF),
        ),
      PortClass.independent => const _HackPalette(
          green: Color(0xFF00FF88),
          red: Color(0xFFFF3366),
          cyan: Color(0xFF66FFCC),
        ),
      PortClass.free => const _HackPalette(
          green: Color(0xFFB7FF3C),
          red: Color(0xFFFF3B30),
          cyan: Color(0xFFE4FF4F),
        ),
      PortClass.hardwareEmporium => const _HackPalette(
          green: Color(0xFF00D9FF),
          red: Color(0xFFFFB300),
          cyan: Color(0xFF9D7BFF),
        ),
      null => const _HackPalette(
          green: Color(0xFF00FF41),
          red: Color(0xFFFF0040),
          cyan: Color(0xFF00FFFF),
        ),
    };
  }

  int get _attemptTotal => max(1, widget.maxAttempts);

  int get _tracePercent {
    final usedAttempts = _attemptTotal - _attemptsLeft;
    return (usedAttempts / _attemptTotal * 100).round().clamp(0, 100);
  }

  List<String> _buildInitialTerminalMessages() {
    final port = widget.port;
    if (port?.ownerFaction == FactionClass.pirate) {
      return [
        'Connecting to pirate relay ${port!.name.toUpperCase()}...',
        'Hidden firewall signature detected.',
      ];
    }

    return switch (port?.portClass) {
      PortClass.federal => [
          'Establishing federal security uplink...',
          'Martial authorization handshake required.',
        ],
      PortClass.free => [
          'Reading corrupted port handshake...',
          'Diagnostic integrity below threshold.',
        ],
      PortClass.hardwareEmporium => [
          'Mapping hardware security bus...',
          'Firmware signature analysis ready.',
        ],
      _ => [
          'Establishing uplink...',
          'Local firewall detected.',
        ],
    };
  }

  String _generatePacketTrace() {
    const protocols = ['TCP', 'UDP', 'ICMP', 'TLS', 'DNS'];
    const flags = ['SYN', 'ACK', 'DATA', 'FIN', 'RST'];
    final packet = _packetCounter++;
    final protocol = protocols[packet % protocols.length];
    final sourceHost =
        '10.${packet % 4}.${(packet * 7) % 250}.${(packet * 13) % 250}';
    final destinationHost =
        '172.16.${(packet * 3) % 250}.${(packet * 17) % 250}';
    final sourcePort = 30000 + ((packet * 37) % 9000);
    final destinationPort = protocol == 'TLS' ? 443 : 8080;
    final flag = flags[packet % flags.length];
    final bytes = 64 + ((packet * 137) % 4096);
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);

    return '$timestamp  $protocol  $sourceHost:$sourcePort -> '
        '$destinationHost:$destinationPort  [$flag]  $bytes B';
  }

  @override
  void initState() {
    super.initState();
    _secret = _generateUniqueCode();
    _terminalMessages = _buildInitialTerminalMessages();
    _attemptsLeft = _attemptTotal;
    _glitchController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _cursorController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _atmosphereController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _keyboardFocus = FocusNode(debugLabel: 'hack-port-keyboard');
    _packetTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) {
      if (!mounted || _isGameOver) return;
      setState(() => _addTerminalMessage(_generatePacketTrace()));
    });
  }

  void _stopPacketCapture() {
    _packetTimer?.cancel();
    _packetTimer = null;
  }

  @override
  void dispose() {
    _stopPacketCapture();
    _glitchController.dispose();
    _cursorController.dispose();
    _atmosphereController.dispose();
    _keyboardFocus.dispose();
    super.dispose();
  }

  static List<int> _generateUniqueCode() {
    final digits = List<int>.generate(10, (i) => i);
    digits.shuffle();
    return digits.take(3).toList();
  }

  void _requestKeyboardFocus() {
    if (!_keyboardFocus.hasFocus) {
      _keyboardFocus.requestFocus();
    }
  }

  int? _digitFromKey(KeyEvent event) {
    final keyIndex = _digitKeys.indexOf(event.logicalKey);
    if (keyIndex >= 0) return keyIndex % 10;

    final character = event.character;
    if (character != null && character.length == 1) {
      final code = character.codeUnitAt(0);
      if (code >= 48 && code <= 57) return code - 48;
    }
    return null;
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isGameOver) {
      return KeyEventResult.ignored;
    }

    final digit = _digitFromKey(event);
    if (digit != null) {
      _onDigitPressed(digit);
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace ||
        event.logicalKey == LogicalKeyboardKey.delete) {
      _onDelete();
      return KeyEventResult.handled;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submitGuess();
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  void _onDigitPressed(int digit) {
    _requestKeyboardFocus();
    if (_isGameOver || _isSubmitting) return;
    if (_currentSlot >= 3) return;
    // Skip any locked positions
    while (_currentSlot < 3 && _locked[_currentSlot] != null) {
      _currentSlot++;
    }
    if (_currentSlot >= 3) return;
    final slot = _currentSlot;
    setState(() {
      _currentInput[slot] = digit;
      _currentSlot++;
      _addTerminalMessage('PLAYER INPUT  slot=${slot + 1}  value=$digit');
    });
  }

  void _onDelete() {
    _requestKeyboardFocus();
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

  void _addTerminalMessage(String message) {
    _terminalMessages.add(message);
    if (_terminalMessages.length > 30) {
      _terminalMessages.removeAt(0);
    }
  }

  void _submitGuess() {
    _requestKeyboardFocus();
    if (!_canSubmit || _isGameOver || _isSubmitting) return;
    setState(() {
      _isSubmitting = true;
      _addTerminalMessage('Injecting authentication packet...');
    });

    final guess = <int>[];
    for (var i = 0; i < 3; i++) {
      guess.add(_locked[i] ?? _currentInput[i]!);
    }

    // Build locked result after this guess.
    final newLocked = List<int?>.from(_locked);
    var matchedCount = 0;
    for (var i = 0; i < 3; i++) {
      if (guess[i] == _secret[i]) {
        newLocked[i] = _secret[i];
        matchedCount++;
      }
    }

    final allMatch = matchedCount == 3;
    _history
        .add(_GuessRow(guess: List.from(guess), locked: List.from(newLocked)));

    if (allMatch) {
      _isGameOver = true;
      _stopPacketCapture();
      _creditReward = 500 + Random().nextInt(1501);
      _cargoReward = CommodityRegistry
          .names[Random().nextInt(CommodityRegistry.names.length)];
      _addTerminalMessage('AUTHENTICATION ACCEPTED.');
      _addTerminalMessage('Opening port security node...');
      _glitchController.forward(from: 0).whenComplete(() {
        if (mounted) setState(() => _showSuccessOverlay = true);
      });
      setState(() => _isSubmitting = false);
      return;
    }

    _attemptsLeft--;
    _glitchController.forward(from: 0);
    if (matchedCount == 0) {
      _addTerminalMessage('Injection rejected. No valid digits found.');
    } else {
      _addTerminalMessage(
        'Injection partially accepted. $matchedCount digit${matchedCount == 1 ? '' : 's'} locked.',
      );
    }

    if (_attemptsLeft <= 0) {
      _isGameOver = true;
      _stopPacketCapture();
      _addTerminalMessage('SECURITY TRACE COMPLETE. PORT LOCKDOWN.');
      _glitchController.forward(from: 0).whenComplete(() {
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

    // Sci-fi/cyberpunk color scheme, themed by the target port.
    final palette = _palette;
    final hackerGreen = palette.green;
    final hackerRed = palette.red;
    final hackerCyan = palette.cyan;
    final darkBg = cs.surface;

    return Focus(
      focusNode: _keyboardFocus,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        backgroundColor: darkBg,
        body: Stack(
          children: [
            // Scanline overlay
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _atmosphereController,
                  builder: (context, child) {
                    return CustomPaint(
                      painter: _ScanlinePainter(
                        animation: _atmosphereController,
                        accentColor: hackerCyan,
                        alertColor: hackerRed,
                        isAlert: _tracePercent >= 75,
                      ),
                    );
                  },
                ),
              ),
            ),

            // Main content. The controller is also used for a short shake
            // after an incorrect submission.
            AnimatedBuilder(
              animation: _glitchController,
              builder: (context, child) {
                final progress = _glitchController.value;
                final envelope = sin(pi * progress);
                return Transform.translate(
                  offset: Offset(
                    sin(progress * 45) * 3 * envelope,
                    cos(progress * 37) * 2 * envelope,
                  ),
                  child: child,
                );
              },
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth > 600;
                    if (isWide) {
                      return _buildWideLayout(
                          hackerGreen, hackerRed, hackerCyan);
                    }
                    return _buildNarrowLayout(
                        hackerGreen, hackerRed, hackerCyan);
                  },
                ),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedBuilder(
                          animation: _atmosphereController,
                          builder: (context, child) {
                            return Opacity(
                              opacity: 0.35 +
                                  (sin(_atmosphereController.value * pi * 4) *
                                          0.45)
                                      .abs(),
                              child: child,
                            );
                          },
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: cyan,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 8,
                            color: cyan.withValues(alpha: 0.55),
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _buildTerminalLog(green, red, cyan),
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
              const SizedBox(height: 12),
              _buildTraceMeter(green, cyan, red),
              const SizedBox(height: 12),
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
                _statusLine(
                    green, 'Attempts', '$_attemptsLeft / $_attemptTotal'),
                _statusLine(green, 'Locked',
                    '${_locked.where((l) => l != null).length} / 3'),
                _statusLine(
                  green,
                  'Trace',
                  '$_tracePercent%',
                  valueColor: _tracePercent >= 75
                      ? red
                      : (_tracePercent >= 40 ? const Color(0xFFFFC857) : green),
                ),
                _statusLine(
                    green,
                    'State',
                    _isGameOver
                        ? (_showSuccessOverlay ? 'CRACKED' : 'CAUGHT')
                        : 'ACTIVE'),
                const SizedBox(height: 12),
                Divider(color: green.withValues(alpha: 0.2), height: 1),
                const SizedBox(height: 8),
                Text(
                  'ATTEMPT LOG',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: green.withValues(alpha: 0.4),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: _buildAttemptHistory(green, red),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _statusLine(
    Color green,
    String label,
    String value, {
    Color? valueColor,
  }) {
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
              color: valueColor ?? green,
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
        _buildTraceMeter(green, cyan, red),
        const SizedBox(height: 12),
        // Current input row
        _buildCurrentRow(green),
        const SizedBox(height: 12),
        // Packet feed and attempt history stay side-by-side so neither is
        // pushed out of view by the other.
        SizedBox(
          height: 120,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildTerminalLog(green, red, cyan),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _buildAttemptHistory(green, red),
              ),
            ],
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
            'TARGET: ${(widget.port?.name ?? 'UNKNOWN PORT').toUpperCase()}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              color: cyan.withValues(alpha: 0.55),
              letterSpacing: 1,
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
    final warningThreshold = (_attemptTotal * 0.4).ceil();
    final color = _attemptsLeft <= warningThreshold ? red : green;
    final bars = StringBuffer();
    for (var i = 0; i < _attemptTotal; i++) {
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
          '$_attemptsLeft / $_attemptTotal',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildTraceMeter(Color green, Color cyan, Color red) {
    final trace = _tracePercent;
    final traceColor =
        trace >= 75 ? red : (trace >= 40 ? const Color(0xFFFFC857) : cyan);
    final statusText = trace >= 75
        ? 'COUNTER-INTRUSION IMMINENT'
        : (trace >= 40 ? 'SECURITY TRACE RISING' : 'TRACE NOMINAL');

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: trace / 100),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'SECURITY TRACE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: traceColor.withValues(alpha: 0.8),
                    letterSpacing: 1.5,
                  ),
                ),
                Text(
                  '$trace%',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: traceColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 8,
                backgroundColor: green.withValues(alpha: 0.08),
                valueColor: AlwaysStoppedAnimation<Color>(traceColor),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              statusText,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: traceColor.withValues(alpha: 0.6),
                letterSpacing: 0.5,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTerminalLog(Color green, Color red, Color cyan) {
    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.zero,
      itemCount: _terminalMessages.length,
      itemBuilder: (context, index) {
        final message = _terminalMessages[_terminalMessages.length - 1 - index];
        final isPlayerInput = message.startsWith('PLAYER INPUT') ||
            message.toLowerCase().contains('injection');
        final isPacket = const ['TCP ', 'UDP ', 'ICMP ', 'TLS ', 'DNS ']
            .any(message.startsWith);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(
            isPacket || isPlayerInput ? message : '> $message',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: isPacket ? 9 : 10,
              height: 1.25,
              color: isPlayerInput
                  ? const Color(0xFFFFFF66)
                  : isPacket
                      ? cyan.withValues(alpha: 0.7)
                      : green.withValues(alpha: 0.55),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttemptHistory(Color green, Color red) {
    if (_history.isEmpty) {
      return Center(
        child: Text(
          'No attempts submitted',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 10,
            color: green.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    return ListView.builder(
      reverse: true,
      padding: EdgeInsets.zero,
      itemCount: _history.length,
      itemBuilder: (context, index) {
        final row = _history[_history.length - 1 - index];
        return _buildGuessRow(row, green, red);
      },
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
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
              ? AnimatedBuilder(
                  animation: _cursorController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _cursorController.value > 0.35 ? 0.9 : 0.18,
                      child: child,
                    );
                  },
                  child: Text(
                    '_',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: size * 0.5,
                      color: color.withValues(alpha: 0.8),
                    ),
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
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.scale(
              scale: 0.96 + (value * 0.04),
              child: child,
            ),
          );
        },
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
                    Shadow(
                        color: accent.withValues(alpha: 0.5), blurRadius: 16),
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
      ),
    );
  }

  Widget _buildSuccessRewardOptions(Color accent) {
    final creditReward = _creditReward ?? 0;
    final cargoReward = _cargoReward ?? CommodityRegistry.names.first;

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
          subtitle: '+$creditReward cr',
          color: accent,
          onTap: () {
            final updated = widget.player.copyWith(
              credits: widget.player.credits + creditReward,
            );
            widget.onSuccess(updated);
          },
        ),
        const SizedBox(height: 8),
        _rewardButton(
          icon: Icons.diamond_rounded,
          label: 'STEAL RESOURCES',
          subtitle: '+5 $cargoReward cargo',
          color: accent,
          onTap: () {
            final newCargo = Map<String, int>.from(widget.player.cargo);
            newCargo[cargoReward] = (newCargo[cargoReward] ?? 0) + 5;
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
    final penalties = <int, int>{1: 500, 2: 2500, 3: 5000, 4: 7500, 5: 10000};
    final penalty = penalties[nextFailCount] ?? 0;
    final isLastChance = nextFailCount >= widget.maxFailures;

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
              'Attempts: $nextFailCount / ${widget.maxFailures}',
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
  _ScanlinePainter({
    required this.animation,
    required this.accentColor,
    required this.alertColor,
    required this.isAlert,
  });

  final Animation<double> animation;
  final Color accentColor;
  final Color alertColor;
  final bool isAlert;

  @override
  void paint(Canvas canvas, Size size) {
    final progress = animation.value;
    final scanlinePaint = Paint()
      ..color = Colors.white.withValues(alpha: isAlert ? 0.025 : 0.015)
      ..strokeWidth = 1;
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scanlinePaint);
    }

    // A restrained perspective grid gives the terminal depth without
    // competing with the code slots or log text.
    final gridPaint = Paint()
      ..color = (isAlert ? alertColor : accentColor).withValues(alpha: 0.045)
      ..strokeWidth = 1;
    for (var x = 0.0; x < size.width; x += 64) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y < size.height; y += 64) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Small data packets travel through the grid. Alert mode changes their
    // color and adds a brief red pulse, but the effect remains subtle.
    final packetColor = isAlert ? alertColor : accentColor;
    for (var i = 0; i < 7; i++) {
      final travel = (progress + i / 7) % 1;
      final x = travel * size.width;
      final y = (size.height * ((i * 37) % 100) / 100);
      final fade = 0.12 + (0.18 * sin(pi * travel).abs());
      final packetPaint = Paint()
        ..color = packetColor.withValues(alpha: fade)
        ..strokeWidth = isAlert ? 2 : 1;
      canvas.drawLine(
        Offset(x - 12, y),
        Offset(x, y),
        packetPaint,
      );
      canvas.drawCircle(Offset(x, y), isAlert ? 2.4 : 1.6, packetPaint);
    }
  }

  @override
  bool shouldRepaint(_ScanlinePainter oldDelegate) => true;
}

class _HackPalette {
  const _HackPalette({
    required this.green,
    required this.red,
    required this.cyan,
  });

  final Color green;
  final Color red;
  final Color cyan;
}
