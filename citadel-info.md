# Citadel & Planet Levelling — reference and open design brief

This document exists to be handed to a model for **design review**, so it is
split deliberately:

- **Part I is verified ground truth.** Every figure is checkable against the file
  named beside it. Treat it as fact about what the code does today.
- **Part II is one reviewer's opinion**, each claim carrying the evidence it
  rests on. React to it; do not inherit it.
- **Part III is constraints** — derived rules that a proposal must not quietly
  undo. These are not preferences.
- **Part IV is what already exists to build on**, which is the part a reviewer is
  least likely to find unaided.
- **Part V is twelve numbered questions.** Answering by number is more useful
  than more feature ideas.

The reason for the hard split: a document that mixes shipped rules with proposals
gets its opinions read as requirements, and that is the specific failure this
project keeps paying for (see §13).

| Section | File the claims come from |
|---|---|
| Tiers, costs, build time, grants | `lib/data/models/planet.dart` |
| Production triangle, class tables | `lib/data/models/planet_classes.dart` |
| Per-tick pass | `lib/services/planet_production_service.dart` |
| World generation | `lib/data/models/universe_generator.dart` |
| Port defence + combat engine | `lib/data/models/port_defense_config.dart`, `lib/services/npc_ai/port_combat_service.dart` |
| Trade jobs (T1–T10b) | `lib/data/models/trade_job.dart`, `lib/services/planet_trade_service.dart` |
| Full design narrative | `planets.md` |

---
---

# Part I — As built

## 1. The six tiers

Display names only — `Planet.levelTitles`, 0-indexed.

| Level | Title |
|---|---|
| 1 | Outpost |
| 2 | Settlement |
| 3 | Colony |
| 4 | Fortified Colony |
| 5 | Planetary Base |
| 6 | Citadel |

A world is generated at **level 1** and never starts higher.

---

## 2. Cost to reach each tier

`Planet.levelUpCosts`, index 0 = 1→2.

**Colonists are a minimum requirement, not consumed. The three resources are
consumed at build start** — paid up front, not refunded if the build is
interrupted.

| Step | Colonists (min) | Minerals | Organics | Industrial |
|---|---|---|---|---|
| 1→2 | 250 | 250 | 250 | 150 |
| 2→3 | 1,000 | 1,000 | 1,000 | 600 |
| 3→4 | 4,000 | 4,000 | 4,000 | 2,500 |
| 4→5 | 15,000 | 20,000 | 15,000 | 12,000 |
| 5→6 | 50,000 | 80,000 | 50,000 | 30,000 |

Gate check is `Planet.canStartConstruction`: not already building, a next tier
exists, population ≥ the colonist minimum, and all three stores sufficient.

**Colonists have no natural growth.** Purchase is the only source. Colonists are
priced at `15 × hops^1.5` credits from your faction's own homeworld, plus the
energy for one shipment regardless of size — so batching pays, and a distant
empire is a fuel problem as well as a money one. This makes the 4→5 and 5→6 gates
shopping trips whose difficulty depends on where your faction's capital happens
to be. See §11.

---

## 3. Build time

`Planet.levelConstructionTicks`, scaled by `GameSettings.constructionTimeScale`
(Settings → Instant / Fast / Standard / Slow). One game tick is **30 seconds**.

| Step | Ticks | At 30s/tick |
|---|---|---|
| 1→2 | 15 | 7.5 min |
| 2→3 | 30 | 15 min |
| 3→4 | 60 | 30 min |
| 4→5 | 120 | 1 hr |
| 5→6 | 160 | 80 min |

A full 1→6 is roughly **four hours of actual play**.

**Builds advance only while the game is running.** There is no wall-clock
catch-up — the countdown is decremented by the tick, so a build does not progress
while the app is closed. The time scale is applied once, at the moment the build
starts, and the resulting tick count is persisted.

`Planet.levelUp()` is the instant path (the Instant setting). Both paths share
one grant implementation, so the cost table and the grant table have exactly one
implementation each.

---

## 4. What a tier grants — the complete list

Applied by `Planet._applyLevelGrants()` on build completion. **Nothing else in
the model changes with level.**

