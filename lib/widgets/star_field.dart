import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class StarFieldBackground extends StatefulWidget {
  final int starCount;
  final Color color;

  const StarFieldBackground({
    super.key,
    this.starCount = 150,
    this.color = Colors.white,
  });

  @override
  State<StarFieldBackground> createState() => _StarFieldBackgroundState();
}

class _StarFieldBackgroundState extends State<StarFieldBackground>
    with SingleTickerProviderStateMixin {
  late Ticker _ticker;
  late List<_Star> _stars;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _stars = List.generate(widget.starCount, (_) => _Star());
    _ticker = createTicker((elapsed) {
      setState(() => _elapsed = elapsed);
    })
      ..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StarPainter(
        stars: _stars,
        elapsed: _elapsed,
        color: widget.color,
      ),
      size: Size.infinite,
    );
  }
}

class _Star {
  final double x;
  final double y;
  final double speedX;
  final double speedY;
  final double twinkleFreq;
  final double twinklePhase;
  final double size;
  final double brightness;

  _Star()
      : x = Random().nextDouble(),
        y = Random().nextDouble(),
        speedX = 0.003 + Random().nextDouble() * 0.015,
        speedY = 0.001 + Random().nextDouble() * 0.005,
        twinkleFreq = 0.5 + Random().nextDouble() * 1.5,
        twinklePhase = Random().nextDouble() * 2 * pi,
        size = 0.5 + Random().nextDouble() * 2.0,
        brightness = 0.3 + Random().nextDouble() * 0.7;
}

class _StarPainter extends CustomPainter {
  final List<_Star> stars;
  final Duration elapsed;
  final Color color;

  _StarPainter({
    required this.stars,
    required this.elapsed,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final seconds = elapsed.inMilliseconds / 1000.0;

    for (final star in stars) {
      final x = (star.x + seconds * star.speedX) % 1.0;
      final y = (star.y + seconds * star.speedY) % 1.0;

      final twinkle =
          sin(seconds * 2 * pi * star.twinkleFreq + star.twinklePhase);
      final opacity = star.brightness * (0.3 + 0.7 * (0.5 + 0.5 * twinkle));

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..style = PaintingStyle.fill;

      canvas.drawCircle(
        Offset(x * size.width, y * size.height),
        star.size,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_StarPainter oldDelegate) => true;
}

/// Static starfield painter used inside InteractiveViewer (no drift).
/// Stars twinkle in place based on an [Animation<double>] value.
class StarfieldPainter extends CustomPainter {
  final Size size;
  final Animation<double> animation;
  final int starCount;
  final List<_StaticStar> _stars;

  StarfieldPainter({
    required this.size,
    required this.animation,
    this.starCount = 80,
  })  : _stars = _generateStars(starCount),
        super(repaint: animation);

  static List<_StaticStar> _generateStars(int count) {
    final random = Random(42);
    return List.generate(count, (_) {
      final r = 200 + (random.nextDouble() * 55).toInt();
      final g = 200 + (random.nextDouble() * 55).toInt();
      final b = 200 + (random.nextDouble() * 55).toInt();
      return _StaticStar(
        x: random.nextDouble(),
        y: random.nextDouble(),
        radius: 0.5 + random.nextDouble() * 1.5,
        phase: random.nextDouble() * 2 * pi,
        baseColor: Color.fromRGBO(r, g, b, 1.0),
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final time = animation.value * 2 * pi;
    for (final star in _stars) {
      final px = star.x * size.width;
      final py = star.y * size.height;
      final twinkle = 0.3 + 0.7 * (0.5 + 0.5 * sin(time + star.phase));
      final paint = Paint()..color = star.baseColor.withValues(alpha: twinkle);
      canvas.drawCircle(Offset(px, py), star.radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant StarfieldPainter oldDelegate) {
    return oldDelegate.size != size;
  }
}

class _StaticStar {
  final double x;
  final double y;
  final double radius;
  final double phase;
  final Color baseColor;

  const _StaticStar({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.baseColor,
  });
}
