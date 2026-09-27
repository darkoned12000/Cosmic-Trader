import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';

// Regression: overlapping ticks at 1s dev intervals loaded/saved the same
// JSON concurrently — metrics counted both runs while last-write-wins
// storage kept one, producing phantom trade volume (1100 buys, ~20 sells,
// ~500 units actually held). The second concurrent tick must skip.
void main() {
  test('concurrent ticks skip instead of overlapping', () async {
    final service = GameTickService();
    var starts = 0;
    service.onTickStart = () => starts++;
    service.onTickError = (_) {};

    // Storage is unavailable in unit tests, so the first tick suspends on
    // load failure while holding the in-progress flag; the second call
    // must observe it and skip.
    await Future.wait([
      service.processTickNow(),
      service.processTickNow(),
    ]);

    expect(starts, 1);
    expect(service.overlapSkips, 1);
  });

  test('sequential ticks both run', () async {
    final service = GameTickService();
    var starts = 0;
    service.onTickStart = () => starts++;
    service.onTickError = (_) {};

    await service.processTickNow();
    await service.processTickNow();

    expect(starts, 2);
    expect(service.overlapSkips, 0);
  });

  test('clearWrecks drops destroyed hulls, keeps the living', () {
    final living = NpcShip.create(
      faction: FactionClass.trader,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 11,
      startingCredits: 0,
      seed: 1,
    );
    final wreck = NpcShip.create(
      faction: FactionClass.pirate,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 11,
      startingCredits: 0,
      seed: 2,
    ).copyWith(isDestroyed: true);
    final roster = [living, wreck, wreck];
    expect(GameTickService.clearWrecks(roster), 2);
    expect(roster, [living]);
    expect(GameTickService.clearWrecks(roster), 0);
  });
}
