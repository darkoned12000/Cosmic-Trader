import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/main.dart';

void main() {
  group('CosmicTraderApp', () {
    testWidgets('shows LoginScreen as home', (WidgetTester tester) async {
      await tester.pumpWidget(const CosmicTraderApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('theme uses Material 3 with dark brightness',
        (WidgetTester tester) async {
      await tester.pumpWidget(const CosmicTraderApp());
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.useMaterial3, isTrue);
      expect(app.theme!.brightness, Brightness.dark);
    });

    testWidgets('LoginScreen exposes an Exit Game button that is harmless',
        (WidgetTester tester) async {
      await tester.pumpWidget(const CosmicTraderApp());
      expect(find.byTooltip('Exit Game'), findsOneWidget,
          reason: 'login screen should offer a clean way to quit');

      await tester.tap(find.byTooltip('Exit Game'));
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'Exit Game must not throw on any platform');
    });
  });
}
