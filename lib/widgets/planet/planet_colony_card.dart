import 'package:flutter/material.dart';

import 'package:cosmic_trader/core/number_format.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/planet_classes.dart';
import 'package:cosmic_trader/widgets/planet/planet_info_row.dart';
import 'package:cosmic_trader/widgets/planet/planet_supply_warning.dart';
import 'package:cosmic_trader/widgets/planet/planet_transit_panel.dart';

/// Colonists moved per tap of a workforce stepper, scaled to the colony so a
/// world of a million is not adjusted ten at a time.
int _workforceStep(int population) {
  if (population >= 100000) return 1000;
  if (population >= 10000) return 500;
  if (population >= 1000) return 100;
  return 10;
}

/// The step actually used for a move of [delta] colonists.
///
/// A fixed step is unusable at the small end: a 900-colony world steps 100 at a
/// time, so with 40 colonists in the reserve the add button was **dead** —
/// `reserve >= 100` was false and there was no way to move any of them. The
/// player saw a full population and four disabled buttons.
///
/// So the step is clamped to what is actually available on the side being moved.
/// A 40-colonist reserve still moves 40, not "nothing, because 100 does not fit".
int _effectiveStep(int step, int available) =>
    available < step ? (available > 0 ? available : 0) : step;

/// Colonists on a track, by track name.
int _staffedOn(Planet planet, String track) => switch (track) {
      'minerals' => planet.colonistsMinerals,
      'organics' => planet.colonistsOrganics,
      'industrial' => planet.colonistsIndustrial,
      _ => 0,
    };

String _trackLabel(String track) => switch (track) {
      'minerals' => 'Minerals',
      'organics' => 'Organics',
      'industrial' => 'Industrial',
      _ => track,
    };

Color _trackColour(String track) => switch (track) {
      'minerals' => Colors.orange,
      'organics' => Colors.green,
      'industrial' => Colors.blue,
      _ => Colors.grey,
    };

/// The staffing at which this track produces the most it can.
int _optimumFor(Planet planet, String track) =>
    planet.classSpec.productFor(track).optimumColonists;

/// The most this track can produce in a day, whatever the colony does.
///
/// The colony's **achievable** ceiling, not the class table's. The two agree only
/// for a yield-1.0 colony, and a level-1 world rolled below 1.0 has a class figure
/// roughly twice what it can produce. Labelling that "max" told a
/// correctly-staffed track it was short of the ceiling, and the only way to close
/// the gap is to staff past the optimum — the one move the triangle punishes. See
/// [Planet.achievableMaxPerDayFor].
int _ceilingFor(Planet planet, String track) =>
    planet.achievableMaxPerDayFor(track);

/// How many of a world's three production tracks sit exactly at their optimum.
///
/// Counts tracks that are *at* the optimum rather than tracks that produce,
/// because a track past its optimum still produces and still counts as badly
/// staffed. Reported rather than derived into a judgement, so the colony card
/// states the situation instead of grading the player.
int _tracksOnOptimum(Planet planet) {
  var n = 0;
  for (final track in PlanetClassSpec.tracks) {
    final spec = planet.classSpec.productFor(track);
    if (!spec.isPossible) continue;
    if (_staffedOn(planet, track) == spec.optimumColonists) n++;
  }
  return n;
}

/// The derived drone output, and the ceiling it is measured against.
///
/// Shown as a **ceiling with a progress figure** rather than a plain number,
/// because the number on its own cannot be acted on: drones fall when any track
/// is mis-staffed, so the useful information is how close this world is to what
/// it could produce at all. That is the whole reason the cap is derived — a
/// player can see the gap their own decisions opened.
class _DroneReadout extends StatelessWidget {
  const _DroneReadout({required this.planet, required this.cs});

  final Planet planet;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final perDay = planet.classSpec.droneOutputPerDay(
      orePerDay: planet.outputPerDayFor('minerals'),
      organicsPerDay: planet.outputPerDayFor('organics'),
      equipmentPerDay: planet.outputPerDayFor('industrial'),
    );
    final ceiling = planet.achievableMaxDroneOutputPerDay;
    final onPeak = _tracksOnOptimum(planet);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Drones (derived)',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface.withValues(alpha: 0.75))),
              Text('${compact(perDay)}/day',
                  style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: Colors.redAccent)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Made from what the three tracks produce. Ceiling '
            '${compact(ceiling)}/day at $onPeak of 3 tracks on optimum.',
            style: TextStyle(
                fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
          ),
        ],
      ),
    );
  }
}

/// A `+`/`−` workforce stepper.
class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final button = SizedBox(
      width: 26,
      height: 24,
      child: Material(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 14,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    // Wrapping rather than putting the text in the row: a workforce row is four
    // numbers wide and there is no room to spell out what each glyph does. This
    // is the fix for a genuine confusion — a bare +/- pair on a row of numbers
    // does not say that the pair *moves colonists between two places*, which is
    // the only thing these buttons do.
    return Tooltip(message: tooltip!, child: button);
  }
}

