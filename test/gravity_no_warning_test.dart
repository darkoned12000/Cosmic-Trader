import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/genesis_launcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/storage_fakes.dart';

/// Faithful storage: it re-parses on every read and actually writes, because the
/// launch path awaits the write-through and a shared-list fake would make an
/// unsaved mutation structurally impossible to observe.

/// Over-stacking does not stop the player, and does not make a speech first.
///
/// Deliberately a **behaviour** test. The first version of this guard grepped the
/// panel's source for the words 'Unstable' and 'UNSTABLE' and failed — not because
/// the code still warned, but because a *comment* explaining the removal still
/// mentioned them. A source scan is answered by prose, which is the opposite of
/// what it is for.
///
/// It used to drive the Sector Contents orbit row, which no longer exists \u2014 the
/// Ship screen's Cargo & Equipment card is now the single launch point. The
/// *rule* under test never lived in either: it lives in [runGenesisLaunch], so
/// that is what gets driven here. Testing the shared function rather than one
/// of its two entry points is the point of having extracted it.
void main() {
  setUp(() => UniverseStorage.instanceForTest = FaithfulUniverse([]));
  tearDown(() => UniverseStorage.instanceForTest = null);

  Player pilot({int torpedoes = 1}) => Player(
        name: 'Tester',
        currentSectorId: 1,
        hull: 100,
        maxHull: 100,
        shields: 100,
        maxShields: 100,
        cargoUsed: 0,
        maxCargo: 100,
        cargoSize: 100,
        credits: 500000,
        researchPoints: 0,
        faction: FactionClass.duran,
        genesisTorpedoes: torpedoes,
      );

  /// A sector holding [worlds] worlds against [cap].
  Sector sectorWith(int worlds) => Sector(
        id: 1,
        name: 'Kronos Reach',
        x: 0,
        y: 0,
        warpRoutes: const [],
        planets: List<Planet>.generate(
            worlds, (i) => Planet(name: 'W$i', planetType: 'Terran')),
      );

  /// A host that mirrors what the real launch buttons do: read the player from
  /// its own field, hand the updated one back through the callback.
  ///
  /// It has to **rebuild from what the callback returned**. A host that passed
  /// the player in once and mutated a local would read a stale copy on a second
  /// launch, and the guard would report zero while the flow worked perfectly \u2014
  /// the same shape of bug the colony tests hit.
  Future<void> pump(WidgetTester tester, Sector sector, Player player,
      {int cap = 3}) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var live = player;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: _LauncherHost(
          sector: sector,
          cap: cap,
          player: live,
          onPlayerUpdate: (p) => live = p,
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a full sector is disclosed inline, while naming',
      (tester) async {
    final sector = sectorWith(3);
    await pump(tester, sector, pilot());

    await tester.tap(find.text('LAUNCH'));
    await tester.pumpAndSettle();

    // Named first, warned once, and the warning arrives *with the name* rather
    // than as a separate gate the player has to acknowledge before they can
    // finish typing.
    expect(find.text('Name this world'), findsOneWidget);
    expect(find.textContaining('gravitationally unstable'), findsOneWidget,
        reason: 'over-stacking is disclosed before the launch, not after');
  });

  testWidgets('an empty name cannot be launched', (tester) async {
    final sector = sectorWith(1);
    await pump(tester, sector, pilot());
    await tester.tap(find.text('LAUNCH'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Launch'),
    );
    expect(button.onPressed, isNotNull,
        reason: 'prefilled, so it starts valid');

    // Clear it. The confirm must go dead rather than silently substituting the
    // suggestion \u2014 a player who emptied the box to type their own name should
    // not get a name they never chose.
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Launch'))
          .onPressed,
      isNull,
    );
    expect(sector.worldSlotsUsed, 1, reason: 'nothing was created');
  });

  testWidgets('the type is never revealed before the launch commits',
      (tester) async {
    // The leak: the dialog used to be titled "A <Type> World", which turned the
    // naming step into a free reroll \u2014 read the roll, abort if it was wrong, fire
    // again, since aborting costs nothing.
    final sector = sectorWith(1);
    await pump(tester, sector, pilot());
    await tester.tap(find.text('LAUNCH'));
    await tester.pumpAndSettle();

    expect(
        find.text('Planet Creation Process Initiated\u2026'), findsOneWidget);

    final dialogText = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(AlertDialog), matching: find.byType(Text)))
        .map((t) => t.data ?? '')
        .join(' ');
    for (final type in Planet.allTypes) {
      expect(dialogText, isNot(contains(type)),
          reason: 'the dialog leaked the $type roll');
    }
  });

  testWidgets('and it is revealed afterwards, once the launch is committed',
      (tester) async {
    final sector = sectorWith(1);
    await pump(tester, sector, pilot());
    await tester.tap(find.text('LAUNCH'));
    await tester.pumpAndSettle();

    final dialogLaunch = find.descendant(
        of: find.byType(AlertDialog), matching: find.text('Launch'));
    await tester.tap(dialogLaunch);
    await tester.pumpAndSettle();

    // Post-hoc disclosure is fine and useful \u2014 the finding out is on landing.
    expect(sector.worldSlotsUsed, 2);
    expect(sector.livingPlanets.last.planetType, isIn(Planet.allTypes));
  });
}

/// Minimal host for [runGenesisLaunch].
class _LauncherHost extends StatefulWidget {
  final Sector sector;
  final int cap;
  final Player player;
  final ValueChanged<Player> onPlayerUpdate;

  const _LauncherHost({
    required this.sector,
    required this.cap,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<_LauncherHost> createState() => _LauncherHostState();
}

class _LauncherHostState extends State<_LauncherHost> {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: ElevatedButton(
        onPressed: () async {
          final outcome = await runGenesisLaunch(
            context: context,
            player: widget.player,
            sector: widget.sector,
            worldCap: widget.cap,
          );
          if (outcome == null || !mounted) return;
          widget.onPlayerUpdate(outcome.player);
          setState(() {});
        },
        child: const Text('LAUNCH'),
      ),
    );
  }
}
