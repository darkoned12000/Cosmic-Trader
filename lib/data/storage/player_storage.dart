import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'file_safe.dart';

/// Handles reading/writing players.json to the device's application directory.
class PlayerStorage {
  PlayerStorage._();

  static PlayerStorage? _instance;
  static PlayerStorage get instance => _instance ??= PlayerStorage._();

  String? _cachedPath;

  /// True when the last load hit a corrupt/unreadable file (storage
  /// review C1). Mutations refuse while set (see [updatePlayer],
  /// [register]): writing over a failed read would drop every other
  /// account from players.json.
  bool _lastLoadFailed = false;

  /// Clears a sticky load failure: generation paths author new truth.
  void clearLoadFailure() {
    _lastLoadFailed = false;
  }

  Future<String> _getBasePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<String> get _filePath async {
    final cached = _cachedPath;
    if (cached != null) return cached;
    final basePath = await _getBasePath();
    _cachedPath = '$basePath/players.json';
    return _cachedPath!;
  }

  /// Load all players from disk. Corrupt files are quarantined aside
  /// (recoverable) with a loud log instead of silently becoming an
  /// empty roster that later writes would cement.
  Future<List<Player>> loadPlayers() async {
    try {
      final path = await _filePath;
      final file = File(path);
      if (!await file.exists()) {
        _lastLoadFailed = false;
        return [];
      }
      final content = await file.readAsString();
      final list = jsonDecode(content) as List;
      final players =
          list.map((e) => Player.fromJson(e as Map<String, dynamic>)).toList();
      _lastLoadFailed = false;
      return players;
    } catch (e) {
      debugPrint('Error loading players: $e');
      GameEventLog.global.system(
          '[PlayerStorage] Load failed — quarantining players.json: $e');
      try {
        await FileSafe.quarantine(File(await _filePath));
      } catch (_) {}
      _lastLoadFailed = true;
      return [];
    }
  }

  /// Save all players to disk.
  Future<void> savePlayers(List<Player> players) async {
    try {
      final path = await _filePath;
      final file = File(path);
      final content = jsonEncode(players.map((p) => p.toJson()).toList());
      await FileSafe.writeString(file, content);
    } catch (e) {
      debugPrint('Error saving players: $e');
    }
  }

  /// Find a player by username. Returns null when absent — never throws
  /// for a missing name (storage review M2); corrupt files are already
  /// quarantined loudly by [loadPlayers].
  Future<Player?> findPlayer(String username) async {
    final players = await loadPlayers();
    for (final p in players) {
      if (p.username.toLowerCase() == username.toLowerCase()) return p;
    }
    return null;
  }

  /// Register a new player. Ship stats derived from [shipName] template.
  /// Refuses when the roster can't be verified (storage review C1): a
  /// failed load must never let a duplicate username through.
  ///
  /// [avatar] is the portrait chosen during account creation. A `null` (or a
  /// selection that does not belong to [faction]) falls back to that faction's
  /// curated default, so a new account is never created with an unrenderable
  /// portrait.
  Future<Player> register(
    String username,
    String password, {
    FactionClass faction = FactionClass.trader,
    String shipName = 'Starhawk Skiff',
    GameSettings? settings,
    AvatarSelection? avatar,
  }) async {
    final players = await loadPlayers();
    if (_lastLoadFailed) {
      throw Exception('Player roster unavailable — refusing registration');
    }

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
      id: const Uuid().v4(),
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
      energy: settings?.initEnergy ?? 1000,
      maxEnergy: settings?.initEnergy ?? 1000,
      credits: settings?.initCredits ?? 1000000,
      researchPoints: 0.0,
      faction: faction,
      avatar:
          (avatar ?? AvatarSelection.defaultFor(faction)).forFaction(faction),
    );

    players.add(player);
    await savePlayers(players);
    return player;
  }

  /// Login: verify credentials and return the player (null when the
  /// name is unknown or the password mismatches).
  Future<Player?> login(String username, String password) async {
    final player = await findPlayer(username);
    if (player != null && player.verifyPassword(password)) {
      return player;
    }
    debugPrint('[PlayerStorage] Login failed for "$username"');
    return null;
  }

  /// Update a player record. Returns false (loudly) when the roster
  /// failed to load or the id is absent — never silently drops
  /// accounts (storage review C1/M3).
  Future<bool> updatePlayer(Player player) async {
    final players = await loadPlayers();
    if (_lastLoadFailed) {
      debugPrint('[PlayerStorage] updatePlayer refused (failed load)');
      GameEventLog.global
          .system('[PlayerStorage] update for ${player.username} refused — '
              'roster failed to load');
      return false;
    }
    final index = players.indexWhere((p) => p.id == player.id);
    if (index == -1) {
      debugPrint('[PlayerStorage] updatePlayer: unknown id ${player.id}');
      GameEventLog.global
          .system('[PlayerStorage] update for unknown id ${player.id} ignored');
      return false;
    }
    players[index] = player;
    await savePlayers(players);
    return true;
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
  Future<bool> savePlayer(Player player) async {
    return updatePlayer(player);
  }
}
