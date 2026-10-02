import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/models/trade_job.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/services/planet_trade_service.dart';
import 'package:cosmic_trader/widgets/planet/planet_mini_controls.dart';
import 'package:cosmic_trader/widgets/planet/planet_trade_report.dart';
import 'package:cosmic_trader/widgets/shared/progress_bar.dart';

/// The Market card: quotes, order sizes, open orders, and the freight report.
///
/// **The widget draws the offer; the screen commits it.** Everything here is
/// either presentation or pure planning — `PlanetTradeService.plan` is a pure
/// function over a universe — and the only things that mutate anything are the
/// three callbacks, which reach the screen because the screen owns the player's
/// wallet and the write. That is the same split the colony card uses
/// (`onAdjust`), and it is why this file is safe to move: a reader can see the
/// entire UI contract in the constructor below.
///
/// Extracted from a 3,947-line screen, and deliberately **last**: mechanical
/// file-moving is safest on code that is not simultaneously changing behaviour,
/// and three of the four things added to this card in the same cycle would have
/// meant moving it twice. The order that worked, when this screen was last split,
/// was least state first — the pure panels went out before the ones that own the
/// wallet, and the wallet-owning handlers (place, cancel, withdraw, bank) stayed.
class PlanetMarketPanel extends StatefulWidget {
  const PlanetMarketPanel({
    super.key,
    required this.planet,
    required this.universe,
    required this.credits,
    required this.onPlaceOrder,
    required this.onCancelOrder,
    required this.treasury,
  });

  final Planet planet;

  /// Every sector, for planning. The panel plans; it does not hunt for ports
  /// itself, because `PlanetTradeService.plan` already does that over a list.
  final List<Sector> universe;

  /// The pilot's credits, read only for the Buy button's enablement. A number
  /// rather than a `Player` so this file does not depend on the player model at
  /// all — it cannot act on it, so it has no business knowing it.
  final int credits;

  /// Places an order. The screen charges the credits and writes.
  final void Function(String type, TradeDirection direction, int amount,
      TradeInsurance cover) onPlaceOrder;

  /// Cancels every share of one request. The screen refunds and writes.
  final void Function(String orderId) onCancelOrder;

  /// The treasury card, built by the screen. A slot rather than a callback
  /// because the withdrawal carries a pending-write state the screen tracks and
  /// re-asserts across refreshes; rendering it here and driving it there would
  /// split one control's logic across two files for no gain.
  final Widget treasury;

  @override
  State<PlanetMarketPanel> createState() => _PlanetMarketPanelState();
}

class _PlanetMarketPanelState extends State<PlanetMarketPanel> {
  /// Order sizes per commodity. Steps of 100 from 100: a Citadel tier costs tens
  /// of thousands, so the ±10 hauling step would be 8,000 taps to the same place.
  final Map<String, int> _marketAmounts = {
    'minerals': 1000,
    'organics': 1000,
    'industrial': 1000,
  };

  static const _marketCommodities = ['minerals', 'organics', 'industrial'];

  /// How much cover the **next** order is bought with.
  ///
  /// One control for the card rather than one per commodity row. It is a policy,
  /// not a per-order quantity: a player who wants cover wants it on the next
  /// thing they buy, and three identical tri-state controls down the side of the
  /// card would be three answers to one question. Per-row would also put three
  /// different premiums on screen at once, which is a comparison nobody asked
  /// for and cannot act on.
  TradeInsurance _cover = TradeInsurance.none;

  /// Smallest order the amount field holds, and the floor every "max" falls back
  /// to, so an empty market leaves a placeable number rather than zero.
  static const int minimumMarketAmount = 100;

  TradePlan _plan(String type, TradeDirection dir, int volume, Planet planet) =>
      PlanetTradeService.plan(
        universe: widget.universe,
        planet: planet,
        commodity: type,
        direction: dir,
        volume: volume,
      );

