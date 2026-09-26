# Cosmic Trader — Improvement Update

> A thorough review of the Cosmic Trader (formerly Tradewars 2050) codebase —
> gameplay mechanics, look & feel, and NPC AI — prepared after a full code
> review and the "Cosmic Trader" rebrand (committed `c39cbe3`).
> Date: 2026-09-23 · Branch: `ui-scale`

---

## 0. Current strengths (foundation to build on)

- **NPCs are not "sit and die" today** — `npc_ai_service.dart` already has:
  pre-engagement threat evaluation (`_evaluateThreat` → immediate flee when
  outmatched), a flee goal with destinations, a hull ≥ 30% gate before
  attacking, distress signals with allied response, death cries, banking,
  profit-per-hop trade routes, BFS pathfinding, and port-owner defense
  retaliation. The AI foundation is genuinely good for a BBS-era tribute.
- **The economy skeleton is right** — data-driven commodities with a
  guaranteed price-split means every route is inherently profitable; a strong
  base for a dynamic market later.
- **The lore is rich and mostly unused in gameplay** — each faction has
  history, philosophy, `loreHooks`, and named `notableHeroes`. That is content
  fuel for quests, events, and hero NPCs.
- **The layout stack is clean** — `TWLayout` breakpoints + `TextScaler` mean
  scaling *can* be fixed centrally rather than screen-by-screen.

---

## A. Look & feel

### A1. The 4K problem: we scale *text* but not *UI* (root cause)

- `main.dart` (lines ~96-99) wraps the app in `MediaQuery.textScaler`
  = font-size/14. **This scales text only.**
- Every panel, padding, icon, map node, and table row is sized in fixed
  logical pixels: `SizedBox(height: 12)`, `nodeRadius` passed into
  `GalaxyMapPainter`, `fontSize: 11/12/13` sprinkled everywhere.
- At 4K with 100% OS scaling, Flutter sees a ~3840x2160 logical canvas.
  Bigger text is rendered inside panels sized for ~1440p → cramped text,
  overflowing rows, tiny icons next to big text.
- The desktop default window is `1280x720` (`main.dart` ~32-33) regardless of
  display → opens small; fullscreen simply *stretches* panels (sector view is
  `Expanded` panels with no max-width clamp) → ~1500px-long unreadable lines.

**The fix — a real UI scale system (build first):**

1. **Global "UI scale" knob** (0.8–2.0) multiplying design tokens: spacing,
   icon sizes, card min-heights, table row heights, map node radii, star
   density. Text scaling (the existing font slider) stays separate. Add
   `lib/core/ui_scale.dart` with helpers like `pad(12) → 12 * scale` and
   migrate the most-scaled widgets (sector view, port tables, galaxy map,
   tactical map, combat).
2. **Auto-detect on desktop** — read display pixel density / resolution at
   startup and *suggest* a UI scale (e.g. physical width ≈ 3840 → scale ~1.5);
   preset "Default / Comfy / Cozy", plus "apply on next launch".
3. **DPI-aware default window** — instead of fixed 1280x720, open at ~75% of
   the work area and remember it per monitor unless the user pinned a size.
4. **Clamp panel widths on wide screens** — sector view panels cap at
   ~420–520px on 4K; let the galaxy/tactical maps absorb the extra width.
   (`TWLayout.maxContentWidth = 800` exists — apply the same idea to panels.)
5. **Density toggle** — "Compact / Normal / Cozy" global setting feeding the
   same tokens (compact HUD-style trade view already exists in
   `port_trade_view.dart`).

### A2. Shared widget library (also unblocks scaling)

Cards, stat bars, and pills are copy-pasted across screens (already noted as
debt in AGENTS.md). Build `PanelCard`, `StatBar`, `HudPill`, `DataTableShell`
once — with the UI-scale tokens *inside* them — so one knob fixes the whole
app instead of 40 places. This is the right first branch: fixes 4K pain and
removes duplication debt at the same time.

### A3. Look & feel polish (sizeable wins)

- **Warp transition** — animated jump (star streak / hyperspace flash ~300ms)
  between sectors. Big feel upgrade, masks sector load.
- **Persistent HUD strip** — sector name, credits, turns/energy, hull/shields
  always visible at the top instead of buried in tabs. (The single biggest
  "easy GUI" improvement.)
- **Consistent faction color language** on all screens (maps already
  color-code factions) + per-sector faction *ambiance* tint.
- **SFX hooks** — `audio_service` + SFX volume exist but are barely wired;
  add SFX for buy/sell, hits, warp, lottery, hack.
- **Table readability** — zebra rows, aligned monospace numbers, sortable
  columns in Port Report.
- **Desktop affordances** — hover cursors + tooltips, keyboard shortcuts
  (arrows/scroll on map, `T` warp, `S` scan).
- **Typography** — sci-fi display font for headers, monospace for data tables.

---

## B. Game mechanics (TW2002-inspired depth)

Ordered roughly by leverage-per-effort. Many are already on the roadmap;
ranked with the missing context.

### B1. Turn → Energy system
`'turns'` don't suit online play (our own roadmap). Energy pool that
regenerates over time (or per tick), warp cost scales with distance + the
**engine efficiency stat (already in the model)**. Do this before economy
work — it changes session pacing.

### B2. Dynamic economy (in progress — measurement first)

**Spec (remaining):**
- Weighted random walk (±2–5%) on prices per tick with mean reversion toward
  the base range.
- Supply/demand actually moves prices: buying lowers supply *and* nudges the
  port's prices up; selling reverses. Supply/demand tracking already exists
  locally — just hook it into pricing.
- Regional/faction modifiers: near faction homeworlds that faction's preferred
  commodity gets a premium; anomalies (already generated) boost/depress
  adjacent sectors.
- Add lore-fitting commodities: Food/Ore (planet trade), Vinari crystalline
  tech, Duran military hardware, black-market Contraband — 2 entries each in
  the commodity registry.

**Status:**

1. ✅ **Economy metrics + report** — new `lib/services/economy_metrics.dart`
   (`EconomyMetrics` singleton: volume, transactions, units,
   player-vs-NPC split, per-commodity avg prices, per-faction net flows,
   trades/min; persisted across restarts via economy_metrics.json —
   restore on launch, save on exit, reset clears; the same payload is the
   ongoing health feed on a server build). Hooks in NPC trade buy/sell phases and player
   `PortTradeView` buy/sell (1 unit/tap). New Computer → **Economy Report**
   screen (`economy_report_screen.dart`: totals, per-commodity avg-vs-base
   table, per-faction net table, reset action). Covered by
   `test/economy_metrics_test.dart` (3 tests).
   - Refined: combat/raid spoils tracked separately (`recordLoot` hooks in
     NPC-vs-NPC resolution + player victories) with a Spoils total and
     per-faction Loot column, so fighter income never masquerades as market
     flow. Faction table also shows live **Holdings (est.)** — NPC cargo at
     base-mid valuation from `NpcStorage` — so mid-route inventory reads as
     wealth in flight instead of negative net.
2. ✅ **Supply-level pricing** — ports now charge scarcity/glut pricing:
   full shelves 0.75x → bare shelves 1.25x on goods sold
   (`supplyPriceMultiplier`), full demand book 1.25x → satisfied 0.75x on
   goods bought (`demandPriceMultiplier`), neutral at half, per-side only
   (sell depth never leaks into buy prices), composing with the existing
   cash-ratio multiplier while owner overrides still win outright. Heavy
   trading on one good compresses its own spread, rotating NPC route
   selection naturally. Covered by `test/port_supply_pricing_test.dart`
   (5 tests).
3. ✅ **Drift + mean reversion** — per-tick ±3% random walk per traded
   commodity with 15% reversion toward 1.0, clamped [0.7, 1.4], stored in a
   persisted `priceDrift` map (legacy saves default neutral), applied in the
   tick port loop before NPC processing, composing under cash/depth layers
   with overrides still absolute. Quiet ports now move too. Extended
   `test/port_supply_pricing_test.dart` (bounds, determinism, reversion,
   round-trip, override precedence).
4. ✅ **Commodities + black market** — registry grows 3 → 8 goods (food,
   ore, crystalline, munitions, contraband with a 300–800 risk premium).
   Contraband is restricted at generation: only free/independent ports deal
   it (30% of them, `isBlackMarketPort` rule), federal/emporiums never;
   others get an `'X'` (untraded) slot with explicit skip logic in price/
   quantity/credit generation plus short-type guards for old saves. Old
   settings files merge new defaults (player edits preserved). Loot loop
   closed on both sides: NPC victors take victim cargo capped by free holds
   (was computed then dropped), and player victories transfer cargo
   contraband-first with overflow lost. Covered by
   `test/black_market_test.dart` (4 tests).
