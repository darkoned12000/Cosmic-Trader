import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/screens/bounty_board_screen.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';

class _FakeNpcStorage extends NpcStorage {
  _FakeNpcStorage(this.npcs) : super.forTesting();
  final List<NpcShip> npcs;
  @override
  Future<List<NpcShip>> loadAll() async => npcs;
}

NpcShip _npc(int i, FactionClass f) => NpcShip.create(
      faction: f,
      shipDef: ShipDefinition.allShips[i % ShipDefinition.allShips.length],
      currentSectorId: 1,
      startingCredits: 200000 + i * 5000,
      seed: 1000 + i,
    );

Bounty _bounty(String id, String targetId, String targetName, int amount) =>
    Bounty(
      id: id,
      targetId: targetId,
      targetName: targetName,
      targetFaction: 'Pirates',
      amount: amount,
      posterId: 'x',
      posterName: 'Traders Guild',
      posterFaction: 'Independent Traders Guild',
      reason: 'Testing.',
      createdAtTick: GameClock.tick,
      expiresAtTick: GameClock.tick + Bounty.ttlTicks,
    );

/// The player's own mark must carry a face.
///
/// It used not to. The card resolved its portrait **only** from the NPC roster,
/// and a mark on a player has no NPC behind it — so the one row a pilot reading
/// the board is guaranteed to care about was the one row drawn without a picture,
/// which reads as a rendering fault rather than as a fact about the target. The
/// Federation posts on players from their alignment, so this row is not rare.
void main() {
  late NpcShip npc;
  late Player me;

  setUp(() {
    npc = _npc(0, FactionClass.pirate);
    me = Player(
      id: 'me-1',
      username: 'Vex',
      name: 'Vex',
      passwordHash: 'x',
      currentSectorId: 1,
      hull: 100,
      maxHull: 200,
      shields: 60,
      maxShields: 120,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: 400000,
      researchPoints: 0,
      faction: FactionClass.trader,
      avatar: AvatarSelection.defaultFor(FactionClass.trader),
    );

    NpcStorage.instanceForTest = _FakeNpcStorage([npc]);
    // `ensureLoaded` awaits BountyStorage, which needs path_provider and is left
    // *pending* rather than throwing — the screen would sit on its spinner and
    // the test would pass with nothing rendered.
    BountyBoard.global.skipDiskLoadForTest = true;
    BountyBoard.global.replaceForTest([
      _bounty('on-npc', npc.id, npc.pilotName, 900000),
      _bounty('on-me', me.id, me.name, 800000),
    ]);
  });

  tearDown(() {
    NpcStorage.instanceForTest = null;
    BountyBoard.global.replaceForTest([]);
    BountyBoard.global.skipDiskLoadForTest = false;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: BountyBoardScreen(
        player: me,
        onPlayerUpdate: (_) {},
        onBack: () {},
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('the row posted on the player carries a face', (tester) async {
    await pump(tester);

    // Both rows are present, so a row-count assertion cannot be what passes.
    expect(find.text('Vex'), findsWidgets);
    expect(find.text(npc.pilotName), findsWidgets);

    // Two marks, so exactly two faces: the NPC's and the player's.
    expect(find.byType(AvatarPortraitView), findsNWidgets(2),
        reason: 'an NPC target and a player target both need a portrait');
    expect(find.byType(AvatarCanvas), findsOneWidget,
        reason: 'the player row resolves from AvatarSelection, not the roster');
  });

  testWidgets('a target that is neither an NPC nor the player still gets none',
      (tester) async {
    // The "missing face must never be an error state" rule, preserved: adding a
    // player branch must not make the null case draw something.
    BountyBoard.global.replaceForTest([
      _bounty('on-npc', npc.id, npc.pilotName, 900000),
      _bounty('on-me', me.id, me.name, 800000),
      _bounty('on-ghost', 'nobody-9', 'Ghost', 700000),
    ]);
    await pump(tester);

    expect(find.byType(AvatarPortraitView), findsNWidgets(2));
    expect(find.byType(AvatarCanvas), findsOneWidget);
    expect(find.text('Ghost'), findsWidgets);
  });
}
