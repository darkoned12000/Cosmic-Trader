import 'dart:convert';

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/sector_interaction_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Faithful storage, for the same reason the colony tests need one: the panel
/// writes through to `UniverseStorage` and the launch path awaits it.
class _FaithfulUniverse extends UniverseStorage {
  _FaithfulUniverse(List<Sector> initial)
      : _blob =
            jsonEncode(initial.map((e) => e.toJson()).toList(growable: false));
  String _blob;

  @override
  Future<List<Sector>> loadUniverse() async =>
      (jsonDecode(_blob) as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(Sector.fromJson)
          .toList();

  @override
  Future<void> saveSectors(List<Sector> updated) async {
    final existing = await loadUniverse();
    for (final u in updated) {
      final i = existing.indexWhere((s) => s.id == u.id);
      if (i >= 0) existing[i] = u;
    }
    _blob = jsonEncode(existing.map((e) => e.toJson()).toList(growable: false));
  }
}

/// Over-stacking does not stop the player, and does not make a speech first.
///
/// Deliberately a **behaviour** test rather than a source scan. The first
/// version of this guard grepped the panel's source for the strings 'Unstable
/// orbit' and 'UNSTABLE', and it failed — not because the code still warned, but
/// because a *comment* explaining that the warning had been removed still
/// mentioned the removed text. A source scan is answered by prose, which is the
/// opposite of what it is for. Tapping the control and watching what happens is
/// not answerable by a comment.
void main() {
  setUp(() => UniverseStorage.instanceForTest = _FaithfulUniverse([]));
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
  Sector sectorWith(int worlds, int cap) {
    final s = Sector(
      id: 1,
      name: 'Kronos Reach',
      x: 0,
      y: 0,
      warpRoutes: const [],
      planets: List<Planet>.generate(
          worlds, (i) => Planet(name: 'W$i', planetType: 'Terran')),
    );
    return s;
  }

  Future<void> pump(WidgetTester tester, Sector sector, Player player,
      {int cap = 3}) async {
    tester.view.physicalSize = const Size(1400, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: SectorInteractionPanel(
          currentSector: sector,
          player: player,
          onPlayerUpdate: (_) {},
          settings: GameSettings.defaults().copyWith(planetsPerSector: cap),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('tapping LAUNCH in a full sector fires without asking',
      (tester) async {
    final sector = sectorWith(3, 3);
    final player = pilot();
    await pump(tester, sector, player);

    expect(find.text('LAUNCH TORPEDO'), findsOneWidget,
        reason: 'the action is offered');

    // Select the row, then fire. Every entry in this panel goes through the same
    // select-then-act flow and the torpedo row shares it, so a guard that only
    // tapped the row's label would have passed against a dead control — which is
    // exactly what this row was until the missing button turned up.
    //
    // The SELECT buttons are identical across rows, so this picks the one in the
    // launch row. The launch row is appended after every world in `_entries`, so
    // it is the last one; asserted rather than assumed, because an entry added
    // later would otherwise silently move the target and the tap would hit a
    // planet instead.
    final selects = find.text('[ SELECT ]');
    expect(selects, findsNWidgets(4),
        reason: 'three worlds plus the launch row');
    expect(find.text('LAUNCH TORPEDO'), findsOneWidget);
    await tester.tap(selects.last);
    await tester.pumpAndSettle();

    expect(find.text('Launch'), findsOneWidget,
        reason: 'selecting the row must reveal a way to fire it');
    await tester.tap(find.text('Launch'));
    await tester.pumpAndSettle();

    // No dialog stood in the way. This is the whole assertion: whatever the
    // rules are, the player is not asked to acknowledge them a fourth time.
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.textContaining('Fire anyway'), findsNothing);
    expect(find.textContaining('Unstable'), findsNothing);

    // And the launch actually happened, so the absence of the dialog is not just
    // the control being broken.
    expect(sector.livingPlanets, hasLength(4));
  });

  testWidgets('the entry reads the same whether or not the sector is full',
      (tester) async {
    // One label, not two. A row that changed its wording past the cap would be
    // the warning, just quieter.
    final roomy = sectorWith(1, 3);
    await pump(tester, roomy, pilot());
    final roomyLabel = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((d) => d.contains('LAUNCH'));

    final full = sectorWith(3, 3);
    await pump(tester, full, pilot());
    final fullLabel = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .firstWhere((d) => d.contains('LAUNCH'));

    expect(fullLabel.split(' · ').first, roomyLabel.split(' · ').first);
  });

  testWidgets('the slot count is still shown, because that is information',
      (tester) async {
    final full = sectorWith(3, 3);
    await pump(tester, full, pilot());
    // Not a warning, but the player still needs to know the sector is at its
    // limit. Facts are not nagging.
    expect(find.textContaining('3/3 slots used'), findsOneWidget);
  });
}
