import 'package:cosmic_trader/services/game_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/faction_rankings_screen.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'support/storage_fakes.dart';

/// Fakes so the screen can be driven without the filesystem — `path_provider` is
/// unavailable in `flutter_test`. Mirrors `computer_screen_test.dart`.
class _FakePlayerStorage extends PlayerStorage {
  _FakePlayerStorage(this.players) : super.forTesting();
  final List<Player> players;
  @override
  Future<List<Player>> loadPlayers() async => players;
}

class _FakeNpcStorage extends NpcStorage {
  _FakeNpcStorage(this.npcs) : super.forTesting();
  final List<NpcShip> npcs;
  @override
  Future<List<NpcShip>> loadAll() async => npcs;
}

/// A deliberately long name. The phone-width regression below squashes the name
/// column to a few pixels, and a short name can survive that by luck; a long one
/// cannot.
const _longName = 'Bartholomew Vandersteen-Wrath';

Player _player(int i, FactionClass f, String name,
        {int credits = 400000, bool withAvatar = true}) =>
    Player(
      id: 'p$i',
      username: name,
      name: name,
      passwordHash: 'x',
      currentSectorId: 1,
      hull: 100,
      maxHull: 200,
      shields: 60,
      maxShields: 120,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: credits,
      researchPoints: 0,
      faction: f,
      avatar: !withAvatar
          ? null
          : AvatarSelection.defaultFor(f).copyWith(
              style: AvatarStyle.neutral.copyWith(tone: i % 6, hair: i % 3),
            ),
    );

NpcShip _npc(int i, FactionClass f) => NpcShip.create(
      faction: f,
      shipDef: ShipDefinition.allShips[i % ShipDefinition.allShips.length],
      currentSectorId: 1,
      startingCredits: 200000 + i * 5000,
      seed: 1000 + i,
    );

Bounty _bounty(String id, String targetId, int amount) {
  return Bounty(
    id: id,
    targetId: targetId,
    targetName: 'Target $id',
    targetFaction: 'Pirates',
    amount: amount,
    posterId: 'x',
    posterName: 'Traders Guild',
    posterFaction: 'Independent Traders Guild',
    reason: 'Testing.',
    createdAtTick: GameClock.tick,
    expiresAtTick: GameClock.tick + Bounty.ttlTicks,
  );
}

