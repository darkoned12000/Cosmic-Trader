import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';

void main() {
  test('successful hack record survives player persistence', () {
    final player = Player(
      name: 'Tester',
      currentSectorId: 1,
      hull: 100,
      maxHull: 100,
      shields: 50,
      maxShields: 50,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 5,
      credits: 1000,
      researchPoints: 0,
      successfulHacks: 4,
      hackedPorts: const ['Alpha Port'],
      lastHackAt: DateTime(2026, 1, 2),
      portHackFailures: const {'Alpha Port': 3},
      portHackBannedUntil: const {'Alpha Port': 9999999999999},
      factionStandings: const {'pirate': -42},
      lastHackProfile: 'HIGH SECURITY',
      lastHackReward: 'AGGRESSIVE CREDITS +2500 CR',
    );

    final restored = Player.fromJson(player.toJson());

    expect(restored.successfulHacks, 4);
    expect(restored.hackedPorts, ['Alpha Port']);
    expect(restored.lastHackAt, DateTime(2026, 1, 2));
    expect(restored.portHackFailures['Alpha Port'], 3);
    expect(restored.portHackBannedUntil['Alpha Port'], 9999999999999);
    expect(restored.factionStandings['pirate'], -42);
    expect(restored.lastHackProfile, 'HIGH SECURITY');
    expect(restored.lastHackReward, 'AGGRESSIVE CREDITS +2500 CR');
    expect(
      restored
          .copyWith(successfulHacks: restored.successfulHacks + 1)
          .successfulHacks,
      5,
    );
    expect(
      restored
          .withFactionStandingChange(FactionClass.pirate, -5)
          .factionStandingWith(FactionClass.pirate),
      -47,
    );
  });
}
