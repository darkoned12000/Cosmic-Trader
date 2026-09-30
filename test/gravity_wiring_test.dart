import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Structural guards: is the gravity hazard actually *wired up*?
///
/// These are source scans rather than behaviour tests, which is a deliberate
/// exception and worth being explicit about. The thing that went wrong here was
/// not arithmetic — `rollCollision` was correct, and every test of it passed. The
/// thing that went wrong was that nothing in the application ever called it. A
/// galaxy can hold a perfectly implemented rule that no code path reaches, and
/// no amount of unit-testing the rule will notice, because the tests *do* reach
/// it: they call it directly.
///
/// A full tick integration test would catch this too, but it would be a large
/// fixture for a one-line question ("is there a call site?"). Scanning the
/// source answers exactly the question being asked, and fails loudly if the call
/// is ever moved to a file this list does not mention.
void main() {
  /// Every `lib/` Dart file, as text.
  List<File> libSources() =>
      Directory('lib').listSync(recursive: true).whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  /// Files that mention [symbol], excluding [skip].
  List<String> callersOf(String symbol, {List<String> skip = const []}) => [
        for (final f in libSources())
          if (!skip.any((s) => f.path.endsWith(s)) &&
              f.readAsStringSync().contains(symbol))
            f.path,
      ];

  group('the collision hazard is reachable from the app', () {
    test('the game tick calls the due check', () {
      // This is the guard that would have caught the original bug. The rule
      // existed, was fully tested, and was called from nowhere.
      final callers = callersOf('runDueCollisions');
      expect(callers, isNotEmpty,
          reason: 'WorldForging.runDueCollisions is implemented and tested but '
              'nothing calls it, so over-stacking can never actually destroy '
              'anything');
      expect(callers, contains('lib/services/game_tick_service.dart'),
          reason: 'the tick runs every 30s and is the natural place to ask '
              'whether a day is up');
    });

    test('a collision is persisted, not just announced', () {
      // A tick reads sectors from disk and writes them back. A collision that
      // mutates the tick's object graph without triggering the universe write is
      // resurrected on the next load — the player is told they lost two worlds
      // and wakes up to find both. The save is gated on a flag, so the guard is
      // that the flag reaches the condition.
      final tick =
          File('lib/services/game_tick_service.dart').readAsStringSync();
      expect(tick, contains('runDueCollisions'),
          reason: 'the roll happens in the tick');
      expect(tick, contains('collided'),
          reason: 'the count of destroyed worlds must be captured, or the save '
              'cannot know there is something to write');
      // The condition that persists sectors.
      final saveLine = RegExp(r'if \(portsRegened > 0[^)]*\)').firstMatch(tick);
      expect(saveLine, isNotNull, reason: 'the sector save condition moved');
      expect(saveLine!.group(0), contains('collided'),
          reason: 'a destroyed world is not written back, so it comes back on '
              'the next load');
    });

    test('the cap the tick rolls against comes from the universe settings', () {
      // Defaulting to 3 and never being set would silently apply a cap the
      // player did not choose, on a galaxy generated with a different
      // planetsPerSector.
      final shell = File('lib/screens/game_shell.dart').readAsStringSync();
      expect(shell, contains('worldCap = _settings.planetsPerSector'),
          reason: 'the tick must be told the cap, or it rolls against a guess');
      final tick =
          File('lib/services/game_tick_service.dart').readAsStringSync();
      expect(tick, contains('worldCap'),
          reason: 'the tick must hold the cap it was given');
    });
  });

  group('the hazard is announced when it happens, not when it is set up', () {
    test('a collision is written to the event log', () {
      // The one notification there is. If a collision is silent the player wakes
      // up to a missing colony with no explanation for it.
      //
      // Asserted on the string rather than on behaviour because there is no
      // behaviour to observe from here: a destroyed world is a destroyed world,
      // and the log line is the notification. A log assertion is worth more than
      // nothing and is not pretending to be a UI test.
      final forging =
          File('lib/services/world_forging.dart').readAsStringSync();
      expect(forging, contains('[Gravity]'),
          reason: 'a destroyed world is announced');
    });
  });
}
