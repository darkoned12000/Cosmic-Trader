import 'dart:convert';

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

// Regression probe: "trading works on a new universe but dies after
// exit + restart." A save/load cycle must preserve everything the
// trade loop needs: memory (ports + classes), mid-flight goals,
// energy, and solar state — and the reloaded NPC must keep trading.
void main() {
  List<Sector> sectors() => [
        Sector(
          id: 1,
          name: 'A',
          x: 0,
          y: 0,
          warpRoutes: const [2],
          hasPort: true,
          port: const Port(
            name: 'P1',
            portClass: PortClass.free,
            buyPrices: {},
            sellPrices: {'minerals': 10.0},
            supply: {'minerals': 5000},
            demand: {},
            maxSupply: {'minerals': 5000},
            maxDemand: {},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        ),
        Sector(
          id: 2,
          name: 'B',
          x: 1,
          y: 0,
          warpRoutes: const [1],
          hasPort: true,
          port: const Port(
            name: 'P2',
            portClass: PortClass.free,
            buyPrices: {'minerals': 200.0},
            sellPrices: {},
            supply: {},
            demand: {'minerals': 5000},
            maxSupply: {},
            maxDemand: {'minerals': 5000},
            portCredits: 1000000,
            desiredCredits: 1000000,
          ),
        ),
      ];

  NpcShip merchant() {
    var memory = const NpcMemory();
    memory = memory.withVisitedSector(1).withVisitedSector(2);
    memory = memory.withDiscoveredPort(
      1,
      const PortInfo(
        name: 'P1',
        portClass: PortClass.free,
        buyPrices: {},
        sellPrices: {'minerals': 10.0},
      ),
    );
    memory = memory.withDiscoveredPort(
      2,
      const PortInfo(
        name: 'P2',
        portClass: PortClass.free,
        buyPrices: {'minerals': 200.0},
        sellPrices: {},
      ),
    );
    return NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 2,
      startingCredits: 10000,
      seed: 31,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      memory: memory,
      energy: 777,
      maxEnergy: 1000,
      solarArrayLevel: 1,
      currentGoal: NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 1,
          'buyPortId': 1,
          'sellPortId': 2,
          'commodity': 'minerals',
          'phase': 'travel_to_buy',
        },
      ),
    );
  }

  test('full NPC save/load round-trip preserves trade state', () {
    final npc = merchant();
    // Simulate disk: JSON encode/decode like the storage layer does.
    final reloaded = NpcShip.fromJson(
      (jsonDecode(jsonEncode(npc.toJson())) as Map).cast<String, dynamic>(),
    );

    expect(reloaded.energy, 777);
    expect(reloaded.maxEnergy, 1000);
    expect(reloaded.solarArrayLevel, 1);
    expect(reloaded.memory.discoveredPorts.length, 2);
    expect(
      reloaded.memory.discoveredPorts[1]?.sellPrices['minerals'],
      10.0,
    );
    expect(
      reloaded.memory.discoveredPorts[2]?.buyPrices['minerals'],
      200.0,
    );
    expect(reloaded.currentGoal?.type, NpcGoalType.tradeRoute);
    expect(reloaded.currentGoal?.params['phase'], 'travel_to_buy');
    expect(reloaded.currentGoal?.targetSectorId, 1);
  });

  test('reloaded NPC resumes and completes its trade route', () {
    final world = sectors();
    var npc = NpcShip.fromJson(
      (jsonDecode(jsonEncode(merchant().toJson())) as Map)
          .cast<String, dynamic>(),
    );
    final startCredits = npc.credits;

    for (int tick = 0; tick < 10; tick++) {
      npc = NpcAiService.processTurn(npc, world, [], [npc]);
    }
    // Buy at P1 (tick 0→1) then sell at P2: credits must grow.
    expect(npc.credits, greaterThan(startCredits));
  });
}
