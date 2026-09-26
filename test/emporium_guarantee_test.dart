import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

Sector _sector(int id, List<int> warps, {Port? port}) => Sector(
      id: id,
      name: 'S$id',
      x: 0,
      y: 0,
      warpRoutes: warps,
      hasPort: port != null,
      port: port,
    );

const _dock = Port(
  name: 'Dock',
  portClass: PortClass.free,
  buyPrices: {},
  sellPrices: {},
);

void main() {
  test('universe without emporiums gains exactly the minimum', () {
    final sectors = [
      _sector(11, [12], port: _dock),
      _sector(12, [11, 13], port: _dock),
      _sector(13, [12], port: _dock),
    ];
    UniverseGenerator.ensureMinimumEmporiums(sectors, 1, math.Random(3));
    final count =
        sectors.where((s) => s.port?.isHardwareEmporium == true).length;
    expect(count, 1);
    // Converted port keeps its books and stays out of FedSpace.
    final emporium =
        sectors.firstWhere((s) => s.port?.isHardwareEmporium == true);
    expect(emporium.id, greaterThan(9));
  });

  test('satisfied minimum is left untouched', () {
    final sectors = [
      _sector(11, [12],
          port: const Port(
            name: 'E',
            portClass: PortClass.hardwareEmporium,
            buyPrices: {},
            sellPrices: {},
          )),
      _sector(12, [11], port: _dock),
    ];
    UniverseGenerator.ensureMinimumEmporiums(sectors, 1, math.Random(3));
    expect(
      sectors.where((s) => s.port?.isHardwareEmporium == true).length,
      1,
    );
    expect(sectors[1].port?.portClass, PortClass.free);
  });

  NpcShip trader({required int energy, NpcGoal? goal}) {
    return NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 1,
      startingCredits: 50000,
      seed: 91,
    ).copyWith(
      personality: NpcPersonality.traderMerchant,
      energy: energy,
      currentGoal: goal,
    );
  }

  NpcGoal tradeGoal() => NpcGoal(
        type: NpcGoalType.tradeRoute,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {
          'targetSectorId': 2,
          'buyPortId': 2,
          'sellPortId': 1,
          'commodity': 'minerals',
          'phase': 'travel_to_buy',
        },
      );

  test('low-energy trade survives unknown-emporium fallback', () {
    // No emporium anywhere: old code replaced the travelling trade with
    // explore every tick below 25%, permanently suppressing selection.
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1])
    ];
    var npc = trader(energy: 100, goal: tradeGoal());

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.currentGoal?.type, NpcGoalType.tradeRoute);
  });

  test('low-energy patrol still falls back to explore', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1])
    ];
    var npc = trader(
      energy: 100,
      goal: NpcGoal(
        type: NpcGoalType.patrol,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: const {'targetSectorId': 1},
      ),
    );

    npc = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(npc.currentGoal?.type, NpcGoalType.explore);
  });
}
