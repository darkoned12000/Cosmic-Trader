/// The **shared universe** invariant: one object graph, shared by reference.
///
/// Every screen and the tick used to call `loadUniverse()` and get a fresh
/// parse, so two holders of "the same" sector were mutating different `Planet`
/// objects. That isolation is the root of this project's worst bug class: a
/// writer holding a snapshot taken before someone else's change could overwrite
/// that change with no error anywhere. Roughly 400 lines of reconciliation in
/// `planet_screen.dart` existed only to survive it.
///
/// These guards drive the **real** `UniverseStorage` against a temp directory.
/// That is deliberate and is the reason `testDirectory` exists: the doubles in
/// `test/support/storage_fakes.dart` re-implement load and save, so a test
/// against one of them vouches for the double. The caching, adopting and
/// write-failure paths can be exercised for real here, and they are the
/// load-bearing part of the session now.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A one-sector, one-world universe. Small on purpose: these guards are about
/// object identity and write semantics, not about scale.
List<Sector> _universe({int population = 2000}) => [
      Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [
          Planet(
            name: 'Xandor',
            planetType: 'Lava',
            population: population,
            colonistsMinerals: 1000,
          ),
        ],
      ),
    ];

late Directory _dir;
late UniverseStorage _store;

/// Writes [sectors] to disk as `universe.json`.
///
/// Deliberately *not* routed through `saveUniverse`: seeding via the save would
/// install the fixture as the cached graph, so every test would begin already
/// loaded and `loadUniverse` would never exercise its read path. Each test
/// starts in the true session-start condition — a file on disk, nothing cached.
Future<void> _seedFile(List<Sector> sectors) async {
  await File('${_dir.path}/universe.json')
      .writeAsString(jsonEncode(sectors.map((e) => e.toJson()).toList()));
}

void main() {
  setUp(() async {
    _dir = await Directory.systemTemp.createTemp('shared_universe');
    _store = UniverseStorage();
    _store.testDirectory = _dir.path;
    await _seedFile(_universe());
  });

  tearDown(() async {
    _store.testDirectory = null;
    if (_dir.existsSync()) {
      try {
        _dir.deleteSync(recursive: true);
      } catch (_) {
        // best effort
      }
    }
  });

  group('one graph, shared by reference', () {
    test(
        'two loads are the same list, and the same Sector, and the same Planet',
        () async {
      final a = await _store.loadUniverse();
      final b = await _store.loadUniverse();

      // Not "deeply equal" — *identical*. Deep equality is what a private copy
      // passes, and the private copy is the entire bug this guards.
      expect(identical(a, b), isTrue,
          reason: 'loadUniverse returned a second object graph');
      expect(identical(a.first, b.first), isTrue,
          reason: 'the Sector was re-parsed, so a sector-level patch would '
              'still clobber');
      expect(identical(a.first.planets.first, b.first.planets.first), isTrue,
          reason: 'the Planet was re-parsed — the actual subject of every '
              'clobber bug in the project');
    });

    test(
        'a mutation through one holder is visible to the other with no re-read',
        () async {
      final screen = await _store.loadUniverse();
      final tick = await _store.loadUniverse();

      // The tick advances production on its copy.
      screen.first.planets.first.population += 500;
      await _store.saveSectors([screen.first]);

      // The screen reads the value it already has. Under the old architecture
      // this was a re-parse of the file; now it is the same object, so the
      // figure cannot be stale and there is nothing to re-read.
      expect(tick.first.planets.first.population, 2500);
    });

    test('a sector-level patch is seen by a holder of the graph', () async {
      final a = await _store.loadUniverse();
      final b = await _store.loadUniverse();

      // Genesis Torpedo style: a *foreign* sector object merged into the graph.
      final replacement = Sector(
        id: 7,
        name: 'Renamed Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: a.first.planets,
      );
      expect(await _store.saveSectors([replacement]), isTrue);

      expect(b.first.name, 'Renamed Reach');
    });
  });

  group('durability is separate from the simulation', () {
    test('a failed write leaves the graph live', () async {
      // Point the storage at a path whose parent cannot exist: a regular file
      // is not a directory, so creating `blocker/sub/` fails.
      final blocker = File('${_dir.path}/blocker')..writeAsStringSync('x');
      final broken = UniverseStorage();
      broken.testDirectory = '${blocker.path}/sub';

      // Adopt the graph, then fail to write it.
      await broken.saveUniverse(_universe());

      // Still readable and still the truth. A failed write costs durability —
      // progress on restart — not the running game.
      final after = await broken.loadUniverse();
      expect(after, hasLength(1));
      after.first.planets.first.population = 9999;
      expect(
          (await broken.loadUniverse()).first.planets.first.population, 9999);
    });

    test('the file is actually written, and a fresh storage reads it back',
        () async {
      final holder = await _store.loadUniverse();
      holder.first.traderCount = 42;
      holder.first.planets.first.population = 3210;
      await _store.saveUniverse(holder);

      // A *new* storage instance stands in for a restart.
      final relaunched = UniverseStorage()..testDirectory = _dir.path;
      final reloaded = await relaunched.loadUniverse();
      expect(reloaded.first.traderCount, 42);
      expect(reloaded.first.planets.first.population, 3210);
    });

    test('a failed load does not poison the cache with an empty universe',
        () async {
      final corrupt = UniverseStorage()..testDirectory = _dir.path;
      await File('${_dir.path}/universe.json').writeAsString('{not json');

      final first = await corrupt.loadUniverse();
      expect(first, isEmpty, reason: 'a corrupt file yields no sectors');

      // **Not** cached. "Failed to read" and "a universe with no sectors" are
      // different states; conflating them makes a corrupt file look like an
      // empty galaxy for the rest of the session, and the next write would then
      // cement the emptiness over the good data.
      expect(corrupt.sharedUniverse, isNull,
          reason: 'a failed read was cached as if it were truth');

      // And it self-heals: a good file on the next call re-establishes the
      // graph, rather than the storage being permanently stuck refusing.
      await _seedFile(_universe());
      final healed = await corrupt.loadUniverse();
      expect(healed, hasLength(1));
      expect(corrupt.sharedUniverse, isNotNull);
    });
  });

  group('lifecycle', () {
    test('deleteUniverse clears the cache, so the graph cannot resurrect it',
        () async {
      final held = await _store.loadUniverse();
      expect(held, hasLength(1));

      await _store.deleteUniverse();

      expect(_store.sharedUniverse, isNull);

      // Mutating the old graph must not bring the universe back — that is the
      // "resurrected on the next load" half of the class of bug where an
      // announcement is rolled back by a stale reload.
      held.first.traderCount = 99;
      expect(_store.sharedUniverse, isNull);
      expect(await _store.loadUniverse(), isEmpty);
    });

    test('a fresh list passed to saveUniverse becomes the graph', () async {
      // This is what lets generation need no separate wiring: the generator's
      // brand-new list is installed by the same save every other caller uses.
      await _store.loadUniverse(); // establish the old graph
      final replacement = _universe(population: 50);
      await _store.saveUniverse(replacement);

      final after = await _store.loadUniverse();
      expect(identical(after, replacement), isTrue);
      expect(after.first.planets.first.population, 50);
    });

    test('invalidateCache forces a re-read from disk', () async {
      final held = await _store.loadUniverse();
      held.first.traderCount = 77;

      _store.invalidateCache();
      final reread = await _store.loadUniverse();
      expect(reread.first.traderCount, 0,
          reason: 'the in-memory-only change leaked to a fresh read');
    });
  });
}
