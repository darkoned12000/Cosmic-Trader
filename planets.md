# Planets — Design & Implementation Plan

## Current State (audited 2026-09-29 against `main` + planet work)

This section was substantially out of date in both directions: it listed work that
ships as missing, and its balance tables disagreed with the code by an order of
magnitude. Corrected below, with the audit that produced it in the next section.

### What is built and working

- **Model** (`lib/data/models/planet.dart`): **10** planet types with atmosphere,
  production multipliers, colonist caps, and image pools. Ownership, homeworld
  status, colonists per track, storage, Citadel level 1-6, defense
  (level/shield/hull), NPC spawn timers, and a `scanned` flag.

  > This said **11**, which was true before Gas Giant was removed. Ten is the
  > shipped count: Terran, Jungle, Mountain, Desert, Ocean, Ice, Lava, Moon,
  > Barren, Toxic.
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
- **Scanning**: **one** verb, `ScanService` — `EnergyService.scanCost` (1 energy),
  set the flag, +1 standing with the owner, persist, log. Both the planet tab and
  the sector panel call it, so the two cannot charge differently for the same
  action.

  > This said "two paths… Planet tab costs 4 energy and grants +1 standing; the
  > sector panel costs 1 energy and grants nothing". Both halves were stale: the
  > two verbs were unified into one (Code Audit #3) and the standing is granted on
  > **both** paths, because leaving it on one would have inverted the dominance
  > rather than removed it. It also contradicted this document 200 lines further
  > down, in the Code Audit that fixed it.
- **UI**: planet tab, header + image, resources/defense cards, production
  readout, **cargo** transfers in both directions (`Unload`/`Load` — free, and
  bounded by free hold space; they used to be a credits-to-goods purchase that
  never touched `player.cargo`), claim, and level-up.
- **Maps**: planet markers on the galaxy map and tactical map, with
  type/homeworld/owner status; a land/scan action in the sector panel.

### Shipped since the first audit

- **Per-tick colony production** — `Planet.produce()` applies the yield the
  screen displays, clamped to storage, driven by
  `PlanetProductionService.process` once per tick. The formula now lives on the
  model in one place; the screen and the tick both read it, so they cannot
  disagree.
- ~~**Organics upkeep**~~ — **REMOVED.** A per-capita tax is the wrong sink; it
  makes harsh worlds *worse Terran worlds*. See *DECISION — harsh types cannot
  produce a commodity at all*.
- ~~**Starvation**~~ — **REMOVED** along with it, and replaced by **colony
  supply**: a bill every 2,880 ticks for 8% of the colony's own daily output,
  drawn at random from the three consumables. An unpaid bill is *reported* and
  nothing else happens. No population is ever lost.
- **Workforce assignment UI** — steppers on all four tracks plus an implicit
  reserve, owner-only. This was a hard prerequisite: without it a claimed planet
  has no colonists on any track and produces nothing, because only the generator
  ever set the track counts.
- **A development multiplier by level** (1.00-2.00x), deliberately shallow.
- **Per-commodity, per-type storage with nothing wasted** — see the Storage
  section. A full store spills into a shipment pool rather than being discarded.
- **A live planet screen** — a 1s poll **re-reads from disk** and repaints when
  the tick has changed the colony, so production is visible without leaving the
  tab. It deliberately does *not* fingerprint its own objects: every screen holds
  its own copy of the universe, so fingerprinting would report "unchanged" for a
  colony the tick had already altered.
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
- **Scanner-module auto-scan**: not started, and **there is no module to wire.**
  This said "the module exists in `hardware_data.dart` and is unwired"; it does
  not exist. The eight modules are Warp Core Booster, Targeting Computer, Cargo
  Expansion Kit, Solar Array, Auto-Repair System, Shield Capacitor, Cloak
  Generator and Afterburner — no Scanner. The feature therefore needs the module
  **created** first (a catalogue entry, a stat line, a level ladder) and then
  wired, which is materially more than "wire it up". See *Proposed Mechanics 7*.
- **Buy/sell from the planet**: **shipped as T1-T5.** Bulk orders are placed
  from Transfers (behind the Settings → Modules `Planet Trading` toggle),
  filled by port freighters over hops-scaled runs against live port prices,
  with per-run countdown rows, cancellation with refunds, and sell revenue
  landing in the world's treasury for withdrawal. What remains is T6 (retire
  `Collect`), T7 (failure rolls) and T8 (convoy + insurance).
- **Playtest fix (T5): run size decoupled from cadence.** A run used to
  deliver `ticksPerRun` units, so a 3.7k order at 6 ticks/run took 617 runs
  and 31 hours — distance set the shipment size, not just the rhythm. Runs
  now carry the freighter hold (5,000) and one tap is one order id: split
  shares group into a single row with a single Cancel, and legacy jobs keep
  their quoted pacing (`unitsPerRun` defaults to `ticksPerRun`).
- **External review response (T5): three fixed, one already fixed.**
  `planAndCreate` deleted (it spent planet goods without reserving the port —
  value from nothing; `createOrder` is the one seam); sell escrow now records
  what the pool actually held and releases exactly that, unclamped, so
  reserve-then-cancel on a cash-poor port cannot mint; model clamps
  `ticksPerRun`/`unitsPerRun` ≥ 1 in the constructor so a save edit cannot
  delete the cadence; withdrawal settle starts a 10-poll digest watch that
  re-guards against a stale pass landing after the confirming poll.
  The fourth claim (deposit draining the production remainder) was already
  fixed: `_cap` reads pure `perTickFor`, with the old bug described in its
  own comment and guarded in `planet_production_test.dart`.
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

**Decisions still open** and marked `OPEN` in place: whether a Genesis Torpedo
offers type *profiles* or pure random, whether drone maintenance is worth
building, and whether ports should grow on their own. The exchange is no longer on
this list — it is **parked** pending the trade jobs (*DECISION — resource trade as
jobs*), because those may remove the need for it entirely.

### The measurements that drove everything

All taken against a default generated universe (`seed 7`, 24 ports).

| Measurement | Value |
|---|---|
| Total treasury, every port in the galaxy | 455,372,804 cr |
| Daily output of **one** 1M-population Citadel | **4,658,305,000 cr** |
| One colony-day as a multiple of the whole galaxy's treasury | **10.2x** |
| Galaxy-wide daily mineral demand (the absorption budget) | 462,749 units — **superseded, see below** |
| Daily mineral output of a **50,000** level-4 colony | **780,000 units** |
| Daily mineral output of a 1M level-6 colony | **27,600,000 units** (60x) |
| Everything purchasable in the game (270 hardware items + 12 hulls + port storage ladder) | **65.0B cr** |
| Citadel-days to buy the entire game | **72** — **superseded, see below** |

**These figures were measured before two changes that moved them**, and this
document quoted all three numbers in three different sections without saying so,
which is worse than having one stale number. Reconciled:

| quantity | the figure | what it is |
|---|---|---|
| Galaxy-wide daily mineral demand | **462,749 units** | measured at the *old flat colonist caps*, before the cap was derived from Citadel level |
| — the same quantity, universe-sized | **~1.24M units/day** | 25 buying ports in a 100-sector universe |
| — the same quantity, galaxy-wide, all commodities | **~22.97M units/day** | 260 sampled ports; a median port absorbs ~83,700 units/day |
| Everything purchasable in the game | **65.0B cr** | 270 hardware items + 12 hulls + the port storage ladder |

The spread is not a contradiction, it is three universes and three scopes. What
matters for any balance argument is the **ratio**: a single 1M-citadel world
produces 27.6M minerals/day, so it is ~60x the whole galaxy's appetite even at the
larger figure. The market brake is therefore undersized whichever scope you
measure, and the "~60% of ports are unowned and never grow" note below is the
real reason it cannot grow on its own.

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

**PARTLY OPEN — and the mechanism as first written here was wrong.** It said
"nothing restores it except an NPC happening to buy there". A **player** buying
restores it too, and that is the ordinary case:
`port_trade_view.dart:219` does `portCredits + transactionValue` when the player
buys, and `:264` does `portCredits - transactionValue` (clamped at 0) when the
player sells. `Port.regenTick` moves supply and demand only.

So the reservoir does refill, through the same screen that drains it — a port
whose goods anyone buys recovers, and the `cashRatio` valve (`portCredits /
desiredCredits`, feeding `priceMultiplier` across 0.55x–2.0x) works as intended
for a port that sees traffic in both directions.

What remains genuinely open is the case the correction does **not** cover: a port
that only ever *sells* to the player. Every purchase drains it, nothing puts
credits back except a player buying *from* it, and a port whose entire stock is
bought out has nothing left to sell — so it can pin at the floor with no
automatic path back. Whether that needs a fix depends on whether ports should
recover on their own or whether "buying a port dry is permanent until someone
sells to it" is the intended market pressure. **Undecided**, and the first version
of this note could not have informed the decision because it described the wrong
mechanism.

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

