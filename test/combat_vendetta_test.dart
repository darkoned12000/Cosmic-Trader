import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';
import 'package:cosmic_trader/services/npc_ai/pathfinding_service.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

// C2a: vendetta reacquisition — memory → intent → goal. Idle pilots with a
// fresh, actionable grudge hunt first (never by hijacking a committed
// goal); hunts are budgeted by time (expiry), energy (trip + reserve),
// and courage (weaker targets only). Dry holes ease the grudge.
NpcShip _ship({
  required FactionClass faction,
  required NpcPersonality personality,
  required int sector,
  required int seed,
  int hull = 100,
  int energy = 1000,
  int credits = 0,
  Map<String, int>? weapons,
}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: credits,
    seed: seed,
  ).copyWith(
    personality: personality,
    hull: hull,
    maxHull: hull,
    energy: energy,
    weaponSlots: weapons ?? {'main_forward': 3},
  );
}

List<Sector> _sectors() => [
      Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
      Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
    ];

/// Idle holder in sector 12 with a live grudge ([grievance]) against
/// [target], last seen in sector 11.
NpcShip _holderWithGrudge(NpcShip holder, String targetId, int grievance) {
  return holder.copyWith(
    memory: holder.memory.withVendetta(
      targetId: targetId,
      sectorId: 11,
      grievanceBump: grievance,
    ),
  );
}

