import 'package:flutter/material.dart';

/// Dark space-themed Material 3 design for Cosmic Trader.
class TWTheme {
  TWTheme._();

  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF6C63FF), // Deep purple accent
        scaffoldBackgroundColor: const Color(0xFF0A0E17),
        cardColor: const Color(0xFF131A2B),
        dividerColor: const Color(0xFF1E2A42),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0D1220),
          indicatorColor: const Color(0xFF6C63FF),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D1220),
          elevation: 0,
          centerTitle: true,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6C63FF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1A2338),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3A5C)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A3A5C)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6C63FF), width: 2),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: const Color(0xFF1A2338),
          selectedColor: const Color(0xFF6C63FF),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Color(0xFF8892B0),
          textColor: Color(0xFFCDD6F4),
        ),
      );
}
