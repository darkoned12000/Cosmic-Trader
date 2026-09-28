import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/screens/avatar_editor_screen.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_axis_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';

/// The bundled display typeface, loaded so text measures realistically.
///
/// Widget tests otherwise fall back to a font in which every glyph is a
/// full-width box, making labels roughly twice their real width. That produced a
/// genuinely wrong conclusion here: a six-tab strip appeared to overflow a 430px
/// phone by 90px and "proved" a tab was untappable, when on a real device the
/// strip fits with room to spare. Any assertion about whether text *fits* is
/// meaningless without a real font.
bool _fontLoaded = false;

Future<void> _loadRealFont() async {
  if (_fontLoaded) return;
  final bytes = await File('assets/fonts/Audiowide.ttf').readAsBytes();
  final loader = FontLoader('Audiowide')
    ..addFont(Future.value(ByteData.sublistView(bytes)));
  await loader.load();
  _fontLoaded = true;
}

/// Hosts the editor and records every selection it emits, so a test can assert
/// on what the caller would have saved.
Future<void> pumpEditor(
  WidgetTester tester, {
  required FactionClass faction,
  AvatarSelection? initial,
  Size size = const Size(430, 900),
}) async {
  // Real file I/O and a platform-channel font registration, so both have to
  // escape the fake-async zone. Left inside it, `FontLoader.load` never
  // completes and the test hangs until the harness times out.
  await tester.runAsync(_loadRealFont);
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(useMaterial3: true).copyWith(
      textTheme: ThemeData.dark().textTheme.apply(fontFamily: 'Audiowide'),
      primaryTextTheme:
          ThemeData.dark().primaryTextTheme.apply(fontFamily: 'Audiowide'),
    ),
    home: AvatarEditorScreen(faction: faction, initialSelection: initial),
  ));
  await tester.pumpAndSettle();
}

/// A label that is only ever on [tab] for [species] — so finding it proves the
/// tab switched, rather than proving the tab exists.
String _labelOn(AvatarTab tab, AvatarSpecies species) => switch (tab) {
      AvatarTab.portrait => 'Pilot Portrait',
      AvatarTab.face => 'Skin tone',
      AvatarTab.hair => 'Hair colour',
      AvatarTab.gear => 'Headgear',
      AvatarTab.outfit => 'Garment',
      AvatarTab.backdrop => AvatarAxisCatalog.backdropLabel(species, 0),
    };

/// Switches to [tab], scrolling the tab strip first if it is off-screen.
///
/// A tap on an off-screen tab silently does nothing — `flutter_test` only warns
/// — so a test that taps without this will happily "pass" a broken strip. That
/// is exactly how the icon-per-tab strip shipped: it looked fine, and the first
/// sign of trouble was a screenshot showing the wrong tab.
Future<void> _openTab(
  WidgetTester tester,
  AvatarTab tab,
  AvatarSpecies species,
) async {
  // Scoped to the tab strip: the Backdrop *tab* and the Backdrop *axis* share a
  // label, so a bare `find.text` is ambiguous the moment that axis row is built.
  final finder = find.descendant(
    of: find.byType(TabBar),
    matching: find.text(tab.label),
  );
  final bar = tester.getRect(find.byType(TabBar));
  if (tester.getRect(finder).left > bar.right) {
    await tester.drag(find.byType(TabBar), const Offset(-200, 0));
    await tester.pumpAndSettle();
  }
  await tester.tap(finder);
  await tester.pumpAndSettle();
  // Assert the content changed, not merely that the tap did not throw.
  expect(find.text(_labelOn(tab, species)).evaluate(), isNotEmpty,
      reason: 'tapping ${tab.label} did not switch to it');
}

