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
      // and wakes up to find both.
      //
      // This used to assert that the `collided` flag reached a save **condition**
      // (`if (portsRegened > 0 || ... || collided > 0)`), and the condition
      // carried the bug it was guarding: it was a hand-maintained list, so a
      // second thing the tick mutated — a colonist shipment's countdown — was
      // never listed, silently reset every tick, and could never land. So the
      // gate is gone and the universe is written every tick.
      //
      // The claim is therefore strictly stronger than before and the scan checks
      // the new shape: the roll happens, and **nothing gates the save**. This
      // remains a source scan because "there is no gate" is a fact about the
      // text; the behavioural half — that a mutation survives a reload — is
      // covered in `colonist_transit_tick_test.dart`, which drives the real
      // `GameTickService` and asserts an arrival lands on disk with nothing else
      // changing. That test is what fails when this one would pass.
      final tick =
          File('lib/services/game_tick_service.dart').readAsStringSync();
      expect(tick, contains('runDueCollisions'),
          reason: 'the roll happens in the tick');
      // Matched on **shape**, not on a variable name. The first version of this
      // check looked for the literal `if (portsRegened`, which is why it passed
      // against a gate reading `if (processed > 0)` — a guard that names the
      // counter rather than the structure cannot see a counter being renamed,
      // and "cannot fail" looks exactly like "passes". The question is only ever
      // "is an `if` in front of the save", so that is what is asked.
      expect(
        RegExp(r"if\s*\([^)]*\)\s*\{?\s*await[^;]*tick_save_sectors")
            .hasMatch(tick),
        isFalse,
        reason: 'the sector save is gated again — a hand-maintained list of '
            '"what might have changed" is what lost the countdown, and any '
            'new mutation not added to it is silently discarded',
      );
      expect(tick, contains('saveUniverse(sectors)'),
          reason: 'the tick still writes the universe at the end of the pass');
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