| Level | Defence | Shield | Armour (max hull) | Storage × | Population cap × | Development × |
|---|---|---|---|---|---|---|
| 1 | 0 | 0 | 1,000 | 1.00 | 1.00 | 1.00 |
| 2 | 1 | 2,000 | 4,000 | 1.40 | 1.60 | 1.15 |
| 3 | 2 | 5,000 | 10,000 | 2.00 | 2.80 | 1.30 |
| 4 | 3 | 8,000 | 20,000 | 3.00 | 5.00 | 1.50 |
| 5 | 4 | 14,000 | 40,000 | 4.50 | 8.00 | 1.70 |
| 6 | 4 | 22,000 | 70,000 | 6.50 | 12.00 | 2.00 |

Three things the code is deliberately explicit about:

- **Defence saturates.** It runs 0→4 and is **flat between level 5 and level 6**.
  A level-6 Citadel buys shield and armour, not a fifth defence level.
- **Development is deliberately shallow** — 2× at level 6. The stated reason: a
  steeper curve compounds with type multipliers and population caps into a ~110×
  spread between the best and worst possible colony, which erases planet
  identity. Level is meant to buy **capacity and defence**, not extraction.
- **Shield is refilled to full** on completion. Hull is clamped up to the new
  armour but is **not healed**.

Storage and the population cap are *derived* from `level` rather than stored, so
they can never contradict the numbers printed beside them.

Base population caps, before the level multiplier (`Planet.colonistMaxByType`):

| Type | Base cap | | Type | Base cap |
|---|---|---|---|---|
| Terran | 2,000,000 | | Mountain | 400,000 |
| Jungle | 1,500,000 | | Ice | 400,000 |
| Ocean | 1,000,000 | | Lava | 200,000 |
| Desert | 600,000 | | Moon | 200,000 |
| Barren | 150,000 | | Toxic | 100,000 |

The multiplier is why every type can now reach every tier. Before it, the cap was
a flat per-type number while the gate demanded up to a million colonists, so seven
of ten types could never reach Citadel and every Duran homeworld was capped below
the 4→5 gate — **the two numbers were mutually unsatisfiable**.

---

## 5. Production — the triangle

This is the heart of what a colony *is*. Three workforce tracks:
`colonistsMinerals`, `colonistsOrganics`, `colonistsIndustrial`.

**Drones are derived, not staffed.** There is no drone track and no drone
stepper; see §5.3.

Per product: `colonistsPerUnit`, `maxColonists`, `storageCap`.

### 5.1 The formula

```
optimum            = maxColonists / 2                  (always exactly half)
effective          = colonists              if colonists <= optimum
                     maxColonists - colonists  if colonists > optimum
outputPerDay       = effective / colonistsPerUnit
```

**Output rises to a peak at half the track maximum, then falls to zero at the
maximum.** Every colonist past the peak costs exactly as much output as the ones
below it gained. One formula produces production, the caps, and the fighter
ceiling — so they cannot drift apart.

`optimumColonists` is **computed, never a stored field**, precisely so a player
editing the number beside it cannot produce a world that breaks the rule.

`overshootFraction` is exposed so the colony card can say *why* a track is
producing less than it should, rather than just showing a smaller number.

### 5.2 Class tables

`colonistsPerUnit / maxColonists / storageCap`, and `colonistsPerDrone`.

| Type | Class | Minerals | Organics | Industrial | Col/drone |
|---|---|---|---|---|---|
| Terran | M — Earth Type | 3 / 30,000 / 100,000 | 7 / 30,000 / 100,000 | 13 / 30,000 / 100,000 | 10 |
| Desert | K — Desert Wasteland | 2 / 40,000 / 200,000 | 100 / 40,000 / 50,000 | 500 / 40,000 / 10,000 | 15 |
| Ocean | O — Oceanic | 20 / 200,000 / 100,000 | **2** / 200,000 / 1,000,000 | 100 / 200,000 / 50,000 | 15 |
| Ice | C — Glacial | 50 / 100,000 / 20,000 | 100 / 100,000 / 50,000 | 500 / 100,000 / 10,000 | 25 |
| Lava | H — Volcanic | **1** / 100,000 / 1,000,000 | impossible | 500 / 100,000 / 100,000 | 50 |
| Mountain | L — Highland | 2 / 40,000 / 200,000 | 5 / 40,000 / 200,000 | 20 / 40,000 / 100,000 | 12 |
| Jungle | M/J — Jungle | 6 / 60,000 / 200,000 | 4 / 60,000 / 400,000 | 30 / 60,000 / 60,000 | 12 |
| Moon | L/M — Moon | 10 / 40,000 / 150,000 | impossible | 60 / 40,000 / 40,000 | 20 |
| Barren | K/B — Barren | 3 / 40,000 / 400,000 | impossible | 100 / 40,000 / 30,000 | 18 |
| Toxic | H/T — Toxic | 2 / 50,000 / 500,000 | impossible | 30 / 50,000 / 80,000 | 15 |

