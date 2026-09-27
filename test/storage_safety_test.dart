import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_exploration_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';

// Storage review batch: corruption quarantine, write guards, id formats,
// per-player exploration isolation, concurrent generation coalescing.
// path_provider is pointed at a real temp folder (game_shell_test
// pattern) so the stores complete their I/O headlessly.
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

Future<Directory> _freshDocs() async {
  final dir = await Directory.systemTemp.createTemp('ct_storage_safety');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    _pathProviderChannel,
    (call) async => dir.path,
  );
  return dir;
}

Future<void> _cleanFiles(Directory dir) async {
  for (final name in [
    'universe.json',
    'players.json',
    'npcs.json',
    'settings.json',
    'bounties.json',
    'economy_metrics.json',
    'player_exploration.json',
  ]) {
    final file = File('${dir.path}/$name');
    if (await file.exists()) await file.delete();
  }
  for (final e in dir.listSync()) {
    if (e is File && e.path.contains('.corrupt.')) await e.delete();
  }
}

GameSettings _tinySettings({int seed = 0}) => GameSettings.defaults().copyWith(
      totalSectors: 8,
      fedSpaceEnd: 2,
      seed: seed,
      rawSeed: seed.toString(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory docs;
  setUpAll(() async {
    docs = await _freshDocs();
  });
  tearDownAll(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (docs.existsSync()) docs.deleteSync(recursive: true);
    UniverseStorage.instanceForTest = null;
  });
  setUp(() async {
    await _cleanFiles(docs);
    PlayerExplorationStorage.resetForTest();
  });

  group('corruption quarantine (C1)', () {
    test('corrupt universe quarantines; saveSectors refuses the wipe',
        () async {
      await File('${docs.path}/universe.json')
          .writeAsString('{"truncated": [1, 2,');
      final loaded = await UniverseStorage.instance.loadUniverse();
      expect(loaded, isEmpty);
      final quarantined = docs
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('universe.json.corrupt.'));
      expect(quarantined, hasLength(1));
      expect(File('${docs.path}/universe.json').existsSync(), isFalse);

      // Patching onto the failed load must not recreate a stub file.
      await UniverseStorage.instance.saveSectors([]);
      expect(File('${docs.path}/universe.json').existsSync(), isFalse);
    });

    test('missing and empty universes are benign, hasUniverse honest',
        () async {
      expect(await UniverseStorage.instance.loadUniverse(), isEmpty);
      expect(await UniverseStorage.instance.hasUniverse(), isFalse);
      await File('${docs.path}/universe.json').writeAsString('[]');
      expect(await UniverseStorage.instance.hasUniverse(), isFalse);
    });

    test('corrupt players quarantine; updatePlayer refuses the wipe', () async {
      await File('${docs.path}/players.json').writeAsString('not json at all');
      final ghost = await PlayerStorage.instance.loadPlayers();
      expect(ghost, isEmpty);
      expect(
          docs
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('players.json.corrupt.')),
          hasLength(1));

      // Unknown id and refused-write both report false, never throw.
      final fail = await PlayerStorage.instance.updatePlayer(_ghostPlayer());
      expect(fail, isFalse);
      expect(File('${docs.path}/players.json').existsSync(), isFalse);
    });

    test('corrupt roster quarantines; tick-save refuses the wipe', () async {
      await File('${docs.path}/npcs.json').writeAsString('[oops');
      expect(await NpcStorage().loadAll(), isEmpty);
      await NpcStorage().saveAll([]);
      expect(File('${docs.path}/npcs.json').existsSync(), isFalse);
    });
  });

  group('player records', () {
    test('findPlayer returns null instead of throwing', () async {
      expect(await PlayerStorage.instance.findPlayer('nobody'), isNull);
    });

    test('register mints uuid ids; unknown updates report false', () async {
      final player = await PlayerStorage.instance.register(
        'captain',
        'password',
        settings: _tinySettings(seed: 7),
      );
      expect(player.id.length, 36);
      expect(player.id.contains('-'), isTrue);

      final ghost = _ghostPlayer();
      expect(await PlayerStorage.instance.updatePlayer(ghost), isFalse);
    });
  });

  group('exploration isolation (H2/H3)', () {
    test('two players keep separate visited maps', () async {
      final store = PlayerExplorationStorage.instance;
      store.setActivePlayer('alpha');
      await store.markVisited(1);
      await store.markVisited(2);
      store.setActivePlayer('beta');
      expect(store.visited, isEmpty);
      await store.markVisited(3);
      store.setActivePlayer('alpha');
      expect(store.visited, {1, 2});
    });

    test('legacy flat files adopt to the first player', () async {
      await File('${docs.path}/player_exploration.json')
          .writeAsString('{"lastVisited": {"7": 1719999999999}}');
      final store = PlayerExplorationStorage.instance;
      await store.load();
      store.setActivePlayer('pilot-1');
      expect(store.visited, {7});
    });
  });

  group('failure-flag lifecycle (C1)', () {
    test('generation clears sticky failures and writes fresh truth', () async {
      // Poison every flag first, the way a corrupt session would.
      await File('${docs.path}/universe.json').writeAsString('{{{');
      await File('${docs.path}/npcs.json').writeAsString('{{{');
      await File('${docs.path}/players.json').writeAsString('{{{');
      expect(await UniverseStorage.instance.loadUniverse(), isEmpty);
      expect(await NpcStorage().loadAll(), isEmpty);
      expect(await PlayerStorage.instance.loadPlayers(), isEmpty);

      await SettingsStorage.instance.save(_tinySettings(seed: 7));
      await UniverseStorage.instance.ensureUniverse();

      // Fresh truth persisted despite the poisoned flags.
      expect(await UniverseStorage.instance.loadUniverse(), isNotEmpty);
      expect(await NpcStorage().loadAll(), isNotEmpty);
      // And a previously-"missing" player can register again.
      final player = await PlayerStorage.instance.register(
        'reborn',
        'password',
        settings: _tinySettings(seed: 7),
      );
      expect(player.username, 'reborn');
    });
  });

  group('concurrent generation (C2)', () {
    test('three overlapping ensureUniverse calls coalesce', () async {
      final counting = _CountingStorage();
      UniverseStorage.instanceForTest = counting;
      try {
        await SettingsStorage.instance.save(_tinySettings(seed: 7));
        await Future.wait([
          UniverseStorage.instance.ensureUniverse(),
          UniverseStorage.instance.ensureUniverse(),
          UniverseStorage.instance.ensureUniverse(),
        ]);
        expect(counting.generations, 1);
        expect(await UniverseStorage.instance.hasUniverse(), isTrue);
        expect(await UniverseStorage.instance.loadUniverse(), isNotEmpty);
        expect(await NpcStorage().loadAll(), isNotEmpty);
      } finally {
        UniverseStorage.instanceForTest = null;
      }
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}

/// Counts real generations (with an overlap-forcing delay) to prove
/// concurrent ensureUniverse calls share one run.
class _CountingStorage extends UniverseStorage {
  int generations = 0;

  @override
  Future<GameSettings> generateWithSettings(GameSettings settings) async {
    generations++;
    await Future.delayed(const Duration(milliseconds: 100));
    return super.generateWithSettings(settings);
  }
}

Player _ghostPlayer() => Player(
      id: 'ghost-id',
      name: 'Ghost',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 50,
      maxShields: 50,
      cargoUsed: 0,
      maxCargo: 20,
      cargoSize: 20,
      credits: 0,
      researchPoints: 0,
    );
