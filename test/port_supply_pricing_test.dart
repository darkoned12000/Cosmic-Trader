import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'dart:math' show Random;

Port _port({
  Map<String, int> supply = const {},
  Map<String, int> demand = const {},
  Map<String, int> maxSupply = const {},
  Map<String, int> maxDemand = const {},
  double credits = 1000,
  double desired = 1000,
}) {
  return Port(
    name: 'Test Port',
    portClass: PortClass.free,
    buyPrices: const {'minerals': 50.0},
    sellPrices: const {'minerals': 30.0},
    supply: supply,
    demand: demand,
    maxSupply: maxSupply,
    maxDemand: maxDemand,
    portCredits: credits,
    desiredCredits: desired,
  );
}

void main() {
  test('full shelves discount, bare shelves charge premium', () {
    // Cash ratio neutral (credits == desired → multiplier 1.0).
    final full = _port(supply: {'minerals': 100}, maxSupply: {'minerals': 100});
    expect(full.supplyPriceMultiplier('minerals'), 0.75);

    final empty = _port(supply: {'minerals': 0}, maxSupply: {'minerals': 100});
    expect(empty.supplyPriceMultiplier('minerals'), 1.25);

    final half = _port(supply: {'minerals': 50}, maxSupply: {'minerals': 100});
    expect(half.supplyPriceMultiplier('minerals'), 1.0);
  });

  test('demand book mirrors: desperate pays premium, satisfied discounts', () {
    final desperate =
        _port(demand: {'minerals': 100}, maxDemand: {'minerals': 100});
    expect(desperate.demandPriceMultiplier('minerals'), 1.25);

    final satisfied =
        _port(demand: {'minerals': 0}, maxDemand: {'minerals': 100});
    expect(satisfied.demandPriceMultiplier('minerals'), 0.75);
  });

  test('missing stock lines read neutral', () {
    final port = _port();
    expect(port.supplyPriceMultiplier('minerals'), 1.0);
    expect(port.demandPriceMultiplier('minerals'), 1.0);
  });

  test('effective prices compose cash and local depth multipliers', () {
    final port = _port(
      supply: {'minerals': 0},
      maxSupply: {'minerals': 100},
    );
    // Base sell 30 × cash 1.0 × scarcity 1.25.
    expect(port.getEffectiveSellPrice('minerals'), 37.5);
    // No demand line → demand multiplier neutral; base buy 50.
    expect(port.getEffectiveBuyPrice('minerals'), 50.0);
  });

  test('owner pricing override still wins outright', () {
    final port = _port(
      supply: {'minerals': 0},
      maxSupply: {'minerals': 100},
    ).copyWith(pricingOverride: {'minerals': 2.0});
    expect(port.getEffectiveSellPrice('minerals'), 60.0);
  });

  test('drift random-walks within bounds and mean-reverts', () {
    // Deterministic: same seed replays the same walk.
    final a = _port().applyDrift(Random(7));
    final b = _port().applyDrift(Random(7));
    expect(a.driftFor('minerals'), b.driftFor('minerals'));

    // Bounds hold at every step of a long walk starting far from 1.0.
    var port = _port().copyWith(priceDrift: {'minerals': 1.4});
    for (int i = 0; i < 300; i++) {
      port = port.applyDrift(Random(i));
      for (final d in port.priceDrift.values) {
        expect(d, greaterThanOrEqualTo(0.7));
        expect(d, lessThanOrEqualTo(1.4));
      }
    }
    // Mean reversion pulls the 1.4 start back toward 1.0.
    expect(port.driftFor('minerals'), lessThan(1.2));

    // Ports with nothing to trade are untouched (identical instance).
    const bare = Port(
      name: 'Bare',
      portClass: PortClass.free,
      buyPrices: {},
      sellPrices: {},
    );
    expect(identical(bare.applyDrift(Random(1)), bare), isTrue);
  });

  test('drift factors into effective prices; overrides ignore it', () {
    final port = _port(
      supply: {'minerals': 50},
      maxSupply: {'minerals': 100},
    ).copyWith(priceDrift: {'minerals': 1.1});
    // Base sell 30 × cash 1.0 × depth 1.0 × drift 1.1.
    expect(port.getEffectiveSellPrice('minerals'), closeTo(33.0, 1e-9));

    final overridden = port.copyWith(pricingOverride: {'minerals': 2.0});
    expect(overridden.getEffectiveSellPrice('minerals'), 60.0);
  });

  test('drift survives a JSON round-trip', () {
    final port = _port().copyWith(priceDrift: {'minerals': 1.23});
    final restored = Port.fromJson(port.toJson());
    expect(restored.driftFor('minerals'), 1.23);

    // Legacy saves without the key default to neutral drift.
    final legacyJson = port.toJson()..remove('priceDrift');
    expect(Port.fromJson(legacyJson).driftFor('minerals'), 1.0);
  });

  test('homeworld premium lifts buy side only', () {
    final port = _port(
      demand: {'munitions': 50},
      maxDemand: {'munitions': 100},
    ).copyWith(
      buyPrices: {'munitions': 200.0},
      sellPrices: {'munitions': 100.0},
      regionalBuyBonus: {'munitions': 1.30},
    );
    // Buy: base 200 × cash 1.0 × demand 1.0 × drift 1.0 × premium 1.30.
    expect(port.getEffectiveBuyPrice('munitions'), closeTo(260.0, 1e-9));
    // Sell side untouched by the premium.
    expect(port.getEffectiveSellPrice('munitions'), closeTo(100.0, 1e-9));
  });

  test('anomaly boom/bust scales all bought goods', () {
    final boom = _port(
      demand: {'minerals': 50},
      maxDemand: {'minerals': 100},
    ).copyWith(anomalyBuyBonus: 1.10);
    // Base buy 50 × demand 1.0 × anomaly 1.10.
    expect(boom.getEffectiveBuyPrice('minerals'), closeTo(55.0, 1e-9));

    final bust = _port(
      demand: {'minerals': 50},
      maxDemand: {'minerals': 100},
    ).copyWith(anomalyBuyBonus: 0.90);
    expect(bust.getEffectiveBuyPrice('minerals'), closeTo(45.0, 1e-9));
  });

  test('regional bonuses compose and survive JSON', () {
    final port = _port().copyWith(
      regionalBuyBonus: {'munitions': 1.2},
      anomalyBuyBonus: 0.9,
    );
    final restored = Port.fromJson(port.toJson());
    expect(restored.regionalBuyBonus['munitions'], 1.2);
    expect(restored.anomalyBuyBonus, 0.9);

    final legacyJson = port.toJson()
      ..remove('regionalBuyBonus')
      ..remove('anomalyBuyBonus');
    final legacy = Port.fromJson(legacyJson);
    expect(legacy.regionalBuyBonus, isEmpty);
    expect(legacy.anomalyBuyBonus, 1.0);
  });
}