5. ✅ **Regional modifiers** — homeworld premiums (Duran→munitions,
   Vinari→crystalline, Trader→industrial at 1.30/1.20/1.10 over 0/1/2-hop
   BFS rings, max wins on overlap; pirates hold no homeworlds) and anomaly
   boom/bust (1.10/0.90, deterministic per anomaly name, sector + warp
   neighbors). Computed once in a Phase 8b pass and denormalized onto ports
   (`regionalBuyBonus`/`anomalyBuyBonus`, buy side only, persisted with
   neutral legacy defaults) so pricing stays a cheap read. Extended
   `test/port_supply_pricing_test.dart` (premium/boom-bust/composition/
   round-trip).

**B2 complete.** Remaining economy work (if wanted) lives beyond the spec:
tighter/looser bands, contraband enforcement hooks (B3 standing), planet→
port supply (planet-phase2).

### B3. Give FactionStanding teeth (in progress — access + interest done)

Standing was produced everywhere (trade/combat/hacks) and consumed nowhere.
Slices: (1) port pricing ✅, (2) emporium access + banking interest ✅,
(3) attack-on-sight + FedSpace consequences.
1. ✅ **Standing-discounted pricing** — ±100 standing moves both sides 20%
   (clamped [0.8, 1.25]): friends buy cheaper and sell richer. New
   `getEffectiveSellPriceFor`/`BuyPriceFor(commodity, standing:)` (neutral
   overloads preserved); player trade view prices via
   `factionStandingWith(port.ownerFaction)`; NPC execution + route
   selection price via `FactionStanding.resolveFor` (persisted → lore
   defaults → 0), with `ownerFaction` added to `PortInfo` (scanned +
   persisted) so selection matches execution. Covered by
   `test/standing_pricing_test.dart`.

2. ✅ **Emporium access + banking interest** — ports at standing ≤ −50   refuse service: player emporium UI replaced by a refusal card (with the
   number and how to fix it); NPC pathfinding skips hostile emporiums and
   arrivals fail cleanly (`refuel_refused`, replanned same tick). Bank rate
   follows Trade Guild standing, 0.5%–1.5% around the 1% base
   (`BankingAi.interestRateFor`, shared by player banking and per-tick NPC
   accrual with 24h periods, first balance starts the clock). Covered in
   `standing_pricing_test` (refusal threshold, NPC skip + roam, rate math,
   accrual timing).
   - Found by test: `_move` steered by dead (failed/complete) goals
     (refused-refuel ping-pong between two sectors) — movement now only
     follows travelling goals; `_selectGoal` walks the weighted pool past
     null instantiations instead of wasting the tick.
   - **Fuel-crisis fixes (live: zero emporiums, all-NPC refuel_unknown
     lock):** density left ~29% of universes with no emporium at all —
     `ensureMinimumEmporiums` guarantees ≥1 (outside FedSpace, books
     preserved); the unknown-emporium explore fallback no longer fires
     every tick under 25% energy (it permanently suppressed step-5
     selection, freezing trade/bank/attack) — committed goals now run
     dry toward stranded reserves instead. Covered by
     `test/emporium_guarantee_test.dart`.
   - Pirate-exile safety: unowned emporiums serve everyone, standing
     recovers through ordinary trade, and Emergency Tow prefers servable
     emporiums (hostile pumps skipped, any emporium then any port as
     fallbacks). Covered in `tow_service_test`.
   - **NPC port ownership (all factions):** only Duran/pirates could raid,
     so Duran captured 30 ports to everyone else's 0 — and raid targeting
     had no power check (pirates sieged unbeatable defenses). Raids now
     gate on a real siege estimate (`canRaidPort`: survivable rounds ×
     damage vs shields); rich traders/collectors/seekers buy unowned
     non-federal ports outright at half net worth (new `buyPort` goal);
     owners collect revenue and buy defense/storage upgrades (50k reserve
     kept) every tick. Covered in `npc_goal_lifecycle_test` (purchase,
     raid gate, collect + upgrade).
   - **Repopulation (C4 first slice):** pirate predation with no respawns
     wiped Duran/Vinari to zero live — `RepopulationService` tops factions
     to 3/3/3/2 floors, one ship per faction per tick, at homeworld sectors
     (kill loot cut 50%→25% to slow the snowball). Homeworlds spawn only
     while owned-or-unowned: captured homeworlds log
     `has no controlled homeworld — no spawn` until recaptured, so
     extinction is possible and reversible; pirates keep random-sector
     fallback pending outposts. Covered in `repopulation_service_test`
     (homeworld spawn, healthy no-op, capture/recapture cycle).

   - **External review batch 4 (Claude: generator remainder):**
     fedSpaceEnd=1 hard crash guarded; profitability docstring corrected
     (base-only guarantee, effective layers may invert near-split routes);
     NPC persistence de-raced (generate() pure, caller awaits save);
     homeworld collisions excluded + silent-drop logging; display counts
     reconciled to the real roster (galaxy map showed phantoms);
     co-spawned hostiles accepted as deliberate; Terra Prime seed
     documented. Plus the suggested integration suite
     (`universe_generation_test`: connectivity, homeworlds, emporium
     minimum, count truth, base-price invariant, 10-tick NPC health).

