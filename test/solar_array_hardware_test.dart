import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/hardware_data.dart';

void main() {
  test('solar array is a purchasable/installable Hardware Emporium module', () {
    // The Modules tab builds its list from these picks.
    expect(moduleDefs.any((m) => m.id == 'solarArray'), isTrue);

    final levelOne = itemFor(
      'solarArray',
      HardwareCategory.module,
      1,
    );
    expect(levelOne, isNotNull);
    expect(levelOne!.name, 'Solar Array Lv.1');
    expect(levelOne.category, HardwareCategory.module);
    expect(levelOne.equipKey, 'solarArray');
    expect(levelOne.faction, isNull);

    // A null-faction item is offered to every faction.
    for (final faction in FactionClass.values) {
      final offered = itemsForFaction(HardwareCategory.module, faction)
          .where((i) => i.equipKey == 'solarArray');
      expect(offered, isNotEmpty);
      expect(offered.map((i) => i.level), containsAll(<int>[1, 2, 3, 4, 5]));
    }
  });
}