Buying and selling are a **third verb** — and as of *DECISION — resource trade as
jobs* they no longer require flying, because the planet screen can place an order
that real ports fill over time. Drones have no market row and no cash value, but
they *can* be loaded so they can be fielded (below).

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

**Gas Giant is removed from the game.** It is not in this table because it was
never a harsh world — it was a *dead* one, which is a different and worse thing.
Its ratios are N-A on **all three** products, so it produced nothing at any
staffing and at any Citadel level, while still charging real resources for each
build (`ore: 1200, organics: 400, equipment: 2500` for level 2) and holding one
of three `planetsPerSector` slots. It had 10,000 of storage per commodity, so you
could unload into it and watch the goods sit there.

It was **1 of 20 slots** in the generator's weighted type table — roughly one
generated world in twenty — and **1 in 11** of a Genesis Torpedo roll. So it was
not an exotic edge case to be met once; it was a standing tax on every universe,
paid in a slot you could not use.

**A dead world is worse than a bad one.** The whole detonate-and-retry loop rests
on a player being able to *look* at a world and judge it. There is nothing to
look at in an inert one, so the item built to clear a mistake had nothing to
clear. Removal, rather than a yield, because the argument for keeping it was
authentic source lore and the cost was a feature nobody asked for.

Note the two tables disagreed about it, and **both suites were green**:
`TypeMultipliers` gave it 0.6 organics (so one test asserted it grew food) while
the class spec gave it N-A everywhere (so another asserted it produced nothing).
Same type, two answers. That is now impossible to reintroduce — see the
"no class is a zero-output dead end" guard in `test/planet_class_test.dart`.

Verified safe: every output is `colonists x mult x scale` and **nothing in the
model divides by a type multiplier**, so a 0 multiplier yields 0 output rather than
exploding.

**Upkeep and starvation are both removed**, and **colony supply** replaces them.
`organicsUpkeep`, `organicsShortfall`, `colonistsLost` and `isStarving` are gone
from `planet.dart`, `planet_production_service.dart`, `planet_screen.dart`, the
Planet Guide, and three test files.

#### Colony supply — DONE

Every `Planet.supplyInterval` ticks — **one game day, 2,880** — a colony is billed
for the goods its people need: `supplyShareOfOutput` (8%) of the output it
produces in those same 2,880 ticks, drawn at random from minerals, organics or
industrial.

> **This paragraph said "(10) ticks" and "one tick's own output", and both were
> wrong** — the interval by 288x and the base by 2,880x. It is the same defect
> that was found and fixed in the Planet Guide, still living here: the code is
> `Planet.supplyInterval = PlanetClock.ticksPerDay` and the bill is a share of
> `outputPerDayFor`, summed across the three tracks. A doc quoting a number the
> model does not use is worse than no number, and this one sat in a section
> headed **DONE**.

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
surplus is unbounded while deficit is bounded. That is what sizes the trade
network: what a self-sufficient empire needs is somewhere to *sell* what it is
best at, which is exactly what a sell job does.

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
then a **collision roll every game day (2,880 ticks)**: if it comes up bad,
planets collide and
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
sector raises an unmissable warning and then a **game-day gravity check** (2,880
ticks); a bad
roll destroys a **pair** — two bodies meeting is the fiction, and losing a pair
makes over-stacking a real gamble rather than a slow tax. Hard-blocking it would
remove the torpedo's only offensive use and make the detonator pointless: a
capacity limit can be waited out, a hazard has to be answered. It is also how
players attacked a target's *economy* rather than their hulls.

**The collision roll now counts ticks too — this reverses an earlier decision in
this document, and the reversal is worth recording rather than quietly editing.**

The argument for wall-clock was: construction counts ticks because a build is the
player's own progress and must not complete while they sleep, but a collision is
the opposite — a background hazard *meant* to bite an abandoned sector.

**That argument does not survive this game's clock.** The game is single-player
with local saves, so "abandoned" has no meaning: closing the app stops time
everywhere at once. There is no period during which a sector ages without the
player, so a wall-clock stamp made the hazard the *only* thing in the economy that
advanced while nobody was playing — the same two-clocks defect that was just fixed
on the port side, and it was the last one standing.

So `Sector.destabilisedAtTick` replaces `destabilisedAtMs`, and
`WorldForging.collisionIntervalTicks` is `GameClock.ticksPerDay`. The consequence
is real and worth stating plainly: **an over-stacked sector no longer eats itself
overnight.** It has to be left over-stacked for a game day *of play*, which means
the hazard is answered by returning to the game rather than by sleeping through
it. The 1-in-8 and 1-in-2 odds per world past the cap are unchanged.

**The clock starts the moment the sector goes over the cap, and the player is not
warned.** Two decisions, both corrected after the first implementation:

- *Per sector, not per galaxy.* `Sector.destabilisedAtTick` is stamped by
  `reconcileStability(cap, tick)` at the moment of the crossing, and
  `WorldForging.runDueCollisions` asks only whether that stamp is a game day old.
  A global hour would destroy worlds in a system that had been unstable for three
  minutes. The stamp is set by **every** path that can change the world count,
  including the sweep itself, so it is self-healing: a stamp
  maintained by hand at each call site is a stamp that will eventually disagree
  with the thing it describes, and a wrong stamp is either a sector that never
  rolls or one that rolls when it should not. A surviving check **re-arms** from
  the moment it came due, so the hazard is daily rather than one-shot — otherwise
  a player who survives the first roll has a system that is safe forever.
- *No warning.* The first version raised a red "Unstable orbit" dialog on every
  launch past the cap and logged a warning, on the reasoning that a colony
  destroyed overnight reads as a bug. It fires again on every launch after that,
  and a warning that repeats forever stops being read as information. The rules
  are fixed and known; the player was told once. The collision itself is announced
  loudly in the event log, which is the only notification that matters because it
  is the only one that is news.

**The first version of this rule had no clock attached to it.** `runDailyCollisions`
existed, was correct, was unit-tested, and was called from nowhere in `lib/` —
so over-stacking warned about a hazard that could not happen. `test/gravity_wiring_test.dart`
is a deliberate source scan for exactly that, because no behavioural test of the
rule can notice: the tests call the rule directly, which is how they reach it.

**A full sector is not an over-stacked one.** `isFull(cap)` (`>=`) and
`isOverStacking(cap)` (`>`) are separate predicates doing different jobs — the
first is the pre-launch question, the second is the state the collision roll acts
on. Conflating them described a sector holding exactly its cap as gravitationally
unstable, which is both wrong and the reason a guard passed against a fault.

**`worldSlotsUsed` counts the worlds in the list, and a destroyed world leaves
the list.** This reverses an earlier decision to keep it as a corpse "so it can
still be drawn and argued about". That reasoning did not survive contact with the
game: the corpse stayed in Sector Contents, could be landed on, and could be
**claimed again** — so a detonator freed the slot without destroying anything,
which is the opposite of what the item is for. A destroyed world is now removed
from `sector.planets` outright.

Two consequences worth stating, because both were bugs first:

- `Planet.destroy()` is still called **before** the removal, not instead of it.
  Every screen holds its own copy of the universe, so the instance the detonation
  was fired from is a *different instance* from the one in the list. Removing
  without neutralising would leave that detached copy with its colony intact,
  still producing into a world that no longer exists.
- `isDestroyed` on a world *in the list* is now an invariant violation rather than
  a normal state. It still means something on a detached instance and in legacy
  saves, so `Sector._planetsFromJson` purges corpses on load — otherwise a world
  vaporised before this change would come back from disk as landable.

The detonate-then-re-roll loop is unaffected, and in fact improved: because the
world is gone rather than flagged, its **name** is free again, so the naming
dialog will keep offering the name the player just used.

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
(Terran/Jungle/Ocean/Mountain), **Industrial** (Terran/Desert/Lava/Barren/Toxic),
**Barren-Cold** (Ice/Moon). Three rolls instead of ten, and "I need an ocean
world" becomes a request rather than a numeric grind.

(The profiles were the only place the removed type still had a role, which is a
fair argument that removing it was overdue: a torpedo lottery whose one unusable
outcome was in the recommended profile list.)

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

### DECISION — resource trade as jobs: buy and sell from the planet

**The problem, measured.** A 5 -> 6 Citadel needs **80,000 minerals**
(`levelUpCosts`, verified). A ship with 150 holds needs **533 round trips** to
deliver them. That is not a difficulty setting, it is a wall, and it is the single
largest source of tedium in the game. The same applies in reverse: a colony
producing 27.6M minerals a day cannot be cashed in by flying.

**The mechanic.** The Transfers panel gains **Buy** and **Sell**, alongside the
existing `Unload`/`Load`. They place an **order**, not a haul. The game finds
suitable ports, and over time a series of cargo runs delivers or collects the
goods, with a job status the player can watch — exactly like a colonist shipment,
which is the template (`dispatchColonists` -> `colonistTransitTicks` ->
`advanceColonistTransit`, advanced by the tick, with a progress panel).

