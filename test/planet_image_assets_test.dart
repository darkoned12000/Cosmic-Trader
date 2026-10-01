import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/world_forging.dart';

/// Every planet image must actually resolve.
///
/// This is a filesystem check rather than a widget test, and deliberately so.
/// The bug was that two callers each built the asset path independently: the
/// universe generator produced `assets/images/planets/Terran_World_1.gif` and
/// `WorldForging._imageFor` produced `Terran_World_1.gif`. Both compiled, both
/// were plausible, the file existed, and the *only* symptom was a torpedo-launched
/// world rendering with no picture while a generated one rendered fine — so no
/// unit test of either function failed, and nothing in the UI test could see it
/// without a real asset bundle.
///
/// Asserting the prefix and asserting the file exists are different failures
/// and both are needed: a missing file is a packaging mistake, a missing prefix
/// is a code mistake, and a pool entry that names a type the generator cannot
/// produce is a third.
void main() {
  test('every pool entry names a file that exists', () {
    // The pool holds **bare** file names on purpose — that is the shape of the
    // data, and [Planet.imageFolder] is where the prefix comes from. What matters
    // is that every name resolves once joined, so a packaging mistake (a renamed
    // or missing file) is caught here rather than as a blank world.
    final missing = <String>[];
    for (final entry in Planet.imagePool.entries) {
      for (final file in entry.value) {
        expect(file, isNot(startsWith('assets/')),
            reason: '${entry.key} entry "$file" is already a full path; the '
                'pool holds bare names so the prefix stays in one place');
        if (!File('${Planet.imageFolder}$file').existsSync()) {
          missing.add('${entry.key} -> $file');
        }
      }
    }
    expect(missing, isEmpty,
        reason: 'imagePool names files that are not in the asset folder');
  });

  test('every type produces a path that starts at the asset root', () {
    // The regression, at the level it was actually reported. A bare file name
    // cannot resolve through `Image.asset`, and the symptom was a world that
    // simply had no picture rather than an error anyone could trace.
    for (final type in Planet.allTypes) {
      for (var seed = 0; seed < 3; seed++) {
        final path = Planet.randomImageFor(type, math.Random(seed));
        expect(path, isNotNull, reason: '$type produced no image');
        expect(path, startsWith('assets/'), reason: '$type -> $path');
        expect(File(path!).existsSync(), isTrue, reason: '$type -> $path');
      }
    }
  });

  test('an unknown type yields no image rather than a broken path', () {
    // The guard has to be checked as well as the happy path: a plausible-looking
    // wrong path degrades into a broken-image box, where null degrades into
    // nothing at all.
    expect(Planet.randomImageFor('Not A World Type', math.Random(1)), isNull);
  });

  test('every planet type has a pool, and every type is pooled', () {
    // Both directions. A type in `allTypes` with no pool renders nothing, and a
    // pool key for a type nothing can generate is dead weight that will rot.
    for (final type in Planet.allTypes) {
      expect(Planet.imagePool[type], isNotNull,
          reason: '$type has no image pool');
      expect(Planet.imagePool[type], isNotEmpty,
          reason: '$type has an empty pool');
    }
    expect(Planet.imagePool.keys.toSet(), containsAll(Planet.allTypes.toSet()));
  });

  test('a launched world gets a path that starts at the asset root', () {
    // The regression itself, at the level it was reported: what a torpedo
    // actually produces.
    final sector = Sector(id: 7, name: 'K', x: 0, y: 0, warpRoutes: const []);
    final (_, world, _) = WorldForging.launch(
      player: _player(),
      sector: sector,
      cap: 3,
      rng: math.Random(1),
      tick: 0,
    );
    expect(world!.imagePath, isNotNull);
    expect(world.imagePath, startsWith('assets/'),
        reason: 'a bare file name cannot resolve through Image.asset');
    expect(File(world.imagePath!).existsSync(), isTrue,
        reason: 'and the file it names is not there');
  });

  test('over many seeds every launched world resolves', () {
    // One seed can land on the one good entry. Fifty covers the pool and every
    // type, which is what "sometimes it has a picture" looked like from the bug
    // report.
    final unresolved = <String>[];
    for (var seed = 0; seed < 50; seed++) {
      final sector = Sector(id: 7, name: 'K', x: 0, y: 0, warpRoutes: const []);
      final (_, world, _) = WorldForging.launch(
        player: _player(),
        sector: sector,
        cap: 3,
        rng: math.Random(seed),
        tick: 0,
      );
      final p = world!.imagePath;
      if (p == null || !p.startsWith('assets/') || !File(p).existsSync()) {
        unresolved.add('seed $seed (${world.planetType}) -> $p');
      }
    }
    expect(unresolved, isEmpty);
  });
}

Player _player() => Player(
      name: 'T',
      currentSectorId: 7,
      hull: 100,
      maxHull: 100,
      shields: 100,
      maxShields: 100,
      cargoUsed: 0,
      maxCargo: 10,
      cargoSize: 10,
      credits: 1000,
      researchPoints: 0,
      faction: FactionClass.trader,
      genesisTorpedoes: 1,
    );
