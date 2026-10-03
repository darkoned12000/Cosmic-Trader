# Citadel & Planet Levelling — as built

A reference snapshot of the levelling and production systems, taken from the code
on the `planet-econ` branch. It exists to be handed to another model for
proposals, so every figure below is one the reader can verify against the file
named beside it.

**Read this first.** There are two citadel systems in the codebase and only one
of them is live. See [§11](#11-the-two-systems-warning).

| Section | File the claims come from |
|---|---|
| Tiers, costs, build time, grants | `lib/data/models/planet.dart` |
| Production triangle, class tables | `lib/data/models/planet_classes.dart` |
| Per-tick pass | `lib/services/planet_production_service.dart` |
| World generation | `lib/data/models/universe_generator.dart` |
| Live tuning | `lib/data/models/planet_classes.dart` (`PlanetClassTuning`) |
| Full design narrative | `planets.md` |

---

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
to be. See [§10](#10-known-gaps-worth-filling-first).

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

Applied by `Planet._applyLevelGrants()` when a build completes. **Nothing else in
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
stepper; see [§5.3](#53-drones).

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
`storesEmpty` flag — not inflicted. This is the third derived-not-fixed balance in
this model, after the storage floor and the level-scaled population cap.

Production lands **before** upkeep is charged, so a colony that farms its own
food stands still rather than spiralling.

---

## 8. Per-planet fields

| Field | Range | Notes |
|---|---|---|
| `productionEfficiency` | `0.5`–`1.5` uniform, rounded to 1 dp, rolled at generation | **Never displayed anywhere.** Roughly half of all generated worlds start below 1.0. See §10. |
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

The split is the point:

- A player can edit **values** — ratios, caps, build times.
- The player **cannot** edit the **rules**. The half-maximum optimum is computed,
  not a field, and the fighter ceiling is derived from output. So a customised
  world cannot end up violating the relationship the Planet Guide documents.

`GameSettings` populates the overrides; a null entry means "use the default".

---

## 10. Known gaps, worth filling first

Ordered by cost-to-value, not by importance to the design.

1. **`productionEfficiency` is invisible and halves output on ~half of all
   worlds.** A `[0.5, 1.5)` roll at generation, never surfaced in any UI. A player
   comparing two identical Terran colonies finds one produces half as much with no
   explanation and no way to act on it. This is the cheapest high-value fix on the
   list — one label on the colony card.
2. **The 4→5 and 5→6 gates need purchasing**, and purchase is priced by distance
   from your faction's capital. Levelling pace is therefore gated on geography the
   player did not choose. Natural population growth is the real fix and is
   acknowledged as outstanding.
3. **Levelling has no effect on freight or trade.** The trade planner reads
   nothing about the world — not its level, its type, or its storage. A level-6
   Citadel and a level-1 Outpost have identical freight capability, so citadel
   development affects the *economy* only through raw output and storage.
4. **Level 6 buys no additional defence level.** 5→6 is shield and armour only,
   which makes the final tier's headline less legible than the one below it.
5. **Invasion and combat are stubs.** The planet screen's Attack action writes to
   the action log only. Defence, shield and armour are modelled but nothing
   currently attacks a colony.
6. **Homeworlds are not citadel-linked.** `RepopulationService` drives ship spawn
   cadence from the homeworld flag, not from citadel level, so a player's capital
   and their best-developed world are unrelated.

---

## 11. The two-systems warning

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
| 3 | **Quasar cannon** — fires at anything entering the sector, anything landing, or both. Burns fuel ore; 1 ore per 1 damage atmospheric, 3 per 1 sector-firing. Bypassable by photon missile unless planetary shielding covers it. |
| 4 | **Planetary transwarp drive** — move this world to any sector where you have dropped a fighter, 400 ore per sector jumped. |
| 5 | **Planetary shielding system** — planetary shields must be destroyed before invasion, 20 damage each. Ten ship shields make one planetary shield. |
| 6 | **Planetary interdictor generator** — makes it difficult for an enemy to retreat from the sector. Similar to a tractor beam. |

Meanwhile the **live** levelling is the completely separate set of tables in
`planet.dart` described in §1–§4, which grants storage, population cap,
development, defence level, shield and armour — none of the above abilities.

So: two sources of truth, one wired. Any design work has to decide which it is
extending. The prose table is a ready-made source of six *distinct* tier
identities, which the current numeric tables do not have — every level is
"bigger numbers", with the single exception of defence saturating at 5.

---

## 12. Design intent, for context

The stated goal for the levelling curve is that level buys **capacity and
defence**, and buys them **hard**, while per-colonist extraction stays close to
flat. That is deliberate: a steeper development curve compounds with type
multipliers and population caps into a ~110× spread and erases planet identity —
everything worth having would end up on one planet type. An Ocean world should
remain the best food producer and a Lava world the best mineral source no matter
how developed either gets.

Consequences worth respecting in any proposal:

- Anything that makes one type dominant at high level works against this.
- The **storage floor** and **level-scaled population cap** are both derived
  rules, not tuned numbers. Replacing either with a flat figure reintroduces the
  bug they were built to fix.
- The **half-maximum optimum** is the second such rule. It cannot become a stored
  value.