**The transaction happens at a real port.** This is the point, and it is what
separates this from the `Collect` button. A job consumes the target port's real
`demand`, pays its real `buyPrices` (which move with `cashRatio`), and moves its
`portCredits`. The port economy therefore *moves* rather than being bypassed — and
it replaces the hardcoded `_shipmentUnitValue` table (minerals 42.5, organics 115,
industrial 230) with a live price. Two prices for the same goods is the defect
that was already fixed once between `Wdr` and `Collect`; this is the third and
last place it exists.

**Explicit cargo runs, not a duration.** A job is `N` runs of hold-size, each
taking `hops`-scaled ticks, and the UI reports `12 runs, 4 to go`. A single
`ticks = volume / rate` delay was considered and rejected: it is a duration
wearing a cargo run's clothes, it makes hold size irrelevant, and it gives the
player nothing to read. Explicit runs also make the job's cost naturally
proportional to volume **and** distance, which is what keeps the hauler honest.

**Orders split across ports, and that is forced rather than chosen.** One port's
`effectiveMaxDemand` is finite and refills over a game day, so an 80,000-mineral
order *cannot* come from one port. The design is constrained by the economy
rather than bolted onto it — which is why it should hold up.

**The port sends its own freighter.** The player's hold and engine are not
involved; the job is a credit-and-time cost. Deliberate for now: it keeps the
feature about removing tedium rather than about ship build. A later revision could
let the player's or an NPC's ships fly the runs, which would open a real mechanic —
convoy losses to pirates, protection contracts, insurance — and make the universe
feel inhabited. **Deferred, and flagged as the interesting direction rather than a
detail.**

**A paid order is a reservation.** If the player has paid for 20,000 minerals,
those minerals are theirs: the job reserves that much of the port's demand at
order time rather than racing other buyers for it. The alternative — re-checking
demand on every run — is more realistic and can strand a job mid-flight, which for
a 1-2 hour delivery is a punishment the player cannot act on. Ports have finite,
refilling demand; a reservation is the honest reading of "I bought it".

**Sell proceeds go to the world, and the owner withdraws them.** A sell run
credits `Planet.accumulatedRevenue`, not a pilot. That is the **port pattern**,
deliberately and down to the name: `Port.accumulatedRevenue` already accumulates
trade income that its owner collects — the player via a confirm dialog on the port
screen, an NPC automatically in the tick. A planet doing the same is learnable
rather than novel, and neither withdrawal has to be invented.

It also happens to be the only safe shape. **`GameTickService` loads players but
never saves them**, and a save would be a start-of-pass snapshot — the
read-modify-write clobber that ate colonist recruits earlier. So `advanceAll` takes
no player list at all: it credits the *world*, which the tick owns, and the screen
moves the money to the *pilot*, which the screen owns. An NPC's share is collected
in the tick, which is safe for the same reason NPCs are persisted there already.

**This does not contradict retiring `Collect` (T6).** T6 retires a button that
converts *goods into credits at an invented flat price*. A treasury withdrawal
moves *already-earned credits into a wallet*. No price, no invention, no second
price for the same goods — a different verb wearing a similar label.

**Gated behind a toggle in Settings, for now.** This is an advanced convenience
that saves a great deal of time, so it should not be free at the start. It ships as
a **`Planet Trading` toggle in a new Settings -> Modules panel**, and the reasoning
for a toggle rather than a purchasable module is mechanical: `installedModules` is
*equipment* — a `Map<String, int>` of id -> level on `Player` — while feature gates
in this codebase are plain bools on `GameSettings` (`unlockAllShips`,
`uiScaleAuto`). A toggle is therefore the established pattern and needs no new
machinery.

**Two ways to unlock it later are deliberately left open:** gating it behind a
Citadel level (so a developed world earns the capability), or selling it as a real
purchase. Both are additive changes to the gate, not to the feature, which is why
the feature must live behind **one seam** — a single service owning job creation,
advancing and cancellation, with the UI calling only into it. Removing the feature
should mean deleting the service and its UI with no other file touched. That is the
same shape as `ScanService`: one verb, one owner, so two screens cannot drift.

**A job can fail, and that is a decision rather than an oversight.** An order is a
chance roll, not a guaranteed delivery — which is what makes it a *decision* rather
than a button that converts credits into goods with a delay. A failure needs to be
legible when it happens (the job reports what was lost and why) because a silent
loss reads as a bug.

**Insurance is the intended mitigation, and it is deferred.** The natural response
to a loss is to buy cover against it, and that is the mechanism to build *after*
jobs are running and the failure rate can be measured. Deliberately not designed
here: an insurance premium priced against a failure chance nobody has observed is a
guess, and it would be the third thing built on top of two that do not exist yet.
Recorded so the idea is not lost — it also pairs with the convoy mechanic below,
where the loss is a *ship* rather than a crate.

**What the Port Report needs.** It already lists every port with buy and sell
prices, and the data for quantities is **already public** — `port.supply`,
`port.demand`, `effectiveMaxSupply`, `effectiveMaxDemand` — the report simply does
not render it. A quantity column is therefore small. What is genuinely missing is
**distance**: the report computes no hops, so "relatively close" currently has
nothing to sort by. Job selection needs it, and the report should show it.

**Decided:**

- **Credits are paid up front.** The order is paid in full when placed, which is
  what makes the reservation above honest — the player has bought the goods, so
  they are theirs. Colonists charge at order, so this matches the existing
  precedent rather than inventing a second payment model.

**Still open:**

- **What is the failure chance, and what does a failure cost?** The roll is
  decided; its probability and its penalty are not. The penalty should probably
  scale with the order — losing a 200-unit run is noise, losing a 20,000-unit run
  is a decision the player wants to have insured.
- **Modules panel: what else goes in it?** It is being created for one toggle, which
  is fine, but the name implies a home for future gates and that is worth thinking
  about before the second one arrives.
- **Does a job survive the port being destroyed mid-flight?** A reserved order
  should be safe from *other buyers*, but a port that ceases to exist is a
  different question, and "what happens to my cargo" has to have an answer.

#### Planned phases — trade jobs

**Eight phases, ordered so each one is independently landable and the feature stays
behind one seam.** `T` rather than `A`-`I` so these do not collide with the
existing planet phases. T7 and T8 are deferred by decision, not by dependency.

| # | Phase | Size | Depends on | Guard |
|---|---|---|---|---|
| **T1** | **`TradeJob` model + `PlanetTradeService`.** A job: id, planet id, port id, commodity, direction, runs total/remaining, ticks per run, ticks remaining, reserved units, credits paid, status. The service owns create / advance / cancel. No UI. | Medium | — | Unit tests driving the service directly: a job advances one run per `hops`-scaled interval, lands its cargo exactly once, and cancels cleanly |
| **T2** | **The tick advances jobs.** `GameTickService` steps every job each pass and writes through. | Small | T1 | **DONE.** The `productionRemainder` lesson applies here. The tick re-parses the universe every pass, so a job that lives only in memory resets every tick and never progresses. Guard: mutate → save → reload → advance, for a multi-run job |
| **T3** | **Port selection.** Given a planet, commodity, direction and volume: find ports that can actually perform the trade, nearest first, split across them when one cannot absorb the order. | Medium | — | Pure function over a universe. Guard: a 100,000-unit order against ports whose combined capacity is 60,000 splits into jobs summing to 60,000 and reports the shortfall, and never selects a port that does not trade that commodity |
| **T4** | **Port Report: quantities and distance.** A column for what a port will still take, and hops from the player. | Small | — | Widget test on the rendered rows. The quantity data is already public (`supply`, `demand`, `effectiveMax*`); distance is not computed today |
| **T5** | **The gate and the UI.** `GameSettings.planetTradingEnabled` + a new **Settings → Modules** panel, and Buy/Sell in Transfers with a job-status row. | Medium | T1-T4 | **DONE.** Widget test pins the gate both ways (absent off, present on); every job row carries a per-run `TickProgressBar` countdown |
| **T6** | **Retire `Collect`.** Route the shipment pool through a sell job, or delete the button. | Small | T5 | **DONE as sweep, not sale.** The pool is overflow, so `Collect` became a free **Move to store** bounded by room (drones included); the flat payout table is deleted, leaving exactly one price per commodity — the live port one. Guard: model bounds + widget flow + a source scan pinning the table's absence |
| **T7** | **Failure rolls.** The chance a run is lost, and what it costs. | Small | T5 | Injectable RNG so both branches are reachable in a test — a probability tested with a real RNG is a test of the weather |
| **T8** | **Convoy + insurance.** Player or NPC ships fly the runs; losses are ships; insurance covers them. | Large | T7 | Deferred by decision. See the note above |

**A job row needs a per-run countdown, not just a run count.** A run is minutes
long, so a row reading `12 runs to go` that does not move for four minutes is
indistinguishable from a stalled job — the same failure the colonist transit bar
had at twenty-nine seconds, sixteen times worse. `TickProgressBar`
(`lib/widgets/shared/progress_bar.dart`) is the shared answer: one tick is 30s, so
a run of N ticks has an exactly known duration, and the bar measures real time
*within* the current tick and resyncs when the count moves. It therefore moves
every second **and** cannot claim progress the ticks have not granted. The
sub-tick term is capped just below a full tick for that reason: without the cap,
`(total - 1 + 1) / total` reads as finished on the last tick, which is the same lie
a self-driven `t / D` clock tells.

