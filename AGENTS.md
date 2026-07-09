# AGENTS.md -- Tradewars 2050 (Flutter)

## Project at a glance

Flutter app targeting Android, iOS, web, Linux, macOS, Windows. Dart SDK ^3.6.2.
All source code is under `tradewars_2050/`.

## Commands (run inside `tradewars_2050/`)

| Task | Command |
|------|---------|
| Get dependencies | `flutter pub get` |
| Run (device/emulator) | `flutter run` |
| Run on web | `flutter run -d chrome` |
| Run on Linux | `flutter run -d linux` |
| Analyze / lint | `flutter analyze` |
| Format check | `dart format --set-exit-if-changed lib/ test/` |
| Format fix | `dart format lib/ test/` |
| Run tests | `flutter test` |
| Single test | `flutter test test/widget_test.dart` |
| Clean + rebuild | `flutter clean && flutter pub get && flutter run` |

Always run `flutter pub get` before build, analyze, or test commands.

## Architecture

Layered structure under `lib/`. Screens import storage directly (no repository/DI layer).

```
lib/
  main.dart                       -- runApp, MaterialApp, inline theme from ThemeService, no named routes
  core/
    theme.dart                    -- TWTheme (unused — theme built inline in main.dart)
    theme_service.dart            -- static ValueNotifiers for live color/brightness, 15 presets
    tw_layout.dart                -- helpers (largeScreenMinWidth=600, extraLargeMinWidth=900)
    npc_name_generator.dart       -- sci-fi faction-themed NPC pilot/ship name generation
  data/
    models/
      player.dart                 -- immutable Player, copyWith, toJson/fromJson, ship stats,
                                     weapons, drones, cargo, banking, ownedPorts, faction, hardware
      sector.dart                 -- mutable Sector (coords, warps, content, npcShips, hardwareEmporium flag)
      planet.dart                 -- Planet + PlanetClass enum (mammat/kron/slyland/human)
      port.dart                   -- Port + PortClass enum (federal/free/independent),
                                     buyPrices/sellPrices, supply/demand, defenseLevel (0-4),
                                     portCredits, desiredCredits, lastRegenTime, owner (nullable),
                                     netWorth/defenseValue/isOwned getters, buys()/sells() helpers
      game_settings.dart          -- universe gen + economy + player init + warp distribution, const constructor
      universe_generator.dart     -- 8-phase generator (1131 lines, uses PathfindingService)
      faction.dart                -- Faction + FactionClass enum (duran/vinari/trader/pirate),
                                     heroes list, full lore (background, philosophy, motto, tech, etc.)
      faction_standing.dart       -- inter-faction reputation tracking via Map<FactionClass, int>
      npc_ship.dart               -- NpcShip model: identity, faction, shipDef, stats, equipment,
                                     cargo, personality, goal, memory, toJson/fromJson
      ship_templates.dart         -- ShipClassType enum (interceptor/battleship/freighter/capitalShip),
                                     ShipDefinition with per-faction templates
      hardware_data.dart          -- HardwareCategory enum, HardwareItem class, full item catalog
      ship_equipment_types.dart   -- HullType/ShieldType/EngineType/WeaponType/ModuleType enums + stat maps
    storage/
      player_storage.dart         -- singleton, file JSON (players.json), register/login/update/loadPlayers
      universe_storage.dart       -- singleton, file JSON (universe.json), generate/regenerate/saveSingleSector
      settings_storage.dart       -- singleton, file JSON (settings.json), persist GameSettings
      npc_storage.dart            -- singleton, file JSON (npcs.json), loadAll/saveAll
  screens/
    login_screen.dart             -- form, starfield, caps-lock detection, navigate to GameShell/Register
    register_screen.dart          -- 3-step registration (credentials, faction, ship), password strength
    game_shell.dart               -- adaptive layout, owns Player state, tick service, 6-tab navigation
    sector_view.dart              -- sector display with 7 sub-widgets, warp nav, NPC interaction, port quick-nav
    ship_status.dart              -- full ship stats (hull/shields/cargo/weapons/equipment), rename, owned ports
    galaxy_map.dart               -- interactive CustomPainter map, force-directed, search, NPC dots
    port_screen.dart              -- trading, supply/demand, port ownership, mini-games (lottery/hack/jam),
                                     hardware emporium, adaptive layout
    computer_screen.dart          -- tool hub: Banking, Port Report, Faction Rankings, Knowledge Base, Ports Guide
    settings_screen.dart          -- universe gen form, theme picker, warp-balance, starting values
    knowledge_base_screen.dart    -- expandable faction lore cards, rich-text rendering
    faction_rankings_screen.dart  -- leaderboard with faction tabs, net worth, kills, sector control stats
    ports_knowledge_base.dart     -- static reference guide for port classes, buying, defenses, management
  widgets/
    star_field.dart               -- animated starfield (150 stars, drift + twinkle)
    lottery_widget.dart           -- pick-6-digits mini-game, animated draw, prize tiers, max 3 plays/24h
    hacking_widget.dart           -- 3-digit code cracking, terminal UI, 5 attempts, escalating penalties
    frequency_jamming_widget.dart -- oscilloscope matching mini-game, 45s timer, signal strength, waveforms
    banking_widget.dart           -- deposit/withdraw, 1% daily interest, account stats
    combat_screen.dart            -- turn-based player-vs-NPC combat, weapon selection, damage calc, flee
    npc_trade_dialog.dart         -- player-NPC trading dialog for commodities at base prices
    hardware_emporium_widget.dart -- ship upgrade store (services/hull/shield/engine/weapons/modules)
    sector_view_widgets/
      action_log_provider.dart    -- ChangeNotifier singleton, LogType enum, max 200 entries
      action_log_panel.dart       -- color-coded scrollable log listening to ActionLogProvider
      tactical_map.dart           -- sector overview with NPC dots, markers, animated starfield bg
      warp_console.dart           -- adjacent sector chips + direct-ID input, validation
      sector_interaction_panel.dart -- NPC list with Hail/Attack actions
      communications_panel.dart   -- Messages/Scan/Hail tabbed panel
      ship_status_summary.dart    -- compact hull/shields/cargo progress bars for sector view
  services/
    game_tick_service.dart        -- background timer (30s), batch NPC processing, turn replenishment,
                                     proximity-filtered event logging, NPC attack detection
    npc_ai/
      npc_ai_service.dart         -- main NPC AI orchestrator: goal selection, pathfinding, action execution
      npc_goal.dart               -- NpcGoalType enum (tradeRoute/explore/attack/bank/flee/patrol/raid/upgrade)
      npc_memory.dart             -- PortInfo + NpcMemory, visited sector/port recall for trade route evaluation
      npc_personality.dart        -- 18 personality types across 4 factions, configurable trait weights
      npc_death_cries.dart        -- faction-specific death broadcast messages
      banking_ai.dart             -- NPC deposit/withdraw decisions based on caution/credit thresholds
      trade_evaluator.dart        -- TradeRoute evaluation, profit-per-hop analysis, nearest-port BFS
      pathfinding_service.dart    -- BFS shortest path between sectors
      combat_service.dart         -- combat resolution engine, damage/loot/faction-standing calculation
```

