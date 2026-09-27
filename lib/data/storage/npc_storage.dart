import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/npc_ship.dart';
import '../../services/game_event_log.dart';
import 'file_safe.dart';

class NpcStorage {
  static final NpcStorage _instance = NpcStorage._internal();
  factory NpcStorage() => _instance;
  NpcStorage._internal();

  static const _fileName = 'npcs.json';

  /// True when the last load hit a corrupt/unreadable file (storage
  /// review C1). [saveAll] refuses while set: the tick loads fresh
  /// every cycle, so a failed load followed by a save would empty
  /// npcs.json. Cleared by every successful or absent load.
  bool _lastLoadFailed = false;

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<NpcShip>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        _lastLoadFailed = false;
        return [];
      }
      final contents = await file.readAsString();
      if (contents.isEmpty) {
        _lastLoadFailed = false;
        return [];
      }
      final data = json.decode(contents) as Map<String, dynamic>;
      final npcList = data['npcs'] as List? ?? [];
      // Per-record parse (review batch 3, P3): one corrupt NPC used to
      // discard the entire roster. Skips are loud in the system feed.
      final roster = <NpcShip>[];
      var skipped = 0;
      for (final raw in npcList) {
        try {
          roster.add(NpcShip.fromJson(raw as Map<String, dynamic>));
        } catch (_) {
          skipped++;
        }
      }
      if (skipped > 0) {
        GameEventLog.global.system(
          '[NpcStorage] Skipped $skipped corrupt NPC record(s) '
          '(${roster.length} loaded)',
        );
      }
      _lastLoadFailed = false;
      return roster;
    } catch (e) {
      // Loud, matching this file's stated convention (storage review
      // M5): the old silent catch hid total roster loss.
      debugPrint('[NpcStorage] Load failed: $e');
      GameEventLog.global.system(
          '[NpcStorage] Load failed — quarantining npcs.json: $e');
      try {
        await FileSafe.quarantine(await _getFile());
      } catch (_) {}
      _lastLoadFailed = true;
      return [];
    }
  }

  /// Clears a sticky load failure (storage review C1): generation
  /// authors brand-new truth and must not be blocked by an old failed
  /// read. Called by [UniverseStorage.generateWithSettings].
  void clearLoadFailure() {
    _lastLoadFailed = false;
  }

  Future<void> saveAll(List<NpcShip> npcs) async {
    // Refuse after a failed load (storage review C1): the tick loads
    // fresh every cycle, so saving here would empty npcs.json. Loud,
    // and the next successful load clears the flag.
    if (_lastLoadFailed) {
      debugPrint('[NpcStorage] saveAll refused (failed load)');
      GameEventLog.global.system(
          '[NpcStorage] saveAll refused — last load failed');
      return;
    }
    try {
      final file = await _getFile();
      final data = {'npcs': npcs.map((npc) => npc.toJson()).toList()};
      await FileSafe.writeString(file, json.encode(data));
    } catch (e) {
      // Loud instead of silent (review batch 3, P3): an invisible
      // failed save is how sessions lose whole rosters.
      GameEventLog.global.system('[NpcStorage] Save failed: $e');
    }
  }

  List<NpcShip> findInSector(List<NpcShip> allNpcs, int sectorId) {
    return allNpcs.where((npc) => npc.currentSectorId == sectorId).toList();
  }
}