**Pacing.** `ticksPerHop` is 2, so one hop is a minute and the **median** four-hop
port is a **four-minute** run. That makes an 80,000-mineral Citadel order 16 runs
over about an hour, with a delivery every four minutes. Distance sets the cadence;
order size sets the number of runs; the two do not interact.

**Why T3 and T4 come before T5.** Both are independently useful — the Port Report
gets better for a player who never enables the feature, and port selection is the
piece most likely to be wrong in a way that is hard to see from the UI. Landing them
first means T5 is only the controls, and the two things it depends on are already
tested.

**Why T6 is its own phase rather than part of T5.** Removing a button the player
currently uses deserves its own commit and its own reasoning, not a side effect of
adding a feature. If `Collect` is kept instead, the guard above is what stops the
two prices drifting apart again — which is how this defect survived twice already.

### PARKED — the exchange, as a pressure valve

**Deferred until the trade jobs above have landed, and possibly forever.** It is
kept here so the reasoning is not lost, not because it is scheduled.

The original argument was that an unlimited market with a **spread** keeps ports
strictly better:

```
exchange bid  <  port average buy price  <  port average sell price  <  exchange ask
```

The gap is the premium on logistics, and it is what makes cargo capacity, hull
choice, engines and owning a port worth anything.

**Two things changed.** First, trade jobs route bulk movement through real ports
at real prices, which supplies the "unlimited enough" sink without a second
parallel economy — and a second price for the same goods is exactly the defect
this document keeps finding. Second, the exchange was partly justified by things
the player **cannot** buy, and that list is shorter than it sounds: hardware comes
from emporiums, scrap sells at them, contraband trades at black markets.

So the honest position is: **build the trade jobs first, then ask what is actually
left that needs an exchange.** If the answer is "nothing", the exchange was a
solution to a problem the jobs already solved. If the answer is "equipment and
artefacts", it should be scoped to exactly those rather than to resources.

The knife-edge condition still applies if it is ever built: if the bid is ever
above a port's buy price that is an arbitrage loop, and it would be found
immediately.

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

### DONE — Mountain is generated, weighted like Desert and Ocean

This was `OPEN — Mountain is implemented but not generated`, and it is now stale in
the opposite direction. `_pickPlanetType`'s `weightedTypes` includes Mountain
**twice**:

```
Terran x3, Jungle x2, Desert x2, Ocean x2, Ice x1,
Lava x2, Mountain x2, Moon x2, Barren x1, Toxic x2
```

A mid-table slot rather than a rare one, on the reasoning that a highland world
productive in all three commodities *is* the complement the harsh types are
designed to want beside them, and a complement that exists mostly in torpedo rolls
is not a complement. The **19-slot** table makes Mountain as common as Desert,
Ocean, Lava, Moon or Toxic (2 each), and twice as common as Ice or Barren (1 each).

The caveat the open note raised is the one that still applies to any future edit:
**adding an entry shifts every downstream random draw and therefore every seed.**
That is why the entry carries a comment in the generator saying so, and why the
generator tests were re-run rather than assumed green.

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

### The game clock — **one clock, and it is the tick**

One unit of game time is one **tick**: one pass of the 30-second loop. So:

| unit | ticks | real time at the default tick |
|---|---|---|
| game minute | 2 | 30 s |
| game hour | 120 | 30 min |
| game day | **2,880** | 24 h |
| game week | 20,160 | 7 d |

**One tick is 30 seconds, so 30 minutes is 60 ticks.** That is the whole
conversion, and it is the only one the game ever performs: nothing invents its own
day, and a per-day figure is divided by 2,880 to get a per-tick figure.

### Why ticks and not wall-clock

The rule is not stylistic. It is that **the game can be shut off.**

- **Time stops when the game is closed.** A month of real time between sessions is
  not game time and nothing may accrue against it. A 2,880-tick interest period is
  a day *of play*, which at an hour a session is two months of sessions — which is
  exactly what the player is buying when they sit down.
- **Otherwise every cooldown is escapable.** A 2,880-tick hack ban expressed in
  milliseconds is a ban the player clears by quitting and reopening, because the
  stored deadline is compared against a clock that kept running. That is not a
  balance question; it is a missing guard.

Four mechanics were quietly on the wall clock, and each had the same shape of bug:

| mechanic | was | now | what it cost |
|---|---|---|---|
| Port supply/demand refill | `DateTime.now() - lastRegenTime` | `Port.regenTick(ticks)` | a sold-out market **restocked itself overnight** |
| Bank interest | `DateTime.now().difference(lastInterestTime)` | tick deadline | a player who slept a week got a week of interest; one who played seven hours got almost nothing |
| Hack ban (1 day) | epoch ms, persisted | tick deadline, persisted | **quitting cleared the ban** |
| Sabotage (30 min) | epoch ms, persisted | tick deadline, persisted | the debuff expired during dinner |
| Lottery limit (3/day) | `State` local, not persisted | two fields on `Player` | **the limit reset every time you left the tab** — unlimited plays by dipping in and out |
| Gravity collision (1 day) | epoch ms, persisted | tick deadline | the only hazard that fired while nobody was playing |
| Bounty TTL (7 days) | `DateTime` + `Duration(days: 7)` | `ttlTicks` | a bounty lapsed during a week the game was shut |

### The counter is persisted

`GameClock` keeps the tick count on `GameSettings.worldTick`, and
`GameTickService` advances it — **one caller, in one place**, before anything in
the tick reads a deadline.

Persistence is not an optimisation, it is load-bearing. A counter that reset to
zero on launch would make every stored "expires at tick N" meaningless, because N
came from the previous session and `N - 0` is enormous: **nothing would ever
expire.** The obvious repair — clamping a negative elapsed to zero — then makes
every cooldown *vacuous* instead, and the ban is gone. Persisting is the only option
that keeps a long cooldown long.

It is saved on a **60-tick throttle** (30 minutes of play) and on clean exit, so a
crash rewinds cooldowns by at most half an hour. That is the deliberate trade: a
disk write every 30 seconds for the life of the app buys nothing, and rewinding is
generous to the player and **not farmable**, because restarting does not reset the
counter.

### Per-tick rates need a carried remainder

2,880 ticks to refill a store means one tick is `max / 2,880` units — and for a
1,000-unit commodity that is **0.347 of a unit**, which truncates to nothing. A
small port would lose ~38% of its stock a day and effectively never restock. The
sub-unit remainder is carried per commodity, as an **integer numerator** rather
than a `double` fraction: a `double` accumulated over 2,880 ticks landed a
50,000-unit port on 49,999, and since the port clamps at its cap that shortfall
would have been permanent.

Interest does **not** need this, and the difference is instructive: it is computed
lazily from the elapsed tick count rather than accumulated a tick at a time, so
there is nothing to carry. It pays for **whole days only** and advances its stamp
by exactly those days — paying for the fractional part while advancing by the whole
part was a version of this rule that leaked, paying 2,500 for two days where the
rate says 2,000.

### The tick interval is a diagnostic, not a clock

The Automation console can change the loop's *interval*, and that deliberately
does **not** redefine how long a tick is worth. If it did, every cooldown in the
game would silently shorten the moment somebody opened the dev console, which is
the opposite of what a diagnostic tool should do.

### What a tick buys the player

The rate is quotable without a conversion table, which is the practical point of
getting the unit right:

- **30 minutes** of a hack ban is **60 ticks**.
- **1.1% daily interest on 100,000 cr** is 1,100 cr over 2,880 ticks — **0.38194 cr
  per tick**.
- A full **1 → 6** Citadel is 385 ticks, about **3.2 hours of actual play** and
  nothing at all while the game is closed.

### Two consequences that were *not* obvious

- **The old economy was ~29x the new one.** A Volcanic colony at optimum made
  1,440,000 ore/day under the linear formula and 50,000 under the class caps. The
  "72 days to buy the game" figure in this document was measured against the old
  one and no longer holds.
- **The colony supply bill had to move to the same unit.** It was 8% of one tick's
  output charged every 10 ticks — generous while per-tick figures were inflated, but
  at the class caps 288 bills a day came to 23x what a colony earned. It is now 8%
  of a **day's** output, charged once a day: one bill every 2,880 ticks.

### Citadel tiers

All ten classes have six tiers, transcribed from the source tables. Two
translation decisions:

- **Build time is in hours, not days.** The tables say 4–18 days; at 2,880 ticks
  a day that is 4–18 *real* days of play, and construction only advances while the
  game runs, so level 2 would be a week of evenings. Reading the same numbers as
  hours preserves the shape of the authored table exactly — a Mountain level 2 is
  still four times faster than the source table's Class U — while making it
  reachable.
