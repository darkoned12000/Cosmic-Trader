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
    this.sourced = false,
  });

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
  ),
};
