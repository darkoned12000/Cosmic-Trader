# Cosmic Trader — Performance

Measured, not guessed. This file exists because the development universe is **500
sectors** and the target is **20,000+**, and at that size the answers change.

Nothing here is urgent today. It becomes urgent somewhere around **2,000–5,000
NPCs**, which the 20,000-sector target reaches.

---

## The clock: one tick, and it does everything

There is **one** game tick. `lib/services/game_tick_service.dart` runs a single
`Timer.periodic(30s)`, and one pass does all of:

port regen → NPC turns → repopulation → ship production → colony production →
gravity sweep → combat census → bounty prune → Fed bounties → NPC interest →
wreck clearing → attack check

Every other `Timer` in the app is **UI-local**, not a game clock — the planet
screen's 1-second poll, the port screen's 3-second save flush, animations,
hold-to-repeat, and the mini-game countdowns.

That is deliberate and should stay that way. See *Why not to stagger the tick*.

---

## Measurements

Taken in the `flutter test` VM (JIT), so treat them as indicative: an AOT release
build is faster, a mobile device slower. Sector count drives planets at 3/sector;
NPC count is a per-sector coin flip, and the default densities sum to **0.35 per
sector**, so 20,000 sectors implies **~7,000 NPCs**.

### The whole-universe JSON round trip

The tick **saves** the universe every pass and **re-parses** it at the top of the
next one. Both are JSON over the entire galaxy.

| sectors | planets | JSON size | encode | decode | round trip | % of a 30s tick |
|---|---|---|---|---|---|---|
| 500 | 1,500 | 1.4 MB | 20 ms | 22 ms | 42 ms | 0.1% |
| 2,000 | 6,000 | 5.8 MB | 38 ms | 46 ms | 84 ms | 0.3% |
| 10,000 | 30,000 | 29.2 MB | 182 ms | 191 ms | 373 ms | 1.2% |
| **20,000** | **60,000** | **58.7 MB** | **353 ms** | **388 ms** | **741 ms** | **2.5%** |

### The other per-tick passes that scale with sectors

| sectors | colony production | repopulation | gravity sweep |
|---|---|---|---|
| 500 | 4 ms | 0 ms | 0 ms |
| 2,000 | 8 ms | 0 ms | 1 ms |
| 10,000 | 25 ms | 4 ms | 2 ms |
| **20,000** | **40 ms** | **2 ms** | **6 ms** |

All fine. Together with the JSON round trip that is ~800 ms, about **2.7% of a
30-second tick**.

### The NPC sweep — this is the problem

| NPCs | total | per turn |
|---|---|---|
| 1,000 | 553 ms | 0.55 ms |
| 3,000 | 3,199 ms | 1.07 ms |
| **7,000** | **10,389 ms** | **1.48 ms** |

**Per-turn cost rises with roster size**, so the total is roughly **O(n²)**. At the
20,000-sector NPC count that is **10.4 seconds of a 30-second tick** — about 35% of
the budget, in the test VM, before the JSON round trip is added.

---

## The cause: roster scans inside per-NPC turns

Not "one big tick doing too much". At least **15 loops over the full `allNpcs`
list run inside per-NPC turn paths**:

| file | lines |
|---|---|
| `npc_goal_executor.dart` | 162, 703, 718 (`any`), 831 (`indexWhere`), 1024, 1044 (`indexWhere`), 1418/1426 (`firstWhere`), 1466/1467 (`indexWhere`) |
| `npc_goal_planner.dart` | 45, 479, 492, 545 |
| `npc_ai_service.dart` | 158, 572 |

Most are id lookups — `allNpcs.firstWhere((n) => n.id == npc.id)` for a ship the
caller **already holds**. Each is O(roster) inside a loop over the roster, which is
where the n² comes from.

**The fix already exists.** `NpcAiService.beginTick` builds `sectorById`,
`npcById` and `npcsBySector` once per tick. The pattern is there; those sites
bypass it.

---

## Why not to stagger the tick

The idea is reasonable and the answer is no, for two reasons.

**1. One tick number is a correctness invariant.** Every deadline in the game is
read against the same `GameClock.tick`. If port regen ran on a different cadence
from NPC turns, an NPC could trade against a port whose demand has not refilled
*in that schedule* — two notions of "now" inside one pass. That is precisely the
two-clocks defect this project has already paid for twice: port refill, bank
interest, hack ban, sabotage, lottery and bounty TTL were all on the wall clock and
all had the same class of bug (a sold-out market restocking overnight; quitting
clearing a ban).

**2. Staggering does not reduce work, it spreads it.** The same total happens per
unit of time. It helps with frame hitches, not throughput, and it makes tick cost
unpredictable. It would not touch the actual problem either — the NPC phase alone
exceeds the budget.

**Stagger entities, not subsystems.** Each NPC acting every K ticks, offset by
index, is safe: it is a per-entity budget, and the tick number stays one. That is
worth keeping in reserve, though the index refactor below should make it
unnecessary.

---

## Plan, in order of value

| # | Change | Why | Size |
|---|---|---|---|
| **P1** | **Index the 15 roster scans** against the per-tick indices that already exist | Removes the O(n²). Biggest single win, and it is a contained refactor rather than new infrastructure | Medium |
| **P2** | **Stop re-parsing the universe every tick** — hold it in memory in `UniverseStorage` and let the tick mutate it | Removes 388 ms + a 58.7 MB read per tick, and it is the documented *"one universe, two object graphs"* debt. It also removes the concurrent-write clobber class, where a tick's write-back erases a screen's save | Large |
| **P3** | **Stop writing the whole universe every tick** — dirty sectors only, or per-sector files, or SQLite | 58.7 MB rewritten every 30 s is ~170 GB/day if left running. That is disk wear and battery more than CPU | Large |
| **P4** | **Re-measure at the real NPC count** before optimising anything else | Everything above is estimated from 7,000; the real number depends on the final densities | Small |

**P1 first** because it is the only one that removes work rather than moving it, and
because it is the smallest.

**A note on P3.** The tick currently saves unconditionally, and that was a
*correctness* fix: the save used to be gated on a hand-maintained list of "things
that might have changed", and a colonist shipment's countdown was not on that list,
so the countdown reset every tick and the shipment could never arrive. A dirty-set
save has to be done carefully for the same reason — **the set of things that mark a
sector dirty is exactly the list that was wrong before.** Any replacement should
mark dirty inside the mutation, not at the call site.

---

## What is *not* a problem

- **Colony production** — 40 ms at 60,000 planets.
- **Gravity, repopulation, census, bounty pruning** — single-digit milliseconds at
  20,000 sectors.
- **The `1 + warpRoutes.length` proximity BFS** — bounded to 2 hops per player, so
  it does not scale with the galaxy.

---

## Reproducing the numbers

The benchmarks were scratch harnesses and are not in the suite. Two places to put
them if this becomes active work:

- `test/scaling_benchmark_test.dart` already exists and already measures a
  300-sector / 200-NPC sweep. Extending it with a 20,000-sector / 7,000-NPC case
  would make the numbers above a regression guard rather than a one-off.
- The `DevProfiler` spans in `GameTickService` (`tick_port_regen`,
  `tick_npc_processing`, `tick_colony_production`, …) are already wired and are the
  in-game way to read live tick cost.