Four classes are taken from the TradeWars source tables (flagged `sourced`); the
other four were derived from the same triangle so that its invariants hold.

**Five of ten types cannot produce organics at all** — Ice, Lava, Moon, Barren,
Toxic. This is a **gap, not a penalty**: the organics workforce stepper is *locked*
and the rate column reads "cannot produce". The designed answer is to haul
organics in, or plant an Ocean world beside it. Earlier builds used small non-zero
values, but those only existed to feed a per-capita upkeep tax the design has
since dropped.

### 5.3 Drones

```
dronesPerDay = (mineralsPerDay + organicsPerDay + industrialPerDay) / colonistsPerDrone
```

Drones are computed from what the three tracks *actually* produce. This is why the
fighter ceiling falls out of the production caps instead of being a separate number
someone has to keep balanced against them. `colonistsPerDrone` is the per-class
constant that converts output into fighters, and it is never set independently of
the triangle.

### 5.4 Per-type flavour table

`Planet.typeMultipliers` — (minerals, organics, industrial, "headline"). It is
**not** the production rule any more; the triangle is. It exists to say what a
world is *known* for and it feeds `canProduce` (which locks a stepper),
`dominantCommodity`, and the Planet Guide's "strongest at" line. Its organics term
is `0.0` on the five harsh types, matching the triangle.

| Type | Multipliers |
|---|---|
| Terran | 1.0, 1.0, 1.2, 1.0 |
| Jungle | 0.6, 1.8, 0.6, 0.8 |
| Desert | 1.4, 0.4, 0.8, 1.2 |
| Ocean | 0.4, 2.0, 0.6, 0.6 |
| Ice | 0.8, **0.0**, 0.6, 0.8 |
| Lava | 2.0, **0.0**, 1.4, 1.4 |
| Moon | 1.0, **0.0**, 0.6, 0.8 |
| Mountain | 1.5, 1.2, 1.0, 1.2 |
| Barren | 1.2, **0.0**, 0.8, 1.0 |
| Toxic | 1.6, **0.0**, 1.0, 1.2 |

Mountain is a flavour row rather than a second copy of the maths: the triangle
gives it a peak of 10,000 minerals, 4,000 organics and 1,000 equipment per day, so
minerals must read as its headline or the guide would contradict the numbers
printed beside it.

---

## 6. Storage

Two-part rule, and both parts are load-bearing:

- **Working store** = `max(typeStorageCap, outputPerTick × 120)`. A store always
  holds **120 ticks — one game day — of its own output**. This is what makes "no
  waste" structural rather than a matter of picking good numbers: a fixed
  per-type cap cannot serve both a colony of a hundred and one of two million,
  because the latter out-produced any fixed cap within seconds. A small colony
  keeps its type's character; a very large one is automatically given
  infrastructure proportionate to what it makes.
- **Overflow goes to a shipment pool** (`pendingMinerals` / `Organics` /
  `Industrial` / `Drones`), sized at `pendingCapMultiple = 250` × the working
  store. The pool exists so a colony keeps earning while you are elsewhere, so it
  should only fill on a world ignored for a very long time.
- **Goods are only truly lost if the *pool* overflows.** Overflowing the working
  store is normal operation and is not reported.

The old `Collect` button was retired: the pool is now swept into the store for
free, bounded by room. There is exactly **one** price per commodity — the live
port one. (There is no flat pool payout table, and a structural guard forbids one
reappearing.)

