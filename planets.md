# Planets — Design & Implementation Plan

## Current State (audited 2026-09-29 against `main` + planet work)

This section was substantially out of date in both directions: it listed work that
ships as missing, and its balance tables disagreed with the code by an order of
magnitude. Corrected below, with the audit that produced it in the next section.

### What is built and working

- **Model** (`lib/data/models/planet.dart`): 10 planet types with atmosphere,
  production multipliers, colonist caps, and image pools. Ownership, homeworld
  status, colonists per track, storage, Citadel level 1-6, defense
  (level/shield/hull), NPC spawn timers, and a `scanned` flag.
- **Generator** (`universe_generator.dart:1280`): planets placed at `planetDensity`
  with a random image, random `productionEfficiency` (0.5-1.5), random defense
  level (0-2), and small starting stores. `scanned: false`.
- **Homeworlds** (`universe_generator.dart:1219`): one primary per major faction
  plus a labelled cold-standby backup, at level 4 / defense 4, with starting
  colonists, stores, and a 10-tick spawn interval.
- **Repopulation + ship production** (`lib/services/repopulation_service.dart`):
  **done, and ahead of this document.** Floor-based recovery (below 3 ships for
  majors, 2 for pirates), steady-state production caps (8/8/8, pirates 4),
  control-gated yards (a captured homeworld freezes production; recapture
  restores it), backup homeworlds that idle while a live primary exists,
  destroyed-world exclusion, and rare hero ships (5%, roster-unique, minted with
  a Guild bounty on first kill).
- **Scanning**: two paths, both charging energy and persisting to the sector
  file. Planet tab costs 4 energy and grants +1 standing with the owner
  (`planet_screen.dart:58`); the sector panel costs 1 energy and grants nothing
  (`sector_interaction_panel.dart:203`).
- **UI**: planet tab, header + image, resources/defense cards, production
  readout, credits-based transfers in both directions, claim, and level-up.
- **Maps**: planet markers on the galaxy map and tactical map, with
  type/homeworld/owner status; a land/scan action in the sector panel.

### Shipped since the first audit

- **Per-tick colony production** — `Planet.produce()` applies the yield the
  screen displays, clamped to storage, driven by
  `PlanetProductionService.process` once per tick. The formula now lives on the
  model in one place; the screen and the tick both read it, so they cannot
  disagree.
- **Organics upkeep** — `ceil(population / 10)` per tick, charged *after*
  production so a colony that farms its own food stands still.
- **Starvation** — a colony that cannot feed itself bleeds at 2% of population
  per tick, with a floor of one colonist so it always finishes dying.
- **Workforce assignment UI** — steppers on all four tracks plus an implicit
  reserve, owner-only. This was a hard prerequisite: without it a claimed planet
  has no colonists on any track and produces nothing, because only the generator
  ever set the track counts.
- **A development multiplier by level** (1.00-2.00x), deliberately shallow.
- **Per-commodity, per-type storage with nothing wasted** — see the Storage
  section. A full store spills into a shipment pool rather than being discarded.
- **A live planet screen** — a 1s fingerprint poll repaints the colony when the
  tick changes it, so production is visible without leaving the tab.
- **Distance-priced, per-faction colonist supply** — see Colonists & Production.
- **A Planet Guide** at Computer -> Planet Guide, with its storage, type, level
  and transport tables generated from the model so a balance change cannot leave
  the reference stale.

### What is NOT working

- **Levelling grants, the level-scaled cap, and the build timer all landed** —
  see *Citadel levels* and Code Audit #1/#2. This entry was stale.
- **Invasion combat**: not started. The Attack button writes a log line. (The
  Atomic Detonator, below, is now a *second* path to `destroy()` and lands long
  before invasion.)
- **Colonists as physical cargo**: not started. They are priced and fuelled like
  a shipment but are still an abstract count with no cargo-hold constraint. This
  is now step 3 of the Economy Redesign and is no longer deferred.
- **Scanner-module auto-scan**: the module exists in `hardware_data.dart` and is
  unwired.
- **Colonies feeding ports directly**: not started. A shipment is still cashed
  in by hand at whatever the port pays. See *The resource market* below — the
  `Wdr` button and the `Collect` pool currently pay **two different invented
  prices for the same goods** (5 cr vs 42.5 cr per mineral), which is the defect
  that makes a real market necessary rather than merely nice.
- **One planet per sector**: `Sector.planet` is `Planet?`, strictly 1:1. Multiple
  planets per sector is the top-priority change; see *Multiple planets per
  sector*.
- **NPC colonisation / backup claiming by AI**: not started (the control-gating
  rules it would need already exist).

---

## Economy Redesign (2026-09-29) — decisions

This section records a design conversation that reshaped the planet system. It is
written here **before** the code, deliberately: every number below is measured, and
where a decision is still open it says so rather than picking a side silently.

The through-line is that the planet screen was **locally correct and globally
incoherent**. Production, storage, levels and upkeep each worked; they described an
economy that could not exist, because a colony could out-produce every port in the
galaxy in a single day and there was no way to move a single resource from one
world to another.

**Top priority: multiple planets per sector.** `Sector.planet` is `Planet?` — one
world per sector — and that single field is the blocker for the entire design
below. Eight files read it, and with three worlds per sector a per-planet stable id
becomes mandatory because `(sectorId)` stops being an identity.

**Four decisions are still open** and are marked `OPEN` in place: whether a
Genesis Torpedo offers type *profiles* or pure random, what the exchange spread
should be, whether drone maintenance is worth building, and whether ports should
grow on their own. None of them block the top-priority refactor.

### The measurements that drove everything

All taken against a default generated universe (`seed 7`, 24 ports).

| Measurement | Value |
|---|---|
| Total treasury, every port in the galaxy | 455,372,804 cr |
| Daily output of **one** 1M-population Citadel | **4,658,305,000 cr** |
| One colony-day as a multiple of the whole galaxy's treasury | **10.2x** |
| Galaxy-wide daily mineral demand (the absorption budget) | 462,749 units |
| Daily mineral output of a **50,000** level-4 colony | **780,000 units** |
| Daily mineral output of a 1M level-6 colony | **27,600,000 units** (60x) |
| Everything purchasable in the game (270 hardware items + 12 hulls + port storage ladder) | **65.0B cr** |
| Citadel-days to buy the entire game | **72** |

Three conclusions, and they drove everything after:

1. **There is no sink for a colony's output.** Even a modest mid-game colony
   produces more minerals than the entire galaxy can absorb in a day.
2. **Credits inflate hard.** One colony finances the whole game in under three
   months of play. The sinks are all finite and all saturate; the faucet is
   neither.
3. **This is partly self-inflicted.** Deriving the population cap from the Citadel
   level (necessary, to fix the cap/gate contradiction) raised the achievable
   ceiling by up to **12x** on exactly the types that had been dead ends. The
   sinks were never re-sized against it. Recorded because the same mistake is
   available again: **widening the output range obliges you to re-check the sink.**

### A second, quieter defect: the port treasury ratchets

`portCredits` is debited by every player sale (`port_trade_view.dart`, clamped at
0), but `Port.regen()` restores **only supply and demand, never credits**
(`port.dart:359-380`). The only inflow is an NPC happening to buy there.

The self-correcting valve exists — `cashRatio` drives `priceMultiplier` across
0.55x-2.0x — but it depends on a reservoir that cannot refill. A port that sells
into a colony ratchets toward zero and pins at the 0.55x floor permanently.

### A third: the Transfers buttons are not transfers

`_transferToPlanet` debits credits and energy, then does
`planet.storedMinerals += amount` and **never touches `player.cargo`**. Depositing
a million minerals costs nothing in cargo space against a hold that fits fifty.
`_transferFromPlanet` decrements the store, credits the player, also never touches
cargo, and does not charge energy at all.

Worse, there were **three prices for the same goods**: the `Wdr` button paid
5/8/12 cr, the `Collect` shipment pool paid 42.5/115/230, and a real port paid a
live demand-driven price. The first two are both invented. The `port_trade_view`
already moves units into `player.cargo` and respects `maxCargo` correctly, so the
infrastructure existed and the planet screen simply was not using it.

**DONE.** `Dep`/`Wdr` are now `Unload`/`Load` and genuinely move units: unload
takes goods out of `player.cargo` into the store, load takes them out of the store
into the hold, both free, both hard-bounded. `maxCargo` is now a constraint
rather than a stat line — before, a million minerals went into a hold that fits
fifty. `_transferPrices` is **deleted, not retuned**: it priced goods that no
longer change hands, and it gave the same minerals three values in one screen
(5 cr on that row, 42.5 cr on Collect, a live price at a port).

A resource market is a **third, separate verb** — buy at a port into cargo, fly,
unload. Drones have no market row and no cash value, but they *can* be loaded so
they can be fielded (below).

Two details worth recording:

- The buttons are gated on "is this possible **at all**", not on the current
  stepper amount. Gating on the amount made them lie: with 5 free hold slots and
  a stepper reading 10, a player with 1,000 minerals on a nearby world and a
  nearly-empty hold saw a dead button and no way to make the one load that would
  have fitted. The handlers clamp to `min(stored, space)`.
- The trailing cell that used to read a price now reads `hold N`. A per-unit
  credit rate on a haul that costs nothing is an invented number, and the hold
  count is what actually bounds a deposit.

**Why step 3 shipped before step 2, reversing the documented order.** The original
argument was that hauling is "pointless before step 2 — with no gap to fill there
is nothing to haul". That was reasoning about *necessity* and it ignored
*blocking*. Step 2 gives the harsh types zero organics, and a harsh world cannot
level without organics in its store — so doing step 2 first would make 5 of the 10
world types **permanently unable to reach level 2** until step 3 landed, and the
player is actively playing. Hauling first means step 2 is safe to land.

`test/planet_cargo_transfer_test.dart` (8 tests) guards it, including the two
assertions that could not have existed before: the hold is a hard bound, and a
deposit needs room on the world.

### DECISION — harsh types cannot produce a commodity at all

The design this replaces was a **three-way per-capita upkeep** (minerals, organics,
industrial at 20/12/25 per 100 colonists). Its algebra was attractive: the
workforce fraction needed to feed a colony is `1 / (divisor x typeMultiplier)`,
which **cancels population, development and efficiency out entirely** — so the
"needs never outpace production" requirement held by construction, for all ten
types, worst case 50.8% of the workforce (Barren).

**Rejected anyway.** Measured against a naive 40/30/20/10 split, that design made
Lava and Barren consume **138.9% of their own organics output** — they could not
feed themselves at all, and needed 41.7% of their workforce on their *weakest*
track. It turned harsh worlds into *worse Terran worlds*: the identity came from a
penalty.

**A gap is not a tax.** A harsh type instead produces **zero** organics. It is not
punished for existing; it is structurally incapable of feeding itself, which makes
importing or planting a complement a genuine decision. And critically, a gap
creates *permanent market demand* for the player who holds it, while a tax merely
reduces volume.

| Type | Minerals | Organics | Industrial | Drones |
|---|---|---|---|---|
| Lava | 2.0 | **0** | 1.4 | 1.4 |
| Barren | 1.2 | **0** | 0.8 | 1.0 |
| Toxic | 1.6 | **0** | 1.0 | 1.2 |
| Ice | 0.8 | **0** | 0.6 | 0.8 |
| Moon | 1.0 | **0** | 0.6 | 0.8 |

Verified safe: every output is `colonists x mult x scale` and **nothing in the
model divides by a type multiplier**, so a 0 multiplier yields 0 output rather than
exploding.

**Upkeep and starvation are both removed**, and **colony supply** replaces them.
`organicsUpkeep`, `organicsShortfall`, `colonistsLost` and `isStarving` are gone
from `planet.dart`, `planet_production_service.dart`, `planet_screen.dart`, the
Planet Guide, and three test files.

#### Colony supply — DONE

Every `Planet.supplyInterval` (10) ticks a colony is billed for the goods its
people need: `supplyShareOfOutput` (8%) of **one tick's own output**, drawn at
random from minerals, organics or industrial.

Three deliberate properties:

- **A share of its own output, not a per-capita rate.** A fixed per-colonist
  figure is trivial for a world of a hundred and ruinous for a world of two
  million. This is the third time this model has met that trap (storage floor,
  level-scaled colonist cap) and the third time the answer was to derive it.
  Measured across 100 / 10,000 / 1,000,000 populations, the share holds at 8%.
