/// Planet class data: production rules, lore, and the fighter economy.
///
/// ## The one rule
///
/// Every production figure in this game comes from a single triangle. For each
/// product a world can make, it has:
///
/// - **[PlanetClassProduct.colonistsPerUnit]** — colonists needed per unit.
/// - **[PlanetClassProduct.maxColonists]** — the most colonists that track can
///   ever hold.
/// - **[ProductSpec.optimumColonists]** — **half** of that. The optimum is
///   always half the maximum.
///
/// Output rises to a peak at the optimum and then **falls**, reaching zero at the
/// maximum:
///
/// ```
///   output/day = c <= optimum ?  c / ratio
///                            :  (max - c) / ratio
/// ```
///
/// So 50,000 colonists on a Volcanic ore track makes 50,000/day, and 55,000 makes
/// 45,000/day. Staffing past the optimum does not merely stop helping — it
/// destroys output you already had. That is the whole decision surface: the peak
/// is a thing to find, and then a thing to accidentally overshoot.
///
/// ## Fighters are not a workforce track
///
/// Drones are **derived**, not staffed. There is no drone track to assign
/// colonists to, and no drone stepper in the colony card:
///
/// ```
///   fighters/day = (ore + organics + equipment output per day) / colonistsPerDrone
/// ```
///
/// The consequence is the important part: the fighter ceiling is not a separate
/// constant that has to be kept in sync with anything. Volcanic's famous 1,002
/// fighters/day is simply (50,000 ore + 100 equipment) / 50. One rule produces
/// both the production caps and the cap on fleets, so a player cannot build an
/// invincible planet by ignoring production — and overstaffing every track past
/// its optimum drives total output, and therefore fighters, toward zero.
///
/// ## Where these numbers come from
///
/// Seven classes are taken from the TradeWars 2002 planet tables and are marked
/// `sourced`. Four of this game's ten world types have no TW equivalent — Jungle,
/// Moon, Barren and Toxic — and their figures are **derived** from the
/// multipliers already in `Planet.typeMultipliers` so they stay consistent with
/// the rest of the game. `test/planet_class_test.dart` asserts that every sourced
/// class reproduces its published fighter figure exactly, which is what keeps the
/// derived four honest: a change to a sourced number fails loudly rather than
/// quietly changing the balance.
library;

/// One product a world can be made to produce.
///
/// A product with `colonistsPerUnit == 0` **cannot be produced at all** — the
/// organics track of a Glacial or Volcanic world. That is a gap in the world's
/// capability, not a penalty applied to it: the answer is to haul organics in or
/// plant a neighbour that makes them, never to pay a tax for existing.
class ProductSpec {
  /// Colonists needed to produce one unit per day. Zero means impossible.
  final int colonistsPerUnit;

  /// The most colonists this track can hold. Zero means impossible.
  ///
  /// Not a soft cap: a colony can be given more than this, and the surplus is
  /// what makes output fall. Clamping here instead would hide the whole mechanic.
  final int maxColonists;

  /// The most of this product the world's stores can hold.
  final int storageCap;

  const ProductSpec({
    required this.colonistsPerUnit,
    required this.maxColonists,
    required this.storageCap,
  });

  /// A product this world cannot make.
  static const ProductSpec impossible =
      ProductSpec(colonistsPerUnit: 0, maxColonists: 0, storageCap: 0);

  /// Whether this world can produce this product at all.
  bool get isPossible => colonistsPerUnit > 0 && maxColonists > 0;

  /// **Half** the maximum. Always. This is the stated rule of the source tables
  /// and it holds for every product of every sourced class, so it is a computed
  /// value rather than a per-product number that could drift out of step.
  int get optimumColonists => maxColonists ~/ 2;

  /// The most of this product this world can produce in a day.
  int get maxOutputPerDay =>
      isPossible ? optimumColonists ~/ colonistsPerUnit : 0;

