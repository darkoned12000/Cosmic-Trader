import 'dart:math' as math;

import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/core/number_format.dart';
import 'package:flutter/material.dart';

/// Player-facing reference for the planet system, swapped inline inside
/// [ComputerScreen] alongside the Ports Guide.
///
/// The planet type table and the Citadel cost table are **generated from
/// `Planet`**, not transcribed. A hand-typed balance table in a help screen is
/// a table that lies the first time a number is retuned — and these numbers
/// have already been retuned more than once. Change the model and this screen
/// follows.
class PlanetsKnowledgeBaseScreen extends StatelessWidget {
  /// Invoked when the user taps back. This screen is swapped inline inside
  /// ComputerScreen (not pushed as a route), so popping the Navigator would
  /// pop the whole GameShell route and kill the game.
  final VoidCallback onBack;

  const PlanetsKnowledgeBaseScreen({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planet Guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: onBack,
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            theme,
            cs,
            Icons.travel_explore_rounded,
            'Finding a Planet',
            [
              'Planets sit in sectors. A planet marker is brown on the galaxy map and the tactical map, and shows whether it is scanned, unclaimed, or owned.',
              '',
              'You must scan a world before you can land on it. Scanning costs '
                  '${EnergyService.scanCost} energy, and it is one action, not two — the sector view and the Planet screen both run the same scan, so neither can charge a different price for the same look.',
              '',
              'A scan identifies the world and its owner, and credits you +1 standing with whoever owns it. A world you already own is scanned on sight.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.groups_rounded,
            'The Colony and Its Workforce',
            [
              'Every colony is a population of colonists split across three production tracks, plus a reserve.',
              '',
              'Minerals, Organics, Industrial — colonists on a track produce that commodity every tick.',
              'Reserve — colonists not on a track. They produce nothing, and they are the pool you draw from when you reassign a workforce.',
              '',
              'Drones are not a fourth track. They are derived from what the three tracks above actually make, so there is no stepper for them and nothing to assign — a workforce row for drones would let you staff it and watch the figure refuse to move. See Production below.',
              '',
              'On a world you own, the + and − buttons on each track move colonists between that track and the reserve. The step scales with your population so a large colony is not adjusted ten at a time.',
              'You can only reassign a workforce on a world your faction owns.',
              '',
              'Colonists come from your own faction\'s homeworld, and what they cost depends on how far your planet is from it — see Colonist Supply below. Population is capped by planet type, and the cap is shown next to your population.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.trending_up_rounded,
            'Production',
            [
              'Each tick, every track delivers:',
              '',
              '    colonists on track  ×  type multiplier  ×  world efficiency  ×  development',
              '',
              'World efficiency (${Planet.minEfficiency}–${Planet.maxEfficiency}) is rolled once when the galaxy is generated, so two identical worlds are not identical colonies.',
              'Development is your Citadel level. It is deliberately shallow — see the Citadel section for why.',
              '',
              'Per-tick output is usually a fraction of a unit. A Jungle minerals track staffed with 5,000 colonists yields about 0.38 a tick, so the stored whole number moves only every few ticks. The Resources card shows two decimals and includes the fraction not yet banked, which is why a working colony can look like a still one — it is not, and nothing is being rounded away.',
              '',
              'Drones are derived, not staffed: a day of drones is the sum of the three tracks\' output divided by a per-class figure, so the ceiling on your fleet falls out of the production caps rather than being a separate number. Overstaffing a track past its optimum lowers all three outputs, and therefore the drones too.',
              '',
              'Nothing is thrown away while you are away. Each store has its own limit, and when one fills the surplus moves into a shipment pool that holds ${Planet.pendingCapMultiple}× the store and keeps growing. Sweep it into the stores with the pool panel whenever you are here — it is free, and moving it is what makes it sellable.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.public_rounded,
            'Planet Types',
            [
              'A world\'s type decides what it is good at, how many colonists it can hold, and what its air is. The type advantage outranks development on purpose: a well-run Lava world is still a mineral powerhouse, and a mature Ocean world is still the best food producer.',
              '',
              ..._typeRows(),
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.analytics_rounded,
            'Type Reference',
            [
              'The full numbers behind the table above, read straight from the game data. Output is per colonist per tick before your world\'s efficiency and level bonuses.',
              '',
              'Output/colonist      Min   Org   Ind   Dro | Colonist max | Organics to import | Strongest at',
              ..._referenceRows(),
              '',
              '"Organics to import" is how many organics a world that cannot grow any must be shipped in to pay every Citadel level-up cost from here to level 6 — a figure rather than a multiplier, because "×0.00" does not tell you that you have a problem to solve. On a world with poor soil (Lava, Barren, Toxic, Ice, Moon) it is the whole requirement; everywhere else it is zero.',
              '',
              'Note that a world\'s output per colonist and its capacity are two different things. A Lava world out-produces any other type per colonist, but it also holds the fewest colonists, so its total output is small. A Terran world does less per head and holds twenty times as many.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.commute_rounded,
            'Colonist Supply',
            [
              'Colonists come from your own faction\'s homeworld, and the price is set by how many warps away your planet is from it.',
              '',
              'A Duran Hegemony pilot draws Duran colonists; a Vinari draws Vinari. Nobody ships in settlers of another species, so a world under your control is the only supply of your own people — and if you lose it, you cannot grow.',
              '',
              'Your capital grows its own. Every ${Planet.colonistInfusionTicks} ticks a controlled homeworld adds colonists to its population, and a reserve capital takes over if the main one falls. A levelled capital adds more, from ${_infusion(1)} every ${Planet.colonistInfusionTicks} ticks at Outpost to ${_infusion(6)} at Citadel.',
              '',
              'That is what makes buying affordable rather than possible. The per-colonist price below is severe at distance, and it is charged per colonist: so without a local supply, two identical colonies could differ by more than twenty times on nothing but where their capital happened to sit. Distance is still a real cost; it just buys you the transport of people who already exist.',
              '',
              'Hops from homeworld    Credits per colonist    100,000 colonists    1,000,000 colonists',
              ..._transportRows(),
              '',
              'You can also fly there yourself, load your hold from the capital\'s population, and carry them back — which costs cargo space and one shipment of fuel instead of the per-colonist price. Both routes stay open; buying is for the pilot in a hurry, hauling is for the one already going that way.',
              '',
              'Your capital is the cheapest place to settle, and a reserve capital takes over if the main one is captured or lost. A faction with neither is an exile and buys from Terra Prime at a punishing rate — expensive, but never stuck.',
              '',
              'A purchase is a shipment, not an instant edit. Credits leave the moment you order, and the colonists spend ${Planet.colonistTransitDelayTicks} ticks in transit before joining the world\'s reserve — the colony card shows a progress bar for the flight. They arrive in the reserve, not on a track, so you still assign them yourself.',
              '',
              'Each shipment also burns the energy it would cost to fly there — the same engine-aware rate as a real warp — whatever the shipment size. So sending one lot of a thousand costs the same fuel as ten lots of a hundred, and a good engine genuinely makes a distant empire cheaper to run.',
              '',
              'The galaxy is small, so the price climbs steeply rather than gently: the farthest worlds cost more than twenty times what the nearest do. Settle close to Terra while you are growing, and treat a distant world as a deliberate investment rather than an obvious one.',
              '',
              'Bulk goods are not priced by distance — a raw ore run is not worth taxing per tonne, and levelling a planet should not be a second grind on top of populating it. They ride the same shipments and pay the same fuel.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.restaurant_rounded,
            'Colony Supply',
            [
              'Every ${Planet.supplyInterval} ticks — one game day — a colony is billed for the goods its people need: ${(Planet.supplyShareOfOutput * 100).round()}% of the output it produces in those same ${Planet.supplyInterval} ticks, drawn at random from ${Planet.supplyCommodities.join(', ')}.',
              '',
              'The base is the output of ${Planet.supplyInterval} ticks, not of one. It said "one tick\'s own output" until that was caught, which understated the bill by a factor of ${Planet.supplyInterval} — a help text quoting a number the model does not use is worse than no help text, and the guard that pinned the interval and the percentage did not cover the base.',
              '',
              'It is a share of what the colony makes rather than a fixed amount per colonist, so the bill is the same relative size whether you are running a world of a hundred or a world of two million.',
              '',
              'The commodity is drawn at random, and a colony that has none of it falls back to whatever it does have — so a world that cannot make organics is not punished for the draw landing on organics.',
              '',
              'Goods already produced and waiting in the shipment pool count as goods, so a busy colony is never told it cannot feed itself while its own output sits uncollected.',
              '',
              'There is no starvation and no population loss. A colony whose stores are empty simply goes unpaid, and the planet screen says so with the fix: haul goods in, or plant a world beside it that grows what it cannot.',
              '',
              'A harsh world cannot make organics at all — Lava, Barren, Toxic, Ice and Moon have no organics output whatsoever, matching the classic Volcanic world. Their workforce stepper is locked on that track and says so, because a stepper that accepts colonists onto a dead track looks like a bug.',
              '',
              'That is a gap rather than a penalty: a harsh world is not taxed for being harsh, it is structurally unable to feed itself. The two answers are to unload organics you have hauled in, or to plant a world beside it that grows them — and a sector holds up to three.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.fort_rounded,
            'Citadel Levels',
            [
              'A planet works up through six tiers, from Outpost to Citadel. Each level needs colonists and stored resources delivered to the world. The resources are spent the moment work begins, not when it finishes, so a build is a commitment: a world halfway to Citadel is holding an investment.',
              '',
              ..._levelRows(),
              '',
              'Build time is counted in game ticks, and a tick only happens while the game is running. Nothing progresses while you are away — which is deliberate. A wall-clock timer would finish every build the moment you closed the game and nothing else, so you would come back a week later advanced past a galaxy that had stood still.',
              '',
              'What each tier gives you:',
              ..._levelGrantRows(),
              '',
              'Every row above is generated from the model, not typed by hand. The '
                  'planet screen shows the same figures as a "current -> next" delta for '
                  'whichever level you are standing at, because a player at a level gate '
                  'wants the change, not the whole table.',
              '',
              'Population ceilings scale with the tier rather than being a fixed per-type number. A fixed ceiling was the original bug: the top gate wanted a million colonists while seven of the ten world types capped below that, so those worlds could never reach Citadel no matter how much you developed them.',
              '',
              'Development bonus by level:',
              ...Planet.levelDevelopment.entries.map((e) =>
                  '  Level ${e.key} ${Planet.levelTitles[e.key - 1].padRight(18)} ${e.value.toStringAsFixed(2)}×'),
              '',
              'Note that development scales gently on purpose. An earlier draft used a much steeper curve, which compounded with the type multipliers and the population caps into something like a 110× spread between the best and worst possible colony — which would have made every world but one worthless. Storage and defence are meant to be what levelling buys.',
              '',
              'Storage is capped per commodity and differs sharply by world type: a Volcanic world holds a great deal of minerals and almost no organics, an Oceanic world the reverse. A store also always has room for at least two hours of what your colony currently makes, so no colony can ever out-produce its own infrastructure however large it grows — and storage grows with Citadel level on top of that.',
              '',
              'Only a shipment pool left completely untouched for days will finally start losing goods, which is the point: your colonies keep earning whether or not you visit them.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.shield_moon_rounded,
            'Defence',
            [
              'Every world carries a defence level, a shield rating and an armour (hull) rating. Levelling the world raises all three — see the Citadel section for what each tier grants.',
              '',
              'Drones are a colony product, derived from what the three production tracks make rather than staffed from a track of their own, and they are counted separately from your ship\'s drones. A world that produces nothing produces no drones.',
              '',
              'Invasion — attacking and capturing a defended world — is not implemented yet, so these figures are what the world will defend itself with rather than something you can currently test.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.home_work_rounded,
            'Homeworlds',
            [
              'Each major faction — Duran, Vinari, Traders — has a homeworld that quietly builds their ships. Pirates hold scattered outposts instead of a capital.',
              '',
              'A homeworld produces one ship every ${Planet.defaultSpawnInterval} ticks. Two things govern it:',
              '  • Control. A homeworld captured by another faction stops building. Recapture it and production resumes — losing your capital is a serious setback, not a permanent end.',
              '  • Population. Yards stand down once a faction already has ships to spare, so a strong faction stops adding to its numbers.',
              '',
              'A second, reserve homeworld sits cold while the primary is intact and takes over if the primary is captured or lost.',
              '',
              'Pirate outposts work the same way on a slower cadence (${Planet.pirateOutpostSpawnInterval} ticks) — they are not a capital, but they do replace their losses while they hold ground.',
              '',
              'If a faction has no world under its control at all, it cannot rebuild its fleet, and its numbers will only fall.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.warehouse_rounded,
            'Storage',
            [
              'How much each world can hold at Citadel level 1. Storage grows with level, and is always at least two hours of your own output on top of that.',
              '',
              'World        Minerals  Organics  Industrial  Drones',
              ..._storageRows(),
              '',
              'A Volcanic world is a minerals fortress that cannot feed itself; an Oceanic world is the mirror image. Glacial worlds are cramped everywhere. That is what makes choosing a world a decision rather than a lottery.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.inventory_2_rounded,
            'Transfers',
            [
              'On a world you own, the Transfers panel moves goods and colonists between your ship and the world.',
              '',
              ..._transferRows(),
              '',
              'Colonists are the exception to that list — they are priced by distance from your homeworld, shown on their row as credits-per-colonist, the hop count and where they are coming from.',
              'Delivered goods and colonists are added straight to the world\'s stores and population, and colonists you bring in land in the reserve until you assign them.',
              'You can withdraw goods but not colonists.',
              'A deposit is refused if you cannot pay, cannot fuel the trip, or it would take a store over its cap.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.construction_rounded,
            'Designed, Not Yet Available',
            [
              'The following are part of the planet system\'s design and are not playable yet. They are listed so the shape of the system is on the record:',
              '',
              '• Invasion — attacking and capturing a defended world.',
              '• Colonist transport — carrying colonists from Terra in cargo holds rather than recruiting them at a port.',
              '• Supply routes — a world feeding a nearby port, which would move port prices.',
              '• Scanner module auto-scan on sector entry — there is no Scanner module in the catalogue, so nothing scans a world for free.',
              '• Planet specialisation and reserve-worker roles.',
            ],
            comingSoon: true,
          ),
        ],
      ),
    );
  }

  /// Level-1 storage row per world, derived from the model.
  List<String> _storageRows() {
    final rows = <String>[];
    for (final type in Planet.allTypes) {
      final p = Planet(name: type, planetType: type);
      rows.add(
        '${type.padRight(12)}'
        '${compact(p.maxMinerals).padLeft(8)}'
        '${compact(p.maxOrganics).padLeft(10)}'
        '${compact(p.maxIndustrial).padLeft(12)}'
        '${compact(p.maxDrones).padLeft(8)}',
      );
    }
    return rows;
  }

  /// A capital's colonists per infusion at [level], for the guide.
  ///
  /// Derived from the model rather than typed, for the reason this file's other
  /// generated tables are generated: a help screen quoting a number the model does
  /// not name drifts the first time that number is retuned, and it has been
  /// retuned repeatedly.
  int _infusion(int level) =>
      Planet.colonistInfusionByLevel[level.clamp(1, 6)] ??
      Planet.colonistInfusionByLevel[1]!;

  /// Colonist price by distance, derived from the transport model.
  List<String> _transportRows() {
    final rows = <String>[];
    for (var hops = 1; hops <= 8; hops++) {
      rows.add(
        '${(hops == 8 ? '$hops (farthest)' : '$hops').padRight(18)}'
        '${ColonistSupply.pricePerColonist(hops).toString().padLeft(22)}'
        '${compact(ColonistSupply.costFor(100000, hops)).padLeft(21)}'
        '${compact(ColonistSupply.costFor(1000000, hops)).padLeft(22)}',
      );
    }
    return rows;
  }

  /// Per-type reference row, derived entirely from the model: multipliers, the
  /// colonist cap, and the organics a world must import over its whole 1->6 if
  /// it cannot grow any. `strongest at` is read off the winning multiplier, so
  /// it cannot claim a world is good at something its numbers do not support.
  List<String> _referenceRows() {
    final rows = <String>[];
    for (final type in Planet.allTypes) {
      final m = Planet.typeMultipliers[type];
      if (m == null) continue;
      final max = Planet.colonistMaxByType[type] ?? 0;
      // A world that cannot make organics at all needs them imported for its
      // level-up costs. Stated as a figure rather than a multiplier, because
      // "x0.00" does not tell a player they have a problem to solve.
      final toFeed = m.organics <= 0
          ? (Planet.levelUpCosts.fold<int>(0, (a, c) => a + c.requiredOrganics))
          : 0;
      final best = <String, double>{
        'Minerals': m.minerals,
        'Organics': m.organics,
        'Industrial': m.industrial,
        'Drones': m.drones,
      };
      final winner = best.entries.reduce((a, b) => a.value >= b.value ? a : b);
      // A tie means the world is a genuine generalist; say so rather than
      // picking one arbitrarily and implying the others are worse.
      final tied = best.values.where((v) => v == winner.value).length;
      rows.add(
        '${type.padRight(15)}'
        '${m.minerals.toStringAsFixed(1).padLeft(5)}'
        '${m.organics.toStringAsFixed(1).padLeft(6)}'
        '${m.industrial.toStringAsFixed(1).padLeft(6)}'
        '${m.drones.toStringAsFixed(1).padLeft(6)} |'
        '${compact(max).padLeft(9)} |'
        '${toFeed > 0 ? compact(toFeed) : '-'} | '
        '${tied > 1 ? 'all-round' : winner.key.toLowerCase()}',
      );
    }
    return rows;
  }

  /// Type table, read straight off the model.
  List<String> _typeRows() {
    final rows = <String>[];
    for (final type in Planet.allTypes) {
      final m = Planet.typeMultipliers[type];
      if (m == null) continue;
      rows.add(
        '${type.padRight(11)} air ${Planet.planetAtmospheres[type]?.atmosphere.padRight(6) ?? '?'}  '
        'min ${m.minerals.toStringAsFixed(1)}  '
        'org ${m.organics.toStringAsFixed(1)}  '
        'ind ${m.industrial.toStringAsFixed(1)}  '
        'dro ${m.drones.toStringAsFixed(1)}  '
        '| colonists ${compact(Planet.colonistMaxByType[type] ?? 0)}',
      );
    }
    return rows;
  }

  /// Level cost table, read straight off the static cost list.
  List<String> _levelRows() {
    final rows = <String>[];
    for (var i = 0; i < Planet.levelUpCosts.length; i++) {
      final c = Planet.levelUpCosts[i];
      final from = Planet.levelTitles[i];
      final to = Planet.levelTitles[i + 1];
      final heading = '${(i + 1).toString().padLeft(2)}  $from -> $to';
      final needs = 'needs ${compact(c.requiredColonists)} colonists, '
          '${compact(c.requiredMinerals)} minerals, '
          '${compact(c.requiredOrganics)} organics, '
          '${compact(c.requiredIndustrial)} industrial';
      final ticks = Planet.constructionLengthFor(i + 1);
      rows.add('${heading.padRight(34)}$needs');
      rows.add('${' '.padRight(34)}build time $ticks game ticks');
    }
    return rows;
  }

  /// What each tier confers, read straight off the grant tables.
  ///
  /// Defence and armour used to be set once when a world was generated and never
  /// changed, so a level-6 Citadel defended exactly as well as a level-1 Outpost
  /// and the six tiers bought nothing but a better yield multiplier. The table is
  /// generated from [Planet.levelDefense] and friends so it cannot describe a
  /// progression the model does not have.
  ///
  /// The population column is the per-type cap *after* scaling, and it is given
  /// for a Toxic world (the tightest base in the game) as well as a multiplier,
  /// because "x5.00" tells a player nothing about whether they can actually reach
  /// the next gate. A multiplier that quietly means "you are capped" is the exact
  /// defect this column exists to make visible.
  List<String> _levelGrantRows() {
    final tightest = Planet.colonistMaxByType.values.reduce(math.min);
    final rows = <String>[];
    rows.add('  ${'TIER'.padRight(22)}'
        '${'DEFENCE'.padRight(12)}'
        '${'ARMOUR'.padRight(10)}'
        '${'SHIELD'.padRight(10)}'
        '${'DEV'.padRight(8)}'
        '${'STORE'.padRight(8)}'
        'POP CAP');
    // Iterate the **level number**, not the title index.
    //
    // Two of these tables are 0-indexed and the rest are 1-indexed, which is the
    // whole trap: `levelTitles[i]` is the title of level `i + 1`, while
    // `levelDefense[i]`, `levelArmour[i]` and friends are the stats of level `i`.
    // Looping `i` from 1 paired the *Citadel* label with level 5's numbers, showed
    // level 2 under the name "Settlement" with level 1's stats, and never printed
    // Outpost at all — six tiers of the guide quietly mislabelled.
    //
    // So: `title` comes from `levelTitles[level - 1]` and every stat map is
    // indexed by `level` directly.
    for (var level = 1; level <= Planet.levelTitles.length; level++) {
      final title = Planet.levelTitles[level - 1];
      final popScale = Planet.levelColonistScale[level] ?? 1.0;
      final capped = (tightest * popScale).round();
      // The gate to the *next* tier. `levelUpCosts` is indexed by transition, so
      // level L's gate is `levelUpCosts[L - 1]`, and the top level has none.
      final gate = level <= Planet.levelUpCosts.length
          ? Planet.levelUpCosts[level - 1].requiredColonists
          : null;
      // Flag a ceiling that cannot clear the next gate. Should be unreachable —
      // the scale table is what makes it so — but printing it means a future
      // retune that breaks the pairing shows up in the guide rather than in a
      // player's playthrough.
      final tight = gate != null && capped < gate;
      rows.add('  ${title.padRight(22)}'
          '${_defenceWord(Planet.levelDefense[level] ?? 0).padRight(12)}'
          '${compact(Planet.levelArmour[level] ?? 0).padRight(10)}'
          '${compact(Planet.levelShield[level] ?? 0).padRight(10)}'
          '${'x${(Planet.levelDevelopment[level] ?? 1.0).toStringAsFixed(2)}'.padRight(8)}'
          '${'x${_trimScale(Planet.levelStorageScale[level])}'.padRight(8)}'
          '${compact(capped)}${tight ? '  <-- CANNOT REACH NEXT TIER' : ''}');
    }
    rows.add('');
    rows.add(
        '  POP CAP is shown for a Toxic world, which has the tightest base '
        'ceiling in the game');
    rows.add(
        '  (${compact(tightest)} at level 1). Every other world type starts '
        'higher and');
    rows.add('  scales by the same factor, so none is excluded.');
    return rows;
  }

  /// Storage scale as a short string: 2.0 not 2.00, 1.5 not 1.50.
  static String _trimScale(double? v) {
    if (v == null) return '1';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  /// Defence levels are a 0-4 scale, matching ports. Name them rather than
  /// printing a bare number: "4" and "1" mean nothing to a player.
  static String _defenceWord(int level) {
    const words = ['none', 'light', 'moderate', 'heavy', 'fortified'];
    return level < words.length ? words[level] : '$level';
  }

  /// Transfer prices, matching the panel on the planet screen. Kept in step by
  /// hand with `PlanetScreen._transferPrices`; the two are documented as a pair
  /// so a price change touches both.
  /// What a transfer actually costs.
  ///
  /// It used to print a per-unit credit price for every commodity — minerals at
  /// 5 cr, colonists at 20 cr — which was wrong twice over. `_depositToPlanet`
  /// charges **no credits at all**: bulk goods move freely between the hold and
  /// the store, bounded only by free cargo space and the store's cap. (There was a
  /// credits-based transfer here once, and a `Dep`/`Wdr` button that debited
  /// credits, credited the store, and never touched `player.cargo` — so
  /// `maxCargo` was never a constraint and the same minerals had three invented
  /// values in one screen.) And colonists are not a flat price either: they are
  /// priced by distance from your faction's homeworld, which the very next
  /// paragraph of this same guide already said — so the table contradicted its
  /// own author.
  ///
  /// A hand-typed price table is the failure mode: it drifts the moment the rule
  /// moves and there is nothing to fail a test. Stated as the rule instead, so
  /// there is no second copy to disagree with.
  List<String> _transferRows() => const [
        '  Bulk goods  free. Moving them costs no credits and no energy — a',
        '              deposit is bounded by your free cargo space, a withdrawal',
        '              by the room left in your hold. A hauler is worth flying',
        '              because of that room, not because of a better rate.',
        '  Colonists    15 cr x hops^1.5, measured from your faction\u2019s homeworld,',
        '              plus the energy to fly the shipment. Batching pays: one',
        '              shipment of many colonists costs far less than the same',
        '              colonists taken in several small trips.',
      ];

  Widget _sectionCard(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String title,
    List<String> lines, {
    bool comingSoon = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (comingSoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map((line) {
              if (line.isEmpty) return const SizedBox(height: 6);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                    fontFamily: line.startsWith(' ') || line.contains('  ')
                        ? 'monospace'
                        : null,
                    fontSize: line.startsWith(' ') || line.contains('  ')
                        ? 11.5
                        : null,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
