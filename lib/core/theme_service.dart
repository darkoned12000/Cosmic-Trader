import 'package:flutter/material.dart';

/// Predefined theme colour schemes.
class ThemePreset {
  final String name;
  final Color seed;
  final IconData icon;

  const ThemePreset(this.name, this.seed, this.icon);
}

const List<ThemePreset> themePresets = [
  ThemePreset('Deep Space', Color(0xFF4D6BFF), Icons.dark_mode_rounded),
  ThemePreset('Nebula', Color(0xFF00BCD4), Icons.water_drop_rounded),
  ThemePreset(
      'Crimson Void', Color(0xFFD32F2F), Icons.local_fire_department_rounded),
  ThemePreset('Solar Flare', Color(0xFFFF8F00), Icons.wb_sunny_rounded),
  ThemePreset('Emerald', Color(0xFF388E3C), Icons.eco_rounded),
  ThemePreset('Void Walker', Color(0xFF546E7A), Icons.grain_rounded),
  ThemePreset(
      'Phantom Signal', Color(0xFF7B1FA2), Icons.wifi_tethering_rounded),
  ThemePreset('Deep Ocean', Color(0xFF00897B), Icons.water_rounded),
  ThemePreset('Nova Burst', Color(0xFF5C6BC0), Icons.flare_rounded),
  ThemePreset('Cosmic Rose', Color(0xFFE91E63), Icons.blur_on_rounded),
  ThemePreset('Inferno', Color(0xFFFF6F00), Icons.whatshot_rounded),
  ThemePreset('Bio-Lume', Color(0xFF00E676), Icons.brightness_5_rounded),
  ThemePreset(
      'Rust Bucket', Color(0xFF6D4C41), Icons.settings_backup_restore_rounded),
  ThemePreset('Quantum Wave', Color(0xFF536DFE), Icons.waves_rounded),
  ThemePreset('Golden Age', Color(0xFFFFAB00), Icons.auto_awesome_rounded),
];

/// Simple global notifier for runtime theme changes.
class ThemeService {
  static final ValueNotifier<Color> colorNotifier =
      ValueNotifier<Color>(themePresets[0].seed);
  static final ValueNotifier<Brightness> brightnessNotifier =
      ValueNotifier<Brightness>(Brightness.dark);
  static final ValueNotifier<String> fontFamilyNotifier =
      ValueNotifier<String>('');
  static final ValueNotifier<double> fontSizeNotifier =
      ValueNotifier<double>(14);
}