  /// Units of this product produced per day by [colonists] colonists.
  ///
  /// The triangle. Below the optimum it is the plain ratio; above it, every
  /// colonist past the peak costs as much output as the ones below it gained.
  int outputPerDay(int colonists) {
    if (!isPossible) return 0;
    if (colonists <= 0) return 0;
    final peak = optimumColonists;
    final effective = colonists < peak ? colonists : maxColonists - colonists;
    if (effective <= 0) return 0;
    return effective ~/ colonistsPerUnit;
  }

  /// How far past the optimum [colonists] is, as a fraction of the optimum.
  ///
  /// 0.0 at the peak, 1.0 at the maximum. Exposed so the colony card can say
  /// *why* a track is producing less than it should rather than just showing a
  /// smaller number.
  double overshootFraction(int colonists) {
    if (!isPossible || optimumColonists == 0) return 0;
    if (colonists <= optimumColonists) return 0;
    return (colonists - optimumColonists) / optimumColonists;
  }
}

/// A world type's whole production and lore identity.
class PlanetClassSpec {
  /// This game's type key, as it appears in `Planet.typeMultipliers`.
  final String key;

  /// The star-system designation, e.g. `M`.
  final String designation;

  /// Human-readable class name, e.g. `Class M - Earth Type`.
  final String className;

  /// The full description, shown in the Planet Guide.
  final String lore;

  final ProductSpec ore;
  final ProductSpec organics;
  final ProductSpec equipment;

  /// Colonists-worth of total output needed to yield one drone per day.
  ///
  /// Per class, and the reason a Volcanic world (50) tops out so much higher
  /// than a Glacial one (25) for a comparable population. Not a tuning knob that
  /// can be set independently of anything else — it is the single number that
  /// turns the production triangle into the fighter economy.
  final int colonistsPerDrone;

  /// The six citadel tiers, index 0 being level 1.
  final List<CitadelLevel> citadels;

  /// Whether these figures come from a TradeWars table rather than being chosen.
  final bool sourced;

  const PlanetClassSpec({
    required this.key,
    required this.designation,
    required this.className,
    required this.lore,
    required this.ore,
    required this.organics,
    required this.equipment,
    required this.colonistsPerDrone,
    this.citadels = const [],
    this.sourced = false,
  });

  /// The tier record for [level], or null past the top.
  CitadelLevel? citadelAt(int level) =>
      (level >= 1 && level <= citadels.length) ? citadels[level - 1] : null;

  /// What reaching [level] confers.
  String abilityAt(int level) => citadelAbilities[level] ?? '';

  /// The product spec for one of this game's track names.
  ProductSpec productFor(String track) => switch (track) {
        'minerals' => ore,
        'organics' => organics,
        'industrial' => equipment,
        _ => ProductSpec.impossible,
      };

  /// Every production track, in the order the colony card shows them.
  static const List<String> tracks = ['minerals', 'organics', 'industrial'];

  /// The most drones per day this world can produce, which is what it produces
  /// when every track sits exactly at its optimum.
  int get maxDroneOutputPerDay {
    if (colonistsPerDrone <= 0) return 0;
    return (ore.maxOutputPerDay +
            organics.maxOutputPerDay +
            equipment.maxOutputPerDay) ~/
        colonistsPerDrone;
  }

  /// Drones per day from actual per-day production totals.
  ///
  /// Takes the tracks' *achieved* output rather than their colonists, so the
  /// triangle is what drives it: overstaff one track and its contribution falls,
  /// which lowers the total and therefore the fleet.
  int droneOutputPerDay({
    required int orePerDay,
    required int organicsPerDay,
    required int equipmentPerDay,
  }) {
    if (colonistsPerDrone <= 0) return 0;
    return (orePerDay + organicsPerDay + equipmentPerDay) ~/ colonistsPerDrone;
  }
}

