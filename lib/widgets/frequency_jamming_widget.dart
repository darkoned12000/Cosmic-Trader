import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:tradewars_2050/data/models/player.dart';

class FrequencyJammingWidget extends StatefulWidget {
  final Player player;
  final ValueChanged<Player> onSuccess;
  final VoidCallback onFailure;
  final VoidCallback onCancel;

  const FrequencyJammingWidget({
    super.key,
    required this.player,
    required this.onSuccess,
    required this.onFailure,
    required this.onCancel,
  });

  @override
  State<FrequencyJammingWidget> createState() => _FrequencyJammingWidgetState();
}

class _FrequencyJammingWidgetState extends State<FrequencyJammingWidget>
    with TickerProviderStateMixin {
  late final double _targetFrequency;
  late final double _targetAmplitude;
  late final double _targetPhase;

  double _currentFrequency = 50.0;
  double _currentAmplitude = 50.0;
  double _currentPhase = 50.0;

  int _phase = 0;
  bool _isLocked = false;
  bool _showSuccess = false;
  bool _showFailure = false;

  late AnimationController _waveController;
  late Timer _countdownTimer;
  int _timeLeft = 20;

  static const double _minFreq = 1.0;
  static const double _maxFreq = 100.0;
  static const double _tolerance = 8.0;

  @override
  void initState() {
    super.initState();
    _targetFrequency = _minFreq + Random().nextDouble() * (_maxFreq - _minFreq);
    _targetAmplitude = _minFreq + Random().nextDouble() * (_maxFreq - _minFreq);
    _targetPhase = _minFreq + Random().nextDouble() * (_maxFreq - _minFreq);

    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_isLocked || _showSuccess || _showFailure) {
        timer.cancel();
        return;
      }
      setState(() {
        _timeLeft--;
        if (_timeLeft <= 0) {
          timer.cancel();
          _showFailure = true;
          _waveController.stop();
        }
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer.cancel();
    _waveController.dispose();
    super.dispose();
  }

  double get _signalStrength {
    final freqDiff = (_currentFrequency - _targetFrequency).abs();
    final ampDiff = (_currentAmplitude - _targetAmplitude).abs();
    final phaseDiff = (_currentPhase - _targetPhase).abs();

    final totalDiff = (freqDiff + ampDiff + phaseDiff) / 3;
    return (1.0 - (totalDiff / (_maxFreq - _minFreq)).clamp(0.0, 1.0))
        .clamp(0.0, 1.0);
  }

  bool get _isMatched {
    return (_currentFrequency - _targetFrequency).abs() < _tolerance &&
        (_currentAmplitude - _targetAmplitude).abs() < _tolerance &&
        (_currentPhase - _targetPhase).abs() < _tolerance;
  }

  void _adjustParameter(double value) {
    if (_isLocked) return;
    setState(() {
      switch (_phase) {
        case 0:
          _currentFrequency = value;
          break;
        case 1:
          _currentAmplitude = value;
          break;
        case 2:
          _currentPhase = value;
          break;
      }
    });
  }

  void _tryLock() {
    if (!_isMatched) return;
    setState(() {
      _isLocked = true;
      _showSuccess = true;
    });
    _waveController.stop();
  }

  void _stealResources() {
    final commodities = ['minerals', 'organics', 'industrial'];
    final available = commodities.where((c) {
      final current = widget.player.cargo[c] ?? 0;
      return current < widget.player.maxCargo;
    }).toList();

    if (available.isEmpty) {
      widget.onFailure();
      return;
    }

    final chosen = available[Random().nextInt(available.length)];
    final amount = min(10, widget.player.maxCargo - widget.player.cargoUsed);

    final newCargo = Map<String, int>.from(widget.player.cargo);
    newCargo[chosen] = (newCargo[chosen] ?? 0) + amount;

    final updated = widget.player.copyWith(
      cargo: newCargo,
      cargoUsed: widget.player.cargoUsed + amount,
    );

    widget.onSuccess(updated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _ScanlinePainter(),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Column(
                children: [
                  _buildHeader(cs),
                  const SizedBox(height: 16),
                  Expanded(
                    flex: 3,
                    child: _buildOscilloscope(cs),
                  ),
                  _buildSignalBar(cs),
                  const SizedBox(height: 16),
                  _buildControls(cs),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          if (_showSuccess) _buildSuccessOverlay(cs),
          if (_showFailure) _buildFailureOverlay(cs),
        ],
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs) {
    final timerColor = _timeLeft <= 10
        ? Colors.red
        : _timeLeft <= 20
            ? Colors.orange
            : cs.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
      decoration: BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: cs.primary.withValues(alpha: 0.4), width: 1),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '// FREQUENCY ANALYZER \\',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: cs.primary.withValues(alpha: 0.7),
                  letterSpacing: 2,
                ),
              ),
              Text(
                'TIME: ${_timeLeft}s',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: timerColor,
                  letterSpacing: 2,
                  shadows: [
                    Shadow(
                        color: timerColor.withValues(alpha: 0.6),
                        blurRadius: 8),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'PORT SECURITY JAMMING',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: cs.primary,
              letterSpacing: 4,
              shadows: [
                Shadow(
                    color: cs.primary.withValues(alpha: 0.6), blurRadius: 12),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Match the security frequency',
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: cs.primary.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOscilloscope(ColorScheme cs) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.3),
          width: 2,
        ),
        color: const Color(0xFF0A0A0A),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: AnimatedBuilder(
          animation: _waveController,
          builder: (context, child) {
            return SizedBox.expand(
              child: CustomPaint(
                painter: _WaveformPainter(
                  frequency: _currentFrequency,
                  amplitude: _currentAmplitude,
                  phase: _currentPhase,
                  progress: _waveController.value,
                  signalStrength: _signalStrength,
                  isLocked: _isLocked,
                  color: cs.primary,
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSignalBar(ColorScheme cs) {
    final strength = _signalStrength;
    final color = strength > 0.8
        ? Colors.green
        : strength > 0.5
            ? Colors.orange
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SIGNAL STRENGTH',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 10,
                  color: cs.primary.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
              ),
              Text(
                '${(strength * 100).toInt()}%',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: strength,
            backgroundColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildControls(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        children: [
          _buildParameterSelector(cs),
          const SizedBox(height: 16),
          _buildAdjustmentSliders(cs),
          const SizedBox(height: 16),
          _buildLockButton(cs),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _isLocked ? null : widget.onCancel,
            child: Text(
              'ABORT JAMMING',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.grey.withValues(alpha: 0.5),
                letterSpacing: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterSelector(ColorScheme cs) {
    final params = ['FREQUENCY', 'AMPLITUDE', 'PHASE'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(3, (i) {
        final isSelected = i == _phase;
        return GestureDetector(
          onTap: () {
            if (!_isLocked) {
              setState(() => _phase = i);
            }
          },
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected
                  ? cs.primary.withValues(alpha: 0.2)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? cs.primary.withValues(alpha: 0.6)
                    : cs.primary.withValues(alpha: 0.2),
                width: 1,
              ),
            ),
            child: Text(
              params[i],
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color:
                    isSelected ? cs.primary : cs.primary.withValues(alpha: 0.5),
                letterSpacing: 1,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAdjustmentSliders(ColorScheme cs) {
    double currentValue;
    switch (_phase) {
      case 0:
        currentValue = _currentFrequency;
        break;
      case 1:
        currentValue = _currentAmplitude;
        break;
      case 2:
      default:
        currentValue = _currentPhase;
        break;
    }

    return Column(
      children: [
        Slider(
          value: currentValue,
          min: _minFreq,
          max: _maxFreq,
          onChanged: _adjustParameter,
          activeColor: cs.primary,
          inactiveColor: cs.primary.withValues(alpha: 0.3),
        ),
        Text(
          'VALUE: ${currentValue.toStringAsFixed(1)}',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: cs.primary.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }

  Widget _buildLockButton(ColorScheme cs) {
    return GestureDetector(
      onTap: _tryLock,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 48,
        decoration: BoxDecoration(
          color: _isMatched
              ? cs.primary.withValues(alpha: 0.15)
              : Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isMatched
                ? cs.primary.withValues(alpha: 0.8)
                : Colors.grey.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: _isMatched
              ? [
                  BoxShadow(
                    color: cs.primary.withValues(alpha: 0.2),
                    blurRadius: 8,
                  )
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          _isMatched ? 'LOCK FREQUENCY' : 'MATCH REQUIRED',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: _isMatched ? cs.primary : Colors.grey.withValues(alpha: 0.4),
            letterSpacing: 3,
            shadows: _isMatched
                ? [
                    Shadow(
                        color: cs.primary.withValues(alpha: 0.5), blurRadius: 8)
                  ]
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessOverlay(ColorScheme cs) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
            const SizedBox(height: 16),
            Text(
              'FREQUENCY LOCKED',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.green,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                      color: Colors.green.withValues(alpha: 0.5),
                      blurRadius: 16),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Security system jammed',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Colors.green.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: _stealResources,
              child: Container(
                width: 240,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.green.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'STEAL RESOURCES',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: widget.onCancel,
              child: Text(
                'ABORT',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Colors.grey.withValues(alpha: 0.5),
                  letterSpacing: 2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFailureOverlay(ColorScheme cs) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.85),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.warning_amber_rounded, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'DETECTED!',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: Colors.red,
                letterSpacing: 4,
                shadows: [
                  Shadow(
                      color: Colors.red.withValues(alpha: 0.5), blurRadius: 16),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Security forces alerted',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                color: Colors.red.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: widget.onFailure,
              child: Container(
                width: 200,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.red.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  'ACKNOWLEDGE',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double frequency;
  final double amplitude;
  final double phase;
  final double progress;
  final double signalStrength;
  final bool isLocked;
  final Color color;

  _WaveformPainter({
    required this.frequency,
    required this.amplitude,
    required this.phase,
    required this.progress,
    required this.signalStrength,
    required this.isLocked,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (var i = 0; i < 5; i++) {
      final y = size.height * (i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    for (var i = 0; i < 10; i++) {
      final x = size.width * (i / 9);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final mainWavePaint = Paint()
      ..color = isLocked ? Colors.green : color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final waveHeight = (amplitude / 100.0) * (size.height * 0.4);

    final mainPath = Path();
    const step = 4.0;
    for (var x = 0.0; x < size.width; x += step) {
      final t = x / size.width;
      final wave = sin(t * frequency * 0.5 + phase * 0.1 + progress * pi * 2);
      final y = centerY + wave * waveHeight;

      if (x == 0) {
        mainPath.moveTo(x, y);
      } else {
        mainPath.lineTo(x, y);
      }
    }

    canvas.drawPath(mainPath, mainWavePaint);

    final secondaryPaint = Paint()
      ..color = const Color(0xFF00FF41).withValues(alpha: 0.3)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final secondaryPath = Path();
    for (var x = 0.0; x < size.width; x += step) {
      final t = x / size.width;
      final wave = sin(t * (frequency + 5) * 0.3 + progress * pi);
      final y = centerY + wave * (waveHeight * 0.3);

      if (x == 0) {
        secondaryPath.moveTo(x, y);
      } else {
        secondaryPath.lineTo(x, y);
      }
    }

    canvas.drawPath(secondaryPath, secondaryPaint);

    // Random noise/static lines
    final noiseFrequencies = [17.0, 29.0, 43.0, 57.0];
    for (var n = 0; n < noiseFrequencies.length; n++) {
      final noisePaint = Paint()
        ..color = const Color(0xFF00FF41).withValues(alpha: 0.08)
        ..strokeWidth = 0.8
        ..style = PaintingStyle.stroke;

      final noisePath = Path();
      final noiseFreq = noiseFrequencies[n];
      final noiseAmp = waveHeight * 0.15 * (1.0 - n * 0.15);
      for (var x = 0.0; x < size.width; x += step) {
        final t = x / size.width;
        final wave = sin(t * noiseFreq + progress * pi * (n + 1) * 0.7) *
            cos(t * (noiseFreq * 0.3) + progress * 3.0);
        final y = centerY + wave * noiseAmp;

        if (x == 0) {
          noisePath.moveTo(x, y);
        } else {
          noisePath.lineTo(x, y);
        }
      }
      canvas.drawPath(noisePath, noisePaint);
    }

    if (signalStrength > 0.7) {
      final strengthPaint = Paint()
        ..color = Colors.green.withValues(alpha: signalStrength * 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      for (var i = 0; i < 3; i++) {
        final radius = 20.0 + i * 15.0;
        canvas.drawCircle(
          Offset(size.width - 30, 30),
          radius,
          strengthPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
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
