import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/theme_service.dart';
import 'package:cosmic_trader/screens/login_screen.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/services/audio_service.dart';
import 'package:window_manager/window_manager.dart' as window_manager;

bool get _isDesktopPlatform =>
    defaultTargetPlatform == TargetPlatform.linux ||
    defaultTargetPlatform == TargetPlatform.macOS ||
    defaultTargetPlatform == TargetPlatform.windows;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load saved settings (needed early for window prefs on desktop)
  final savedSettings = await SettingsStorage.instance.load();
  final settings = savedSettings ?? GameSettings.defaults();
  ThemeService.fontFamilyNotifier.value = settings.fontFamily;
  ThemeService.fontSizeNotifier.value = settings.fontSize;

  // Window manager only works on desktop platforms.
  if (_isDesktopPlatform) {
    try {
      await window_manager.WindowManager.instance.ensureInitialized();
      await window_manager.WindowManager.instance.waitUntilReadyToShow(
        window_manager.WindowOptions(
          size: Size(settings.resolutionWidth.toDouble(),
              settings.resolutionHeight.toDouble()),
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

class _CosmicTraderAppState extends State<CosmicTraderApp> {
  @override
  void initState() {
    super.initState();
    ThemeService.colorNotifier.addListener(_onThemeChanged);
    ThemeService.brightnessNotifier.addListener(_onThemeChanged);
    ThemeService.fontFamilyNotifier.addListener(_onThemeChanged);
    ThemeService.fontSizeNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeService.colorNotifier.removeListener(_onThemeChanged);
    ThemeService.brightnessNotifier.removeListener(_onThemeChanged);
    ThemeService.fontFamilyNotifier.removeListener(_onThemeChanged);
    ThemeService.fontSizeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cosmic Trader',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
      builder: (context, child) {
        final scale = ThemeService.fontSizeNotifier.value / 14;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: child!,
        );
      },
    );
  }

  ThemeData _buildTheme() {
    final fontFamily = ThemeService.fontFamilyNotifier.value;
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: ThemeService.colorNotifier.value,
      brightness: ThemeService.brightnessNotifier.value,
      fontFamily: fontFamily.isEmpty ? null : fontFamily,
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