/// The class table, keyed by this game's type names.
const Map<String, PlanetClassSpec> planetClasses = {
  // ── Sourced from the TradeWars 2002 planet tables ─────────────────────────
  'Terran': PlanetClassSpec(
    key: 'Terran',
    designation: 'M',
    className: 'Class M - Earth Type',
    sourced: true,
    colonistsPerDrone: 10,
    lore:
        'Thick oxygen/nitrogen atmosphere. Specific gravity within 0.7 to 1.3 '
        'Earth normal. Random, but mostly manageable weather patterns, with '
        'temperatures ranging from 0 to 40 degrees Celsius. Fertile soil, '
        'excellent for organic production. Mineral deposits very good for '
        'equipment production; chemical elements good for fuel ore. Class M '
        'planets are excellent for human colonisation and promote an excellent '
        'population growth curve as well as a very good population harmony '
        'quotient. They have an above average "habitability band". Drawbacks '
        'include overpopulation problems, political unrest, and human-induced '
        'destruction of the biosphere.',
    ore: ProductSpec(
        colonistsPerUnit: 3, maxColonists: 30000, storageCap: 100000),
    organics: ProductSpec(
        colonistsPerUnit: 7, maxColonists: 30000, storageCap: 100000),
    equipment: ProductSpec(
        colonistsPerUnit: 13, maxColonists: 30000, storageCap: 100000),
    citadels: [
      CitadelLevel(
        hours: 4,
        colonists: 1000,
        ore: 300,
        organics: 200,
        equipment: 250,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 2000,
        ore: 200,
        organics: 50,
        equipment: 250,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 4000,
        ore: 500,
        organics: 250,
        equipment: 500,
      ),
      CitadelLevel(
        hours: 10,
        colonists: 6000,
        ore: 1000,
        organics: 1200,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 6000,
        ore: 300,
        organics: 400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 15,
        colonists: 6000,
        ore: 1000,
        organics: 1200,
        equipment: 2000,
      ),
    ],
  ),
  'Desert': PlanetClassSpec(
    key: 'Desert',
    designation: 'K',
    className: 'Class K - Desert Wasteland',
    sourced: true,
    colonistsPerDrone: 15,
    lore: 'Thin oxygen/nitrogen atmosphere. Specific gravity within 0.5 to 1.5 '
        'Earth normal. Weather patterns are mostly dry and hot with temperatures '
        'ranging from 40 to 140 degrees Celsius. Little area of fertile soil, '
        'very bad for organics. Very little precious metal, making it bad for '
        'equipment production. Common chemical traces make it great for fuel '
        'ore. Class K worlds are average for humanoid colonisation, but an arid '
        'and hot climate requires specialised colonists. Narrow habitability '
        'band but a generally stable political environment, as the population '
        'must depend on each other to survive. Higher fatality rate than Class M '
        'worlds.',
    ore: ProductSpec(
        colonistsPerUnit: 2, maxColonists: 40000, storageCap: 200000),
    organics: ProductSpec(
        colonistsPerUnit: 100, maxColonists: 40000, storageCap: 50000),
    equipment: ProductSpec(
        colonistsPerUnit: 500, maxColonists: 40000, storageCap: 10000),
    citadels: [
      CitadelLevel(
        hours: 6,
        colonists: 1000,
        ore: 400,
        organics: 300,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 2400,
        ore: 300,
        organics: 80,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 4400,
        ore: 600,
        organics: 400,
        equipment: 650,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 7000,
        ore: 700,
        organics: 900,
        equipment: 800,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 8000,
        ore: 300,
        organics: 400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 7000,
        ore: 700,
        organics: 900,
        equipment: 1600,
      ),
    ],
  ),
  'Ocean': PlanetClassSpec(
    key: 'Ocean',
    designation: 'O',
    className: 'Class O - Oceanic',
    sourced: true,
    colonistsPerDrone: 15,
    lore:
        'Dense oxygen/nitrogen atmosphere. Specific gravity within 1.1 to 1.8 '
        'Earth normal. Random and occasional violent weather current patterns, '
        'with temperatures ranging from 20 to 50 degrees Celsius. No land mass '
        'to speak of, making mining for ore more difficult. Organics production '
        'quite good, one of the best, but a poor environment for building '
        'equipment. Class O planets are more challenging to habituate but are '
        'almost as safe as Class M. Good population growth curve and decent '
        'population harmony. Their entire surface is habitable with proper gear, '
        'the only drawbacks being the costs to settle and build citadels.',
    ore: ProductSpec(
        colonistsPerUnit: 20, maxColonists: 200000, storageCap: 100000),
    organics: ProductSpec(
        colonistsPerUnit: 2, maxColonists: 200000, storageCap: 1000000),
    equipment: ProductSpec(
        colonistsPerUnit: 100, maxColonists: 200000, storageCap: 50000),
    citadels: [
      CitadelLevel(
        hours: 6,
        colonists: 1400,
        ore: 500,
        organics: 200,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 2400,
        ore: 200,
        organics: 50,
        equipment: 300,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 4400,
        ore: 600,
        organics: 400,
        equipment: 650,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 7000,
        ore: 700,
        organics: 900,
        equipment: 800,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 8000,
        ore: 300,
        organics: 400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 7000,
        ore: 700,
        organics: 900,
        equipment: 1600,
      ),
    ],
  ),
  'Ice': PlanetClassSpec(
    key: 'Ice',
    designation: 'C',
    className: 'Class C - Glacial',
    sourced: true,
    colonistsPerDrone: 25,
    lore:
        'Extremely thin oxygen-nitrogen atmospheres. Specific gravity from 0.5 '
        'to 1.7 Earth normal. Meteorologically unstable, causing violent '
        'conditions. Temperatures range from -10 to -190 degrees Celsius. Full '
        'life support necessary for colonies and death rates are high. No '
        'workable soil base, so hydroponic organics are limited. Modest mineral '
        'and chemical deposits, so production of ore and equipment will be below '
        'average to none. Class C planets are not recommended for colonisation: '
        'their violent conditions make it extremely hazardous. Some have been '
        'adopted by the Federation and used as prison colonies with very '
        'effective results.',
    ore: ProductSpec(
        colonistsPerUnit: 50, maxColonists: 100000, storageCap: 20000),
    organics: ProductSpec(
        colonistsPerUnit: 100, maxColonists: 100000, storageCap: 50000),
    equipment: ProductSpec(
        colonistsPerUnit: 500, maxColonists: 100000, storageCap: 10000),
    citadels: [
      CitadelLevel(
        hours: 5,
        colonists: 1000,
        ore: 400,
        organics: 300,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 2400,
        ore: 300,
        organics: 80,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 7,
        colonists: 4400,
        ore: 600,
        organics: 400,
        equipment: 650,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 6600,
        ore: 700,
        organics: 900,
        equipment: 700,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 9000,
        ore: 300,
        organics: 400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 6600,
        ore: 700,
        organics: 900,
        equipment: 1400,
      ),
    ],
  ),
  'Lava': PlanetClassSpec(
    key: 'Lava',
    designation: 'H',
    className: 'Class H - Volcanic',
    sourced: true,
    colonistsPerDrone: 50,
    lore:
        'Extremely thin oxygen/nitrogen atmospheres. Specific gravities within '
        '0.8 to 2.6 Earth normal. Climate patterns are violent with temperatures '
        'from 45 to 400 degrees Celsius. Full life support required for '
        'colonisation. Zero workable soil, and harsh conditions make organics '
        'production impossible. Good trace elements for equipment, but conditions '
        'make production a gamble at best. Excellent ore production possibilities '
        'as material is often ejected by volcanic activity and found on the '
        'surface. Very dangerous for colony growth, as unstable planetary crusts '
        'often lead to the complete loss of a colony. The Federation has been '
        'known to use Class H planets for the defence of key sectors due to their '
        'large ore base.',
    ore: ProductSpec(
        colonistsPerUnit: 1, maxColonists: 100000, storageCap: 1000000),
    organics: ProductSpec.impossible,
    equipment: ProductSpec(
        colonistsPerUnit: 500, maxColonists: 100000, storageCap: 100000),
    citadels: [
      CitadelLevel(
        hours: 4,
        colonists: 800,
        ore: 500,
        organics: 300,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 1600,
        ore: 300,
        organics: 100,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 4400,
        ore: 1200,
        organics: 400,
        equipment: 1500,
      ),
      CitadelLevel(
        hours: 12,
        colonists: 7000,
        ore: 2000,
        organics: 2000,
        equipment: 2500,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 10000,
        ore: 3000,
        organics: 1200,
        equipment: 2000,
      ),
      CitadelLevel(
        hours: 18,
        colonists: 7000,
        ore: 2000,
        organics: 2000,
        equipment: 5000,
      ),
    ],
  ),
  'Gas Giant': PlanetClassSpec(
    key: 'Gas Giant',
    designation: 'U',
    className: 'Class U - Vaporous / Gaseous',
    sourced: true,
    colonistsPerDrone: 1,
    lore: 'Very heavy to very thin atmospheres consisting of various elements, '
        'mostly helium or hydrogen. Specific gravities can range from 0.2 to 8.0 '
        'Earth normal. Climate patterns are usually extremely violent, with '
        'temperatures from -200 to 400 Celsius. Full life support required at all '
        'times. No production can sustain itself on a Class U planet. Some miners '
        'have hinted at very valuable products extracted from Class U worlds, but '
        'the Federation does not have them in its "Official Guide to Mining". '
        'Class U planets are not recommended for colonisation, as the environment '
        'is harsher than being in space itself.',
    // No production at all. The caps are still stated, because the source table
    // states them and because a cap of zero with a non-zero storage limit is what
    // makes the world legible rather than merely broken.
    ore:
        ProductSpec(colonistsPerUnit: 0, maxColonists: 3000, storageCap: 10000),
    organics:
        ProductSpec(colonistsPerUnit: 0, maxColonists: 3000, storageCap: 10000),
    equipment:
        ProductSpec(colonistsPerUnit: 0, maxColonists: 3000, storageCap: 10000),
    citadels: [
      CitadelLevel(
        hours: 8,
        colonists: 3000,
        ore: 1200,
        organics: 400,
        equipment: 2500,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 3000,
        ore: 300,
        organics: 100,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 8000,
        ore: 500,
        organics: 500,
        equipment: 2000,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 6000,
        ore: 500,
        organics: 200,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 8000,
        ore: 200,
        organics: 200,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 6000,
        ore: 500,
        organics: 200,
        equipment: 1200,
      ),
    ],
  ),

  // ── Derived: no TradeWars equivalent ──────────────────────────────────────
  // Chosen to sit consistently with `Planet.typeMultipliers` for these four, so
  // a world reads the same way in the colony card as it does in the guide. Their
  // fighter ceilings land between Glacial's 64 and Ocean's 3,733, which is the
  // band the multipliers imply.
  'Jungle': PlanetClassSpec(
    key: 'Jungle',
    designation: 'M/J',
    className: 'Class M/J - Jungle',
    colonistsPerDrone: 12,
    lore:
        'A wet, overgrown world of closed canopy and standing water. Deep soil '
        'and near-constant moisture make it the best organics world outside an '
        'ocean type, and its mineral wealth is unremarkable. Clearing it for '
        'industry is slow work, and the biosphere fights back.',
    ore: ProductSpec(
        colonistsPerUnit: 6, maxColonists: 60000, storageCap: 200000),
    organics: ProductSpec(
        colonistsPerUnit: 4, maxColonists: 60000, storageCap: 400000),
    equipment: ProductSpec(
        colonistsPerUnit: 30, maxColonists: 60000, storageCap: 60000),
    citadels: [
      CitadelLevel(
        hours: 3,
        colonists: 1000,
        ore: 300,
        organics: 300,
        equipment: 250,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 1600,
        ore: 250,
        organics: 120,
        equipment: 250,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 3200,
        ore: 600,
        organics: 400,
        equipment: 500,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 5000,
        ore: 900,
        organics: 1400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 6000,
        ore: 350,
        organics: 500,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 12,
        colonists: 5000,
        ore: 900,
        organics: 1200,
        equipment: 1800,
      ),
    ],
  ),
  'Moon': PlanetClassSpec(
    key: 'Moon',
    designation: 'L/M',
    className: 'Class L/M - Moon',
    colonistsPerDrone: 20,
    lore:
        'A small airless body, all rock and regolith and no atmosphere to speak '
        'of. Ore is plentiful on the surface where it has been left exposed by '
        'millions of years of impacts, and there is workable soil nowhere. A '
        'colony here lives entirely inside its own life support.',
    ore: ProductSpec(
        colonistsPerUnit: 10, maxColonists: 40000, storageCap: 150000),
    organics: ProductSpec.impossible,
    equipment: ProductSpec(
        colonistsPerUnit: 60, maxColonists: 40000, storageCap: 40000),
    citadels: [
      CitadelLevel(
        hours: 4,
        colonists: 600,
        ore: 400,
        organics: 250,
        equipment: 500,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 1600,
        ore: 250,
        organics: 60,
        equipment: 350,
      ),
      CitadelLevel(
        hours: 6,
        colonists: 3200,
        ore: 550,
        organics: 300,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 5200,
        ore: 650,
        organics: 700,
        equipment: 750,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 6400,
        ore: 300,
        organics: 300,
        equipment: 900,
      ),
      CitadelLevel(
        hours: 8,
        colonists: 5200,
        ore: 650,
        organics: 700,
        equipment: 1200,
      ),
    ],
  ),
  'Barren': PlanetClassSpec(
    key: 'Barren',
    designation: 'K/B',
    className: 'Class K/B - Barren',
    colonistsPerDrone: 18,
    lore:
        'Stripped of everything but rock. What was here is gone — atmosphere, '
        'water, and any soil worth the name — and what remains is an exposed '
        'mineral wealth that other worlds would envy. It is a refinery world, '
        'not a home.',
    ore: ProductSpec(
        colonistsPerUnit: 3, maxColonists: 40000, storageCap: 400000),
    organics: ProductSpec.impossible,
    equipment: ProductSpec(
        colonistsPerUnit: 100, maxColonists: 40000, storageCap: 30000),
    citadels: [
      CitadelLevel(
        hours: 5,
        colonists: 800,
        ore: 500,
        organics: 250,
        equipment: 500,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 1800,
        ore: 300,
        organics: 50,
        equipment: 350,
      ),
      CitadelLevel(
        hours: 7,
        colonists: 3600,
        ore: 650,
        organics: 350,
        equipment: 600,
      ),
      CitadelLevel(
        hours: 6,
        colonists: 5600,
        ore: 800,
        organics: 700,
        equipment: 800,
      ),
      CitadelLevel(
        hours: 4,
        colonists: 7000,
        ore: 300,
        organics: 300,
        equipment: 900,
      ),
      CitadelLevel(
        hours: 9,
        colonists: 5600,
        ore: 800,
        organics: 700,
        equipment: 1300,
      ),
    ],
  ),
  'Toxic': PlanetClassSpec(
    key: 'Toxic',
    designation: 'H/T',
    className: 'Class H/T - Toxic',
    colonistsPerDrone: 15,
    lore: 'A thick corrosive atmosphere and a surface that eats unprotected '
        'equipment in weeks. What it offers in exchange is ore and heavy industry '
        'in quantities that survive the corrosion — nobody stays, which is exactly '
        'why so much of it is worked. Sealed colony domes are mandatory.',
    ore: ProductSpec(
        colonistsPerUnit: 2, maxColonists: 50000, storageCap: 500000),
    organics: ProductSpec.impossible,
    equipment: ProductSpec(
        colonistsPerUnit: 30, maxColonists: 50000, storageCap: 80000),
    citadels: [
      CitadelLevel(
        hours: 6,
        colonists: 1000,
        ore: 450,
        organics: 250,
        equipment: 500,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 2200,
        ore: 280,
        organics: 60,
        equipment: 400,
      ),
      CitadelLevel(
        hours: 7,
        colonists: 4200,
        ore: 700,
        organics: 400,
        equipment: 700,
      ),
      CitadelLevel(
        hours: 6,
        colonists: 6400,
        ore: 900,
        organics: 800,
        equipment: 900,
      ),
      CitadelLevel(
        hours: 5,
        colonists: 7600,
        ore: 350,
        organics: 400,
        equipment: 1000,
      ),
      CitadelLevel(
        hours: 10,
        colonists: 6400,
        ore: 900,
        organics: 800,
        equipment: 1500,
      ),
    ],
  ),
};

