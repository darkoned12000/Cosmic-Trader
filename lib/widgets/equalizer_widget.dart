import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tradewars_2050/services/audio_service.dart';

class EqualizerWidget extends StatefulWidget {
  final int bandCount;
  final double barWidth;
  final double barSpacing;
  final double height;

  const EqualizerWidget({
    super.key,
    this.bandCount = 14,
    this.barWidth = 3.0,
    this.barSpacing = 2.0,
    this.height = 20.0,
  });

  @override
  State<EqualizerWidget> createState() => _EqualizerWidgetState();
}

class _EqualizerWidgetState extends State<EqualizerWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final _rng = math.Random();
  final _heights = <double>[];
  late int _bandCount;

  @override
  void initState() {
    super.initState();
    _bandCount = widget.bandCount;
    for (int i = 0; i < _bandCount; i++) {
      _heights.add(0.0);
    }
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    )..addListener(() => setState(() {}));
    _controller.repeat(min: 0.0, max: 1.0);

    AudioService.isPlaying.addListener(_onPlayStateChanged);
    AudioService.isMusicEnabled.addListener(_onPlayStateChanged);
  }

  @override
  void dispose() {
    _controller.dispose();
    AudioService.isPlaying.removeListener(_onPlayStateChanged);
    AudioService.isMusicEnabled.removeListener(_onPlayStateChanged);
    super.dispose();
  }

  void _onPlayStateChanged() {
    if (!mounted) return;
    if (!AudioService.isMusicEnabled.value || !AudioService.isPlaying.value) {
      setState(() => _heights.fillRange(0, _bandCount, 0.0));
    }
  }

  @override
  void didUpdateWidget(EqualizerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bandCount != widget.bandCount) {
      _bandCount = widget.bandCount;
      while (_heights.length < _bandCount) {
        _heights.add(0.0);
      }
      while (_heights.length > _bandCount) {
        _heights.removeLast();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active =
        AudioService.isMusicEnabled.value && AudioService.isPlaying.value;

    for (int i = 0; i < _bandCount; i++) {
      if (active) {
        final target = _rng.nextDouble();
        _heights[i] = _heights[i] + (target - _heights[i]) * 0.3;
      } else {
        _heights[i] *= 0.85;
      }
    }

    return SizedBox(
      width: _bandCount * (widget.barWidth + widget.barSpacing) + widget.barSpacing,
      height: widget.height,
      child: CustomPaint(
        painter: _EqualizerPainter(
          heights: _heights,
          barWidth: widget.barWidth,
          barSpacing: widget.barSpacing,
          color: cs.primary,
          active: active,
        ),
      ),
    );
  }
}

class _EqualizerPainter extends CustomPainter {
  final List<double> heights;
  final double barWidth;
  final double barSpacing;
  final Color color;
  final bool active;

  _EqualizerPainter({
    required this.heights,
    required this.barWidth,
    required this.barSpacing,
    required this.color,
    required this.active,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = active ? color : color.withValues(alpha: 0.2)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < heights.length; i++) {
      final barHeight = heights[i] * size.height;
      final x = i * (barWidth + barSpacing) + barSpacing;
      final y = size.height - barHeight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, barWidth, barHeight),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) => true;
}
