import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/warp_console.dart';

// The warp chips are dense numeric targets, and the box holds **the number and
// nothing else**.
//
// An earlier version put a 🔧/🏪 icon in each chip so a neighbouring hardware
// emporium was visible without consulting the tactical map's purple dot. It was
// a reasonable idea and the wrong one: the chips are a `Wrap` of small numeric
// targets, an avatar crowds the number and changes how the run wraps. The port
// is identified on hover instead, which keeps the box clean.
//
// The guards below therefore pin the *absence* as the primary property. An
// earlier guard counted icons, which could not tell "no icon" from "an icon
// that happens to be the right one" — the wrong shape for the requirement.

Port _port(String name, PortClass cls) => Port(
      name: name,
      portClass: cls,
      portType: null,
      buyPrices: const {},
      sellPrices: const {},
      supply: const {},
      demand: const {},
      defenseLevel: 1,
      portCredits: 1000,
      desiredCredits: 1000,
    );

Sector _sector(int id, {Port? port, List<int> warps = const [1]}) => Sector(
      id: id,
      name: 'Sector $id',
      x: 0,
      y: 0,
      warpRoutes: warps,
      hasPort: port != null,
      port: port,
      planets: [Planet(name: 'W$id', planetType: 'Terran')],
    );

Player _player() => Player(
      name: 'Cap',
      currentSectorId: 1,
      hull: 1000,
      maxHull: 1000,
      shields: 500,
      maxShields: 500,
      cargoUsed: 0,
      maxCargo: 20,
      cargoSize: 20,
      credits: 1000,
      researchPoints: 0,
      faction: FactionClass.trader,
      energy: 100,
      maxEnergy: 100,
    );

Future<void> _pump(WidgetTester tester, List<Sector> adjacent) async {
  // Adjacency is resolved from the **current** sector's warpRoutes, not the
  // neighbour's. The first fixture set every sector's warps to `[1]`, which
  // rendered an empty chip list and made the guard report "the marker never
  // renders" rather than "nothing is adjacent".
  final current = _sector(
    1,
    port: _port('Home', PortClass.federal),
    warps: adjacent.map((s) => s.id).toList(),
  );
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WarpConsole(
        currentSector: current,
        allSectors: [current, ...adjacent],
        player: _player(),
        // `OnWarpCallback` is `Future<void> Function(int)`, so the stub must be
        // async; a bare `(_) {}` returns null and the analyzer refuses it.
        onWarp: (_) async {},
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

List<ChoiceChip> _chips(WidgetTester tester) =>
    tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).toList();

void main() {
  setUpAll(() => TestWidgetsFlutterBinding.ensureInitialized());

  testWidgets('the chip is the number and nothing else', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, [
      _sector(2,
          port: _port('Forge Hardware Emporium', PortClass.hardwareEmporium)),
      _sector(3, port: _port('Orbital Market', PortClass.free)),
      _sector(4), // no port
    ]);

    final chips = _chips(tester);
    expect(chips, hasLength(3), reason: 'three neighbours, three chips');

    for (final c in chips) {
      expect(c.avatar, isNull,
          reason: 'nothing but the number goes in the box');
      expect((c.label as Text).data, matches(RegExp(r'^\d+$')),
          reason: 'the label is the sector id and no more');
    }

    // And nothing else was smuggled in as a child of the chip.
    for (final c in chips) {
      final rendered = find.descendant(
        of: find.byWidget(c),
        matching: find.byType(Icon),
      );
      expect(rendered, findsNothing, reason: 'no icon inside any warp chip');
    }
  });

  testWidgets('the port is identified on hover instead', (tester) async {
    tester.view.physicalSize = const Size(1400, 3000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await _pump(tester, [
      _sector(2,
          port: _port('Forge Hardware Emporium', PortClass.hardwareEmporium)),
      _sector(3, port: _port('Orbital Market', PortClass.free)),
      _sector(4),
    ]);

    final chips = _chips(tester);
    // The tooltip is how the emporium stays findable now that the box is clean,
    // so it carries the port's real name rather than a colour.
    expect(chips[0].tooltip, contains('Forge Hardware'));
    expect(chips[0].tooltip, contains('hardware emporium'));
    expect(chips[1].tooltip, contains('Orbital Market'));
    expect(chips[1].tooltip, isNot(contains('hardware emporium')));
    // Nothing to say about an empty rock.
    expect(chips[2].tooltip, isNull);
  });
}
