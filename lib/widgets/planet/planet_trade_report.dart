import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';

/// The world's freight ledger, as a dialog.
///
/// Extracted from `planet_screen.dart` because it is **pure presentation** — a
/// `Planet` in, nothing out, no callbacks — which is the safest thing to move
/// out of a large screen and the first category to move for that reason (the
/// panels split earlier were ordered the same way: least state first).
///
/// Two sections because they answer two different questions. **Orders** is the
/// one a player asks an hour later — "what did that 80,000-mineral order
/// actually get me?" — and only `Planet.tradeOrders` holds the totals, because
/// the run ledger is truncated to ten entries and an order's early runs are long
/// gone by the time it finishes. **Runs** answers "what happened just now",
/// with the cause attached.
///
/// A plain `Column` inside a `SingleChildScrollView`, deliberately **not** a
/// `ListView`: both lists are bounded by construction, so a lazy list would buy
/// nothing and cost the lazy-build trap (rows below the fold reporting as
/// "missing" in a test because they were never built).

Future<void> showPlanetTradeReport(BuildContext context, Planet planet) async {
  final incidents = planet.tradeIncidents.reversed.toList();
  final orders = planet.tradeOrders.reversed.toList();
  // Both empty is the only case with nothing to say. Before an order record
  // existed this was `incidents.isEmpty`, which meant a world that traded and
  // finished would open to a blank dialog once its ten runs rolled over.
  if (incidents.isEmpty && orders.isEmpty) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final dialogCs = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: const Text('Freight Report', style: TextStyle(fontSize: 18)),
        content: SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (orders.isNotEmpty) ...[
                  _heading(dialogCs, 'Orders'),
                  for (final o in orders) _orderRow(o, dialogCs),
                  const SizedBox(height: 4),
                ],
                if (incidents.isNotEmpty) ...[
                  _heading(dialogCs, 'Recent runs'),
                  for (final i in incidents) _runRow(i, dialogCs),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Close'),
          ),
        ],
      );
    },
  );
}

Widget _heading(ColorScheme cs, String label) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
          color: cs.onSurface.withValues(alpha: 0.5),
        ),
      ),
    );

/// One finished order: what it was for, what it got, and what went wrong.
Widget _orderRow(TradeOrderRecord o, ColorScheme cs) {
  final clean = o.status == 'COMPLETE';
  final cancelled = o.status == 'CANCELLED';
  final tone = clean
      ? Colors.green.shade400
      : cancelled
          ? cs.onSurface.withValues(alpha: 0.5)
          : cs.error;
  final verb = o.direction == TradeDirection.buy ? 'Buy' : 'Sell';
  // The shortfall is split rather than summed: "lost" and "impounded" are
  // different events and a single figure would hide which one happened,
  // which is the whole reason the four outcome classes exist.
  final shortfall = <String>[
    if (o.unitsLost > 0) '${compact(o.unitsLost)} lost',
    if (o.unitsSeized > 0) '${compact(o.unitsSeized)} impounded',
    if (o.unitsCancelled > 0) '${compact(o.unitsCancelled)} cancelled',
  ].join(' · ');
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              clean
                  ? Icons.check_circle_rounded
                  : cancelled
                      ? Icons.cancel_rounded
                      : Icons.report_gmailerrorred_rounded,
              size: 14,
              color: tone,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$verb ${compact(o.unitsTotal)} ${o.commodity}'
                '${o.ports.length > 1 ? ' · ${o.ports.length} ports' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 1),
          child: Text(
            '${o.status} · ${compact(o.unitsDelivered)} delivered'
            '${shortfall.isEmpty ? '' : ' · $shortfall'}'
            '${o.runs > 0 ? ' · ${o.runs} runs' : ''}',
            maxLines: 2,
            style: TextStyle(fontSize: 11, color: tone),
          ),
        ),
      ],
    ),
  );
}

/// One resolved run. The line reads what became of the freight, not whether
/// it "succeeded" — four outcomes, and a seizure is a delivery.
Widget _runRow(TradeIncident i, ColorScheme cs) {
  final icon = switch (i.outcome) {
    TradeRunOutcome.delivered => Icons.check_circle_rounded,
    TradeRunOutcome.lost => Icons.report_gmailerrorred_rounded,
    TradeRunOutcome.delayed => Icons.schedule_rounded,
    TradeRunOutcome.seized => Icons.gavel_rounded,
  };
  final tone = switch (i.outcome) {
    TradeRunOutcome.delivered => Colors.green.shade400,
    TradeRunOutcome.lost => cs.error,
    // A diversion costs nothing but patience, so it is not an error tone —
    // painting it red would train the player to ignore the warning colour.
    TradeRunOutcome.delayed => Colors.amber.shade400,
    TradeRunOutcome.seized => cs.error,
  };
  final status = switch (i.outcome) {
    TradeRunOutcome.delivered => 'Delivered',
    TradeRunOutcome.lost => 'LOST — ${i.cause?.label ?? 'cause unrecorded'}',
    TradeRunOutcome.delayed => 'DIVERTED — '
        '${i.cause?.label ?? 'rerouted'} (+${i.delayTicks}t)',
    TradeRunOutcome.seized => 'PARTIAL — ${compact(i.deliveredUnits)} of '
        '${compact(i.units)} delivered, ${i.cause?.label ?? 'impounded'}',
  };
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: tone),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${i.direction == TradeDirection.buy ? 'Buy' : 'Sell'} '
                '${compact(i.units)} ${i.commodity} '
                '→ port #${i.portSectorId}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 1),
          child: Text(
            status,
            maxLines: 2,
            style: TextStyle(fontSize: 11, color: tone),
          ),
        ),
      ],
    ),
  );
}