---

## 7. Colony supply bill

This replaced a per-capita organics upkeep with a starvation bleed. **Both halves
of the old design were wrong** for a world that cannot make organics at all: a
harsh type would have bled to death on a mechanic it was designed to be unable to
pay, and the only available answers were "haul organics forever" or "watch your
colonists die" — neither of which is a decision.

The current rule:

- Billed every `supplyInterval = 2,880` ticks (one game day).
- The bill is **8% of the colony's own output** (`supplyShareOfOutput`), so it is
  the same relative size at every scale.
- The commodity is drawn **at random** from the three consumables, salted by
  `population × 31 + drawCount × 17 + name.hashCode` so two identical colonies do
  not draw in lockstep.
- Payment falls through to whatever the world actually has, so a harsh type is
  never punished for being unable to grow the drawn commodity.

**Nothing dies.** An unpaid bill is *reported* — a supply warning chip and a
`storesEmpty` flag — not inflicted.

Production lands **before** upkeep is charged, so a colony that farms its own
food stands still rather than spiralling.

---

## 8. Per-planet fields

| Field | Range | Notes |
|---|---|---|
| `productionEfficiency` | `0.5`–`1.5` uniform, rounded to 1 dp, rolled at generation | **Never displayed anywhere.** Roughly half of all generated worlds start below 1.0. |
| `productionRemainder` | per-track fraction | Carries sub-unit output between ticks. Persisted. Without it a track yielding 0.03/tick banks nothing, ever. |
| `supplyTimer` | 0–2,879 | Persisted. |
| `level` | 1–6 | |
| `constructionTicksRemaining` / `constructionTarget` | — | Both persisted. A countdown nobody persists resets to full every tick and the build never lands. |
| `storedDrones` | — | Derived output, but stored as a normal good. |
| `storedColonists` | — | Does not exist; population is a single scalar. |

**One game clock.** `GameClock.tick` is the only notion of game time: 120
ticks/hour, 2,880/day. Nothing in the colony path may use `DateTime.now()`.

---

## 9. Tunability

`PlanetClassTuning` is a **mutable overlay** on the `const` default table; the
screen and Settings editor resolve through `specFor`, which merges any saved
override over the default.

- A player can edit **values** — ratios, caps, build times.
- The player **cannot** edit the **rules**. The half-maximum optimum is computed,
  not a field, and the fighter ceiling is derived from output. So a customised
  world cannot end up violating the relationship the Planet Guide documents.

`GameSettings` populates the overrides; a null entry means "use the default".

---

## 10. The two-systems warning

**`planet_classes.dart` contains a second, dead citadel system.** Nothing in
`lib/` reads any of it:

- `CitadelLevel` — a per-tier record of `hours`, `colonists`, `ore`, `organics`,
  `equipment`.
- Each `PlanetClassSpec.citadels` — a `List<CitadelLevel>` of six tiers per class.
- `citadelAbilities` — a `Map<int, String>` of prose describing the classic
  TradeWars tier abilities.

The `citadelAbilities` text is **sourced and good**, and none of it is
implemented:

| Level | Ability (prose only) |
|---|---|
| 1 | Citadel — defenseless. Treasury, overnight, planet transporter available; fighters will not defend and the world can be taken by anyone who lands. |
| 2 | **Combat computer** — fighters stationed on the planet now defend, at 3:1. Can be set to send fighters into the sector at 2:1. |
| 3 | **Quasar cannon** — fires on anything landing, entering the sector, or both. Burns fuel ore; 1 ore per 1 damage atmospheric, 3 per 1 sector-firing. Bypassable by photon missile unless planetary shielding covers it. |
| 4 | **Planetary transwarp drive** — move this world to any sector where you have dropped a fighter, 400 ore per sector jumped. |
| 5 | **Planetary shielding system** — planetary shields must be destroyed before invasion, 20 damage each. Ten ship shields make one planetary shield. |
| 6 | **Planetary interdictor generator** — makes it difficult for an enemy to retreat from the sector. Similar to a tractor beam. |

The **live** levelling is the completely separate set of tables in `planet.dart`
(Part I §1–§4), which grants storage, population cap, development, defence level,
shield and armour — none of the above abilities.

