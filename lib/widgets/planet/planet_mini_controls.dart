import 'dart:async';

import 'package:flutter/material.dart';

/// The two dense-row controls the planet screen is built from.
///
/// Extracted because **two files need them** — the screen's transfer rows and
/// the market panel — and a helper shared by two extracted files has nowhere
/// else to live. That is the same reason `_estimateMinutes` moved to
/// `GameClock` when the planet panels were split: a shared *private* helper is
/// either duplicated (and the copies drift) or promoted, and the promotion is
/// the honest outcome.

/// Hold-to-repeat `−`/`+` for a dense numeric row.
class PlanetMiniStepper extends StatelessWidget {
  const PlanetMiniStepper(this.icon, this.onPressed, {super.key});

  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return HoldRepeatIcon(
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14),
      ),
    );
  }
}

/// A small coloured action button for a dense row.
///
/// [disabledReason] is not decoration: the playtest report for these exact
/// controls was "nothing happens" — twice, once for genuinely-disabled buttons
/// whose reason was invisible. A dead button with no reason reads as a broken
/// one.
class PlanetMiniButton extends StatelessWidget {
  const PlanetMiniButton(
    this.label,
    this.color,
    this.enabled,
    this.onPressed, {
    super.key,
    this.disabledReason,
  });

  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onPressed;

  /// Why the button is dead. Null renders a bare disabled button.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: enabled ? color.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: enabled ? color : color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
    if (!enabled && disabledReason != null) {
      return Tooltip(message: disabledReason!, child: button);
    }
    return button;
  }
}

/// A bare icon button that fires once on press and repeats while held.
///
/// Mirrors `lib/widgets/hold_button.dart`'s timing (400ms before the first
/// repeat, 80ms between) but takes a [child] instead of a label, because these
/// sit as 24px squares inside a dense table row where a 36px labelled button
/// would not fit and a `FittedBox` label is pointless on a `+` glyph.
class HoldRepeatIcon extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const HoldRepeatIcon({
    required this.onPressed,
    required this.child,
    super.key,
  });

  @override
  State<HoldRepeatIcon> createState() => HoldRepeatIconState();
}

class HoldRepeatIconState extends State<HoldRepeatIcon> {
  static const _delay = Duration(milliseconds: 400);
  static const _interval = Duration(milliseconds: 80);

  Timer? _timer;

  void _start() {
    widget.onPressed();
    _timer = Timer(_delay, () {
      _timer = Timer.periodic(_interval, (_) {
        if (!mounted) {
          _stop();
          return;
        }
        widget.onPressed();
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: widget.child,
    );
  }
}
