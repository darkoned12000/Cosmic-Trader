import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

// P2 scaling batch (review P6): the O(N^2)/O(N^3) paths went unnoticed
// because no test ever ran a big universe. These put a big universe
// under the suite: a full NPC sweep must complete inside a generous
// budget (hang/regression tripwire, not a perf SLA), and worst-case
// route evaluation over dozens of known ports must answer fast.
List<Sector> _chain(int n) {
  final sectors = <Sector>[];
  for (var id = 1; id <= n; id++) {
    final warps = <int>[
      if (id > 1) id - 1,
      if (id < n) id + 1,
      if (id % 50 == 0 && id + 50 <= n) id + 50,
    ];
    final ported = id % 10 == 0;
    sectors.add(Sector(
      id: id,
      name: 'S$id',
      x: id.toDouble(),
      y: 0,
      warpRoutes: warps,
      hasPort: ported,
      port: ported
          ? const Port(
              name: 'P',
              portClass: PortClass.free,
              buyPrices: {'minerals': 200.0},
              sellPrices: {'minerals': 10.0},
              supply: {'minerals': 5000},
              demand: {'minerals': 5000},
              maxSupply: {'minerals': 5000},
              maxDemand: {'minerals': 5000},
              portCredits: 1000000,
              desiredCredits: 1000000,
            )
          : null,
    ));
  }
  return sectors;
}

void main() {
  setUp(() {
    NpcAiService.clearSignalsForTest();
    BountyBoard.resetForTest();
  });
  tearDown(() {
    NpcAiService.clearSignalsForTest();
    BountyBoard.resetForTest();
    NpcAiService.endTick();
  });

  test(
    '300-sector 200-NPC sweep completes in budget',
    () {
      final sectors = _chain(300);
      final factions = FactionClass.values;
      final npcs = <NpcShip>[
        for (var i = 0; i < 200; i++)
          NpcShip.create(
            faction: factions[i % factions.length],
            shipDef: ShipDefinition.allShips.first,
            currentSectorId: 1 + (i * 37) % 300,
            startingCredits: 5000,
            seed: 7000 + i,
          ),
      ];

      NpcAiService.beginTick(sectors, npcs);
      final sw = Stopwatch()..start();
      final out = List<NpcShip>.of(npcs);
      for (var i = 0; i < out.length; i++) {
        out[i] = NpcAiService.processTurn(out[i], sectors, [], out);
      }
      sw.stop();
      NpcAiService.endTick();

      debugPrint(
          'P2 benchmark: ${out.length} NPC turns over ${sectors.length} '
          'sectors in ${sw.elapsedMilliseconds}ms '
          '(${(sw.elapsedMilliseconds / out.length).toStringAsFixed(2)}ms/turn)');
      expect(out, hasLength(npcs.length));
      expect(sw.elapsedMilliseconds, lessThan(120000));
      expect(NpcAiService.sectorById, isNull);
      expect(NpcAiService.npcsBySector, isNull);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('60-port route evaluation answers fast', () {
    final sectors = _chain(60);
    final knownPorts = <int, PortInfo>{
      for (var id = 1; id <= 60; id++)
        if (id % 2 == 0)
          id: const PortInfo(
            name: 'P',
            portClass: PortClass.free,
            buyPrices: {'minerals': 200.0},
            sellPrices: {'minerals': 10.0},
          ),
    };
    final sw = Stopwatch()..start();
    TradeRoute? route;
    for (var i = 0; i < 20; i++) {
      route = TradeEvaluator.findBestTradeRoute(
        1,
        knownPorts,
        sectors,
        500,
        credits: 100000,
      );
    }
    sw.stop();
    debugPrint(
        'P2 benchmark: 20× 30-port evaluations in ${sw.elapsedMilliseconds}ms');
    expect(route, isNotNull);
    expect(sw.elapsedMilliseconds, lessThan(60000));
  });
}
