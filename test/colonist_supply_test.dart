import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:flutter_test/flutter_test.dart';

/// A generated universe, so the homeworld fixtures are real rather than
/// hand-built. One helper because every test here needs the same thing and a
/// second copy of a 20-line `GameSettings` literal is a second thing to forget.
List<Sector> _universe({required int seed, int sectors = 100}) =>
    UniverseGenerator(GameSettings(
      totalSectors: sectors,
      seed: seed,
      rawSeed: '$seed',
      portDensity: 0.35,
      planetDensity: 0.25,
      anomalyDensity: 0.10,
      hardwareEmporiumDensity: 0.05,
      traderDensity: 0.12,
      duranDensity: 0.10,
      vinariDensity: 0.08,
      pirateDensity: 0.05,
      fedSpaceEnd: 9,
      bubbleChance: 0.15,
      maxBubbleSize: 6,
      pct1Warp: 0.10,
      pct2Warp: 0.30,
      pct3Warp: 0.28,
      pct4Warp: 0.15,
      pct5Warp: 0.10,
      pct6Warp: 0.05,
      pct7Warp: 0.02,
      anomalyTypes: const ['Nebula'],
    )).generate();

void main() {
  group('distance to an unreachable capital', () {
    // **The unreachable clamp was dead code.** `hopsBetween` guarded on
    // `PathfindingService.distance(...) <= 0`, and that function returns the
    // sentinel **9999** for "no route" — never zero. So the guard never fired and
    // an existing-but-unreachable capital priced colonists at
    // `15 x 9999^1.5` = 14,997,750 cr each, against 624 at the intended
    // `unreachableHops` of 12. A thousand colonists came to 15 billion.
    //
    // It also meant the *orphan* fallback never engaged for this case, because
    // `isOrphan` is about having no capital at all, not an unreachable one — two
    // different failures behind one guard.
    test('is priced as the worst case, not as the sentinel', () {
      // Two sectors that share no warp: 1 knows nobody, 2 knows nobody.
      final disconnected = [
        Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const []),
        Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const []),
      ];
      final hops = ColonistSupply.hopsBetween(disconnected, 1, 2);
      expect(hops, ColonistSupply.unreachableHops,
          reason: 'an unreachable capital must clamp to the worst case');
      expect(hops, isNot(9999),
          reason: 'the pathfinder sentinel is not a distance');
    });

    test('and the price is the clamp price, not fifteen million', () {
      final atClamp =
          ColonistSupply.pricePerColonist(ColonistSupply.unreachableHops);
      expect(atClamp, lessThan(2000), reason: '624 at the time of writing');
      // The figure the dead guard produced, so a regression names itself.
      final atSentinel = ColonistSupply.pricePerColonist(9999);
      expect(atSentinel, greaterThan(10000000),
          reason: 'this is what the bug looked like: ~15M cr per colonist');
    });

    test('a reachable pair still measures real hops', () {
      // The fix must not break the ordinary case.
      final chain = [
        Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const [2]),
        Sector(id: 2, name: 'B', x: 1, y: 0, warpRoutes: const [1, 3]),
        Sector(id: 3, name: 'C', x: 2, y: 0, warpRoutes: const [2]),
      ];
      expect(ColonistSupply.hopsBetween(chain, 1, 2), 1);
      expect(ColonistSupply.hopsBetween(chain, 1, 3), 2);
    });

    test('a sector is zero hops from itself, reported as one', () {
      final chain = [
        Sector(id: 1, name: 'A', x: 0, y: 0, warpRoutes: const []),
      ];
      expect(ColonistSupply.hopsBetween(chain, 1, 1), 1,
          reason: 'one, not zero — a zero-hop shipment would be free');
    });
  });

  group('distance pricing', () {
    test('costs more the further the colony is from Terra', () {
      var previous = 0;
      for (var hops = 1; hops <= 12; hops++) {
        final price = ColonistSupply.pricePerColonist(hops);
        expect(price, greaterThan(previous),
            reason: 'hop $hops must not be cheaper than hop ${hops - 1}');
        previous = price;
      }
    });

    test('distance is a real multiplier, not a rounding difference', () {
      // The galaxy is compact (median 4 hops, max 8), so a linear premium is
      // nearly invisible. This is the guard on that: if the exponent is ever
      // flattened to 1, the spread collapses and distance stops mattering.
      final near = ColonistSupply.pricePerColonist(1);
      final far = ColonistSupply.pricePerColonist(8);
      expect(far / near, greaterThan(10),
          reason: 'an 8-hop colony must cost far more than a 1-hop one');
    });

    test('the old flat rate is gone', () {
      // 20 credits flat made 500,000 credits buy 25,000 colonists instantly.
      // There should be no hop count at which a colonist costs 20.
      for (var hops = 1; hops <= 12; hops++) {
        expect(ColonistSupply.pricePerColonist(hops), isNot(20),
            reason: 'hop $hops still prices at the old flat rate');
      }
    });

    test('scales the total with the batch', () {
      expect(ColonistSupply.costFor(10, 4),
          10 * ColonistSupply.pricePerColonist(4));
      expect(ColonistSupply.costFor(0, 4), 0);
    });

    test('handles a zero or negative hop count', () {
      expect(ColonistSupply.pricePerColonist(0),
          ColonistSupply.pricePerColonist(1));
      expect(ColonistSupply.pricePerColonist(-5),
          ColonistSupply.pricePerColonist(1));
    });
  });

  group('hops', () {
    test('measures the real BFS distance from Terra Prime', () {
      final sectors = _universe(seed: 7);

      for (final s in sectors) {
        final hops = ColonistSupply.hopsBetween(sectors, 1, s.id);
        expect(hops, greaterThan(0), reason: 'sector ${s.id} got $hops');
        expect(hops, lessThanOrEqualTo(ColonistSupply.unreachableHops));
      }
    });

    test('Terra Prime itself is one hop, not zero', () {
      final sectors = _universe(seed: 7);

      expect(
        ColonistSupply.hopsBetween(sectors, ColonistSupply.terraPrimeSectorId,
            ColonistSupply.terraPrimeSectorId),
        1,
        reason: 'a world is one hop from itself, not zero',
      );
    });
  });

  group('colonists come from the faction\'s own homeworld', () {
    // The lore argument, asserted. A Duran Hegemony player drawing human
    // colonists off a general pool is not an abstraction — it is the thing the
    // faction is described as doing. Each faction supplies from its own capital.
    test('each faction is supplied by its own homeworld, not a shared pool',
        () {
      final sectors = _universe(seed: 11, sectors: 100);

      for (final faction in [
        FactionClass.duran,
        FactionClass.vinari,
        FactionClass.trader
      ]) {
        final source = ColonistSupply.sourceFor(sectors, faction);
        expect(source.isHomeworld, isTrue,
            reason: '$faction should be drawing from its own capital');
        expect(source.isOrphan, isFalse);

        // `.homeworld`, not `primaryPlanet`: a capital can sit in any slot of a
        // three-world sector, and grabbing slot 0 would test a neighbour while
        // the assertion still passed on `homeworldOf` being wrong.
        final planet =
            sectors.firstWhere((s) => s.id == source.sectorId).homeworld!;
        expect(planet.homeworldOf, faction,
            reason: '${faction.name} was pointed at ${planet.name}, which is '
                '${planet.homeworldOf?.name}');
        expect(planet.owner, faction);
      }
    });

    test('the sources are different worlds, not one pool', () {
      final sectors = _universe(seed: 11, sectors: 100);
      final ids = [FactionClass.duran, FactionClass.vinari, FactionClass.trader]
          .map((f) => ColonistSupply.sourceFor(sectors, f).sectorId)
          .toSet();
      expect(ids.length, 3, reason: 'each faction needs its own capital');
    });

    test('a captured homeworld falls through to the reserve capital', () {
      // Already how ship production behaves; colonist supply must not diverge,
      // or a player could be denied colonists while their yard still built ships.
      final sectors = _universe(seed: 11, sectors: 100);
      final before = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      final homeSector = sectors.firstWhere((s) => s.id == before.sectorId);
      final home = homeSector.homeworld!;

      // Every world, not slot 0: the reserve capital may share a sector with the
      // primary it is standing in for.
      final backup = sectors.firstWhere((s) => s.planets.any(
          (p) => p.isBackupHomeworld && p.homeworldOf == FactionClass.duran));
      expect(backup.id, isNot(homeSector.id), reason: 'fixture needs a backup');

      home.owner = FactionClass.trader; // captured

      final after = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      expect(after.sectorId, backup.id, reason: 'the reserve takes over');
      expect(after.isHomeworld, isTrue);
      expect(after.isBackup, isTrue);
    });

    test('a destroyed homeworld does not supply colonists', () {
      final sectors = _universe(seed: 11, sectors: 100);
      final source = ColonistSupply.sourceFor(sectors, FactionClass.vinari);
      sectors.firstWhere((s) => s.id == source.sectorId).homeworld!.destroy();

      final after = ColonistSupply.sourceFor(sectors, FactionClass.vinari);
      expect(after.sectorId, isNot(source.sectorId),
          reason: 'a corpse cannot supply anybody');
    });

    test('a faction with no capital falls back to Terra at a penalty', () {
      final sectors = _universe(seed: 11, sectors: 100);
      // Strip every capital for one faction.
      // Every world in every sector. Stripping only slot 0 would leave a Duran
      // capital alive in slot 2 of some sector, the faction would keep its
      // supply, and the "no capital" premise of the test would be a fiction.
      for (final s in sectors) {
        for (final p in s.planets) {
          if (p.homeworldOf == FactionClass.duran) {
            p.isHomeworld = false;
            p.isBackupHomeworld = false;
            p.homeworldOf = null;
          }
        }
      }

      final source = ColonistSupply.sourceFor(sectors, FactionClass.duran);
      expect(source.isOrphan, isTrue);
      expect(source.sectorId, ColonistSupply.terraPrimeSectorId);
      expect(source.label, contains('exile'));
      expect(
        ColonistSupply.pricePerColonist(1, orphan: true),
        greaterThan(ColonistSupply.pricePerColonist(1)),
        reason: 'an exiled faction is expensive, not stuck',
      );
    });

    test('shipping to your own capital is the cheapest possible run', () {
      final sectors = _universe(seed: 11, sectors: 100);
      final source = ColonistSupply.sourceFor(sectors, FactionClass.trader);
      final samePlanet =
          ColonistSupply.hopsBetween(sectors, source.sectorId, source.sectorId);
      expect(samePlanet, 1);
      expect(ColonistSupply.pricePerColonist(samePlanet),
          ColonistSupply.pricePerColonist(1));
    });
  });

  group('energy is per shipment, not per colonist', () {
    test('a good engine costs less to supply an empire', () {
      final base = Player(
        name: 'T',
        currentSectorId: 1,
        hull: 1,
        maxHull: 1,
        shields: 1,
        maxShields: 1,
        cargoUsed: 0,
        maxCargo: 10,
        cargoSize: 1,
        credits: 100000,
        researchPoints: 0,
      );
      final engine3 = base.copyWith(engineEquipmentLevel: 3);
      expect(
        ColonistSupply.energyPerShipment(engine3, 6),
        lessThan(ColonistSupply.energyPerShipment(base, 6)),
        reason: 'the engine upgrade that helps you travel should help you '
            'supply too, and the two must not be separate systems',
      );
    });

    test('costs more the further you go', () {
      final p = Player(
        name: 'T',
        currentSectorId: 1,
        hull: 1,
        maxHull: 1,
        shields: 1,
        maxShields: 1,
        cargoUsed: 0,
        maxCargo: 10,
        cargoSize: 1,
        credits: 100000,
        researchPoints: 0,
      );
      expect(ColonistSupply.energyPerShipment(p, 8),
          greaterThan(ColonistSupply.energyPerShipment(p, 2)));
    });
  });
}