/// The game clock.
///
/// One unit of game time is one **tick**, and a tick is the 30-second game loop.
/// So a game day is 2,880 ticks and a game hour is 120. Nothing in the economy
/// invents its own notion of a day: a per-day figure from the source tables is
/// divided by [ticksPerDay] to get a per-tick figure, and that is the whole
/// conversion.
///
/// This is deliberately *not* a compressed clock. An earlier draft proposed
/// shortening the day so that build times felt brisk; it was wrong, and the
/// error was instructive — a compressed day would have desynchronised the planet
/// economy from the port market, which already refills on a real 24 hours. With
/// a game day being a real day, the two agree by construction and there is
/// nothing to keep in step.
///
/// The switch to real time for a persistent multiplayer game is a change to this
/// class alone, because everything that needs to know how long a day is reads it
/// from here.
class PlanetClock {
  PlanetClock._();

  /// Ticks in one game hour.
  static const int ticksPerHour = 120;

  /// Ticks in one game day.
  static const int ticksPerDay = ticksPerHour * 24;

  /// Converts a per-day figure into a per-tick one.
  ///
  /// Doubles, deliberately. A Volcanic ore track peaks at 50,000/day, which is
  /// 17.361 per tick — and the colony's stores accumulate in whole units, so
  /// truncating each tick would lose a fraction of everything produced. The
  /// remainder is carried rather than dropped.
  static double perDayToPerTick(double perDay) => perDay / ticksPerDay;
}