## File inventory (58 source files)

| Path | Role |
|------|------|
| `lib/main.dart` | App entry point, theme building, universe pre-gen |
| `lib/core/theme.dart` | TWTheme class (unused) |
| `lib/core/theme_service.dart` | Live color/brightness switching, 15 presets |
| `lib/core/tw_layout.dart` | Responsive layout breakpoints |
| `lib/core/npc_name_generator.dart` | Procedural NPC pilot/ship name generation |
| `lib/data/models/player.dart` | Player + ship stats + banking + faction + hardware |
| `lib/data/models/sector.dart` | Sector content container + npcShips list |
| `lib/data/models/planet.dart` | Planet model + class enum |
| `lib/data/models/port.dart` | Port + buy/sell prices + supply/demand + defense + ownership |
| `lib/data/models/game_settings.dart` | Universe generation config |
| `lib/data/models/universe_generator.dart` | 8-phase generation algorithm |
| `lib/data/models/faction.dart` | Faction model + lore data + heroes |
| `lib/data/models/faction_standing.dart` | Inter-faction reputation tracking |
| `lib/data/models/npc_ship.dart` | NPC ship model (identity, stats, equipment, AI state) |
| `lib/data/models/ship_templates.dart` | Ship class types + per-faction ship definitions |
| `lib/data/models/hardware_data.dart` | Hardware item catalog (services, hulls, shields, engines, weapons, modules) |
| `lib/data/models/ship_equipment_types.dart` | Equipment type enums + stat maps |
| `lib/data/storage/player_storage.dart` | Players file I/O |
| `lib/data/storage/universe_storage.dart` | Universe file I/O |
| `lib/data/storage/settings_storage.dart` | Settings file I/O |
| `lib/data/storage/npc_storage.dart` | NPC ships file I/O |
| `lib/screens/login_screen.dart` | Login form |
| `lib/screens/register_screen.dart` | 3-step registration form |
| `lib/screens/game_shell.dart` | Main game shell + tab routing + tick service |
| `lib/screens/sector_view.dart` | Sector display with 7 sub-widgets + warp |
| `lib/screens/ship_status.dart` | Ship stats + rename + owned ports |
| `lib/screens/galaxy_map.dart` | Interactive galaxy map |
| `lib/screens/port_screen.dart` | Trading + mini-games + hardware emporium |
| `lib/screens/computer_screen.dart` | Computer tool hub |
| `lib/screens/settings_screen.dart` | Universe gen form + theme picker |
| `lib/screens/knowledge_base_screen.dart` | Faction lore browser |
| `lib/screens/faction_rankings_screen.dart` | Leaderboard with faction tabs |
| `lib/screens/ports_knowledge_base.dart` | Port mechanics reference guide |
| `lib/widgets/star_field.dart` | Animated background |
| `lib/widgets/lottery_widget.dart` | Lottery mini-game |
| `lib/widgets/hacking_widget.dart` | Hacking mini-game |
| `lib/widgets/frequency_jamming_widget.dart` | Frequency jamming mini-game |
| `lib/widgets/banking_widget.dart` | Banking system |
| `lib/widgets/combat_screen.dart` | Turn-based player-vs-NPC combat |
| `lib/widgets/npc_trade_dialog.dart` | NPC trading dialog |
| `lib/widgets/hardware_emporium_widget.dart` | Ship hardware upgrade store |
| `lib/widgets/sector_view_widgets/action_log_provider.dart` | ChangeNotifier log singleton |
| `lib/widgets/sector_view_widgets/action_log_panel.dart` | Color-coded log display |
| `lib/widgets/sector_view_widgets/tactical_map.dart` | Sector tactical overview |
| `lib/widgets/sector_view_widgets/warp_console.dart` | Adjacent warp navigation |
| `lib/widgets/sector_view_widgets/sector_interaction_panel.dart` | NPC interaction hub |
| `lib/widgets/sector_view_widgets/communications_panel.dart` | Tabbed comms panel |
| `lib/widgets/sector_view_widgets/ship_status_summary.dart` | Compact ship stats card |
| `lib/services/game_tick_service.dart` | 30s background tick timer |
| `lib/services/npc_ai/npc_ai_service.dart` | NPC AI orchestrator |
| `lib/services/npc_ai/npc_goal.dart` | NPC goal types |
| `lib/services/npc_ai/npc_memory.dart` | NPC port/sector memory |
| `lib/services/npc_ai/npc_personality.dart` | 18 personality types |
| `lib/services/npc_ai/npc_death_cries.dart` | Faction-specific death cries |
| `lib/services/npc_ai/banking_ai.dart` | NPC banking decisions |
| `lib/services/npc_ai/trade_evaluator.dart` | NPC trade route evaluation |
| `lib/services/npc_ai/pathfinding_service.dart` | BFS shortest path |
| `lib/services/npc_ai/combat_service.dart` | Combat resolution engine |

