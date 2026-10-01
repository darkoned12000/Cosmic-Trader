import 'package:cosmic_trader/services/game_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/bounty.dart';
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

  test('resetForNewUniverse clears marks and history', () async {
    final board = BountyBoard.global;
    board.post(
      targetId: 'victim-1',
      targetName: 'Victim',
      targetFaction: 'trader',
      amount: 5000,
      posterId: 'poster-1',
      posterName: 'Poster',
      reason: 'stale universe',
    );
    expect(board.totalFor('victim-1'), 5000);

    await board.resetForNewUniverse();
    expect(board.active, isEmpty);
    expect(board.paid, isEmpty);
    expect(board.paidLifetime, 0);
    expect(board.totalFor('victim-1'), 0);
  });

  test('paid lifetime counts past the display cap', () {
    final board = BountyBoard.global;
    for (var i = 0; i < 25; i++) {
      board.post(
        targetId: 't$i',
        targetName: 'T$i',
        targetFaction: 'pirate',
        amount: 100,
        posterId: 'p$i',
        posterName: 'P$i',
        reason: 'cap',
      );
      board.payKiller(
        targetId: 't$i',
        killerName: 'K',
        targetName: 'T$i',
      );
    }
    expect(board.paid.length, 20);
    expect(board.paidLifetime, 25);
  });

  test('poster cap, minimum amount, and cheapest-first eviction', () {
    final board = BountyBoard.global;
    // Dust amounts are refused outright.
    expect(
        board.post(
          targetId: 'dust',
          targetName: 'Dust',
          targetFaction: 'pirate',
          amount: 50,
          posterId: 'poor',
          posterName: 'Poor',
        ),
        isNull);
    expect(board.totalFor('dust'), 0);
    // Empty target ids are refused.
    expect(
        board.post(
          targetId: '',
          targetName: 'Nobody',
          targetFaction: 'pirate',
          amount: 500,
          posterId: 'poor',
          posterName: 'Poor',
        ),
        isNull);
    // Ten live marks per poster, then refusal.
    for (var i = 0; i < 11; i++) {
      board.post(
        targetId: 'c$i',
        targetName: 'C$i',
        targetFaction: 'pirate',
        amount: 500,
        posterId: 'spammer',
        posterName: 'Spammer',
      );
    }
    expect(board.active.where((b) => b.posterId == 'spammer').length,
        BountyBoard.maxBountiesPerPoster);
    // A flood of minimums evicts minimums, never the high-value head.
    board.post(
      targetId: 'whale',
      targetName: 'Whale',
      targetFaction: 'pirate',
      amount: 50000,
      posterId: 'rich',
      posterName: 'Rich',
    );
    for (var i = 0; i < BountyBoard.maxActiveBounties; i++) {
      board.post(
        targetId: 'f$i',
        targetName: 'F$i',
        targetFaction: 'pirate',
        amount: 100,
        posterId: 'flood$i',
        posterName: 'Flood$i',
      );
    }
    expect(board.active.length, BountyBoard.maxActiveBounties);
    expect(board.totalFor('whale'), 50000);
  });

  test('house posters are exempt from the per-poster cap', () {
    final board = BountyBoard.global;
    for (var i = 0; i < BountyBoard.maxBountiesPerPoster + 3; i++) {
      expect(
          board.post(
            targetId: 'fed$i',
            targetName: 'Fed$i',
            targetFaction: 'pirate',
            amount: 5000,
            posterId: 'FEDERATION',
            posterName: 'Federation Marshal',
          ),
          isNotNull);
    }
    expect(board.active.where((b) => b.posterId == 'FEDERATION').length,
        BountyBoard.maxBountiesPerPoster + 3);
  });

  test('pruneAbsent drops vanished targets, keeps the living', () {
    final board = BountyBoard.global;
    board.post(
      targetId: 'alive',
      targetName: 'Alive',
      targetFaction: 'pirate',
      amount: 500,
      posterId: 'p',
      posterName: 'P',
    );
    board.post(
      targetId: 'gone',
      targetName: 'Gone',
      targetFaction: 'pirate',
      amount: 500,
      posterId: 'p',
      posterName: 'P',
    );
    board.pruneAbsent({'alive', 'player-1'});
    expect(board.totalFor('alive'), 500);
    expect(board.totalFor('gone'), 0);
    // Pruned poster money queues as escrow, not vapor.
    expect(board.pendingRefundFor('p'), 500);
    expect(board.takeRefund('p'), 500);
    expect(board.pendingRefundFor('p'), 0);
  });

  group('escrow and expiry', () {
    test('expired marks lapse and refund', () {
      final board = BountyBoard.global;
      board.post(
        targetId: 'old',
        targetName: 'Old',
        targetFaction: 'pirate',
        amount: 1000,
        posterId: 'p',
        posterName: 'P',
        // Already lapsed: one tick short of an hour of *play*.
        expiresAtTick: GameClock.tick - GameClock.ticksPerHour + 1,
      );
      board.post(
        targetId: 'fresh',
        targetName: 'Fresh',
        targetFaction: 'pirate',
        amount: 1000,
        posterId: 'p',
        posterName: 'P',
      );
      final pruned = board.pruneExpired();
      expect(pruned.map((b) => b.targetId), ['old']);
      expect(board.totalFor('old'), 0);
      expect(board.totalFor('fresh'), 1000);
      expect(board.pendingRefundFor('p'), 1000);
    });

    test('house-minted marks evaporate instead of refunding', () {
      final board = BountyBoard.global;
      board.post(
        targetId: 'fed-mark',
        targetName: 'Fed Mark',
        targetFaction: 'pirate',
        amount: 5000,
        posterId: 'FEDERATION',
        posterName: 'Federation Marshal',
        // Already lapsed: one tick short of an hour of *play*.
        expiresAtTick: GameClock.tick - GameClock.ticksPerHour + 1,
      );
      expect(board.pruneExpired(), hasLength(1));
      expect(board.pendingRefunds, isEmpty);
    });

    test('settleNpcRefunds credits roster pilots in place', () {
      final board = BountyBoard.global;
      board.post(
        targetId: 'gone',
        targetName: 'Gone',
        targetFaction: 'pirate',
        amount: 700,
        posterId: 'npc-1',
        posterName: 'Pilot',
      );
      board.pruneAbsent({'someone-else'});
      var npc = NpcShip.create(
        faction: FactionClass.trader,
        shipDef: ShipDefinition.allShips.first,
        currentSectorId: 11,
        startingCredits: 1000,
        seed: 5,
      );
      // Force the roster id to match the poster.
      final roster = [
        npc.copyWith(id: 'npc-1'),
        NpcShip.create(
          faction: FactionClass.pirate,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: 11,
          startingCredits: 1000,
          seed: 6,
        ),
      ];
      expect(board.settleNpcRefunds(roster), 1);
      expect(roster[0].credits, 1700);
      expect(board.pendingRefundFor('npc-1'), 0);
    });

    test('posts default to a 7-day expiry; legacy rows backfill', () {
      final board = BountyBoard.global;
      final before = GameClock.tick;
      final posted = board.post(
        targetId: 't',
        targetName: 'T',
        targetFaction: 'pirate',
        amount: 500,
        posterId: 'p',
        posterName: 'P',
      )!;
      expect(posted.expiresAtTick - before, Bounty.ttlTicks,
          reason: 'a week is 7 x 2,880 = 20,160 ticks');
      // A legacy row: a wall-clock `createdAt` and no expiry at all.
      //
      // It is read as created *now*, which is a deliberate choice and not an
      // oversight — see `Bounty.fromJson`. Converting the old timestamp would
      // mean inventing a tick, and "some time before now" is unknowable, so the
      // row is treated as fresh and gets a full TTL from load. The assertion
      // pins that behaviour rather than leaving it to be discovered.
      final legacy = Bounty.fromJson({
        'id': 'x',
        'createdAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      });
      expect(legacy.createdAtTick, GameClock.tick,
          reason: 'a pre-clock row is re-stamped at load, not converted');
      expect(legacy.expiresAtTick, GameClock.tick + Bounty.ttlTicks);

      // A row already on the tick keys round-trips exactly.
      final modern = Bounty.fromJson(posted.toJson());
      expect(modern.createdAtTick, posted.createdAtTick);
      expect(modern.expiresAtTick, posted.expiresAtTick);
    });
  });

  test('self-posts pay out but mint no standing', () {
    final board = BountyBoard.global;
    board.post(
      targetId: 'mark',
      targetName: 'Mark',
      targetFaction: 'pirate',
      amount: 1000,
      posterId: 'me',
      posterName: 'Me',
      posterFaction: 'trader',
    );
    expect(board.posterFactionsFor('mark'), ['trader']);
    expect(board.posterFactionsFor('mark', excludePosterId: 'me'), isEmpty);
  });

  test('grouped targets stack totals richest-first', () {
    final board = BountyBoard.global;
    board.post(
      targetId: 'a',
      targetName: 'A',
      targetFaction: 'pirate',
      amount: 1000,
      posterId: 'p1',
      posterName: 'P1',
    );
    board.post(
      targetId: 'b',
      targetName: 'B',
      targetFaction: 'duran',
      amount: 5000,
      posterId: 'p2',
      posterName: 'P2',
    );
    board.post(
      targetId: 'a',
      targetName: 'A',
      targetFaction: 'pirate',
      amount: 3000,
      posterId: 'p3',
      posterName: 'P3',
    );
    final groups = board.groupedTargets();
    expect(groups.map((g) => g.targetId), ['b', 'a']);
    expect(groups.last.total, 4000);
    expect(groups.last.marks, hasLength(2));
    expect(groups.last.targetFaction, 'pirate');
  });

  test('paid factions round-trip through JSON with legacy defaults', () {
    final paid = PaidBounty(
      targetName: 'T',
      targetFaction: 'pirate',
      killerName: 'K',
      killerFaction: 'duran',
      amount: 100,
      paidAt: DateTime.utc(2026),
    );
    final restored = PaidBounty.fromJson(paid.toJson().cast<String, dynamic>());
    expect(restored.targetFaction, 'pirate');
    expect(restored.killerFaction, 'duran');
    final legacy = PaidBounty.fromJson(const {
      'targetName': 'T',
      'killerName': 'K',
      'amount': 100,
    });
    expect(legacy.targetFaction, '');
    expect(legacy.killerFaction, '');
  });

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
      killerFaction: 'duran',
      targetFaction: 'pirate',
    );
    expect(paid, 8000);
    expect(board.active, isEmpty);
    expect(board.paid, hasLength(1));
    expect(board.paid.first.killerName, 'Killer');
    // Factions ride along for the faction-colored board.
    expect(board.paid.first.killerFaction, 'duran');
    expect(board.paid.first.targetFaction, 'pirate');

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
        posterId: 'p$i',
        posterName: 'P$i',
      );
      board.payKiller(targetId: 't$i', killerName: 'K', targetName: 'T$i');
    }
    expect(board.paid, hasLength(20));
    expect(board.paid.first.targetName, 'T24');
  });

  test('Federation amounts scale with evilness above the Menace threshold', () {
    // FedAmount takes **evilness** (the magnitude of a negative alignment), not a
    // signed reputation: the Federation hunts villains, so a well-liked pilot
    // draws no Fed bounty at all rather than a small one. 64 is "Menace 1st
    // Class", the original's threshold for the Federation to start posting.
    expect(BountyBoard.fedAmount(0), 0);
    expect(BountyBoard.fedAmount(63.9), 0);
    expect(BountyBoard.fedAmount(64), 6400);
    expect(BountyBoard.fedAmount(96), 9600);
    expect(BountyBoard.fedAmount(128), 12800);
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
