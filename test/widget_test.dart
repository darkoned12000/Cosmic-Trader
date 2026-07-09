import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tradewars_2050/main.dart';

void main() {
  group('TradeWarsApp', () {
    testWidgets('shows LoginScreen as home', (WidgetTester tester) async {
      await tester.pumpWidget(const TradeWarsApp());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('theme uses Material 3 with dark brightness',
        (WidgetTester tester) async {
      await tester.pumpWidget(const TradeWarsApp());
      final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(app.theme!.useMaterial3, isTrue);
      expect(app.theme!.brightness, Brightness.dark);
    });
  });
}
