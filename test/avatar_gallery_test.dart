import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/avatar_editor_screen.dart';
import 'package:cosmic_trader/screens/register_screen.dart';
import 'package:cosmic_trader/screens/ship_status.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_gallery.dart';

Player _pilot(
    {FactionClass faction = FactionClass.trader, AvatarSelection? avatar}) {
  return Player(
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
    faction: faction,
    avatar: avatar,
  );
}

/// Hosts an [AvatarGallery] and keeps the current selection in real state.
///
/// A `StatefulBuilder` alone is not enough: passing a freshly-computed
/// selection inline would hand the gallery an identical value on every rebuild
/// and silently swallow the update under test.
class _GalleryHost extends StatefulWidget {
  const _GalleryHost({
    required this.species,
    required this.initial,
    this.onChanged,
  });

  final AvatarSpecies species;
  final AvatarSelection initial;
  final ValueChanged<AvatarSelection>? onChanged;

  @override
  State<_GalleryHost> createState() => _GalleryHostState();
}

class _GalleryHostState extends State<_GalleryHost> {
  late AvatarSelection _selection = widget.initial;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AvatarGallery(
        species: widget.species,
        selection: _selection,
        onChanged: (value) {
          setState(() => _selection = value);
          widget.onChanged?.call(value);
        },
      ),
    );
  }
}

/// Fake universe storage so ShipStatusView finishes its loading state without
/// touching the filesystem.
class _FakeUniverseStorage extends UniverseStorage {
  _FakeUniverseStorage(this.sectors);

  final List<Sector> sectors;

  @override
  Future<void> ensureUniverse() async {}

  @override
  Future<List<Sector>> loadUniverse() async => sectors;

  @override
  void logSectorStats(List<Sector> _) {}
}