  @override
  Widget build(BuildContext context) {
    // Unwrapped once rather than threaded through forty call sites: every row
    // below wants the two things a `Build` has and a constructor does not.
    final planet = widget.planet;
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Market',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Bulk orders against live port markets. The port sends its own '
              'freighter — you pay credits and time, not cargo space.',
              style: TextStyle(
                fontSize: 11,
                height: 1.4,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 8),
            widget.treasury,
            const SizedBox(height: 8),
            _coverRow(cs),
            const SizedBox(height: 8),
            for (final type in _marketCommodities) ...[
              _marketRow(type, planet, cs),
              const SizedBox(height: 6),
            ],
            const Divider(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Open orders',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
                // One button rather than one per order: the log line lives in a
                // 200-entry ring the player may have scrolled past, and a
                // per-row Report would be a third control on a row that
                // already carries a Cancel and a countdown bar. The history
                // belongs to the world, so it is read from the world.
                PlanetMiniButton(
                    'Report',
                    Colors.teal,
                    planet.tradeIncidents.isNotEmpty,
                    () => showPlanetTradeReport(context, planet),
                    key: const Key('market-report'),
                    disabledReason: 'No shipments yet'),
              ],
            ),
            const SizedBox(height: 6),
            if (planet.tradeJobs.isEmpty)
              Text(
                'No open orders yet.',
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            // One row per request, not per port-run: a split order is one
            // job with one Cancel, so N taps always read as N rows.
            for (final group in _orderGroups(planet)) ...[
              _marketOrderRow(planet, group, cs),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// The cover policy, as one row of three.
  ///
  /// `SegmentedButton` rather than a dropdown: three options, all of them
  /// relevant on every order, and a dropdown would hide the choice behind a tap
  /// to discover that there are three. Each chip carries what it means —
  /// `HALF` is "half of what is lost", not "half off" — because the difference
  /// between the two readings is the whole purchase.
  Widget _coverRow(ColorScheme cs) {
    return Row(
      children: [
        Icon(Icons.shield_outlined, size: 12, color: cs.onSurface),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            'Freight cover',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        for (final level in TradeInsurance.values)
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: _coverChip(level, cs),
          ),
      ],
    );
  }

  Widget _coverChip(TradeInsurance level, ColorScheme cs) {
    final selected = _cover == level;
    // A zero-risk route is free to insure, and saying so is the point: it is
    // what teaches that the premium is priced off *this* order's distance.
    final free = level != TradeInsurance.none && _nearestPlanRisk() == 0.0;
    final label = switch (level) {
      TradeInsurance.none => 'NONE',
      TradeInsurance.half => 'HALF',
      TradeInsurance.full => 'FULL',
    };
    return InkWell(
      key: Key('market-cover-${level.name}'),
      onTap: () => setState(() => _cover = level),
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: selected
              ? Colors.teal.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color:
                selected ? Colors.teal : cs.onSurface.withValues(alpha: 0.25),
          ),
        ),
        child: Text(
          free ? '$label · FREE' : label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
            color: selected ? Colors.teal : cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  /// The lowest risk on the card right now, used only to decide whether the
  /// FREE badge is honest.
  ///
  /// Cheap and honest, but note what it is *not*: the premium is still priced
  /// per row from that row's own plan. A badge is a hint about the cheapest
  /// route on screen, not a promise about the order being placed.
  double _nearestPlanRisk() {
    var lowest = 1.0;
    for (final type in _marketCommodities) {
      final plan = _plan(type, TradeDirection.buy, _marketAmounts[type] ?? 1000,
          widget.planet);
      if (plan.allocations.isEmpty) continue;
      final risk = PlanetTradeService.orderRiskFraction(plan);
      if (risk < lowest) lowest = risk;
    }
    return lowest;
  }

  Widget _marketRow(String type, Planet planet, ColorScheme cs) {
    final stored = planet.storedFor(type);
    final amount = _marketAmounts[type] ?? 1000;
    final label = type[0].toUpperCase() + type.substring(1);
    // A sell cannot promise what the store does not hold: clamp the volume
    // before planning, so every planned share is creatable.
    final sellVolume = amount < stored ? amount : stored;
    final buyPlan = _plan(type, TradeDirection.buy, amount, planet);
    final sellPlan = sellVolume > 0
        ? _plan(type, TradeDirection.sell, sellVolume, planet)
        : null;
    var buyTotal = 0;
    for (final s in buyPlan.allocations) {
      buyTotal += s.units * s.unitPrice;
    }
    var sellTotal = 0;
    if (sellPlan != null) {
      for (final s in sellPlan.allocations) {
        sellTotal += s.units * s.unitPrice;
      }
    }
    // The premium is priced from the **same** risk figure the quote prints, so
    // the two can never disagree — and the buy button is gated on the sum, since
    // cover you cannot afford is not cover.
    final buyPremium = PlanetTradeService.premiumFor(buyPlan, _cover);
    final sellPremium =
        sellPlan == null ? 0 : PlanetTradeService.premiumFor(sellPlan, _cover);
    final canBuy = buyPlan.unitsAllocated > 0 &&
        widget.credits >= buyTotal + buyPremium &&
        buyTotal > 0;
    // **Cover is charged on a sell too**, so a pilot who cannot pay the premium
    // must be told why rather than discovering it as a refund.
    final canSell = sellPlan != null &&
        sellPlan.unitsAllocated > 0 &&
        widget.credits >= sellPremium;
    final buyDisabledReason = buyPlan.unitsAllocated <= 0
        ? 'No port is selling $label right now'
        : buyPremium > widget.credits - buyTotal
            ? 'Need ${compact(buyTotal + buyPremium)} cr including cover'
            : 'Need ${compact(buyTotal + buyPremium)} cr for that order';
    final sellDisabledReason = sellVolume <= 0
        ? 'Nothing stored to sell'
        : sellPremium > widget.credits
            ? 'Not enough credits for the cover premium'
            : 'No port is buying $label right now';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                '${compact(stored)} / ${compact(planet.capacityFor(type))}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            PlanetMiniStepper(Icons.remove_rounded, () {
              setState(() {
                _marketAmounts[type] =
                    (amount - 100).clamp(minimumMarketAmount, 1 << 30);
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                compact(amount),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            PlanetMiniStepper(Icons.add_rounded, () {
              setState(() {
                _marketAmounts[type] =
                    (amount + 100).clamp(minimumMarketAmount, 1 << 30);
              });
            }),
            Padding(
              padding: const EdgeInsets.only(left: 4, right: 2),
              // A menu, not a bare "Max". The two maxima are usually wildly
              // different — one is bounded by the galaxy's stock and the other
              // by this world's store — and a single button has to pick one,
              // so it either fills the field with a number the other button
              // cannot honour or it guesses wrong half the time. Naming both
              // directions *and their figures* teaches the asymmetry, which is
              // the thing that made the old button confusing rather than
              // merely wrong.
              child: PopupMenuButton<TradeDirection>(
                key: Key('market-max-$type'),
                tooltip: 'Set the maximum order size',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 0),
                offset: const Offset(0, 18),
                position: PopupMenuPosition.under,
                onSelected: (d) => _setMarketMax(type, d, planet),
                itemBuilder: (ctx) => [
                  for (final d in TradeDirection.values)
                    PopupMenuItem<TradeDirection>(
                      value: d,
                      height: 30,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            d == TradeDirection.buy
                                ? 'Max buy  '
                                : 'Max sell  ',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: d == TradeDirection.buy
                                  ? Colors.blue
                                  : Colors.orange,
                            ),
                          ),
                          Text(
                            // Quoted live, not cached: the two maxima move
                            // every tick as ports regen and the store fills,
                            // so a value captured when the row was built
                            // would be a stale promise.
                            compact(_marketMaxFor(type, d, planet)),
                            style: TextStyle(
                              fontSize: 10,
                              fontFamily: 'monospace',
                              color: Theme.of(ctx)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Max',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      Icon(Icons.arrow_drop_down_rounded,
                          size: 14, color: cs.onSurface.withValues(alpha: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            PlanetMiniButton('Buy', Colors.blue, canBuy, () {
              widget.onPlaceOrder(type, TradeDirection.buy, amount, _cover);
            }, key: Key('market-buy-$type'), disabledReason: buyDisabledReason),
            const SizedBox(width: 4),
            PlanetMiniButton('Sell', Colors.orange, canSell, () {
              widget.onPlaceOrder(type, TradeDirection.sell, amount, _cover);
            },
                key: Key('market-sell-$type'),
                disabledReason: sellDisabledReason),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _marketPreview(buyPlan, buyTotal, sellPlan, sellTotal, sellVolume,
              _portNames(), buyPremium, sellPremium),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// One honest line per direction: what it costs, who fills it, and what the
  /// galaxy could not cover. Shown *before* paying, because a paid order is a
  /// reservation and the player should see the shortfall while it is still
  /// a quote. Ports are named, not counted: "1 port(s)" says where to look
  /// without saying what it is called.
  String _marketPreview(
      TradePlan buyPlan,
      int buyTotal,
      TradePlan? sellPlan,
      int sellTotal,
      int sellVolume,
      Map<int, String> portNames,
      int buyPremium,
      int sellPremium) {
    String portsOf(TradePlan p) {
      final names = [
        for (final a in p.allocations)
          portNames[a.portSectorId] ?? '#${a.portSectorId}'
      ];
      if (names.isEmpty) return '';
      if (names.length == 1) return ' · ${names.first}';
      return ' · ${names.first} +${names.length - 1} more';
    }

    // The order's loss risk, from the **service** — it used to be computed here,
    // and the premium is priced from the same figure, so two copies would be two
    // chances for the cover to be sold against a different risk than the one on
    // screen.
    String riskOf(TradePlan p) {
      final pct = (PlanetTradeService.orderRiskFraction(p) * 100).round();
      if (pct <= 0) return '';
      return ' · $pct% run risk';
    }

    // The premium, on the same line as the risk it is priced from, so the
    // relationship is visible: cover costs roughly twice the chance it removes.
    String coverOf(int premium) {
      if (_cover == TradeInsurance.none || premium <= 0) return '';
      return ' · cover ${compact(premium)} cr';
    }

    final buy = buyPlan.unitsAllocated <= 0
        ? 'Buy: no port selling'
        : 'Buy ${compact(buyPlan.unitsAllocated)} → ${compact(buyTotal)} cr'
            '${portsOf(buyPlan)}${riskOf(buyPlan)}${coverOf(buyPremium)}'
            '${buyPlan.shortfall > 0 ? ' · short ${compact(buyPlan.shortfall)}' : ''}';
    final sell = sellVolume <= 0
        ? 'Sell: nothing stored'
        : sellPlan == null || sellPlan.unitsAllocated <= 0
            ? 'Sell: no port buying'
            : 'Sell ${compact(sellPlan.unitsAllocated)} → ${compact(sellTotal)} cr'
                '${portsOf(sellPlan)}${riskOf(sellPlan)}${coverOf(sellPremium)}'
                '${sellPlan.shortfall > 0 ? ' · short ${compact(sellPlan.shortfall)}' : ''}';
    return '$buy\n$sell';
  }

  Map<int, String> _portNames() => {
        for (final s in widget.universe)
          if (s.port != null) s.id: s.port!.name,
      };

  /// The most a [direction] order of [type] could actually place right now.
  ///
  /// **Direction-specific, and that is the whole point.** The two maxima are
  /// routinely different by an order of magnitude: buying is capped by what
  /// ports hold across the galaxy, selling by what this world's stores hold.
  /// A single "Max" that took the larger of the two — which is what this did —
  /// put a number in the field that the *other* button could not honour, so
  /// pressing Max then Sell silently sold less than Max promised. The preview
  /// line already quoted each side separately, so the player had no way to
  /// tell the field had been filled for the wrong direction.
  ///
  /// Never below [minimumMarketAmount], so Max on an empty market still leaves a
  /// placeable order rather than zero.
  int _marketMaxFor(String type, TradeDirection direction, Planet planet) {
    final stored = planet.storedFor(type);
    if (direction == TradeDirection.sell) {
      if (stored <= 0) return minimumMarketAmount;
      // Capped by the store: a sell cannot promise goods the world does not
      // have, so an over-large volume would plan shares the order then cannot
      // create.
      final plan = _plan(type, TradeDirection.sell, stored, planet);
      final max = plan.unitsAllocated;
      return max < minimumMarketAmount ? minimumMarketAmount : max;
    }
    final plan = _plan(type, TradeDirection.buy, 1 << 30, planet);
    final max = plan.unitsAllocated;
    return max < minimumMarketAmount ? minimumMarketAmount : max;
  }

  void _setMarketMax(String type, TradeDirection direction, Planet planet) {
    final max = _marketMaxFor(type, direction, planet);
    setState(() => _marketAmounts[type] = max);
  }

  /// In-flight jobs grouped by request: one tap on Buy/Sell is one order,
  /// possibly split across ports. Legacy jobs with no order id group alone.
  List<OrderGroup> _orderGroups(Planet planet) {
    final groups = <OrderGroup>[];
    final index = <String, int>{};
    for (final job in planet.tradeJobs) {
      final key =
          job.orderId.isEmpty ? 'job:${job.id}' : 'order:${job.orderId}';
      final at = index[key];
      if (at == null) {
        index[key] = groups.length;
        groups.add(OrderGroup(
          cancelId: job.orderId.isEmpty ? job.id : job.orderId,
          direction: job.direction,
          commodity: job.commodity,
          jobs: [job],
        ));
      } else {
        groups[at].jobs.add(job);
      }
    }
    return groups;
  }

  /// One request, one row, one Cancel: aggregate units up top, one countdown
  /// per port-run below (each run has its own cadence, so they cannot share
  /// a bar), and the slowest run sets the ETA.
  Widget _marketOrderRow(
    Planet planet,
    OrderGroup group,
    ColorScheme cs,
  ) {
    final isBuy = group.direction == TradeDirection.buy;
    var total = 0;
    var delivered = 0;
    var lost = 0;
    var seized = 0;
    var ticksLeft = 0;
    for (final job in group.jobs) {
      total += job.unitsTotal;
      // `unitsDelivered`, not `unitsTotal - unitsRemaining`: the latter counts
      // a lost run as delivered, so an order that lost its only run read
      // "5.0K / 10.0K" while the store gained nothing. A counter that
      // overstates delivery is worse than no counter.
      delivered += job.unitsDelivered;
      lost += job.unitsLost;
      seized += job.unitsSeized;
      if (job.ticksLeft > ticksLeft) ticksLeft = job.ticksLeft;
    }
    final eta = GameClock.estimate(ticksLeft);
    final commodity =
        group.commodity[0].toUpperCase() + group.commodity.substring(1);
    final ports = group.jobs.map((j) => j.portSectorId).toSet().length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              isBuy ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              size: 12,
              color: isBuy ? Colors.blue : Colors.orange,
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '${isBuy ? 'Buy' : 'Sell'} $commodity'
                '${ports > 1 ? ' · $ports ports' : ' · port #${group.jobs.first.portSectorId}'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                // Shortfall is named, not silently subtracted: the player needs
                // to see that the gap between "of" and "delivered" has a name,
                // and the Report says which one. Lost and impounded are
                // reported separately because they are different events —
                // pirates and customs call for different decisions — and a
                // single "LOST" for both would tell the player their goods were
                // destroyed when most of them arrived.
                '${compact(delivered)} / ${compact(total)}'
                '${lost > 0 ? ' · ${compact(lost)} LOST' : ''}'
                '${seized > 0 ? ' · ${compact(seized)} HELD' : ''}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: lost > 0 || seized > 0 ? FontWeight.bold : null,
                  color: lost > 0 || seized > 0
                      ? cs.error
                      : cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            PlanetMiniButton('Cancel', cs.error, true, () {
              widget.onCancelOrder(group.cancelId);
            }),
          ],
        ),
        if (lost > 0 || seized > 0) ...[
          const SizedBox(height: 2),
          _lostNotice(cs, lost, seized),
        ],
        const SizedBox(height: 4),
        for (final job in group.jobs) ...[
          _marketRunRow(job, cs),
          const SizedBox(height: 4),
        ],
        Text(
          eta.isEmpty ? 'arriving' : 'done $eta of play',
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  /// The standing warning under an order that has come up short.
  ///
  /// Always present once anything is gone rather than a transient flash: the
  /// count is on the order until it completes, and a marker that appeared for
  /// one tick and vanished is a thing the player would not have read.
  Widget _lostNotice(ColorScheme cs, int lost, int seized) {
    final parts = <String>[
      if (lost > 0) '${compact(lost)} destroyed',
      if (seized > 0) '${compact(seized)} held by customs',
    ];
    return Row(
      children: [
        Icon(Icons.warning_amber_rounded, size: 11, color: cs.error),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${parts.join(' · ')} — see Report for the cause',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: cs.error,
            ),
          ),
        ),
      ],
    );
  }

  /// One port-run's countdown: which port, which run of how many, and a bar
  /// that moves every second without ever claiming a tick that has not landed
  /// (see [TickProgressBar]).
  Widget _marketRunRow(TradeJob job, ColorScheme cs) {
    final currentRun =
        job.runsDone + 1 > job.runsTotal ? job.runsTotal : job.runsDone + 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'port #${job.portSectorId} · run $currentRun of ${job.runsTotal}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.55),
          ),
        ),
        const SizedBox(height: 2),
        TickProgressBar(
          remaining: job.ticksRemaining,
          total: job.ticksPerRun,
          secondsPerTick: GameClock.secondsPerTick,
        ),
      ],
    );
  }
}

class OrderGroup {
  OrderGroup({
    required this.cancelId,
    required this.direction,
    required this.commodity,
    required this.jobs,
  });

  final String cancelId;
  final TradeDirection direction;
  final String commodity;
  final List<TradeJob> jobs;
}
