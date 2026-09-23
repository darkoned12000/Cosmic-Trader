# Tradewars 2050

> A space trading and exploration game built with Flutter.

Navigate a procedurally generated universe. Buy low, sell high. Manage your ship, bank your credits, play the lottery, and build your reputation among the factions. The galaxy is yours to explore — but can you turn a profit?

---

## Table of Contents

- [Overview](#overview)
- [Screenshots (coming soon)](#screenshots-coming-soon)
- [Features](#features)
- [Installation](#installation)
- [Configuration](#configuration)
- [Gameplay](#gameplay)
  - [The Universe](#the-universe)
  - [Factions](#factions)
  - [Economy & Trading](#economy--trading)
  - [Banking](#banking)
  - [Lottery](#lottery)
  - [Ship Status](#ship-status)
  - [Galaxy Map](#galaxy-map)
  - [Port Mini-Games](#port-mini-games)
  - [Port Ownership](#port-ownership)
  - [Tools & Intelligence](#tools--intelligence)
- [Roadmap](#roadmap)
- [Technical Architecture](#technical-architecture)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

**Tradewars 2050** is a Flutter-based space trading game inspired by the classic BBS-era TradeWars series. You play as the captain of a starship navigating a connected network of sectors, buying and selling commodities across ports of varying allegiances, managing your finances, and exploring a procedurally generated galaxy.

The game runs on Android, iOS, Web, Linux, macOS, and Windows — all from a single codebase.

Current status: **Active development with a full feature base in place.** The core trading/navigation loop is complete alongside a full NPC AI system (personality-driven trading, combat, banking, patrols, port raiding), player-vs-NPC and NPC-vs-NPC combat, interactive tactical map, hardware emporium ports, communications panel, port ownership & haggling, and several mini-games. Planetary systems, dynamic economy, port upgrades, and black market goods are the next frontiers.

---

## Features

### Implemented

- **Procedural universe generation** — 8-phase algorithm creates a fully connected, balanced graph of sectors with ports, planets, NPCs, anomalies, and aliens
- **Port trading** — Buy and sell commodities (minerals, organics, industrial by default) with finite supply and demand per port; data-driven `CommodityConfig` system makes adding new commodities trivial
- **Adaptive UI** — Navigation bar (mobile) / navigation rail (desktop) layout adapts to screen width
- **Galaxy map** — Interactive zoomable map with force-directed layout, tap-to-navigate, and search
- **Warp navigation** — Travel between connected sectors at the cost of 1 turn
- **Ship status screen** — View hull, shields, cargo, weapons, drones, credits, and equipment stats (damage, fire rate, defense, regeneration, speed, warp capacity, efficiency)
- **Banking system** — Deposit and withdraw credits at 1% interest per 24 hours; view bank statistics across all players
- **Lottery mini-game** — Pick 6 unique digits (0-9), watch the animated draw, and win prizes up to 10M credits
- **Computer hub** — Centralized tool access: Banking, Port Report, Knowledge Base
- **Port Report** — Browse all ports with commodity filters and price sorting
- **Knowledge Base** — In-game lore browser for factions (Duran Hegemony, Vinari Collective, Independent Traders Guild)
- **Settings** — Configurable universe generation parameters, theme picker (6 color presets + dark/light), player starting values
- **Authentication** — Local account creation with SHA-256 password hashing
- **Hacking mini-game** — 3-digit code cracking with escalating penalties and IP ban risk
- **Frequency Jamming** — Oscilloscope frequency matching mini-game to steal resources from ports; 45-second countdown timer, signal strength indicator, animated waveforms
- **Port Net Worth & Defense** — Each port displays its net worth (resources + credits + defense value) and defensive level (0-4)
- **Port Ownership** — Purchase non-Federal ports through a haggling negotiation system. Port owners gain access to Port Management for upgrading defenses, setting prices, and collecting revenue. Bank financing available for purchases.
- **Persistent storage** — JSON file-based save system (players, universe, settings)
- **Animated starfield** — Background with drifting and twinkling stars
- **Sector dashboard** — Three-panel responsive layout: Action Log (left), Tactical Map (center), Command Console (right) with warp console, NPC interaction cards, and ship status summary
- **Tactical map** — Multi-ring radial diagram showing current sector plus 1-hop and 2-hop neighbors (max 8 nodes/ring); pan/zoom via InteractiveViewer; optional twinkling starfield background; legend with color-coded node indicators (YOU, 1 HOP, 2 HOP, PORT, ALIENS, HAZARD, HARDWARE)
- **Warp console** — Direct sector-number input + adjacent sector chips (bare numbers); long-range warp at Engine Level 3+
- **Action log** — Last 50 events with type-based filtering (info/success/warning/error/combat/trade/movement/system); Wrap filter chips for responsive layout
- **Communications panel** — Tabbed Chat/Mail/Quests card; mail dialog with Respond/Delete/Close-read-mark actions
- **Hardware Emporium port class** — ~5% of non-FedSpace ports (violet display); faction-filtered equipment listings across 4 tabs (Ships/Weapons/Equip/Modules); density configurable in Settings
- **ShipStatus cargo hold** — Collapsible bullet-list showing each commodity with quantity
- **Ports Knowledge Base** — Browse all ports with commodity filters and price sorting (Best Buy / Best Sell)
- **Player faction assignment** — FactionClass field on Player model (Duran/Vinari/Trader); used by Hardware Emporium for equipment filtering
- **Ship renaming** — Rename your ship via the Ship Status screen with an inline dialog
- **Equipment stats display** — Each equipment shows its stats scaled by level: Weapons (damage, fire rate), Hull (hull bonus, defense rating), Shields (shield bonus, regen rate), Engine (speed bonus, warp capacity, efficiency)
- **Combat system** — Full player-vs-NPC and NPC-vs-NPC combat resolution with shields, hull damage, loot, and death cries
- **NPC AI engine** — Personality-driven autonomous NPCs with 12 personalities across 4 factions; goal state machine (trade, explore, attack, bank, flee, patrol, raid, upgrade); BFS pathfinding
- **NPC trading** — NPCs discover ports, evaluate trade routes by profit-per-hop, buy/sell commodities, bank profits
- **NPC banking** — Autonomous deposit/withdraw decisions based on caution thresholds and credit balances
- **NPC combat** — NPCs hunt hostile NPCs, raid weakly-defended ports, attack players (when aggressive and able to win)
- **NPC distress signals** — Outmatched NPCs broadcast distress calls; allied NPCs respond
- **NPC port owners** — ~40% of non-FedSpace ports have named NPC owners
- **NPC death cries** — Faction-specific death broadcasts when NPCs are destroyed
- **Faction Power Rankings** — Live report with pie/bar charts, top-10 pilots, power scores, combat stats, and wealth rankings
- **Galaxy map NPC dots** — Faction-colored position dots on both galaxy map and tactical map, updated live per tick
- **Game tick system** — 30-second background timer processes all NPCs; turn replenishment, proximity-filtered event logging
- **Port Management (placeholder)** — Owned ports display a management card (upgrade defenses, set prices, collect revenue — implementation pending)

### In Development

- NPC repopulation (prevent faction extinction over time)
- Damage-based fleeing (NPCs retreat at low hull based on caution)
- Faction standing tracking with combat and trade impact
- Player faction reputation UI
- Equipment purchasing from Hardware Emporiums
- Ship damage and repair system
- Full port upgrade system (storage, defenses, pricing tools)
- Dynamic commodity price fluctuations — faction relationships, anomalies, and player activity affect local markets
- Black market goods — high-risk, high-reward contraband trading
- Planet colonization and manufacturing
- Galaxy event log

---

## Installation

### Prerequisites

- Flutter SDK ^3.6.2 ([install guide](https://docs.flutter.dev/get-started/install))
- Dart SDK (bundled with Flutter)
- A code editor (VS Code, Android Studio, or IntelliJ recommended)

### Clone and run

```bash
git clone <repository-url>
cd tradewars_2050
flutter pub get
flutter run
```

To run on a specific platform:

```bash
flutter run -d chrome       # Web
flutter run -d linux        # Linux desktop
flutter run                 # Auto-detected device / emulator
```

### Clean rebuild

```bash
flutter clean && flutter pub get && flutter run
```

---

## Configuration

### Universe generation settings

All settings are configurable from the **Settings** screen (gear icon in the AppBar). Key parameters include:

| Setting | Default | Description |
|---------|---------|-------------|
| Total Sectors | 50 | Number of sectors in the universe |
| Seed | 0 (random) | Deterministic generation seed |
| Port Density | 0.35 | Chance a non-FedSpace sector has a port |
| Planet Density | 0.25 | Chance a sector has a planet |
| NPC Density | 0.4 | Chance a sector has NPC ships |
| Alien Density | 0.08 | Chance an alien ship appears |
| FedSpace End | 9 | Last sector ID in Federation space |
| Bubble Chance | 0.15 | Probability of warp bubble clustering |
| Hardware Emporium Density | 0.05 | Chance a non-FedSpace port is a hardware emporium |
| Sector Dashboard | On (default) | Three-panel responsive layout: Action Log, Tactical Map, Command Console |

### Economy ranges

Each commodity has its own configurable price/quantity range via the `CommodityRegistry` data model. Defaults:

| Commodity | Sell Range (player pays) | Buy Range (player receives) | Quantity Range |
|-----------|-------------------------|---------------------------|----------------|
| Minerals | 5 - 14 cr | 15 - 25 cr | 10,000 - 50,000 |
| Organics | 10 - 29 cr | 30 - 50 cr | 5,000 - 40,000 |
| Industrial | 20 - 59 cr | 60 - 100 cr | 40,000 - 30,000 |

Sell and buy ranges are **guaranteed non-overlapping** — the mid-point (`splitPoint`) divides each commodity's total `[priceMin, priceMax]` range so the highest sell price is always below the lowest buy price. Every trade route is inherently profitable.

### Player starting values

| Setting | Default |
|---------|---------|
| Turns | 1000 |
| Credits | 1,000,000 |
| Cargo Holds | 50 |
| Drones | 100 |

---

## Gameplay

### The Universe

The universe is procedurally generated using an 8-phase algorithm:

1. **Init** — Creates sectors with Greek/mythological names
2. **Terra Prime** — Sector 1 gets a Federal port ("Terra Prime")
3. **NavHaz & Anomalies** — Scatters navigation hazards and anomalies
4. **FedSpace Hub** — Connects Federation sectors into a hub network
5. **General Warps** — Grows warp connections from the center outward with bubble clustering
6. **Orphan Repair** — Ensures no sector is disconnected; balances warp distribution
7. **Ports** — Populates ports (Federal in FedSpace, mixed classes outside)
8. **Planets, NPCs & Aliens** — Fills the universe with interactive content

Each sector may contain: a port, a planet, NPC ships, alien ships, and/or an anomaly (asteroid field, nebula, gravity well, etc.).

### Factions

The galaxy is home to three major factions:

**The Duran Hegemony** — A militaristic empire of insectoid warriors. They conquer through strength, view other species as resources, and patrol their borders aggressively. Their society is rigidly hierarchical, built on conquest and dominance.

**The Vinari Collective** — A decentralized alliance of bio-luminescent, semi-corporeal beings. They are nomadic explorers who value knowledge and harmony. Their technology is grown from crystalline seeds rather than built.

**The Independent Traders Guild** — A loose coalition of humanoid Terrans who turned to commerce after a failed federation. Pragmatic and profit-driven, they navigate the galaxy by staying neutral and exploiting opportunities.

### Economy & Trading

The economy revolves around commodities traded at ports. By default, three commodities exist, but the data-driven `CommodityRegistry` system makes adding new ones trivial (two entries in `commodity.dart`):

- **Minerals** — Basic raw materials
- **Organics** — Biological resources
- **Industrial** — Manufactured goods

**Port types:**

Each port is assigned a dynamic type string where each character corresponds to a commodity (in registry order). `S` = port sells (you buy), `B` = port buys (you sell). Type strings are generated at port-creation time with at least one `S` and one `B`. A port never buys and sells the same commodity.

A port class (Federal/Free/Independent) affects appearance and reputation only — all classes draw from the same type-generation logic.

**How prices work (guaranteed profitable):**

Each commodity's `[priceMin, priceMax]` range is split at the mid-point (`splitPoint`):

- **Sell price** (what you pay to buy from the port) = random in `[priceMin, splitPoint)` — the **lower half**
- **Buy price** (what you receive when selling to the port) = random in `[splitPoint, priceMax]` — the **upper half**

This guarantees `maxSellPrice < minBuyPrice` for every commodity at every port. **Every trade route is inherently profitable.**

**Making a profit:**

Since sell prices are always in the lower half and buy prices always in the upper half, every port pair generates a profit:

```
Port A (sell price): 8 cr     ← lower half of [5, 25]
Port B (buy price): 22 cr     ← upper half of [5, 25]
Profit: 22 - 8 = 14 cr per unit (175% return)
```

Returns typically range from 30% to 300%+ depending on the random roll within each half. Larger spreads are found by visiting many ports and comparing prices.

### Banking

The **Terran Galactic Bank** offers secure credit storage with interest:

- **Deposit** — Credits in your bank earn 1% interest every 24 hours
- **Withdraw** — Access your funds anytime
- **Interest** — Calculated pro-rata based on time since last transaction
- **Statistics** — View total account holders and total deposits across all players

### Lottery

Feeling lucky? Each port offers a **Lottery** mini-game:

- **Ticket cost:** 2,500 credits
- **How it works:** Pick 6 unique digits (0-9), then watch the animated sequential draw
- **Prize tiers:**
  - 2 matches: 100 cr
  - 3 matches: 10,000 cr
  - 4 matches: 50,000 cr
  - 5 matches: 200,000 cr
  - 6 matches: 10,000,000 cr (jackpot)
  - **Exact order bonus:** 6 matches in exact order = 10x jackpot (100,000,000 cr!)
- **Limit:** Maximum 3 plays per 24-hour period

### Ship Status

Your ship has the following stats visible on the Ship screen:

| Stat | Description |
|------|-------------|
| Hull | Ship structural integrity (0-100) |
| Shields | Energy shields (0-100) |
| Cargo | Used / Max cargo holds |
| Drones | Available / Max drones |
| Turns | Remaining / Max actions |
| Credits | On-hand credits |
| Weapons | Laser, Pulse, Phaser, Torpedo levels |
| Engine | Engine level (affects warp capability) |

**Equipment stats** — Each equipment displays its stats scaled by level:
- **Weapons**: Damage and Fire Rate
- **Hull**: Hull Bonus and Defense Rating
- **Shields**: Shield Bonus and Regen Rate
- **Engine**: Speed Bonus, Warp Capacity, and Efficiency

**Ship renaming** — Rename your ship via the Ship Status screen with an inline dialog.

**Owned ports** — Navigate to owned ports directly from the Ship Status screen.

### Galaxy Map

The interactive galaxy map visualizes all sectors as nodes connected by warp lines:

- **Zoom** — Pinch or scroll to zoom (0.1x - 5x)
- **Tap** — Select the nearest sector within tap range
- **Search** — Filter sectors by name or ID
- **Navigate** — Click "Move to Sector" to warp to the selected sector
- **Layout** — Circular arrangement: FedSpace at 55% radius, others at 85%; optional force-directed layout for sectors ≤ 100

### Tools & Intelligence

The **Computer** hub provides three tools:

1. **Banking** — Full banking interface with deposit, withdraw, interest, and statistics
2. **Port Report** — Browse all ports in the universe with commodity filters and price sorting (Best Buy / Best Sell)
3. **Knowledge Base** — In-depth faction lore with expandable cards, faction selection, and copy-to-clipboard

### Port Mini-Games

Each port offers additional activities beyond trading:

**Hacking** — Crack a 3-digit security code. 5 attempts per hack, 3 max hack attempts per port with escalating penalties (500/2500/5000 cr). 3rd failure triggers a 24-hour IP ban.

**Frequency Jamming** — Match the port's security frequency using an oscilloscope interface. Adjust frequency, amplitude, and phase parameters to match the target signal within a 45-second countdown timer. Success lets you steal resources; failure alerts security forces.

**Port Net Worth & Defense** — Each port displays its net worth (total resources + port credits + defense value) and defensive level (0-4):
- Level 0: No defenses
- Level 1: Laser turrets
- Level 2: Laser turrets + drones
- Level 3: Laser turrets + drones + missiles
- Level 4: Laser turrets + drones + missiles + EMP pulse

Defense level contributes to port net worth: Level 1 = 250,000 cr, Level 2 = +500,000 cr, Level 3 = +750,000 cr, Level 4 = +1,000,000 cr.

### Port Ownership

**Purchasing Ports** — Non-Federal ports can be purchased through a haggling negotiation system:
- The asking price is based on the port's net worth (1.2x-1.5x multiplier)
- Make offers at 50%, 75%, 90%, or 100% of asking price (or custom amount)
- Offers at 70%+ of the counter offer result in a counter-offer (average of both)
- Offers below 70% are rejected
- Bank financing is available if you have sufficient bank balance
- Once purchased, the port name is added to your owned ports list

**Port Management** — Available only to port owners:
- Upgrade port defenses
- Set commodity prices
- Collect port revenue
- (Currently placeholder, full implementation planned)

**NPC Port Owners** — ~40% of non-FedSpace ports have NPC owners (Trader Vex, Captain Rourke, Mama Duran, The Vinari Council, etc.)

---

## Roadmap

### Phase 1: Core Systems (✅ Complete)
- [x] Universe generation (8-phase algorithm)
- [x] Navigation & warp (adjacent, long-range)
- [x] Port trading (data-driven commodity system, guaranteed profitable spreads)
- [x] Ship management (hull, shields, cargo, drones, turns)
- [x] Banking (deposit, withdraw, 1% daily interest)
- [x] Lottery mini-game (pick-6, animated draw, 10M jackpot)
- [x] Galaxy map (interactive zoom, force-directed layout, search)
- [x] Knowledge Base (faction lore browser)
- [x] Settings & persistence (JSON file-based save system)
- [x] Hacking mini-game (3-digit code cracking, escalating penalties)
- [x] Frequency Jamming mini-game (oscilloscope matching, 45s timer)
- [x] Port defense levels (0-4) and net worth display
- [x] Port ownership & haggling system (negotiation, bank financing)
- [x] Ship renaming
- [x] Equipment stats display (damage, fire rate, defense, regen, speed, warp, efficiency)
- [x] Player faction assignment (Duran/Vinari/Trader)
- [x] Hardware Emporium port class (faction-filtered equipment listings)
- [x] Adaptive UI (navigation bar/rail, responsive layouts)
- [x] Animated starfield background

### Phase 2: Combat & NPC AI (✅ Core Complete)
- [x] Ship-to-ship combat resolution (shields, hull, damage, loot)
- [x] Player-vs-NPC combat flow (CombatScreen with damage report)
- [x] NPC-vs-NPC combat (attacker/defender resolution, kill tracking)
- [x] NPC AI engine (12 personalities, goal state machine, BFS pathfinding)
- [x] NPC trading (trade route evaluation, port discovery, profit-per-hop)
- [x] NPC banking (autonomous deposit/withdraw, caution-based thresholds)
- [x] NPC attacks on player (aggression check, power threshold, CombatScreen push)
- [x] NPC port raiding (canRaidPort check, loot scaling)
- [x] NPC faction patrol behavior (random adjacent patrol chaining)
- [x] NPC distress signals (outmatched broadcasts, ally response)
- [x] NPC death cries (faction-specific broadcast on destruction)
- [x] NPC port owners (~40% of non-FedSpace ports)
- [x] Game tick system (30s background timer, batch processing, turn replenishment)
- [x] Tactical map (multi-ring radial, live NPC dots, legend)
- [x] Galaxy map NPC presence dots (faction-colored, updated per tick)
- [x] Faction Power Rankings report (pie/bar charts, top-10, power scores)
- [x] Action log (filtered event log with proximity-aware NPC events)
- [ ] **NPC repopulation** — Spawn new NPCs over time to maintain faction density (prevent extinction)
- [ ] **Damage-based fleeing** — NPCs retreat when hull drops below caution-scaled threshold
- [ ] **Low-aggression immediate flee** — NPCs with aggression<0.3 flee from any hostile presence
- [ ] **Faction standing tracking** — Player actions (kills, trades, port purchases) affect reputation; combat checks standings
- [ ] **Player faction reputation UI** — Visible standing meter for each faction with effects shown

### Phase 3: Ship Equipment & Enhancements (Up Next)
- [ ] **Equipment purchasing** — Buy weapons, hull, shields, engines from Hardware Emporiums (credits spent, ship updated)
- [ ] **Ship damage & repair** — Hull degradation persists; repair at ports for credit cost
- [ ] **Shipyard** — Purchase different ship classes with varied stats (freighter, warship, scout)
- [ ] **Additional weapon types** — Mines (area denial), missiles (high damage, ammo-limited)
- [ ] **Cloaking devices** — Temporarily hide from NPC detection; energy cost per tick
- [ ] **Scanners** — Detect cloaked ships, scan cargo at range
- [ ] **Hull plating & shield boosters** — Permanent damage reduction / shield capacity increase
- [ ] **Hacking computers** — Improve hacking mini-game success rates
- [ ] **Insurance system** — Pay premium to recover partial credits on ship destruction

### Phase 4: Economy, Ports & Black Market (Planned)
- [ ] **Full port upgrade tree** — Storage capacity, defense level, pricing influence, revenue generation
- [ ] **Dynamic commodity prices** — Prices fluctuate per tick based on:
  - Global supply/demand trends (weighted random walk)
  - Faction presence (faction-owned ports get trade bonuses)
  - Local effects (anomalies boost/depress adjacent sectors)
  - Player activity (heavy trading shifts local prices)
- [ ] **Faction economic effects** — Trade embargoes, faction trade routes, faction-subsidized commodities
- [ ] **Universe anomaly economy** — Anomaly types affect sector prices (nebula→organics premium, asteroid→minerals premium)
- [ ] **Black market goods** — Contraband commodities with seizure risk, NPC enforcement patrols, high profit margins
- [ ] **Port resource quantity evolution** — Supply/demand regenerates over time based on connected sector traffic
- [ ] **Trade route automation** — Set up recurring buy/sell routes between owned/known ports

### Phase 5: Planets & Colonies (Planned)
- [ ] Planet claiming and ownership (stake claim, pay fee, defend)
- [ ] Colony development (build housing, factories, defenses over time)
- [ ] Planetary resource extraction (mine minerals, harvest organics)
- [ ] Planet-to-port supply chains (colony production feeds adjacent port prices)
- [ ] Planetary defenses (ground turrets, fighter squadrons, shield dome)
- [ ] Colonist system (3 types matching factions — each gives different bonuses)
- [ ] Planet colonization by NPC factions (autonomous empire building)

### Phase 6: Social, Events & Galaxy Simulation (Planned)
- [ ] Galaxy event log — Persistent timeline of major events (wars, economic booms, disasters)
- [ ] Faction-specific missions — Dynamic quests generated from faction standing and galaxy state
- [ ] Dynamic galaxy events — Trade disruptions, faction skirmishes, pirate raids, natural disasters
- [ ] Chat system (in-memory, per-session)
- [ ] In-game message system (persistent, between sessions)
- [ ] Faction fleet coordination — Multiple NPCs attacking/defending together
- [ ] Alien encounters — Unique alien ships with special behaviors and loot

### Phase 7: Polish, Balance & Content (Future)
- [ ] Combat balance pass — Weapon stats, ship stats, NPC difficulty scaling
- [ ] Economy balance pass — Price ranges, profit margins, supply/demand curves
- [ ] UI polish — Consistent card styles, animations, transitions
- [ ] Tutorial system — New player onboarding flow
- [ ] Achievements / milestones
- [ ] Sound effects & music
- [ ] Test coverage — Unit + widget tests for all core systems

---

## Technical Architecture

### Stack

| Layer | Technology |
|-------|------------|
| Framework | Flutter (Dart 3.6.2+) |
| State management | Callback-driven lifted state (no BLoC/Provider) |
| Storage | File-based JSON (path_provider) |
| Navigation | Navigator 1.0 with MaterialPageRoute |
| Authentication | SHA-256 password hashing (crypto) |
| Code quality | flutter_lints, dart format |

### Project layout

```
tradewars_2050/lib/
  main.dart               # App entry point
  core/                   # Theme, layout helpers, name generators
  data/
    models/               # Data models (Player, Sector, Port, Faction, NpcShip, etc.)
    storage/              # JSON file I/O (PlayerStorage, UniverseStorage, SettingsStorage, NpcStorage)
  screens/                # UI screens (12+ screens)
  services/               # Game services (NPC AI engine, combat, tick system, pathfinding)
  widgets/                # Reusable widgets (CombatScreen, BankingWidget, LotteryWidget, StarField, etc.)
```

### Architecture decisions

- **No DI framework** — Screens import storage singletons directly
- **Immutable player state** — `Player.copyWith()` for all updates
- **Versioned async writes** — Counter prevents stale writes from overwriting newer state
- **IndexedStack for tabs** — Preserves tab state while navigating; Computer screen key regenerates on tab-select to reset tools
- **Adaptive layout** — `LayoutBuilder` + breakpoints for mobile vs desktop

---

## Contributing

This is an early-stage project. Contributions, ideas, and bug reports are welcome.

Areas where help is most valuable:
- UI polish and theming
- Combat balance and ship equipment system
- NPC repopulation and faction standing mechanics
- Dynamic economy and port upgrade design
- Planet colonization and resource systems
- Black market goods and risk/reward balancing
- Test coverage (unit + widget)
- Bug fixes

---

## License

MIT — see LICENSE file for details.
