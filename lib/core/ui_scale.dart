import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';

/// Info about the desktop's primary display, as probed via the platform
/// plugin (GDK monitors on Linux — works on both Wayland and X11).
class UiDisplayInfo {
  const UiDisplayInfo({required this.logicalWidth, this.visibleSize});

  /// Monitor width in application (logical) pixels — the OS/desktop scaling
  /// is already applied (4K @100% scaling → 3840, 4K @200% → 1920).
  final double logicalWidth;

  /// Work-area size (logical) minus taskbars/docks, when the platform knows it.
  final Size? visibleSize;
}

/// Global layout density — how much breathing room the interface uses.
///
/// Independent of [UiScale.scaleNotifier] (which magnifies the whole canvas):
/// density only adjusts *spacing* tokens (gaps, paddings, row/panel heights)
/// via [UiScale.spacing], so a Compact layout squeezes more content into the
/// same scaled canvas while Cozy spreads it out.
enum UiDensity {
  compact('Compact', 0.8),
  normal('Normal', 1.0),
  cozy('Cozy', 1.25);

  const UiDensity(this.label, this.spacingFactor);

  /// Display label used in the settings UI.
  final String label;

  /// Multiplier for spacing tokens ([UiScale.spacing]).
  final double spacingFactor;
}

/// Global UI magnification for the whole interface.
///
/// [scaleNotifier] is applied to the entire app canvas (panels, icons,
/// spacing, maps) via a render transform in `MaterialApp.builder`
/// (see `main.dart`). The separate font-size setting scales text on top.
class UiScale {
  UiScale._();

  /// Current UI scale applied to the entire interface (>= 1.0).
  static final ValueNotifier<double> scaleNotifier =
      ValueNotifier<double>(defaultScale);

  /// When true, the scale is auto-detected from the primary display on
  /// launch (and can be re-run via [detectSuggestedScale]).
  static final ValueNotifier<bool> autoNotifier = ValueNotifier<bool>(true);

  /// Current layout density (compact / normal / cozy).
  static final ValueNotifier<UiDensity> densityNotifier =
      ValueNotifier<UiDensity>(UiDensity.normal);

  static UiDensity get density => densityNotifier.value;

  /// Spacing token: [base] adjusted by the current density multiplier.
  ///
  /// The canvas UI scale is applied separately by the render transform, so
  /// this only needs the density factor. Use it anywhere whitespace is
  /// authored: `SizedBox(height: UiScale.spacing(12))`,
  /// `EdgeInsets.symmetric(vertical: UiScale.spacing(6))`, etc.
  static double spacing(double base) => base * density.spacingFactor;

  /// Displays this wide (logical px) map to a scale of 1.0.
  static const double referenceWidth = 2560;

  static const double minScale = 1.0;
  static const double maxScale = 2.0;
  static const double defaultScale = 1.0;
  static const double comfyScale = 1.25;
  static const double cozyScale = 1.5;

  /// Presets exposed in the settings UI: label → scale value.
  static const List<({String label, double value})> presets = [
    (label: 'Default', value: defaultScale),
    (label: 'Comfy', value: comfyScale),
    (label: 'Cozy', value: cozyScale),
    (label: 'Max', value: maxScale),
  ];

  static double get current => scaleNotifier.value;

  /// Recommended scale for a display with logical width [logicalWidth].
  /// 3840 (4K @100% scaling) → 1.5, 1920 (4K @200% scaling) → 1.0.
  static double suggestFor(double logicalWidth) {
    if (logicalWidth <= 0) return defaultScale;
    return (logicalWidth / referenceWidth).clamp(minScale, maxScale);
  }

  /// Clamps a user-supplied scale into the supported range.
  static double clampScale(double v) => v.clamp(minScale, maxScale);

  /// Probes the primary display on desktop platforms. Returns null on
  /// web/mobile or when the plugin channel is unavailable.
  static Future<UiDisplayInfo?> detectPrimaryDisplay() async {
    if (kIsWeb || !_isDesktopPlatform) return null;
    try {
      final display = await screenRetriever.getPrimaryDisplay();
      if (display.size.width <= 0) return null;
      return UiDisplayInfo(
        logicalWidth: display.size.width.toDouble(),
        visibleSize: display.visibleSize,
      );
    } catch (_) {
      return null;
    }
  }

  /// Re-runs auto-detection and returns the suggested scale (or null when
  /// the display couldn't be queried).
  static Future<double?> detectSuggestedScale() async {
    final info = await detectPrimaryDisplay();
    return info == null ? null : suggestFor(info.logicalWidth);
  }
}

/// Desktop platforms only — display probing has no web/mobile backend.
bool get _isDesktopPlatform =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows);
