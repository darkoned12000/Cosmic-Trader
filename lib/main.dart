import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/app_exit.dart';
import 'package:cosmic_trader/core/theme_service.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/screens/game_shell.dart';
import 'package:cosmic_trader/screens/login_screen.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/services/audio_service.dart';
import 'package:window_manager/window_manager.dart' as window_manager;

bool get _isDesktopPlatform => isDesktopPlatform();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved settings (needed early for window prefs on desktop)
  final savedSettings = await SettingsStorage.instance.load();
  final settings = savedSettings ?? GameSettings.defaults();
  ThemeService.fontFamilyNotifier.value = settings.fontFamily;
  ThemeService.fontSizeNotifier.value = settings.fontSize;
  UiScale.scaleNotifier.value = settings.uiScale;
  UiScale.autoNotifier.value = settings.uiScaleAuto;
  UiScale.densityNotifier.value = settings.uiDensity;

  // Window manager only works on desktop platforms.
  if (_isDesktopPlatform) {
    try {
      await window_manager.WindowManager.instance.ensureInitialized();

      // Probe the primary display *before* the window opens so the UI scale
      // and the default window size can adapt to the monitor. Uses GDK
      // monitors on Linux, so it works on both Wayland (Hyprland et al.)
      // and X11; tiling compositors override window sizing themselves,
      // which is fine — the scale still applies to the whole canvas.
      UiDisplayInfo? display;
      if (settings.uiScaleAuto) {
        display = await UiScale.detectPrimaryDisplay();
        if (display != null) {
          final detectedScale = UiScale.suggestFor(display.logicalWidth);
          UiScale.scaleNotifier.value = detectedScale;
          // Keep settings.json in sync with what is actually applied, so the
          // Settings screen shows the live value and a later failed probe
          // falls back to the last good detection instead of the default.
          await SettingsStorage.instance
              .save(settings.copyWith(uiScale: detectedScale));
        }
      }

      // Default window: 80% of the display's work area when auto-scaling,
      // otherwise the saved resolution.
      var windowSize = Size(settings.resolutionWidth.toDouble(),
          settings.resolutionHeight.toDouble());
      if (settings.uiScaleAuto && display?.visibleSize != null) {
        final vs = display!.visibleSize!;
        if (vs.width >= 1024 && vs.height >= 680) {
          windowSize = Size(vs.width * 0.8, vs.height * 0.8);
        }
      }

      await window_manager.WindowManager.instance.waitUntilReadyToShow(
        window_manager.WindowOptions(
          size: windowSize,
          fullScreen: settings.fullscreen,
          backgroundColor: Colors.transparent,
          skipTaskbar: false,
        ),
        () async {
          await window_manager.WindowManager.instance.show();
          await window_manager.WindowManager.instance.focus();
        },
      );
    } catch (e) {
      debugPrint('[main] window_manager init error: $e');
    }
  }

  // Pre-generate the universe on startup if it doesn't exist yet.
  // This is fire-and-forget — login won't block on it.
  UniverseStorage.instance.ensureUniverse();

  // Initialize audio service
  await AudioService.instance.init();

  runApp(const CosmicTraderApp());
}

class CosmicTraderApp extends StatefulWidget {
  const CosmicTraderApp({super.key});

  @override
  State<CosmicTraderApp> createState() => _CosmicTraderAppState();
}