3. ✅ **Fear + hatred (no always-attack):** notoriety inflates perceived
   power ×(1 + notoriety/200) on both sides of every fight decision —
   infamous pilots deter attacks below overwhelming odds and clear
   sectors as weaker ships flee rather than provoke; personal standing
   ≤ −50 substitutes for lore hostility but demands a decisive 1.5× edge
   (grudges don't make NPCs suicidal). Fed enforcement deliberately NOT
   a police force: crimes feed notoriety → the B4 bounty board, placed in
   the Computer area. Covered in `test/fear_hate_test.dart` (deterrence,
   hatred gates, fear flee).

   - **External review batch 6 (Claude: combat/bounty re-read):**
     ownership keyed by stable id (`Port.ownerId`, set on every buy and
     capture path incl. player flows) with name fallback for legacy saves —
     a pilot-name collision can no longer collect or defend another's
     port; per-tick owner index (`ownedPortIndex`, index path + scan
     fallback tested) replaces the O(sectors)-per-NPC management scan;
     rankings match owners by id first. Covered in
     `npc_goal_lifecycle_test` (id/name precedence, indexed collection).
   - **External review batch 7 (Claude: combat/bounty/economy/report):**
     player loot matched to 25% + floor (the larger snowball half);
     raid gate recalibrated onto the real siege formulas
     (totalWeaponPowerx50 power, counter/EMP incoming, free finishing
     round); siege core consolidated (`resolveRound`, one math path for
     both attacker types) with mode/portDestroyed documented as
     post-siege labels; metrics record actor-net amounts (fee-inclusive)
     with normalized faction keys; report reset reloads holdings.
     Deferred with rationale: EMP-as-strip redesign, variance profile,
     drone power (C-branch). Covered: existing raid/loot/metrics tests
     hold under new formulas + casing test.


   - **External review batch 3 (Claude: tick/port/generator):** cross-file
     safe-zone boundary unified (`safeZoneEnd` statics synced from settings
     instead of two hardcoded 10s); effective-price stack capped [0.25,
     4.0] on the *multiplier* (plus a caught self-bug: clamping the price
     turned 10cr goods into 4.0); NPC memory now snapshots full local
     pricing (depth/drift/regional/anomaly factors) so selection matches
     execution; regen no-op returns identical (saves I/O); anomaly overlap
     composes multiplicatively (order-independent) instead of
     last-write-wins; emporiums carry real desiredCredits; tick attacks all
     players (proximity union) with logged unknown-sector fallback;
     3-strike goal reset for erroring NPCs; attack-goal selection reuses
     the trigger margin (no more cross-map chases for refused fights).
     Covered in `port_supply_pricing_test` (ceiling semantics) + suite.

### B4. Bounties & pirate pressure (in progress — board live)

- Fed ports post bounties on pirates — and on the player as `notoriety`
  climbs (`notoriety` already exists on Player).
- Bounty hunters appear (see NPC AI); hunting a marked pilot yields credits +
  standing. Feed kills/bounties into the existing Power Rankings report.

**Status:**

1. ✅ **Bounty Board (Computer tool)** — `bounty.dart` model + `bounties.json`
   store + `BountyBoard` singleton (post/stack/pay/claim, 20-deep paid
   history, persisted). Anyone posts: players from the board view (credits
   deducted, live NPC target picker), NPC survivors auto-post 5k from
   their bankroll on surviving an attack. NPC kills pay the killer
   instantly; player kills record victim ids (`Player.recentKills`, capped
   50) and pay through the board's Claim action. Loaded at shell start so
   persisted bounties resolve. Covered by `bounty_board_test.dart`.
   - **External review batch 5 (Claude: bounty files):** claim()
     verifies kills itself (`verifiedKills` param — UI gate alone could be
     bypassed to drain stacked bounties); debit-before-post ordering on
     both call sites with refund fallback; persistence failures logged
     instead of swallowed; dispose() override removed (lifecycle footgun);
     dead 60-char check removed. Confirmed already-wired (reviewer
     couldn't see the files): payKiller in NPC kill resolution,
     recentKills in player victories. Covered in `bounty_board_test`
     (verified claim, denial, double-claim).

   - Rankings copy action (full faction/pilot/most-wanted text dump);
     NPC port price cut to 10% of net worth (floor 25k) — half-net-worth
     priced every NPC out forever, which is why only raiders ever took
     ports.

2. ✅ **Fed enforcement + hunters + rankings + completion standing**
   (B4 spec closeout: kills pay credits AND +5 with posting factions —
   `posterFaction` persisted, NPC memory + player standings updated on
   both payout paths).

2. ✅ **Fed enforcement + hunters + rankings** — Federation
   auto-posts notoriety×100 (min 5k, max 100k, ≥50 notoriety, max 3/tick,
   skips already-marked) as the answer to federal crime — no police
   force; greedy hunters (greed ≥ 0.7) take the highest open contract
   over the weakest victim; Power Rankings gained a Most Wanted top-5
   feed. Board form now takes custom reasons (≤60 chars) with
   type-ahead pilot search. Covered by `bounty_board_test` (Fed amounts,
   greedy preference) + live verification pending.

**B4 complete.**

### B5. Finish the planet loop (planets.md Phase 2) and tie it to the economy
- Per-tick automated production (UI already computes rates — just process).
- Planet-to-port supply: colonies feed nearby port supply, shifting prices
  (ties into B2).
- Invasion combat with existing defense stats; homeworld repopulation (fields
  exist on Planet, unwired); backup homeworlds.

### B6. Port depth (roadmap: full upgrade tree)
Owned ports generate revenue into storage; add storage/specialist upgrade
tiers (cargo capacity, better pricing tools, trade-network links between
owned ports for auto-supply). TW2002's star-base metaphor fits.

### B7. Small but high-feel TW2002 touches
- **Sector notes / beacons** — `Sector` has `hasBeacon/beaconOwner/beaconText`
  and `SectorKnowledge` has bookmarks/notes; both modeled, **zero UI**. A
  notes panel on the Galaxy Map becomes the "Navigation Computer" instantly.
- **Galaxy event log** — a Comm News feed of wars, booms, raids; feeds quests.
- **Bank loans** — 1% interest + NPC banking exist; add "borrow up to X,
  repay with interest" for both players and NPCs.

---

## C. NPC AI — from "reacts" to "lives"

NPCs are already reactive and goal-driven. What's missing is **memory, social
structure, and mid-combat reactivity**.

### C1. Mid-combat intelligence (highest-value gap)
- **Damage-based flee during player combat** — chance each round to break
  engagement when hull < caution-scaled threshold; players must commit to
  kills. Add a disengage move gated by engine stats.
- **Faction-flavored surrender/fight rules (uses the lore!)**: Duran warriors
  rarely flee; Vinari almost always disengage; Traders bribe/parley; Pirates
  fight hard when cornered but flee when overwhelmed. (Currently it's a
  generic "aggressive never flees".)
- **Reinforcement during combat** — when an NPC is attacked, allies within
  1-2 hops warp in after 1-3 turns. Distress signals already exist; this
  "completes" them. Combat becomes tactical: finish the kill or break before
  the wing arrives?

### C2. Memory & grudges
`NpcMemory` is port/sector recall for trade. Add:
- **Player encounter memory** — "that pilot shot me" → vendetta goal, avoids/
  attacks that player specifically, tells allies within range (gossip).
- **Event-based avoidance** — NPCs mark dangerous sectors and reroute; feed
  danger into the trade-route evaluator.
- **Route learning** — remember profitable routes from `TradeEvaluator` and
  revisit them.

### C3. Coordination & formations (roadmap: fleet/NPC coordination)
- **Convoy goal** for Traders (group up, escort); **wolf-pack raiding** for
  Pirates (ambush high-value lanes); **border patrols** for Duran (hold map
  segments — matches their lore).
- **Shared intel** — if one NPC spots the player, allied factions in the
  region know approximately where (probability-weighted "last seen"); bounty
  hunters actively *hunt* (predict destinations with BFS, intercept).

### C4. Repopulation & living galaxy (roadmap; lore gold)
- Wire homeworld spawn fields (`productionTimer`/`spawnInterval` already on
  Planet) to the game tick.
- **Named Heroes from the lore** — `Faction.notableHeroes` is unused data.
  Spawn lore heroes occasionally: better stats, bounty, unique Hail dialogue.
- **Personality drift** — survivors get more cautious, victors more
  aggressive; NPCs "grow" within the same 12 archetypes.

### C5. Danger/tension curve
Current gating (`npcPower > playerPower * threshold`) keeps early game safe —
good. Add late-game pressure: as `notoriety` climbs, pirates specifically
target the player and bounties attract hunters. The universe should get
meaningfully more dangerous as the player gets richer.

---

## D. Easy-GUI theme (ties A + B + C together)

- Persistent HUD (A3) + keyboard shortcuts + tooltips = "feels like a game,
  not a form."
- **Navigation Computer** (B7) = the answer to "where do I go to make
  money?": show "best profitable port within 5 hops" in the Warp Console using
  the same `TradeEvaluator` the NPCs use.
- One consistency pass over dialogs using the shared widget library from A2.

---

## Suggested plan (phases → branches)

| Branch | Scope | Why first |
|---|---|---|
| **1. `ui-scale`** | UI-scale tokens (+global scale) + shared widget library + 4K/DPI auto-detect + panel width clamps + density toggle | Top pain; unblocks all visual work |
| **2. `living-economy`** | Dynamic prices, supply/demand → pricing, faction/regional modifiers, black market, standing consequences, bounties | Biggest gameplay lever; feeds NPC behavior |
| **3. `living-npcs`** | Mid-combat flee/parley/reinforcement, memory & grudges, coordination, repopulation + lore heroes | The "not dumb NPCs" goal; builds on HUD + economy |
| **4. `planet-phase2`** | Automated production, invasion, homeworld repopulation, planet→port supply | Completes the half-built system; ties to economy |

Each branch is independently shippable. Start with **1 (`ui-scale`)** — the 4K
pain blocks dev time itself, and it's the lowest-risk branch (tokens + one
widget layer before touching deeper systems).

---

## E. Technology & architecture review (2026-09-23)

Verdict: the core stack is solid — Flutter + custom widgets/painters + a
hand-built GUI is the right tool for a turn-based management/trading game.
No game engine (Godot/Unity/Flame) and no rewrite is warranted. **Four**
targeted improvements follow; everything else stays as-is.

### E1. Current stack scorecard

| Layer | You use | Verdict |
|---|---|---|
| Framework | Flutter 3.47.5 / Dart 3.6.2 | ✅ Keep — ideal for a 6-platform GUI game |
| Rendering | Widgets + extracted `CustomPainter`s (galaxy/tactical maps) | ✅ Keep — right call; no engine needed |
| State | Callbacks in `GameShell` + `ValueNotifier`s (theme) + one global `ChangeNotifier` | ⚠️ Works — formalize only when it hurts |
| `provider ^6.1.2` | Declared in pubspec, never used | ⚠️ Removed on `ui-scale` (dead dep) |
| Storage | Hand-written JSON in app documents dir | ⚠️ Made crash-safe (atomic writes); DB later if data grows |
| Passwords | **Unsalted SHA-256** (`player.dart:323`) | 🔴 Weak — upgrade to salted bcrypt/argon2 |
| Models | Hand-written `copyWith`/`toJson`/`fromJson` (~15 classes) | ⚠️ Boilerplate — codegen (freezed/json_serializable) would help |
| Audio | `audioplayers` | ✅ Fine for music + sparse SFX |
| Desktop window | `window_manager` | ✅ Standard; keep |
| Icons/SVG | `flutter_svg` + Material icons | ✅ Fine (3 SVGs) |
| Tests/CI | 2 smoke tests, no CI | 🔴 Thinnest area — see E5 |

### E2. Improvement 1 — Storage: crash-safe today, DB when it pays

- Today every save was `file.writeAsString` directly (e.g.
  `universe_storage.dart`) — a crash mid-write can corrupt the file. The
  `_playerUpdateVersion` counter in `game_shell.dart` is a symptom: no race
  control between the tick service and UI saves.
- **Done on `ui-scale`:** `lib/data/storage/file_safe.dart` —
  `FileSafe.writeString` writes to a `.tmp` sibling and renames over the
  destination (atomic on POSIX; explicit replace fallback on Windows).
  Applied to players / universe / settings / npcs / exploration stores.
- **Later, if data grows or queries are needed:** Hive (simplest object
  store, works on all 6 platforms incl. web) or drift/SQLite (relational
  queries, migrations — for galaxy search / leaderboards). Access pattern
  today is "load everything into memory," which suits Hive — don't spin up
  anything heavier until queries are real.

### E3. Improvement 2 — Passwords: salted hashing

`player.dart:323` hashes passwords as `sha256(password)` — no salt, no
iterations; fast to brute-force and rainbow-table prone. For a local game the
threat is modest, but it's a ~30-minute fix: `bcrypt` or `dart_bcrypt` (or
salted PBKDF2 via `package:cryptography`). **Do this before any online mode.**