- **The commodity is drawn at random and paid from whatever the colony has.** A
  world short of the drawn one falls back through `supplyCommodities`, so the
  bill can never be made unsatisfiable by a type's multiplier alone. This is what
  lets a harsh world exist at all: it is not punished when the draw lands on
  organics, it just pays in minerals.
- **Goods already produced and waiting in the shipment pool count.** A busy
  colony is never told it cannot feed itself while its own output sits
  uncollected.

Drones are excluded — combat units, not a consumable, and a colony that ate its
own drone force would be nonsense.

**There is no starvation and no population loss.** An unpaid bill is *reported*
and nothing else happens: the colony card reads "Stores empty — supply unpaid",
and on a world that cannot make organics it names the actual fix (unload organics,
or plant a world beside it that grows them). The starvation tests are **deleted
rather than inverted** — a colony that cannot starve cannot regress, so a test
forbidding the mechanic's return would outlive its reason. What is asserted
instead is that an empty colony loses nobody over 500 ticks.
`test/planet_supply_test.dart` (16 tests) covers the rest.

**The workforce locks itself on a dead track.** A harsh world's organics stepper
is disabled and the rate column reads "cannot produce". A stepper that accepts
colonists onto a track yielding nothing looks like a bug, and a player who cannot
see why their organics stay at zero will assume the mechanic is broken. Remove
stays enabled even there, so a colony generated before its world became incapable
is not stuck holding colonists who will never work again.

**Test trap worth recording.** The first supply guards used a *staffed* colony with
an empty store. It refills itself long before the bill comes due, so the "unpaid
bill" tests passed while proving nothing. They now use `idleColony()` — no
workforce at all — which is the only way to actually observe an unpaid bill.

**Honest limit of this decision.** The import demand it creates is *trivial in
volume*. A full 1 -> 6 needs **65,250 organics, total, ever**, against roughly
**17M organics per day** from a 1M Terran Citadel — about 0.4% of one day's
output. This design buys real **identity and strategic dependency**; it does not
put meaningful pressure on the market, and it should not be claimed to. What
escapes a self-sufficient empire is **surplus in whatever it is best at**, and
surplus is unbounded while deficit is bounded. That is what sizes the exchange.

### DECISION — multiple planets per sector (the top priority)

`Sector.planet` is `Planet?` — strictly 1:1, and eight files read it. **3 planets
per sector is now the primary change**, because the complementarity loop is only
pleasant when the worlds are adjacent: hauling 5,000 organics from sector 12 to
sector 40 is a chore you route around, and hauling them to the next world **in your
own sector** is trivial. Multi-planet sectors are not nostalgia for the classic
game; they are the difference between hauling being a core verb and a nuisance.

**STATUS: DONE** (2026-09-29). `Sector.planets` is a `List<Planet>`, `Planet` has
a stable `id`, `hasPlanet` is a derived getter, and a legacy single-`planet` save
migrates into a one-element list. `GameSettings.planetsPerSector` defaults to 3.
Guarded by `test/multi_planet_sector_test.dart` (17 tests).

Three things the refactor turned up that the design above did not anticipate:

- **`planetDensity` was raised 0.25 -> 0.5.** Measured over 50 sectors, the old
  density gave 41 empty / 5 single / 1 double / 3 triple — only **8%** of the
  galaxy held more than one world, so the complementarity loop, the hauler and
  the torpedo all had almost nowhere to exist. At 0.5 it measures 22/12/9/7: a
  third of sectors hold multiple worlds, 44% are still empty.
- **A capital is not always slot 0.** Every service that looked for a homeworld
  was reading `sector.planet`, which would have silently picked a random
  frontier world while the real capital sat in slot 2. `Sector.homeworld` and
  `RepopulationService.homeworldSectors` now search every world. The
  colonist-supply and yard tests were rewritten to place a capital in slot 2
  **on purpose**, because "one homeworld per sector" is no longer an invariant
  and neither is "the first world is the interesting one".
- **Filling a sector draws more from the shared `Random`,** which shifts every
  downstream roll. That exposed a latent bug: NPC placement is a per-sector coin
  flip, and an 8-sector universe could generate **zero ships for all four
  factions**. A galaxy with no ships in it is broken regardless of size, so
  generation now guarantees one ship per faction with a nonzero density —
  the same minimum guarantee already made for ports and port trade characters.
  Densities still decide how *numerous* a faction is; they no longer get to
  decide whether one exists.

This also **vindicates a declined review item**. The Third-Party Review section
declined a stable `planetId` on the grounds that a planet's identity is
`(sectorId)` because `Sector.planet` is 1:1, and noted:

> This becomes a real requirement in exactly one case: if a sector ever holds more
> than one planet (a Genesis Torpedo creating a moon beside a world, for
> instance), at which point 1:1 breaks and a per-planet id is needed.

That case is now the plan. **A per-planet id becomes mandatory**, because with
three worlds in a sector, `(sectorId)` is no longer an identity.

- `Sector.planets: List<Planet>`, each with its own stable id, name, and type.
- `hasPlanet` becomes `planets.isNotEmpty`.
- **Planets per sector is a universe-generation setting**, fixed at creation and
  not changeable afterwards, so every sector in a given universe obeys the same
  physics. Default 3.
- Save migration: an existing `planet` field loads into a one-element list.

### DECISION — over-stacking is allowed, and is dangerous

Exceeding the cap does **not** hard-block, because players used exactly this as an
attack. Creating a 4th world in a 3-planet sector raises a **gravity warning** and
then a **collision roll every 24 hours**: if it comes up bad, planets collide and
are destroyed.

This is the strongest form the mechanic takes. It converts a construction choice
into an ongoing liability, and it gives a player or NPC a way to **attack a
sector's economy rather than its hulls** — plant a destabilising world in a
target's 3-planet system and let the dice decide. It is also the second path to
`Planet.destroy()`, which is currently reachable only from code and tests.

The warning must be explicit and unmissable, and the roll must be visible: a silent
destruction of a 1M-citadel colony would read as a bug, not as a risk the player
accepted.

### DONE — colony controls read at a glance

**The level gate colours the requirement, not the total.** Each row prints
`have / need`, and only the **need** is coloured — red when unmet, green when met.
The first number is what the world actually has and stays in the normal text
colour, because colouring it too would colour every cell in the card and say
nothing the figures do not. This went through two earlier versions: a trailing
`✓` that appeared only on success (so the two states were told apart by the
*absence* of a character), and then a tick-or-cross icon column, which was
unambiguous but added a fourth column to every row for a binary the numbers
already carry.

**A colony track row had two `−` buttons, and asking what they did was a fair
question.** One sat either side of the count, and both pulled colonists off the
track — but the leading one was enabled only when the track held a full step, so
on any colony smaller than a step it rendered greyed out and read as a dead
control while the other worked. The duplicate is gone. What remains is a `+`/`−`
pair that moves colonists **between the reserve and the track**, which a bare pair
of glyphs on a row of numbers does not communicate, so each button now names its
source or destination in a tooltip and the card says it in prose.

### DONE — Genesis Torpedo and Atomic Detonator

Sold at **hardware emporiums only**, which is true by construction: the emporium
widget is only reachable from a port with `isHardwareEmporium`, so there is no gate
in the new tab to forget.

**Both are equipment, not cargo, and take no hold space.** The first design made them
cargo-bounded at one slot each, which looked like a tidy way to stop stockpiling
and was wrong: it conflated the two systems the game otherwise keeps apart. A hold
full of ore would have been a reason to be short of torpedoes, and the player would
have had to dump cargo they needed in order to make the purchase worth making. The
Ship screen now states the split directly — **Cargo** is the resource types and
shares one hold against a shared capacity, **Equipment** is the ordnance and takes
no hold space at all. `WorldForging.cargoPerUnit` is `0`, so the accounting is not
merely correct but *impossible* to get wrong.

Both can be **returned for half price**. Without that, money spent on a roll that
went badly is money the player can never get back, which turns a bad launch into a
dead end rather than a lesson.

**The type really is random, and that is a decision rather than an omission.**
Twenty to thirty planet explosions a day in the galactic log was authentic TW2002,
and chasing the world you want by paying for the rolls is the price of a credit
sink that never saturates — a world is permanent, so there is always another empty
sector. Ten types means an expected **ten rolls** to get a specific one, each
costing a torpedo and a detonator. Type *profiles* (pick Fertile / Industrial /
Barren, roll within) would cut that to about three and are the obvious mitigation
**if** it turns out to be wearing — but that is a change to the item, and it should
be made after playtesting rather than before.

- `Planet.fromGenesis` — a torpedoed world starts unscanned, unowned, unpopulated,
  at 1.0 efficiency and no defence. A generated world carries a roll, a defence
  level and a starting store, all of which are *differences between worlds*; a
  new one has no history to differ by, so it starts at the honest baseline.
- `WorldForging` (new) owns the rules, rather than methods on `Planet`. These are
  the first things in the game that create and destroy the object the rest of the
  planet system is built around, so the slot cap, over-stack warning and collision
  dice need one home a screen cannot half-implement.
- The sector panel gains a `LAUNCH TORPEDO` entry when the player holds any. It is
  an action on the **orbit**, not a button on a world.

**Over-stacking is allowed, and is a weapon.** A fourth world in a three-world
sector raises an unmissable warning and then a **24-hour gravity check**; a bad
roll destroys a **pair** — two bodies meeting is the fiction, and losing a pair
makes over-stacking a real gamble rather than a slow tax. Hard-blocking it would
remove the torpedo's only offensive use and make the detonator pointless: a
capacity limit can be waited out, a hazard has to be answered. It is also how
players attacked a target's *economy* rather than their hulls.

**The collision roll is wall-clock, not game ticks, and deliberately so.**
Construction counts ticks because a build is the player's own progress and must
not complete while they sleep. A collision is the opposite — a background hazard,
meant to bite an abandoned sector, and the only thing that makes over-stacking a
decision. Odds worsen with each world past the cap: at a cap of 3, one extra world
is a 1-in-8 daily loss and three extras is 1-in-2, a sector that eats itself
within a week of being abandoned.

**A full sector is not an over-stacked one.** `isFull(cap)` (`>=`) and
`isOverStacking(cap)` (`>`) are separate predicates doing different jobs — the
first is the pre-launch question, the second is the state the collision roll acts
on. Conflating them described a sector holding exactly its cap as gravitationally
unstable, which is both wrong and the reason a guard passed against a fault.

**`worldSlotsUsed` counts living worlds, not total.** A destroyed world stays in
the list so it can still be drawn and argued about, but it holds no orbital slot —
that is exactly what makes the detonate-then-re-roll loop work.

### DECISION — Genesis Torpedo and Atomic Detonator

The torpedo creates a world in a sector; the type is **random**. The detonator
destroys a world, freeing its slot for another roll.

An earlier draft of this document recommended letting the player **choose** the
type. **That was wrong, and the reason is the detonator.** If the type is chosen,
there is no reason for a detonator to exist and the torpedo becomes a one-shot
purchase instead of a **repeatable sink** — and the credit sink matters more than
the convenience, because a world is permanent, non-transferable, and there is
always another empty sector.

The design that follows: buy torpedoes and detonators from the emporium, limited by
cargo; roll a sector; detonate what you dislike; roll again. **The lottery is the
cost, and the sector you roll in is the actual bet.**

**Open question — profiles.** Ten types means an expected **10 rolls** to get one
specific world, which reads as bad luck rather than a decision. A proposed
mitigation, not yet agreed: pick a *profile* and roll within it — **Fertile**
(Terran/Jungle/Ocean), **Industrial** (Terran/Desert/Lava/Barren/Toxic), **Barren-
Cold** (Ice/Moon/Gas Giant). Three rolls instead of ten, and "I need an ocean
world" becomes a request rather than a numeric grind.

The Atomic Detonator also makes `Planet.destroy()` reachable years before
invasion ships, and forces `destroy()` to be correct against a **list** (remove
from the list, not null one field).

### DECISION — per-type production caps

Every type caps how much of each commodity it can produce **per day**; past the cap
nothing further accumulates. This is the classic mechanic, and it is the missing
half of the storage work: storage bounds what a colony can *hold*, but a cap bounds
what it can *extract*, which is what stops a 1M-citadel world from printing
without limit.

The cap should be per type and per commodity, and it should scale with Citadel
level — otherwise it is another fixed number that cannot serve a small and a very
large colony, which is the same trap as `colonistMax` and the storage floor.

