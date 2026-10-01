import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';

// A sector can hold several worlds, and nothing stops a **backup** capital for
// one faction sitting beside a **primary** capital for another. That is not a
// hypothetical layout — adding a world type to the generator reshuffles which
// sectors collide, and a `colonist_supply` test failed on exactly this shape.
//
// The bug it exposed: `sourceFor` resolved the world's *detail* through
// `Sector.homeworld`, which returns the first world flagged `isHomeworld` with
// no faction filter. For a Duran query that returned the Vinari capital's name
// and `isBackup: false`, in a sector that really did hold the Duran reserve. So
// the supply tooltip named the Guild's capital while the player was buying from
// the Hegemony's — the sector id was right and everything next to it was wrong.
//
// The guards below build that layout on purpose rather than hoping a generated
// universe produces it, which is the same discipline `multi_planet_sector_test`
// uses for "a capital is not always slot 0".

Planet _world({
  required String name,
  required FactionClass faction,
  required int sector,
  required bool backup,
}) {
  return Planet(
    name: name,
    planetType: 'Terran',
    isHomeworld: true,
    isBackupHomeworld: backup,
    homeworldOf: faction,
    owner: faction,
    population: 1000,
  );
}

Sector _sector(int id, List<Planet> planets) => Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: const [99],
      planets: planets,
    );

void main() {
  group('a backup capital beside another faction\'s primary', () {
    // Duran's *reserve* shares a sector with the Vinari *primary*, and the
    // Duran world is deliberately in slot 1 so a positional read gets it wrong
    // for a second reason.
    late List<Sector> sectors;
    late Sector shared;

    setUp(() {
      shared = _sector(20, [
        _world(
          name: 'Celestara Prime',
          faction: FactionClass.vinari,
          sector: 20,
          backup: false,
        ),
        _world(
          name: 'Kravos Reserve',
          faction: FactionClass.duran,
          sector: 20,
          backup: true,
        ),
      ]);
      // Duran's primary, in its own sector, so capture makes the reserve the
      // only candidate — the same shape as the real fallback.
      final duranPrimary = _sector(21, [
        _world(
          name: 'Kravos Prime',
          faction: FactionClass.duran,
          sector: 21,
          backup: false,
        ),
      ]);
      sectors = [shared, duranPrimary, _sector(99, const [])];
    });

    test('each faction gets its OWN world, not the sector\'s first', () {
      final duran = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      final vinari = ColonistSupply.sourceFor(sectors, FactionClass.vinari);

      expect(duran.sectorId, 21);
      expect(duran.name, 'Kravos Prime');
      expect(duran.isBackup, isFalse);

      expect(vinari.sectorId, 20);
      expect(vinari.name, 'Celestara Prime');
      expect(vinari.isBackup, isFalse);
    });

    test('capturing the primary hands over to the right reserve', () {
      // The bug's exact symptom. The Duran primary is captured, so supply must
      // fall through to `Kravos Reserve` — and report it by that name, flagged
      // as a backup. Before the fix this returned sector 20 (correct) with
      // `name: 'Celestara Prime'` and `isBackup: false` (both wrong).
      sectors.firstWhere((s) => s.id == 21).homeworld!.owner =
          FactionClass.trader;

      final after = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      expect(after.sectorId, 20);
      expect(after.name, 'Kravos Reserve',
          reason: 'not the Vinari capital that shares the sector');
      expect(after.isHomeworld, isTrue);
      expect(after.isBackup, isTrue);
    });

    test('a destroyed world of another faction is never offered', () {
      // The lookup filters on faction, so destroying the *other* faction's
      // world cannot blank out a valid source — the failure mode of resolving
      // the detail through the sector's generic homeworld.
      shared.planets.first.destroy();
      final duran = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      expect(duran.sectorId, 21);
      expect(duran.name, 'Kravos Prime');
    });

    test('and the reported name always belongs to the faction asked about', () {
      // The general property, so a new layout cannot reintroduce the mismatch.
      for (final s in sectors) {
        for (final w in s.planets.where((p) => p.isHomeworld)) {
          final src = ColonistSupply.sourceFor(sectors, w.homeworldOf!);
          if (src.sectorId != s.id) continue;
          expect(src.name, w.name,
              reason: '${w.homeworldOf} was told it buys from ${src.name}');
          expect(src.isBackup, w.isBackupHomeworld);
        }
      }
    });
  });
}
