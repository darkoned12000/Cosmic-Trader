import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sibling widgets must have **unique keys**, and every one of them must have
/// one.
///
/// This is a documented Flutter invariant — `Column` throws "Duplicate keys
/// found" — but `GameShell`'s navigation stack is an `IndexedStack`, which does
/// **not** enforce it. So the collision was invisible: it ran only by accident of
/// `updateChildren`'s index-advancing, would have broken silently on a reorder,
/// and produced no error pointing at the cause. `IndexedStack` and `Column`
/// cannot be swapped here (the stack is what keeps offstage tabs alive), so
/// nothing but a check will catch a reintroduction.
///
/// A source scan is the right tool for this and the wrong tool for almost
/// everything else: this is a structural fact — *do these two keys collide* —
/// which no behavioural test can observe without building the whole shell, and
/// which would read as "everything renders" even with a confused element tree.
/// The failure mode a source scan does have is being answered by prose, so this
/// parses the construction sites rather than grepping for a name.
void main() {
  /// The navigation screens that read the universe and reload together.
  const navScreens = [
    'SectorView',
    'GalaxyMap',
    'ComputerScreen',
    'PortScreen',
    'PlanetScreen',
    'ShipStatusView',
  ];

  String source() => File('lib/screens/game_shell.dart').readAsStringSync();

  /// **Every** key a screen is constructed with, in source order.
  ///
  /// `allMatches`, not `firstMatch`. The first version of this guard read only
  /// the first construction site, and fault injection found the hole at once:
  /// deleting the key from the *rail* layout left the wide layout's key visible,
  /// so the guard reported "ShipStatusView is keyed" and passed — for exactly the
  /// defect it existed to prevent, a screen re-keyed in one layout only. Same
  /// family as a rank lookup that returns on the first match: it answers "is
  /// there one?" when the question is "is there exactly one, everywhere?".
  List<String> keysOf(String screen) =>
      RegExp('${screen}\\(\\s*\\n\\s*key:\\s*([A-Za-z_][A-Za-z0-9_]*),')
          .allMatches(source())
          .map((m) => m.group(1)!)
          .toList();

  /// How many times the screen is constructed. The wide and rail layouts each
  /// build the whole stack, so this is 2 per screen.
  int sitesOf(String screen) =>
      RegExp('$screen\\(').allMatches(source()).length;

  test('every navigation screen is keyed at every construction site', () {
    final missing = <String>[];
    final disagreed = <String>[];

    for (final screen in navScreens) {
      final keys = keysOf(screen);
      final sites = sitesOf(screen);
      if (sites == 0) {
        missing.add('$screen (not found — the scan is not matching)');
        continue;
      }
      if (keys.length < sites) {
        missing.add('$screen (${keys.length}/$sites keyed)');
      } else if (keys.toSet().length > 1) {
        disagreed.add('$screen: ${keys.join(" and ")}');
      }
    }

    expect(missing, isEmpty,
        reason: 'an unkeyed navigation screen is not re-keyed on regeneration, '
            'so it keeps serving the old universe while its siblings reload');

    expect(disagreed, isEmpty,
        reason: 'the wide and rail layouts must agree on a screen\'s key; '
            'disagreeing means regeneration re-keys it in one layout only');
  });

  test('no two navigation screens share a key', () {
    final byField = <String, Set<String>>{};
    for (final screen in navScreens) {
      for (final key in keysOf(screen)) {
        // A **set**, because each screen is constructed once per layout and so
        // appears twice. A list reported every screen as colliding with itself,
        // which is not a defect at all — the first version of this test failed on
        // a clean file for exactly that reason, and the sanity check below is what
        // made the shape obvious instead of leaving it looking like a real bug.
        byField.putIfAbsent(key, () => <String>{}).add(screen);
      }
    }

    final collisions = byField.entries
        .where((e) => e.value.length > 1)
        .map((e) => '${e.key} -> ${(e.value.toList()..sort()).join(', ')}')
        .toList();

    expect(collisions, isEmpty,
        reason: 'sibling widgets must have unique keys; these screens share '
            'one field, which IndexedStack does not check and Column would '
            'reject outright');

    // Sanity: the scan actually matched the construction sites. Without this, a
    // reformatted constructor would leave every list empty and both tests would
    // pass on an empty answer rather than a clean one.
    expect(byField.length, greaterThanOrEqualTo(5),
        reason: 'the scan matched almost nothing — it is no longer reading '
            'the construction sites');
  });
}
