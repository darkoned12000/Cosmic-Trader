import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_memory.dart';

NpcShip _npc({
  int energy = 1000,
  int maxEnergy = 1000,
  int credits = 10000,
  int bankBalance = 0,
  int engineLevel = 1,
  int solarArrayLevel = 0,
  bool solarArrayDeployed = false,
  int sector = 1,
  List<int> knownEmporiums = const [],
}) {
  var memory = const NpcMemory();
  for (final id in knownEmporiums) {
    memory = memory.withDiscoveredPort(
      id,
      const PortInfo(
        name: 'Emporium',
        portClass: PortClass.hardwareEmporium,
        buyPrices: {},
        sellPrices: {},
      ),
    );
  }
  return NpcShip.create(
    faction: FactionClass.trader,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: sector,
    startingCredits: credits,
    seed: 42,
  ).copyWith(
    energy: energy,
    maxEnergy: maxEnergy,
    bankBalance: bankBalance,
    engineEquipmentLevel: engineLevel,
    solarArrayLevel: solarArrayLevel,
    solarArrayDeployed: solarArrayDeployed,
    currentSectorId: sector,
    memory: memory,
  );
}

Sector _sector(int id, List<int> warps, {bool emporium = false}) {
  return Sector(
    id: id,
    name: 'Sector $id',
    x: 0,
    y: 0,
    warpRoutes: warps,
    hasPort: emporium,
    port: emporium
        ? const Port(
            name: 'Emporium',
            portClass: PortClass.hardwareEmporium,
            buyPrices: {},
            sellPrices: {},
          )
        : null,
  );
}