void main() {
  setUp(() => NpcAiService.clearSignalsForTest());
  tearDown(() => NpcAiService.clearSignalsForTest());

  test('idle pilot hunts a weaker vendetta target first', () {
    final sectors = _sectors();
    final target = _ship(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateHunter,
      sector: 11,
      seed: 401,
      weapons: const {'main_forward': 1},
    );
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 402,
      ),
      target.id,
      60,
    );

    final roster = [holder, target];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);

    expect(holder.currentGoal?.type, NpcGoalType.attack);
    expect(holder.currentGoal?.params['vendettaFor'], target.id);
    expect(holder.currentGoal?.params['targetId'], target.id);
    expect(holder.currentGoal?.params['targetSectorId'], 11);
    // Pursuit starts the same turn: 12 → 11.
    expect(holder.currentSectorId, 11);
  });

  test('stronger vendetta target is held, not hunted', () {
    final sectors = _sectors();
    final target = _ship(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateHunter,
      sector: 11,
      seed: 411,
      weapons: const {'main_forward': 9},
    );
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 412,
      ),
      target.id,
      80,
    );

    final roster = [holder, target];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);

    // No suicide runs: whatever the pilot does instead, it is not a
    // vendetta hunt — but the grudge itself is kept.
    expect(holder.currentGoal?.params.containsKey('vendettaFor') ?? false,
        isFalse);
    expect(holder.memory.vendettas[target.id]?.grievance, 80);
  });

  test('grudge below threshold does not launch a hunt', () {
    final sectors = _sectors();
    final target = _ship(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateHunter,
      sector: 11,
      seed: 421,
      weapons: const {'main_forward': 1},
    );
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 422,
      ),
      target.id,
      30,
    );

    final roster = [holder, target];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);
    expect(holder.currentGoal?.params.containsKey('vendettaFor') ?? false,
        isFalse);
  });

  test('missing target yields no hunt (pruned in C2b)', () {
    final sectors = _sectors();
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 431,
      ),
      'no-such-pilot',
      90,
    );

    final roster = [holder];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);
    expect(holder.currentGoal?.params.containsKey('vendettaFor') ?? false,
        isFalse);
  });

  test('dry hole eases the grudge without refreshing its window', () {
    final sectors = _sectors();
    final beforeMs = DateTime.now().millisecondsSinceEpoch;
    var target = _ship(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateHunter,
      sector: 12,
      seed: 441,
      weapons: const {'main_forward': 1},
    );
    target = target.copyWith(currentSectorId: 12);
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 442,
      ),
      target.id,
      45,
    ).copyWith(
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
    final lastSeenBefore = holder.memory.vendettas[target.id]!.lastSeenMs;
    expect(lastSeenBefore, greaterThanOrEqualTo(beforeMs));

    final roster = [holder, target];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);

    // 45 − 10 = 35: below threshold, so no same-turn re-acquisition.
    expect(holder.memory.vendettas[target.id]?.grievance, 35);
    expect(holder.currentGoal?.params.containsKey('vendettaFor') ?? false,
        isFalse);
    // No sighting refresh — the 6h decay window is untouched.
    expect(holder.memory.vendettas[target.id]!.lastSeenMs, lastSeenBefore);
  });

  test('expired hunt stands down and a fresh hunt re-issues', () {
    final sectors = _sectors();
    final target = _ship(
      faction: FactionClass.pirate,
      personality: NpcPersonality.pirateHunter,
      sector: 12,
      seed: 451,
      weapons: const {'main_forward': 1},
    );
    var holder = _holderWithGrudge(
      _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 452,
      ),
      target.id,
      60,
    ).copyWith(
      currentGoal: NpcGoal(
        type: NpcGoalType.attack,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now().subtract(const Duration(minutes: 31)),
        params: {
          'targetSectorId': 11,
          'targetId': target.id,
          'vendettaFor': target.id,
        },
      ),
    );

    final roster = [holder, target];
    holder = NpcAiService.processTurn(holder, sectors, [], roster);

    // The stale leg died (expiry branch) and selection issued a new one:
    // the live goal is fresh, not 31 minutes old.
    expect(holder.currentGoal?.params['vendettaFor'], target.id);
    expect(
      DateTime.now().difference(holder.currentGoal!.createdAt),
      lessThan(const Duration(minutes: 1)),
    );
  });

  group('C2b resolution', () {
    List<NpcShip> strike(
        List<Sector> sectors, List<NpcShip> npcs, String defenderId) {
      final out = List<NpcShip>.from(npcs);
      out[0] = out[0].copyWith(
        currentGoal: NpcGoal(
          type: NpcGoalType.attack,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: {
            'targetSectorId': 11,
            'targetId': defenderId,
            'vendettaFor': defenderId,
          },
        ),
      );
      out[0] = NpcAiService.processTurn(out[0], sectors, [], out);
      return out;
    }

    test('kill settles the score: vendetta resolves', () {
      final sectors = _sectors();
      var npcs = [
        _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 461,
          credits: 0,
        ),
        // Doomed: hull 1, no shields, broke (no survivor bounty either).
        _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 462,
          hull: 1,
          credits: 0,
          weapons: const {'main_forward': 1},
        ),
      ];
      npcs[1] = npcs[1].copyWith(shields: 0, maxShields: 0);
      npcs[0] = npcs[0].copyWith(
        memory: npcs[0].memory.withVendetta(
              targetId: npcs[1].id,
              sectorId: 11,
              grievanceBump: 60,
            ),
      );
      npcs = strike(sectors, npcs, npcs[1].id);

      expect(npcs[1].isDestroyed, isTrue);
      expect(npcs[0].memory.vendettas, isEmpty);
    });

    test('crossed blades refresh the trail (sector + small bump)', () {
      final sectors = _sectors();
      var npcs = [
        _ship(
          faction: FactionClass.pirate,
          personality: NpcPersonality.pirateHunter,
          sector: 11,
          seed: 471,
          credits: 0,
        ),
        // Tanky: survives the exchange so the trail refreshes, not ends.
        _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 472,
          hull: 5000,
          credits: 0,
          weapons: const {'main_forward': 1},
        ),
      ];
      // Stale intel on purpose: last seen in 12, actually met in 11.
      npcs[0] = npcs[0].copyWith(
        memory: npcs[0].memory.withVendetta(
              targetId: npcs[1].id,
              sectorId: 12,
              grievanceBump: 60,
            ),
      );
      npcs = strike(sectors, npcs, npcs[1].id);

      expect(npcs[1].isDestroyed, isFalse);
      final record = npcs[0].memory.vendettas[npcs[1].id]!;
      expect(record.sectorId, 11);
      expect(record.grievance, 70);
    });

    test('grudges against the gone are dropped', () {
      final sectors = _sectors();
      // Absent id, plus a destroyed hulk still in the roster.
      final hulk = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 11,
        seed: 481,
        hull: 0,
      ).copyWith(isDestroyed: true);
      var holder = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 482,
        credits: 0,
      );
      holder = holder.copyWith(
        memory: holder.memory
            .withVendetta(
              targetId: 'no-such-pilot',
              sectorId: 11,
              grievanceBump: 90,
            )
            .withVendetta(
              targetId: hulk.id,
              sectorId: 11,
              grievanceBump: 90,
            ),
      );

      final roster = [holder, hulk];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      expect(holder.memory.vendettas, isEmpty);
    });

    test('living targets are kept through the prune', () {
      final sectors = _sectors();
      final target = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 11,
        seed: 491,
        weapons: const {'main_forward': 1},
      );
      var holder = _holderWithGrudge(
        _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 12,
          seed: 492,
          credits: 0,
        ),
        target.id,
        60,
      );

      final roster = [holder, target];
      holder = NpcAiService.processTurn(holder, sectors, [], roster);
      // Hunt launched (C2a) — and the entry survived the prune to do it.
      expect(holder.currentGoal?.params['vendettaFor'], target.id);
    });
  });

  group('C2c avoidance', () {
    List<Sector> diamond() => [
          Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12, 13]),
          Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11, 14]),
          Sector(id: 13, name: 'C', x: 0, y: 1, warpRoutes: const [11, 14]),
          Sector(id: 14, name: 'D', x: 1, y: 1, warpRoutes: const [12, 13]),
        ];

    test('feared sectors hold stronger grudge-targets only', () {
      final strong = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 12,
        seed: 501,
        weapons: const {'main_forward': 9},
      );
      final weak = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 13,
        seed: 502,
        weapons: const {'main_forward': 1},
      );
      var holder = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 503,
        credits: 0,
      );
      holder = holder.copyWith(
        memory: holder.memory
            .withVendetta(targetId: strong.id, sectorId: 12, grievanceBump: 90)
            .withVendetta(targetId: weak.id, sectorId: 13, grievanceBump: 90),
      );

      expect(
        NpcAiService.fearedSectors(holder, [holder, strong, weak]),
        {12},
      );
      expect(
        NpcAiService.fearedSectors(
            holder.copyWith(
                memory: holder.memory.withVendettaResolved(strong.id)),
            [holder, strong, weak]),
        isEmpty,
      );
    });

    test('trade evaluator discounts danger but never refuses all money', () {
      // Star around 11: great route via 13, decent safe route via 14.
      final knownPorts = {
        12: const PortInfo(
          name: 'P12',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 10.0},
        ),
        13: const PortInfo(
          name: 'P13',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
        ),
        14: const PortInfo(
          name: 'P14',
          portClass: PortClass.free,
          buyPrices: {'minerals': 110.0},
          sellPrices: {},
        ),
      };
      final sectors = [
        Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12, 13, 14]),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
        Sector(id: 13, name: 'C', x: 0, y: 1, warpRoutes: const [11]),
        Sector(id: 14, name: 'D', x: 1, y: 1, warpRoutes: const [11]),
      ];

      final greedy = TradeEvaluator.findBestTradeRoute(
          11, knownPorts, sectors, 30,
          credits: 10000);
      expect(greedy!.sellSectorId, 13);

      // Danger at the great route's sell end flips to the safe route.
      final cautious = TradeEvaluator.findBestTradeRoute(
          11, knownPorts, sectors, 30,
          credits: 10000, dangerSectors: {13});
      expect(cautious!.sellSectorId, 14);

      // Danger everywhere: still trades (discounted, not refused).
      final desperate = TradeEvaluator.findBestTradeRoute(
          11, knownPorts, sectors, 30,
          credits: 10000, dangerSectors: {12, 13, 14});
      expect(desperate, isNotNull);
    });

    test('avoiding path bends, keeps endpoints, falls back', () {
      final sectors = diamond();
      // Bend around 12 via 13.
      expect(
        PathfindingService.findPathAvoiding(sectors, 11, 14, {12}),
        [11, 13, 14],
      );
      // Endpoints are never avoided.
      expect(
        PathfindingService.findPathAvoiding(sectors, 11, 12, {12}),
        [11, 12],
      );
      // No alternative: straight through, not stranded.
      final line = [
        Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12]),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11, 13]),
        Sector(id: 13, name: 'C', x: 2, y: 0, warpRoutes: const [12]),
      ];
      expect(
        PathfindingService.findPathAvoiding(line, 11, 13, {12}),
        [11, 12, 13],
      );
    });

    test('transit bends around a feared sector', () {
      final sectors = diamond();
      final brute = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 12,
        seed: 511,
        weapons: const {'main_forward': 9},
      );
      var mover = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 512,
        credits: 0,
      );
      mover = mover.copyWith(
        memory: mover.memory.withVendetta(
          targetId: brute.id,
          sectorId: 12,
          grievanceBump: 90,
        ),
        // Committed transit 11 → 14 (mid-route trade leg no-ops here,
        // so the turn is pure movement).
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
          },
        ),
      );

      final roster = [mover, brute];
      mover = NpcAiService.processTurn(mover, sectors, [], roster);
      expect(mover.currentSectorId, 13);
      // Committed goal survives the bend — avoidance steers, never drops.
      expect(mover.currentGoal?.params['targetSectorId'], 14);
    });

    test('sell-first prefers safe buyers, flies dangerous last', () {
      final sectors = [
        Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12, 13]),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
        Sector(id: 13, name: 'C', x: 0, y: 1, warpRoutes: const [11]),
      ];
      NpcShip fullHolder(Map<int, PortInfo> ports, String bruteId) {
        var npc = _ship(
          faction: FactionClass.trader,
          personality: NpcPersonality.traderMerchant,
          sector: 11,
          seed: 521,
          credits: 5000,
        );
        final cap = npc.cargoHoldCapacity;
        npc = npc.copyWith(
          cargo: {'minerals': cap},
          cargoUsed: cap,
          // Fully charted: explore is not viable, so selection is
          // trade-vs-patrol and trade wins the weight lottery ~12:1.
          // The retry loop below covers the residual patrol draws.
          memory: npc.memory.copyWith(
            discoveredPorts: ports,
            visitedSectors: {11, 12, 13},
          ).withVendetta(
            targetId: bruteId,
            sectorId: 12,
            grievanceBump: 90,
          ),
        );
        return npc;
      }

      final ports = {
        12: const PortInfo(
          name: 'DangerBuyer',
          portClass: PortClass.free,
          buyPrices: {'minerals': 100.0},
          sellPrices: {},
        ),
        13: const PortInfo(
          name: 'SafeBuyer',
          portClass: PortClass.free,
          buyPrices: {'minerals': 50.0},
          sellPrices: {},
        ),
      };
      // Brute must be live and stronger for 12 to count as feared.
      final brute = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 12,
        seed: 522,
        credits: 0,
        weapons: const {'main_forward': 9},
      );

      NpcShip runUntilTrade(Map<int, PortInfo> ports, String bruteId) {
        // Goal selection is a weighted lottery; patrol occasionally beats
        // trade, so deal fresh hands until trade wins (12:1 per draw).
        for (var i = 0; i < 20; i++) {
          var npc = fullHolder(ports, brute.id);
          npc = NpcAiService.processTurn(npc, sectors, [], [npc, brute]);
          if (npc.currentGoal?.type == NpcGoalType.tradeRoute) return npc;
        }
        throw StateError('trade never won 20 goal lotteries');
      }

      var npc = runUntilTrade(ports, brute.id);
      // Safe 50cr beats dangerous 100cr.
      expect(npc.currentGoal?.params['sellPortId'], 13);

      // Dangerous-only: flies dangerous rather than sitting on cargo.
      // (Decoy 13 buys nothing on board, so trade stays viable via the
      // 2-port minimum but danger is the only way to sell minerals.)
      npc = runUntilTrade({
        12: ports[12]!,
        13: const PortInfo(
          name: 'NoBuyer',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {},
        ),
      }, brute.id);
      expect(npc.currentGoal?.params['sellPortId'], 12);
    });
  });

  group('C2d gossip and route learning', () {
    test('wingmates adopt unknown killers as hearsay', () {
      final sectors = _sectors();
      final now = DateTime.now().millisecondsSinceEpoch;
      // X stays live (else the prune drops the grudge first) but far
      // outside this universe, so no hunt can launch off the gossip.
      final x = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 50,
        seed: 531,
        credits: 0,
      ).copyWith(currentSectorId: 50);
      var a = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 532,
        credits: 0,
      );
      a = a.copyWith(
        memory: a.memory.withVendetta(
          targetId: x.id,
          sectorId: 5,
          grievanceBump: 60,
          nowMs: now - 1000,
        ),
      );
      var b = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 533,
        credits: 0,
      );

      final roster = [a, b, x];
      roster[0] = NpcAiService.processTurn(roster[0], sectors, [], roster);

      final heard = roster[1].memory.vendettas[x.id]!;
      expect(heard.grievance, NpcMemory.hearsayGrievance);
      expect(heard.sectorId, 5);
      // Source keeps its own full grudge — sightings only.
      expect(roster[0].memory.vendettas[x.id]!.grievance, 60);
    });

    test('newer sightings refresh sector, never grievance', () {
      final sectors = _sectors();
      final now = DateTime.now().millisecondsSinceEpoch;
      final x = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 50,
        seed: 541,
        credits: 0,
      ).copyWith(currentSectorId: 50);
      var a = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 542,
        credits: 0,
      );
      a = a.copyWith(
        memory: a.memory.withVendetta(
          targetId: x.id,
          sectorId: 5,
          grievanceBump: 60,
          nowMs: now - 5000,
        ),
      );
      var b = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 543,
        credits: 0,
      );
      b = b.copyWith(
        memory: b.memory.withVendetta(
          targetId: x.id,
          sectorId: 7,
          grievanceBump: 20,
          nowMs: now - 1000,
        ),
      );

      final roster = [a, b, x];
      roster[0] = NpcAiService.processTurn(roster[0], sectors, [], roster);

      final updated = roster[0].memory.vendettas[x.id]!;
      expect(updated.sectorId, 7);
      expect(updated.grievance, 60);
    });

    test('gossip stays inside faction and sector', () {
      final sectors = _sectors();
      final now = DateTime.now().millisecondsSinceEpoch;
      final x = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 50,
        seed: 551,
        credits: 0,
      ).copyWith(currentSectorId: 50);
      var a = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 552,
        credits: 0,
      );
      a = a.copyWith(
        memory: a.memory.withVendetta(
          targetId: x.id,
          sectorId: 5,
          grievanceBump: 60,
          nowMs: now - 1000,
        ),
      );
      // Same sector, hostile faction.
      final pirate = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 11,
        seed: 553,
        credits: 0,
      );
      // Same faction, next sector over.
      final farTrader = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 12,
        seed: 554,
        credits: 0,
      );

      final roster = [a, pirate, farTrader, x];
      roster[0] = NpcAiService.processTurn(roster[0], sectors, [], roster);
      expect(roster[1].memory.vendettas, isEmpty);
      expect(roster[2].memory.vendettas, isEmpty);
    });

    test('hearsay alone never launches a hunt', () {
      final sectors = _sectors();
      final x = _ship(
        faction: FactionClass.pirate,
        personality: NpcPersonality.pirateHunter,
        sector: 12,
        seed: 561,
        credits: 0,
        weapons: const {'main_forward': 1},
      );
      var b = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 562,
        credits: 0,
      );
      b = b.copyWith(
        memory: b.memory.withVendetta(
          targetId: x.id,
          sectorId: 12,
          grievanceBump: NpcMemory.hearsayGrievance,
        ),
      );

      final roster = [b, x];
      b = NpcAiService.processTurn(b, sectors, [], roster);
      expect(
          b.currentGoal?.params.containsKey('vendettaFor') ?? false, isFalse);
    });

    test('evaluator boosts routes with remembered wins', () {
      final knownPorts = {
        12: const PortInfo(
          name: 'P12',
          portClass: PortClass.free,
          buyPrices: {},
          sellPrices: {'minerals': 10.0},
        ),
        13: const PortInfo(
          name: 'P13',
          portClass: PortClass.free,
          buyPrices: {'minerals': 200.0},
          sellPrices: {},
        ),
        14: const PortInfo(
          name: 'P14',
          portClass: PortClass.free,
          buyPrices: {'minerals': 170.0},
          sellPrices: {},
        ),
      };
      final sectors = [
        Sector(id: 11, name: 'A', x: 0, y: 0, warpRoutes: const [12, 13, 14]),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
        Sector(id: 13, name: 'C', x: 0, y: 1, warpRoutes: const [11]),
        Sector(id: 14, name: 'D', x: 1, y: 1, warpRoutes: const [11]),
      ];

      final plain = TradeEvaluator.findBestTradeRoute(
          11, knownPorts, sectors, 30,
          credits: 10000);
      expect(plain!.sellSectorId, 13);

      // Five remembered wins (+25%) flip the pick to the learned route.
      final learned = TradeEvaluator.findBestTradeRoute(
        11,
        knownPorts,
        sectors,
        30,
        credits: 10000,
        preferredRoutes: {'12>14:minerals': 5},
      );
      expect(learned!.sellSectorId, 14);
    });

    test('profitable sales are remembered (losses are not)', () {
      final sectors = [
        Sector(
          id: 11,
          name: 'A',
          x: 0,
          y: 0,
          warpRoutes: const [12],
          hasPort: true,
          port: const Port(
            name: 'Buyer',
            portClass: PortClass.free,
            buyPrices: {'minerals': 100.0},
            sellPrices: {},
            supply: {},
            demand: {'minerals': 100},
            maxSupply: {},
            maxDemand: {'minerals': 100},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        ),
        Sector(id: 12, name: 'B', x: 1, y: 0, warpRoutes: const [11]),
      ];
      var npc = _ship(
        faction: FactionClass.trader,
        personality: NpcPersonality.traderMerchant,
        sector: 11,
        seed: 571,
        credits: 0,
      ).copyWith(
        cargo: {'minerals': 10},
        cargoUsed: 10,
        currentGoal: NpcGoal(
          type: NpcGoalType.tradeRoute,
          status: NpcGoalStatus.travelling,
          createdAt: DateTime.now(),
          params: const {
            'targetSectorId': 11,
            'buyPortId': 12,
            'sellPortId': 11,
            'commodity': 'minerals',
            'buyPrice': 5.0,
            'phase': 'travel_to_sell',
          },
        ),
      );

      final roster = [npc];
      npc = NpcAiService.processTurn(npc, sectors, [], roster);
      // 10 × (100 − 5) profit: the route teaches.
      expect(npc.memory.profitableRoutes['12>11:minerals'], 1);
    });

    test('route wins cap and survive JSON round-trip', () {
      var memory = const NpcMemory();
      for (var i = 0; i < 15; i++) {
        memory = memory.withProfitableRoute('1>2:minerals');
      }
      expect(memory.profitableRoutes['1>2:minerals'], NpcMemory.maxRouteWins);

      final restored =
          NpcMemory.fromJson(memory.toJson().cast<String, dynamic>());
      expect(restored.profitableRoutes['1>2:minerals'], NpcMemory.maxRouteWins);
      // Legacy saves without the map default empty.
      final legacy = NpcMemory.fromJson(const {});
      expect(legacy.profitableRoutes, isEmpty);
    });

    test('sighting merges are sightings-only at the helper level', () {
      const now = 1000000;
      final mine = const NpcMemory().withVendetta(
        targetId: 'x',
        sectorId: 5,
        grievanceBump: 60,
        nowMs: now - 5000,
      );
      final theirs = {
        'x': VendettaRecord(
            sectorId: 7,
            firstSeenMs: now - 4000,
            lastSeenMs: now - 1000,
            grievance: 20),
        'y': VendettaRecord(
            sectorId: 9,
            firstSeenMs: now - 2000,
            lastSeenMs: now - 2000,
            grievance: 80),
      };
      final merged = mine.mergeSightings(theirs, nowMs: now);
      expect(merged.adopted, 1);
      expect(merged.refreshed, 1);
      expect(merged.memory.vendettas['x']!.sectorId, 7);
      expect(merged.memory.vendettas['x']!.grievance, 60);
      expect(
          merged.memory.vendettas['y']!.grievance, NpcMemory.hearsayGrievance);
      // Nothing newer: identical memory back.
      final again = merged.memory.mergeSightings(theirs, nowMs: now);
      expect(again.adopted, 0);
      expect(again.refreshed, 0);
      expect(identical(again.memory, merged.memory), isTrue);
    });
  });

  group('vendetta memory helpers', () {
    test('resolve drops the entry; absent ids are no-ops', () {
      var memory = const NpcMemory().withVendetta(
        targetId: 'killer',
        sectorId: 7,
        grievanceBump: 40,
      );
      memory = memory.withVendettaResolved('killer');
      expect(memory.vendettas, isEmpty);
      expect(identical(memory.withVendettaResolved('nobody'), memory), isTrue);
    });

    test('ease reduces, drops at zero, never refreshes the window', () {
      var memory = const NpcMemory().withVendetta(
        targetId: 'killer',
        sectorId: 7,
        grievanceBump: 40,
      );
      final window = memory.vendettas['killer']!.lastSeenMs;
      memory = memory.withVendettaEased('killer', 15);
      expect(memory.vendettas['killer']!.grievance, 25);
      expect(memory.vendettas['killer']!.lastSeenMs, window);
      memory = memory.withVendettaEased('killer', 25);
      expect(memory.vendettas, isEmpty);
      expect(identical(memory.withVendettaEased('nobody', 10), memory), isTrue);
    });
  });
}