### E4. Improvement 3 — State: already 80% clean; stop at the right level

The current pattern — immutable `Player.copyWith` + `ValueNotifier`s +
callback lifting in `GameShell` — is coherent and testable. It only gets
clunky as screens juggle more state (the version counter is the first sign).
Options (cheapest → most invested):
1. Do nothing; formalize only when a feature demands it.
2. Lean into what's there: scoped `ChangeNotifier`s + `AnimatedBuilder`
   (the `ActionLogProvider` pattern), keep `ValueNotifier`s for singletons.
3. Riverpod — the natural upgrade if pain hits: declarative, testable, and it
   handles the async-save races for you.
Remove the unused `provider` dep now (done on `ui-scale`); revisit Riverpod
when a feature demands it — not before.

### E5. Improvement 4 — Models & tests: codegen + CI

- **Codegen** (`freezed` + `json_serializable`, or Hive/drift part files)
  removes hundreds of hand-written `copyWith`/`toJson`/`fromJson` lines and
  the recurring bug class where a new constructor field is forgotten in
  `fromJson` (happened in `game_settings.dart`).
- **Tests are the biggest expandability risk.** Only 2 smoke tests exist.
  Because `GameSettings.seed` makes universe generation deterministic, the
  generator, economy price-split, combat, and `TradeEvaluator` are perfectly
  unit-testable — build a `test/` suite for those before big refactors.
- **CI:** a GitHub Actions pipeline running `flutter analyze` + `flutter test`
  on the Linux target is cheap and standard.

### E6. The decision that gates the rest: online or not?

The roadmap line — *"turns → energy (internet no longer justifies a turn
limit in online play)"* — implies online play is on the horizon.
- **If online (even someday):** client-side storage becomes a *cache*; the
  real architecture is a server (authority for universe/tick/NPC AI). A Dart
  server (`dart_frog`/`shelf`) reuses existing logic; Go/Node + Postgres is
  the mainstream alternative. The 30s `GameTickService` and the JSON stores
  move server-side; the client renders + sends intents. "AI NPC chat" needs a
  server-side agent/LLM integration regardless.
- **If offline/P2P forever:** keep everything local, add Hive, done.
This doesn't block `ui-scale` — but Phase B (economy) and C (NPC AI) get
built differently depending on the answer. Design the storage layer to be
*syncable* either way.

### E7. Display scaling requirement (EndeavourOS / Hyprland / Wayland)

- Dev machine: EndeavourOS (Arch) + Hyprland (Wayland compositor; "Noctalia"
  setup). Requirement: **the game must scale to any desktop display.**
- Wayland reality: tiling compositors ignore client window sizing/placement —
  windows fill the monitor/tile — so `window_manager.setSize` is best-effort
  there; the compositor owns layout. The UI-scale canvas transform is the
  reliable lever on every platform.
- Detection: `screen_retriever` on Linux uses **GDK monitors**
  (`gdk_monitor_get_geometry`) which work on both Wayland and X11, and report
  application pixels (Hyprland scale 2 → 1920, scale 1 → 3840). Suggested
  scale = `clamp(logicalWidth / 2560, 1.0, 2.0)`.
- Fallback: if the plugin channel is unavailable, the first-frame window size
  is used — under a tiling WM the window already fills the monitor, so this
  recovers the same result.
- Manual override (slider 1.0–2.0, presets) remains the universal fallback
  for any display/WM combo.

### E8. Save-file tamper resistance (backlog — later, not now)

Local machine = deterrence, not prevention: any key shipped with the game
can be extracted by decompiling, so a determined cheater always wins. The
goal is stopping casual `npcs.json` credit-edits (covers ~99% of it).

- **Option A — integrity seal (recommended, pairs with the password-hashing
  work in E3).** Write an HMAC-SHA256 alongside each save with a baked-in
  key; on load, a mismatched seal means hand-editing → refuse the file
  (backup fallback or reset with a warning). A few lines per store.
- **Option B — encrypted blob.** AES-GCM the whole file
  (`package:cryptography`), key in `flutter_secure_storage` (OS keychain —
  libsecret on Linux) rather than hardcoded. Genuinely unreadable at rest;
  needs a storage-layer wrapper + test seam.
- **Option C — both.** Standard combo, ~1 hour over either alone.
- Effort: S. If multiplayer ever happens this becomes moot — the server is
  the authority and local saves are an untrusted cache (E6).

---

## F. Dev automation console (planned next — unblocks NPC verification)

Motivation: an NPC with a 1000-energy tank at ~10/hop needs ~90 ticks to
reach refuel range — 45+ minutes at the 30s tick. Real-time console
`grep NPC_ENERGY` works but is slow and unfilterable. A Settings →
**Automation** section fixes both. All controls live **on the panel as
toggles/switches** (no key-press shortcuts) so the automation state is
always visible and reviewable in one place.

- **F1 — Full-action log viewer.** ✅ **Done.** New `lib/services/game_event_log.dart`
  (`GameEventLog` ChangeNotifier singleton, 2000-entry ring, newest-first,
  `query(text, categories)` search): all 43 `debugPrint` sites across
  `npc_ai_service.dart` (36), `combat_service.dart` (2), and
  `game_tick_service.dart` (5) now log categorized entries (combat / trade /
  movement / energy / banking / goal / system) with `debugPrint` mirroring
  preserved, so console `grep NPC_ENERGY` keeps working verbatim. New
  `lib/widgets/automation_console_widget.dart` — Settings → **Automation
  (Dev)** card with search box, per-category filter chips, live count, and
  Clear — wired into `settings_screen.dart`. Covered by
  `test/game_event_log_test.dart` (4 tests: ordering, 2000-cap eviction,
  text+category query, clear).
- **F2 — Tick controls (panel switches).** ✅ **Done.** Settings → Automation
  card now has a Tick controls row (30s / 5s / 1s preset chips + Pause/Resume
  toggle, wired to the existing `GameTickService.updateInterval`/`stop`/
  `start` from `GameShell`), a Player resources row (live
  credits/metal/tech/energy readout + **+100k cr / +500 metal / +50 tech**
  grant buttons for emporium/store/upgrade testing), and an Energy drains
  row (**NPCs → 10 %** persisted via `NpcStorage`, **Player → 0** for tow
  testing). All dev grants/drains are logged to the event bus as `DEV …`
  system lines. Callbacks flow `GameShell → SettingsScreen →
  AutomationConsoleWidget`; the widget hides the section when callbacks are
  absent. Covered by `test/automation_console_widget_test.dart` (4 widget
  tests).
- **F3 — Debug action toggles.** ✅ **Done early** (folded into F2 above —
  energy drains shipped with the tick controls).

---

## Decisions (2026-09-23)

- **Branch to start:** `ui-scale` ✔ created.
- **UI scale approach:** auto-detect + manual override ✔ (device-aware
  default from display density/resolution, with slider/preset override).
- **Rebrand:** fully committed on `main` (`c39cbe3`), clean run + tests.
- **Technology review:** see section E — stack kept as-is; storage made
  crash-safe (atomic writes); unused `provider` dropped; password hashing +
  tests/CI tracked as future work.
- **Display requirement:** the game must scale to any desktop display — dev
  machine is EndeavourOS + Hyprland (Wayland). Auto-detect uses GDK monitors
  (works on Wayland *and* X11); fallback = first-frame window size, since
  tiling WMs fill the monitor with the window. Manual slider covers the rest.
- **Open question:** online play? (gates storage/architecture choices — E6.)

### ui-scale branch — implementation status