/// One citadel tier: what it costs, how long it takes, and what it grants.
///
/// **[hours] is the source table's "Days" column read as hours.** The TradeWars
/// tables express build time in days, and 4 to 18 real days of play is not a
/// build — it is a season, and construction only advances while the game is
/// running, so level 2 would be a week of evenings. Reading the same numbers as
/// hours preserves the shape of the authored table exactly (a Mountain level 2 is
/// still four times faster than a Vaporous one) while making the thing
/// reachable. See *Revised order of work* in `planets.md`.
///
/// The colonist figure is a **gate, not a cost**. It is a minimum population the
/// world must hold to begin, not a quantity spent — the same distinction the
/// rest of the model draws between a gate and a price.
class CitadelLevel {
  /// Build time in game hours.
  final int hours;

  /// Cumulative colonist gate for reaching this tier.
  final int colonists;

  /// Fuel ore consumed when the build starts.
  final int ore;

  /// Organics consumed when the build starts.
  final int organics;

  /// Equipment consumed when the build starts.
  final int equipment;

  const CitadelLevel({
    required this.hours,
    required this.colonists,
    required this.ore,
    required this.organics,
    required this.equipment,
  });

  /// Build time in ticks, at a construction time scale of 1.
  ///
  /// Kept next to [hours] so the two cannot drift: every consumer that wants a
  /// duration rather than a figure wants this one, and a build stored in hours
  /// with a countdown in ticks is a conversion somebody has to remember.
  int get ticks => hours * PlanetClock.ticksPerHour;
}

