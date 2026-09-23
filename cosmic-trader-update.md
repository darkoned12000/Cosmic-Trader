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

### B2. Dynamic economy (biggest single gameplay lever)
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

### B3. Give FactionStanding teeth (modeled but inert)
`combat_service` computes standing changes; nothing consumes them. Make
standing affect: port price multipliers, emporium access, banking interest,
attack-on-sight by Duran/Vinari NPCs, and FedSpace access (attacking Fed
targets has consequences — TW2002's Fed interdiction).

### B4. Bounties & pirate pressure (TW2002 bounty board, adapted)
- Fed ports post bounties on pirates — and on the player as `notoriety`
  climbs (`notoriety` already exists on Player).
- Bounty hunters appear (see NPC AI); hunting a marked pilot yields credits +
  standing. Feed kills/bounties into the existing Power Rankings report.

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