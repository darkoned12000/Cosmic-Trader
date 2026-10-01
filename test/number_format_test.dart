import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/core/number_format.dart';

/// The one place the app turns a number into a figure on screen.
///
/// These functions were seven private copies across seven files before they were
/// consolidated, and the copies had already drifted — the K/M pair was identical
/// in five places, one had grown a `B` rung the others lacked, and two rounded
/// the thousands rung differently. Nothing caught it because each copy was only
/// asserted by whatever screen test happened to read it, if any.
void main() {
  group('compact', () {
    test('one decimal on each rung, raw below a thousand', () {
      expect(compact(0), '0');
      expect(compact(999), '999');
      expect(compact(1000), '1.0K');
      expect(compact(1500), '1.5K');
      expect(compact(999999), '1000.0K');
      expect(compact(1000000), '1.0M');
      expect(compact(1234567), '1.2M');
      expect(compact(1000000000), '1.0B');
      expect(compact(1234567890), '1.2B');
    });

    test('extends to billions, which is the rung the copies disagreed on', () {
      // `faction_rankings_screen` had its own copy with a `B` rung; the other
      // four stopped at `M`, so a credit total of 1.2 billion read as
      // `1234.5M` on every other screen.
      expect(compact(1200000000), '1.2B');
    });

    test('is negative-safe', () {
      // A negative hull or a reputation figure must not render as `-1.0K` by
      // accident of `abs()` being applied without restoring the sign — which is
      // exactly the bug a naive `n.abs() >= 1000` branch produces.
      expect(compact(-1), '-1');
      expect(compact(-1500), '-1.5K');
      expect(compact(-1200000000), '-1.2B');
    });
  });

  group('compactMoney', () {
    test('keeps two decimals on the millions rung', () {
      expect(compactMoney(1500000), '1.50M');
      expect(compactMoney(1500), '1.5K');
      expect(compactMoney(999), '999');
    });

    test('is a genuinely different convention from compact', () {
      // Pinned as a difference rather than a coincidence: money is worth more
      // precision than a hull figure, and two screens relied on that.
      expect(compactMoney(1500000), isNot(compact(1500000)));
    });
  });

  group('grouped', () {
    test('separates every three digits', () {
      expect(grouped(0), '0');
      expect(grouped(999), '999');
      expect(grouped(1000), '1,000');
      expect(grouped(12345), '12,345');
      expect(grouped(1234567), '1,234,567');
    });

    test('is negative-safe', () {
      expect(grouped(-1234), '-1,234');
    });
  });

  group('groupedDecimal', () {
    test('two decimals, always, and grouped', () {
      expect(groupedDecimal(144), '144.00');
      expect(groupedDecimal(1234.5), '1,234.50');
      // Rounded, not truncated: a display that floors reads as a hundredth
      // behind at all times.
      expect(groupedDecimal(144.376), '144.38');
      expect(groupedDecimal(0.075), '0.08');
    });

    test('does not lose a hundredth to binary floating point', () {
      // `1234567.99 - 1234567` is `0.9899999…`, so the subtract-the-floor
      // version printed `1,234,567.98`. Integer hundredths do not.
      expect(groupedDecimal(1234567.99), '1,234,567.99');
      expect(groupedDecimal(0.29), '0.29');
      expect(groupedDecimal(8.11), '8.11');
    });

    test('carries a rounded fraction into the whole part', () {
      // 1.999 rounds to 2.00, not 1.100 — the carry has to cross the decimal
      // point, which is the case a naive `whole = n.floor()` gets wrong.
      expect(groupedDecimal(1.999), '2.00');
      expect(groupedDecimal(0.999), '1.00');
    });
  });
}