### DECISION — the resource market, and why one port is not enough

A port's type string is **per commodity** (each legal good independently rolled
`S` or `B` at 50/50), so a port can never both buy and sell the same commodity,
and only **12.5%** of ports buy all three resources. Assigning one port per planet
would therefore be unable to run a colony's economy in ~99% of cases.

**Each commodity, in each direction, gets its own counterparty** — up to six per
planet. Each is stable, each is named in its own `(i)` bubble, and each is
rerollable. The reroll must **search for a port that can actually perform that
trade**, never roll at random, so a counterparty can never be assigned one that
refuses the commodity. Port character stays a feature: a black market that will not
touch contraband stays a black market.

### DECISION — the exchange, as a pressure valve

An unlimited market with a **spread**, so ports are always better:

```
exchange bid  <  port average buy price  <  port average sell price  <  exchange ask
```

Selling to the exchange pays the low bid; buying from it charges the high ask. The
gap between them **is** the premium on logistics, and it is what makes cargo
capacity, hull choice, engines, and owning a port worth anything. Without it, the
exchange becomes the default the moment it can absorb more than a port, and the
port economy becomes decorative.

**The condition is a knife edge and needs a test**: if the bid is ever above a
port's buy price, that is an arbitrage loop, and with colonies under pressure to
liquidate fast it would be found immediately.

**It is built last, and that is the important sequencing decision.** An unlimited
flat sink **hides every other problem** — the moment it exists, the 10x faucet stops
mattering, and the harsh worlds, the hauler and the torpedo all look like features
nobody needs. Build it first and we ship a broken economy without ever finding out.

### DECISION — no selling drones

Drones are a colony output and a combat resource, not a commodity. They get
`Dep`/`Wdr` (so they can reach a hold and be fielded) but **no market row, no cash
value, and nothing in the `Collect` payout**. Drones are worth 10 cr in the current
shipment valuation, the lowest of the four by an order of magnitude, and they
should be worth zero in credits.

**Consequence to watch:** if drone production also consumes industrial (proposed,
below), a drone-heavy world becomes a pure industrial drain with no cash return.
That is defensible — drones are worth their combat value — but the player has to be
able to see it, or it reads as a trap.

### OPEN — the only remaining recurring sink

