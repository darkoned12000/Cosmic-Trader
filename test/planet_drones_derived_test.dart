import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/data/models/sector.dart';

/// Drones are **derived**, not staffed, and `colonistsDrones` is the corpse of
/// the track that stopped existing.
///
/// This was never a player-visible bug: `assignedColonists` sums only the three
/// real tracks, so the 2,000 the generator used to seed were counted in the
/// reserve \u2014 which is *correct*, because they genuinely are free and there is no
/// drone track to staff. What made it worth pinning is that a field which means
/// nothing but looks live is how a rule gets transcribed twice and disagrees.
/// The removed Gas Giant was exactly that: `TypeMultipliers` said it grew organics
/// while the class spec said it grew nothing, and both suites were green.
///
/// So these are guards on the *rule*, not on the field: they fail if anyone
/// reintroduces a fourth workforce track, or starts reading the corpse.
void main() {
  test('there is no drone track to staff', () {
    // The root fact. Everything below follows from it.
    expect(PlanetClassSpec.tracks, isNot(contains('drones')));
    expect(PlanetClassSpec.tracks,
        containsAll(['minerals', 'organics', 'industrial']));
  });

  test(
      'assigning colonists counts three tracks, so legacy drone counts are free',
      () {
    // The consequence that makes the legacy field harmless rather than harmful.
    final base = Planet(
      name: 'X',
      planetType: 'Terran',
      population: 10000,
      colonistsMinerals: 3000,
      colonistsOrganics: 3000,
      colonistsIndustrial: 2000,
    );
    expect(base.assignedColonists, 8000);
    expect(base.reserveColonists, 2000);

    // Nominally "on" the dead track: still free, because it is not a track.
    base.colonistsDrones = 2000;
    expect(base.assignedColonists, 8000,
        reason: 'the legacy field must not inflate the assigned total');
    expect(base.reserveColonists, 2000);
    expect(base.assignedColonists + base.reserveColonists, base.population,
        reason: 'every colonist is accounted for exactly once');
  });

  test('drone output is derived, and does not respond to colonistsDrones', () {
    // The strongest form of the property. If a stale drone workforce could
    // change drone output, the field would not be legacy at all.
    Planet at(int drones) {
      final p = Planet(
        name: 'X',
        planetType: 'Lava',
        population: 60000,
        colonistsMinerals: 20000,
        colonistsOrganics: 20000,
        colonistsIndustrial: 20000,
        productionEfficiency: 1.0,
      );
      p.colonistsDrones = drones;
      return p;
    }

    // No staffed track named 'drones' exists at all — the getter has no branch
    // for it, so the figure is zero whatever the legacy field says.
    expect(at(0).outputPerDayFor('drones'), 0);
    expect(at(999999).outputPerDayFor('drones'), 0);

    // And drones really are produced — from the three tracks that are.
    expect(at(0).achievableMaxDroneOutputPerDay, greaterThan(0),
        reason: 'drones come from what the other three make');
    expect(at(0).achievableMaxDroneOutputPerDay,
        at(999999).achievableMaxDroneOutputPerDay,
        reason: 'a million colonists on a dead track must not make a drone');
  });

  test('the generator does not seed the legacy field', () {
    // A source scan, and deliberately so: this is a structural fact about a
    // *literal in a fixture*, which no behavioural assertion can reach without
    // generating a universe and inspecting every homeworld in it.
    final src = _code('lib/data/models/universe_generator.dart');
    expect(src, isNot(contains('colonistsDrones')),
        reason:
            'seeding the corpse buys nothing \u2014 those colonists were always '
            'in the reserve, since `assignedColonists` never counted them');
  });

  test('the workforce adjuster has no drone arm', () {
    // Scoped to **one function**, not the file. The first version asserted the
    // literal `case 'drones'` appears nowhere in `planet_screen.dart` and failed
    // on two entirely legitimate uses — the transfer switches over *stores*,
    // where drones are a real storable commodity (`storedDrones`) that can be
    // loaded into a hold. A guard broad enough to fail on correct code is a guard
    // that gets deleted rather than fixed, and the thing it was protecting is then
    // unguarded.
    final body = _code('lib/screens/planet_screen.dart');
    // The end anchor used to be `_buildColonyCard`, which is a **sibling method
    // name** — so splitting the screen out moved it away and `indexOf` returned
    // -1. Anchored to the method's own end instead: the next top-level member
    // after it in the same file.
    final start = body.indexOf('Future<void> _adjustWorkforce');
    final fn = body.substring(
      start,
      body.indexOf('\n  Widget _buildLevelUpSection(', start),
    );
    expect(fn, isNot(contains('colonistsDrones')),
        reason: 'drones are derived; the workforce adjuster must not read or '
            'write the legacy field at all');
    expect(fn, isNot(contains("'drones'")),
        reason: 'and must not accept a drone track name');
  });

  test('the legacy field still round-trips, so old saves are not corrupted',
      () {
    // The one thing it is still *for*. A save that dropped the key would load
    // fine, but a save that failed to parse would take the whole universe with
    // it, because planets are embedded in sectors.
    final w = Planet(
      id: 'w-1',
      name: 'Xandor',
      planetType: 'Terran',
      colonistsDrones: 2000,
    );
    final restored = Planet.fromJson(w.toJson());
    expect(restored.colonistsDrones, 2000);

    // And through a sector, which is how it actually loads.
    final sector = Sector(
        id: 7, name: 'K', x: 0, y: 0, warpRoutes: const [], planets: [w]);
    expect(
        Sector.fromJson(sector.toJson()).planets.first.colonistsDrones, 2000);
  });
}

/// Source with `//` line comments removed.
///
/// **Load-bearing, not fussy.** The comment left at the removed generator line
/// *names the symbol it removed*, so a scan that included prose failed on the
/// prose — which is what the first run of this guard did. A source scan is
/// answered by prose, so it has to exclude prose. Written once so the two scans
/// in this file cannot drift on how they read.
String _code(String path) => File(path)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');
