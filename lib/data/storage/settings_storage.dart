import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';

/// Persists [GameSettings] to a JSON file so the seed and other params
/// survive app restarts.
class SettingsStorage {
  SettingsStorage._();

  static SettingsStorage? _instance;
  static SettingsStorage get instance => _instance ??= SettingsStorage._();

  String? _cachedPath;

  Future<String> get _filePath async {
    if (_cachedPath != null) return _cachedPath!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedPath = '${dir.path}/settings.json';
    return _cachedPath!;
  }

  Future<void> save(GameSettings settings) async {
    try {
      final path = await _filePath;
      await File(path).writeAsString(jsonEncode(settings.toJson()));
    } catch (e) {
      debugPrint('Error saving settings: $e');
    }
  }

  Future<GameSettings?> load() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return null;
      final content = await file.readAsString();
      return GameSettings.fromJson(jsonDecode(content) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error loading settings: $e');
      return null;
    }
  }
}
