import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/repopulation_service.dart';

// C3: coordination — outposts, convoys, wolf-packs, border holds,
// bounty intercepts, probabilistic intel.
Sector _plain(int id, [List<int> warps = const []]) => Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: warps,
    );

Sector _outpost({
  required int id,
  FactionClass? owner,
  int timer = 5,
}) {
  return Sector(
    id: id,
    name: 'S$id',
    x: 0,
    y: 0,
    warpRoutes: const [],
    hasPlanet: true,
    planet: Planet(
      name: 'Outpost$id',
      planetType: 'Barren',
      owner: owner,
      isHomeworld: true,
      homeworldOf: FactionClass.pirate,
      productionTimer: timer,
      spawnInterval: 12,
    ),
  );
}

NpcShip _npc(
  FactionClass faction,
  int sector,
  int seed, {
  NpcPersonality? personality,
  Map<String, int>? weapons,
  int credits = 0,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: credits,
    seed: seed,
  ).copyWith(
    personality: personality ??
        (faction == FactionClass.pirate
            ? NpcPersonality.pirateHunter
            : NpcPersonality.traderMerchant),
    energy: 1000,
    weaponSlots: weapons ?? {'main_forward': 3},
  );
}

void main() {
  setUp(() => NpcAiService.clearSignalsForTest());
  tearDown(() => NpcAiService.clearSignalsForTest());

  group('C3 convoys', () {
    List<Sector> lane() => [
          _plain(11, [12]),
          _plain(12, [11, 13]),
          _plain(13, [12]),
        ];

    NpcGoal tradeRun(String commodity) => NpcGoal(
          type: NpcGoalType.tradeRoute,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {
            'targetSectorId': 12,
            'buyPortId': 12,
            'sellPortId': 13,
            'commodity': commodity,
            'phase': 'travel_to_buy',
          },
        );

    test('idle traders fall in with a live run (cap two)', () {
      final sectors = lane();
      var leader = _npc(FactionClass.trader, 11, 701, credits: 5000)
          .copyWith(currentGoal: tradeRun('minerals'));
      var e1 = _npc(FactionClass.trader, 11, 702, credits: 5000);
      var e2 = _npc(FactionClass.trader, 11, 703, credits: 5000);
      var e3 = _npc(FactionClass.trader, 11, 704, credits: 5000);

      var roster = [leader, e1, e2, e3];
      // Prevent the lottery from stealing escorts: fully charted,
      // and patrol loses the weight game often enough — retry per ship
      // until each either escorts or exhausts (escort is sticky: the
      // first two wins fill the wing, the third must fail).
      NpcShip escortOrPatrol(NpcShip ship) {
        for (var i = 0; i < 10; i++) {
          var cand = ship.copyWith(clearGoal: true);
          final r = [roster[0], cand, ...roster.sublist(2)];
          cand = NpcAiService.processTurn(cand, sectors, [], r);
          if (cand.currentGoal?.params['convoyLeader'] != null) return cand;
        }
        return ship.copyWith(
            currentGoal: NpcGoal(
                type: NpcGoalType.patrol,
                status: NpcGoalStatus.travelling,
                createdAt: DateTime.now(),
                params: const {'targetSectorId': 12}));
      }

      e1 = escortOrPatrol(e1);
      roster = [leader, e1, e2, e3];
      e2 = escortOrPatrol(e2);
      roster = [leader, e1, e2, e3];

      expect(e1.currentGoal?.params['convoyLeader'], leader.id);
      expect(e1.currentGoal?.params['buyPortId'], 12);
      expect(e1.currentGoal?.params['sellPortId'], 13);
      expect(e2.currentGoal?.params['convoyLeader'], leader.id);

      // Wing full: the third trader finds no room.
      var third = e3;
      var joined = false;
      for (var i = 0; i < 10; i++) {
        var cand = e3.copyWith(clearGoal: true);
        final r = [leader, e1, e2, cand];
        cand = NpcAiService.processTurn(cand, sectors, [], r);
        if (cand.currentGoal?.params['convoyLeader'] != null) {
          joined = true;
          third = cand;
          break;
        }
        third = cand;
      }
      expect(joined, isFalse);
      expect(third.currentGoal?.params.containsKey('convoyLeader') ?? false,
          isFalse);
    });

    test('escorts scatter when the leader dies', () {
      final sectors = lane();
      final leader = _npc(FactionClass.trader, 11, 711, credits: 5000)
          .copyWith(currentGoal: tradeRun('minerals'));
      var escort = _npc(FactionClass.trader, 11, 712, credits: 5000).copyWith(
          currentGoal: NpcGoal(
              type: NpcGoalType.tradeRoute,
              status: NpcGoalStatus.travelling,
              createdAt: DateTime.now(),
              params: {
            ...tradeRun('minerals').params,
            'convoyLeader': leader.id,
          }));

      // Leader destroyed in place: escort's next execution scatters,
      // then selection refills the freed pilot (never a convoy remake —
      // the leader is gone, so no wing flag can return).
      final wreck = leader.copyWith(isDestroyed: true);
      final roster = [wreck, escort];
      escort = NpcAiService.processTurn(escort, sectors, [], roster);
      expect(escort.currentGoal?.params.containsKey('convoyLeader') ?? false,
          isFalse);
    });

    test('escorts fly solo when the leader finishes first', () {
      final sectors = lane();
      final done = _npc(FactionClass.trader, 12, 721, credits: 5000).copyWith(
          currentGoal: NpcGoal(
              type: NpcGoalType.tradeRoute,
              status: NpcGoalStatus.complete,
              createdAt: DateTime.now(),
              params: tradeRun('minerals').params));
      var escort = _npc(FactionClass.trader, 11, 722, credits: 5000).copyWith(
          currentGoal: NpcGoal(
              type: NpcGoalType.tradeRoute,
              status: NpcGoalStatus.travelling,
              createdAt: DateTime.now(),
              params: {
            ...tradeRun('minerals').params,
            'convoyLeader': done.id,
          }));

      final roster = [done, escort];
      escort = NpcAiService.processTurn(escort, sectors, [], roster);
      // Kept its legs, dropped the wing flag, moved toward the buy port.
      expect(escort.currentGoal?.type, NpcGoalType.tradeRoute);
      expect(escort.currentGoal?.params.containsKey('convoyLeader'), isFalse);
      expect(escort.currentSectorId, 12);
    });
  });

  group('C3 wolf-packs', () {
    test('idle pirates pile onto a live hunt (cap three)', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final victim = _npc(FactionClass.trader, 12, 731);
      var hunter = _npc(FactionClass.pirate, 11, 732).copyWith(
          currentGoal: NpcGoal(
              type: NpcGoalType.attack,
              status: NpcGoalStatus.travelling,
              createdAt: DateTime.now(),
              params: {
            'targetSectorId': 12,
            'targetId': victim.id,
          }));
      var joiner = _npc(FactionClass.pirate, 11, 733);

      final roster = [hunter, victim, joiner];
      joiner = NpcAiService.processTurn(joiner, sectors, [], roster);
      expect(joiner.currentGoal?.type, NpcGoalType.attack);
      expect(joiner.currentGoal?.params['targetId'], victim.id);
      expect(joiner.currentGoal?.params['targetSectorId'], 12);
      expect(joiner.currentSectorId, 12);
    });

    test('full packs hunt alone', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final victim = _npc(FactionClass.trader, 12, 741);
      NpcShip packmate(int seed) =>
          _npc(FactionClass.pirate, 11, seed).copyWith(
              currentGoal: NpcGoal(
                  type: NpcGoalType.attack,
                  status: NpcGoalStatus.travelling,
                  createdAt: DateTime.now(),
                  params: {
                'targetSectorId': 12,
                'targetId': victim.id,
              }));
      final roster = [packmate(742), packmate(743), packmate(744), victim];
      var extra = _npc(FactionClass.pirate, 11, 745);
      extra = NpcAiService.processTurn(extra, sectors, [], roster);
      // Three hulls already on this victim: no fourth.
      final targetId = victim.id;
      expect(
          extra.currentGoal?.type == NpcGoalType.attack &&
              extra.currentGoal?.targetId == targetId,
          isFalse);
    });
  });

  group('Review batch 1: shared convergence cap', () {
    NpcShip hunterWithGoal(int seed, String targetId, int sector) =>
        _npc(FactionClass.pirate, 11, seed).copyWith(
            currentGoal: NpcGoal(
                type: NpcGoalType.attack,
                status: NpcGoalStatus.travelling,
                createdAt: DateTime.now(),
                params: {
              'targetSectorId': sector,
              'targetId': targetId,
            }));

    test('vendetta waits when a full wing is already inbound', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final victim = _npc(FactionClass.pirate, 12, 801,
          weapons: const {'main_forward': 1});
      final pack = [
        hunterWithGoal(802, victim.id, 12),
        hunterWithGoal(803, victim.id, 12),
        hunterWithGoal(804, victim.id, 12),
      ];
      var holder = _npc(FactionClass.trader, 11, 805, credits: 0);
      holder = holder.copyWith(
        memory: holder.memory.withVendetta(
          targetId: victim.id,
          sectorId: 12,
          grievanceBump: 90,
        ),
      );

      final roster = [...pack, victim, holder];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      // Magnet target: the grudge keeps, the hunt waits.
      expect(holder.currentGoal?.params.containsKey('vendettaFor') ?? false,
          isFalse);
      expect(holder.memory.vendettas[victim.id]?.grievance, 90);
    });

    test('bounty targeting respects the same cap', () {
      BountyBoard.resetForTest();
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      var victim = _npc(FactionClass.trader, 12, 811,
          weapons: const {'main_forward': 1});
      BountyBoard.global.post(
        targetId: victim.id,
        targetName: victim.pilotName,
        targetFaction: victim.faction.name,
        amount: 5000,
        posterId: 'tester',
        posterName: 'Tester',
        reason: 'test mark',
      );
      final pack = [
        hunterWithGoal(812, victim.id, 12),
        hunterWithGoal(813, victim.id, 12),
        hunterWithGoal(814, victim.id, 12),
      ];
      var extra = _npc(FactionClass.pirate, 11, 815,
          personality: NpcPersonality.pirateHunter);
      extra = extra.copyWith(
          memory: extra.memory.copyWith(visitedSectors: {11, 12}));

      final roster = [...pack, victim, extra];
      extra = NpcAiService.processTurn(extra, sectors, [], roster);
      final targetId = victim.id;
      expect(
          extra.currentGoal?.type == NpcGoalType.attack &&
              extra.currentGoal?.targetId == targetId,
          isFalse);
      BountyBoard.resetForTest();
    });

    test('hunts resume as the wing drains', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final victim = _npc(FactionClass.pirate, 12, 821,
          weapons: const {'main_forward': 1});
      // Only two inbound: room for one more.
      final pack = [
        hunterWithGoal(822, victim.id, 12),
        hunterWithGoal(823, victim.id, 12),
      ];
      var holder = _npc(FactionClass.trader, 11, 824, credits: 0);
      holder = holder.copyWith(
        memory: holder.memory.withVendetta(
          targetId: victim.id,
          sectorId: 12,
          grievanceBump: 90,
        ),
      );

      final roster = [...pack, victim, holder];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      expect(holder.currentGoal?.params['vendettaFor'], victim.id);
    });
  });

  group('C3 border holds', () {
    test('idle Duran post up next door to hostiles and sit', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11, 13]),
        _plain(13, [12]),
      ];
      final vinari = _npc(FactionClass.vinari, 13, 751);
      var holder = _npc(FactionClass.duran, 11, 752);

      var roster = [holder, vinari];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      // Nearest sector neighboring hostiles: 12.
      expect(holder.currentGoal?.type, NpcGoalType.patrol);
      expect(holder.currentGoal?.params['borderHold'], 12);
      expect(holder.currentSectorId, 12);

      // Next turn on post: sits (legs tick, no wandering).
      roster = [holder, vinari];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      expect(holder.currentSectorId, 12);
      expect(holder.currentGoal?.type, NpcGoalType.patrol);
      expect(holder.currentGoal?.params['borderHold'], 12);
    });

    test('full posts free the rest of the faction (soak fix)', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11, 13]),
        _plain(13, [12]),
      ];
      final vinari = _npc(FactionClass.vinari, 13, 771);
      NpcGoal holdAt12() => NpcGoal(
            type: NpcGoalType.patrol,
            status: NpcGoalStatus.travelling,
            createdAt: DateTime.now(),
            params: const {
              'targetSectorId': 12,
              'homeSector': 11,
              'borderHold': 12,
            },
          );
      final h1 =
          _npc(FactionClass.duran, 11, 772).copyWith(currentGoal: holdAt12());
      final h2 =
          _npc(FactionClass.duran, 11, 773).copyWith(currentGoal: holdAt12());
      var newcomer = _npc(FactionClass.duran, 11, 774);

      final roster = [h1, h2, vinari, newcomer];
      newcomer = NpcAiService.processTurn(newcomer, sectors, [], roster);
      // Two hulls already hold 12: no third — lottery instead.
      expect(newcomer.currentGoal?.params.containsKey('borderHold') ?? false,
          isFalse);
    });

    test('no hostiles, no hold', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11]),
      ];
      final mate = _npc(FactionClass.duran, 12, 761);
      var holder = _npc(FactionClass.duran, 11, 762);
      final roster = [holder, mate];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      expect(holder.currentGoal?.params.containsKey('borderHold') ?? false,
          isFalse);
    });
  });

  group('C3 bounty intercepts', () {
    setUp(BountyBoard.resetForTest);
    tearDown(BountyBoard.resetForTest);

    List<Sector> triangle() => [
          _plain(11, [12, 14]),
          _plain(12, [11]),
          _plain(14, [11]),
        ];

    NpcShip mark(NpcShip target) {
      BountyBoard.global.post(
        targetId: target.id,
        targetName: target.pilotName,
        targetFaction: target.faction.name,
        amount: 5000,
        posterId: 'tester',
        posterName: 'Tester',
        reason: 'test mark',
      );
      return target;
    }

    test('greedy hunters cut off underway marks', () {
      final sectors = triangle();
      var target =
          _npc(FactionClass.trader, 12, 771, weapons: const {'main_forward': 1})
              .copyWith(
                  currentGoal: NpcGoal(
                      type: NpcGoalType.tradeRoute,
                      status: NpcGoalStatus.travelling,
                      createdAt: DateTime.now(),
                      params: const {
            'targetSectorId': 14,
            'buyPortId': 14,
            'sellPortId': 14,
            'commodity': 'minerals',
            'phase': 'travel_to_buy',
          }));
      target = mark(target);
      var hunter = _npc(FactionClass.pirate, 11, 772,
          personality: NpcPersonality.pirateHunter);
      // Fully charted: explore is dead, trade wants unknown ports, so
      // the weighted lottery can only deal the attack goal.
      hunter = hunter.copyWith(
          memory: hunter.memory.copyWith(visitedSectors: {11, 12, 14}));

      final roster = [hunter, target];
      hunter = NpcAiService.processTurn(hunter, sectors, [], roster);
      // Not where they are (12) — where they're going (14).
      expect(hunter.currentGoal?.type, NpcGoalType.attack);
      expect(hunter.currentGoal?.params['targetId'], target.id);
      expect(hunter.currentGoal?.params['targetSectorId'], 14);
    });

    test('unmarked but underway still cuts off (soak fix)', () {
      final sectors = triangle();
      final target =
          _npc(FactionClass.trader, 12, 791, weapons: const {'main_forward': 1})
              .copyWith(
                  currentGoal: NpcGoal(
                      type: NpcGoalType.tradeRoute,
                      status: NpcGoalStatus.travelling,
                      createdAt: DateTime.now(),
                      params: const {
            'targetSectorId': 14,
            'buyPortId': 14,
            'sellPortId': 14,
            'commodity': 'minerals',
            'phase': 'travel_to_buy',
          }));
      // No bounty posted: the cutoff no longer needs one.
      var hunter = _npc(FactionClass.pirate, 11, 792,
          personality: NpcPersonality.pirateHunter);
      hunter = hunter.copyWith(
          memory: hunter.memory.copyWith(visitedSectors: {11, 12, 14}));

      final roster = [hunter, target];
      hunter = NpcAiService.processTurn(hunter, sectors, [], roster);
      expect(hunter.currentGoal?.type, NpcGoalType.attack);
      expect(hunter.currentGoal?.params['targetId'], target.id);
      expect(hunter.currentGoal?.params['targetSectorId'], 14);
    });

    test('no mark, no heading, no cutoff', () {
      final sectors = triangle();
      final target = _npc(FactionClass.trader, 12, 781,
          weapons: const {'main_forward': 1});
      var hunter = _npc(FactionClass.pirate, 11, 782,
          personality: NpcPersonality.pirateHunter);
      hunter = hunter.copyWith(
          memory: hunter.memory.copyWith(visitedSectors: {11, 12, 14}));

      final roster = [hunter, target];
      hunter = NpcAiService.processTurn(hunter, sectors, [], roster);
      // Unmarked: straight hunt where they are.
      expect(hunter.currentGoal?.type, NpcGoalType.attack);
      expect(hunter.currentGoal?.params['targetSectorId'], 12);
    });
  });

  group('C3 probabilistic intel', () {
    test('fresh sightings are exact; stale ones fan out', () {
      final sectors = [
        _plain(11, [12, 13]),
        _plain(12, [11]),
        _plain(13, [11]),
      ];
      final now = DateTime.now().millisecondsSinceEpoch;
      // Fresh (just seen): exact.
      const freshBase = VendettaRecord(
          sectorId: 11, firstSeenMs: 0, lastSeenMs: 0, grievance: 60);
      final fresh = VendettaRecord(
          sectorId: freshBase.sectorId,
          firstSeenMs: now,
          lastSeenMs: now,
          grievance: freshBase.grievance);
      expect(NpcAiService.intelSearchSector(fresh, sectors, nowMs: now), 11);
      // Stale (an hour): a neighbor of 11.
      final stale = VendettaRecord(
          sectorId: 11,
          firstSeenMs: now - 3600000,
          lastSeenMs: now - 3600000,
          grievance: 60);
      expect(
          {12, 13},
          contains(NpcAiService.intelSearchSector(stale, sectors,
              nowMs: now, rng: math.Random(3))));
      // Unknown ground: the sighting itself.
      final lost = VendettaRecord(
          sectorId: 99,
          firstSeenMs: now - 3600000,
          lastSeenMs: now - 3600000,
          grievance: 60);
      expect(NpcAiService.intelSearchSector(lost, sectors, nowMs: now), 99);
    });

    test('dry holes widen live grudges without refreshing decay', () {
      final sectors = [
        _plain(11, [12]),
        _plain(12, [11, 13]),
        _plain(13, [12]),
      ];
      final now = DateTime.now().millisecondsSinceEpoch;
      final target = _npc(FactionClass.trader, 13, 791,
          weapons: const {'main_forward': 1});
      var holder = _npc(FactionClass.trader, 11, 792, credits: 0);
      final lastSeenBefore = now - 1000;
      holder = holder.copyWith(
        memory: holder.memory.withVendetta(
          targetId: target.id,
          sectorId: 11,
          grievanceBump: 90,
          nowMs: lastSeenBefore,
        ),
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {
            'targetSectorId': 11,
            'targetId': target.id,
            'vendettaFor': target.id,
          },
        ),
      );

      final roster = [holder, target];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      // 90 − 10 = 80: live, so the search fans out to 12 (only neighbor)
      // with the decay window untouched — and the fresh hunt re-issues
      // against the new intel in the same turn.
      final record = holder.memory.vendettas[target.id]!;
      expect(record.grievance, 80);
      expect(record.sectorId, 12);
      expect(record.lastSeenMs, lastSeenBefore);
      expect(holder.currentGoal?.params['vendettaFor'], target.id);
      expect(holder.currentGoal?.params['targetSectorId'], 12);
    });
  });

  group('C3 pirate outposts', () {
    test('floor fallback launches from the outpost, not random ground', () {
      final sectors = [_plain(11), _outpost(id: 12)];
      final spawned = RepopulationService.repopulate(
        sectors,
        [],
        rng: math.Random(7),
      );
      // Only pirates have ground here (other factions log extinction).
      expect(spawned, hasLength(1));
      expect(spawned[0].faction, FactionClass.pirate);
      expect(spawned[0].currentSectorId, 12);
    });

    test('captured outpost returns pirates to random fallback', () {
      final sectors = [
        _plain(11, [12]),
        _outpost(id: 12, owner: FactionClass.duran),
      ];
      final spawned = RepopulationService.repopulate(
        sectors,
        [],
        rng: math.Random(7),
      );
      expect(spawned, hasLength(1));
      expect(spawned[0].faction, FactionClass.pirate);
      expect({11, 12}, contains(spawned[0].currentSectorId));
    });

    test('outpost yards produce up to the lean pirate cap', () {
      final sectors = [_plain(11), _outpost(id: 12, timer: 1)];
      var built = RepopulationService.produce(
        sectors,
        [],
        rng: math.Random(7),
      );
      expect(built, hasLength(1));
      expect(built[0].faction, FactionClass.pirate);
      expect(built[0].currentSectorId, 12);

      final crew = [
        for (var i = 0; i < 4; i++) _npc(FactionClass.pirate, 12, 200 + i),
      ];
      sectors[1].planet!.productionTimer = 1;
      built = RepopulationService.produce(
        sectors,
        crew,
        rng: math.Random(7),
      );
      expect(built, isEmpty);
    });
  });
}