/// What each citadel tier confers.
///
/// Index is the level number, and the wording follows the source tables. Level 1
/// is in the list deliberately: a world with a citadel and no defences is a real
/// state that a player can walk into, and the rule it breaks is that a planet
/// with no citadel has no defensive capability at all.
const Map<int, String> citadelAbilities = {
  1: 'Citadel — defenseless. You can use the treasury, remain overnight, the '
      'planet transporter and other citadel commands, but fighters left on '
      'the planet will not defend and can be taken by anyone who lands.',
  2: 'Combat computer — fighters on the planet now defend. Usually you want '
      'your military reaction at 0%, since the fighters get 3:1; this can be '
      'set to send fighters from the planet at 2:1 against anything entering '
      'the sector.',
  3: 'Quasar cannon — can be set to fire at anything entering the sector, '
      'anything trying to land, or both. Firing burns fuel ore; atmospheric '
      'shots are 1 ore to 1 damage, sector shots 3 ore to 1. A quasar can be '
      'bypassed by a photon missile unless a planetary shielding system '
      'covers it.',
  4: 'Planetary transwarp drive — move this world to any sector where you '
      'have dropped a fighter, for 400 units of ore per sector jumped.',
  5: 'Planetary shielding system — planetary shields must be destroyed before '
      'anyone can invade, each taking 20 damage. Shields the world and anyone '
      'on it from a photon blast. Ten ship shields make one planetary shield.',
  6: 'Planetary interdictor generator — when on, makes it difficult for an '
      'enemy to retreat from the sector. Similar to a tractor beam.',
};