void main() {
  test('legacy turns populate NPC energy on old save files', () {
    final npc = _npc();
    final legacyJson = npc.toJson()
      ..remove('energy')
      ..remove('maxEnergy');
    legacyJson['turns'] = 432;

    final restored = NpcShip.fromJson(legacyJson);
    expect(restored.energy, 432);
    expect(restored.maxEnergy, 1000);
  });

  test('NPC warp cost scales with engine level', () {
    final basic = _npc(engineLevel: 1);
    final upgraded = _npc(engineLevel: 5);

    expect(EnergyService.npcWarpCost(basic), 10);
    expect(EnergyService.npcWarpCost(upgraded), 2);
    expect(EnergyService.npcCanWarp(_npc(energy: 0)), isFalse);
    expect(EnergyService.npcCanWarp(_npc(energy: 10)), isTrue);
  });

  test('NPC refuel buys only what tank needs and credits afford', () {
    final npc = _npc(energy: 990, maxEnergy: 1000, credits: 5);
    expect(EnergyService.npcMissingEnergy(npc), 10);

    final result = EnergyService.npcRefuel(npc);
    expect(result.unitsAdded, 5);
    expect(result.creditsSpent, 5);
    expect(result.npc.energy, 995);
    expect(result.npc.credits, 0);
  });

  test('NPC solar array only recharges while deployed', () {
    final noArray = _npc(energy: 100, maxEnergy: 200);
    expect(EnergyService.npcSolarRecharge(noArray).unitsAdded, 0);

    final retracted = _npc(
      energy: 100,
      maxEnergy: 200,
      solarArrayLevel: 2,
    );
    expect(EnergyService.npcSolarRechargePerTick(retracted), 4);
    expect(EnergyService.npcSolarRecharge(retracted).unitsAdded, 0);

    final deployed = retracted.copyWith(solarArrayDeployed: true);
    expect(deployed.canMove, isFalse);
    final charged = EnergyService.npcSolarRecharge(deployed);
    expect(charged.unitsAdded, 4);
    expect(charged.npc.energy, 104);
  });

  test('movement spends energy', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1])
    ];
    final npc = _npc(energy: 100, sector: 1).copyWith(
      currentGoal: NpcGoal(
        type: NpcGoalType.explore,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {'targetSectorId': 2},
      ),
    );

    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(after.currentSectorId, 2);
    expect(after.energy, 100 - EnergyService.npcWarpCost(npc));
  });

  test('zero-energy NPC does not move and takes emergency reserve', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1])
    ];
    final npc = _npc(energy: 0, credits: 5000, sector: 1);

    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(after.currentSectorId, 1);
    expect(after.energy, greaterThan(0));
  });

  test('broke stranded NPC still gets a reserve (never idles forever)', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1])
    ];
    final npc = _npc(energy: 0, credits: 0, bankBalance: 0, sector: 1);

    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(after.energy, greaterThan(0));
    expect(after.credits, 0);
  });

  test('low-energy NPC seeks refuel at nearest discovered emporium', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1], emporium: true)
    ];
    final npc = _npc(energy: 5, credits: 5000, sector: 1, knownEmporiums: [2]);

    expect(NpcAiService.shouldRefuel(npc, sectors), isTrue);
    final goal = NpcAiService.createRefuelGoal(npc, sectors);
    expect(goal, isNotNull);
    expect(goal!.targetSectorId, 2);

    // Unknown emporium → no goal (memory, not the map, decides).
    expect(
      NpcAiService.createRefuelGoal(_npc(energy: 5, credits: 5000, sector: 1), [
        _sector(1, [2]),
        _sector(2, [1])
      ]),
      isNull,
    );
  });

  test('undiscovered emporiums are invisible to NPCs', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1], emporium: true)
    ];
    // Same universe, but this NPC has never scanned sector 2.
    final naive = _npc(energy: 5, credits: 5000, sector: 1);
    expect(NpcAiService.knownEmporiumSectors(naive), isEmpty);
    expect(NpcAiService.createRefuelGoal(naive, sectors), isNull);
    // Still wants fuel — so processTurn sends it exploring, not sitting.
    expect(NpcAiService.shouldRefuel(naive, sectors), isTrue);
    final after = NpcAiService.processTurn(naive, sectors, [], [naive]);
    expect(after.currentGoal?.type, NpcGoalType.explore);
  });

  test('refuel trigger is distance-aware, not a flat hop reserve', () {
    // Chain 1—2—…—21, emporium only at 21 (20 hops from sector 1).
    List<Sector> chain(int length) => List.generate(length, (i) {
          final id = i + 1;
          final warps = <int>[
            if (id > 1) id - 1,
            if (id < length) id + 1,
          ];
          return _sector(id, warps, emporium: id == length);
        });

    final far = chain(21);
    // 15% tank (150): trip home costs 20×10 + 20 reserve = 220 → refuel.
    expect(
        NpcAiService.shouldRefuel(
            _npc(energy: 150, sector: 1, knownEmporiums: [21]), far),
        isTrue);
    // Same tank, efficient engine (2/hop → trip 44+4=48 < 150) → carry on.
    expect(
        NpcAiService.shouldRefuel(
            _npc(energy: 150, engineLevel: 5, sector: 1, knownEmporiums: [21]),
            far),
        isFalse);
    // Same tank, emporium next door (trip 10+20=30 < 150) → carry on.
    final near = [
      _sector(1, [2]),
      _sector(2, [1], emporium: true)
    ];
    expect(
        NpcAiService.shouldRefuel(
            _npc(energy: 150, sector: 1, knownEmporiums: [2]), near),
        isFalse);
    // Half tank never triggers, no matter the distance.
    expect(
        NpcAiService.shouldRefuel(
            _npc(energy: 500, sector: 1, knownEmporiums: [21]), far),
        isFalse);
    // Below the 10% floor always triggers when an emporium exists.
    expect(
        NpcAiService.shouldRefuel(
            _npc(energy: 50, sector: 1, knownEmporiums: [2]), near),
        isTrue);
  });

  test('NPC refuels on arrival at emporium', () {
    final sectors = [
      _sector(1, [2]),
      _sector(2, [1], emporium: true)
    ];
    final npc = _npc(
        energy: 10,
        maxEnergy: 1000,
        credits: 5000,
        sector: 2,
        knownEmporiums: [2]).copyWith(
      currentGoal: NpcGoal(
        type: NpcGoalType.refuelEnergy,
        status: NpcGoalStatus.travelling,
        createdAt: DateTime.now(),
        params: {'targetSectorId': 2},
      ),
    );

    final after = NpcAiService.processTurn(npc, sectors, [], [npc]);
    expect(after.energy, greaterThan(10));
    expect(after.credits, lessThan(5000));
    // Refuel completed, so the NPC moved on: goal is no longer refuel.
    expect(after.currentGoal?.type, isNot(NpcGoalType.refuelEnergy));
  });
}
