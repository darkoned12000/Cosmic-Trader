import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../models/npc_ship.dart';

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
      return npcList
          .map((npc) => NpcShip.fromJson(npc as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> saveAll(List<NpcShip> npcs) async {
    try {
      final file = await _getFile();
      final data = {'npcs': npcs.map((npc) => npc.toJson()).toList()};
      await file.writeAsString(json.encode(data));
    } catch (e) {
      // Silently fail to not break universe generation
    }
  }

  List<NpcShip> findInSector(List<NpcShip> allNpcs, int sectorId) {
    return allNpcs.where((npc) => npc.currentSectorId == sectorId).toList();
  }
}