So: two sources of truth, one wired. Any design work has to decide which it is
extending. The prose table is a ready-made source of six *distinct* tier
identities, which the current numeric tables do not have — every level is
"bigger numbers", with the single exception of defence saturating at 5.

---

## 11. Known gaps

Ordered by cost-to-value, not by importance to the design.

1. **`productionEfficiency` is invisible and halves output on ~half of all
   worlds.** A player comparing two identical Terran colonies finds one produces
   half as much with no explanation and no way to act on it. The cheapest
   high-value fix on the list — one label on the colony card.
2. **The 4→5 and 5→6 gates need purchasing**, and purchase is priced by distance
   from your faction's capital. Levelling pace is gated on geography the player
   did not choose. Natural population growth is the real fix.
3. **Levelling has no effect on freight or trade.** The trade planner reads
   nothing about the world — not its level, its type, or its storage. A level-6
   Citadel and a level-1 Outpost have identical freight capability.
4. **Level 6 buys no additional defence level.** 5→6 is shield and armour only,
   which makes the final tier's headline less legible than the one below it.
5. **Invasion and combat are stubs.** The planet screen's Attack action writes to
   the action log only. Defence, shield and armour are modelled but nothing
   currently attacks a colony — see §IV.1, which changes the cost estimate.
6. **Homeworlds are not citadel-linked.** `RepopulationService` drives ship spawn
   cadence from the homeworld flag, not from citadel level, so a player's capital
   and their best-developed world are unrelated.

---
---

# Part II — Analysis and proposals

> Everything below is **opinion**, offered so a reviewer has something to react
> to rather than re-deriving it. Each claim names the evidence it rests on.

## A. The biggest reframe: invasion combat is nearly built already

The instinct is that invasion is a large project because nothing can currently
attack a colony. That is true and misleading: **a complete, live, turn-based
defence-combat system already exists — for ports.**

| Existing | Detail |
|---|---|
| `PortDefenseConfig` | Per-level 0–4 table: shield capacity, firepower, and a `PortSpecialAbility` (counter-attack, shield regen, EMP burst, all-abilities) |
| `port_combat_service.dart` | 282 lines of turn-based resolution, loot, surrender |
| `port_combat_screen.dart` | 1,214 lines of working combat UI |
| The integration point | `PortCombatService` reads defender stats through `PortDefenseConfig.defenseStats(int level)` — a pure function of an int |

The decisive detail is the last row: **the defender's stats are already
parameterised by a single integer on a 0–4 scale**, and `Planet.levelDefense` is
already on exactly that scale. A planet already has `defenseLevel`, `shield` and
`hull` — the three things a port defender has.

So invasion is not a project; it is a port. The Attack button exists; what it
needs is a defender built from the planet and handed to an engine that already
runs. That is a fraction of the cost usually budgeted, and it argues for wiring
the Combat Computer ability much earlier than any tier table would suggest —
because every later military ability depends on invasion existing first.

Caveat: this is an argument about the *defender* half. The attacker side — who
invades, on what authority, with what garrison — is still unbuilt, and the NPC AI
has no goal that targets a planet at all (`raidPort` is ports only).

## B. Supply Lines: the best idea here, and the wrong order