- **Colonists are a gate, not a cost**, as everywhere else in this model.

Level abilities follow the source: treasury at 1, fighter defence at 2, quasar
cannon at 3, transwarp at 4, planetary shields at 5, interdictor at 6.

### The Production Triangle

Every production figure in the game comes from **one rule**, reconstructed from
the TradeWars 2002 planet tables rather than transcribed from them.

For each product a world can make:

- `colonistsPerUnit` — colonists needed per unit per day
- `maxColonists` — the most that track can ever hold
- **`optimumColonists` = half the maximum.** Always. It is computed, never
  typed, so it cannot drift out of step with the maximum it is half of.

```
output/day =  c <= optimum  ?  c / ratio
                         :  (max - c) / ratio
```

Output **rises to a peak and then falls**, reaching zero at the maximum. So 50,000
colonists on a Volcanic ore track makes 50,000/day and 55,000 makes 45,000/day —
the published worked example, reproduced exactly. Staffing past the optimum does
not merely stop helping, it **destroys output you already had**. The peak is a
thing to find and then a thing to accidentally overshoot, and that is the entire
decision surface.

**Drones are derived, not staffed.** There is no drone track to assign colonists
to:

```
fighters/day = (ore + organics + equipment output per day) / colonistsPerDrone
```

The consequence is the point: **the fighter ceiling is not a separate constant.**
Volcanic's 1,002 fighters/day is simply (50,000 ore + 100 equipment) / 50. One
rule produces both the production caps and the cap on fleets, so nobody can build
an invincible planet by ignoring production — and overstaffing every track past
its optimum drives total output, and therefore the fleet, toward zero.

### Why the tables are a rule and not a set of numbers

Every published figure is *derived* from two inputs, so the tables can be checked
against each other without a single transcribed output:

| class | per-product ratios | max colonists | reproduced fighter figure |
|---|---|---|---|
| M Earth | 3 / 7 / 13 | 30,000 | 8,295 / 10 = **829** |
| K Desert | 2 / 100 / 500 | 40,000 | 10,240 / 15 = **682** |
| O Ocean | 20 / 2 / 100 | 200,000 | 56,000 / 15 = **3,733** |
| L Mountain | 2 / 5 / 20 | 40,000 | 15,000 / 12 = **1,250** |
| C Glacial | 50 / 100 / 500 | 100,000 | 1,600 / 25 = **64** |
| H Volcanic | 1 / N-A / 500 | 100,000 | 50,100 / 50 = **1,002** |

All six reproduce their published figure exactly, with a per-class
`colonistsPerDrone` of 10 / 15 / 15 / 12 / 25 / 50. That is not a
coincidence of transcription — it is why the divisor can be a per-class constant
rather than a hardcoded fighter cap, and it is what makes the four **derived**
world types (Jungle, Moon, Barren, Toxic — no TW equivalent) checkable by the
same relationships as the six sourced ones.

**Class U is the seventh source class and is deliberately not implemented.** It
is the only one whose ratios are N-A on every product, so it cannot be given a
non-zero yield without inventing one — see the removal note under *Colony supply*
above for the full reasoning and why removal beat a rescue. `test/planet_class_test.dart` holds
it: changing one mistyped digit in the Volcanic table breaks four independent
assertions, because a wrong input surfaces as a broken *relationship* rather than
as a plausible number.

### Revised order of work

Every step makes the next one worth building, which is the entire argument for the
sequence.

| # | Change | Size | Why here |
|---|---|---|---|
| 1 | ~~**`Sector.planets` list + per-planet id + save migration**~~ | **DONE** | Eight files read `sector.planet`. Every other step touches the same files — doing them on the 1:1 model means doing them twice. |
| 2 | ~~Harsh types -> organics 0; remove upkeep/starvation~~ | **DONE** | Small. Created the gaps that made step 3 meaningful |
| 3 | ~~`Dep`/`Wdr` -> cargo; delete `_transferPrices`~~ | **DONE** | The hauler. **Built before step 2, reversing the documented order** — see below. |
| 4 | ~~Genesis Torpedo + Atomic Detonator + collision rolls~~ | **DONE** | Needs 2 and 3: planting a complement is worthless if goods cannot move |
| 5 | ~~Per-type production caps~~ | **DONE** | Stops a large colony printing without limit. `planet_classes.dart` — see *The Production Triangle* below |
| 6 | **Buy/sell jobs from the planet screen** — **planned as phases T1-T6**, see *Planned phases — trade jobs* | Large | The tedium fix. Needs 3 (cargo moves) and 5 (there is a reason to care which port). Landed as six independently testable phases rather than one |
| 7 | Port Report: quantities and distance | Small | The data for quantities is already public; distance is not computed. Job selection needs both |
| 8 | Port growth on unowned ports | Medium | The most likely fix for the absorption overshoot |
| 9 | ~~The exchange~~ | **PARKED** | Revisit only if something remains that cannot be bought. See *PARKED — the exchange* |

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

### 3. The two scan paths made one strictly dominated — MEDIUM, **FIXED**

The sector panel's 1-energy quick scan and the planet tab's 4-energy scan set the
same `scanned` flag and reveal the same detail dialog. The only difference was
that the expensive path granted +1 faction standing. Every player will quick-scan,
so the 4-energy path was dead weight and the standing reward was the sole reason
to use it.

**Now one verb.** `lib/services/scan_service.dart` owns it: `EnergyService.scanCost`
(1 energy), set the flag, +1 standing with the owner, persist, log. Both screens
call it, so the two cannot drift apart again — and the standing is granted on
*both* paths, because leaving it on one would have inverted the dominance rather
than removed it.

**Scanning is deliberately simple.** It costs one energy and tells you what a world
is. An in-depth scan — production figures, fleet strength — is a **separate verb
that does not exist yet**, and when it lands it should be a second cost constant
on this service rather than a third price on this one.

The one thing that changed shape is the ban countdown: a tick deadline has
30-second resolution, so the widget counts ticks and renders `23h 58m` rather than
`23:58:31`. A seconds-resolution display would be inventing precision the deadline
does not have.

### 4. Colonists are bought, not transported — MEDIUM, **PARTIALLY FIXED**

Was `_transferPrices['colonists'] = 20` credits per colonist with no cargo hold
consumed. That table is **deleted**; colonists now come from your own faction's
homeworld priced by distance (`15 x hops^1.5`) plus a per-shipment energy cost.

Still true: colonists are an **abstract count with no cargo-hold constraint**, so
the economy remains a pure credit-and-fuel cost rather than a hauling problem.
That half is Phase D and remains open.

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