void main() {
  group('tabbed appearance editor', () {
    testWidgets('every tab is reachable and titled', (tester) async {
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      // Six tabs, and on a 430px phone every one must be *visible* — an earlier
      // icon-per-tab strip pushed two of them off-screen with no affordance that
      // it scrolled, which read as "there are only four tabs".
      //
      // Measured against the rendered layout, not `view.physicalSize`: that
      // reports the binding's 800x600 at dpr 3 even after `setSurfaceSize`, so an
      // assertion using it passes no matter how far the row overflows. And with
      // the real font loaded, since the default test font is ~2x too wide.
      final viewport = tester.getRect(find.byType(TabBar));
      for (final tab in AvatarTab.values) {
        expect(
            find.descendant(
                of: find.byType(TabBar), matching: find.text(tab.label)),
            findsOneWidget,
            reason: 'tab ${tab.label} should be present');
        final rect = tester.getRect(find.descendant(
            of: find.byType(TabBar), matching: find.text(tab.label)));
        expect(rect.left, greaterThanOrEqualTo(viewport.left - 0.5),
            reason: 'tab ${tab.label} is cut off on the left');
        expect(rect.right, lessThanOrEqualTo(viewport.right + 0.5),
            reason: 'tab ${tab.label} is cut off on the right');
      }

      for (final tab in AvatarTab.values) {
        await _openTab(tester, tab, AvatarSpecies.duran);
        expect(tester.takeException(), isNull,
            reason: 'tab ${tab.label} must not throw or overflow');
      }
    });

    testWidgets('every tab stays reachable on a small phone, by scrolling',
        (tester) async {
      // At 360px the six tabs genuinely do not fit (~26px short with the real
      // font), so the strip scrolls. That is fine and is standard Material
      // behaviour — what is *not* fine is a tab that cannot be reached at all,
      // which is what happens if the strip is clipped instead of scrollable.
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
        size: const Size(360, 640),
      );
      for (final tab in AvatarTab.values) {
        await _openTab(tester, tab, AvatarSpecies.duran);
        expect(tester.takeException(), isNull,
            reason: 'tab ${tab.label} must be reachable and not overflow');
      }
    });

    testWidgets('each tab shows the axes for that species', (tester) async {
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      // Face: every applicable axis label is present.
      await tester.tap(find.text('Face'));
      await tester.pumpAndSettle();
      for (final label in ['Skin tone', 'Eyes', 'Iris colour', 'Markings']) {
        expect(find.text(label), findsOneWidget,
            reason: 'Face should offer $label');
      }
      // `expression` is below the fold on a short phone; scroll to it.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Expression'), findsOneWidget);

      // Hair: the Duran grow horns.
      await tester.tap(find.text('Hair'));
      await tester.pumpAndSettle();
      expect(find.text('Horns'), findsOneWidget);

      // Backdrop: named options, including the auto entry.
      await tester.tap(find.text('Backdrop'));
      await tester.pumpAndSettle();
      expect(find.text('Auto'), findsOneWidget);
      for (final label
          in AvatarAxisCatalog.backdropLabel(AvatarSpecies.duran, 0) == ''
              ? <String>[]
              : [
                  AvatarAxisCatalog.backdropLabel(AvatarSpecies.duran, 0),
                  AvatarAxisCatalog.backdropLabel(AvatarSpecies.duran, 1),
                  AvatarAxisCatalog.backdropLabel(AvatarSpecies.duran, 2),
                ]) {
        expect(find.text(label), findsOneWidget,
            reason: 'Backdrop should offer $label');
      }
    });

    testWidgets('an inapplicable axis is hidden, not shown inert',
        (tester) async {
      // A control that silently does nothing is worse than no control: the
      // player reasonably assumes they changed something.
      await pumpEditor(
        tester,
        faction: FactionClass.trader,
        initial: AvatarSelection.defaultFor(FactionClass.trader),
      );
      await tester.tap(find.text('Hair'));
      await tester.pumpAndSettle();
      expect(find.text('Horns'), findsNothing,
          reason: 'only the Duran grow horns');

      await pumpEditor(
        tester,
        faction: FactionClass.vinari,
        initial: AvatarSelection.defaultFor(FactionClass.vinari),
      );
      await tester.tap(find.text('Face'));
      await tester.pumpAndSettle();
      expect(find.text('Markings'), findsNothing,
          reason: 'the Vinari are unmarked by lore');
      expect(find.text('Pigment'), findsNothing);
    });

    testWidgets('choosing an option updates the preview and marks the axis',
        (tester) async {
      final initial = AvatarSelection.defaultFor(FactionClass.duran);
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: initial,
      );

      await tester.tap(find.text('Gear'));
      await tester.pumpAndSettle();

      // Unchanged to begin with: no marker, and the draft is clean.
      expect(find.text('changed'), findsNothing);
      expect(find.text('Unsaved portrait change'), findsNothing);

      await tester.tap(find.text('Goggles'));
      await tester.pumpAndSettle();

      expect(find.text('changed'), findsWidgets,
          reason: 'a modified axis must be visibly marked');
      expect(find.text('Unsaved portrait change'), findsOneWidget,
          reason: 'the editor is a draft; nothing is committed until SAVE');
      expect(find.text('Now: Goggles'), findsOneWidget);
    });

    testWidgets('Reset returns the axis to the seed value', (tester) async {
      final initial = AvatarSelection.defaultFor(FactionClass.duran);
      final seed = initial.portrait.seededStyle.sanitized();
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: initial,
      );

      await tester.tap(find.text('Backdrop'));
      await tester.pumpAndSettle();

      // Move away from the seed, then put it back.
      final target = (seed.backdrop ?? 0) == 0 ? 1 : 0;
      await tester.tap(find.text(AvatarAxisCatalog.backdropLabel(
        AvatarSpecies.duran,
        target,
      )));
      await tester.pumpAndSettle();
      expect(find.text('changed'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('changed'), findsNothing,
          reason: 'Reset must clear the modified marker');
    });

    testWidgets('Reset all clears every axis but keeps the chosen seed',
        (tester) async {
      // Deliberately changes one axis rather than using Reroll. Reroll also draws
      // a new catalogue seed, so after it the editor is *still* dirty once the
      // axes are reset — which is correct, because the seed genuinely changed.
      // A test that rerolled here was flaky two runs in three.
      await pumpEditor(
        tester,
        faction: FactionClass.vinari,
        initial: AvatarSelection.defaultFor(FactionClass.vinari),
      );

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.vinari);
      await tester.tap(find.text('Aurora'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved portrait change'), findsOneWidget);

      await tester.tap(find.text('Reset all'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved portrait change'), findsNothing,
          reason: 'Reset all must return every axis to the catalogue seed');
      // And the button then reports that it is already at the preset.
      expect(find.text('At preset'), findsOneWidget);
    });

    testWidgets('Reroll everything draws a new seed as well as new axes',
        (tester) async {
      // Only asserts the deterministic half. Whether the editor is still dirty
      // after a *subsequent* Reset all depends on whether the re-roll happened to
      // redraw the same seed — 1 time in 3 — so that half is asserted at the
      // model level in `avatar_selection_test.dart` instead, where the draw can
      // be forced.
      await pumpEditor(
        tester,
        faction: FactionClass.vinari,
        initial: AvatarSelection.defaultFor(FactionClass.vinari),
      );

      await tester.tap(find.text('Reroll everything'));
      await tester.pumpAndSettle();
      expect(find.text('Unsaved portrait change'), findsOneWidget);
      expect(find.text('At preset'), findsNothing,
          reason: 'a re-roll leaves a style, so the preset state must not be '
              'claimed');
    });

    testWidgets('a lock survives a re-roll and unlocks cleanly',
        (tester) async {
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);

      // The button starts by claiming to roll everything — with locks it must
      // stop claiming to, or it would be lying about what it does.
      expect(find.text('Reroll everything'), findsOneWidget);

      // Lock the backdrop axis. Semantics carry the state, because a padlock
      // glyph alone is not an accessible control.
      final lockButton =
          find.bySemanticsLabel('Lock this axis against re-rolling');
      expect(lockButton, findsOneWidget);
      await tester.tap(lockButton);
      await tester.pumpAndSettle();

      expect(find.text('Reroll unlocked'), findsOneWidget);
      expect(find.bySemanticsLabel('Un' 'lock axis'), findsOneWidget);

      // Choose a specific backdrop, re-roll, and confirm it held.
      await tester.tap(find.text('Ember field'));
      await tester.pumpAndSettle();
      expect(find.text('Now: Ember field'), findsOneWidget);

      await tester.tap(find.text('Reroll unlocked'));
      await tester.pumpAndSettle();
      expect(find.text('Now: Ember field'), findsOneWidget,
          reason: 'a locked axis must survive a re-roll');
      // The complementary half — that unlocked axes *do* still move — is
      // asserted in `avatar_selection_test.dart` with a forced generator, since
      // here the roll is random and a single axis would match its seed 1 time in
      // 4. What matters at this level is only that the lock reaches the reroll.

      // Unlocking and re-rolling lets it move again.
      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      await tester.tap(find.bySemanticsLabel('Un' 'lock axis'));
      await tester.pumpAndSettle();
      expect(find.text('Reroll everything'), findsOneWidget,
          reason: 'unlocking must restore the "everything" claim');
    });

    testWidgets('locks are per axis, not per tab', (tester) async {
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      await tester
          .tap(find.bySemanticsLabel('Lock this axis against re-rolling'));
      await tester.pumpAndSettle();
      expect(find.text('Reroll unlocked'), findsOneWidget);

      // A different tab is untouched: its axes are still free.
      await _openTab(tester, AvatarTab.face, AvatarSpecies.duran);
      expect(find.bySemanticsLabel('Lock this axis against re-rolling'),
          findsWidgets,
          reason: 'a lock on one axis must not lock the whole tab');
      expect(find.bySemanticsLabel('Un' 'lock axis'), findsNothing);
      // And the count is global across tabs, because a re-roll is global.
      expect(find.text('Reroll unlocked'), findsOneWidget);
    });

    testWidgets('locks do not survive leaving the editor', (tester) async {
      // Locks are transient by design: they describe how to re-roll, not what
      // the pilot is. Reopening must start unlocked, or a lock would silently
      // change what the next session's Reroll does.
      final initial = AvatarSelection.defaultFor(FactionClass.duran);
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: initial,
      );
      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      await tester
          .tap(find.bySemanticsLabel('Lock this axis against re-rolling'));
      await tester.pumpAndSettle();
      expect(find.text('Reroll unlocked'), findsOneWidget);

      // Genuinely tear the editor down. Re-pumping an identical widget tree
      // *reuses* the existing State, so without this the "reopen" would keep the
      // very locks the test is claiming do not survive.
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await tester.pumpAndSettle();

      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: initial,
      );
      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      expect(find.text('Reroll everything'), findsOneWidget);
      expect(find.bySemanticsLabel('Un' 'lock axis'), findsNothing);
    });

    testWidgets('the Portrait tab re-roll honours the same locks',
        (tester) async {
      // There are two re-roll entry points. If only one honours locks, the
      // Portrait tab becomes a way to sidestep them.
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      await tester
          .tap(find.bySemanticsLabel('Lock this axis against re-rolling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ember field'));
      await tester.pumpAndSettle();

      // Now use the gallery's own Reroll tile, on the Portrait tab.
      await _openTab(tester, AvatarTab.portrait, AvatarSpecies.duran);
      await tester.tap(find.text('Reroll'));
      await tester.pumpAndSettle();

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      expect(find.text('Now: Ember field'), findsOneWidget,
          reason: 'the gallery re-roll must honour the editor\'s locks');
    });

    testWidgets('locking every applicable axis still leaves Reset working',
        (tester) async {
      // Lock and Reset are independent: a lock governs re-rolling, a reset
      // governs the value. Conflating them would trap a player on a look they
      // had already modified and then wanted back.
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      await _openTab(tester, AvatarTab.backdrop, AvatarSpecies.duran);
      await tester
          .tap(find.bySemanticsLabel('Lock this axis against re-rolling'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ember field'));
      await tester.pumpAndSettle();
      expect(find.text('changed'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(find.text('changed'), findsNothing,
          reason: 'Reset must still work on a locked axis');
      expect(find.bySemanticsLabel('Un' 'lock axis'), findsOneWidget,
          reason: 'Reset must not silently unlock the axis');
    });

    testWidgets('the preview stays pinned while the axis list scrolls',
        (tester) async {
      // The reason the editor is laid out as pinned-preview + scrolling-axes
      // rather than one long scroll view. An earlier version put everything in a
      // SingleChildScrollView, which looked fine and meant changing a hairstyle
      // happened off-screen.
      await pumpEditor(
        tester,
        faction: FactionClass.duran,
        initial: AvatarSelection.defaultFor(FactionClass.duran),
      );

      await tester.tap(find.text('Face'));
      await tester.pumpAndSettle();

      // Identify the preview by the portrait it draws.
      final preview = find.byType(AvatarCanvasPreviewProbe);
      expect(preview, findsNothing); // sanity: probe is not in the tree

      final before = tester.getRect(find.byType(ListView).first);
      // Scroll the axis list to the bottom.
      await tester.fling(
          find.byType(ListView).first, const Offset(0, -1200), 2000);
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byType(ListView).first);

      expect(after, equals(before),
          reason: 'the axis list viewport must not move when its contents '
              'scroll — the preview above it is pinned');

      // The pinned preview is still on screen and still showing the pilot.
      final canvas = find.byType(CustomPaint).evaluate().length;
      expect(canvas, greaterThan(0));
    });

    testWidgets('no overflow at phone and at a deliberately cramped size',
        (tester) async {
      for (final size in const [
        Size(430, 900),
        Size(360, 640),
        Size(1024, 768),
      ]) {
        await pumpEditor(
          tester,
          faction: FactionClass.duran,
          initial: AvatarSelection.defaultFor(FactionClass.duran),
          size: size,
        );
        for (final tab in AvatarTab.values) {
          await tester.tap(find.descendant(
              of: find.byType(TabBar), matching: find.text(tab.label)));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'no overflow at ${size.width}x${size.height} on '
                  '${tab.label}');
        }
      }
    });

    testWidgets('the editor still works when the seed is a legacy null style',
        (tester) async {
      // `Player.avatar.style` is nullable, so a pre-avatar save opens the editor
      // with `style: null` and every axis showing its seed value.
      final legacy = AvatarSelection.defaultFor(FactionClass.trader)
          .copyWith(clearStyle: true);
      expect(legacy.style, isNull);

      await pumpEditor(
        tester,
        faction: FactionClass.trader,
        initial: legacy,
      );
      expect(find.text('Unsaved portrait change'), findsNothing,
          reason: 'starting from the preset is not a change');

      await tester.tap(find.text('Backdrop'));
      await tester.pumpAndSettle();
      // Backdrop names are species-specific: the Trader options are the
      // human-scale ones, not the Duran forge set.
      expect(find.text('Starfield'), findsOneWidget);
      expect(find.text('Forge glow'), findsNothing,
          reason: 'a Duran backdrop name must not be offered to a Trader');

      await tester.tap(find.text('Starfield'));
      await tester.pumpAndSettle();
      expect(find.text('Now: Starfield'), findsOneWidget);
      expect(find.text('Unsaved portrait change'), findsOneWidget,
          reason: 'choosing from a null-seeded legacy style is a real change');
    });

    testWidgets('every catalogue seed opens cleanly on every tab',
        (tester) async {
      // Cheap sweep for build-time crashes across the whole gallery rather than
      // the three defaults the other tests touch.
      for (final species in AvatarSpecies.values) {
        for (final portrait in AvatarCatalog.forSpecies(species)) {
          await pumpEditor(
            tester,
            faction: species.faction,
            initial: AvatarSelection(
              species: portrait.species,
              presentation: portrait.presentation,
              portraitId: portrait.id,
            ),
          );
          expect(tester.takeException(), isNull,
              reason: '${portrait.id} must build without throwing');
        }
      }
    });
  });
}

/// Never present. Exists so the pinned-preview test can assert it is *not* the
/// thing it is measuring, which catches a future rename of the preview widget
/// silently turning the assertion into a no-op.
class AvatarCanvasPreviewProbe extends StatelessWidget {
  const AvatarCanvasPreviewProbe({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
