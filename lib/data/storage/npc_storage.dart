import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/npc_ship.dart';
import '../../services/game_event_log.dart';
import 'file_safe.dart';

class NpcStorage {
  static final NpcStorage _instance = NpcStorage._internal();
  factory NpcStorage() => _instance;
  NpcStorage._internal();

  static const _fileName = 'npcs.json';

  Future<File> _getFile() async {
    final directory = await getApplicationDocumentsDirectory();
    return File('${directory.path}/$_fileName');
  }

  Future<List<NpcShip>> loadAll() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) return [];
      final contents = await file.readAsString();
      if (contents.isEmpty) return [];
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
      return roster;
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAll(List<NpcShip> npcs) async {
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
