import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/scan_service.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';

/// A scan is **one verb**, not two.
///
/// There used to be a 4-energy scan on the planet tab and a 1-energy scan on the
/// sector panel, both setting the same `scanned` flag and showing the same
/// detail. The expensive one was strictly dominated, and the only thing it had
/// going for it was a +1 faction standing bonus — so the fix could not be "make
/// the cheap one cost more" without removing a reward, and could not be "leave it"
/// without keeping a dead path.
///
/// These guards exist because the failure mode is *structural*: two screens each
/// holding their own copy of the same five lines is how the prices diverged in
/// the first place, and nothing in the type system stops it happening again. The
/// behavioural assertions below would still pass if a third screen grew its own
/// inline copy, so the source scan at the bottom is the part that actually
/// protects the rule.
void main() {
  Player pilot({int energy = 50}) => Player(
        name: 'Tester',
        currentSectorId: 7,
        hull: 1000,
        maxHull: 1000,
        shields: 500,
        maxShields: 500,
        energy: energy,
        maxEnergy: 100,
        credits: 1000,
        maxCargo: 100,
        cargoSize: 100,
        cargoUsed: 0,
        researchPoints: 0,
        faction: FactionClass.trader,
      );

  Planet world({bool scanned = false, FactionClass? owner}) => Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: 'Jungle',
        owner: owner,
        scanned: scanned,
      );

  test('a scan costs exactly one energy', () async {
    // The headline decision: scanning is a simple act. A deeper scan that
    // reveals production figures and fleet strength will be a different verb
    // with its own price, not a surcharge on this one.
    expect(EnergyService.scanCost, 1);

    final p = pilot();
    final w = world();
    final r = await ScanService.scanPlanet(
      player: p,
      planet: w,
      onPersist: () async {},
    );
    expect(r.performed, isTrue);
    expect(p.energy - r.player.energy, EnergyService.scanCost);
  });

  test('both entry points now cost the same, because there is only one',
      () async {
    // The specific regression. Previously 4 on the planet tab and 1 on the
    // sector panel, for an identical result.
    expect(EnergyService.scanCost, 1);
    // No second scan price exists to drift.
    // (A compile error if someone reintroduces one is the strongest guard; this
    // is the belt to that braces.)
  });

  test('a scan reveals the world and is persisted', () async {
    final w = world();
    var persisted = 0;
    final r = await ScanService.scanPlanet(
      player: pilot(),
      planet: w,
      onPersist: () async => persisted++,
    );
    expect(w.scanned, isTrue, reason: 'the flag is what gates the planet tab');
    expect(persisted, 1,
        reason: 'a scan that costs energy but never saves is paid for twice');
    expect(r.performed, isTrue);
  });

  test('a second scan is free and does nothing', () async {
    final w = world(scanned: true);
    var persisted = 0;
    final p = pilot();
    final r = await ScanService.scanPlanet(
      player: p,
      planet: w,
      onPersist: () async => persisted++,
    );
    expect(r.performed, isFalse);
    expect(r.player.energy, p.energy, reason: 'no charge for a no-op');
    expect(persisted, 0, reason: 'and nothing to save');
  });

  test('a player with no energy cannot scan, and is not charged', () async {
    final w = world();
    final p = pilot(energy: 0);
    final r = await ScanService.scanPlanet(
      player: p,
      planet: w,
      onPersist: () async {},
    );
    expect(r.performed, isFalse);
    expect(w.scanned, isFalse);
    expect(r.player.energy, 0);
  });

  test('scanning an owned world earns standing with its owner', () async {
    // The reason merging the paths was not simply "delete the bonus": the reward
    // is a *diplomatic* effect, not information, so it belongs to the verb rather
    // than to the price. Both entry points now grant it, which is what stops the
    // cheap path becoming the poor one.
    final p = pilot();
    final before = p.factionStandingWith(FactionClass.duran);
    final r = await ScanService.scanPlanet(
      player: p,
      planet: world(owner: FactionClass.duran),
      onPersist: () async {},
    );
    expect(r.player.factionStandingWith(FactionClass.duran), before + 1);
  });

  test('an unowned world grants no standing to anyone', () async {
    // Asserted as a delta, not an absolute. Standing does not start at zero: an
    // untouched pilot sits at a per-faction baseline, which for a rival is
    // negative. An absolute assertion here tested the fixture's starting point
    // rather than the rule, and its failure would have named a number that looks
    // like a bug in the scan.
    final p = pilot();
    final before = p.factionStandingWith(FactionClass.duran);
    final r = await ScanService.scanPlanet(
      player: p,
      planet: world(),
      onPersist: () async {},
    );
    expect(r.performed, isTrue);
    expect(r.player.factionStandingWith(FactionClass.duran), before,
        reason: 'there is no owner to be diplomatic toward');
  });

  test('the scan is logged', () async {
    // Cleared first: ActionLogProvider is a process-wide ring that outlives the
    // test which filled it, so reading it without clearing finds someone else's
    // line and the assertion vouches for the wrong scan.
    ActionLogProvider.global.clear();
    await ScanService.scanPlanet(
      player: pilot(),
      planet: world(),
      onPersist: () async {},
    );
    final messages =
        ActionLogProvider.global.entries.map((e) => e.message).toList();
    expect(messages.where((m) => m.contains('Scan complete')), hasLength(1));
    expect(messages.first, contains('Xandor'));
  });

  /// `flutter test` runs with the package root as the working directory, which
  /// is the convention `gravity_wiring_test.dart` uses for its source scans.
  String code(String path) => File(path)
      .readAsStringSync()
      .split('\n')
      // Comments stripped, and that is load-bearing rather than fussy: most of
      // this file's value is *comments about* the rule, and a scan that matched
      // those would fail the moment somebody documented what they were checking.
      // A source scan is answered by prose, so it has to exclude prose.
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  group('no screen keeps its own copy of the rule', () {
    // A source scan, which is normally the wrong tool. It is the right one here
    // for a structural fact: that the five lines of a scan live in one file. A
    // behavioural test cannot see a *third* inline copy, and a third copy is
    // exactly how the two prices diverged in the first place.
    //
    // What is being asked is "does anyone outside the service set `scanned` or
    // spend a scan's energy", not anything about prose in a comment.
    test('only ScanService sets the scanned flag or charges for a scan', () {
      for (final path in const [
        'lib/screens/planet_screen.dart',
        'lib/widgets/sector_view_widgets/sector_interaction_panel.dart',
      ]) {
        final src = code(path);
        expect(src.contains('ScanService.scanPlanet'), isTrue,
            reason: '$path should go through the shared verb');
        expect(src, isNot(contains('.scanned = true')),
            reason:
                '$path sets the scanned flag itself \u2014 the rule has been forked');
        expect(
            src, isNot(matches(RegExp(r'spendEnergy\(\s*EnergyService\.scan'))),
            reason:
                '$path charges for a scan itself \u2014 the price has forked');
      }
    });
  });
}