With upkeep removed, the level-up import is a one-time-per-tier cost and
therefore almost no drain (0.4% of a day's output, above). The only candidate left
for a **recurring** resource cost is **drone maintenance**, scaled per colonist on
the drone track rather than per drone unit — a real but minority cost. Per-unit was
rejected: drones are the lowest-value output, so a meaningful per-unit industrial
cost would make drone production value-destroying on every world.

**Undecided.** It is the only mechanism left that would make a large empire
consume rather than merely accumulate.

### OPEN — ports do not grow, and unowned ports never will

`storageLevel` drives `effectiveMaxSupply`/`effectiveMaxDemand` at `1.5^level`, so
it is exactly the right lever. But only two things increment it: an NPC that
**owns** the port (`npc_goal_executor.dart:473`) and a player who **owns** it
(`port_management_screen.dart:685`). The generator gives ~40% of ports an owner, so
**~60% of the galaxy's ports are frozen at their generated capacity forever**.

Making a port's storage level creep with accumulated volume would let **the sink
scale with the faucet**, and would make owning a port a *speed* advantage rather
than a prerequisite. Not decided, and it is the most likely fix for the absorption
overshoot.

### OPEN — sector stealth is accidental, not designed

A player picks a base sector partly to be found rarely, and `1 + warpRoutes.length`
is a perfectly good discovery-risk score. Our generator **does** produce 1-warp
dead-ends, but only as a side effect of the orphan-repair phase. If the strategy
depends on them, that should be intentional.

### Revised order of work

Every step makes the next one worth building, which is the entire argument for the
sequence.

| # | Change | Size | Why here |
|---|---|---|---|
| 1 | ~~**`Sector.planets` list + per-planet id + save migration**~~ | **DONE** | Eight files read `sector.planet`. Every other step touches the same files — doing them on the 1:1 model means doing them twice. |
| 2 | Harsh types -> organics 0; remove upkeep/starvation | Small | Creates the gaps that make step 3 meaningful |
| 3 | ~~`Dep`/`Wdr` -> cargo; delete `_transferPrices`~~ | **DONE** | The hauler. **Built before step 2, reversing the documented order** — see below. |
| 4 | ~~Genesis Torpedo + Atomic Detonator + collision rolls~~ | **DONE** | Needs 2 and 3: planting a complement is worthless if goods cannot move |
| 5 | Per-type production caps | Small | Stops a large colony printing without limit |
| 6 | Per-commodity port counterparties + `(i)` bubbles | Medium | Now answerable, because there is a reason to care which port |
| 7 | The exchange | Medium | **Last, deliberately** — see above |
| 8 | Port growth on unowned ports | Medium | The most likely fix for the absorption overshoot |

Steps 2 and 3 are **independent of the refactor** and can be banked first if the
risk in step 1 is not wanted up front. Scanner auto-scan, NPC colonisation and
invasion all remain after this, and invasion is still the only path to ownership
having combat stakes.


## Code Audit (2026-09-28)

Findings from reading the model, screen, generator, and tick service against this
document. Severity is about player-visible impact.

### 0. FIXED — production is displayed but never applied

`planet_screen.dart:793-799` renders, per track, e.g.
`1,200 -> 1,440/tick`. The **only** writes to `storedMinerals`,
`storedOrganics`, `storedIndustrial`, and `storedDrones` anywhere in `lib/`
are `planet_screen.dart:644-650`, inside `_transferToPlanet` — which is a
**credits purchase**, not production. `GameTickService` has no production hook;
it calls `RepopulationService.repopulate` and `.produce`, which spawn NPC
*ships*.

Design Goals 2, 6, and 7 are therefore entirely inert. This ranks above a
missing feature because the UI presents a working feature that silently does
nothing, and a player watching the number will reasonably assume it will change.

### 1. Levelling a planet grants nothing — HIGH, **FIXED**

*(Original finding, kept for the record. Both halves are now resolved — see below
and the Citadel section.)*

`Planet.levelUp()` (`planet.dart:285`) increments `level`, zeroes
`levelProgress`, and updates the `required*` fields. It does not touch
`maxStorage`, `defenseLevel`, `shield`, `hull`, or any production capacity.
Design Goal 3 promises "more production capacity, defense options, and storage"
per level; none of the three happen.

**Now fixed.** `levelProgress` is gone; builds take game ticks. Completing a build
applies `levelDefense` / `levelArmour` / `levelShield`. The colonist cap scales
with the tier, and the cost table is re-derived against the distance-priced
colonist economy.

At the old flat colonist price (20 cr) this climbed 1 -> 6 for **~36.8M credits**,
with colonists accounting for 85-95% of every step and no mechanical benefit — a
treadmill, not a progression. **Both halves are now fixed** (see *Citadel levels*
below): levels confer defence, armour, shields and a larger population ceiling, and
the cost table has been re-derived against the distance-priced colonist economy.

Two supporting findings:

- **`levelProgress` was dead.** Never incremented anywhere in `lib/` — only
  initialised to 0, reset by `levelUp()`, and serialised. **Removed** and replaced
  by `constructionTicksRemaining` / `constructionTarget`, which are real: a build
  takes game ticks to complete.
- **`defenseLevel` never scaled.** Set once at generation (0-2, or 4 for
  homeworlds) and never written again, so a level-6 Citadel defended exactly as
  well as a level-1 Outpost. **Fixed**: a completed build applies
  `Planet.levelDefense` / `levelShield` / `levelArmour` for the tier reached.

### 2. The colonist cap and the level costs are mutually unsatisfiable — HIGH

`Planet.colonistMaxByType` caps colonists per planet type, but the level costs
require up to 1,000,000. The cap is **display-only** — `_maxFor`
(`planet_screen.dart:454`) feeds a progress-bar bound and is not enforced on
transfer — so this is not a hard block. It is worse in a way: the UI tells a
player they are capped at 100,000 while requiring 1,000,000 to advance, and the
bar sits pegged at maximum the entire time.

Reachability of level 6 (needs 1,000,000 colonists) by type:

| Type | Cap | Reaches 4->5 (500k)? | Reaches 5->6 (1M)? |
|------|-----|----------------------|---------------------|
| Terran | 2,000,000 | yes | yes |
| Jungle | 1,500,000 | yes | yes |
| Ocean | 1,000,000 | yes | yes (exactly) |
| Desert | 600,000 | yes | no |
| Ice | 400,000 | no | no |
| Lava | 200,000 | no | no |
| Moon | 200,000 | no | no |
| Barren | 150,000 | no | no |
| Gas Giant | 100,000 | no | no |
| Toxic | 100,000 | no | no |

**8 of 10 types can never reach Citadel.** And because Duran homeworlds are
drawn only from Lava/Toxic/Barren/Moon, **every Duran homeworld is capped below
the 500,000 needed for 4 -> 5**.

Root cause was this document's own level table disagreeing with the code by 13x.
**RESOLVED** — resolved in both directions at once, because either alone leaves the
other as a wall: the colonist costs were cut (see *Citadel levels*) **and**
`colonistMax` now scales with level. Every one of the 10 types can reach every
tier, and that now holds *by construction* rather than by tuning: a test walks all
ten types up all five steps and fails on any row where the cap is under the gate.

The test that used to assert this broken state was deleted rather than inverted. It
existed to stop anyone changing a cap silently, which was a real risk — but a guard
that forbids fixing the defect outlives its reason, and the replacement guard
protects the same tables from a different direction.

### 3. The two scan paths make one strictly dominated — MEDIUM

The sector panel's 1-energy quick scan and the planet tab's 4-energy scan set the
same `scanned` flag and reveal the same detail dialog. The only difference is
that the expensive path grants +1 faction standing. Every player will quick-scan,
so the 4-energy path is dead weight and the standing reward is the sole reason to
use it. Either fold them into one scan, or make the quick scan reveal strictly
less and leave the full reveal worth paying for.

### 4. Colonists are bought, not transported — MEDIUM

`_transferPrices['colonists'] = 20` credits per colonist, with no cargo hold
consumed. Design Goal 2 and the Inspiration table both specify colonists
travelling from Terra (sector 1) in cargo holds. This is Phase D, unimplemented,
and it means the colonist economy is currently a pure credits sink with no
physical constraint.

### 5. A removed faction name crashes the whole universe load — HIGH, FIXED

`_parseFactionClass` (`planet.dart:3`) looked up a persisted faction with
`FactionClass.values.firstWhere(...)` inside a `try { } on ArgumentError { }`.

`firstWhere` with no match throws **`StateError`**, not `ArgumentError`, so the
`on` clause never fired. Any save naming a faction that no longer exists threw
out of `Planet.fromJson` — and because a planet is embedded in a `Sector`, that
takes down the entire `universe.json` decode, not just one planet.

Fixed by switching to `FactionClass.values.byName`, which does throw
`ArgumentError` and is what the `on` clause was written for. This also makes
`planet.dart` match `port.dart`'s identically-named helper, which already used
`byName` correctly. `FactionStanding`, `NpcShip`, and `Player` use `orElse:` and
were never affected.

Found by the first test written against the planet model, which did not exist
until the drones rename forced the question.

### 6. Dead and vestigial model surface — LOW

- `dominantCommodity` (`planet.dart:139`) has no caller anywhere in `lib/`.
- **Terminology: fighters -> drones.** The model carried `storedFighters` /
  `colonistsFighters` / `TypeMultipliers.fighters` while the planet screen
  already labelled the row "Drones" and the rest of the game uses drones
  throughout (`Player.drones`). Renamed to `storedDrones` / `colonistsDrones` /
  `drones`, with a legacy read of the old JSON keys so existing saves keep their
  colony. Ships field drones in this game; a planet growing "fighter
  squadrons" was importing the wrong game's vocabulary.
- The `requiredColonists` **field** is written by the generator and never read:
  all gating goes through `levelUpCost.requiredColonists` from the static table.
- `requiredColonists` defaults disagree — 1000 in the constructor
  (`planet.dart:95`) vs 100 in `fromJson` (`planet.dart:217`).

### 7. The starvation cap could strand a colony forever — HIGH, FIXED

Found by the first test written against `produce()`.

The bleed is capped at 2% of population per tick so a colony cannot be wiped
out in one tick. But `floor(population * 0.02)` is **0 for any population below
50**, so the cap floored the loss to zero: a starving colony shrank to 49
colonists and then stopped losing anybody, permanently. A zombie world, starving
forever, that could not be saved by delivering organics — the tick had nothing
left to take.

Fixed by guaranteeing at least one colonist dies per starving tick, so an un-fed
colony always finishes, while a large one still only bleeds at 2%.

### 8. The economy's sink already existed; the UI made it unreachable

Recorded because it is a case of **the balance being right and the control
surface being wrong**, which reads from the player's side exactly like a balance
bug.

The instinct on seeing a colony produce ~14,400 minerals/tick (roughly 36M
credits/hour at mid-range) was to nerf production. Measuring first showed the
market brake was already built and correctly sized: every port has a finite
`maxDemand` per commodity that refills over a 24-hour cycle, and port storage
upgrades multiply it by 1.5x per level (max 10, from 100,000 credits doubling
each time). Across a 100-sector universe that is **~1.24M minerals of demand per
day** across 25 buying ports, worth ~52M credits.

The real bug: `_buy` and `_sell` in `port_trade_view.dart` both hard-coded
`final amount = 1`, so a port's ~78,000 minerals of demand took **78,000 taps**
to cash in. A colony's shipment pool was effectively uncashable, and the economy
read as broken rather than throttled.

Fixed with a `UNITS/TAP` selector (1 / 10 / 100 / 1K / MAX), clamped to what the
port will still take, the player's cargo, credits and cargo space. The balance
needed no change. Guarded by `test/port_demand_test.dart`.

The general lesson, now in `AGENTS.md`: **when a player says a number is too
generous, measure the sink *and check the sink is reachable through the UI*
before nerfing the tap.**

### 9. Two natural-width Texts in a Row — three layouts, all pre-existing

Found by rendering the planet screen at 430px, not by reading it. `Row` with
`spaceBetween` and two unconstrained `Text`s overflows once the value gets long,
and every one of these had a value that had simply never been long enough:

- `_infoRow` in `planet_screen.dart` — broke as soon as Population was shown
  against its cap ("12,450 / 1.5M").
- The shared `StatBar` **stacked** layout, which is used app-wide, not just here.
- The "Owned by {faction}" header — 153px over at 430px.

Each now constrains the value side and ellipsises. Separately, two card rows
side-by-side were stacked below 560px with a `LayoutBuilder`, because two
`Expanded` halves of a 430px phone leave each panel ~198px. The StatBar
ellipsis alone was not enough: it stopped the overflow but left a player's own
stores unreadable, so the cards had to stack to fix the cause rather than the
symptom.

**None of this was visible in the code, and the only reason it surfaced is that
the screen was rendered at four widths and looked at.**

---

## Third-Party Review (2026-09-28) — response

A long external review proposed elevating planets to a strategic layer. Most of it
is good and is folded into this document. This section records what was accepted,
what was declined **and why**, and the one place where the review and this
project disagree about sequencing. Without it, the next reader cannot tell which
of these ideas are decisions and which are still open.

### Accepted outright

- **The production multiplier was a balance bug, not a feature.** The 5.5x level
  multiplier compounds with the type multiplier and the colonist caps into a
  110x spread between best and worst colony. Corrected to a shallow development
  curve; see the Citadel section for the reasoning.
- ~~**Economic runaway is a real risk, and upkeep is the sink.**~~ **Accepted the
  risk, declined the mechanism.** The concern was correct — measured, one colony
  out-produces the whole galaxy's port treasury 10.2x in a day — but a per-capita
  upkeep tax was the wrong sink, because it taxes a *large* colony harder and
  makes harsh types tedious rather than distinct. The Economy Redesign takes three
  other routes instead: production gaps on harsh types, a repeatable torpedo sink,
  and per-type daily production caps.
- ~~**Maintenance budget as a concept**~~ **Declined with upkeep.** "Gross output
  minus upkeep, so a bigger colony is powerful *and* expensive to run" is exactly
  the tax that turned out to be wrong. The only survivor is drone maintenance as a
  per-colonist rate, and that is still `OPEN`.
  section.
- **Progressive scanning** (quick reveals type/owner/danger, detailed reveals
  population and production, scanner module reveals exact figures). This makes
  the unwired scanner module worth buying and gives the two existing scan paths a
  reason to differ.
- **Per-commodity storage** rather than one global `maxStorage`, so a player
  cannot fill a planet with minerals and consume all capacity. This also gives
  infrastructure a reason to specialise.
- **Planet specialisation** (mining / agricultural / industrial / fortress /
  trade), which is what makes planet type strategically meaningful rather than
  cosmetic.
- **Reserve population** — colonists not assigned to a track contribute to
  growth and defence. Adds a real decision to workforce allocation.
- ~~**Construction instead of instant upgrades**~~ — **done**, see *Citadel
  levels*. The dilemma it was meant to create (attack a world mid-upgrade) is
  still latent: it only becomes reachable when invasion lands.
- **Make level unlocks capabilities, not just bigger numbers.**
- **Gas Giant identity.** At 0.6/0.6/0.4 it has no reason to exist, and "why
  would I colonise this" is the right question. Fuel ties neatly into the energy
  system that already exists.
- **Planets affecting port prices**, and **port supply chains with distance /
  piracy / cargo constraints** — the strongest ideas in the review, because they
  make a planet's existence change the galaxy rather than fill a private box.
- **Destruction in stages** (devastated -> dead) rather than a single permanent
  removal, so destruction is an event rather than a routine combat outcome.
- **NPC colonisation scoring** rather than "first unclaimed planet found".
- **Ownership history** feeding faction memory, vendettas, and news events.
- **Planets as NPC strategic targets** (faction-flavoured defence priorities).
- **The six "must resolve before coding" items** — all were already in the audit
  and all remain open. That agreement is the most useful part of the review.

### Declined — with evidence

- **"Add a stable `planetId`; do not rely on `planet.name`."** The premise is
  incorrect. `Planet` has no id field, but nothing keys a planet by name
  either — `grep` for name-based lookups across `lib/` finds none. A planet's
  identity is already `(sectorId)`, because `Sector.planet` is a single
  `Planet?` and `Sector.id` is a stable persisted int. That is the save key
  today. Adding `planetId` would introduce a second identity to keep in sync
  rather than fix a bug.

  This becomes a real requirement in exactly one case: if a sector ever holds
  more than one planet (a Genesis Torpedo creating a moon beside a world, for
  instance), at which point 1:1 breaks and a per-planet id is needed. Worth
  writing down now, not building now.

- **"Drones as a separate defence system rather than a stored resource."**
  Directionally right, but it is Phase-2 work that depends on invasion existing
  to have anything to defend against. Renaming the vocabulary now is right;
  restructuring the storage model now is not.

### Disagreed — sequencing

The review's central recommendation is **do not implement production yet**; land a
large model redesign first (id, role, condition, occupation, per-resource
storage, capacity model, construction) and only then write the tick loop.

This is the one place where I think the advice is wrong, and the reason is
specific rather than a difference of taste:

- Production is the one thing on the planet screen that is **currently a lie**.
  The screen displays a per-tick rate that can never change. That is worse than
  an absent feature, because it looks like a working one and misleads the player
  about the state of their colony.
- The production tick is **small and independent** of the redesign. It reads
  fields the model already has and writes fields the model already has. None of
  the proposed new concepts are prerequisites for it.
- Every week production stays unimplemented, the lie is live in front of players.
  Deferring correctness in order to enable a future redesign maximises the cost of
  the redesign, not minimises it.

So: land production and upkeep now, because it is cheap and it stops the screen
misrepresenting the game. Land the **colonist assignment UI** with it, or the
feature is unreachable — a claimed planet has zero colonists and no way to get
any, because only the generator ever sets track counts. Then do the model work.

The review is right that invasion must come *after* production, population,
defence, and ownership have real consequences; designing combat around
placeholder planetary economics would indeed mean redoing it. That part is
adopted as-is.

### The five questions, answered

The review asked for five decisions before the production tick. Four are
recorded in this document and one is answered here:

1. **What does a level mean?** Capability unlocks plus storage and defence
   growth, with a shallow development multiplier. See the Citadel section.
2. **How does population grow, work, and die?** Assign to four tracks plus a
   reserve; grow from habitability, organics surplus, and level; decline from
   food shortage and unrest. The lifecycle beyond that is not designed yet — see
   the backlog.
3. **What makes one planet strategically different?** Type multipliers that stay
   dominant regardless of level, plus specialisation. See the multiplier
   correction.
4. **How does a planet affect the wider economy?** Through supply chains into
   nearby ports, which move port prices. Not built.
5. **What happens when someone tries to take one?** Still open. The review's
   staged model (breach -> orbital control -> assault -> occupation ->
   claim/puppet/abandon) is the right shape and is recorded in the warfare
   section, but the decision is not made and should not be made before
   production exists, precisely because the review is right that it would
   otherwise be designed against placeholder economics.

### Backlog, not prerequisites

Recorded so the ideas are not lost, explicitly **not** blocking production:
`PlanetRole` enum, occupation/pacification states, planetary ruins, abandoned
colonies, planet events, colony ships, ownership history fields, NPC strategic
targeting, blockade/raid outcomes, and the full per-commodity storage split.

## Design Goals (from user conversation)

Status is as of the 2026-09-28 audit. **DONE** = shipped; **PARTIAL** = shipped
but not as described; **NOT BUILT** = designed only.

1. **DONE — NPC repopulation via homeworlds.** Ships spawn from homeworlds on a
   timer, with floor recovery. Shipped *more* strictly than specified: capture
   freezes production but recapture restores it, so extinction is reversible.
2. **DONE — Colonist-driven production.** `Planet.produce()` runs the same
   arithmetic the screen displays, once per tick.
3. **DONE — Planet levels (Citadel 1-6).** Levels, titles, gating, costs, a
   development multiplier, storage growth, **and** per-tier defence/armour/shield
   grants. The colonist-cost/cap contradiction is resolved in both directions: the
   costs were re-derived and the cap now scales with the tier. Builds are timed in
   game ticks. *Superseded entry: the earlier PARTIAL wording said defence did not
   scale and the cap was contradictory; both are fixed.*
4. **PARTIAL — Scan before landing.** Scanning works and gates the screen. The
   scanner-module auto-scan is unwired, and the two manual paths are
   inconsistent (Code Audit #3).
5. **DONE — Claiming & ownership.** Unclaimed planets can be claimed; owner and
   homeworld state drive map markers, repopulation control, and the screen.
6. **DONE — Resource abundance.** Extraction rate scales with colonists, type,
   world efficiency and level, and storage is the only thing that can hold a
   colony back.
7. **DONE — Max production rate.** Capped per commodity by a per-type store,
   which also scales with level and is floored at a fixed number of ticks of
   the colony's own output so nothing can out-produce its own infrastructure.
8. **PARTIAL — Backup homeworld.** Backups are generated, control-gated, and
   take over correctly. No NPC ever *claims* one, so the recovery path only
   triggers from capture/destruction, not from an orphaned faction expanding.
   **Deliberately left until after invasion (H).** Its entire drama is a faction
   losing its capital and re-founding, and NPCs cannot capture anything yet — so
   building it now means writing code whose interesting state is unreachable.
   The control-gating rules all exist and are waiting.
9. **DONE — Construction timer.** A build advances one step per game tick, so it
   only progresses while the game is running, and the speed is a preference in
   Settings -> Planet Construction. See *Build time* for why this is not a
   wall-clock deadline.
10. **NOT BUILT — Invasion.** Log line only.

## Inspiration (Research Summary)

Classic BBS-era planet system core mechanics:

| Mechanic | Classic BBS | Our adaptation |
|----------|--------|----------------|
| Planet creation | Genesis Torpedo, random type, up to 3-5 per sector; Atomic Detonator to retry | Random gen at universe creation; Genesis Torpedo + Atomic Detonator are steps 4 of the Economy Redesign, with a 24h collision roll for over-stacking |
| Planet types | 7 types (M/K/O/L/C/H/U) with different production multipliers | 10 types, each with production rate multipliers; **harsh types produce zero organics** rather than a small amount (Economy Redesign) |
| Colonists | Brought from Terra (sector 1) in cargo holds | Per-faction from the faction's own homeworld, priced by distance; **the physical cargo-hold half is still not built** |
| Production assignment | Assign colonists to Fuel Ore / Organics / Equipment tracks; per-type daily caps, past which nothing accumulates | Assign colonists to Minerals / Organics / Industrial tracks; per-type daily caps (step 5, not built) |
| Citadel levels | 6 levels, each requires resources + colonists, takes real days (34-52) | 6 levels, each requires resources + colonists; a build takes 15-160 **game ticks** |
| Defense | Fighter squadrons + Quasar Cannons per level (the classic term; this game calls them drones) | Shield/hull per level + special abilities (matching port defense model) |
| Drone production | Colonists produce drones per day as passive output | Passive drone production per tick (stored on planet) |

## Planet Model — Enhanced Fields

```dart
class Planet {
  final String name;
  final String planetType;            // Terran, Jungle, Desert, Ocean, Ice, Lava, Gas Giant, Moon, Barren, Toxic
  final String atmosphere;            // N2-O2, CO2, Methane, Ammonia, Acid, Thin, None, Dense

  // Ownership
  FactionClass? owner;               // null = unclaimed
  bool isHomeworld;                  // true if this is a faction's homeworld
  FactionClass? homeworldOf;         // which faction's homeworld
  bool isBackupHomeworld;            // cold-standby capital (C4b)
  bool isDestroyed;                  // planet-killer path; permanently out of play

  // Colony
  int population;                    // total colonists on planet
  int colonistsMinerals;             // colonists assigned to mineral production
  int colonistsOrganics;             // colonists assigned to organic production
  int colonistsIndustrial;           // colonists assigned to industrial production
  int colonistsDrones;             // colonists assigned to drone production
  double productionEfficiency;       // 0.5–1.5, random per planet

  // Storage (per commodity). Caps are NOT fields — they are derived from
  // planet type and level (see baseStorageByType / levelStorageScale), so they
  // cannot drift from the type table.
  int storedMinerals;
  int storedOrganics;
  int storedIndustrial;
  int storedDrones;

  // Output that overflowed the working store and is owed to the player.
  // Nothing is discarded; a colony keeps earning while you are elsewhere.
  int pendingMinerals;
  int pendingOrganics;
  int pendingIndustrial;
  int pendingDrones;

  // Level / Citadel (1–6)
  int level;                         // 1 = basic colony, 6 = max fortress
  int constructionTicksRemaining;    // 0 = idle; decremented once per game tick
  int constructionTarget;            // the level the running build will produce

  // Resources needed for next level
  // NOTE: these four fields are written by the generator but all gating reads
  // levelUpCost.* from the static table instead — they are currently vestigial,
  // and requiredColonists defaults inconsistently (1000 ctor vs 100 fromJson).
  int requiredMinerals;
  int requiredOrganics;
  int requiredIndustrial;
  int requiredColonists;

  // Defense
  int defenseLevel;                  // 0-4; scaled by levelDefense on build completion
  double shield;
  double maxShield;
  double hull;
  double maxHull;

  // NPC spawning (homeworld only)
  int productionTimer;               // ticks since last NPC spawn
  int spawnInterval;                 // ticks between NPC spawns

  // Visual
  String? imagePath;                 // selected at universe gen from the type's image pool

  // Scanning
  bool scanned;                      // has this planet been scanned?

  String id;                         // REQUIRED once a sector holds more than
                                     // one world. (sectorId) stops being an
                                     // identity the moment Sector.planet
                                     // becomes a list.
}
```

**The owning `Sector` changes shape too** — this is the top-priority refactor and
the only change in this document that is not additive:

```dart
class Sector {
  // BEFORE
  //   bool hasPlanet;
  //   Planet? planet;

  // AFTER
  bool get hasPlanet => planets.isNotEmpty;
  List<Planet> planets;   // up to `planetsPerSector` (universe setting, default 3)
}
```

## Planet Types & Production Multipliers

Each planet type has production multipliers for each commodity (1.0 = baseline).
Colonist output per tick = `baseOutput * multiplier * productionEfficiency`.

| Type        | Description           | Atm.    | Minerals | Organics | Industrial | Drones |
|-------------|-----------------------|---------|----------|----------|------------|----------|
| **Terran**  | Earth-like, habitable | N2-O2   | 1.0      | 1.0      | 1.2        | 1.0      |
| **Jungle**  | Dense vegetation      | N2-O2   | 0.6      | 1.8      | 0.6        | 0.8      |
| **Desert**  | Arid, sandy           | Thin    | 1.4      | 0.4      | 0.8        | 1.2      |
| **Ocean**   | Water world           | N2-O2   | 0.4      | 2.0      | 0.6        | 0.6      |
| **Ice**     | Frozen wasteland      | Thin    | 0.8      | 0.4      | 0.6        | 0.8      |
| **Lava**    | Volcanic, molten      | CO2     | 2.0      | 0.2      | 1.4        | 1.4      |
| **Gas Giant**| Massive, gaseous     | Dense   | 0.6      | 0.6      | 0.4        | 1.0      |
| **Moon**    | Small rocky body      | None    | 1.0      | 0.4      | 0.6        | 0.8      |
| **Barren**  | Rocky, lifeless       | None    | 1.2      | 0.2      | 0.8        | 1.0      |
| **Toxic**   | Corrosive atmosphere  | Acid    | 1.6      | 0.3      | 1.0        | 1.2      |

**Classic equivalents:** Terran→Class M, Jungle→Class M variant, Desert→Class K, Ocean→Class O, Ice→Class C, Lava→Class H, Gas Giant→Class U, Moon→new, Barren→new, Toxic→new.

**SUPERSEDED — the Organics column.** The values above are the *shipped* table.
Per the Economy Redesign, Lava / Barren / Toxic / Ice / Moon go to **0.0**
organics, matching the classic Volcanic world which produced none at all. The
weak-but-nonzero values (0.2-0.4) are what the abandoned per-capita upkeep design
needed; with a gap-based design they should be a true zero, so a harsh world is
*incapable* rather than merely expensive.

That is also the only value in the whole game that can be zero, so it needs a UI
consequence: a workforce track showing "cannot produce" rather than a `0`. Nothing
in the model divides by a type multiplier, so zero is safe arithmetically —
verified — but it is not safe to leave invisible in the workforce steppers.

## Planet Levels (Citadel)

Six tiers, from Outpost to Citadel. **The table below is what the code enforces**
(`Planet.levelUpCosts`), and it no longer matches this document's original
figures — see the Code Audit for the consequences.

Gating is a direct check against *stored* resources plus population. Colonists are
a **minimum**, not a cost — a gate you satisfy by having enough people. Resources
are **consumed the moment the build starts**, not when it finishes, which makes a
build a commitment rather than a purchase.

### Build time — game ticks, deliberately not wall-clock

A build advances one step per **game tick** (`PlanetProductionService.process`
calls `advanceConstruction()`), so it only progresses while the game is running.

This is a design decision, not a limitation. The classic game's 34-52 *day* builds
were acceptable in a persistent online world where every other colony was decaying
while you slept. This is single-player, and a wall-clock deadline would mean
quitting for a week silently finishing every build and nothing else: the player
would come back advanced past a galaxy that had stood still. Counting ticks keeps
the player and the NPCs on one clock.

| Transition | Base ticks | At the 30s tick |
|------------|-----------|-----------------|
| 1 -> 2 | 15 | 7.5 min |
| 2 -> 3 | 30 | 15 min |
| 3 -> 4 | 60 | 30 min |
| 4 -> 5 | 120 | 1 hr |
| 5 -> 6 | 160 | 80 min |

A full 1 -> 6 is 385 ticks, about **3.2 hours of actual play** and nothing at all
while the game is closed.

**The countdown must reach disk before the player can navigate away.** A live
bug had `startConstruction()` mutate the planet in memory and return without
saving, so leaving the tab threw the build away: the gate came back armed, at the
same level, with the resources back in the store, and the timer never moved
because the tick was advancing a *different* object — `GameTickService` re-reads
the universe from disk every tick while the screen holds a copy loaded at mount.
The screen now writes through on every mutating action and re-reads from disk on
its poll rather than fingerprinting its own objects. The underlying architecture —
one universe, two object graphs — is still open; see the guard in
`test/planet_construction_persistence_test.dart`.

`GameSettings.constructionTimeScale` scales this (Instant / Fast / Standard /
Slow), surfaced in **Settings -> Planet Construction** with the resulting per-tier
times displayed. The scale is applied **when a build starts**, not when it
finishes, so changing it mid-build cannot retroactively shorten work already paid
for. A scale of 0 means instant and yields a 1-tick build rather than a
zero-length one.

### What each tier grants

Generated from `Planet.levelDefense` / `levelShield` / `levelArmour`, and
documented in the Planet Guide from the same tables so they cannot disagree.

| Tier | Defence | Population ceiling |
|------|---------|--------------------|
| 1 Outpost | none | x1.00 |
| 2 Settlement | light | x1.60 |
| 3 Colony | moderate | x2.80 |
| 4 Fortified Colony | heavy | x5.00 |
| 5 Planetary Base | fortified | x8.00 |
| 6 Citadel | fortified | x12.00 |

**The population ceiling scales with the tier on purpose.** A fixed per-type cap
was the original defect: the top gate wanted 1,000,000 colonists while 7 of the 10
world types capped below that, so those worlds could never reach Citadel however
much they were developed, and every Duran homeworld was capped under the 4 -> 5
gate. Deriving the cap from the level is the same fix as the storage floor — a
single fixed number cannot serve both a small and a very large colony, so the gate
grows with the colony and can never contradict the cap printed beside it.

| Transition | Colonists (min) | Minerals | Organics | Industrial | Credits @1 hop | @4 hops | @8 hops |
|------------|-----------------|----------|----------|------------|---------------|---------|---------|
| 1 -> 2 Outpost -> Settlement | 250 | 250 | 150 | 100 | 7.4K | 33.6K | 88.4K |
| 2 -> 3 Settlement -> Colony | 1,000 | 1,000 | 600 | 400 | 29.6K | 134.6K | 353.6K |
| 3 -> 4 Colony -> Fortified | 4,000 | 4,000 | 2,500 | 1,500 | 118.0K | 538.0K | 1.4M |
| 4 -> 5 Fortified -> Base | 15,000 | 20,000 | 12,000 | 7,000 | 505.0K | 2.1M | 5.4M |
| 5 -> 6 Base -> Citadel | 50,000 | 80,000 | 50,000 | 30,000 | 1.9M | 7.2M | 18.1M |
| **Total 1 -> 6** | | | | | **2.6M** | **9.9M** | **25.3M** |

Credit figures are **measured**, not estimated: `ColonistSupply.costFor` at 1/4/8 hops
plus the current resource transfer prices. A hand-computed balance table in a design
doc is a table that is wrong the moment the code underneath it moves.

**Why these numbers.** The previous table was priced when colonists cost a flat
20 cr, which made 1 -> 6 cost ~36.8M. Colonists are now priced by distance from
the faction's own homeworld at `15 x hops^1.5`, so the *same* gates came to
**28.7M at one hop, ~198M at the median four, and ~551M at eight** — the last two
steps alone were 94% of the total and read as a wall rather than a difficulty
setting. The resource half had stopped mattering too: 3.65M of resources against
120M of colonists.

The colonist requirements are cut by roughly 4x / 10x / 25x / 33x / 20x, landing the
full arc at 2.6M credits one hop from a capital, 9.9M at the median four, and
25.3M at eight — a few hours of play at any plausible distance, and reachable from
a mid-game income rather than only from a late one. Resources
are held in the same proportion *to each other* so the import decision still
bites — a large colony genuinely needs organics shipped to it, because upkeep is
proportional to population.

The earlier "credit column derived from `_transferPrices`" note is **removed**: it
described a flat 20cr colonist price that no longer exists. Credits are now
`ColonistSupply.costFor` (distance-scaled) plus resource transfer prices, and
`Dep`/`Wdr` no longer move credits at all — they move cargo. The measured table
above stands until the resource market replaces its resource prices with live port
prices.

### What a level grants — IMPLEMENTED

**Superseded.** This section was headed "NONE of it yet" and described a proposal.
Every column below is now live: `levelStorageScale` for storage,
`levelColonistScale` for the population ceiling, and `levelDefense` /
`levelShield` / `levelArmour` applied by `_applyLevelGrants()` when a build
completes. The development multiplier column was already implemented.

The original design gave each level storage, defense, and production capacity. The
grants, in the order they were implemented:

| Level | maxStorage | defenseLevel | shield / hull | development |
|-------|-----------|--------------|---------------|--------------|
| 1 Outpost | 5,000 | 0 | 0 / 1,000 | 1.00x |
| 2 Settlement | 25,000 | 1 | 2,000 / 4,000 | 1.15x |
| 3 Colony | 100,000 | 2 | 5,000 / 10,000 | 1.30x |
| 4 Fortified | 250,000 | 3 | 8,000 / 20,000 | 1.50x |
| 5 Base | 500,000 | 4 | 14,000 / 40,000 | 1.70x |
| 6 Citadel | 1,000,000 | 4 | 22,000 / 70,000 | 2.00x |

Storage values come from this document's original table. Defence follows the
original level -> defence mapping, **settled in favour of the generator**: homeworlds
are seeded at level 4 / defence 4, so level 5 and 6 both sit at 4 and the tier
defence scale is `0/1/2/3/4/4`. A level-6 Citadel no longer defends as well as a
level-1 Outpost, which was the defect.

The old `maxStorage` column is superseded by the **derived** per-commodity caps
(`baseStorageByType x levelStorageScale`, floored at 120 ticks of the colony's own
output). A single storage number cannot serve both a colony of a hundred and a
colony of two million, which is the same lesson as the population cap below.

**The development multiplier is deliberately shallow, and this was corrected.**
The first draft of this table used 1.0 / 1.5 / 2.2 / 3.0 / 4.0 / 5.5, which a
reviewer correctly identified as a balance bug rather than a feature. It
compounds with the type multiplier: a level-6 Lava world would produce
`2.0 x 5.5 = 11x` base minerals against a level-1 Terran's `1.0 x 1.0 = 1.0x`,
and multiplying that by the 10x gap in colonist caps (Terran 2M vs Lava 200k)
gives a **110x spread** between the best and worst colony. Everything worth
having would be on one planet type and every other type would be scenery.

The fix is to let **level scale the things a colony can hold and survive, not
the rate it extracts at**. Storage scales 200x across the six tiers and defense
scales with it, so levelling still buys a great deal; the development multiplier
stays shallow enough that an Ocean world remains the best food producer and a
Lava world remains the mineral powerhouse no matter how developed either gets.
Planet type stays a strategic identity rather than an early-game mistake.

### Open decision: colonist caps vs colonist costs

**RESOLVED: both, not either.** The costs were cut *and* `colonistMax` now scales
with the level. Either alone would have left the other as a wall — cutting costs
to fit a fixed 100,000 cap makes a Gas Giant a Citadel, and raising caps to fit
1,000,000 colonists makes the top two steps unaffordable for everyone. The
reasoning that settled it:

- 37M credits is unreachable regardless, so the current table is not a difficulty
  setting, it is a wall.
- A cap the UI displays must never contradict the gate printed next to it.
- Scaling the cap with level gives the 6 tiers a second axis of progression and
  makes `colonistMax` mean something, which a flat per-type number does not.
- A derived cap cannot contradict its own gate. Tuning two tables against each
  other only works until the next balance pass moves one of them.

This is the same lesson as the storage floor, arrived at independently: **a single
fixed number cannot serve both a small colony and a very large one.** Derive it.

---

## Colonists & Production

> **Status: implemented**, except colonist transport (phase D). The formulas below
> are what `Planet.produce()` runs and what the screen displays — one
> implementation, two readers.

### Sourcing Colonists — per-faction, priced by distance

**Colonists come from the player's own faction homeworld**, not from a shared
pool. A Duran Hegemony pilot draws Duran colonists; a Vinari draws Vinari.
Nobody ships in settlers of another species, so a world under your control is
the only supply of your own people. This is a lore constraint that turns out to
be a good mechanical one: it means **losing your capital costs you the ability to
grow**, not merely the ability to replace losses.

Source resolution (`ColonistSupply.sourceFor`) is deliberately delegated to
`RepopulationService.homeworldSectors`, which already encodes the control rules:
primary capital first, reserve capital as fallback, a captured or destroyed
capital produces nothing. Ship production and colonist supply therefore cannot
disagree about who still has a capital. A faction with neither falls back to
Terra Prime at `orphanSourcePenalty` (3x) — an exile is expensive, but never
permanently stuck.

**Credits scale with distance** from that homeworld:
`ColonistSupply.pricePerColonist(hops) = 15 x hops^1.5`, using the real BFS
distance.

| Hops | cr/colonist | 100,000 colonists | 1,000,000 colonists |
|------|-------------|------------------|--------------------|
| 1 | 15 | 1.5M | 15M |
| 4 (median) | 120 | 12M | 120M |
| 8 (farthest) | 339 | 33.9M | 339M |

The exponent is load-bearing. The galaxy is compact — measured across 117
generated planets, the distance from Terra runs 1 to 8 hops with a median of 4 —
so a *linear* distance premium is nearly invisible; 4 hops would cost barely
more than 2. At 1.5 the farthest worlds cost more than twenty times the nearest,
which is what makes "where do I settle" a real question.

**Energy is charged per shipment, not per colonist.** A shipment costs
`EnergyService.warpCost(player, hops)` — the same engine-aware rate as a real
warp, so the engine upgrade that helps you travel helps you supply an empire and
the two systems cannot disagree. Per-shipment rather than per-unit means batching
pays: a thousand colonists in one shipment costs the same fuel as ten shipments of
a hundred, and energy is the throughput limiter on how far an empire can spread.

**There is deliberately no transit timer.** The obvious alternative is "pay, then
wait for the colonists to land". That worked in the game this is drawn from
because it was online and every other colony was decaying while you slept. This
game is single-player with local saves, so a transit bar is not a strategic cost
— it is the player watching a bar for no reason, which is exactly the tedium the
design is trying to remove. A price rises whether or not you are looking.

**Bulk goods are not priced by distance.** A raw ore run is not worth taxing per
tonne, and levelling a planet should not be a second grind on top of populating
it. Resources ride the same shipments and pay the same fuel.

This replaces the flat 20 credits/colonist that made colonisation a pure credit
conversion: 500,000 credits used to buy 25,000 colonists instantly, and a planet
at any distance was worth the same to build.

- ~~**Colonists consume 1 unit of Organics per 10 colonists per tick (upkeep).**~~
  **Being removed.** See *Harsh types cannot produce a commodity at all* in the
  Economy Redesign: the classic game had no upkeep mechanic, and a per-capita tax
  turns harsh types into worse Terran worlds. Harsh types instead produce zero
  organics and must import or plant a complement. `organicsUpkeep` and the
  starvation path are deleted, not retuned.

### Assigning Colonists
When viewing a claimed planet, player can assign colonists to tracks:
- **Minerals** — `colonistsMinerals * mineralMultiplier * efficiency * levelMult`
- **Organics** — `colonistsOrganics * organicMultiplier * efficiency * levelMult`
- **Industrial** — `colonistsIndustrial * industrialMultiplier * efficiency * levelMult`
- **Drones** — `colonistsDrones * droneMultiplier * efficiency * levelMult`

Total assigned colonists cannot exceed `population`. *(The model carries the four
track counts and the screen displays them, but there is no assignment UI — the
tracks are only ever set by the generator for homeworlds.)*

`levelMult` is the per-level extraction multiplier from the table above; it does
not exist yet.

### Production Formula
```
outputPerTick = colonistsOnTrack * typeMultiplier * efficiency * development
                 * Planet.baseOutputPerColonist
```

`baseOutputPerColonist` is 0.01 and is a **pure scale factor**, not a balance
lever. It exists because the original per-tick figures were orders of magnitude
larger than any storage number could be sane against: a full Terran colony turned
out 1,600,000 minerals a tick against a 200,000 store and filled it in 0.6 ticks.
Upkeep is divided by the same constant, so output and upkeep move together and
every ratio in this design is unchanged — a colony still breaks even with one
tenth of its population on organics.

Example: 100 colonists on Minerals on a Lava planet (2.0x) at 1.0 efficiency,
level 1: `100 * 2.0 * 1.0 * 1.0 * 0.01 = 2 minerals per tick`. At level 6
(2.0x development): 4.

> When the scale was first corrected, upkeep was **divided** by the new constant
> instead of multiplied, which inflated food costs a thousandfold and made a
> colony unable to feed itself at any workforce size. Both are now expressed
> against the same constant.

### Storage — implemented, and nothing is wasted

Storage is **per commodity** and **differentiated by type**, replacing the single
`maxStorage` every world shared. Modelled on the classic game's per-product
limits, which are wildly uneven (Volcanic 1,000,000 ore / 10,000 organics;
Oceanic 1,000,000 organics / 50,000 equipment; Vaporous 10,000 of everything).
Drones are not a classic product, so their store is derived from the mineral
store rather than given a hand-picked row that could drift.

Caps scale with Citadel level, and are floored at
`Planet.minimumTicksOfOutput` (120 ticks, ~2 hours) of the colony's own output.
That floor is the important part: a fixed cap cannot serve both a colony of a
hundred and a colony of two million, because the large one out-produced any
fixed cap within a tick. Computing the floor means no colony can out-produce its
own infrastructure at any size, so **losing goods requires ignoring a world for
days**.

**Overflow is not discarded.** A full store spills into a shipment pool, which
holds 250x the working store. The planet screen shows what is queued and offers a
Collect action that pays the midpoint of the commodity spread. Measured over
1,000 ticks (~8 hours) at full population on every one of the ten types: **zero
waste**.

Two numbers were wrong before this and are worth recording. The output scale was
orders of magnitude too large — a full Terran colony turned out 1,600,000
minerals a tick against a 200,000 store and filled it in 0.6 ticks — and when
that was corrected, upkeep was initially *divided* by the same scale rather than
multiplied, which inflated food costs a thousandfold. Both are now expressed
against `Planet.baseOutputPerColonist`, and every ratio in the design is
unchanged because output and upkeep move together.

Upkeep also draws from the shipment pool as well as the working store. Food
already produced and awaiting collection is still food; without that, a poor-
organics world could starve on an empty store while tens of thousands of organics
sat unclaimed beside it.

### Upkeep and starvation — REMOVED

**This entire subsection describes a mechanic that no longer exists.** It is kept only to record what the
mechanic was and why it is going, so the reasoning is not lost and not reinvented.
`organicsUpkeep`, the shortfall calc, the starvation bleed, the workforce rebalance
and their tests all come out. The "all colonies can feed themselves" property the
divisor was tuned for is not wanted: the design replaces "everyone pays a tax"
with "harsh types cannot produce food at all".

```
organicsUpkeep = ceil(population / 10)   // REMOVED
```

Charged **after** production lands, which is what makes the equilibrium work: a
colony that farms enough organics stands still instead of spiralling. At 1.0x
multipliers a colony breaks even with **one tenth of its population on organics**,
so the workforce share is a real decision. A Lava world (0.2x organics) needs
five times that share, or it must import food at 8 credits a unit — barren-world
colonies are expensive to run by design.

When a colony cannot cover its upkeep it loses
`min(shortfall x divisor, 2% of population)`, with a floor of one colonist so
small colonies still finish dying (see Code Audit #7). Measured from 10,000
colonists: 10% gone in 3 minutes, half in 17, nine tenths in an hour, and zero at
about 170 minutes. The first minutes are the window in which delivering organics
saves the colony. The workforce is rebalanced proportionally after a loss, so
track counts can never sum to more than the population left to fill them.

> Two numbers in the first draft of this were wrong. The divisor said 1 per 100
> when the code uses 1 per 10. And the starvation comment claimed 2% "kills a
> full colony in 50 ticks", which is not how it behaves: the cap applies to the
> *remaining* population, so the bleed is asymptotic and a 1,000-colony colony
> needs ~300 ticks, not 50. Comment and code now carry the measured figures.

---

## Homeworld System

> **Status: substantially implemented**, and ahead of this document. See Code
> Audit for what replaced the original design.

### Universe Generation
- One **primary** homeworld per major faction (duran/vinari/trader) plus one
  cold-standby **backup**, in random non-FedSpace sectors
  (`universe_generator.dart:1219`).
- Type is drawn from a faction-weighted list:
  - **Duran**: Lava / Toxic / Barren / Moon
  - **Vinari**: Terran / Jungle / Ocean
  - **Trader**: Terran / Desert / Moon
- Homeworld names are hard-coded per faction (Kravos / Celestara / Vionis).
  Backups are suffixed `(Reserve)` so two worlds never share a display name.
- Pirates get no homeworld (distributed threat). FedSpace planets stay unowned.

### Homeworld Properties (as generated)
Level 4, defense level 4, shield 8,000, hull 20,000, `maxStorage` 250,000,
population 10,000-15,000 split across the four tracks (3k/3k/2k/2k), starting
stores 5,000/3,000/2,000/500, `spawnInterval` 10 ticks, `productionTimer` seeded
to 8 so the first ship arrives promptly, `scanned: true`.

Note: the seeded `requiredColonists` of 500,000 is unreachable for every Duran
homeworld type (see Code Audit #3). Harmless while NPC planets never level, but
it should be corrected when levelling grants are implemented.

### NPC Ship Spawning — implemented
Two independent paths, both in `GameTickService`:

1. **Floor recovery** (`RepopulationService.repopulate`) — a faction below its
   floor (3 ships for majors, 2 for pirates) gets at most **one** replacement per
   tick, launched from its controlled homeworld sector. Pirates fall back to a
   random sector, since they hold outposts rather than homeworlds. Small floors
   plus one-per-tick make this recovery rather than a flood.
2. **Yard production** (`RepopulationService.produce`) — each controlled, intact
   homeworld counts `productionTimer` down; at zero it rolls out one ship and
   resets to `spawnInterval`. At or above the faction's production cap (8/8/8,
   pirates 4) the yards stand down, though the timer still resets — production
   is a cadence, not a queue.

### Control gating — implemented, and stricter than the original design
- **Captured yards run cold.** A homeworld whose `owner` is another faction
  produces nothing. Losing control means losing regeneration; **recapture
  restores it**, so a faction is not permanently extinguished by a raid.
- **Primaries beat backups.** A live primary idles its backup. Capitals move
  back rather than duplicating, so a faction never double-spawns.
- **Destroyed worlds are excluded** — the planet-killer path sets `isDestroyed`,
  and such a world never counts for either path.
- **Unowned homeworlds still produce** (frontier), which is deliberate.

### Homeworld Destruction
`Planet.destroy()` (`planet.dart:113`) zeroes the colony, stores, defenses,
homeworld status, ownership, and spawn timers, and sets `isDestroyed` so nothing
re-attaches regeneration to it. Stale timers are zeroed deliberately, so a future
reader who forgets the `isDestroyed` check cannot schedule ghost spawns.

**The trigger is not built yet** — this is the planet-killer path with nothing
pointed at it, since invasion combat (Phase H) does not exist. `destroy()` is
currently only reachable from code and tests.

### Backup Homeworld Claiming — not implemented
The model flag, generator seeding, and control-gating logic all exist; what is
missing is an NPC that *chooses* to claim an unclaimed planet as a new capital.
See Proposed Mechanics.

---

## Planet UI

### Navigation
- **Planets** is its own tab button on the left nav bar/rail, directly below Ports.
- Tab index in `GameShell`: 6 (after Settings) or re-sequenced.
- Shows planet in current sector, or "No planet in this sector."

### Entry Point
- "Land on Planet" button on tactical map / sector interaction panel.
- Only visible when `sector.planet != null` — **becomes `sector.planets.isNotEmpty`**
  once sectors hold more than one world.
- If the planet is not scanned, the button scans it; once scanned it opens the
  planet screen.
- **Scanning costs energy, not turns** — this document predates the B1
  turn -> energy migration. Two paths exist and they are not equivalent: the
  sector panel's quick scan costs 1 energy, the planet tab's full scan costs 4
  and additionally grants +1 standing with the owner. Both set the same `scanned`
  flag and reveal the same detail, which makes the expensive path strictly
  dominated — see Code Audit #4.

### Planet Screen Layout

**Unscanned:**
```
┌─────────────────────────────────────┐
│  [Scan Planet] (4 energy)             │
│  Planet detected in this sector.    │
│  Requires scan to identify.         │
└─────────────────────────────────────┘
```

**Scanned, unowned:**
```
┌─────────────────────────────────────┐
│  Planet: Xandor                     │
│  Type: Terran · Atm: N2-O2          │
│  Status: Unclaimed                  │
├─────────────────────────────────────┤
│  [Planet image]                     │
├─────────────────────────────────────┤
│  Resource Potential:                │
│  Minerals ██████░░ 1.0×             │
│  Organics ████████ 1.0×             │
│  Industrial ████████░ 1.2×           │
├─────────────────────────────────────┤
│  [Claim] [Attack] [Leave]           │
└─────────────────────────────────────┘
```

**Scanned, owned (by player or faction):**
```
┌─────────────────────────────────────┐
│  Planet: Xandor                     │
│  Type: Terran · Atm: N2-O2          │
│  Owner: Duran Hegemony ★ HOMEWORLD  │
│  Level: 4 Fortified Colony           │
├─────────────────────────────────────┤
│  [Planet image]                     │
├─────────────────────────────────────┤
│  Population: 2,400 / ∞              │
│  ├─ Minerals:  1,200 ██████░░       │
│  ├─ Organics:    600 ███░░░░░       │
│  ├─ Industrial:  200 █░░░░░░░       │
│  └─ Drones:      800 ████░░░░       │
│  Storage: 24,700 / 250,000          │
├─────────────────────────────────────┤
│  Production / tick:                 │
│  Minerals: 240 · Organics: 120      │
│  Industrial: 40 · Drones: 16        │
├─────────────────────────────────────┤
│  Defense Level: ████░ 4             │
│  Shield: ██████████ 8000/8000       │
│  Hull:   ██████████ 20000/20000     │
├─────────────────────────────────────┤
│  [Manage] [Attack] [Leave]          │
└─────────────────────────────────────┘
```

### The Transfers Panel — BOTH BUTTONS NEED REWRITING

**The `Dep` and `Wdr` buttons are not transfers and do not behave as described
anywhere in this document.** `Dep` debits credits and energy and then credits the
goods into the planet's store without ever touching `player.cargo`; `Wdr` does the
reverse and does not charge energy at all. Neither is bounded by `maxCargo`. They
are credit<->goods converters wearing the label of a haul, and they are why
`_transferPrices` exists at all.

Per the Economy Redesign, the panel becomes three distinct verbs:

1. **`Dep`** — cargo -> planet store. No cost. Bounded by what is in the hold.
2. **`Wdr`** — planet store -> cargo. No cost, **bounded by `maxCargo`**. This is
   the number that makes a hauler worth flying.
3. **Market** — buy at a port into cargo, or sell from cargo for credits. A third
   verb, with its own panel, and the only one that moves credits.

`_transferPrices` is deleted rather than retuned. `port_trade_view.dart` is the
pattern to copy — it already moves units into `player.cargo` and clamps to
`maxCargo` correctly.

Drones get `Dep`/`Wdr` so they can reach a hold and be fielded, but no market row
and no cash value.

Only the colonists row is unusual, and deliberately so:

- Its price is **not** a flat rate. It is a function of distance from the
  faction's homeworld, and the row used to display the whole explanation
  inline — `5.4K / 200.0K  405cr · 9 hops from Vionis`. That is a sentence in a
  number cell, and at phone width the meaningful half ellipsised away.
- So the row now shows **just the price**, and an amber info bubble beside the
  "Colonists" label carries the explanation: the source world, the hop count,
  and the per-shipment energy cost. Hover on desktop, tap on mobile.
- The bubble also carries the exile-rate line when the faction has no capital,
  including what to do about it ("Recapture your homeworld"). That case is
  currently unreachable — losing a homeworld needs invasion, which does not exist
  — but the tooltip is where a player will look when it becomes reachable.
- Bulk goods are not distance-priced, and the row does not pretend otherwise.

Guarded by `test/planet_colony_ui_test.dart`, which asserts the price cell is
bare, the bubble exists, and the message covers source, distance, fuel and exile.

### Planet Management Screen (for owned planets)
- **Colonists tab** — Assign colonists to production tracks via sliders
- **Resources tab** — View stored resources, transfer to/from ship cargo
- **Construction tab** — Show level progress, deposit resources toward next level
- **Defense tab** — View/upgrade defenses (auto-upgrades on level up)
- **Rename tab** — Rename the planet

## Invasion / Planet Combat

- Same turn-based flow as `PortCombatScreen`.
- Planet has `shield`, `maxShield`, `hull`, `maxHull`, `defenseLevel`.
- Planet weapons fire back with damage scaling by defense level.
- Surrender when hull < 20%.
- Outcomes:
  1. **Destroy** — hull reaches 0, homeworld destroyed, planet becomes unowned barren
  2. **Claim** — attacker takes ownership
  3. **Plunder** — steal resources without destroying
- Faction standing impact: destroying a homeworld is a major reputation hit.

## Planet Image Pool

Assets in `assets/images/planets/`. Each type has 3 images, picked randomly at universe gen.

| Type        | Assets |
|-------------|--------|
| Terran      | `Terran_World_1.gif`, `Terran_World_2.gif`, `Terran_World_3.gif` |
| Jungle      | `Jungle_World_1.gif`, `Jungle_World_2.gif`, `Jungle_World_3.gif` |
| Desert      | `Desert_World_1.gif`, `Desert_World_2.gif`, `Desert_World_3.gif` |
| Ocean       | `Ocean_World_1.gif`, `Ocean_World_2.gif`, `Ocean_World_3.gif` |
| Ice         | `Ice_World_1.gif`, `Ice_World_2.gif`, `Ice_world_3.gif` |
| Lava        | `Lava_World_1.gif`, `Lava_World_2.gif`, `Lava_World_3.gif` |
| Gas Giant   | `Gas_Giant_1.gif`, `Gas_Giant_2.gif`, `Gas_Giant_3.gif` |
| Moon        | `Moon_1.gif`, `Moon_2.gif`, `Moon_3.gif` |
| Barren      | `Moon_1.gif`, `Moon_2.gif`, `Moon_3.gif` (reuses Moon pool) |
| Toxic       | `Toxic_World_1.gif`, `Toxic_World_2.gif`, `Toxic_World_3.gif` |
| Unknown     | `Unknown_World_1.gif`, `Unknown_World_2.gif`, `Unknown_World_3.gif` |

> **Case note:** `Ice_world_3.gif` has lowercase `w`. Account for this in asset loading.

Planet names drawn from 100-name pool (user-provided list) instead of current `_planetName()`.

## Planet Name Pool

100 names: Xandor, Elara, Sygnara, Voryn, Celestara, Rynara, Thalys, Orwyn, Glavara, Zephyron, Tyria, Axion, Nebulon, Valthor, Saronis, Elyx, Corvus, Zantara, Oberyn, Krythos, Selara, Phaeton, Ecliptor, Astralis, Vionis, Nexilon, Caelum, Sypher, Galeth, Xeridia, Lumora, Tychon, Velara, Myriad, Arctura, Novex, Zephyris, Calyx, Orithyia, Sylvara, Aetherion, Draconis, Quasys, Solara, Erebos, Thalara, Kryon, Vylis, Nexara, Zorath, Ilythar, Vexalon, Synthera, Auralis, Zypheron, Tarsys, Elion, Gravara, Nyxara, Corynth, Xylara, Praxon, Vionara, Zelthar, Astron, Kytheris, Sylion, Eryndor, Valthys, Orythia, Nebula, Xerath, Tylara, Cygnara, Aethys, Zorwyn, Vexara, Sylthara, Klyon, Ecthara, Rynther, Galara, Zyron, Velithor, Naxara, Thalith, Orionis, Clythera, Voryth, Aelara, Xynara, Krylara, Zentara, Elythar, Sovara, Nyxion, Tethys, Vionth, Astrara.

## Proposed Mechanics

Ranked by value against effort. The first two are what stand between the planet
screen and being truthful.

### 1. Make production real, and pay upkeep — DONE

Shipped. The formula moved onto `Planet.produce` as the single source, read by
both the tick and the screen, and upkeep is charged after production so a
self-sufficient colony is stable. Zero measured waste across all ten types over
1,000 ticks.

The failure mode chosen was **starvation** over a clamp to zero: an un-fed
colony bleeds and eventually dies out. A clamp would have made overpopulation
consequence-free, and revolt was judged too much for the first slice. Revolt
remains the better long-term design and is listed as item 9 below.

### 2. Give levels something to grant — DONE

Storage scales with level (1.00x to 6.50x), the development multiplier gives a
shallow 1.00x to 2.00x, the population ceiling scales with the tier, and
**defence, armour and shields are applied on build completion** from
`levelDefense` / `levelArmour` / `levelShield`. Builds are timed in game ticks and
the cost table is re-derived against the distance-priced colonist economy.

A level-6 Citadel now defends as well as a level-6 Citadel should, and every one
of the ten types can reach every tier.

### 3. Planet-to-port supply chains — the sink already exists, the UI was the bug

**The market brake is already built and correctly sized, and the UI was hiding
it.** Each port has a finite `maxDemand` per commodity that refills over a
24-hour cycle, and port storage upgrades multiply it by 1.5x per level up to
level 10, costing 100,000 credits and doubling each time. Measured across a
100-sector universe: **~1.24M minerals of demand per day** across 25 buying
ports, worth ~52M credits at mid-range.

So a colony cannot simply be converted into money — there has to be somewhere
willing to buy it, and a player earns their way into bigger markets by upgrading
ports rather than by producing more. That is the intended progression and it was
already correct.

What was broken: buy and sell moved **exactly one unit per tap**, so absorbing a
port's ~78,000 minerals of demand took 78,000 clicks. A `UNITS/TAP` selector
(1 / 10 / 100 / 1K / MAX) now makes the existing sink reachable, and the Ports
Guide documents the mechanic. The balance needed no change; the control surface
did.

**Superseded by measurement.** The 1.24M/day figure was measured at the *old*
flat colonist caps, before the population cap was derived from the Citadel level.
Re-measured against current code: a single 1M-citadel world produces **27.6M
minerals a day** — 60x the entire galaxy's mineral demand — and is worth **10.2x
every port's combined treasury** in a single day. The market brake is therefore
**no longer correctly sized**; it was correctly sized for a production range that
no longer exists. The ~60% of ports that are unowned never upgrade their storage
level at all, so the sink cannot grow.

Still to do: per-commodity port counterparties, colonies actively feeding a port
(moving port prices directly), convoy and route mechanics, NPC factions competing
for the same finite demand, and the exchange as the unlimited valve.

Planets currently compete with nothing, because they produce nothing. Once they
produce, letting a nearby port draw on a claimed planet's stores gives the
eight-commodity economy a second supply source that is not a port simply
minting stock against the player's credit, and it gives distance a reason to
matter.

### 4. Colonist transport — MOSTLY DONE

Distance-priced credits from the faction's own homeworld, plus a per-shipment
energy cost, are shipped. What remains is the *physical* half: colonists as
cargo units in ship holds, and a load/unload action at the homeworld, so cargo
capacity becomes a constraint as well as a cost.

### 5. Genesis Torpedo — MEDIUM, and no longer "small"

**Re-rated on two grounds.**

First, it was always going to be the keystone rather than a nicety: the whole
harsh-type design depends on the player being able to *plant* a complement rather
than only buy one. Without it, "Lava cannot make organics" is a permanent external
dependency; with it, the problem is the player's to solve.

Second, it is the **first credit sink in the game that scales and never
saturates.** Hardware all has to be bought once; a torpedo can be fired forever,
because the thing it buys is permanent, non-transferable, and there is always
another empty sector. That matters more now that credits are known to inflate 72x
faster than anything can absorb them.

Requires the Atomic Detonator to be worth anything — with a random type, the
detonate-and-retry loop is the mechanic, and it is what makes the torpedo a
*sink* rather than a *purchase*. Also carries a 24h collision roll when a sector
is over-stacked past its cap. See the Economy Redesign.

### 6. Invasion combat — LARGE

`PortCombatScreen` is the pattern and the model already carries shield/hull/
defenseLevel. Needed for ownership to have stakes, and it is the only thing that
can call `Planet.destroy()`, which is currently unreachable from gameplay.

### 7. Scanner-module auto-scan — SMALL

The module already exists in `hardware_data.dart` and is unwired. Wiring it makes
it a real purchase instead of a stat line, and it interacts with Code Audit #4:
if the module scans for free on entry, the paid 4-energy full scan has a purpose
again.

### 8. NPC colonisation — MEDIUM

The control-gating rules all exist in `RepopulationService`. This only needs an
NPC goal: a faction with no controlled homeworld, whose ship visits an unclaimed
planet, claims it as a capital. Closes Design Goal 8's actual intent.

### 9. Colony unrest — MOOT, for now

This was proposed to make upkeep a *state* rather than merely a punishment. With
upkeep and starvation removed in favour of production gaps, there is no recurring
shortfall to revolt about — a harsh world is not starving, it is *incapable*, and
the response is an import, not an uprising.

Worth revisiting only if drone maintenance (the one remaining recurring sink)
turns out to bite. A colony whose drone yards run dry revolting is a different
and better version of this idea than a colony that simply cannot farm.

---

## Implementation Phases

Status as of the 2026-09-28 audit. Phases were originally ordered A-I; the
audit's findings reorder the *remaining* work, because production (E) and level
grants (F) are what make the existing screen honest, and neither is large.

### DONE
- **Phase E: Planet Production (Tick-Based)** — production tick, storage ceiling,
  organic upkeep, starvation with a real failure state, and the workforce
  rebalance. `PlanetProductionService` runs it once per tick.
  `test/planet_production_test.dart` (28 tests) and `test/planet_colony_ui_test.dart`
  (13 tests) guard it, including a displayed-rate-equals-applied-rate check so the
  original defect cannot return.
- **Phase E-adjacent: Workforce assignment** — steppers on all four tracks plus
  an implicit reserve, owner-only, with a starvation warning on the colony card.
  Shipped *with* production rather than after it: without it a claimed planet has
  nobody on any track and produces nothing, so production alone was unreachable
  for a player.
- **Phase A: Model Replacement** — `planetType` String replaced `PlanetClass`;
  enhanced model, `toJson`/`fromJson`, type config maps, `Sector.planetType`
  removed.
- **Phase B: Universe Generator Updates** — weighted 10-type placement,
  atmospheres, random efficiency, starting stores, random image, plus homeworld
  and backup-homeworld placement.
- **Phase C: Scanning & Discovery (partial)** — `scanned` flag, scan actions,
  energy cost, persistence. *Auto-scan on scanner module not wired.*
- **Phase G: Planet UI** — planet tab, screen, scan, claim, transfers, level-up,
  map markers, land action.
- **Phase I: NPC Repopulation (partial)** — homeworld ship spawning, floor
  recovery, control gating, production caps, hero ships, backup idling.
  *Backup claiming by AI not built.*

### NOT BUILT
- **Phase D: Colonist Transport** — **partially done.** Distance-priced credits
  plus per-shipment energy is shipped. Still to do: colonists as physical cargo in
  ship holds, and a Terra-side load/unload action, so cargo capacity becomes a
  constraint as well as a cost.
- ~~**Phase F: Planet Levels (grants)**~~ — **DONE.** Defence, armour and shield
  grants now come from per-tier tables on build completion (a level-6 Citadel no
  longer defends like an Outpost); the population cap scales with the tier so no
  world type is a dead end; the cost table is re-derived against the
  distance-priced colonist economy; and `levelProgress` is gone, replaced by a
  real `constructionTicksRemaining` countdown.
- **Phase H: Planet Combat** — not started. One of **two** paths to
  `Planet.destroy()`; the Atomic Detonator lands long before it.
- **Multi-planet sectors** — not started, and now the **top priority**.
  `Sector.planet` is `Planet?`; three worlds per sector requires a list, a
  per-planet stable id, and a save migration. See the Economy Redesign.
- **Per-type daily production caps** — not started. The classic mechanic, and the
  missing half of the storage work: storage bounds what a colony can *hold*, a cap
  bounds what it can *extract*.
- **Genesis Torpedo + Atomic Detonator** — not started, plus the 24h collision
  roll for over-stacking a sector past its cap.
- **Resource market** — not started. Per-commodity port counterparties with `(i)`
  bubbles, then the exchange as an unlimited pressure valve at a spread that keeps
  ports strictly better in both directions.

### Recommended order for what remains
1. ~~**E** — production + upkeep + storage ceiling.~~ **DONE.**
2. ~~Colonist assignment UI.~~ **DONE**, shipped alongside E rather than after it.
3. ~~Storage rework — per-commodity, no waste.~~ **DONE.**
4. ~~Distance-priced per-faction colonist supply.~~ **DONE.**
5. ~~**F** — defence scaling with level, and the colonist cost/cap
   reconciliation.~~ **DONE.** Level grants, a level-scaled cap, re-derived
   costs, and a per-tick build timer. "Levelling pays for itself" is now true.
6. **The Economy Redesign order supersedes this list** — see *Revised order of
   work*. In short: multi-planet sectors first (it is a model refactor and eight
   files read `sector.planet`), then the harsh-type gaps and the `Dep`/`Wdr` cargo
   fix, then the torpedo, then the market, and the exchange **last**.
7. Scanner auto-scan, NPC colonisation.
8. **H** — invasion, which makes homeworld capture a real growth denial and gives
   ownership stakes. Note that `destroy()` no longer waits for it: the Atomic
   Detonator reaches it years earlier.

---

## References

- `lib/data/models/planet.dart` — the model (phase A landed; no longer
  pending replacement)
- `lib/data/models/faction.dart` — FactionClass enum, faction lore with homeworld planet names
- `lib/data/models/sector.dart` — Sector with a structured `Planet?`; `planetType`
  string already removed. **The 1:1 `Planet?` is the blocker for the top-priority
  change**; eight files read it and a per-planet id becomes mandatory with it.
- `lib/data/models/universe_generator.dart` — phase 8 planet creation;
  `_createPlanet` (~1280) and `_setupHomeworld` (~1219)
- `lib/services/repopulation_service.dart` — homeworld floors, production caps,
  control gating, hero ships (implemented; ahead of this document)
- `lib/services/game_tick_service.dart` — 30s tick; ship spawning and colony
  production are both wired (`tick_repopulate`, `tick_produce`,
  `tick_colony_production`)
- `lib/widgets/port_combat_screen.dart` — reusable combat pattern for invasions
- `lib/screens/port_screen.dart` — pattern for planet screen UI
- `lib/screens/port_management_screen.dart` — pattern for planet management screen
- `lib/widgets/sector_view_widgets/sector_interaction_panel.dart` — where "Land on Planet" / "Scan Planet" buttons go
- `lib/data/models/ship_equipment_types.dart` — for scanner module
- `lib/services/energy_service.dart` — `planetScanCost` (4) vs `quickScanCost` (1)
- `lib/screens/planet_screen.dart` — colony card + workforce steppers, transfer-in
  write, level-up UI, starvation warning, attack stub
- `lib/services/planet_production_service.dart` — the per-tick colony pass
  (production, upkeep and starvation; the upkeep and starvation parts are being
  removed per the Economy Redesign)
- `lib/services/colonist_supply.dart` — per-faction colonist source, distance
  pricing, per-shipment energy; delegates source resolution to
  `RepopulationService.homeworldSectors` so the two cannot disagree
- `lib/screens/planets_knowledge_base.dart` — the Computer -> Planet Guide, with
  its tables generated from the model
- `test/planet_production_test.dart`, `test/planet_colony_ui_test.dart`,
  `test/colonist_supply_test.dart`, `test/port_demand_test.dart`,
  `test/planet_test.dart`, `test/planet_construction_test.dart`,
  `test/planets_knowledge_base_test.dart` — the planet guards
- `test/planet_supply_test.dart` — colony supply: the share-of-output invariant
  across three population scales, the cross-commodity fallback, the shipment pool
  counting as goods, and that an empty colony loses nobody
- `test/planet_cargo_transfer_test.dart` — the `Unload`/`Load` hauls, including
  that `maxCargo` is a hard bound and that no credits change hands
- `test/planet_construction_persistence_test.dart` — a build survives leaving the
  screen, and its progress is visible without leaving
- `test/multi_planet_sector_test.dart` — three worlds per sector, the per-planet
  id, and that every service reads past slot 0
- `lib/widgets/port_trade_view.dart` — the **correct** cargo pattern to copy for
  planet `Dep`/`Wdr`: it moves units into `player.cargo` and respects `maxCargo`,
  which is exactly what the planet screen does not do
- `lib/widgets/sector_view_widgets/sector_interaction_panel.dart` — second scan
  path (~203) and the planet detail dialog
