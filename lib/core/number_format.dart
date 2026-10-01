/// Number formatting shared by every screen that shows a figure.
///
/// These lived as **seven near-identical private helpers** across the app —
/// `_compact` (×2), `_formatNumber`, `_format`, `_formatShort`, `_fmt`,
/// `_commas` (×2) — which is how a display convention drifts: the K/M pair was
/// copied five times and one copy had already grown a `B` rung the others
/// lacked, so the same credit total read differently on two screens.
///
/// Nothing here reads game state; it is pure presentation, which is why it sits
/// in `core/` rather than beside any one screen.
library;

/// Compact magnitude — `1.2K`, `3.4M`, `5.6B`.
///
/// One decimal, and the raw number below a thousand. Extends to billions: the
/// copies this replaces stopped at `M`, so a credit total of 1.2 billion printed
/// as `1234.5M`. That was the leaderboard's problem to work around and nobody
/// else's, which is exactly how the two conventions diverged.
String compact(int n) {
  final negative = n < 0;
  final v = n.abs();
  final String out;
  if (v >= 1000000000) {
    out = '${(v / 1000000000).toStringAsFixed(1)}B';
  } else if (v >= 1000000) {
    out = '${(v / 1000000).toStringAsFixed(1)}M';
  } else if (v >= 1000) {
    out = '${(v / 1000).toStringAsFixed(1)}K';
  } else {
    out = '$v';
  }
  return negative ? '-$out' : out;
}

/// Compact magnitude for a **money** figure, keeping two decimals on the
/// millions rung.
///
/// A revenue total is worth more precision than a hull figure, which is why
/// `port_management_screen` had its own copy. Kept as its own function rather
/// than a flag on [compact] so the difference is visible at the call site.
String compactMoney(double value) {
  final negative = value < 0;
  final v = value.abs();
  final String out;
  if (v >= 1000000) {
    out = '${(v / 1000000).toStringAsFixed(2)}M';
  } else if (v >= 1000) {
    out = '${(v / 1000).toStringAsFixed(1)}K';
  } else {
    out = v.toStringAsFixed(0);
  }
  return negative ? '-$out' : out;
}

/// Thousands separators — `1,234,567`. Negative-safe.
String grouped(int n) {
  final s = n.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${n < 0 ? '-' : ''}$buf';
}

/// A stored figure with two decimals and separators — `1,234.56`.
///
/// Rounds to hundredths via integer arithmetic rather than subtracting the
/// floor. `1234567.99 - 1234567` is `0.9899999…` in binary floating point, so
/// the subtraction-then-floor version printed `1,234,567.98` — off by a
/// hundredth, silently, on exactly the large figures this exists to make
/// legible.
String groupedDecimal(double n) {
  final hundredths = (n * 100).round();
  final whole = hundredths ~/ 100;
  final fraction = (hundredths % 100).abs();
  return '${grouped(whole)}.${fraction.toString().padLeft(2, '0')}';
}
