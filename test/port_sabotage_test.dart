import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/port.dart';

void main() {
  test('port sabotage state survives JSON persistence', () {
    final until =
        DateTime.now().add(const Duration(minutes: 30)).millisecondsSinceEpoch;
    final port = Port(
      name: 'Test Port',
      portClass: PortClass.independent,
      buyPrices: const {},
      sellPrices: const {},
      securityCompromisedUntil: until,
    );

    final restored = Port.fromJson(port.toJson());

    expect(restored.securityCompromisedUntil, until);
    expect(restored.isSecurityCompromised, isTrue);
    expect(
      restored.copyWith(clearSecurityCompromised: true).isSecurityCompromised,
      isFalse,
    );
  });
}
