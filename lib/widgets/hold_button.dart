import 'dart:async';
import 'package:flutter/material.dart';

/// A button that fires [onPressed] on tap and repeats while held.
/// Added optional [height]/[fontSize] so the same button works both at
/// full size (elsewhere) and packed into a dense table row.
class HoldButton extends StatefulWidget {
  final bool enabled;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final String label;
  final double height;
  final double fontSize;

  const HoldButton({
    super.key,
    required this.enabled,
    required this.onPressed,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.label,
    this.height = 36,
    this.fontSize = 12,
  });

  @override
  State<HoldButton> createState() => _HoldButtonState();
}

class _HoldButtonState extends State<HoldButton> {
  Timer? _timer;

  void _startRepeat() {
    if (!widget.enabled) return;
    widget.onPressed?.call();
    const delay = Duration(milliseconds: 400);
    const interval = Duration(milliseconds: 80);
    _timer = Timer(delay, () {
      _timer = Timer.periodic(interval, (_) {
        if (!widget.enabled || !mounted) {
          _stopRepeat();
          return;
        }
        widget.onPressed?.call();
      });
    });
  }

  void _stopRepeat() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stopRepeat();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Material(
        color: widget.enabled ? widget.backgroundColor : Colors.grey.shade700,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTapDown: widget.enabled ? (_) => _startRepeat() : null,
          onTapUp: widget.enabled ? (_) => _stopRepeat() : null,
          onTapCancel: widget.enabled ? _stopRepeat : null,
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                widget.label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: widget.fontSize,
                  color:
                      widget.enabled ? widget.foregroundColor : Colors.white70,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