/// Where the class numbers actually come from.
///
/// `planetClasses` above is the shipped **default** table, and it is `const` so it
/// cannot be edited by accident. This is the mutable layer on top: the planet
/// screen and the Settings editor resolve through [specFor], which merges any
/// saved override over the default.
///
/// The split is the whole point. A player editing a ratio, a cap or a build time
/// changes **values**, and the rules that use them — the triangle, the optimum
/// being half the maximum, fighters derived from output — cannot be edited at
/// all, so a customised world cannot end up violating the relationship the Planet
/// Guide documents. `optimumColonists` is derived, never a field, precisely so
/// that it stays half the maximum whatever a player does to the number beside it.
///
/// Currently empty; `GameSettings` populates it. Kept as a separate class rather
/// than folded into the defaults map so that the const table stays const.
class PlanetClassTuning {
  PlanetClassTuning._();

  /// Overrides, keyed by world type. A null entry means "use the default".
  static final Map<String, PlanetClassSpec> _overrides = {};

  /// Replaces every override, keeping only those naming a world type the game
  /// actually has.
  ///
  /// Filtered on the way in rather than the way out, so a save from an older or
  /// hand-edited settings file cannot inject a spec for a world type that does
  /// not exist and quietly shadow the default table.
  static void loadAll(
    Map<String, PlanetClassSpec> overrides,
    List<String> validTypes,
  ) {
    _overrides
      ..clear()
      ..addAll({
        for (final e in overrides.entries)
          if (validTypes.contains(e.key)) e.key: e.value,
      });
  }

