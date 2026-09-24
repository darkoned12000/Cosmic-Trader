import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/widgets/font_settings_widget.dart';

/// Regression guard for the font picker crash: when a bundled typeface
/// (e.g. Audiowide in `assets/fonts/`) is scanned, the dropdown's items are
/// keyed by family *name*, and the persisted selection must always map to
/// exactly one item. Previously the items were keyed by file name
/// (`Audiowide.ttf`) while the value was the family name (`Audiowide`), which
/// tripped the DropdownButton "exactly one item" assertion.
void main() {
  testWidgets('font dropdown renders with a scanned custom family selected',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FontSettingsWidget(
            fontFamily: 'Audiowide',
            fontSize: 14,
            onFontFamilyChanged: (_) {},
            onFontSizeChanged: (_) {},
            buildSettings: () => GameSettings.defaults(),
          ),
        ),
      ),
    );
    // Let the assets/fonts directory scan finish (real file IO must run
    // outside the fake-async zone) and the dropdown render.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
    await tester.pump();
    expect(tester.takeException(), isNull,
        reason: 'selecting/displaying Audiowide must not assert');

    // Expand the card so the picker is visible and interactable.
    await tester.tap(find.text('FONTS'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.text('Audiowide'), findsOneWidget);
  });
}
