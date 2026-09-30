import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/hardware_data.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/widgets/hardware_emporium_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The emporium's Equipment tab: buying and returning ordnance.
///
/// This file exists because the tab shipped with **no test at all**, and the
/// first thing a playtester did was find that buying deducted credits and changed
/// nothing else. The cause was one expression: `(held + sign).clamp(0, held)`,
/// whose upper bound of `held` clamps `held + 1` straight back down to `held`, so
/// the count could never rise. The button worked, the money left, and the figure
/// stayed at zero.
///
/// It passed `flutter analyze`, formatted clean, and looked correct in the
/// source. Nothing short of pressing the button finds it — which is the argument
/// for having this file at all.
void main() {
  /// The player **as the tab currently sees it**.
  ///
  /// One field for the whole file, not one per test. Every version of this file
  /// that opened each test with `var live = pilot(...)` shadowed a shared field
  /// with a local that nothing ever wrote, so every assertion about a purchase
  /// read a stale copy and reported zero while the widget under test was working
  /// perfectly. The failing test was the test, not the shop.
  late Player live;

  Player pilot(
          {int credits = 1000000, int torpedoes = 0, int detonators = 0}) =>
      Player(
        name: 'Tester',
        currentSectorId: 1,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 100,
        credits: credits,
        researchPoints: 0,
        faction: FactionClass.duran,
        genesisTorpedoes: torpedoes,
        atomicDetonators: detonators,
      );

  /// Hosts the **real** tab the way `GameShell` does.
  ///
  /// `EmporiumConsumablesTab` is a stateless widget whose `player` prop is fixed
  /// at build time; it reports every transaction through `onPlayerUpdate` and
  /// expects its parent to rebuild it. `_EmporiumHost` at the bottom of this file
  /// saves and `setState`s, exactly as `GameShell._updatePlayer` does — so a
  /// second tap sees the first one's result.
  Future<void> pump(WidgetTester tester, Player player) async {
    live = player;
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester
        .pumpWidget(_EmporiumHost(player: player, onUpdate: (p) => live = p));
    await tester.pump();
  }

  /// The Buy button for the torpedo (first item) or the detonator (last).
  Finder buyFor(int index) =>
      find.widgetWithText(FilledButton, 'Buy').at(index);

  /// The return control.
  ///
  /// `find.byIcon` matches the **Icon inside** the button rather than the
  /// button, so casting the list to `IconButton` throws a `_TypeError` rather
  /// than failing an assertion — which is how this file's first version of the
  /// "cannot return what you do not have" guard reported nothing useful at all.
  Finder returnButtons() =>
      find.widgetWithIcon(IconButton, Icons.remove_circle_outline);

  group('the Equipment tab renders', () {
    testWidgets('both items are listed with a price', (tester) async {
      await pump(tester, pilot());
      expect(find.text('Genesis Torpedo'), findsOneWidget);
      expect(find.text('Atomic Detonator'), findsOneWidget);
      expect(find.textContaining('50.0K'), findsOneWidget,
          reason: 'the torpedo price');
      expect(find.textContaining('5.0K'), findsOneWidget,
          reason: 'the detonator price');
    });

    testWidgets('it says ordnance takes no hold space', (tester) async {
      await pump(tester, pilot());
      expect(find.textContaining('Equipment, not cargo'), findsOneWidget);
      expect(find.textContaining('half price'), findsOneWidget);
    });
  });

  group('buying', () {
    testWidgets('from empty, the count rises and the credits fall',
        (tester) async {
      // The bug. Both halves must move together: a purchase that moves one
      // without the other is either free ordnance or a shop that takes money for
      // nothing, and only the pair proves a transaction happened.
      await pump(tester, pilot(credits: 1000000));
      expect(find.text('Held: 0'), findsNWidgets(2));

      await tester.tap(buyFor(0));
      await tester.pump();

      expect(live.genesisTorpedoes, 1,
          reason: 'a purchase from empty must change the count');
      expect(live.credits, 1000000 - 50000,
          reason: 'and it must cost the listed price');
    });

    testWidgets('the Held figure updates after the purchase', (tester) async {
      // The visible symptom: the money moved and the number did not.
      await pump(tester, pilot(credits: 1000000));
      await tester.tap(buyFor(0));
      await tester.pump();
      expect(find.text('Held: 1'), findsOneWidget);
    });

    testWidgets('buying twice takes two', (tester) async {
      // Needs the host to rebuild between taps. The tab itself is stateless and
      // reads its `player` prop, so without a rebuild the second press re-reads
      // the figure from before the first.
      await pump(tester, pilot(credits: 1000000));
      await tester.tap(buyFor(0));
      await tester.pump();
      await tester.tap(buyFor(0));
      await tester.pump();
      expect(live.genesisTorpedoes, 2);
      expect(live.credits, 1000000 - 100000);
    });

    testWidgets('buying the detonator touches only the detonator count',
        (tester) async {
      await pump(tester, pilot(credits: 1000000));
      await tester.tap(buyFor(1));
      await tester.pump();
      expect(live.atomicDetonators, 1);
      expect(live.genesisTorpedoes, 0);
      expect(live.credits, 1000000 - 5000);
    });

    testWidgets('buying does not consume hold space', (tester) async {
      // Equipment is carried on the ship, not in the hold. A purchase that moved
      // `cargoUsed` would be the Cargo/Equipment split leaking back together.
      await pump(tester, pilot(credits: 1000000));
      await tester.tap(buyFor(0));
      await tester.pump();
      expect(live.cargoUsed, 0);
    });
  });

  group('returning', () {
    testWidgets('returns half the price and reduces the count', (tester) async {
      await pump(tester, pilot(credits: 1000000, torpedoes: 1));
      final before = live.credits;

      await tester.tap(returnButtons().first);
      await tester.pump();

      expect(live.genesisTorpedoes, 0);
      expect(live.credits, before + 25000, reason: 'half of 50,000 back');
    });

    testWidgets('cannot return what you do not have', (tester) async {
      await pump(tester, pilot(credits: 1000000, torpedoes: 0));
      final buttons = tester.widgetList<IconButton>(returnButtons());
      expect(buttons, hasLength(2));
      // Disabled on the control rather than guarded in the handler, so the
      // player is never offered a tap that does nothing.
      expect(buttons.every((b) => b.onPressed == null), isTrue);
    });

    testWidgets('a return can never drive the count below zero',
        (tester) async {
      // The clamp's only real job. `(held + sign).clamp(0, held)` got the
      // decrement case right and the increment case catastrophically wrong; this
      // is the half that must not regress when the other half is touched.
      await pump(tester, pilot(credits: 1000000, torpedoes: 1));
      for (var i = 0; i < 3; i++) {
        final buttons = tester.widgetList<IconButton>(returnButtons());
        if (buttons.every((b) => b.onPressed == null)) break;
        await tester.tap(returnButtons().first);
        await tester.pump();
      }
      expect(live.genesisTorpedoes, 0);
      expect(live.atomicDetonators, 0);
    });
  });

  group('affordability', () {
    testWidgets('Buy is dead when the credits are not there', (tester) async {
      await pump(tester, pilot(credits: 1000));
      final buys = tester.widgetList<FilledButton>(find.byType(FilledButton));
      expect(buys, hasLength(2), reason: 'one per item');
      // 1,000 credits buys neither 50,000 nor 5,000.
      expect(buys.every((b) => b.onPressed == null), isTrue);
    });

    testWidgets('Buy comes alive at exactly the listed price', (tester) async {
      await pump(tester, pilot(credits: 5000));
      final buys = tester.widgetList<FilledButton>(find.byType(FilledButton));
      // The detonator is affordable, the torpedo is not.
      expect(buys.first.onPressed, isNull, reason: '50,000 is out of reach');
      expect(buys.last.onPressed, isNotNull, reason: '5,000 is not');
    });
  });

  group('the catalogue', () {
    test('the prices are what the tab shows', () {
      // Pinned because both were reduced together and the tab renders the
      // catalogue's own figure. A tab with a hardcoded price would drift from
      // the catalogue silently, which is exactly the bug class here.
      final items = itemsForCategory(HardwareCategory.consumable);
      expect(items, hasLength(2));
      expect(
          items.firstWhere((i) => i.id == 'genesisTorpedo').priceCredits, 50000,
          reason: 'a torpedo is a repeatable sink, so it has to be affordable '
              'repeatedly — 250k priced out the loop it exists to serve');
      expect(
          items.firstWhere((i) => i.id == 'atomicDetonator').priceCredits, 5000,
          reason: 'a detonator is cheap because it is only useful to undo a '
              'torpedo, and expensive enough to discourage spraying them');
    });

    test('neither is installable equipment', () {
      for (final item in itemsForCategory(HardwareCategory.consumable)) {
        expect(item.equipKey, isNull,
            reason: '${item.id} is consumed, not socketed');
      }
    });
  });
}

/// Hosts the real tab the way `GameShell` does: save, then rebuild.
///
/// The rebuild is the point. The tab is stateless and reports through a
/// callback; without a parent that re-renders it, a second tap reads a stale
/// player. That is not a quirk of the test — it is the contract the real screen
/// satisfies, and a test that ignores it is testing a configuration the game
/// never runs.
class _EmporiumHost extends StatefulWidget {
  final Player player;
  final Function(Player) onUpdate;
  const _EmporiumHost({required this.player, required this.onUpdate});

  @override
  State<_EmporiumHost> createState() => _EmporiumHostState();
}

class _EmporiumHostState extends State<_EmporiumHost> {
  late Player _player = widget.player;

  void _update(Player p) {
    widget.onUpdate(p);
    setState(() => _player = p);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(
          body: EmporiumConsumablesTab(
            player: _player,
            onPlayerUpdate: _update,
          ),
        ),
      );
}
