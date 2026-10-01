import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';

/// `Port.regen` has a no-op short-circuit so the tick's dirty-check
/// (`regenerated != sector.port`) does not write a sector to disk that did not
/// change.
///
/// It used to read `if (!changed) return this;` with `changed` set by "this
/// commodity is below its cap". A tick a few minutes after the last regen yields
/// a tiny fraction of the 24h cycle, and `(effectiveMax * fraction).round()` is
/// **zero** for most of them — so a port that was a single unit short of full on
/// any one line allocated new maps, returned a new identity, and forced a save
/// for a numerically invisible change. The short-circuit was therefore reachable
/// only for a port that was at its cap on *every* line at once, which is the one
/// case where nothing needed saving anyway.
///
/// The guard therefore has to be about the **stored integers**, not about being
/// under a cap.
void main() {
  const hour = 60 * 60 * 1000;

  Port port({
    int supply = 999,
    int demand = 999,
    int maxSupply = 1000,
    int maxDemand = 1000,
    int lastRegen = 1000 * hour,
    int storageLevel = 0,
  }) =>
      Port(
        name: 'Test',
        portClass: PortClass.free,
        portType: 'SB',
        buyPrices: const {'minerals': 10},
        sellPrices: const {'minerals': 20},
        supply: {'minerals': supply},
        demand: {'minerals': demand},
        maxSupply: {'minerals': maxSupply},
        maxDemand: {'minerals': maxDemand},
        defenseLevel: 1,
        portCredits: 1000,
        desiredCredits: 1000,
        storageLevel: storageLevel,
      );

  group('a regen that moves nothing returns the identical instance', () {
    test('a capped port, on any number of ticks', () {
      // The whole-regen no-op. Nothing to store, so nothing to write.
      final p = port(supply: 1000, demand: 1000);
      expect(identical(p.regenTick(), p), isTrue);
      expect(identical(p.regenTick(ticks: 1000), p), isTrue);
    });

    test('a port one unit short accumulates without a false positive', () {
      // The interesting one. At 1,000 units a tick accrues 0.347 of a unit,
      // so a single tick moves no stored integer — but the fraction *is*
      // banked, so the port crosses the threshold a few ticks later rather
      // than never.
      //
      // This is why an unconditional `if (!changed) return this` was wrong: it
      // would drop the remainder and the port would sit one unit short forever.
      var p = port(supply: 999, demand: 999);
      final first = p.regenTick();
      expect(first.supply['minerals'], 999,
          reason: '0.347 of a unit is not yet a unit');
      expect(identical(first, p), isFalse,
          reason: 'the fraction moved, so the port must be written');
      p = first;
      for (var i = 0; i < 5; i++) {
        p = p.regenTick();
      }
      expect(p.supply['minerals'], 1000,
          reason: 'the carried fraction must eventually cross a whole unit');

      // The previous version of this guard asserted the *opposite* for the
      // one-unit-short case: that a single 30-second tick returned the
      // identical instance. That was true only because the increment rounded to
      // zero — i.e. because the fraction was being thrown away. Under a carried
      // fraction a tick is a real event with a small real effect, so the
      // identical-instance contract belongs to a genuinely capped port and to
      // nothing else. Both halves are asserted above, which is why deleting the
      // rounding does not leave the no-op case unguarded.
    });
  });

  group('a regen that does move something still works', () {
    test('a full day tops a port back up', () {
      final p = port(supply: 0, demand: 0);
      final regenerated = p.regenTick(ticks: PlanetClock.ticksPerDay);
      expect(regenerated.supply['minerals'], 1000);
      expect(regenerated.demand['minerals'], 1000);
      expect(identical(regenerated, p), isFalse);
    });

    test('five minutes really does move a small port, and is saved for it', () {
      // The other side of the boundary, and the reason the fix is not simply
      // \"never allocate a new map unless something moved by a lot\": 1000 * 0.00347
      // is 3.47, which rounds to 3. A genuine change must still be reported.
      final p = port(supply: 999);
      final regenerated = p.regenTick(ticks: 10);
      expect(regenerated.supply['minerals'], 1000);
      expect(identical(regenerated, p), isFalse);
    });

    test('a partial interval moves by the fraction, not the whole amount', () {
      final p = port(supply: 0);
      // 6/24 of a day is a quarter of the cap.
      final regenerated = p.regenTick(ticks: PlanetClock.ticksPerDay ~/ 4);
      expect(regenerated.supply['minerals'], 250);
    });

    test('and it cannot overshoot the cap', () {
      // 999 + a full day's worth would be 1999 without the clamp.
      final p = port(supply: 999);
      final regenerated = p.regenTick(ticks: PlanetClock.ticksPerDay);
      expect(regenerated.supply['minerals'], 1000);
    });
  });

  group('the tick-dependent quantities are not touched by regen', () {
    // The thing the balance question actually turns on: `regen` moves only the
    // rate at which a market climbs back toward its cap. It never resizes the
    // cap, and it has no knowledge of colonies, planet classes, or production.
    test('maxDemand is set at generation and only scaled by storage level', () {
      final base = port(demand: 0);
      final stocked = base.regenTick(ticks: PlanetClock.ticksPerDay);
      expect(stocked.maxDemand['minerals'], 1000,
          reason: 'a full refill does not change the ceiling');

      final upgraded = Port(
        name: 'Test',
        portClass: PortClass.free,
        portType: 'SB',
        buyPrices: const {'minerals': 10},
        sellPrices: const {'minerals': 20},
        supply: const {'minerals': 0},
        demand: const {'minerals': 0},
        maxSupply: const {'minerals': 1000},
        maxDemand: const {'minerals': 1000},
        defenseLevel: 1,
        portCredits: 1000,
        desiredCredits: 1000,
        storageLevel: 4,
      );
      expect(upgraded.effectiveMaxDemand('minerals'),
          (1000 * 1.5 * 1.5 * 1.5 * 1.5).round(),
          reason: 'the only multiplier is 1.5^storageLevel');
      expect(upgraded.maxDemand['minerals'], 1000,
          reason: 'the stored ceiling itself is never rewritten');
    });
  });
}
