import 'dart:convert';
import 'dart:io';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// A capital grows its own colonists, in bulk, on a cadence.
///
/// This exists because of the **geography tax** it removes. `ColonistSupply
/// .costFor(count, hops)` is *per colonist*, and the price is `15 x hops^1.5`, so
/// 50,000 colonists cost 750,000 credits one hop from your capital and
/// **17,000,000** eight hops away. Two otherwise identical colonies therefore
/// differed by 23x on capital position alone — a lottery, not a difficulty
/// setting, and the precondition for all the level-4+ content.
///
/// A capital holding colonists turns that into a *transport* cost: the premium
/// is untouched, so distance is still a decision, but you are buying goods that
/// exist rather than conjuring them at a scarcity price.
///
/// The rules are deliberately the same as the ship yards (captured yards freeze,
/// backups idle behind a live primary, a destroyed world is silent), which is why
/// these read as a mirror of `produce` rather than a new idea.
void main() {
  Planet capital({
    String id = 'hw',
    String planetType = 'Terran',
    int level = 3,
    int population = 1000,
    bool backup = false,
    bool destroyed = false,
    FactionClass? owner,
    FactionClass faction = FactionClass.trader,
    int timer = 0,
  }) =>
      Planet(
        id: id,
        name: 'Vionis',
        planetType: planetType,
        isHomeworld: true,
        isBackupHomeworld: backup,
        homeworldOf: faction,
        owner: owner,
        level: level,
        population: population,
        productionEfficiency: 1.0,
        colonistTimer: timer,
        hull: 40000,
        maxHull: 40000,
        isDestroyed: destroyed,
      );

  /// One pass of the real tick length.
  void tick(Planet p) => RepopulationService.produceColonists([
        Sector(
          id: 1,
          name: 'Vionis',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [p],
        )
      ]);

  group('a capital produces colonists', () {
    test('on its first pass, and keeps producing', () {
      final p = capital();
      expect(p.colonistTimer, 0, reason: 'precondition: due immediately');

      tick(p);
      expect(p.population, 1000 + p.colonistInfusion);

      // And the cadence is real, not a one-shot.
      expect(p.colonistTimer, Planet.colonistInfusionTicks);
      tick(p);
      expect(p.population, 1000 + p.colonistInfusion,
          reason: 'a second pass one tick later must not infuse again');

      for (var i = 0; i < Planet.colonistInfusionTicks; i++) {
        tick(p);
      }
      expect(p.population, 1000 + 2 * p.colonistInfusion,
          reason: 'the next infusion lands once the cadence has elapsed');
    });

    test('a developed capital produces more, so levelling it pays', () {
      // The one part of the yield a player can move. Scaling by *level* rather
      // than by population is deliberate: population-scaled would compound
      // against itself, because the infusion raises the population that sets the
      // next infusion.
      final low = capital(level: 1, population: 100);
      final high = capital(level: 6, population: 100);

      tick(low);
      tick(high);

      expect(high.colonistInfusion, greaterThan(low.colonistInfusion));
      expect(high.population - 100, greaterThan(low.population - 100),
          reason: 'the better capital must actually deliver more colonists');
    });

    test('the infusion stops at the population cap, and never exceeds it', () {
      // Driven by *position*, not by running thousands of ticks. The cap is a
      // ceiling, so the thing to test is the ceiling: the first version ran 4,000
      // ticks and asserted `population == colonistMax`, which failed at 68,000
      // against a 2,000,000 cap -- not because the clamp was broken but because
      // filling a Terran capital takes ~120,000 ticks. Running the arithmetic to
      // its conclusion would be a slow way to ask about a clamp.
      //
      // `Toxic` because its base cap is the smallest in the table, so the numbers
      // stay legible.
      final p = capital(planetType: 'Toxic', level: 1, population: 0);
      expect(p.colonistMax, 100000, reason: 'precondition: smallest cap');
      expect(p.colonistMax, p.baseColonistMax,
          reason: 'precondition: level 1 is unscaled');

      // Just short of the ceiling, so one infusion has to be clamped.
      p.population = p.colonistMax - 100;
      expect(p.colonistInfusion, greaterThan(100),
          reason: 'precondition: a full infusion would have overshot');

      tick(p);
      expect(p.population, p.colonistMax,
          reason: 'clamped to the room left, not added in full and overshot');

      // And a full capital says it has nothing to give rather than reporting work
      // it did not do. The timer still resets -- an infusion is a cadence, not a
      // queue, which is the rule the ship yards already follow at their cap.
      final full = p.population;
      tick(p);
      expect(p.population, full);
      expect(
          RepopulationService.produceColonists([
            Sector(
              id: 1,
              name: 'Vionis',
              x: 0,
              y: 0,
              warpRoutes: const [],
              planets: [p],
            )
          ]),
          isEmpty,
          reason: 'a full capital must not claim it infused');
    });
  });

  group('the gating matches the ship yards', () {
    test('a captured capital produces nothing', () {
      final p = capital(owner: FactionClass.duran);
      tick(p);
      expect(p.population, 1000);
      // And the countdown does not run either — "run cold", not "run and discard".
      expect(p.colonistTimer, 0);
    });

    test('a destroyed capital produces nothing', () {
      final p = capital(destroyed: true);
      tick(p);
      expect(p.population, 1000);
    });

    test('a backup idles while its primary is alive, and works once it is gone',
        () {
      final primary = capital();
      final reserve = capital(backup: true, id: 'hw2');
      final galaxy = [
        Sector(
            id: 1,
            name: 'Vionis',
            x: 0,
            y: 0,
            warpRoutes: const [],
            planets: [primary]),
        Sector(
            id: 2,
            name: 'Reserve',
            x: 0,
            y: 0,
            warpRoutes: const [],
            planets: [reserve]),
      ];

      RepopulationService.produceColonists(galaxy);
      expect(reserve.population, 1000,
          reason: 'capitals move back, they do not duplicate');

      primary.destroy();
      RepopulationService.produceColonists(galaxy);
      expect(reserve.population, greaterThan(1000),
          reason: 'with the primary gone the reserve is the capital');
    });

    test('a sector holding two capitals infuses both', () {
      // The loop iterates worlds, not sectors, for exactly this reason.
      final a = capital();
      final b = capital(faction: FactionClass.duran, id: 'hw2');
      RepopulationService.produceColonists([
        Sector(
            id: 1,
            name: 'Twin',
            x: 0,
            y: 0,
            warpRoutes: const [],
            planets: [a, b])
      ]);
      expect(a.population, greaterThan(1000));
      expect(b.population, greaterThan(1000));
    });
  });

  group('the countdown is durable', () {
    test('it survives a JSON round trip', () {
      // **This is the guard that matters.** A timer that lives only in memory is
      // not a countdown: it reloads at full and the infusion is deferred forever.
      // That is the `productionRemainder` bug exactly — 13 of 26 production
      // tracks banked literally nothing, and every test held one long-lived
      // `Planet` across its ticks so the suite was green throughout and could not
      // see it by construction.
      //
      // So this deliberately does **not** reload through any storage: it encodes
      // and decodes the JSON by hand, because a caller that goes via
      // `loadUniverse()` would be handed a live object graph and would prove
      // nothing about durability.
      final p = capital()..colonistTimer = 137;
      final decoded = Planet.fromJson(
          jsonDecode(jsonEncode(p.toJson())) as Map<String, dynamic>);

      expect(decoded.colonistTimer, 137);
      expect(decoded.colonistInterval, p.colonistInterval);

      // And the meaning survives, not just the number: a reloaded capital is still
      // N ticks from its next infusion.
      //
      // N-1 passes, not N: the timer **decrements before it is tested**, so a
      // countdown of 137 fires on the 137th pass. Looping 137 times and expecting
      // no infusion is the same off-by-one this codebase has already documented
      // twice -- a countdown that is correct for exactly N steps and not N+1.
      //
      // `start` is captured because the loop condition cannot read the timer it
      // is decrementing: on the firing pass the timer is reset to 240, which is
      // greater than the loop counter, so the loop silently runs on through to
      // the *next* firing and the assertion ends up measuring two infusions.
      final before = decoded.population;
      final start = decoded.colonistTimer;
      for (var i = 0; i < start - 1; i++) {
        tick(decoded);
      }
      expect(decoded.colonistTimer, 1, reason: 'precondition: one pass left');
      expect(decoded.population, before, reason: 'not due yet');

      tick(decoded);
      expect(decoded.population, greaterThan(before),
          reason: 'the countdown came back as a countdown, not as a fresh one');
    });

    test('a legacy save with no colonist fields still loads', () {
      final json = capital().toJson()
        ..remove('colonistTimer')
        ..remove('colonistInterval');
      final decoded = Planet.fromJson(json);
      expect(decoded.colonistTimer, 0, reason: 'due immediately on first load');
      expect(decoded.colonistInterval, Planet.colonistInfusionTicks);
    });

    test('the tick actually calls it', () {
      // A rule with no caller is not a rule, and its tests cannot tell you --
      // every test above drives `produceColonists` *directly*, so they would all
      // stay green with the call site deleted. This is the same shape as
      // `gravity_wiring_test.dart`.
      //
      // A source scan, deliberately: the question is structural (does the tick
      // invoke it) and a real tick fixture is a large thing to stand up for a
      // one-line question. The scan reads the tick's source and counts the call,
      // rather than looking for the method's own declaration, which would be
      // satisfied by the definition.
      final tickSource =
          File('lib/services/game_tick_service.dart').readAsStringSync();
      final calls = RegExp(r'RepopulationService\.produceColonists\s*\(')
          .allMatches(tickSource)
          .length;
      expect(calls, 1,
          reason: 'the colonist infusion must be driven by the tick exactly '
              'once; 0 means capitals never produce, and 2 means a double '
              'infusion nobody intended');
    });

    test('destroying a capital stops its countdown', () {
      final p = capital(timer: 50)..destroy();
      expect(p.colonistTimer, 0,
          reason: 'a corpse with a running infusion hands colonists to a world '
              'that no longer exists');
    });
  });
}