The strongest proposal in the previous review is a standing lane between sibling
worlds in a sector, paying off a design promise already written into
`sector.dart` ("the complementarity loop — an Ocean feeding a Lava … only feels
good when the worlds are adjacent"). The code confirms that comment exists, and
nothing implements it.

Two corrections:

**It is not a small lift, and "reuse TradeJob" is half true.** A `TradeJob`
carries a port reservation, an escrow, a price, a run-risk roll, four outcome
classes, an incident ledger, an order record and an insurance premium. A supply
lane needs **none** of those — no port, no price, no risk, no cover. What it
shares with a trade job is a *scheduler* (cadence, hold size, run length), not a
system. Building it by copying `TradeJob` will produce the wrong shape.

**Its economics are uncosted, and they are large.** Free intra-sector lanes mean
goods move without touching a port, so port demand and supply stop mattering
between sector-mates — and the entire trade-job feature (nearest-port planning,
split orders, run risk, freight cover) becomes an edge case for anyone who
develops a sector properly. That may be a *good* design. But it is a paradigm
shift, and it should be sequenced as one rather than as the cheap first win.

Suggested safety valves, if it is built: lanes move **surplus above a
player-set reserve** (reusing the storage-overflow concept), carry a throughput
cap, and carry one commodity each. Without a reserve, a Barren world with an
organics lane is an infinite faucet that trivialises the supply bill entirely.

## C. Tier count versus tier identity

The complaint that tiers have no identities is right. Doubling the table to ten is
one answer and the most expensive one: `levelUpCosts`, every grant table, the
level-up preview, the construction panel and the Planet Guide's *generated* tables
are all currently indexed to six. Four of the ten would be extrapolated numeric
grants nobody has designed — which walks into the exact problem being complained
about.

The cheaper answer is **specialisation rather than more tiers**: keep six tiers
and all six numeric tables, and at tier 4+ let the world choose **one of three**
tier-appropriate abilities. Six rows of numbers, eighteen identities, and the
player *chooses* rather than accumulates.

It also solves the endgame-rarity problem without tiers 7–10. A choice feels
irreversible; a grind eventually completes. "I picked Quasar, so I can never have
Transwarp" is rarer than "I got to tier 9 eventually".

## D. The missing axis is type × level, not more tiers

What the two existing systems do:

- The triangle made **type** matter for *output*.
- Levelling made **level** matter for *capacity*.

Neither made **type matter for identity**. `levelUpCosts`, `levelDefense`,
`levelStorageScale` and every other grant table are keyed on level alone, so a
tier-4 Lava Citadel and a tier-4 Terran Citadel receive identical benefits. All
ten types share one citadel table.

This is where a "ten distinct identities" ambition is already half-spent, with
**zero new tiers** — a modifier on the grant table rather than a second table. An
ore-fed Volcanic quasar burns its own surplus; a Barren world's supply charter is
the reason it exists at all.

It also interacts with Part III: type-flavored abilities *reinforce* planet
identity rather than spending it.

## E. Tier 1 undefended, and the absence of any loss state

The most interesting line in the dead ability table is level 1: *"defenseless …
the world can be taken by anyone who lands."* The previous review kept tier 1 as a
safe no-op.

Right now nothing can land, so that line is inert. The moment invasion exists, it
turns a first colony into a genuinely vulnerable thing — and it gives levelling
teeth, because a taken world can come back at a **lower tier**.

This is the largest playability gap in the whole system and it is not in the
proposal: a six-tier treadmill where you can never lose anything is a progression
chart, not a story. Loss is what would make the defence number mean something,
and the defence number currently means nothing because nothing reads it.

## F. Make the citadel attract, not only repel

Four of the five live-able abilities in the dead table are **reactive** —
prevent theft, prevent invasion, prevent retreat. Only one (transwarp) is
initiative-taking. That is a pattern, and it argues for more identities about what
a world *does* rather than what it prevents.

Related: the gap between "my planet is big" and "my faction is powerful" is real.
The bridge is that a developed world should change the galaxy's *behaviour toward
it* — NPC traders route through sectors with developed worlds, immigrants arrive
where there is demand, faction missions target them. That would also make citadel
level legible **from the galaxy map**, which is currently uniform brown dots, and
is the cheapest high-emotion change available.

## G. What I agree with from the previous review, and would keep

- **Adopt the dead ability table rather than reinvent tier flavour.** It is
  sourced, written, and unused. Re-deriving six identities when six are already on
  disk is waste.
- **New power should come from new *kinds* of leverage, never from juiced
  ratios.** See Part III — this codebase has now paid for that lesson three times.
- **The endgame must be steeper than a linear extension.** Tiers that matter
  should be rare, and rarity should come from choice or cost, not from a longer
  bar.
- **Colonist growth needs fixing before any gate gets much higher.** The geography
  tax worsens with every tier added, and it is a small, independent change — it
  does not need the tier table extended first, and bundling them makes a modest
  change look like a risky one.

## H. Where I think the previous review was wrong

- **Survey Commission (rerolling `productionEfficiency`) fights the stated
  constraint.** Efficiency is a type-relative multiplier on capped figures. A
  Volcanic world going 0.5 → 1.3 is less volcanic. The framing is elegant, but it
  needs a *band*, not the full 0.5–1.5 range, or it spends exactly the identity
  the design is protecting.
- **Sector Influence is three features in one name.** "NPC spawn weighting,
  reputation gain, or pricing nudges" are three separate designs. Reputation gain
  collides with a deed table that already encodes hostility splits; pricing nudges
  collide with a standing-price multiplier that already feeds effective prices.
  It is not a tier ability until it is three tickets.
- **Combat Computer at tier 2** is well-motivated but mis-sequenced *as written*:
  it says invasion becomes cheap, when in truth it makes invasion *possible*.
  Every later military ability depends on the system existing, which argues for
  building it before the tier table, not inside it.

---
---

# Part III — Constraints a proposal must not undo

These are not preferences. Each is a derived rule that exists because a tuned
number could not serve the case, and the failure it fixed has already happened.

1. **The half-maximum production optimum is computed, not a field.** It cannot
   become a stored or tunable value, or a customised world can break production
   entirely.
2. **The storage floor (one game day of output) is derived, not tuned.** A flat
   per-type cap cannot serve a colony of a hundred and one of two million.
3. **The population cap is level-scaled, not flat.** A flat cap and a rising colonist
   gate were mutually unsatisfiable — seven of ten types could never reach Citadel.
4. **Per-colonist extraction stays close to flat across levels.** A steeper
   `levelDevelopment` compounds with type multipliers and caps into a ~110× spread
   and erases planet identity. New tier power must therefore be new *kinds* of
   leverage, not larger ratios.
5. **One clock.** `GameClock.tick` is the only game time. A `DateTime.now()` in a
   gameplay path is a bug even when it looks right.
6. **Anything that makes one planet type dominant at high level works against the
   whole design.** Ocean should stay the best food producer and Lava the best
   mineral source however developed either gets.

---

# Part IV — What already exists to build on

The part a reviewer is least likely to find unaided.

### IV.1 Port defence and combat — a complete system, for ports

| Level | Shield capacity | Firepower | Special ability | Shield regen | EMP drain |
|---|---|---|---|---|---|
| 0 | 500 | 30 | none | — | — |
| 1 | 1,000 | 60 | none | — | — |
| 2 | 2,000 | 120 | counter-attack | — | — |
| 3 | 3,500 | 200 | shield regen | 5% | — |
| 4 | 6,000 | 300 | all abilities | 5% | 15% |

Plus a 282-line resolution service and a 1,214-line combat screen. A port defender
is `PortDefenseConfig.defenseStats(defenseLevel)` — see Part II.A.

### IV.2 The trade-job system (T1–T10b, shipped this cycle)

`PlanetTradeService` + `TradeJob` provide: pure planning over a universe,
nearest-first port selection with splitting, a tick-driven run cadence scaled by
hops, port reservations with escrow and proportional release, four outcome
classes (delivered / lost / delayed / seized) with contextual causes, a bounded
per-world incident ledger, per-order history, and per-order freight cover priced
from the order's own risk.

**Relevant to supply lanes:** the scheduler is reusable; the accounting half is
not (see Part II.B). **Relevant to levelling:** the planner currently reads
nothing about the planet (§11.3), so tier-gated freight is a clean addition —
which makes it the natural "second axis" if the planet market is ever meant to be
strategic rather than convenient.

### IV.3 Pathfinding

`PathfindingService.bfsParents` / `distanceInTree` — id-keyed BFS shortest path,
already called by the trade planner. Anything measured in hops (transwarp cost,
convoy reach, influence radius, colonist pricing) has this to build on.

### IV.4 Destruction, and gravity

`Planet.destroy()` clears every subsystem a world owns — stores, population,
orders, incidents, order history, build timers — and removes it from the sector.
Any loss mechanic (§Part II.E) gets its cleanup for free, and gets it *correctly*:
a destroyed world leaves no ghost timers, no owed deliveries and no revenue.

### IV.5 Reputation and its deed table

`ReputationActions` encodes hostility splits, kill-vs-bounty distinctions and
standing caps in one table. Anything that wants "developing a world earns
standing" should be a **row in that table**, not a new multiplier — the split
between "hostile" and "peaceful" is already load-bearing for combat AI decisions.

### IV.6 Homeworlds and repopulation

`RepopulationService` already gates ship production on homeworld control, and
`ColonistSupply` already prices colonists by distance from the faction's own
capital using real engine-aware warp costs. Any "develop your capital" idea
attaches to an existing, correct system rather than inventing one.

### IV.7 What does *not* exist

- **No NPC goal attacks a planet.** `raidPort` targets ports only.
- **No garrison model.** `Planet.defenseLevel` is written by the tier table and
  displayed; nothing consumes it in a combat calculation.
- **No natural population growth.**
- **No freight, planetary demand, or manual port selection** — the trade planner
  has no player-facing port choice at all.

---
---

# Part V — Open questions

Answering by number is worth more than more feature ideas. Each is a real fork.

1. **Tier count.** More tiers, or a specialisation choice at 4+? (Part II.C — and
   note the migration cost of every table currently indexed to six.)
2. **Loss.** Should a colony be losable at all? If a world is taken, does it drop
   a tier, lose its garrison, lose its build progress, or something else? What is
   recoverable? (Part II.E — currently nothing is.)
3. **Type × level.** Should tier grants vary by planet type? If so, how does it
   stay legible in the UI without a 10×6 matrix?
4. **Supply lanes.** What reserve and throughput? Does the port economy survive
   free intra-sector movement, or does a lane need a price? (Part II.B.)
5. **Efficiency reroll.** Band or full range? Does it violate the type-identity
   constraint, and if so is that acceptable at one tier? (Part II.H.)
6. **Sector influence.** Split into three separate designs — reputation, pricing
   and spawn weighting have different risk profiles. Which is worth doing?
7. **Faction-gated capability.** Should the most galaxy-scale abilities (transwarp,
   interdictor) be gated on the world being a **capital**, rather than on the
   world reaching a tier? That makes developing your capital matter at the faction
   level and stops every mature world becoming a strategic weapon.
8. **Attraction vs repulsion.** Should a developed world attract visitors — NPC
   trade routing, immigration, faction missions? Or stay purely defensive?
   (Part II.F.)
9. **The second economy axis.** If not tiers, where does it live: tier-gated
   freight capacity, planetary demand/supply, manual port choice, or cost-based
   routing? (Currently the planet market has exactly one player decision: volume.)
10. **Endgame rarity.** What should the capstone cost, and what is the target
    number of worlds in a galaxy that hold it? A number, not an adjective.
11. **Colonist growth.** What rate, and does natural growth break the supply bill
    or make the store floor's "ignored world" pressure disappear?
12. **Legibility.** What is the smallest change that makes a citadel's tier visible
    **outside** the planet screen — galaxy map, sector view, scan report? A level-6
    world currently looks like a level-1 one from every distance.

---
---

# Part VI — Why this document is split the way it is

Recorded because the pattern keeps recurring and is worth naming.

The most expensive defect in this project's recent history was **signs in
user-facing text**. A detonation line said "your notoriety **rises**" — written
against a one-direction scale, and after that scale was made signed it became the
loudest possible lie on screen, telling a player they were becoming *more popular*
for blowing up a planet. The number was right. The sentence was not.

The same shape appears in code, and this document is an attempt not to repeat it:

- A help screen drifted from its model in eight places, none of which broke
  anything — a documented mechanic, a "scanner module" that does not exist, a
  column count that was off by one so every value was labelled one column to the
  left, and a hand-typed figure that was wrong by a factor of 2,880 while the guard
  covered two of its three numbers.
- A guard described a mechanism the code did not use: a comment credited a
  `continue` with enforcing a promise that the arithmetic already enforced, and
  deleting the line changed nothing.
- A test asserted a marker *appears* while the number it annotated was free to lie,
  because the marker was driven by a different field.

So: **Part I is what the code does. Part II is what one person thinks about it.
Part III is what must not change. Keeping them in separate sections is the whole
point** — a reviewer reading Part I as requirements is reading it correctly, and a
reviewer reading Part II as requirements is being misled by the document rather
than by the design.