### Universe generator algorithm

`UniverseGenerator.generate()` runs 8 phases:

1. **Init** — Greek/mythological sector names, placeholder coords, empty warp lists. Also generates NPC ships via `_createNpcs()`
2. **Terra Prime** — Sector 1 gets a Federal port with random pricing via `_createPort`
3. **NavHaz/Anomaly** — 15% navHaz + anomalies at `anomalyDensity` outside FedSpace
4. **FedSpace hub** — Sectors 1-7 connect 2-3 peers; 8..fedEnd connect to 2-3 hubs
5. **General warps** — "grow-from-center" coords with bubble clustering; distance-weighted connections
6. **Orphan/connectivity/balancing** — Fix orphans, BFS repair, `_balanceDistribution` up to 100 iterations
7. **Ports** — FedSpace = Federal; outside = portDensity (30% federal, 40% free, 30% independent). Each port gets defenseLevel (0-4), portCredits, and ~40% chance of NPC owner; hardware emporium flag at hardwareEmporiumDensity
8. **Planets/NPCs/Aliens** — FedSpace planets at 50%; global planetDensity; NPCs by faction density settings; aliens at alienDensity

Seeding: `GameSettings.seed` → `Random(seed)`. Seed 0 → time-based replacement.

### Economy model

Three commodities: minerals (5-25 cr), organics (10-50 cr), industrial (20-100 cr).
Each port gets random price per commodity within `[PriceMin, PriceMax]`.

