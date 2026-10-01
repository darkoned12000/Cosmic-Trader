import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';

// The action log is the player's own feed. The tick service has always
// proximity-filtered the lines IT writes, but the NPC AI wrote straight
// to ActionLogProvider, so on a wide map a player read about distant
// NPCs refuelling and capturing ports while their own sector was
// silent. These guards pin the gate, and they assert BOTH halves: a far
// event is absent from the panel AND still present in GameEventLog, so
// "not shown here" can never quietly become "not recorded anywhere".

NpcShip _npc(int sector) {
  return NpcShip.create(
    faction: FactionClass.trader,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: 5000,
    seed: 4242,
  ).copyWith(
    energy: 500,
    maxEnergy: 1000,
    credits: 5000,
    currentSectorId: sector,
    // A refuel goal already aimed at the emporium it is standing on, so
    // the turn produces exactly one player-visible line and nothing
    // else competes for the assertion.
    currentGoal: NpcGoal(
      type: NpcGoalType.refuelEnergy,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: const {'targetSectorId': 11},
    ),
  );
}

Sector _emporium(int id, List<int> warps) {
  return Sector(
    id: id,
    name: 'Sector $id',
    x: 0,
    y: 0,
    warpRoutes: warps,
    hasPort: true,
    port: const Port(
      name: 'Emporium',
      portClass: PortClass.hardwareEmporium,
      buyPrices: {},
      sellPrices: {},
    ),
  );
}

/// Runs one turn for an NPC refuelling in sector 11.
void _refuelTick(List<Sector> sectors, NpcShip npc) {
  final roster = [npc];
  NpcAiService.processTurn(roster[0], sectors, [], roster);
}

/// Both logs are process-wide singletons that outlive a single test, so
/// every assertion here is a DELTA across one tick. An "is anything in
/// the log" check would be satisfied by the previous test's line — the
/// panel is a 200-entry ring and the world log 2000, and neither is
/// cleared between tests.
int _panelRefuelLines() => ActionLogProvider.global.entries
    .where(
        (e) => e.message.contains('refueled') && e.message.contains('energy'))
    .length;

int _worldRefuelLines() =>
    GameEventLog.global.query(query: 'refuel_buy').length;

void main() {
  setUp(() {
    NpcAiService.clearSignalsForTest();
    ActionLogProvider.global.clear();
  });
  tearDown(() {
    // A leaked index would silently gate every later test in this file.
    NpcAiService.endTick();
    NpcAiService.clearSignalsForTest();
  });

  final sectors = [
    _emporium(11, [12]),
    _emporium(12, [11])
  ];

  test('no tick context keeps every line (tests and direct calls)', () {
    final before = _panelRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), before + 1,
        reason: 'outside a tick nothing is filtered, so existing callers '
            'and direct processTurn tests are unaffected');
  });

  test('an event far from the player stays out of the panel', () {
    NpcAiService.beginTick(sectors, [_npc(11)], playerProximity: {99});
    final before = _panelRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), before,
        reason: 'sector 11 is nowhere near a player in sector 99');
  });

  test('a suppressed line is still filed as world news', () {
    NpcAiService.beginTick(sectors, [_npc(11)], playerProximity: {99});
    final panelBefore = _panelRefuelLines();
    final worldBefore = _worldRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), panelBefore);
    expect(_worldRefuelLines(), worldBefore + 1,
        reason: 'proximity gating must not lose the event — it files it as '
            'world news instead of as something the player watched');
  });

  test('an event near the player does reach the panel', () {
    NpcAiService.beginTick(sectors, [_npc(11)], playerProximity: {11});
    final before = _panelRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), before + 1,
        reason: 'the gate must not silence the galaxy around the player');
  });

  test('a 2-hop ring around the player counts as near', () {
    // Mirrors the tick's own _reachableWithin(p, sectors, 2): the player
    // in 12 can perceive 11, so an event there belongs in the feed.
    NpcAiService.beginTick(sectors, [_npc(11)], playerProximity: {12, 11, 13});
    final before = _panelRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), before + 1);
  });

  test('endTick restores the unfiltered behaviour', () {
    NpcAiService.beginTick(sectors, [_npc(11)], playerProximity: {99});
    NpcAiService.endTick();
    final before = _panelRefuelLines();
    _refuelTick(sectors, _npc(11));

    expect(_panelRefuelLines(), before + 1);
  });

  group('isNearPlayer', () {
    test('unset means near, so nothing is filtered by accident', () {
      expect(NpcAiService.isNearPlayer(9999), isTrue);
    });

    test('set means membership decides', () {
      NpcAiService.beginTick(sectors, const [], playerProximity: {11});
      expect(NpcAiService.isNearPlayer(11), isTrue);
      expect(NpcAiService.isNearPlayer(12), isFalse);
    });
  });

  group('a distant pilot does not narrate its own warp', () {
    // Every ship moves every tick, so an unconditional hop line is two
    // interpolations and two ring inserts per ship per tick — 200 NPCs is 400
    // lines a tick, and the 2,000-entry ring turns over in a few ticks, so
    // kills and port captures get evicted by pilots changing lanes.
    int hopLines() => GameEventLog.global
        .query(categories: {GameEventCategory.movement})
        .where((e) => e.message.contains('Sector'))
        .length;

    Sector lane(int id, List<int> warps) => Sector(
          id: id,
          name: 'S$id',
          x: 0,
          y: 0,
          warpRoutes: warps,
        );

    NpcShip patrolling(int sector, int seed) => NpcShip.create(
          faction: FactionClass.trader,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: sector,
          startingCredits: 5000,
          seed: seed,
        ).copyWith(
          energy: 1000,
          currentSectorId: sector,
          currentGoal: NpcGoal(
            type: NpcGoalType.patrol,
            status: NpcGoalStatus.travelling,
            createdAt: DateTime.now(),
            params: {'targetSectorId': sector == 11 ? 12 : 11},
          ),
        );

    test('a hop near a player is written', () {
      final sectors = [
        lane(11, [12]),
        lane(12, [11])
      ];
      final npc = patrolling(11, 31);
      NpcAiService.beginTick(sectors, [npc], playerProximity: {11, 12});

      final before = hopLines();
      final roster = [npc];
      NpcAiService.processTurn(roster[0], sectors, [], roster);
      expect(hopLines(), greaterThan(before),
          reason: 'a pilot crossing a sector you can see is news');
    });

    test('the same hop in empty space is not', () {
      // The identical movement, with nobody in earshot. This is the assertion
      // that fails if the gate is removed: the hop happens either way, so
      // only the log differs.
      final sectors = [
        lane(11, [12]),
        lane(12, [11])
      ];
      final npc = patrolling(11, 31);
      NpcAiService.beginTick(sectors, [npc], playerProximity: {9000});

      final before = hopLines();
      final roster = [npc];
      final after = NpcAiService.processTurn(roster[0], sectors, [], roster);

      expect(after.currentSectorId, 12,
          reason: 'the ship must still move — this is a logging gate, not a '
              'movement gate');
      expect(hopLines(), before,
          reason: 'a warp in empty space is position, not news, and the line '
              'is what evicts the kills out of the ring');
    });
  });
}
