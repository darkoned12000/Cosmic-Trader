import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/services/game_clock.dart';

void main() {
  test('port sabotage state survives JSON persistence', () {
    // A tick deadline, and the clock pinned so the assertion is about the
    // deadline rather than about when the test happened to run.
    GameClock.resetForTest(1000);
    addTearDown(GameClock.resetForTest);

    // 30 minutes is 60 ticks — the conversion the whole game now speaks.
    final until = GameClock.tick + GameClock.ticksPerHour ~/ 2;
    final port = Port(
      name: 'Test Port',
      portClass: PortClass.independent,
      buyPrices: const {},
      sellPrices: const {},
      securityCompromisedUntilTick: until,
    );

    final restored = Port.fromJson(port.toJson());

    expect(restored.securityCompromisedUntilTick, until);
    expect(restored.isSecurityCompromised, isTrue);

    // Still compromised a tick before it lapses, and lapses on the tick.
    GameClock.resetForTest(until - 1);
    expect(restored.isSecurityCompromised, isTrue,
        reason:
            'the boundary matters: due at `until` and not at `until - 1` is '
            'what makes it a deadline rather than a smear');
    GameClock.resetForTest(until);
    expect(restored.isSecurityCompromised, isFalse);

    expect(
      restored.copyWith(clearSecurityCompromised: true).isSecurityCompromised,
      isFalse,
    );
  });

  test('closing the game does not expire a sabotage', () {
    // The property the wall-clock stamp got wrong. A 30-minute debuff that
    // expires while the player is not playing is a debuff with no cost to them,
    // and since the deadline is persisted, reopening the app is all it took to
    // clear one.
    GameClock.resetForTest(500);
    addTearDown(GameClock.resetForTest);

    final port = Port(
      name: 'Test Port',
      portClass: PortClass.independent,
      buyPrices: const {},
      sellPrices: const {},
      securityCompromisedUntilTick: 500 + GameClock.ticksPerHour ~/ 2,
    );

    // "A week later" in wall-clock terms. The clock has not moved, because the
    // game was closed the whole time, so the debuff is untouched.
    expect(port.isSecurityCompromised, isTrue);

    // Sixty ticks of play — thirty minutes — and only then does it lapse.
    GameClock.resetForTest(500 + GameClock.ticksPerHour ~/ 2);
    expect(port.isSecurityCompromised, isFalse);
  });
}