void main() {
  late List<NpcShip> npcs;

  setUp(() {
    final f = FactionClass.values;
    npcs = [for (var i = 0; i < 9; i++) _npc(i, f[i % f.length])];
    PlayerStorage.instanceForTest = _FakePlayerStorage([
      _player(0, f[0], _longName, credits: 900000),
      _player(1, f[1], 'Aysha Kell'),
      _player(2, f[2], 'Rurik Dane'),
    ]);
    NpcStorage.instanceForTest = _FakeNpcStorage(npcs);
    UniverseStorage.instanceForTest = ReadOnlyUniverse([
      Sector(id: 1, name: 'Alpha Prime', x: 0, y: 0, warpRoutes: [1, 2]),
      Sector(id: 2, name: 'Beta Reach', x: 120, y: 60, warpRoutes: [1]),
    ]);

    // `ensureLoaded` would otherwise await BountyStorage, which needs
    // path_provider and is left *pending* rather than throwing — the screen would
    // sit on its spinner forever instead of failing loudly.
    BountyBoard.global.skipDiskLoadForTest = true;
    BountyBoard.global.replaceForTest([
      // Largest first: the section sorts by amount, and only the top 5 render.
      _bounty('live', npcs.first.id, 900000),
      _bounty('gone', 'no-such-target', 500000),
    ]);
  });

  tearDown(() {
    PlayerStorage.instanceForTest = null;
    NpcStorage.instanceForTest = null;
    UniverseStorage.instanceForTest = null;
    BountyBoard.global.replaceForTest([]);
    BountyBoard.global.skipDiskLoadForTest = false;
  });

  Future<void> pump(WidgetTester tester,
      {Size size = const Size(430, 1600)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FactionRankingsScreen())),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// The card containing [title], so section-level counts are not polluted by
  /// the faces in the other sections.
  Finder cardWith(String title) =>
      find.ancestor(of: find.text(title), matching: find.byType(Card));

  testWidgets('every ranked pilot has a face, from the right side of the split',
      (tester) async {
    await pump(tester, size: const Size(1280, 1600));

    // Scoped to the Top 10 card on purpose. The Most Wanted section renders a
    // face of its own, so a global count silently includes it and the assertion
    // is really measuring two sections at once.
    final top = cardWith('Top 10 Pilots');
    expect(top, findsOneWidget);

    // The two kinds reach a portrait differently, and conflating them would be
    // the easy mistake: a player holds a *selection* (resolved by AvatarCanvas)
    // while an NPC's face is derived per-NPC and goes straight to
    // AvatarPortraitView. `AvatarCanvas` returns an `AvatarPortraitView`, so the
    // portrait count is the total and the canvas count is the players.
    //
    // One face per card, with the players a strict subset — that is the shape
    // that would break if the two routes were ever swapped.
    expect(find.descendant(of: top, matching: find.byType(AvatarPortraitView)),
        findsNWidgets(10));
    expect(find.descendant(of: top, matching: find.byType(AvatarCanvas)),
        findsNWidgets(3));
  });

  testWidgets('a player with no saved avatar still gets their species default',
      (tester) async {
    // A player who registered before the avatar system, or never customised.
    // `effectiveAvatar` resolves a default; using `avatar` directly would leave
    // the row faceless.
    final bare =
        _player(9, FactionClass.trader, 'No Portrait', withAvatar: false);
    PlayerStorage.instanceForTest = _FakePlayerStorage([bare]);
    await pump(tester, size: const Size(1280, 1600));
    expect(find.text('No Portrait'), findsOneWidget);
    expect(find.byType(AvatarCanvas), findsOneWidget);
  });

  testWidgets(
      'a bounty target in the roster gets a face; a missing one does not',
      (tester) async {
    await pump(tester, size: const Size(1280, 1600));
    final card = cardWith('Most Wanted');
    expect(card, findsOneWidget);

    // One face for the live target only. The second contract's target is not in
    // the roster, so it must fall back to the alert icon rather than to a blank
    // or an exception — a bounty stores only an id and a name.
    expect(find.descendant(of: card, matching: find.byType(AvatarPortraitView)),
        findsOneWidget);
    expect(
        find.descendant(
            of: card, matching: find.byIcon(Icons.crisis_alert_rounded)),
        findsOneWidget);
  });

  testWidgets('a destroyed NPC target gets no face, same as a missing one',
      (tester) async {
    // Matches the Bounty Board screen: a dead target is not in the live roster,
    // so the same contract looks the same in both places.
    final live = _npc(7, FactionClass.pirate);
    // `isDestroyed` is final, so the dead ship comes from `copyWith` rather than
    // by assigning after construction.
    final dead = live.copyWith(isDestroyed: true);
    NpcStorage.instanceForTest = _FakeNpcStorage([...npcs, dead]);
    BountyBoard.global.replaceForTest([_bounty('dead', dead.id, 900000)]);

    await pump(tester, size: const Size(1280, 1600));
    final card = cardWith('Most Wanted');
    expect(find.descendant(of: card, matching: find.byType(AvatarPortraitView)),
        findsNothing);
    expect(
        find.descendant(
            of: card, matching: find.byIcon(Icons.crisis_alert_rounded)),
        findsOneWidget);
  });

  testWidgets('the pilot name keeps a usable width on a phone', (tester) async {
    // The regression this file's layout work came out of. Adding a 28px face to
    // the Top 10 row did **not** overflow below the two-column threshold — the
    // `Expanded` absorbed the shortfall — it squeezed the name column to a few
    // pixels, and every name then rendered one character per line down a 4px
    // strip, making each card ~200px tall. No test failed and no overflow was
    // reported; it was only visible in a 430px screenshot.
    //
    // So this measures the rendered `Text` rather than watching for an overflow.
    // Note `setSurfaceSize` does not change `view.physicalSize`, so the width
    // has to come from a real widget's rect.
    //
    // ## What this does and does not measure
    //
    // It reads the **layout** box, not the painted output, so it would not notice
    // a name that was ellipsised away inside a box that stayed wide. That is
    // acceptable *here* because the failure being guarded is the opposite: the box
    // itself collapses when the column is squeezed, which is what a width
    // assertion sees. Verified by re-injecting the two-column-at-all-widths fault
    // and watching it fail.
    //
    // A peer review's other reservations are real and are recorded rather than
    // fixed, because each needs a different instrument: the thresholds are round
    // numbers rather than measured ones, and a raw-pixel width is sensitive to
    // `MediaQuery.textScaler` and to non-Latin scripts. The test therefore pins
    // the default scaler implicitly by not touching it — if that changes, the
    // thresholds need re-measuring, and the comment is the reminder.
    await pump(tester);

    final name = find.text(_longName);
    expect(name, findsOneWidget, reason: 'the long-named player should rank');
    expect(tester.getSize(name).width, greaterThan(80),
        reason: 'the name column collapsed — the Top 10 list is showing two '
            'columns at a width that cannot hold a rank, a face, a name, and a '
            'score bar');

    // The other half of the same collapse: squeezed into a 4px strip, the name
    // wrapped to one character per line, so its *height* exploded. Measuring the
    // rendered `Text` catches that directly, where an overflow check would not —
    // `Expanded` had absorbed the shortfall without complaint.
    expect(tester.getSize(name).height, lessThan(40),
        reason: 'the name is wrapping one character per line, which is what a '
            'collapsed column looks like');
  });

  testWidgets('the ship-class legend no longer overflows a phone',
      (tester) async {
    // Pre-existing: four legend entries in a centred Row overflowed by 162px at
    // 430px. A `Wrap` fixed it. `flutter_test` fails on a RenderFlex overflow, so
    // this is the regression guard — there is nothing to assert beyond the pump
    // not throwing.
    await pump(tester);
    expect(tester.takeException(), isNull);
  });
}
