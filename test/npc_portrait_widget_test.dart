import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/npc_portrait.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/sector_interaction_panel.dart';

NpcShip _npc(int seed, FactionClass faction) => NpcShip.create(
      faction: faction,
      shipDef: ShipDefinition.allShips[seed % ShipDefinition.allShips.length],
      currentSectorId: 5,
      startingCredits: 5000,
      seed: seed,
    );

Player _player() => Player(
      name: 'Tester',
      currentSectorId: 5,
      hull: 100,
      maxHull: 100,
      shields: 50,
      maxShields: 50,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: 1000,
      researchPoints: 0,
    );

Sector _sector() => Sector(
      id: 5,
      name: 'Test',
      x: 100.0,
      y: 50.0,
      warpRoutes: const [6, 7],
    );

Future<void> _pumpPanel(
  WidgetTester tester, {
  required List<NpcShip> npcs,
  Size size = const Size(420, 1400),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    home: Scaffold(
      body: SectorInteractionPanel(
        currentSector: _sector(),
        npcs: npcs,
        player: _player(),
        onPlayerUpdate: (_) {},
        settings: GameSettings.defaults(),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('sector interaction panel with NPC portraits', () {
    testWidgets('shows a face for every NPC and an icon for non-NPC entries',
        (tester) async {
      await _pumpPanel(
        tester,
        npcs: [
          for (var i = 0; i < 4; i++) _npc(100 + i, FactionClass.values[i % 3]),
        ],
      );

      // One portrait per NPC, and only the NPCs — planets and hazards keep
      // their icons, because there is nothing to draw a mountain as.
      expect(
        find.byWidgetPredicate(
          (w) => w.runtimeType.toString().contains('AvatarPortraitView'),
        ),
        findsNWidgets(4),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long pilot and ship name does not overflow the tile',
        (tester) async {
      // The tile has a fixed height shared with the scroll extent, so the
      // caption inside it has to be single-line. This is the regression that
      // fixed height would otherwise invite.
      final npc = _npc(7, FactionClass.duran);
      await _pumpPanel(
        tester,
        npcs: [npc],
        size: const Size(380, 1200),
      );
      expect(find.text(npc.shipName.toUpperCase()), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'the detail caption must ellipsis, not wrap');
    });

    testWidgets('a portrait is derived per NPC, not shared across the list',
        (tester) async {
      final npcs = [
        _npc(11, FactionClass.duran),
        _npc(22, FactionClass.vinari)
      ];
      await _pumpPanel(tester, npcs: npcs);

      final ids = npcs.map((n) => NpcPortraits.of(n).id).toSet();
      expect(ids.length, npcs.length, reason: 'each NPC must get its own face');
      // And they must agree with what the derivation says, rather than the
      // panel picking a portrait some other way.
      for (final npc in npcs) {
        expect(AvatarCatalog.byId(NpcPortraits.of(npc).id), isNull,
            reason: 'NPC portraits are derived, never catalogue entries');
      }
    });

    testWidgets('selecting an NPC still shows its interaction controls',
        (tester) async {
      await _pumpPanel(tester, npcs: [_npc(5, FactionClass.trader)]);
      await tester.tap(find.text('[ SELECT ]'));
      await tester.pumpAndSettle();
      expect(find.text('[ SELECT ]'), findsNothing);
      expect(tester.takeException(), isNull,
          reason: 'the expanded tile must not overflow its fixed height');
    });

    testWidgets('works at a cramped phone size', (tester) async {
      await _pumpPanel(
        tester,
        npcs: [_npc(3, FactionClass.duran), _npc(4, FactionClass.vinari)],
        size: const Size(360, 900),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
