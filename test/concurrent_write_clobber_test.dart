import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'support/storage_fakes.dart';

/// A host that rebuilds the screen on player update, like `GameShell` does.
class _Host extends StatefulWidget {
  const _Host({required this.initial});
  final Player initial;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Player player = widget.initial;
  @override
  Widget build(BuildContext context) => PlanetScreen(
        player: player,
        onPlayerUpdate: (p) => setState(() => player = p),
      );
}

/// A write that lands **during** a tick must survive the tick's write-back.
///
/// `GameTickService` loads the whole universe, runs the NPC pass over the roster
/// (seconds of BFS-heavy work at scale), then writes that snapshot back. A
/// recruit landing inside that window is overwritten by a copy taken before it
/// existed — no error, no log, and indistinguishable from the feature never
/// having worked. Reported as "credits and energy consumed, and I never see
/// information on the colonists' transportation".
void main() {
  late FaithfulUniverse store;
  late Player initial;

  Planet world() => Planet(
        id: 'w-1',
        name: 'Xandor',
        planetType: 'Jungle',
        owner: FactionClass.trader,
        scanned: true,
        level: 3,
        population: 12000,
        hull: 40000,
        maxHull: 40000,
      );

  List<Sector> galaxy() => [
        Sector(
          id: 1,
          name: 'Vionis',
          x: 0,
          y: 0,
          warpRoutes: const [7],
          planets: [
            Planet(
              id: 'hw-1',
              name: 'Vionis',
              planetType: 'Terran',
              owner: FactionClass.trader,
              isHomeworld: true,
              homeworldOf: FactionClass.trader,
              scanned: true,
              level: 4,
              population: 12000,
              hull: 40000,
              maxHull: 40000,
            )
          ],
        ),
        Sector(
            id: 7,
            name: 'Kronos Reach',
            x: 0,
            y: 0,
            warpRoutes: const [1],
            planets: [world()]),
      ];

  Future<Planet> onDisk() async =>
      (await store.loadUniverse()).firstWhere((s) => s.id == 7).planets.first;

  setUp(() {
    store = FaithfulUniverse(galaxy());
    UniverseStorage.instanceForTest = store;
    addTearDown(() => UniverseStorage.instanceForTest = null);
    initial = Player(
      id: 'me',
      username: 'Vex',
      name: 'Vex',
      passwordHash: 'x',
      currentSectorId: 7,
      hull: 1000,
      maxHull: 1000,
      shields: 500,
      maxShields: 500,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 100,
      credits: 9000000,
      energy: 500,
      maxEnergy: 500,
      researchPoints: 0,
      faction: FactionClass.trader,
    );
  });

  testWidgets('a recruit survives a tick writing back a pre-recruit snapshot',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: _Host(initial: initial),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    // The tick's snapshot, taken before the purchase exists.
    final tickSnapshot = store.snapshot();

    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect((await onDisk()).colonistsInTransit, greaterThan(0));

    // The tick finishes and writes its stale snapshot over the top.
    store.writeBackSnapshot(tickSnapshot);
    expect((await onDisk()).colonistsInTransit, 0,
        reason: 'precondition: the clobber actually happened');

    // The screen's 1-second refresh must notice and re-assert, not quietly
    // adopt the loss.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect((await onDisk()).colonistsInTransit, greaterThan(0),
        reason:
            'the purchase must be restored to disk, not just to the screen');
    expect(find.textContaining('colonists en route'), findsOneWidget,
        reason: 'and the panel must still be telling the player it is coming');
  });

  testWidgets('the mitigation converges across REPEATED clobbers',
      (tester) async {
    // A tick whose pass takes longer than its own 30s interval never sleeps:
    // `processTickNow` skips overlapping fires, so every screen write lands
    // inside a load→save window. That turns an intermittent race into a
    // certainty, and it is the strongest explanation for a 100% failure rate.
    // So the mitigation has to survive being clobbered over and over, not once.
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: _Host(initial: initial),
    ));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    final tickSnapshot = store.snapshot();
    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    for (var round = 0; round < 4; round++) {
      store.writeBackSnapshot(tickSnapshot);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect((await onDisk()).colonistsInTransit, greaterThan(0),
          reason: 'round $round: the shipment must be back on disk');
      expect(find.textContaining('colonists en route'), findsOneWidget,
          reason: 'round $round: and still on screen');
    }
  });

  test('the mechanism: a stale whole-universe write does clobber a fresh one',
      () async {
    // The raw storage behaviour the reconciliation exists for. If this ever stops
    // being true, the reconciliation is dead weight and should be reconsidered —
    // but do not delete it without deleting the screen's intent-tracking too.
    final snapshot = await store.loadUniverse();
    final fresh = await store.loadUniverse();
    // Sector 7, not `first`: `galaxy()` puts the homeworld in slot 0, and the
    // whole point is that a sector can hold several worlds.
    fresh.firstWhere((s) => s.id == 7).planets.first.dispatchColonists(100);
    await store.saveSectors(fresh);
    expect((await onDisk()).colonistsInTransit, 100);

    await store.saveUniverse(snapshot);
    expect((await onDisk()).colonistsInTransit, 0,
        reason: 'a whole-universe write from a stale snapshot overwrites newer '
            'writes — this is the hazard, and why the screen reconciles');
  });
}