Ports use TradeWars-style type strings:

```
const portTypes = ['SBB', 'SBS', 'SSB', 'BSS', 'BBS', 'BSB', 'SSS', 'BBB'];
```

Each character position = commodities in order (minerals, organics, industrial).
`S` = port sells (player buys), `B` = port buys (player sells).
`buyPrice = base * (0.75-0.95)` for B commodities; `sellPrice = base` for S commodities.

A port never buys and sells the same commodity. Profit requires finding ports at opposite ends of the random price range.

### NPC AI engine

Autonomous NPCs with 18 personality types across 4 factions (Duran, Vinari, Trader, Pirate). Goal state machine with weighted random selection:

- **Goals**: tradeRoute, explore, attack, bankDeposit, bankWithdraw, patrol, flee, upgradeEquipment, raidPort
- **Personality config**: aggression (0-1), greed (0-1), caution (0-1), explorationDrive, maxTravelDistance
- **Pathfinding**: BFS shortest path via `PathfindingService`
- **Trading**: Port discovery, profit-per-hop route evaluation, buy/sell commodities, bank profits
- **Banking**: Autonomous deposit/withdraw based on caution thresholds and credit balances
- **Combat**: NPCs hunt hostiles, raid weakly-defended ports, attack players (aggression + power check)
- **Distress signals**: Outmatched NPCs broadcast; allied NPCs respond
- **Port owners**: ~40% of non-FedSpace ports have named NPC owners
- **Death cries**: Faction-specific broadcasts when NPCs are destroyed
- **Processing**: `GameTickService` runs every 30s, batches NPC turns, proximity-filters events to player sector

### Combat system

Turn-based player-vs-NPC combat (`CombatScreen`):
- Weapon selection from equipped weapons (laser/pulse/phaser/torpedo/missile)
- Damage calculation using equipment stats (damage, fire rate, energy drain)
- Shield management (shields absorb damage first)
- Hull damage (hull reaches 0 = destroyed)
- Flee option
- Loot on victory (credits + cargo)
- NPC-vs-NPC resolution via `CombatService`

### Sector dashboard (SectorView)

Three-panel responsive layout when enabled in Settings:
- **Left**: Action Log (last 50 events, type-based filtering: info/success/warning/error/combat/trade/movement/system)
- **Center**: Tactical Map (multi-ring radial diagram, 1-hop + 2-hop neighbors, color-coded node indicators, NPC dots)
- **Right**: Command Console with Warp Console (adjacent sector chips + direct input, long-range at Engine 3+), NPC interaction cards, Ship Status Summary

### Port Screen features