/// The explanation behind the Supply draw row's `(i)` bubble.
///
/// Every number here is **read from the model** rather than typed into the
/// sentence. The Planet Guide carried the same explanation and had drifted: it
/// said the bill was a share of "one tick's own output" when the code charges a
/// share of one **day's** — wrong by a factor of [Planet.supplyInterval]. A help
/// text that states a number the model does not use is worse than no help text,
/// so this one cannot state a stale one.
/// Why two identical colonies can produce different amounts.
///
/// `productionEfficiency` is rolled in [Planet.minEfficiency]..[maxEfficiency]
/// when a world is generated and never changes, while
/// [Planet.developmentMultiplier] starts at 1.00 and rises with the Citadel
/// level. Their product is [Planet.yieldScale], which is the multiplier every
/// per-day figure on this screen is already showing — so before this row
/// existed, two worlds of the same type with the same colonists produced visibly
/// different numbers and the screen said nothing about why.
///
/// The Citadel half is the part worth watching: it is the only one a player can
/// move, and levelling a world is exactly the purchase this number is meant to
/// justify.
String yieldTooltipText(Planet planet) {
  String pct(double v) => '${(v * 100).round()}%';
  return 'This world\'s yield.\n\n'
      'Natural yield ${pct(planet.productionEfficiency)} — rolled when the '
      'world was found, between ${pct(Planet.minEfficiency)} and '
      '${pct(Planet.maxEfficiency)}, and never changes. Two worlds of the same '
      'type can differ by up to 3x on this alone.\n\n'
      'Citadel development ${pct(planet.developmentMultiplier)} — rises with '
      'the world\'s level, and is the only part you can change.\n\n'
      'Together ${pct(planet.yieldScale)}, applied to the output rather than '
      'to the colonists, so a better-yield world reaches the same ceiling '
      'sooner but never exceeds what the world can physically do.';
}

String supplyTooltipText(Planet planet) {
  final pct = (Planet.supplyShareOfOutput * 100).round();
  final days = Planet.supplyInterval;
  return 'The colony consumes goods to keep running.\n\n'
      'Once every $days ticks (one game day) it is billed $pct% of the '
      'output it produces in that same $days ticks, drawn at random from '
      '${Planet.supplyCommodities.join(', ')}.\n\n'
      'It is a share of what the colony MAKES, not a fixed amount per '
      'colonist, so the burden stays the same relative size whether you are '
      'running a hundred colonists or two million. Goods waiting in the '
      'shipment pool count, so a busy colony is never told it cannot feed '
      'itself while its own output sits uncollected.\n\n'
      'If the drawn commodity is not in store, the bill falls back through '
      'the others — a world that cannot make organics is not punished for '
      'the draw landing on organics.\n\n'
      'Nothing dies. An unpaid bill is reported, not inflicted: the colony '
      'keeps running and you are told it is short.';
}

/// The Colony card: population, the three workforce tracks, and derived drones.
///
/// Extracted from `PlanetScreen`. It reads a [Planet] and reports a workforce
/// change through [onAdjust] — the transaction itself (bounds check, persist,
/// repaint) stays on the screen, because the screen owns the write.
class PlanetColonyCard extends StatelessWidget {
  const PlanetColonyCard({
    super.key,
    required this.planet,
    required this.cs,
    required this.canAssign,
    required this.onAdjust,
  });

  final Planet planet;
  final ColorScheme cs;

  /// Whether the player may move colonists on this world at all.
  final bool canAssign;

  /// Called with a track name and a signed delta when a stepper is pressed.
  final void Function(String track, int delta) onAdjust;