class _CosmicTraderAppState extends State<CosmicTraderApp>
    with window_manager.WindowListener {
  @override
  void initState() {
    super.initState();
    ThemeService.colorNotifier.addListener(_onThemeChanged);
    ThemeService.brightnessNotifier.addListener(_onThemeChanged);
    ThemeService.fontFamilyNotifier.addListener(_onThemeChanged);
    ThemeService.fontSizeNotifier.addListener(_onThemeChanged);
    UiScale.scaleNotifier.addListener(_onThemeChanged);
    UiScale.autoNotifier.addListener(_onThemeChanged);
    UiScale.densityNotifier.addListener(_onThemeChanged);
    _registerWindowCloseGuard();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  /// Desktop-only close handling: the window's X button is disabled entirely
  /// (quitting happens through the in-app "Exit Game" buttons), and any
  /// close request that still arrives — e.g. a WM close keybind — is
  /// intercepted so the active game session can be flushed before the app
  /// terminates cleanly (no `FlutterEngineRemoveView` teardown errors).
  Future<void> _registerWindowCloseGuard() async {
    if (!isDesktopPlatform()) return;
    try {
      await window_manager.WindowManager.instance.ensureInitialized();
      window_manager.WindowManager.instance.addListener(this);
      // If a close signal still reaches the GTK delete-event, keep the
      // window open until [onWindowClose] has flushed and quit.
      await window_manager.WindowManager.instance.setPreventClose(true);
      // Remove the "x" button entirely (gtk_window_set_deletable(false)).
      await window_manager.WindowManager.instance.setClosable(false);
    } catch (e) {
      debugPrint('[main] window close guard error: $e');
    }
  }

  /// A close request slipped through (WM keybind, session end, …). Flush any
  /// active game session, then terminate quietly.
  @override
  void onWindowClose() {
    _flushAndQuit();
  }

  Future<void> _flushAndQuit() async {
    try {
      final hook = GameShell.exitSaveHook;
      if (hook != null) {
        await hook().timeout(const Duration(seconds: 10));
      }
    } catch (e) {
      debugPrint('[main] exit flush error: $e');
    }
    quitApplication();
  }

  @override
  void dispose() {
    if (isDesktopPlatform()) {
      try {
        window_manager.WindowManager.instance.removeListener(this);
        // Restore defaults in case the app is embedded/hot-restarted.
        window_manager.WindowManager.instance.setPreventClose(false);
        window_manager.WindowManager.instance.setClosable(true);
      } catch (_) {
        // Best-effort teardown.
      }
    }
    ThemeService.colorNotifier.removeListener(_onThemeChanged);
    ThemeService.brightnessNotifier.removeListener(_onThemeChanged);
    ThemeService.fontFamilyNotifier.removeListener(_onThemeChanged);
    ThemeService.fontSizeNotifier.removeListener(_onThemeChanged);
    UiScale.scaleNotifier.removeListener(_onThemeChanged);
    UiScale.autoNotifier.removeListener(_onThemeChanged);
    UiScale.densityNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosmic Trader',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
      builder: _buildScaledApp,
    );
  }

  /// Applies the font-size text scaler and the global UI magnification.
  ///
  /// UI scale works by giving the app a smaller logical canvas
  /// (`viewSize / uiScale`) and drawing it scaled up with [Transform.scale],
  /// so panels, icons, spacing and maps all grow to fill high-resolution
  /// displays. Text is scaled separately via [TextScaler] on top.
  Widget _buildScaledApp(BuildContext context, Widget? child) {
    final uiScale =
        UiScale.scaleNotifier.value.clamp(UiScale.minScale, UiScale.maxScale);
    final viewSize = MediaQuery.sizeOf(context);
    final textScale = ThemeService.fontSizeNotifier.value / 14;

    Widget content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: TextScaler.linear(textScale),
        size: uiScale <= 1.0 ? null : viewSize / uiScale,
      ),
      child: child!,
    );

    if (uiScale > 1.0) {
      content = Transform.scale(
        scale: uiScale,
        alignment: Alignment.topLeft,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: 0,
          minHeight: 0,
          maxWidth: viewSize.width / uiScale,
          maxHeight: viewSize.height / uiScale,
          child: content,
        ),
      );
    }
    return content;
  }

  ThemeData _buildTheme() {
    final fontFamily = ThemeService.fontFamilyNotifier.value;
    final density = UiScale.densityNotifier.value;
    final visualDensity = switch (density) {
      UiDensity.compact => VisualDensity.compact,
      UiDensity.normal => VisualDensity.standard,
      UiDensity.cozy => VisualDensity.comfortable,
    };
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: ThemeService.colorNotifier.value,
      brightness: ThemeService.brightnessNotifier.value,
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
      visualDensity: visualDensity,
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