- Buy/sell UI for minerals, organics, industrial
- Finite supply/demand per commodity (local decrements, reset on universe reload)
- Port Net Worth & Defensive Level display (0-4)
- Port ownership (haggling negotiation with counter-offer system, bank financing)
- Port Management (owner-only: upgrade defenses, set prices, collect revenue — partial implementation)
- Mini-games: Lottery (pick-6), Hacking (3-digit code), Frequency Jamming (oscilloscope)
- Hardware Emporium (faction-filtered equipment buying across 4 tabs)
- Adaptive layout: GridView (3 cols) on wide, vertical list on narrow

### Galaxy Map

- `CustomPainter` inside `InteractiveViewer` (0.1x-5x zoom)
- Circular layout: FedSpace at 55% radius, others at 85%
- Optional force-directed (≤100 sectors, 100 iterations)
- Tap = nearest node within `nodeRadius + 4px`
- Search by name/ID
- NPC overlay dots with faction colors (updated per tick)
- "Move to Sector" via `onSectorSelected(int)` callback

### Ship hardware / equipment

Full equipment system with faction-specific items across categories:
- **Hulls**: 12 types (faction-specific, varying hull/shields/cargo)
- **Shields**: 12 types (faction-specific, varying shield/regen)
- **Engines**: 12 types (faction-specific, varying speed/warp/efficiency)
- **Weapons**: 15 types (laser/pulse/phaser/torpedo/missile × 3 tiers)
- **Modules**: 7 types (cargo expander, scanner, cloaking, etc.)
- **Services**: Repair, rename, respec

Equipment stats: Weapons (damage, fire rate), Hull (hull bonus, defense), Shields (shield bonus, regen), Engine (speed, warp capacity, efficiency).

## State management

No BLoC/Provider/Riverpod. Callback-driven lifted state in `GameShell`:

- `Player` is immutable, updated via `copyWith()`
- `_playerUpdateVersion` counter prevents stale async writes
- Tab indices: 0=Sector, 1=GalaxyMap, 2=Ship, 3=Computer, 4=Port, 5=Settings
- Settings not in nav bar/rail, accessible via AppBar gear or rail button
- `_computerKey` = `UniqueKey()` regenerated on tab-select → ComputerScreen resets to menu
- Theme via `ValueNotifier`s on `ThemeService`
- `ActionLogProvider.global` — `ChangeNotifier` singleton for game event log (max 200 entries)

## Routing

Navigator 1.0. No named routes. Only `'/'` → `LoginScreen`.
Push/pop via `MaterialPageRoute`. Logout uses `pushAndRemoveUntil`.

## Storage

File-based JSON in app documents directory:
- `players.json` — player accounts
- `universe.json` — list of Sector
- `settings.json` — persisted GameSettings
- `npcs.json` — NPC ship states

`UniverseStorage.ensureUniverse()` fires at startup (fire-and-forget).

## Dependencies

- `path_provider` ^2.1.3 — file paths
- `uuid` ^4.4.0 — ID generation
- `crypto` ^3.0.3 — password hashing
- `flutter_lints` ^5.0.0 — lint rules

## Known issues / technical debt

- `core/theme.dart` (TWTheme) is unused — theme built inline in main.dart from ThemeService
- Repeated UI patterns (cards, stat bars, pills) duplicated across screens
- No shared widget library for common patterns
- No lint/format CI pipeline
- No tests beyond default `widget_test.dart`
- Port Management is partially implemented (management card shown but full upgrade/pricing/revenue pending)

## Economy notes

The buy/sell price model creates a natural spread at each port (buy is always 75-95% of sell). Profit relies on finding ports at opposite ends of the random price range. With default ranges (minerals 5-25, organics 10-50, industrial 20-100), a good trade run can net 200-400% return.

## Features planned (roadmap reference)

See README.md for full roadmap. Key items remaining:
- NPC repopulation (prevent faction extinction)
- Damage-based fleeing for NPCs
- Low-aggression immediate flee
- Faction standing tracking with combat/trade impact
- Player faction reputation UI
- Equipment purchasing (UI complete, transaction logic pending)
- Ship damage & repair system
- Full port upgrade tree (storage, defenses, pricing, revenue)
- Dynamic commodity price fluctuations
- Black market goods
- Planet colonization & manufacturing
- Galaxy event log
- Chat & message system
- Additional ship classes
- Colonist system
- Balance passes and test coverage