  /// Drops every override, restoring the shipped table.
  static void reset() => _overrides.clear();

  /// Whether any override is in force. The settings screen shows a "modified"
  /// marker from this.
  static bool get isCustomised => _overrides.isNotEmpty;

  /// The effective class for [type]: the override if there is one, else the
  /// shipped default.
  ///
  /// Falls back to a neutral spec rather than throwing for an unknown type, so a
  /// world generated from a stale universe produces nothing rather than crashing
  /// the tick. `test/planet_class_test.dart` asserts every real type resolves.
  static PlanetClassSpec specFor(String type) =>
      _overrides[type] ?? planetClasses[type] ?? _unknownSpec;

  /// Stand-in for a world type with no entry. Produces nothing at all, which is
  /// the honest answer for "we have no rules for this" and matches the Class U
  /// case: a world nobody can plan for should not silently produce at the
  /// default.
  static final PlanetClassSpec _unknownSpec = PlanetClassSpec(
    key: 'Unknown',
    designation: '?',
    className: 'Unclassified',
    lore: 'No production data is available for this world.',
    ore: ProductSpec.impossible,
    organics: ProductSpec.impossible,
    equipment: ProductSpec.impossible,
    colonistsPerDrone: 1,
  );

  /// The shipped defaults, for the settings screen to show as a starting point.
  static Map<String, PlanetClassSpec> defaults() => Map.of(planetClasses);
}
