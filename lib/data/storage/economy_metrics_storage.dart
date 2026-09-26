import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cosmic_trader/data/storage/file_safe.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

/// File-backed economy metrics (economy_metrics.json). The live numbers
/// live in [EconomyMetrics]; this store only reads/writes the file.
/// Loaded at shell start, saved on exit — and on a server this same file
/// becomes the ongoing economy-health feed instead of a per-session log.
class EconomyMetricsStorage {
  EconomyMetricsStorage._();
  static final EconomyMetricsStorage instance = EconomyMetricsStorage._();

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/economy_metrics.json');
  }

  Future<Map<String, dynamic>?> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[EconomyMetricsStorage] Load failed: $e');
      GameEventLog.global.system('[EconomyMetricsStorage] Load failed: $e');
      return null;
    }
  }

  Future<void> save(Map<String, dynamic> json) async {
    try {
      await FileSafe.writeString(await _file(), jsonEncode(json));
    } catch (e) {
      debugPrint('[EconomyMetricsStorage] Save failed: $e');
      GameEventLog.global.system('[EconomyMetricsStorage] Save failed: $e');
    }
  }

  Future<void> clear() async {
    try {
      final file = await _file();
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
