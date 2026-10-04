import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
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

/// **The tick cannot clobber a screen's write, because it has nothing stale to
/// clobber it with.** The hazard this file used to guard is unrepresentable.
///
/// The bug it replaced was real and expensive. `GameTickService` loaded the whole
/// universe, ran the NPC pass over the roster (seconds of BFS-heavy work at
/// scale), then wrote that snapshot back. A recruit landing inside that window
/// was overwritten by a copy taken before it existed — no error, no log, and
/// indistinguishable from the feature never having worked. Reported as "credits
/// and energy consumed, and I never see information on the colonists'
/// transportation".
///
/// It cost roughly **400 lines** in `planet_screen.dart` to survive: an
/// `_unconfirmedShipments` intent re-asserted onto every fresh read, a bounded
/// re-dispatch window because "a missing job is clobbered, never landed", a
/// parallel ledger for withdrawals (the *infinite-money* variant, where the same
/// revenue withdrew twice), a two-stage watch for a late stale write-back, and a
/// third re-dispatch mechanism for paid-for market orders.
///
/// All of that guarded a single thing: **a second object graph existing**. Every
/// screen called `loadUniverse()` and got a fresh parse, so "stale" was something
/// the system could express. Storage now shares one graph for the session, so
/// there is no second copy, and the hazard is not merely unlikely — it cannot be
/// written down.
///
/// Two things moved rather than vanished, and it is worth knowing where:
///
/// - **End-to-end survival through the real tick** is `colonist_transit_tick_
///   test.dart`, which drives `GameTickService.processTickNow()`. That is the
///   behavioural half and it is unchanged.
/// - **The storage-level identity claim** is `shared_universe_test.dart`, which
///   drives the *real* `UniverseStorage` against a temp directory rather than a
///   double.
///
/// What is left here is the part that is specifically about the hazard: that the
/// screen and a tick pass are demonstrably looking at the same objects, and that a
/// tick pass driven to completion leaves the player's purchase alone — with no
/// injected clobber, because none is needed.
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

  /// The live world, read the way any reader would.
  Future<Planet> live() async =>
      (await store.loadUniverse()).firstWhere((s) => s.id == 7).planets.first;

  /// A `GameTickService` pass, in the shape that used to be the hazard: load,
  /// work the whole universe, write the result back.
  Future<void> tickPass() async {
    final sectors = await store.loadUniverse();
    PlanetProductionService.process(sectors);
    await store.saveUniverse(sectors);
  }

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

  Future<void> mountScreen(WidgetTester tester) async {
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
  }

  testWidgets('a screen and a tick pass are demonstrably the same world',
      (tester) async {
    await mountScreen(tester);

    // Both read the universe the way the app does — `loadUniverse`. Before the
    // shared graph these were two parses and two sets of `Planet` objects, which
    // is the whole hazard. Asserting identity here is what makes the file's
    // claim specific to *this* mechanism rather than to storage in general,
    // where `shared_universe_test.dart` already covers it.
    final asTheTickSeesIt = await store.loadUniverse();
    final tickWorld =
        asTheTickSeesIt.firstWhere((s) => s.id == 7).planets.first;

    // Sector 7, not `first`: `galaxy()` puts the homeworld in slot 0, and a
    // sector can hold several worlds — the same reason `live()` does not say
    // `first`.
    expect(identical(tickWorld, (await live())), isTrue);
  });

  testWidgets('a full tick pass leaves a screen-made purchase intact',
      (tester) async {
    await mountScreen(tester);

    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    final before = (await live()).colonistsInTransit;
    expect(before, greaterThan(0));

    // The pass that used to destroy it: work the whole universe, then write it
    // back. No injected stale snapshot, because there is no stale snapshot to
    // inject — the tick and the screen loaded the same objects.
    await tickPass();

    expect((await live()).colonistsInTransit, before,
        reason: 'the tick wrote back the world it was given, and that world '
            'contained the purchase');

    // And the panel is still telling the player their colonists are coming,
    // without any re-assertion machinery: the object it reads is the one the
    // tick just worked.
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('colonists en route'), findsOneWidget);
  });

  testWidgets('a screen adopts a REPLACED graph, so regeneration is visible',
      (tester) async {
    await mountScreen(tester);
    expect(find.text('Xandor'), findsWidgets);

    // Regeneration installs a **brand-new list**: a regenerated galaxy is
    // genuinely different sectors, not mutated ones, so `saveUniverse` adopts a
    // different list object. Sharing holds identity for the whole session with
    // exactly this one exception, and a screen that missed it would sit on the
    // old universe forever — the same "reads once in initState" staleness the
    // shared graph was supposed to end.
    final regenerated = [
      Sector(
        id: 7,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: [
          Planet(
            id: 'w-2',
            name: 'Yxvarra',
            planetType: 'Ocean',
            owner: FactionClass.trader,
            scanned: true,
            level: 1,
            population: 500,
            hull: 40000,
            maxHull: 40000,
          )
        ],
      )
    ];
    await store.saveUniverse(regenerated);

    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }

    expect(find.text('Yxvarra'), findsWidgets,
        reason: 'the screen must pick up the regenerated universe, not keep '
            'serving the one it was mounted with');
  });

  testWidgets('rolling the durable file back cannot undo a live purchase',
      (tester) async {
    await mountScreen(tester);

    // A snapshot of the stored file from before the purchase — the durable-state
    // equivalent of the old clobber, and the one thing that can still happen.
    final beforePurchase = store.snapshot();

    await tester.tap(find.text('Recruit'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect((await live()).colonistsInTransit, greaterThan(0));

    store.writeBackSnapshot(beforePurchase);

    // The **file** is rolled back. The running game is not: the graph is the
    // simulation and the file is only its durability, so a lost or stale file
    // costs progress on restart rather than the session in progress. This is the
    // inversion that makes the old test's precondition unreachable — it could not
    // observe the loss at all, because there is nothing left to lose.
    expect((await live()).colonistsInTransit, greaterThan(0),
        reason:
            'a rollback of durable state must not reach into the simulation');
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(find.textContaining('colonists en route'), findsOneWidget);
  });
}