1. ✅ `lib/core/ui_scale.dart` — `UiScale` with `scaleNotifier` /
   `autoNotifier`, presets (Default 1.0 / Comfy 1.25 / Cozy 1.5 / Max 2.0),
   `suggestFor(logicalWidth)` (3840 → 1.5, 1920 → 1.0), GDK-based
   `detectPrimaryDisplay()` (Wayland + X11).
2. ✅ `main.dart` — loads `uiScale` + `uiScaleAuto`; probes display before the
   window opens; DPI-aware default window (80% of work area when auto);
   global canvas transform via `Transform.scale` + `OverflowBox` + scaled
   `MediaQuery.size`.
3. ✅ `GameSettings` — `uiScale` / `uiScaleAuto` fields, defaults,
   `copyWith`, `toJson`, `fromJson` (legacy-safe defaults).
4. ✅ `lib/widgets/ui_scale_settings_widget.dart` — auto toggle,
   "Detect now" button, preset chips, slider (1.0–2.0); wired into the
   Settings screen and persisted through `onSettingsChanged`.
5. ✅ Crash-safe storage — `lib/data/storage/file_safe.dart`
   (`FileSafe.writeString`, temp + rename); applied to all five stores
   (players/universe/settings/npcs/exploration).
6. ✅ Dropped unused `provider` dependency; added `screen_retriever: ^0.2.0`.
7. ⏳ Sector view panel **max-width clamps** for wide screens.
8. ⏳ Verify: `flutter analyze` clean, `flutter test` passing, Linux run.
9. ✅ Sector view desktop **max-width clamp** (1760px cap) plus tablet/mobile
   fixes — vertical `Expanded`/`Flexible` removed from scroll views; panels
   sized naturally; header rows made overflow-proof (`Expanded` ellipsis +
   `FittedBox`). New `test/sector_view_layout_test.dart` (13-width sweep).
10. ✅ FileSafe concurrency fix — unique per-write tmp names
    (`file.path.pid.microseconds.tmp`), non-destructive fallback; new
    `test/file_safe_test.dart` (4 tests, incl. 20 concurrent writers).
11. ✅ Ports Guide crash fix — `PortsKnowledgeBaseScreen` took `Navigator.pop()`
    on an inline (non-route) tab inside ComputerScreen, popping the GameShell
    root route (`[TickService] Stopped` → frozen). Now uses an `onBack`
    callback; regression test in `test/computer_screen_test.dart`.
12. ✅ UniverseStorage test seam — public constructor +
    `UniverseStorage.instanceForTest` for widget tests.
13. ✅ **Exit Game / clean shutdown** (new):
    - **App-level close guard** in `main.dart` (`CosmicTraderApp` is now a
      `WindowListener`) — works on *every* screen (login / register / game):
      - The window's X button is **disabled entirely** via
        `setClosable(false)` (Linux: `gtk_window_set_deletable(false)`) —
        quitting is done only through in-app "Exit Game" buttons.
      - `setPreventClose(true)` + `onWindowClose` remain as a safety net for
        WM close keybinds: the handler flushes any active game session
        (`GameShell.exitSaveHook` → stop tick + save player/NPCs/settings,
        10s timeout), then exits.
    - **"Exit Game" buttons on every screen**: Login (top-right power icon),
      Register (AppBar action), GameShell (AppBar icon <600px + rail button
      below Logout on desktop). All save-and-quit; login/register have no
      session state to flush.
    - Shared `lib/core/app_exit.dart`: `quitApplication()` — desktop uses
      `dart:io exit(0)` directly, bypassing the Flutter Linux shell teardown
      that logged `'FlutterEngineRemoveView' returned 'kInvalidArguments'` /
      "Lost connection to device"; mobile falls back to
      `SystemNavigator.pop()`; web is a no-op. `isDesktopPlatform()` is the
      single source of truth.
    - 10s safety timeout on the final save so the app can never hang on exit.
    - Tests: `test/game_shell_test.dart` (2 smoke tests, both layouts) +
      `test/widget_test.dart` login "Exit Game" smoke test.
14. ✅ **Density toggle — A1-5 complete** (new):
    - `UiDensity` enum (Compact 0.8 / Normal 1.0 / Cozy 1.25) +
      `UiScale.densityNotifier` + `UiScale.spacing(base)` spacing token in
      `lib/core/ui_scale.dart`. Density is *independent* of UI scale: the
      canvas transform already magnifies all authored spacing, so `spacing()`
      only applies the density factor.
    - `GameSettings.uiDensity` — field, default, `copyWith`, `toJson`
      (`'uiDensity': name`), legacy-safe `fromJson`.
    - `main.dart` — loads density at startup; `densityNotifier` listener
      rebuilds the app; `_buildTheme()` maps density → `ThemeData.visualDensity`
      (`compact` / `standard` / `comfortable`), affecting Material components
      (ListTiles, buttons, chips) globally.
    - Settings UI — Compact / Normal / Cozy `<ChoiceChip>` row in
      `UiScaleSettingsWidget`, persisted via `onSaveSettings`.
    - **Spacing-token migration** (vertical rhythm of the main play
      surfaces): `port_trade_view.dart` (row/strip/header/extras paddings +
      section gaps — the spec-named file), `ship_status_summary.dart`,
      `action_log_panel.dart` (filter gap, filters, log entry rows),
      `sector_interaction_panel.dart` (entry list separators, detail rows,
      chip padding). Remaining screens adopt `UiScale.spacing()` as part of A2.
    - Verify: `flutter analyze` **No issues found!**, `dart format` clean,
      12/12 tests pass, `flutter build linux --debug` ✓.
15. ✅ **UI scale persists across restarts — fixed** (new):
    - **Root cause**: the scale *was* written to `settings.json`, but with
      `uiScaleAuto` left on (default), `main.dart` re-ran display detection on
      every launch and overrode the saved value — on scaled/HiDPI displays
      (e.g. 4K @ 180% → ~643 logical px) `suggestFor()` clamps to 1.0, so a
      manually chosen scale looked "reset" after relaunch.
    - **Fix 1** (`settings_screen.dart`): any manual scale change — slider or
      preset chip — now switches **auto-detect OFF** (persisted), so the
      chosen value is honored on the next launch.
    - **Fix 2** (`main.dart`): startup auto-detection now **persists** the
      detected scale back to `settings.json`, keeping the file in sync with
      what is applied (Settings screen shows the live value, and a later
      failed display probe falls back to the last good detection).
    - **Video/audio check**: fullscreen / resolution / animation-speed
      (video) and music/SFX volume + folder (audio) all already persist
      through the same `onSaveSettings → _handleSettingsChanged →
      SettingsStorage.save` chain as the scale widget — no change needed.
    - New `test/game_settings_test.dart` (3 tests): JSON round-trip for UI
      scale / density / video / audio prefs, manual-scale-with-auto-off
      survival, and legacy-file defaults. `flutter test` now **15/15**.
