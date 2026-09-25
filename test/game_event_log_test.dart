import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

void main() {
  setUp(() => GameEventLog.resetForTest());
  tearDown(() => GameEventLog.resetForTest());

  test('entries are stored newest-first with category and timestamp', () {
    final log = GameEventLog.global;
    final before = DateTime.now();
    log.energy('NPC_ENERGY event=refuel_buy pilot=Zed units=10');
    log.combat('Zed destroyed someone');

    expect(log.length, 2);
    expect(log.entries.first.category, GameEventCategory.combat);
    expect(log.entries.last.category, GameEventCategory.energy);
    expect(
      log.entries.first.timestamp.isAfter(before) ||
          log.entries.first.timestamp.isAtSameMomentAs(before),
      isTrue,
    );
  });

  test('buffer caps at maxEntries, dropping oldest', () {
    final log = GameEventLog.global;
    for (int i = 0; i < GameEventLog.maxEntries + 50; i++) {
      log.system('line $i');
    }
    expect(log.length, GameEventLog.maxEntries);
    expect(log.entries.first.message, 'line ${GameEventLog.maxEntries + 49}');
    expect(log.entries.last.message, 'line 50');
  });

  test('query filters by text and category', () {
    final log = GameEventLog.global;
    log.energy('NPC_ENERGY event=refuel_buy pilot=Zed units=10');
    log.energy('NPC_ENERGY event=array_buy pilot=Zed spent=75000');
    log.movement('Zed warped to sector #5');

    final buys = log.query(query: 'refuel_buy');
    expect(buys, hasLength(1));

    final energyOnly = log.query(
      categories: {GameEventCategory.energy},
    );
    expect(energyOnly, hasLength(2));

    final pilotSearch = log.query(query: 'zed');
    expect(pilotSearch, hasLength(3));

    expect(log.query(), hasLength(3));
    expect(
      log.query(query: 'nothing matches this'),
      isEmpty,
    );
  });

  test('clear empties the buffer but keeps all-time counts', () {
    final log = GameEventLog.global;
    log.system('hello');
    log.trade('deal');
    expect(log.length, 2);
    log.clear();
    expect(log.length, 0);
    expect(log.entries, isEmpty);
    expect(log.count(GameEventCategory.system), 1);
    expect(log.count(GameEventCategory.trade), 1);
    expect(log.count(GameEventCategory.combat), 0);
  });
}
