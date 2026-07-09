import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tradewars_2050/data/models/faction.dart';
import 'package:tradewars_2050/data/models/game_settings.dart';
import 'package:tradewars_2050/data/models/player.dart';
import 'package:tradewars_2050/data/models/ship_templates.dart';
import 'package:tradewars_2050/data/storage/settings_storage.dart';

/// Handles reading/writing players.json to the device's application directory.
class PlayerStorage {
  PlayerStorage._();

  static PlayerStorage? _instance;
  static PlayerStorage get instance => _instance ??= PlayerStorage._();

  String get _playersPath => _cachedPath ??= '';
  String? _cachedPath;

  Future<String> _getBasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> get _filePath async {
    if (_playersPath.isNotEmpty) return _playersPath;
    final basePath = await _getBasePath();
    return '$basePath/players.json';
  }

  /// Load all players from disk.
  Future<List<Player>> loadPlayers() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      return list
          .map((e) => Player.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error loading players: $e');
      return [];
    }
  }

  /// Save all players to disk.
  Future<void> savePlayers(List<Player> players) async {
    try {
      final path = await _filePath;
      final file = File(path);
      final content = jsonEncode(players.map((p) => p.toJson()).toList());
      await file.writeAsString(content);
    } catch (e) {
      debugPrint('Error saving players: $e');
    }
  }

  /// Find a player by username.
  Future<Player?> findPlayer(String username) async {
    final players = await loadPlayers();
    return players.firstWhere(
      (p) => p.username.toLowerCase() == username.toLowerCase(),
      orElse: () => throw Exception('Player not found'),
    );
  }

  /// Register a new player. Ship stats derived from [shipName] template.
  Future<Player> register(
    String username,
    String password, {
    FactionClass faction = FactionClass.trader,
    String shipName = 'Starhawk Skiff',
    GameSettings? settings,
  }) async {
    final players = await loadPlayers();

    if (players
        .any((p) => p.username.toLowerCase() == username.toLowerCase())) {
      throw Exception('Username already taken');
    }

    settings ??= await SettingsStorage.instance.load();

    final shipDef = ShipDefinition.getShipByName(shipName);

    final weaponTypes = <String, String>{};
    final weaponSlots = <String, int>{};
    if (shipDef != null) {
      for (int i = 0; i < shipDef.weaponSlots.length; i++) {
        final slotName = shipDef.weaponSlots[i];
        weaponTypes[slotName] = shipDef.preferredWeapons[i].name;
        weaponSlots[slotName] = 1;
      }
    }

    final player = Player(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      username: username,
      passwordHash: Player.hashPassword(password),
      createdAt: DateTime.now(),
      name: username,
      currentSectorId: 1,
      hull: shipDef?.maxHullCapacity ?? 110,
      maxHull: shipDef?.maxHullCapacity ?? 110,
      shields: shipDef?.shields ?? 70,
      maxShields: shipDef?.maxShields ?? 70,
      cargoUsed: 0,
      maxCargo: shipDef?.maxCargo ?? 30,
      cargoSize: shipDef?.maxCargo ?? 30,
      shipDefinitionName: shipName,
      shipClass: shipDef?.shipClass ?? ShipClassType.interceptor,
      weaponTypes: weaponTypes,
      weaponSlots: weaponSlots,
      hullEquipment: shipDef?.hullType.name ?? 'patchworkComposite',
      shieldEquipment: shipDef?.shieldType.name ?? 'merchantBuckler',
      engineEquipment: shipDef?.engineType.name ?? 'juryRiggedFusion',
      hullEquipmentLevel: 1,
      shieldEquipmentLevel: 1,
      engineEquipmentLevel: 1,
      drones: settings?.initDrones ?? 0,
      maxDrones: settings?.initDrones ?? 0,
      turns: settings?.initTurns ?? 1000,
      maxTurns: settings?.initTurns ?? 1000,
      credits: settings?.initCredits ?? 1000000,
      researchPoints: 0.0,
      faction: faction,
    );

    players.add(player);
    await savePlayers(players);
    return player;
  }

  /// Login: verify credentials and return the player.
  Future<Player?> login(String username, String password) async {
    try {
      final player = await findPlayer(username);
      if (player != null && player.verifyPassword(password)) {
        return player;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Update a player record.
  Future<void> updatePlayer(Player player) async {
    final players = await loadPlayers();
    final index = players.indexWhere((p) => p.id == player.id);
    if (index != -1) {
      players[index] = player;
      await savePlayers(players);
    }
  }

  /// Load a single player by ID (for session restore).
  Future<Player?> loadPlayer(String id) async {
    try {
      final players = await loadPlayers();
      return players.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Save a single player (shorthand for update).
  Future<void> savePlayer(Player player) async {
    await updatePlayer(player);
  }

  /// Clear session data (remove player from active session tracking).
  Future<void> clearPlayer() async {
    // Session clearing is handled by the app layer;
    // this method exists as a placeholder for future session management.
  }
}