16. ✅ **A2 — shared widget library** (new):
    - New `lib/widgets/shared/` with four density-aware building blocks, each
      routing padding/gap tokens through `UiScale.spacing()` so Compact/Normal/
      Cozy applies everywhere they're used:
      - `PanelCard` — rounded-16 elevation-0 card with optional header row
        (icon/leading + title + subtitle + trailing) above body children.
        Replaces the copy-pasted `Card(elevation: 0, … Padding(16, Column(
        [Row(Icon, 8, Text(title)), SizedBox(12), …])))` pattern.
      - `StatBar` — the `_StatusBar` shape (optional icon + monospace label +
        glowing progress bar + right-aligned value) plus a `stacked` layout
        (label + value above the bar) for planet/faction readouts; label/value
        column widths and gaps are density-aware.
      - `HudPill` — tiny rounded badge (port-class / faction / "sabotaged" /
        stat-chip tags) with optional icon, `radius`/`padding`/`fontSize`/
        `overflow` overrides for exact look preservation, density-aware 7×1
        default padding.
      - `DataTableShell` — bordered dense table shell (shaded header row +
        divider-separated body rows) with flex/alignment per column.
    - **First adoption wave** (behavior-preserving; deleted ~223 lines of
      duplicated code):
      - `port_trade_view.dart` — 3 tags → `HudPill`; the commodity trade table
        → `DataTableShell` (6 columns: commodity/buy/sell/supply-dem/hold/
        actions). Deleted local `_pill` + `_colHeader` helpers.
      - `ship_status_summary.dart` — 4 hull/shields/drones/cargo bars →
        `StatBar`; deleted the 80-line private `_StatusBar` class.
      - `ship_status.dart` — 5 of 6 cards → `PanelCard` (Player Info, Hull &
        Shields, Engine & Weapons, Cargo Hold & Components, Reputation &
        Research). The custom rocket `_shipHeaderCard` intentionally stays
        hand-built.
    - **Second adoption wave** (behavior-preserving; completes the sweep):
      - Extended `HudPill` with `radius` / `overflow` / `iconSize` / `iconColor`
        (preserves the faction stat-pill 6px-radius look) and `StatBar` with a
        `StatBarLayout.stacked` variant (label + value above the bar) and an
        optional inline icon.
      - `planet_screen.dart` — `_resourceBar` / `_defenseBar` (7 call sites)
        → `StatBar(layout: stacked)`; deleted both duplicated bar builders.
      - `faction_rankings_screen.dart` — `_statPill` → `HudPill` (6px radius,
        8×4 padding, 11px ellipsized label, 12px icon preserved exactly).
    - **Full-coverage sweep result**: every remaining `Card(` site (48),
      `HudPill` candidate, `LinearProgressIndicator` site (15) and table was
      audited. Only the patterns above matched the shared widgets' contracts.
      The rest are **deliberately distinct visual families** left as-is (fixed
      sizing), so they keep their identity: radius-12 banded `Container` headers
      (sector dashboard panels, banking, lottery, hardware emporium),
      padding-20 + custom-accent `color:` cards (port management),
      ExpansionTile settings cards with accent `side:` borders (audio/video/
      font/ui-scale/system-resources), hero cards (Galactic Intelligence
      Report), pill-border `_RankingCard`s, headline-layout hull/shield bars,
      and bare embedded progress bars. These are candidates for future
      parameterized passes, not forced migrations.
    - Verify: `flutter analyze` **No issues found!**, `dart format` clean,
      21/21 tests pass (suite includes user's hack/reputation tests),
      `flutter build linux --debug` ✓.

17. ✅ **A3 — look & feel polish, wave 1** (new):
    - **Consistent faction color language** — `lib/core/faction_colors.dart`
      is now the single source of truth (`factionColor(FactionClass)` +
      `FactionPalette` consts). The old palette was inconsistent everywhere:
      the map used blue/teal accents while the leaderboard used violet/green,
      two port screens used cyan/purple, and NPC lists used flat
      `Colors.blue/red/teal/black`. Adopted in all 7 color-coded surfaces
      (galaxy map dots + legend + painter, faction rankings, sector NPC list,
      combat, port trade tags, port management, knowledge base) with one
      canonical palette: Duran red-600, Vinari deep-purple, Trader green-500,
      Pirate orange-500.
    - **Persistent HUD strip** — new `lib/widgets/hud_strip.dart` sits above
      the tab content on both the mobile and desktop layouts and is always
      visible: sector name/ID, credits, turns, and compact hull/shield bars.
      Responsive: the bars drop below 760px and turns below 560px so the row
      never overflows (verified by the 580px/700px shell tests). Carries the
      per-sector faction *ambiance* accent: a 3px bar + title tint from the
      dominant NPC faction in the current sector (shell computes it from live
      NPCs). All spacing routes through `UiScale.spacing()`.
    - **Warp transition** — new `lib/widgets/warp_transition.dart`: a ~460ms
      full-screen hyperspace flash + radial star streaks + collapsing faction
      accent ring over every sector change (warp console, galaxy map moves,
      combat flee), with the destination name under a `W A R P` header. The
      shell triggers it from `_updatePlayer` sector deltas + `_onSectorSelected`.
    - **SFX hookup** — generated a 7-cue procedural sound library
      (`assets/sfx/*.ogg`, via ffmpeg lavfi — not hand-shipped samples): buy
      blip, sell blip, hack two-tone, laser "pew" (real 1600→300 Hz sweep),
      warp whoosh, lottery chime, landing thump. Wired into the actual events:
      port trade buy/sell, combat fire, hack packet injection, lottery reveal,
      warp, and planet dock (`_openPlanet` in the shell). `AudioService.playSfx`
      was already asset-capable; the folder is declared in pubspec.
    - **Table readability** — `DataTableShell` gained a `zebra: true`
      option (faint primary-tinted alternating rows); the port trade table is
      the first adopter.
    - **Typography option** — bundled Audiowide (OFL, single-weight) as
      `assets/fonts/Audiowide.ttf`, declared in pubspec under `fonts:`. The
      existing Settings → Font font picker auto-scans `assets/fonts/`, so
      "Audiowide" now appears as a selectable sci-fi display typeface with no
      new UI. (Not forced onto any screen.)
    - Not in this wave: sortable Port Report columns, hover cursors/keyboard
      shortcuts, forced header typeface — kept for a later A3 pass.
    - Verify: `flutter analyze` **No issues found!**, `dart format` clean,
      21/21 tests pass, `flutter build linux --debug` ✓ (SFX + font verified
      present in the bundled build).

18. ✅ **A3 wave 1b — playtest fixes** (new):
    - **SFX were silent — root cause found & fixed.** `AudioService` handed
      full `assets/...` paths to audioplayers' `AssetSource`, but the engine's
      `AudioCache` prepends its own `assets/` prefix, so the loader asked for
      `assets/assets/...` — which doesn't exist in the bundle — threw, and the
      `catch (_) {}` swallowed it into silence. This affected *every* cue (and
      music used the same pattern, so it was silently dead too). Proven with a
      guarded bundle-key test (`assets/sfx/buy.ogg` loads;
      `assets/assets/sfx/buy.ogg` fails). `playMusic`/`playSfx` now strip the
      leading `assets/` (`AssetSource` gets `sfx/buy.ogg` → `assets/sfx/buy.ogg`)
      and log failures via `debugPrint` instead of swallowing them. New
      regression test `test/sfx_assets_test.dart` pins the correct bundle key
      for all 7 cues and asserts the double-prefixed key fails.
    - **Font picker crashed with Audiowide selected.** The dropdown's items
      were keyed by file name (`Audiowide.ttf`) while its `value` was the
      family name (`Audiowide`) → "exactly one item with value Audiowide"
      assertion. Items are now family names, deduped, and the persisted
      selection is always present as an option. New widget test
      `test/font_settings_widget_test.dart` (scans `assets/fonts/` via
      `runAsync`, verifies no assertion + Audiowide offered).
    - **Warp animation redesigned.** The full-screen flash/burst/ring (which
      the playtest disliked) is replaced by a star-rush: 56 radial streaks +
      dust motes whip outward from the jump point over ~500 ms — the
      background starfield streaming past like flying through space — with a
      barely-there veil (the underlying scene stays visible) and the faction
      accent tinting a subset of streaks. The destination label moved to a
      subtle bottom caption. New painter covered by
      `test/warp_transition_test.dart` (steps the full animation, no throws).
    - Verify: `flutter analyze` **No issues found!**, `dart format` clean,
      37/37 tests pass, `flutter build linux --debug` ✓, 15 s live app run
      (DeskTop session) with no `[audio]`/GStreamer errors logged.

### ✅ Analyzer cleanup — backlog resolved (0 findings)

All 8 previous `info`-lints are now fixed — `flutter analyze` reports
**No issues found!** (down from the 8-finding baseline).

| # | Rule | Location | Fix applied |
|---|------|----------|-------------|
| 1 | `curly_braces_in_flow_control_structures` | `lib/screens/faction_rankings_screen.dart:13` | Braced the single-statement `if` body |
| 2 | `deprecated_member_use` (`translate`) | `lib/screens/galaxy_map.dart:695` | `current.translateByDouble(pan.dx, pan.dy, 0.0, 1.0)` |
| 3 | `deprecated_member_use` (`groupValue`/`onChanged` on Radio) | `lib/screens/register_screen.dart` (faction step) | Wrapped in `RadioGroup<FactionClass>` |
| 4 | `deprecated_member_use` (`groupValue`/`onChanged` on Radio) | `lib/screens/register_screen.dart` (ship step) | Wrapped in `RadioGroup<String>` + per-radio `enabled: !locked` |
| 5 | `deprecated_member_use` (`activeColor`) | `lib/widgets/sector_view_widgets/tactical_map.dart:131` | `activeColor` → `activeThumbColor` |
| 6 | `deprecated_member_use` (`activeColor`) | `lib/widgets/video_settings_widget.dart:203` | `activeColor` → `activeThumbColor` |

Implementation notes (deltas vs. the originally-planned snippets):

1. **galaxy_map.dart** — `translateByDouble` takes *four* required
   positional args in the bundled `vector_math` (`tx, ty, tz, tw`). The old
   `translate(dx, dy)` maps to `translateByDouble(dx, dy, 0.0, 1.0)` — the
   `tw: 1.0` term is what reproduces the incremental-translation math.
   (`translateByVector3(Vector3(dx, dy, 0))` would be equivalent.)

2. **register_screen.dart faction step** — exactly as planned:
   `RadioGroup<FactionClass>` wraps the `Column`; `onChanged` moved onto the
   group; the per-`Radio<FactionClass>` keeps only `value: faction`.

3. **register_screen.dart ship step** — `RadioGroup<String>` wraps the
   `Column`, but `RadioGroup.onChanged` is **required / non-nullable**, so the
   old per-radio `onChanged: locked ? null : …` pattern cannot move to the
   group. Individual locked ships are disabled via the non-deprecated
   `enabled: !locked` parameter on each `Radio<String>`, and the group's
   `onChanged` always runs `setState(() => _selectedShip = value!)`.

4. **`RadioGroup` semantics check** — group wraps the subtree in `Semantics`
   (`radioGroup` role) + `FocusTraversalGroup` + arrow-key/space shortcuts; it
   also asserts (debug) that at most one radio matches the group value per
   frame. All 12 ship `name`s are unique across factions, so the assertion is
   safe.

Verify:
```bash
flutter analyze          # → No issues found!
flutter test             # 12 pass
dart format lib/ test/   # canonical formatting
```

---

### `living-economy` branch — B1: Turn → Energy (✅ complete)

*Closed: `turns`/`maxTurns` deleted from `Player` and `NpcShip`;
`GameSettings.initTurns` renamed to `initEnergy` (Settings form now reads
"Initial Energy"). All three keep one-line `fromJson` fallbacks reading the
legacy keys, so pre-energy saves migrate silently. Zero live `turns`
references remain. Tests: legacy-migration cases in `energy_service_test`,
`npc_energy_test`, and `game_settings_test`.*
*Deferred by decision: universal port refuel (emporiums only, by design) and
a refuel-point list UI (folds into the future bookmark/notes system —
exploration stays earned, not given).*

Decisions taken for this branch:

- **No passive regeneration for now.** Energy is restored by **manual refuel
  purchases at ports**.
- **Solar array** ship equipment is planned as a later self-recharge option
  that takes time, so a stranded ship is never permanently stuck.
- A stranded player should eventually be able to **call for a tow** to the
  nearest port that can sell fuel.

Status:

1. ✅ Branch created from clean `main`.
2. ✅ `Player` gained `energy` / `maxEnergy`. Legacy `turns` / `maxTurns` are
   retained for old save files and are used as the `fromJson` fallback.
3. ✅ New `lib/services/energy_service.dart` owns the rules:
   - warp cost scales with distance and is reduced by engine efficiency
     (`ceil(baseWarpCost * hops / efficiency)`; starter engine = 2 per hop)
   - planet scan = 4 energy, quick sector scan = 1 energy
   - refuel = 1 credit per missing energy unit, clamped by credits and tank
4. ✅ Core player surfaces now read energy: `HudStrip`, `ShipStatusView`,
   `PortTradeView`, `WarpConsole`, planet scan, and sector interaction scans
   (including insufficient-energy messages).
5. ✅ Manual refuel added as a **Refuel Energy** service card in the Hardware
   Emporium → Services tab.
7. ✅ **Solar Array ship module** — purchaseable/equippable in the Hardware
   Emporium → Modules tab (generated by `hardware_data.dart` like every other
   module; buying installs it into `Player.installedModules`). While equipped,
   `EnergyService.solarRecharge()` recovers `2 * moduleLevel` energy per game
   tick, clamped to tank capacity, applied from `GameShell` on every tick
   completion. This is intentionally a slow backup rather than free infinite
   fuel — Hardware Emporium refuel remains the fast option.
8. ✅ **Solar Array deploy/retract toggle** — `Player.solarArrayDeployed` is
   persisted, toggled from a new Ship Status → **Solar Array** card, and shown
   in the HUD as an amber lock icon instead of the energy bolt. A deployed
   array:
   - recharges `2 * moduleLevel` energy per tick via `EnergyService.solarRecharge`
   - locks movement: `EnergyService.canMove(player)` blocks warp console moves,
     tactical-sector warps, and Galaxy Map moves, each surfacing "retract the
     Solar Array" feedback
   - retracting restores movement and stops the trickle
9. ✅ **Emergency Tow system** — new `lib/services/tow_service.dart` prevents
   the B1 soft-lock: a player with no usable warp energy can call a tow to the
   nearest reachable **Hardware Emporium**, falling back to the nearest port if
   no emporium is reachable. Cost is `2,500 cr + 750 cr/hop`, clamped so the
   tow is still available when nearly broke. Arrival retracts the Solar Array
   and grants emergency energy so the ship is operable. Added a Ship Status →
   **Emergency Tow** card, plus a "Call Emergency Tow from Ship view" hint when
   the Warp Console rejects a jump for insufficient energy. Covered by
   `test/tow_service_test.dart` (5 tests).
10. ✅ **NPC energy migration (B1-NPC) — done** (was "later pass"):
   - `NpcShip` gained `energy` / `maxEnergy` (legacy `turns` fallback in
     `fromJson`, same pattern as `Player`), plus `solarArrayLevel` /
     `solarArrayDeployed` with `hasEnergy` / `spendEnergy` / `refuelEnergy`
     / `canMove` helpers.
   - `EnergyService` gained NPC overloads: `npcWarpCost` (efficiency =
     engine level), `npcCanWarp`, `npcMissingEnergy`, `npcRefuelCost`,
     `npcRefuel`, `npcSolarRecharge`, `npcEmergencyEnergy`.
   - `NpcAiService.processTurn`: solar trickle-charge on entry, all `turns`
     gates replaced with energy gates, new `refuelEnergy` goal (nearest
     Hardware Emporium, outranks everything but flee), Solar Array purchase
     inside `upgradeEquipment` for cautious/explorer NPCs (75k cr, no
     scrap), zero-energy `_handleStranded` fallback (deploy array, else
     emergency reserve from credits/bank), `_move` spends warp energy and
     respects deployed-array lock.
   - **Discovery rule (same as players):** refuel/upgrade target only
     *discovered* emporiums (`knownEmporiumSectors` from
     `memory.discoveredPorts`); fuel-low NPCs that know none get an explore
     goal (`refuel_unknown`) and roam until a scan finds one. Stale memories
     (port destroyed) fail cleanly (`refuel_stale`) and re-plan.
   - `GameTickService`: energy gates, 60-tick turn-replenish block deleted,
     tick summary now reports `stranded` count.
   - **Stall-bug fixes (live: trade=0/combat=0 over hours):** (1)
     `copyWith(currentGoal: null)` never actually cleared — the `?? this`
     fallback silently kept the failed goal, blocking all future selection
     (20 call sites → new `clearGoal: true` flag); (2) patrol goals never
     completed (absorbing), so `_needsNewGoal` never fired again — patrols
     now expire after 5 legs (`maxPatrolLegs`) and re-enter selection.
     Covered by `test/npc_goal_lifecycle_test.dart` (3 tests).
   - **Tick re-entrancy guard (live phantom volume):** 1s dev ticks
     overlapped (no guard; BFS-heavy ticks exceed 1s), double-counting
     metrics while last-write-wins storage kept one run — 1100 buys vs 21
     sells with ~500 units held. Concurrent ticks now skip + count
     (`overlapSkips`, surfaced in system log); entry via testable
     `processTickNow()`. Covered by `test/tick_reentrancy_test.dart`.
   - **Live debt catch (assert worked):** Sarek's per-tick owned-port buys
     went negative via the 5% owner surcharge on top of an exactly-fitting
     cost — affordability now prices the fee in (`unitCost` incl. tax) with
     a rounding-guard loop, and the tick loop bulkheads per-NPC errors
     (state kept, error logged, tick completes) instead of aborting the
     whole tick. Covered by the surcharge regression test.
   - **External review batch 2 (Claude):** (1) critical buy-phase debt
     bug — `clamp(1, …)` forced broke NPCs to buy unaffordable units,
     driving credits negative and poisoning killer loot downstream: buy
     phase now bails before clamping, sell phase same treatment, evaluator
     filters routes the bankroll can't start (`credits` param), loot
     clamped ≥ 0, debug `assert(credits >= 0)` in the model; (2) bank
     execution validates the destination port (stale-port abort like
     refuel/trade) — the withdraw-vs-upgrade clobber instance was already
     closed by the interruption guards; (3) evaluator pathfinding hoisted
     (m + m² lookups, not m² × c); (4) `lastTradeTime`/`lastBankTime` now
     stamped on sale/deposit/withdraw. Deferred with rationale: combat
     simultaneity (design), shouldAttackPlayer/canWin consolidation,
     drones in power math, weapon-slot map hardening (C-branch/simulation
     work). Covered in `npc_goal_lifecycle_test` (no-debt buy, evaluator
     affordability, stale bank abort, withdraw-vs-upgrade, timestamps).
     — banking/distress/refuel only override interruptible goals
     (explore/patrol/none), refuel additionally breaks committed legs below
   - **External review batch 1 (Claude):** (1) goal interruption now
     guarded — banking/distress/refuel only override interruptible goals
     (explore/patrol/none), refuel additionally breaks committed legs below
     the 10% emergency floor; unarmed NPCs skip distress response;
     (2) sell-first triggers on full holds *and* sub-25% nibs so partial
     cargo never rides unsold forever; sell-only logs clear holds instead
     of fake 100% margins; (3) dead `flee`/`bankDeposit` weights stripped
     from all personality tables (threshold-driven by design, like
     withdraw/refuel); warlord weights sum to 1.0; (4) failed trade routes
     cool down 5 min in `NpcMemory.failedRoutes` (persisted) and are
     skipped by `findBestTradeRoute` via `avoidRoutes`; (5) startup-safe
     personality coverage test. Verified clean: NPC equipment baselines are
     level 1 (no zero-price bug); `planning`/`executing` statuses reserved;
     static distress map + 5-min TTL accepted. Covered in
   - **Cargo-deadlock fix (live dump: all holds 50/50, 0 trade goals):**
     trade viability required free hold space, but nothing except a trade
     goal empties cargo — full holds permanently blocked all future trading
     (patrol-absorb loop). Viability now accepts full holds carrying goods
     (credits gate applies to the buy leg only, so broke NPCs can still
     sell), and `_createSellOnlyGoal` sends them to the best known buyer
     for on-board cargo (sell-first route, no buy leg). Covered in
     `npc_goal_lifecycle_test`.
   - **Outfitting (all factions earn + gear up):** the `upgradeEquipment`
     goal was a `(deferred)` stub — NPCs ran level-1 gear forever while
     Duran compounded. It now performs real outfitting per emporium visit:
     repairs first (2cr/hull, 1cr/shield, fuel reserve kept), then one
     level purchase — defense-first (shields→hull→engine→weapons) for
     peaceful factions (aggression ≤ 0.5), weapons-first for aggressors.
     Levels feed live formulas (firepower, durability, warp cost); shield
     levels also add +20 maxShields since nothing else read that stat.
     Costs 15k×level (20k engine), caps 5/5/5/3, 5k cash floor. Upgrade
     viability gate lowered 100k→25k; pure non-traders gained small trade
     weights (warlord/protector 0.05, explorer upgrade 0.05) so every
     faction can earn. Covered in `npc_goal_lifecycle_test` (repair +
     priority tests).
   - **Verification:** `test/npc_energy_test.dart` (8 tests); all NPC energy
     events log with a parseable `NPC_ENERGY event=<name> pilot=... ...`
     prefix (`solar_recharge`, `refuel_goal`, `refuel_buy`, `refuel_empty`,
     `array_buy`, `array_deploy`, `emergency_reserve`) — `grep NPC_ENERGY`
     on console output to confirm live behavior.
   - **Decision:** universal port refuel UI / port-class pricing is deliberately
     **not** planned right now — refueling only at scarce Hardware Emporiums
     keeps travel decisions meaningful.

### `living-economy` branch — B1-NPC: NPC Turn → Energy (research + scope)

**Finding:** players run on energy, but NPCs still run on `turns`.
`NpcShip.turns` (init 1000 in `npc_ship.dart:307`, replenish 200 every 60
ticks in `game_tick_service.dart:181-195`) gates *everything*: `processTurn`
early-returns on `turns <= 0` (`npc_ai_service.dart:63`), each sub-step is
gated on `turns > 0` (threat/banking/goal-select/move, lines 80/86/94/104/
115/127), and `_move` spends a flat `turns - 1` per hop (lines 1288/1302)
regardless of distance or engine. The tick service also skips `turns <= 0`
NPCs (line 141) and blocks energy-less NPCs from the player-attack check
(line 217). Scans, combat, and trade currently cost NPCs nothing — turns are
just a liveness gate. `NpcShip` has `engineEquipmentLevel` but, unlike
`Player.engineEquipment`, no engine *type* name, so there is no efficiency
stat to feed a warp-cost formula yet; and NPCs have no `installedModules`
map at all, so there is nowhere to store a Solar Array.

**Scope to finish the energy switchover (all in `living-economy`, no new branch):**

1. **Model (`npc_ship.dart`) — S.** Add `energy` / `maxEnergy`
   (default 1000, `fromJson` falls back to legacy `turns` exactly like
   `player.dart:398-399` does), plus `solarArrayLevel` (int, default 0) and
   `solarArrayDeployed` (bool, default false). `copyWith` / `toJson` /
   `create()` updated. Keep `turns` as a deprecated read-only fallback for
   one release so old `npcs.json` files still load.
2. **Warp-cost rule — S.** Add an NPC overload next to
   `EnergyService.warpCost` (e.g. `npcWarpCost(engineLevel, {hops})`).
   Open question is only what "efficiency" means for NPCs: cheapest correct
   option is `efficiency = max(1, engineEquipmentLevel)` (starter NPC ≈
   10/hop, matching the player starter rate of 2/hop only if levels are
   scaled — calibrate so NPC range ≈ player range). `_move` spends the
   computed cost instead of `- 1`; multi-hop pathfinding already moves one
   hop per tick so `hops: 1` suffices. Quick-scan (1) and planet-scan
   equivalents cost NPCs nothing today — keep it that way, or charge the
   same 1/4 for symmetry (one-line change once the gate exists).
3. **Refuel goal — M.** New `NpcGoalType.refuelEnergy` (or reuse
   `upgradeEquipment` with a `refuel: true` param — new enum is cleaner).
   Trigger: `energy < nextLegCost + reserve` (reserve ≈ 2 hops), evaluated
   in `processTurn` step 4 alongside the existing `BankingAi` checks so
   refuel outranks trade/explore but not flee. Destination: nearest
   Hardware Emporium via the existing `_createUpgradeGoal` BFS pattern
   (`npc_ai_service.dart:1249-1253`); execution deducts
   `1 cr/unit × missing` (same `refuelCreditsPerUnit` as players), clamped
   by credits. If broke, fall through to `BankingAi.createWithdrawGoal`
   first (the withdraw path already exists) — no new banking code needed.
4. **Solar Array for NPCs — M.** No emporium purchase UI is needed (NPCs
   never open widgets): when an NPC executes `upgradeEquipment` at an
   emporium with `credits + bankBalance > threshold` (existing 100k gate),
   give cautious/explorer personalities a weighted chance to buy
   `solarArrayLevel = 1` (cost ≈ player module price in credits only — NPCs
   have no scrap economy, so don't charge scrap). Regen `2 * level`/tick
   applied at the top of `processTurn` when deployed; deployed NPCs skip
   `_move` (mirrors `EnergyService.canMove`). Keep level capped at 1–2 so
   the array stays a slow backup, not infinite fuel.
5. **Stranded fallback — S.** NPC equivalent of `TowService`: if an NPC
   cannot afford refuel *and* has no array, grant a one-time emergency
   reserve (same `max(10% tank, 2 warps)` formula as
   `TowService.emergencyEnergy`) charged against `bankBalance`, else leave
   it docked/idle until the next tick's regen. No pathfinding/teleport
   needed — NPCs don't soft-lock a human session, they just wait.
6. **Tick service (`game_tick_service.dart`) — S.** Replace the
   `turns <= 0` skip (line 141) with an energy gate, delete the 60-tick
   `turns: 200` replenish block (lines 181-195, replaced by refuel/array
   regen), and switch the attack-check gate (line 217) to
   `energy >= attackCost`. Log wording (`processed/skipped`) stays.
7. **Seeding + tests — S.** Universe generator seeds `energy/maxEnergy`
   instead of `turns: 1000`; new `test/npc_energy_test.dart` mirroring
   `test/energy_service_test.dart` (warp-cost math, refuel clamp, array
   regen clamp, stranded reserve) plus one `processTurn` test proving a
   zero-energy NPC does not move and a low-energy NPC picks the refuel
   goal.

**Effort:** ~2–3 focused sessions (S+S+M+M+S+S+S, each S ≈ 0.5 session).
No new screens, no storage migration beyond the `turns`→`energy` fallback,
and no balance pass — NPC ranges just need to *approximate* player ranges
so traders don't freeze mid-route. After this, `turns` can be deleted from
both `Player` and `NpcShip` and the game runs fully on energy.

Verify: `flutter analyze` → **No issues found!**, `dart format` clean,
`flutter test` → **41/41**, including the new `test/energy_service_test.dart`.