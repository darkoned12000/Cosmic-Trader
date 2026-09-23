import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/widgets/hacking_widget.dart';

Player _makePlayer() => Player(
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
    );

void main() {
  testWidgets('accepts keyboard digits and advances the active slot',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: HackingWidget(
          player: _makePlayer(),
          onSuccess: (_) {},
          onFailure: (_) {},
          onCancel: () {},
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('5 / 5'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    expect(find.text('_'), findsOneWidget);

    // The first digit is entered into slot 1 and the cursor advances to slot 2.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
    await tester.pump();
    expect(find.text('1'), findsNWidgets(2)); // keypad button + current slot
    expect(find.textContaining('PLAYER INPUT'), findsOneWidget);

    // The second digit is entered into slot 2.
    await tester.sendKeyEvent(LogicalKeyboardKey.digit2);
    await tester.pump();
    expect(find.text('2'), findsNWidgets(2)); // keypad button + current slot

    // Backspace returns to slot 1 and removes the second digit.
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();
    expect(find.text('2'), findsOneWidget);

    // Simulated packet traffic continues to flow while the hack is active.
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.textContaining('TCP '), findsAtLeastNWidgets(1));
    expect(tester.takeException(), isNull);
  });
}
