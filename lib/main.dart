import 'package:flutter/material.dart';
import 'package:tradewars_2050/core/theme_service.dart';
import 'package:tradewars_2050/screens/login_screen.dart';
import 'package:tradewars_2050/data/storage/universe_storage.dart';
import 'package:tradewars_2050/services/audio_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Pre-generate the universe on startup if it doesn't exist yet.
  // This is fire-and-forget — login won't block on it.
  UniverseStorage.instance.ensureUniverse();

  // Initialize audio service
  await AudioService.instance.init();

  runApp(const TradeWarsApp());
}

class TradeWarsApp extends StatefulWidget {
  const TradeWarsApp({super.key});

  @override
  State<TradeWarsApp> createState() => _TradeWarsAppState();
}

class _TradeWarsAppState extends State<TradeWarsApp> {
  @override
  void initState() {
    super.initState();
    ThemeService.colorNotifier.addListener(_onThemeChanged);
    ThemeService.brightnessNotifier.addListener(_onThemeChanged);
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ThemeService.colorNotifier.removeListener(_onThemeChanged);
    ThemeService.brightnessNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TradeWars 2050',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginScreen(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      useMaterial3: true,
      colorSchemeSeed: ThemeService.colorNotifier.value,
      brightness: ThemeService.brightnessNotifier.value,
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