- `dominantCommodity` (`planet.dart:139`) has **no caller in `lib/`** — it is
  read by a test and by nothing else. Kept because the test pins a real property
  (that the world type's own table is what decides it), but it is not on a live
  path.
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

### 7. The starvation cap could strand a colony forever — HIGH, **FIXED, THEN REMOVED**

> **This entire finding describes a mechanic that no longer exists.** It is kept
> only because the bug it found was real and the reasoning generalises: a
> *capped* loss that floors to zero for small inputs is a permanent state, not a
> slow one. Starvation was fixed and then removed outright in favour of colony
> supply (which reports an unpaid bill and never kills anyone), so nothing here
> describes current behaviour.

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
`maxDemand` per commodity that refills over a 24-hour cycle (2,880 ticks), and
port storage
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
- **Progressive scanning** (quick reveals type/owner/danger, detailed reveals
  population and production, scanner module reveals exact figures). This makes
  a scanner module worth buying — which has to be *created* first, since the
  catalogue has no Scanner — and gives the two existing scan paths a
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
- ~~**Gas Giant identity.**~~ **The review was right and the answer was removal.**
  It suggested fuel as an identity, at 0.6/0.6/0.4 the world had no reason to
  exist. It turned out to have no reason to exist at *any* value: the class spec
  gave it N-A on all three products, so it produced nothing regardless of the
  multipliers the review was looking at. Deleting it answered the question.
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
4. **PARTIAL — Scan before landing.** Scanning works and gates the screen, and
   there is now **one** scan verb (`ScanService`, 1 energy, +1 standing with the
   owner) shared by both entry points — the two prices and two copies are gone
   (Code Audit #3, resolved). Not started: the scanner-module auto-scan, which
   needs the module **created** before it can be wired — there is no Scanner in
   the catalogue. See *Proposed Mechanics 7*.
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
| Planet creation | Genesis Torpedo, random type, up to 3-5 per sector; Atomic Detonator to retry | **Done.** Random gen at universe creation; Genesis Torpedo + Atomic Detonator shipped, with a **game-day** collision roll for over-stacking |
| Planet types | 7 types (M/K/O/L/C/H/U) with different production multipliers | **6 of the 7 sourced classes implemented** + 4 derived = **10 types**. Class U is deliberately absent: its ratios are N-A on every product, so the world it described produced nothing at all (Economy Redesign). **Harsh types produce zero organics** rather than a small amount |
| Colonists | Brought from Terra (sector 1) in cargo holds | Per-faction from the faction's own homeworld, priced by distance, plus a per-shipment energy cost; **the physical cargo-hold half is still not built** |
| Production assignment | Assign colonists to Fuel Ore / Organics / Equipment tracks; per-type daily caps, past which nothing accumulates | **Done.** Minerals / Organics / Industrial tracks with steppers, plus per-type daily caps from the Production Triangle. Drones are *derived* from the three outputs, never staffed |
| Citadel levels | 6 levels, each requires resources + colonists, takes real days (34-52) | 6 levels, each requires resources + colonists; a build takes 15-160 **game ticks** (~7.5 min to ~80 min of play) |
| Defense | Fighter squadrons + Quasar Cannons per level (the classic term; this game calls them drones) | Shield/hull per level + special abilities (matching port defense model) |
| Drone production | Colonists produce drones per day as passive output | Passive drone production per tick (stored on planet) |

## Planet Model — Enhanced Fields

```dart
class Planet {
  final String name;
  final String planetType;            // Terran, Jungle, Mountain, Desert, Ocean, Ice, Lava, Moon, Barren, Toxic
  final String atmosphere;            // N2-O2, CO2, Methane, Ammonia, Acid, Thin, None, Dense

  // Ownership
  FactionClass? owner;               // null = unclaimed
  bool isHomeworld;                  // true if this is a faction's homeworld
  FactionClass? homeworldOf;         // which faction's homeworld
  bool isBackupHomeworld;            // cold-standby capital (C4b)
  bool isDestroyed;                  // planet-killer path; permanently out of play

  // Provenance — **who made it**, as distinct from who holds it.
  //
  // These are `final` and separate from `owner` because ownership moves
  // constantly and none of those transfers create anything: you can fight a Guild
  // world, win, and claim it, at which point `owner` is you and the world is still
  // not yours. A reputation charge keyed on `owner` would then be **laundered by
  // capturing first** — take the world, and the hit for blowing it up disappears.
  // `final` is the guarantee rather than a convention: no screen or NPC can
  // rewrite provenance.
  final String? creator;             // who launched it, if anyone did
  final FactionClass? creatorFaction;// whose faction to charge for its loss

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
  //
  // **VESTIGIAL — do not read these.** Every gate goes through
  // `levelUpCost.*` from the static table. The generator writes them and nothing
  // reads them back, which means a retune of `levelUpCosts` silently leaves four
  // stale numbers lying in every save.
  //
  // The defaults now agree (1,000 in both the constructor and `fromJson`); an
  // earlier version had 1,000 vs 100, which is the kind of drift that makes a
  // field look meaningful when it is not. The clean fix is deletion, and it has
  // not been done because the generator still assigns them — see the note on
  // `Sector.homeworld` for why a "first match wins" lookup is dangerous for the
  // same reason.
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

  String id;                         // Stable per-world identity. (sectorId) stopped
                                     // being an identity the moment Sector.planet
                                     // became a list — a name may duplicate, an
                                     // id may not, so every surface keys on this.
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
| **Mountain**| Highland, cold valleys| Thin    | 1.5      | 1.2      | 1.0        | 1.2      |
| **Moon**    | Small rocky body      | None    | 1.0      | 0.4      | 0.6        | 0.8      |
| **Barren**  | Rocky, lifeless       | None    | 1.2      | 0.2      | 0.8        | 1.0      |
| **Toxic**   | Corrosive atmosphere  | Acid    | 1.6      | 0.3      | 1.0        | 1.2      |

**Classic equivalents:** Terran→Class M, Jungle→Class M variant, Desert→Class K, Ocean→Class O, Mountain→**Class L**, Ice→Class C, Lava→Class H, Moon→new, Barren→new, Toxic→new.

**There are ten types, and Mountain is the sixth *sourced* class.** It was
missing for a while in a way worth recording: the Production Triangle table below
listed **L Mountain** (ratios 2/5/20, max 40,000, 1,250 fighters/day) as one of
the seven TradeWars classes, while `planet_classes.dart` had no entry for it —
so the document was right about a thing the code did not have, and the claim
"all seven reproduce their published figure exactly" was true of six. Adding the
spec made that true of all seven the game had; removing Class U took it back to
six. Its three images are the old `Unknown_World_*.gif`
files, renamed to `Mountain_World_*.gif`; they had been **orphaned**, since
`imagePool` had no `Unknown` key and the `Unknown` class spec is a private
fallback rather than a real type.

**Mountain is not a harsh world.** Its organics ratio is 5, which is productive
(the harsh set is Lava / Barren / Toxic / Ice / Moon, all at 0), so all three
workforce steppers stay live. What distinguishes it is that it is *balanced* —
its biggest peak is ore at 10,000/day, against organics 4,000 and equipment
1,000 — and productive everywhere rather than excellent at one thing.

**Its citadel costs are authored, not sourced.** TW2002 published no Class L
build table, so the six tiers are modelled on Class K (same `maxColonists`, same
ore ratio) with organics and equipment pulled down, because Mountain grows them
an order of magnitude more efficiently and a build should not demand imports the
world can make for itself. `sourced: true` is accurate for the triangle and
deliberately not claimed for those six rows — retune them freely.

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
would come back advanced past a galaxy that had stood still.

This is the same rule as everything else in the game — see *The game clock*. It is
worth stating as the *original* case, though: builds were the first thing that had
to be expressed in ticks, and every other clock was ported afterwards.

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
above stands until trade jobs replace its resource prices with live port prices —
at which point the credit column becomes a *range*, because a port's price moves
with its cash and demand.

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
to fit a fixed 100,000 cap makes an Ice world a Citadel, and raising caps to fit
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

**There IS a transit timer — this reverses an earlier decision.** It used to read
"there is deliberately no transit timer", on the reasoning that a transit bar is not a
strategic cost in a single-player game and is therefore tedium. That reasoning was about
the *cost* argument and it still holds, but it missed what the player actually sees.
Buying 2,000 colonists used to edit the population figure under the cursor and nothing
else, and on a large colony that edit was not even legible — see the note on formatting
below. The purchase read as nothing happening. Two ticks (`Planet.colonistTransitDelayTicks`,
one real minute at 30s a tick) is long enough to be a departure you watch and short
enough that nobody comes back later wondering whether it went through. It is not a
logistics puzzle and it is not a risk: credits are charged at the moment of ordering,
because a purchase the player is unsure they can cancel is worse than a purchase that
already happened.

The colony card shows a **determinate progress panel** while one is in the air — the same
treatment as the citadel-build bar, because a shipment is the same kind of thing: work
already paid for that advances one step per game tick. Amber, bordered, with the headcount,
a bar that fills, and `Arriving in 30s (~1 min)` rendered through `GameClock.format` so it
is honest about tick resolution rather than inventing a seconds-precise countdown.

It was a plain text row first, and a player who had just spent credits on 100 colonists
reported "**nothing happens on the planet screen**". Three things made that literally true
on screen: a one-line row among the stat figures does not read as an event; sitting
*between* `Reserve` and `Supply draw` made it look like one more figure; and the recruit
also wrote an action-log line, so the only acknowledgement the game offered was in a panel
the player was not looking at. **The recruit now writes no log line at all** — a local
transaction with a local progress bar does not also need narrating into the galaxy-wide
feed. The panel is its own bordered block below the stats, appears on purchase and
disappears on arrival, which is the signal.

**Two things had to be true for the arrival to work at all, and both are guards now.**
Transit is advanced *before* the `population <= 0` skip in the tick — the one world
guaranteed to be buying its first colonists is a world with no colonists, so behind that
check the first shipment would never land. And `advanceColonistTransit` lands a shipment
whose countdown is already spent rather than trusting the invariant, because a
paid-for shipment stranded forever is the exact failure the row exists to end.

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

### Assigning Colonists — **the UI exists**

**The colony card is not gated on having colonists.** It used to be hidden entirely at
`population == 0`, on the reasonable-sounding assumption that a world with no colony has
nothing to say. The cost is that "no colonists" and "the panel is broken" render
identically — as *nothing* — and the world most likely to be buying its first shipment is
the world with no panel to show it arriving in. An empty state is not an absent state.

Three tracks with steppers, plus an implicit reserve:

- **Minerals**, **Organics**, **Industrial** — staffed, and the only place a
  colony's workforce decision is made.
- **Drones** — **not staffed.** Drones are *derived*: a day's output is
  `(ore + organics + equipment) / colonistsPerDrone`. There is no drone track to
  assign anyone to, and that is the point — see *The Production Triangle*.

Total assigned colonists cannot exceed `population`; whatever is not on a track is
the reserve. Each stepper names its source or destination in a tooltip, because a
bare `+`/`−` pair on a row of numbers does not communicate that it moves people
*between the reserve and the track*.

**OPEN: the population readout can hide a purchase.** `planet_screen`'s `_formatNumber`
compacts to one decimal (`1.2M`, `10.0K`), which is right for a store readout and wrong
for a figure the player has just paid to change. Measured: at 1,200,000 or 4,200,000 a
+2,000 purchase renders **byte-identical** before and after — the credits leave, the
transaction commits, and the screen shows nothing at all. This was reported as "the
credits were deducted and I don't see them anywhere", and it is not a data bug: the
colonists land, they are simply invisible. The fix is to show exact figures on the
population and reserve rows, keeping the compacted form for stores. Not done here
because it changes how every existing colony reads.

**A dead track locks itself.** On a harsh world the organics stepper is disabled
and the rate column reads "cannot produce" — a stepper that accepts colonists onto
a track yielding nothing looks like a bug. Remove stays enabled even there, so a
colony generated before its world became incapable is not stuck holding colonists
who will never work again.

### Production Formula — **superseded by the Production Triangle**

> The linear formula below was the original design and it is **no longer what the
> code does**. It is kept because the storage work below was built against it and
> the reason it was replaced is load-bearing. The live rule is the triangle in
> *The Production Triangle*: output **rises to a peak at half the track maximum and
> then falls to zero at the maximum**, so overstaffing a track destroys output you
> already had. This formula only ever rose, which is why a colony could be scaled
> without limit.

```
outputPerTick = colonistsOnTrack * typeMultiplier * efficiency * development
                 * Planet.baseOutputPerColonist
```

`baseOutputPerColonist` is 0.01 and is a **pure scale factor**, not a balance
lever. It exists because the original per-tick figures were orders of magnitude
larger than any storage number could be sane against: a full Terran colony turned
out 1,600,000 minerals a tick against a 200,000 store and filled it in 0.6 ticks.

> When the scale was first corrected, upkeep was **divided** by the new constant
> instead of multiplied, which inflated food costs a thousandfold and made a colony
> unable to feed itself at any workforce size. Both are now expressed against the
> same constant — though upkeep itself has since been removed, so that pairing no
> longer exists.

### FIXED — the production carry was not persisted

**`productionRemainder` is the sub-unit fraction of each tick's output**, and it is
load-bearing: a Volcanic ore track peaks at 17.36 units/tick and a Glacial organics
track at 0.17, so without a carry **any track under 2,880 units/day banks nothing at
all, ever**.

It was a bare `= {}` with no `toJson`/`fromJson` entry, and the tick re-parses the
universe every pass — so every planet arrived with an empty remainder and
`floor(0 + perTick)` was computed forever. Measured across all 26 producible tracks:

| | before | after |
|---|---|---|
| tracks banking exactly zero per day | **13 of 26** | 0 |
| worst loss vs the displayed figure | **−100%** | 0% |
| tracks able to self-supply a level 1→2 | **none** | all |

The 8% residual between displayed and banked is the colony supply bill, which is
the intended drain.

Two consequences worth naming, because both were invisible:

- **The harsh-type design was erased.** Lava / Barren / Toxic / Ice / Moon produce
  zero organics *on purpose* — a considered decision so those worlds are *incapable*
  rather than expensive. With Terran also banking zero there was no longer a
  distinction to make.
- **The colony card lied.** It displays `outputPerDayFor`, which by design does not
  consume the remainder, so it read as though the colony were earning the full
  figure while the store never moved.

**Why 965 tests missed it:** every production test held **one long-lived `Planet`**
across its 2,880 ticks, which is exactly the condition under which the bug cannot
appear. Guarded now by `test/planet_production_reload_test.dart`, which drives the
real path — mutate, save, reload, repeat — for every producible track.

### Storage — implemented, and nothing is wasted

Storage is **per commodity** and **differentiated by type**, replacing the single
`maxStorage` every world shared. Modelled on the classic game's per-product
limits, which are wildly uneven (Volcanic 1,000,000 ore / 10,000 organics;
Oceanic 1,000,000 organics / 50,000 equipment; source Class U 10,000 of
  everything — a citation of the table's shape, not a type in this game).
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

**The supply bill draws from the shipment pool as well as the working store.**
Goods already produced and awaiting collection are still goods; without that, a
poor-organics world would be told it could not feed itself while tens of thousands
of organics sat unclaimed beside it. (This paragraph said "starve" — written while
starvation existed, and now describing the supply bill instead.)

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

Note: the generator seeds `requiredColonists` at 500,000, which is unreachable
for every Duran homeworld type. **This is now moot and the field is vestigial**
(see the model sketch above): all gating reads `levelUpCost.requiredColonists`
from the static table, and the per-tier cost figures were re-derived. It was
written when levelling grants did not exist; the fix it asked for has been made
somewhere else, and the note outlived the problem.

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

**The trigger now exists** — the Atomic Detonator calls it, and the gravity
collision roll is a second path. Invasion (Phase H) remains the only way to take a
world *without* destroying it.

### Backup Homeworld Claiming — not implemented
The model flag, generator seeding, and control-gating logic all exist; what is
missing is an NPC that *chooses* to claim an unclaimed planet as a new capital.
See Proposed Mechanics.

---

## Planet UI

### Navigation
- **Planets** is its own tab button on the left nav bar/rail, directly below Ports.
- Tab index in `GameShell`: **5**. Settings is 6 and is deliberately *not* in the
  nav bar — it is reached from the AppBar gear or the rail's last button.
- Shows the selected world in the current sector, or a prompt when the sector has
  none. With three worlds per sector there is a **selection**, keyed on `Planet.id`.

### Entry Point
- "Land on Planet" button on the tactical map / sector interaction panel.
- Visible when `sector.hasPlanet` — which is derived from `planets.isNotEmpty`.
- If the planet is not scanned, the button scans it; once scanned it opens the
  planet screen.
- **Scanning costs energy, not turns** — this document predates the B1
  turn -> energy migration. There is now **one** scan, not two: `ScanService`,
  1 energy, +1 standing with the owner, shared by the planet tab and the sector
  panel. See Code Audit #3.

### Planet Screen Layout

**Unscanned:**
```
┌─────────────────────────────────────┐
│  [Scan Planet] (1 energy)             │
│  Planet detected in this sector.    │
│  Requires scan to identify.         │
└─────────────────────────────────────┘
```

(The wireframe said 4 energy. There is now **one** scan and it costs 1 —
see Code Audit #3. The wireframes below are illustrative and have drifted
from the current layout; the *facts* in them are what this document is for.)

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

### The Transfers Panel — **DONE**

> **This section described a defect that has been fixed.** The `Dep`/`Wdr` buttons
> really were credit<->goods converters that never touched `player.cargo` and were
> unbounded by `maxCargo`, and `_transferPrices` really did exist to price them.
> All of that is gone. The rewrite is kept because the reasoning behind it — what
> the buttons must do instead — is the part worth carrying forward.

The panel is three distinct verbs:

1. **`Unload`** — cargo -> planet store. No cost. Bounded by what is in the hold
   **and** by the world's remaining store capacity.
2. **`Load`** — planet store -> cargo. No cost, **bounded by `maxCargo`**. This is
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
  faction's homeworld, and the row used to display the whole explanation inline —
  `5.4K / 200.0K  405cr · 9 hops from Vionis`. That is a sentence in a number cell,
  and at phone width the meaningful half ellipsised away.
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
| Mountain    | `Mountain_World_1.gif`, `Mountain_World_2.gif`, `Mountain_World_3.gif` |
| Moon        | `Moon_1.gif`, `Moon_2.gif`, `Moon_3.gif` |
| Barren      | `Moon_1.gif`, `Moon_2.gif`, `Moon_3.gif` (reuses Moon pool) |
| Toxic       | `Toxic_World_1.gif`, `Toxic_World_2.gif`, `Toxic_World_3.gif` |

> **Case note:** `Ice_world_3.gif` has lowercase `w`. Account for this in asset loading.

> **There is no `Unknown` pool**, and there never was. The
> `Unknown_World_*.gif` files sat in the folder unreferenced until they were
> renamed for Mountain. The `Unknown` *class* spec in `planet_classes.dart` is a
> private fallback for a type with no entry — it produces nothing at all, on
> purpose — not a world anyone can generate. A world whose type has no image
> pool now gets `imagePath: null` and renders nothing, which both planet views
> already handle; the generator used to return a bare `'Unknown_World_1.gif'`
> with no directory prefix, so it named a file that could not resolve.

Planet names drawn from 100-name pool (user-provided list) instead of current `_planetName()`.

## Planet Name Pool

100 names: Xandor, Elara, Sygnara, Voryn, Celestara, Rynara, Thalys, Orwyn, Glavara, Zephyron, Tyria, Axion, Nebulon, Valthor, Saronis, Elyx, Corvus, Zantara, Oberyn, Krythos, Selara, Phaeton, Ecliptor, Astralis, Vionis, Nexilon, Caelum, Sypher, Galeth, Xeridia, Lumora, Tychon, Velara, Myriad, Arctura, Novex, Zephyris, Calyx, Orithyia, Sylvara, Aetherion, Draconis, Quasys, Solara, Erebos, Thalara, Kryon, Vylis, Nexara, Zorath, Ilythar, Vexalon, Synthera, Auralis, Zypheron, Tarsys, Elion, Gravara, Nyxara, Corynth, Xylara, Praxon, Vionara, Zelthar, Astron, Kytheris, Sylion, Eryndor, Valthys, Orythia, Nebula, Xerath, Tylara, Cygnara, Aethys, Zorwyn, Vexara, Sylthara, Klyon, Ecthara, Rynther, Galara, Zyron, Velithor, Naxara, Thalith, Orionis, Clythera, Voryth, Aelara, Xynara, Krylara, Zentara, Elythar, Sovara, Nyxion, Tethys, Vionth, Astrara.

## Proposed Mechanics

Ranked by value against effort. The first two are what stand between the planet
screen and being truthful.

### 1. Make production real, and pay upkeep — DONE, **then the upkeep was removed**

Shipped. The formula moved onto `Planet.produce` as the single source, read by
both the tick and the screen. Zero measured waste across all ten types over 1,000
ticks.

The upkeep half of this item **was subsequently removed**, along with the
starvation failure mode it introduced — both described here are gone. A per-capita
tax turned out to make harsh worlds worse Terran worlds, and the fix was to make
those worlds *incapable* of producing one commodity rather than taxed on all three.
See *DECISION — harsh types cannot produce a commodity at all*.

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
game-day cycle, and port storage upgrades multiply it by 1.5x per level up to
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

Still to do: **buy/sell jobs from the planet screen** (*DECISION — resource trade
as jobs*), which is what actually connects a colony to a port; port growth on
unowned ports (so the sink can scale with the faucet); NPC factions competing for
the same finite demand; and convoy and route mechanics as the deferred second
stage of the jobs. The exchange is **parked** — see *PARKED — the exchange*.

Planets currently compete with nothing, because nothing they produce leaves the
world without the player flying it. Once a colony can place a sell job against a
nearby port's live demand, it competes for the same finite pool every trader does,
which gives distance a reason to matter and makes a port's `effectiveMaxDemand`
the real ceiling on a colony's income.

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
*sink* rather than a *purchase*. Also carries a game-day collision roll when a
sector
is over-stacked past its cap. See the Economy Redesign.

### 6. Invasion combat — LARGE

`PortCombatScreen` is the pattern and the model already carries shield/hull/
defenseLevel. Needed for ownership to have stakes.

It is **no longer the only path** to `Planet.destroy()` — the Atomic Detonator
reaches it from gameplay, years earlier. That changes what invasion is for: it
becomes the path that takes a world *without* destroying it, which is the only
remaining thing a player cannot do.

### 7. Scanner-module auto-scan — MEDIUM, not SMALL

**Re-rated upward, because the premise was wrong.** This said "the module already
exists in `hardware_data.dart` and is unwired". It does not exist. The eight
modules are Warp Core Booster, Targeting Computer, Cargo Expansion Kit, Solar
Array, Auto-Repair System, Shield Capacitor, Cloak Generator and Afterburner.

So the item is two pieces of work, not one:

1. **Create the module** — a `ModuleDef` entry in the catalogue, a `statLine`, a
   level ladder, and whatever effect the reveal has. That is the part the original
   "SMALL" rating did not account for.
2. **Wire it into scanning**, which is the part that was actually described.

It also interacts with the scan decision: there is now a single 1-energy scan
(Code Audit #3, fixed), so the module's value has to come from removing the
*cost*, or from the deeper reveal that does not exist yet — not from
out-scanning a second, more expensive version of the same verb.

The Planet Guide made the same false claim about this module and it was removed
there; this file kept it, which is why the two surfaces disagreed about whether a
Scanner exists.

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
  and the workforce rebalance. `PlanetProductionService` runs it once per tick.
  The organic upkeep and starvation half of this phase was **removed** after
  landing; see the Economy Redesign. Colony supply replaced them.
  `test/planet_production_test.dart` (28 tests) and `test/planet_colony_ui_test.dart`
  (13 tests) guard it, including a displayed-rate-equals-applied-rate check so the
  original defect cannot return.
- **Phase E-adjacent: Workforce assignment** — steppers on all four tracks plus
  an implicit reserve, owner-only, each with a tooltip naming its source or
  destination. Shipped *with* production rather than after it: without it a claimed
  planet has nobody on any track and produces nothing, so production alone was
  unreachable for a player.
- **Phase A: Model Replacement** — `planetType` String replaced `PlanetClass`;
  enhanced model, `toJson`/`fromJson`, type config maps, `Sector.planetType`
  removed.
- **Phase B: Universe Generator Updates** — weighted 10-type placement,
  atmospheres, random efficiency, starting stores, random image, plus homeworld
  and backup-homeworld placement.
- **Phase C: Scanning & Discovery (partial)** — `scanned` flag, scan actions,
  energy cost, persistence. *Auto-scan not built, and no Scanner module exists
  to build it with — see Proposed Mechanics 7.*
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
- ~~**Multi-planet sectors**~~ — **DONE.** `Sector.planets` is a list with a
  per-planet id and a save migration; see *DECISION — multiple planets per
  sector*. (This list said "not started" while the Economy Redesign section
  200 lines above said DONE. A reader who trusted the shorter list would have
  planned work that already shipped.)
- ~~**Per-type daily production caps**~~ — **DONE.** `planet_classes.dart`; see
  *The Production Triangle*.
- ~~**Genesis Torpedo + Atomic Detonator**~~ — **DONE**, plus the collision roll
  for over-stacking a sector past its cap.
- **Buy/sell jobs from the planet screen** — **shipped as T1-T6** (model +
  service, tick advance, port selection, report quantities/distance, gate +
  Transfers UI, `Collect` retired into a free pool sweep). Remaining: T7
  (failure rolls), T8 (convoy + insurance).
- **Order durability (pre-T7).** Placed orders are held as intent and
  re-dispatched when a tick snapshot erases them — bounded at 8 polls (~8s),
  which is also the correctness argument, since no run can complete inside
  the window. Past the bound the order is assumed landed and logged, because
  blind re-creation could duplicate delivered goods.
- ~~**The exchange**~~ — **PARKED**, pending the trade jobs above. See *PARKED —
  the exchange*.

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
   fix, then the torpedo, then the trade jobs, and the exchange **last** (and now
   **parked**, pending the jobs).
7. **The trade jobs themselves** — planned as **phases T1-T8** in *Planned phases —
   trade jobs*. T1-T6 are the feature; T7 (failure rolls) and T8 (convoy and
   insurance) are deferred until it is running and measurable.
8. Scanner auto-scan, NPC colonisation.
9. **H** — invasion, which makes homeworld capture a real growth denial and gives
   ownership stakes. Note that `destroy()` no longer waits for it: the Atomic
   Detonator reaches it years earlier, and the gravity roll with it.

---

## References

- `lib/data/models/planet.dart` — the model (phase A landed; no longer
  pending replacement)
- `lib/data/models/faction.dart` — FactionClass enum, faction lore with homeworld planet names
- `lib/data/models/sector.dart` — Sector with `List<Planet> planets` (up to
  `planetsPerSector`, default 3) and a stable `Planet.id` per world; the
  `planetType` string is long gone. **The 1:1 `Planet?` that used to block this
  file is resolved** — see *DECISION — multiple planets per sector*.
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
- `lib/data/models/hardware_data.dart` — the module catalogue. **There is no
  Scanner module**, so a scanner auto-scan needs one created before it can be
  wired (Proposed Mechanics 7)
- `lib/services/game_clock.dart` — **the** clock. `GameClock.tick` is the only
  notion of game time in the codebase; `ticksPerDay` (2,880) and
  `ticksPerHour` (120) are the only period constants. Persisted on
  `GameSettings.worldTick` on a 60-tick throttle, advanced by exactly one
  caller (`GameTickService`). See *The game clock*.
- `lib/services/scan_service.dart` — **one** scan verb: `EnergyService.scanCost`
- `lib/data/models/port.dart` — `Port.regenTick(ticks)`, the tick-driven refill,
  with a carried sub-unit remainder (`regenRemainder`) so a per-tick rate is
  exact at any horizon. Driven by `GameTickService` and nothing else.
  (1), shared by the planet tab and the sector panel. It replaces two prices for
  one action (4 and 1), which made the expensive path strictly dominated
- `lib/screens/planet_screen.dart` — colony card + workforce steppers, the
  `Unload`/`Load` transfers, level-up UI, the **supply-unpaid** warning (not
  starvation — nothing starves), attack stub
- `lib/services/planet_production_service.dart` — the per-tick colony pass:
  production, the storage floor, construction advance, the **supply bill**, and the
  unpaid-supply tally. Upkeep and starvation are gone (removed per the Economy
  Redesign, not "being" removed)
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
- `lib/widgets/port_trade_view.dart` — the cargo pattern the planet screen
  **copied**: both move units into `player.cargo` and respect `maxCargo`
- `lib/widgets/sector_view_widgets/sector_interaction_panel.dart` — one of the two
  **call sites** of `ScanService`, plus the planet detail dialog