Sector _sector(int id, String name) =>
    Sector(id: id, name: name, x: id * 10.0, y: 0, warpRoutes: const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory documentsDir;

  setUp(() {
    // RegisterScreen.initState loads settings, and PlayerStorage reads players
    // from the same directory, so point path_provider at a real temp folder.
    documentsDir = Directory.systemTemp.createTempSync('ct_avatar_documents');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      pathProviderChannel,
      (call) async => documentsDir.path,
    );
    UniverseStorage.instanceForTest = _FakeUniverseStorage([
      _sector(1, 'Alpha Prime'),
      _sector(2, 'Beta Reach'),
    ]);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathProviderChannel, null);
    UniverseStorage.instanceForTest = null;
    if (documentsDir.existsSync()) {
      documentsDir.deleteSync(recursive: true);
    }
  });

  group('AvatarCanvas', () {
    testWidgets('renders a portrait for a selection that does not exist', (
      WidgetTester tester,
    ) async {
      // A removed id must not produce a broken-image box; the faction default
      // stands in.
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: AvatarCanvas(
            selection: AvatarSelection(
              species: AvatarSpecies.duran,
              presentation: AvatarPresentation.male,
              portraitId: 'duran_male_deleted_99',
            ),
            size: 96,
          ),
        ),
      ));

      expect(find.byType(AvatarCanvas), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'an unknown portrait id must fall back, not throw');
    });

    testWidgets('exposes an accessible label naming the portrait', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AvatarCanvas(
            selection: AvatarSelection.defaultFor(FactionClass.vinari),
            size: 96,
          ),
        ),
      ));

      final expected = AvatarCatalog.defaultFor(AvatarSpecies.vinari).label;
      expect(
        find.bySemanticsLabel('$expected portrait'),
        findsOneWidget,
        reason: 'portraits must be distinguishable without relying on colour',
      );
    });

    testWidgets('falls back to the preset for a custom source with no file', (
      WidgetTester tester,
    ) async {
      // Uploads are not implemented yet; this must not surface as a hole.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AvatarCanvas(
            selection: AvatarSelection(
              species: AvatarSpecies.terran,
              presentation: AvatarPresentation.female,
              portraitId: 'terran_female_pilot_02',
              source: AvatarSource.custom,
              customFile: 'missing.png',
            ),
            size: 96,
          ),
        ),
      ));

      expect(tester.takeException(), isNull);
    });

    testWidgets('paints without error at thumbnail and preview sizes', (
      WidgetTester tester,
    ) async {
      // The design doc calls out readability at 48px as well as the larger
      // gallery size, so exercise both.
      for (final size in [32.0, 48.0, 64.0, 112.0]) {
        for (final portrait in AvatarCatalog.portraits) {
          await tester.pumpWidget(MaterialApp(
            home: Scaffold(
              body: AvatarCanvas(
                selection: AvatarSelection(
                  species: portrait.species,
                  presentation: portrait.presentation,
                  portraitId: portrait.id,
                ),
                size: size,
              ),
            ),
          ));
          expect(tester.takeException(), isNull,
              reason: '${portrait.id} at $size must paint cleanly');
        }
      }
    });
  });

  group('AvatarGallery', () {
    /// Taps the first other portrait in the current tab and returns it.
    Future<AvatarPortrait> pickFirstOther(
      WidgetTester tester,
      AvatarSelection current,
    ) async {
      final target = AvatarCatalog.forSpecies(
        current.species,
        presentation: current.presentation,
      ).firstWhere((p) => p.id != current.portraitId);
      await tester.tap(find.text(target.label).first);
      await tester.pump();
      return target;
    }

    testWidgets('selecting a thumbnail reports a new selection', (
      WidgetTester tester,
    ) async {
      AvatarSelection? changed;
      await tester.pumpWidget(MaterialApp(
        home: _GalleryHost(
          species: AvatarSpecies.duran,
          initial: AvatarSelection.defaultFor(FactionClass.duran),
          onChanged: (value) => changed = value,
        ),
      ));

      final target = await pickFirstOther(
        tester,
        AvatarSelection.defaultFor(FactionClass.duran),
      );

      expect(changed, isNotNull);
      expect(changed!.portraitId, target.id);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching presentation switches the visible portraits', (
      WidgetTester tester,
    ) async {
      AvatarSelection? changed;
      await tester.pumpWidget(MaterialApp(
        home: _GalleryHost(
          species: AvatarSpecies.terran,
          initial: AvatarSelection.defaultFor(FactionClass.trader),
          onChanged: (value) => changed = value,
        ),
      ));

      // A callsign appears twice: the large preview title and the selected
      // thumbnail caption.
      expect(find.text('Wes Halloway'), findsWidgets,
          reason: 'the default male Trader portrait should be visible');

      await tester.tap(find.text('Female'));
      await tester.pump();

      final female = AvatarCatalog.forSpecies(
        AvatarSpecies.terran,
        presentation: AvatarPresentation.female,
      );
      expect(changed, isNotNull);
      expect(changed!.presentation, AvatarPresentation.female);
      expect(find.text(female.first.label), findsWidgets,
          reason: 'switching presentation should reveal that tab\'s portraits');
      expect(find.text('Wes Halloway'), findsNothing);
    });

    testWidgets('shows the faction appearance as the flavour line', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AvatarGallery(
            species: AvatarSpecies.duran,
            selection: AvatarSelection.defaultFor(FactionClass.duran),
            onChanged: (_) {},
          ),
        ),
      ));

      expect(
        find.textContaining('battle-armor'),
        findsOneWidget,
        reason: 'the flavour line should come from the faction lore',
      );
    });

    testWidgets('reroll randomises the whole appearance and a new portrait', (
      WidgetTester tester,
    ) async {
      AvatarSelection? changed;
      await tester.pumpWidget(MaterialApp(
        home: _GalleryHost(
          species: AvatarSpecies.vinari,
          initial: AvatarSelection.defaultFor(FactionClass.vinari),
          onChanged: (value) => changed = value,
        ),
      ));

      await tester.tap(find.byIcon(Icons.casino_rounded));
      await tester.pump();

      expect(changed, isNotNull);
      final rolled = changed!;
      expect(rolled.species, AvatarSpecies.vinari);
      expect(rolled.isRenderable, isTrue,
          reason: 'a re-roll must stay inside the catalogue');
      expect(rolled.style, isNotNull,
          reason: 'a re-roll must set an explicit appearance');
      expect(rolled.style!.sanitized(), rolled.style,
          reason: 'every rolled axis must already be in range');
    });

    testWidgets('there is no separate Random action', (
      WidgetTester tester,
    ) async {
      // Reroll now covers what Random used to do, so two overlapping actions
      // would just be confusing.
      await tester.pumpWidget(MaterialApp(
        home: _GalleryHost(
          species: AvatarSpecies.duran,
          initial: AvatarSelection.defaultFor(FactionClass.duran),
          onChanged: (_) {},
        ),
      ));

      expect(find.byIcon(Icons.shuffle_rounded), findsNothing);
      expect(find.byIcon(Icons.casino_rounded), findsOneWidget);
    });

    testWidgets('repeated re-rolls produce many distinct appearances', (
      WidgetTester tester,
    ) async {
      // The original defect: Random only shuffled between three pre-baked
      // portraits, so every roll looked the same. A weak re-roll would regress
      // the same way.
      final seen = <AvatarStyle>{};
      for (var i = 0; i < 15; i++) {
        AvatarSelection? changed;
        await tester.pumpWidget(MaterialApp(
          home: _GalleryHost(
            species: AvatarSpecies.terran,
            initial: AvatarSelection.defaultFor(FactionClass.trader),
            onChanged: (value) => changed = value,
          ),
        ));
        await tester.tap(find.byIcon(Icons.casino_rounded));
        await tester.pump();
        seen.add(changed!.style!);
      }

      expect(seen.length, greaterThan(10),
          reason: 're-rolling must actually vary the appearance');
    });

    testWidgets('every style axis paints, across its whole range', (
      WidgetTester tester,
    ) async {
      // Each axis is a bounded index the painter switches on. A value that
      // painted nothing, or threw, would be invisible until a player rolled it.
      // `copyWith` isn't const, so this is a plain final list.
      final axes = <AvatarStyle>[
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(tone: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(outfit: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(outfitTone: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(hair: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(horns: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(eyes: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(markings: i),
        for (var i = 0; i < 3; i++) AvatarStyle.neutral.copyWith(expression: i),
      ];

      for (final faction in FactionClass.values) {
        for (final style in axes) {
          await tester.pumpWidget(MaterialApp(
            home: AvatarCanvas(
              selection:
                  AvatarSelection.defaultFor(faction).copyWith(style: style),
              size: 96,
            ),
          ));
          expect(tester.takeException(), isNull,
              reason: '$faction with \$style must paint cleanly');
        }
      }
    });

    testWidgets('re-rolls stay drawable and in range for every species', (
      WidgetTester tester,
    ) async {
      for (final faction in FactionClass.values) {
        final species = AvatarSpecies.forFaction(faction);
        for (var i = 0; i < 6; i++) {
          AvatarSelection? changed;
          await tester.pumpWidget(MaterialApp(
            home: _GalleryHost(
              species: species,
              initial: AvatarSelection.defaultFor(faction),
              onChanged: (value) => changed = value,
            ),
          ));
          await tester.tap(find.byIcon(Icons.casino_rounded));
          await tester.pump();

          expect(changed!.isRenderable, isTrue, reason: '$faction must render');
          expect(changed!.style!.tone,
              inInclusiveRange(0, AvatarStyle.toneCount - 1));
        }
        expect(tester.takeException(), isNull,
            reason: 'a re-rolled $faction portrait must paint cleanly');
      }
    });

    testWidgets('no per-axis customisation rows are offered', (
      WidgetTester tester,
    ) async {
      // The picker rows were removed once re-rolling covered the same ground.
      await tester.pumpWidget(MaterialApp(
        home: _GalleryHost(
          species: AvatarSpecies.duran,
          initial: AvatarSelection.defaultFor(FactionClass.duran).copyWith(
            style: const AvatarStyle(
              horns: 0,
              tone: 1,
              outfit: 1,
              outfitTone: 1,
              hair: 1,
              eyes: 1,
              markings: 1,
              expression: 1,
            ),
          ),
          onChanged: (_) {},
        ),
      ));

      expect(find.text('Customise'), findsNothing);
      expect(find.text('Reset'), findsNothing);
      expect(find.bySemanticsLabel('Hair style 1'), findsNothing);
      expect(find.bySemanticsLabel('Marking 1'), findsNothing);
    });
  });

  group('AvatarEditorScreen', () {
    /// Hosts a button that pushes the editor, capturing the popped value into
    /// [result] so a test can assert what the caller would have received.
    Future<void> pumpEditorHost(
      WidgetTester tester, {
      required FactionClass faction,
      AvatarSelection? initial,
      required void Function(AvatarSelection? value) onResult,
    }) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  final result =
                      await Navigator.of(context).push<AvatarSelection>(
                    MaterialPageRoute(
                      builder: (_) => AvatarEditorScreen(
                        faction: faction,
                        initialSelection: initial,
                      ),
                    ),
                  );
                  onResult(result);
                },
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
    }

    testWidgets('SAVE returns the edited draft', (WidgetTester tester) async {
      final initial = AvatarSelection.defaultFor(FactionClass.duran);
      AvatarSelection? saved;
      var popped = false;

      await pumpEditorHost(
        tester,
        faction: FactionClass.duran,
        initial: initial,
        onResult: (value) {
          saved = value;
          popped = true;
        },
      );

      final other = AvatarCatalog.forSpecies(
        AvatarSpecies.duran,
        presentation: initial.presentation,
      ).firstWhere((p) => p.id != initial.portraitId);

      // The Portrait tab holds the seed picker, which on a short viewport sits
      // below the fold inside the tab's own scroll view — the same thing a
      // player would do.
      await tester.ensureVisible(find.text(other.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(other.label).first);
      await tester.pump();
      await tester.ensureVisible(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pumpAndSettle();

      expect(popped, isTrue, reason: 'the editor should have popped');
      expect(saved, isNotNull);
      expect(saved!.portraitId, other.id,
          reason: 'SAVE must return the draft the player actually picked');
      expect(find.text('Change Appearance'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('CANCEL discards the draft and returns null', (
      WidgetTester tester,
    ) async {
      final initial = AvatarSelection.defaultFor(FactionClass.vinari);
      AvatarSelection? result;
      var popped = false;

      await pumpEditorHost(
        tester,
        faction: FactionClass.vinari,
        initial: initial,
        onResult: (value) {
          result = value;
          popped = true;
        },
      );

      // Make a change, then cancel: nothing must be committed.
      final other = AvatarCatalog.forSpecies(
        AvatarSpecies.vinari,
        presentation: initial.presentation,
      ).firstWhere((p) => p.id != initial.portraitId);
      await tester.ensureVisible(find.text(other.label).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text(other.label).first);
      await tester.pump();
      expect(find.text('Unsaved portrait change'), findsOneWidget,
          reason: 'the draft should be visibly uncommitted');

      await tester.ensureVisible(find.text('CANCEL'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('CANCEL'));
      await tester.pumpAndSettle();

      expect(popped, isTrue);
      expect(result, isNull,
          reason: 'CANCEL must not write the draft to the player');
    });

    testWidgets('a legacy null selection opens on the faction default', (
      WidgetTester tester,
    ) async {
      await pumpEditorHost(
        tester,
        faction: FactionClass.duran,
        initial: null,
        onResult: (_) {},
      );

      final fallback = AvatarSelection.defaultFor(FactionClass.duran);
      expect(find.text(fallback.portrait.label), findsWidgets);
      expect(find.text('Unsaved portrait change'), findsNothing,
          reason: 'starting from the default is not a change');
      expect(tester.takeException(), isNull);
    });
  });

  group('RegisterScreen', () {
    Future<void> pumpRegister(WidgetTester tester,
        {Size size = const Size(500, 1400)}) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
      await tester.pump();
      expect(tester.takeException(), isNull);
    }

    /// Taps the radio belonging to the faction card titled [title].
    ///
    /// The faction `ListTile` carries no `onTap` — only the trailing `Radio`
    /// drives the `RadioGroup`, so tapping the card's text is a no-op.
    Future<void> selectFaction(WidgetTester tester, String title) async {
      final radio = find.descendant(
        of: find.ancestor(
            of: find.text(title), matching: find.byType(ListTile)),
        matching: find.byType(Radio<FactionClass>),
      );
      await tester.ensureVisible(radio);
      await tester.pumpAndSettle();
      await tester.tap(radio);
      await tester.pumpAndSettle();
    }

    /// Fills the credentials form and advances to the faction/identity step.
    Future<void> advanceToFactionStep(WidgetTester tester) async {
      for (final entry in {
        'Username': 'testpilot',
        'Password': 'orbital7',
        'Confirm Password': 'orbital7',
      }.entries) {
        await tester.enterText(
          find.widgetWithText(TextFormField, entry.key),
          entry.value,
        );
        await tester.pump();
      }
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();
      expect(find.text('Choose Your Faction'), findsOneWidget,
          reason: 'the form should have advanced to the identity stage');
    }

    testWidgets('still has three stages, with the portrait on the faction step',
        (
      WidgetTester tester,
    ) async {
      await pumpRegister(tester);

      // Step indicator shows three numbered stages.
      for (final label in ['1', '2', '3']) {
        expect(find.text(label), findsOneWidget,
            reason: 'registration must keep its three-step indicator');
      }

      await advanceToFactionStep(tester);

      expect(find.text('Pilot Portrait'), findsOneWidget,
          reason: 'the portrait picker lives in the identity stage');
      expect(find.byType(AvatarGallery), findsOneWidget);
      expect(find.text('Select Your Ship'), findsNothing);

      // The default is preselected, so Continue needs no customization.
      await tester.tap(find.text('CONTINUE'));
      await tester.pumpAndSettle();
      expect(find.text('Select Your Ship'), findsOneWidget,
          reason: 'the step after faction should still be the ship step');
    });

    testWidgets('changing faction resets the portrait to that faction default',
        (
      WidgetTester tester,
    ) async {
      await pumpRegister(tester);
      await advanceToFactionStep(tester);

      // Starts as a Trader.
      expect(find.text('Wes Halloway'), findsWidgets);

      await selectFaction(tester, 'Duran Hegemony');

      expect(find.text('Veth Kaal'), findsWidgets,
          reason:
              'a faction change must re-point the portrait at a valid default');
      expect(find.text('Wes Halloway'), findsNothing,
          reason: 'the previous faction\'s art must not linger');
      expect(tester.takeException(), isNull);
    });

    testWidgets('selecting a portrait is reflected in the preview', (
      WidgetTester tester,
    ) async {
      await pumpRegister(tester);
      await advanceToFactionStep(tester);

      await selectFaction(tester, 'Duran Hegemony');

      final target = AvatarCatalog.forSpecies(
        AvatarSpecies.duran,
        presentation: AvatarPresentation.male,
      ).firstWhere((p) => !p.isDefault);
      final thumb = find.text(target.label).first;
      await tester.ensureVisible(thumb);
      await tester.pumpAndSettle();
      await tester.tap(thumb);
      await tester.pumpAndSettle();

      expect(find.text(target.label), findsWidgets,
          reason: 'the large preview should show the chosen portrait');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the faction step is usable on a narrow layout', (
      WidgetTester tester,
    ) async {
      // The design doc warns against forcing a full-screen editor on narrow
      // layouts; the gallery must scroll within the 400px column.
      await pumpRegister(tester, size: const Size(360, 900));
      await advanceToFactionStep(tester);

      expect(find.byType(AvatarGallery), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'a narrow viewport must not overflow the faction step');
    });
  });

  group('ShipStatusView', () {
    testWidgets('shows the portrait and a Change Appearance row', (
      WidgetTester tester,
    ) async {
      final player = _pilot(faction: FactionClass.vinari);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ShipStatusView(player: player, onPlayerUpdate: (_) {})),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AvatarCanvas), findsWidgets,
          reason: 'the pilot portrait belongs in Player Info');
      expect(find.text('Change Appearance'), findsOneWidget);
      expect(find.text('Change Password'), findsOneWidget,
          reason: 'the existing row must survive the new one');
      expect(find.text(player.username), findsOneWidget,
          reason: 'the identity row carries the username');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a legacy player with no saved portrait still renders one', (
      WidgetTester tester,
    ) async {
      final player = _pilot(faction: FactionClass.duran);
      expect(player.avatar, isNull);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ShipStatusView(player: player, onPlayerUpdate: (_) {})),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AvatarCanvas), findsWidgets,
          reason: 'effectiveAvatar must supply a default for legacy saves');
      expect(find.text(player.username), findsOneWidget);
      expect(find.text('Duran Hegemony'), findsWidgets,
          reason: 'the identity row identifies the pilot and their faction');
      expect(find.text('Veth Kaal'), findsNothing,
          reason: 'the portrait callsign is gallery flavour only — on Ship '
              'Status the account name already identifies the pilot, so showing '
              'a second name was redundant');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wide two-column grid does not overflow its fixed cells', (
      WidgetTester tester,
    ) async {
      // The grid pins mainAxisExtent, so a portrait too tall for the cell would
      // throw a RenderFlex overflow. This is the guard for that constraint.
      await tester.binding.setSurfaceSize(const Size(1400, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final faction in FactionClass.values) {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: ShipStatusView(
                player: _pilot(faction: faction), onPlayerUpdate: (_) {}),
          ),
        ));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        expect(tester.takeException(), isNull,
            reason: 'the wide grid must not overflow for $faction');
      }
    });

    testWidgets('the narrow single-column layout does not overflow', (
      WidgetTester tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(420, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShipStatusView(player: _pilot(), onPlayerUpdate: (_) {}),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byType(AvatarCanvas), findsWidgets);
      expect(tester.takeException(), isNull,
          reason: 'the narrow layout must not overflow');
    });
  });
}
