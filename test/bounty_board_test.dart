import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

void main() {
  setUp(() => BountyBoard.resetForTest());
  tearDown(() => BountyBoard.resetForTest());

  test('post holds bounty; killer auto-collects; history kept', () {
    final board = BountyBoard.global;
    final posted = board.post(
      targetId: 'victim-1',
      targetName: 'Victim',
      targetFaction: 'trader',
      amount: 5000,
      posterId: 'poster-1',
      posterName: 'Poster',
      reason: 'unprovoked attack',
    );
    expect(posted, isNotNull);
    expect(board.totalFor('victim-1'), 5000);

    // Second poster stacks on the same head.
    board.post(
      targetId: 'victim-1',
      targetName: 'Victim',
      targetFaction: 'trader',
      amount: 3000,
      posterId: 'poster-2',
      posterName: 'Poster2',
    );
    expect(board.totalFor('victim-1'), 8000);

    // Killer collects everything at once — with the kill verified.
    final paid = board.claim(
      targetId: 'victim-1',
      killerName: 'Killer',
      targetName: 'Victim',
      verifiedKills: {'victim-1'},
    );
    expect(paid, 8000);
    expect(board.active, isEmpty);
    expect(board.paid, hasLength(1));
    expect(board.paid.first.killerName, 'Killer');

    // Nothing owed twice — even with the kill still "verified".
    expect(
      board.claim(
          targetId: 'victim-1',
          killerName: 'Killer',
          targetName: 'Victim',
          verifiedKills: {'victim-1'}),
      0,
    );
  });

  test('unverified claims are denied, even with bounties stacked', () {
    final board = BountyBoard.global;
    board.post(
      targetId: 'victim-9',
      targetName: 'Victim9',
      targetFaction: 'pirate',
      amount: 5000,
      posterId: 'p1',
      posterName: 'P1',
    );
    board.post(
      targetId: 'victim-9',
      targetName: 'Victim9',
      targetFaction: 'pirate',
      amount: 7000,
      posterId: 'p2',
      posterName: 'P2',
    );
    // Stranger with no kill: denied, bounties intact.
    expect(
      board.claim(
          targetId: 'victim-9',
          killerName: 'Grifter',
          targetName: 'Victim9',
          verifiedKills: const {}),
      0,
    );
    expect(board.totalFor('victim-9'), 12000);
    // Wrong victim id: denied.
    expect(
      board.claim(
          targetId: 'victim-9',
          killerName: 'Hunter',
          targetName: 'Victim9',
          verifiedKills: {'someone-else'}),
      0,
    );
    expect(board.totalFor('victim-9'), 12000);
  });

  test('non-positive posts rejected; unknown kills pay nothing', () {
    final board = BountyBoard.global;
    expect(
      board.post(
        targetId: 'x',
        targetName: 'X',
        targetFaction: 'pirate',
        amount: 0,
        posterId: 'p',
        posterName: 'P',
      ),
      isNull,
    );
    expect(board.active, isEmpty);
    expect(
      board.claim(
          targetId: 'nobody',
          targetName: 'Nobody',
          killerName: 'Me',
          verifiedKills: {'nobody'}),
      0,
    );
  });

  test('paid history caps at twenty', () {
    final board = BountyBoard.global;
    for (int i = 0; i < 25; i++) {
      board.post(
        targetId: 't$i',
        targetName: 'T$i',
        targetFaction: 'pirate',
        amount: 100,
        posterId: 'p',
        posterName: 'P',
      );
      board.payKiller(targetId: 't$i', killerName: 'K', targetName: 'T$i');
    }
    expect(board.paid, hasLength(20));
    expect(board.paid.first.targetName, 'T24');
  });

  test('Federation amounts scale with notoriety above 50', () {
    expect(BountyBoard.fedAmount(0), 0);
    expect(BountyBoard.fedAmount(49.9), 0);
    expect(BountyBoard.fedAmount(50), 5000);
    expect(BountyBoard.fedAmount(75), 7500);
    expect(BountyBoard.fedAmount(100), 10000);
    expect(BountyBoard.fedAmount(5000), 100000);
  });

  test('completion pays standing with posting factions', () {
    final board = BountyBoard.global;
    board.post(
      targetId: 'v',
      targetName: 'V',
      targetFaction: 'pirate',
      amount: 3000,
      posterId: 'p1',
      posterName: 'P1',
      posterFaction: 'trader',
    );
    expect(board.posterFactionsFor('v'), ['trader']);
    expect(board.posterFactionsFor('nobody'), isEmpty);
  });

  test('greedy hunters prefer marked targets over weaker ones', () async {
    final board = BountyBoard.global;
    // Two weak hostile traders in the hunter's sector; only one marked.
    final sectors = [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [11]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
    ];
    NpcShip victim(int seed, {int weaponLevel = 1}) {
      return NpcShip.create(
        faction: FactionClass.trader,
        shipDef: ShipDefinition.allShips.first,
        currentSectorId: 11,
        startingCredits: 10000,
        seed: seed,
      ).copyWith(
        personality: NpcPersonality.traderMerchant,
        weaponSlots: {'main_forward': weaponLevel},
      );
    }

    final hunter = NpcShip.create(
      faction: FactionClass.pirate,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 11,
      startingCredits: 10000,
      seed: 301,
    ).copyWith(
      personality: NpcPersonality.piratePillager,
      weaponSlots: const {'main_forward': 3},
    );
    final unmarked = victim(302);
    final marked = victim(303);
    board.post(
      targetId: marked.id,
      targetName: marked.pilotName,
      targetFaction: 'trader',
      amount: 20000,
      posterId: 'FEDERATION',
      posterName: 'Federation Marshal',
      reason: 'notoriety 80',
    );

    var roster = [hunter, unmarked, marked];
    roster[0] = NpcAiService.processTurn(roster[0], sectors, [], roster);
    // Greedy pillager (greed 0.95) takes the marked head over the weaker
    // unmarked one… both weaker than the hunter either way.
    expect(roster[0].currentGoal?.type, NpcGoalType.attack);
    expect(roster[0].currentGoal?.targetId, marked.id);
  });
}
