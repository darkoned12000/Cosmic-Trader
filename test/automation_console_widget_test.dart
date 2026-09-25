import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/widgets/automation_console_widget.dart';

void main() {
  setUp(() => GameEventLog.resetForTest());
  tearDown(() => GameEventLog.resetForTest());

  Future<void> pumpConsole(
    WidgetTester tester, {
    ValueChanged<int>? onTick,
    VoidCallback? onGrant,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AutomationConsoleWidget(
              tickIntervalSeconds: 30,
              onTickIntervalChanged: onTick,
              onGrantCredits: onGrant,
            ),
          ),
        ),
      ),
    );
    // The section starts collapsed — expand it like a user would.
    await tester.tap(find.text('Automation (Dev)'));
    await tester.pumpAndSettle();
  }

  testWidgets('log viewer searches and filters entries', (tester) async {
    GameEventLog.global.energy('NPC_ENERGY event=refuel_buy pilot=Zed');
    GameEventLog.global.movement('Zed warped to sector #5');

    await pumpConsole(tester);

    // Two matches: the log entry plus the search-box hint text.
    expect(find.textContaining('refuel_buy'), findsNWidgets(2));
    expect(find.textContaining('warped to sector'), findsOneWidget);

    // Category filter: hide movement.
    await tester.tap(find.text('movement'));
    await tester.pump();
    expect(find.textContaining('refuel_buy'), findsNWidgets(2));
    expect(find.textContaining('warped to sector'), findsNothing);

    // Text search narrows further (hint text remains the only match).
    await tester.enterText(find.byType(TextField), 'array_buy');
    await tester.pump();
    expect(find.textContaining('refuel_buy'), findsOneWidget);
  });

  testWidgets('copy view button exists only when entries shown',
      (tester) async {
    await pumpConsole(tester);
    // Empty log → Copy view disabled.
    final copyButton = find.widgetWithText(TextButton, 'Copy view');
    expect(copyButton, findsOneWidget);
    expect(tester.widget<TextButton>(copyButton).onPressed, isNull);

    GameEventLog.global.system('DEV ticks resumed');
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Copy view'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('dev controls fire tick and grant callbacks', (tester) async {
    int? tickPicked;
    var granted = false;
    await pumpConsole(
      tester,
      onTick: (s) => tickPicked = s,
      onGrant: () => granted = true,
    );

    await tester.tap(find.text('5s'));
    expect(tickPicked, 5);

    await tester.tap(find.text('+100k cr'));
    expect(granted, isTrue);
  });

  testWidgets('dev controls hidden without callbacks', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AutomationConsoleWidget()),
        ),
      ),
    );
    await tester.tap(find.text('Automation (Dev)'));
    await tester.pumpAndSettle();
    expect(find.text('Tick controls'), findsNothing);
    expect(find.text('+100k cr'), findsNothing);
    // Log viewer itself still works.
    expect(find.byType(TextField), findsOneWidget);
  });
}
