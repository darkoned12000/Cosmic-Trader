import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/commodity.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/universe_generator.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';

// Integration: generate a universe, then tick it. Catches the class of
// bug where individually-correct systems break each other — poisoned
// generation (zero emporiums, colliding homeworlds, phantom counts),
// fedSpaceEnd edge crashes, and corrupted NPC state after ticks.
GameSettings _settings({int seed = 123, int fedSpaceEnd = 5}) {
  return GameSettings.defaults().copyWith(
    totalSectors: 20,
    fedSpaceEnd: fedSpaceEnd,
    seed: seed,
    rawSeed: seed.toString(),
  );
}

Set<int> _reachable(List<Sector> sectors, int from) {
  final byId = {for (final s in sectors) s.id: s};
  final seen = <int>{from};
  final queue = [from];
  while (queue.isNotEmpty) {
    final id = queue.removeAt(0);
    for (final n in byId[id]?.warpRoutes ?? const <int>[]) {
      if (seen.add(n)) queue.add(n);
    }
  }
  return seen;
}

void main() {
  test('fedSpaceEnd of 1 generates without crashing', () {
    final gen = UniverseGenerator(_settings(seed: 7, fedSpaceEnd: 1));
    final sectors = gen.generate();
    expect(sectors, hasLength(20));
  });

  test('generated universe invariants hold', () {
    final gen = UniverseGenerator(_settings());
    final sectors = gen.generate();
    final npcs = gen.generatedNpcs;

    // Fully connected warp graph.
    expect(_reachable(sectors, 1), hasLength(sectors.length));

    // One homeworld per major faction, no collisions.
    final homeworlds = <int, FactionClass>{};
    for (final s in sectors) {
      final p = s.planet;
      if (p != null && p.isHomeworld && p.homeworldOf != null) {
        expect(homeworlds, isNot(contains(s.id)));
        homeworlds[s.id] = p.homeworldOf!;
      }
    }
    expect(
      homeworlds.values.toSet(),
      containsAll(
          [FactionClass.duran, FactionClass.vinari, FactionClass.trader]),
    );

    // At least one emporium (minimum guarantee).
    expect(
      sectors.any((s) => s.port?.isHardwareEmporium == true),
      isTrue,
    );

    // NPC roster populated and display counts match ground truth.
    expect(npcs, isNotEmpty);
    for (final s in sectors) {
      var traders = 0, duran = 0, vinari = 0, pirates = 0;
      for (final n in npcs) {
        if (n.isDestroyed || n.currentSectorId != s.id) continue;
        switch (n.faction) {
          case FactionClass.trader:
            traders++;
            break;
          case FactionClass.duran:
            duran++;
            break;
          case FactionClass.vinari:
            vinari++;
            break;
          case FactionClass.pirate:
            pirates++;
            break;
        }
      }
      expect(s.traderCount, traders, reason: 'sector ${s.id} traders');
      expect(s.duranCount, duran, reason: 'sector ${s.id} duran');
      expect(s.vinariCount, vinari, reason: 'sector ${s.id} vinari');
      expect(s.pirateCount, pirates, reason: 'sector ${s.id} pirates');
    }

    // Base-price profitability invariant holds at generation.
    for (final s in sectors) {
      final port = s.port;
      if (port == null) continue;
      for (final c in CommodityRegistry.names) {
        final sell = port.sellPrices[c];
        final buy = port.buyPrices[c];
        if (sell != null && buy != null) {
          fail('port ${port.name} both buys and sells $c');
        }
      }
    }
  });

  test('fresh NPCs survive ten ticks with non-negative credits', () {
    final gen = UniverseGenerator(_settings(seed: 99));
    final sectors = gen.generate();
    var npcs = List.of(gen.generatedNpcs);
    expect(npcs, isNotEmpty);

    for (int tick = 0; tick < 10; tick++) {
      for (int i = 0; i < npcs.length; i++) {
        npcs[i] = NpcAiService.processTurn(npcs[i], sectors, [], npcs);
      }
    }
    for (final n in npcs) {
      expect(n.credits, greaterThanOrEqualTo(0), reason: n.pilotName);
      expect(n.energy,
          allOf(greaterThanOrEqualTo(0), lessThanOrEqualTo(n.maxEnergy)));
    }
  });
}