  @override
  Widget build(BuildContext context) {
    final step = _workforceStep(planet.population);
    final unsupplied = planet.storesEmpty;

    Widget trackRow(
      String label,
      int count,
      int perDay,
      int optimum,
      int trackCeiling,
      Color colour,
      String track,
    ) {
      // A track the world cannot produce is **locked**, not merely empty.
      // A stepper that accepts colonists onto a track yielding nothing looks
      // like a bug, and a player who cannot see why their organics stay at zero
      // will assume the mechanic is broken. The label says it outright.
      final producible = planet.canProduce(track);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    compact(count),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: colour,
                    ),
                  ),
                  // Where the peak is, under the count. Without this the whole
                  // mechanic is invisible: a player sees a number fall when they
                  // add colonists and has no way to learn that a specific number
                  // would have been the best one.
                  if (producible && optimum > 0)
                    Text(
                      'of ${compact(optimum)}',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 9,
                        fontFamily: 'monospace',
                        color: cs.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                !producible
                    ? 'cannot produce'
                    // **Per day, not per tick.** A day is 2,880 ticks, so a
                    // track at its peak yields a fraction of a unit per tick and
                    // the per-tick figure is either zero or a rounding artefact.
                    // It was also read from a getter that *consumes* the
                    // production remainder, so simply looking at the screen was
                    // taking production away from the colony.
                    : perDay <= 0
                        ? '—'
                        // Overshooting the peak is the mechanic, so when it
                        // happens the row says so rather than showing a smaller
                        // number with no explanation.
                        : count > optimum && optimum > 0
                            ? '${compact(perDay)}/day '
                                '(max ${compact(trackCeiling)})'
                            : '${compact(perDay)}/day'
                                '${optimum > 0 ? ' / max ${compact(trackCeiling)}' : ''}',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: perDay > 0
                      ? cs.onSurface.withValues(alpha: 0.6)
                      : cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
            if (canAssign) ...[
              const SizedBox(width: 6),
              // Each button's step is clamped to what is available on its own
              // side, so a 40-colonist reserve moves 40 rather than being
              // disabled for not fitting 100. Enabled on `> 0`, not `>= step`.
              _StepButton(
                icon: Icons.add,
                // Names the source, because a bare +/- pair on a row of numbers
                // does not say where the colonists come from. It is the reserve —
                // the implicit `population - on tracks` figure three rows above —
                // and the tooltip is the only place that says so.
                tooltip: producible
                    ? 'Assign from reserve (${compact(planet.reserveColonists)} idle)'
                    : 'Cannot produce this - the reserve is not assignable here',
                enabled: producible && planet.reserveColonists > 0,
                onTap: () => onAdjust(
                    track, _effectiveStep(step, planet.reserveColonists)),
              ),
              _StepButton(
                icon: Icons.remove,
                tooltip: 'Return to reserve',
                // Remove stays enabled even on a dead track: a colony generated
                // before a world became unable to produce something should not be
                // stuck holding colonists who will never work again. That is also
                // why the step is clamped to what is actually on the track rather
                // than being the full step.
                enabled: count > 0,
                onTap: () => onAdjust(track, -_effectiveStep(step, count)),
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Colony',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            PlanetInfoRow('Population',
                '${compact(planet.population)} / ${compact(planet.colonistMax)}'),
            PlanetInfoRow('On tracks', compact(planet.assignedColonists)),
            PlanetInfoRow('Reserve', compact(planet.reserveColonists)),
            // The one figure on this screen that explains why two identical
            // colonies differ. `productionEfficiency` is a generation-time roll
            // in [0.5, 1.5) and `developmentMultiplier` is 1.00 at level 1, so
            // roughly half of all generated worlds started below a yield of 1.0
            // — and every per-day figure below already included it. Sourced from
            // the model rather than from a stored string, so the row cannot
            // disagree with the arithmetic the tick runs.
            PlanetInfoRow(
                'World yield', '${(planet.yieldScale * 100).round()}%',
                info: yieldTooltipText(planet)),
            PlanetInfoRow(
                'Supply draw',
                '${compact(planet.supplyDraw)} every '
                    '${Planet.supplyInterval} ticks',
                info: supplyTooltipText(planet)),
            PlanetInfoRow('Next supply', '${planet.ticksToSupply} ticks'),
            // The shipment panel goes **after the stats block, not inside it**,
            // and it carries its own tinted container. As an info row sitting
            // between "Reserve" and "Supply draw" it was just another line of
            // figures — a player who had spent credits on 100 colonists reported
            // "nothing happens on the planet screen". A distinct block that
            // appears on purchase and disappears on arrival is the signal; where
            // it sits is most of why it reads as one.
            if (planet.hasColonistsInTransit) ...[
              const SizedBox(height: 10),
              PlanetTransitPanel(planet: planet, cs: cs),
            ],
            if (unsupplied) ...[
              const SizedBox(height: 8),
              PlanetSupplyWarning(planet: planet, cs: cs),
            ],
            const SizedBox(height: 12),
            for (final t in PlanetClassSpec.tracks)
              trackRow(
                _trackLabel(t),
                _staffedOn(planet, t),
                planet.outputPerDayFor(t),
                _optimumFor(planet, t),
                _ceilingFor(planet, t),
                _trackColour(t),
                t,
              ),
            const SizedBox(height: 8),
            // Drones are **derived**, not staffed: they come from what the three
            // tracks above actually produce. A fourth workforce row would have to
            // lie about where they come from, and a stepper on it would let a
            // player "staff" drones and watch the figure refuse to move.
            _DroneReadout(planet: planet, cs: cs),
            Divider(color: cs.onSurface.withValues(alpha: 0.1), height: 1),
            const SizedBox(height: 8),
            Text(
              canAssign
                  ? '+ moves colonists off the reserve and onto the track; '
                      '\u2212 brings them back. The reserve is everyone not on a '
                      'track \u2014 they still eat. Note the drones are not '
                      'production: they are your haul crew, and they do not work '
                      'this planet\u2019s stores.'
                  : 'This world is not yours to reassign.',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
