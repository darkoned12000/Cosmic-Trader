# Cosmic Trader

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
  - [Planets](#planets)
  - [Tools & Intelligence](#tools--intelligence)
- [Roadmap](#roadmap)
- [Technical Architecture](#technical-architecture)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

**Cosmic Trader** is a Flutter-based space trading game inspired by classic BBS-era space trading games. You play as the captain of a starship navigating a connected network of sectors, buying and selling commodities across ports of varying allegiances, managing your finances, and exploring a procedurally generated galaxy.

The game runs on Android, iOS, Web, Linux, macOS, and Windows — all from a single codebase.

Current status: **Active development with a full feature base in place.** The core trading/navigation loop is complete alongside a full NPC AI system (personality-driven trading, combat, banking, patrols, port raiding), player-vs-NPC and NPC-vs-NPC combat, interactive tactical map, a working hardware emporium (equipment purchases live), port ownership & management, several mini-games, and a partially implemented planet system (claiming, colonies, leveling). Dynamic economy, planet automation, black market goods, and NPC repopulation are the next frontiers.

---

## Features

### Implemented

- **Procedural universe generation** — 8-phase algorithm creates a fully connected, balanced graph of sectors with ports, planets, NPCs, homeworlds, and anomalies
- **Port trading** — Buy and sell commodities (minerals, organics, industrial by default) with finite supply and demand per port; data-driven `CommodityConfig` system makes adding new commodities trivial, and price/quantity ranges are editable in Settings
- **Galaxy map** — Interactive zoomable map with force-directed layout, tap-to-navigate, search, NPC position dots, and planet markers
- **Planet system (partial)** — Planet tab with scanning (1 turn), claiming, resource/colonist/drone transfers, colony production display, defense readout, and Citadel leveling (Outpost → Citadel); one homeworld per major faction at generation
- **Warp navigation** — Travel between connected sectors at the cost of 1 turn
- **Ship status screen** — View hull, shields, cargo, weapons, drones, credits, equipment stats (damage, fire rate, defense, regeneration, speed, warp capacity, efficiency), installed modules, and scrap inventory
- **Banking system** — Deposit and withdraw credits at 1% interest per 24 hours; view bank statistics across all players
- **Lottery mini-game** — Pick 6 unique digits (0-9), watch the animated draw, and win prizes up to 10M credits
- **Computer hub** — Centralized tool access: Banking, Port Report, Knowledge Base, Ports Guide, and Faction Power Rankings
- **Port Report** — Browse all ports with commodity filters and price sorting (Best Buy / Best Sell)
- **Knowledge Base** — In-game lore browser for factions (Duran Hegemony, Vinari Collective, Independent Traders Guild, Pirates)
- **Settings** — Configurable universe generation parameters, per-commodity price/quantity editors, per-faction NPC densities, theme picker (15 color presets + dark/light), font family/size, video (fullscreen/resolution/animation speed), audio (music/SFX volume + folder)
- **Authentication** — Local account creation with SHA-256 password hashing
- **Hacking mini-game** — 3-digit code cracking with escalating penalties and IP ban risk
- **Frequency Jamming** — Oscilloscope frequency matching mini-game to steal resources from ports; 45-second countdown timer, signal strength indicator, animated waveforms
- **Port Net Worth & Defense** — Each port displays its net worth (resources + credits + defense value) and defensive level (0-4)
- **Port Ownership & Management** — Purchase non-Federal ports through a haggling negotiation system (bank financing available). Owners get a full Port Management screen: upgrade defense levels, set commodity prices, collect revenue, rename. ~40% of non-FedSpace ports have named NPC owners
- **Hardware Emporium** — 7 tabs (Services, Weapons, Hull, Shields, Engines, Modules, Scrap). Purchases deduct credits and scrap metal/tech; equipment replacement refunds partial scrap; scrap sells for credits
- **Ship selection at registration** — 4 ship classes per faction (interceptor/battleship/freighter/capital ship); non-default classes can be locked behind milestones (toggle in Settings)
- **Persistent storage** — JSON file-based save system (players, universe, settings, npcs, per-player exploration)
- **Animated starfield** — Background with drifting and twinkling stars
- **Sector dashboard** — Three-panel responsive layout: Action Log (left), Tactical Map (center), Command Console (right) with warp console, NPC interaction cards, and ship status summary
- **Tactical map** — Multi-ring radial diagram showing current sector plus 1-hop and 2-hop neighbors; pan/zoom; legend with NPC dots and planet markers
- **Warp console** — Direct sector-number input + adjacent sector chips; long-range warp at Engine Level 3+
- **Action log** — Last 50 events with type-based filtering (info/success/warning/error/combat/trade/movement/system)
- **Communications panel** — Tabbed Chat/Mail/Quests card; mail dialog with Respond/Delete/Close-read-mark actions
- **Ship renaming** — Rename your ship via the Ship Status screen with an inline dialog
- **NPC scan details** — Scan action reveals full NPC loadout (ship, class, faction, personality, hull/shields, weapons with damage)
- **Combat system** — Full player-vs-NPC and NPC-vs-NPC combat resolution with shields, hull damage, loot, and death cries
- **NPC AI engine** — Personality-driven autonomous NPCs with 12 personalities (3 per faction) across 4 factions; goal state machine (trade, explore, attack, bank, flee, patrol, raid, upgrade); BFS pathfinding
- **NPC trading** — NPCs discover ports, evaluate trade routes by profit-per-hop, buy/sell commodities, bank profits
- **NPC banking** — Autonomous deposit/withdraw decisions based on caution thresholds and credit balances
- **NPC combat** — NPCs hunt hostile NPCs, raid weakly-defended ports, attack players (when aggressive and able to win)
- **NPC distress signals** — Outmatched NPCs broadcast distress calls; allied NPCs respond
- **NPC port owners** — ~40% of non-FedSpace ports have named NPC owners
- **NPC death cries** — Faction-specific death broadcasts when NPCs are destroyed
- **Faction Power Rankings** — Live report with pie/bar charts, top-10 pilots, power scores, combat stats, and wealth rankings
- **Game tick system** — 30-second background timer processes all NPCs; turn replenishment, proximity-filtered event logging
- **Audio system** — Music/SFX playback with volume control, custom music folder scanning (5 tracks bundled), loop modes, equalizer visualizer
- **Video settings** — Fullscreen toggle, resolution/window size, animation speed slider
- **Font customization** — Font family/size picker with custom .ttf/.otf file loading
- **Developer tools** — Dev overlay with FPS/CPU/memory monitoring and named-span profiler
- **Exploration persistence** — Visited sectors + timestamps (and bookmark/note model) persisted per player across sessions

### In Development

- NPC repopulation (prevent faction extinction over time — homeworld spawn fields exist but aren't wired to the tick)
- Damage-based fleeing (NPCs retreat at low hull based on caution)
- Faction standing tracking with combat and trade impact
- Player faction reputation UI
- Ship damage and repair persistence (repair service exists at emporiums)
- Planet automation — per-tick production, invasion combat, scanner auto-scan, backup homeworlds
- Full port upgrade tree (storage, deeper pricing tools)
- Dynamic commodity price fluctuations — faction relationships, anomalies, and player activity affect local markets
- Black market goods — high-risk, high-reward contraband trading
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
cd cosmic-trader
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
| Trader / Duran / Vinari / Pirate Density | 0.12 / 0.10 / 0.08 / 0.05 | Per-faction chance a sector has NPC ships |
| NPC Starting Credits | 10,000 | Starting credits for generated NPCs |
| FedSpace End | 9 | Last sector ID in Federation space |
| Bubble Chance | 0.15 | Probability of warp bubble clustering |
| Hardware Emporium Density | 0.05 | Chance a non-FedSpace port is a hardware emporium |
| Warp Distribution | 10/30/28/15/10/5/2% | Percentage split between 1-7 warp hops |
| Reset Players on Regen | On | Regenerating the universe resets all players to sector 1 |
| Delete All Players on Regen | Off | Full wipe for testing |
| Unlock All Ships | On | Bypass milestone locking for non-default ship classes |
| Sector Dashboard | On (default) | Three-panel responsive layout: Action Log, Tactical Map, Command Console |

**Commodity Economy** — each commodity's price range and quantity range are editable in Settings.

### Economy ranges

Each commodity has its own configurable price/quantity range via the `CommodityRegistry` data model. Defaults (editable in Settings):

| Commodity | Sell Range (player pays) | Buy Range (player receives) | Quantity Range |
|-----------|--------------------------|-----------------------------|----------------|
| Minerals | 10 - 42 cr | 43 - 75 cr | 10,000 - 80,000 |
| Organics | 80 - 114 cr | 115 - 150 cr | 5,000 - 70,000 |
| Industrial | 160 - 229 cr | 230 - 300 cr | 3,000 - 60,000 |

Sell and buy ranges are **guaranteed non-overlapping** — the mid-point (`splitPoint`) divides each commodity's total `[priceMin, priceMax]` range so the highest sell price is always below the lowest buy price. Every trade route is inherently profitable.

### Player starting values

| Setting | Default |
|---------|---------|
| Turns | 1000 |
| Credits | 1,000,000 |
| Cargo Holds | 50 |
| Drones | 100 |

### Audio / Video / Font

- **Audio** — Music and SFX volume sliders, custom music folder picker (5 tracks bundled in `assets/music/`), loop/equalizer modes
- **Video** — Fullscreen toggle, resolution + window scale, tactical display animation speed
- **Font** — Font family and size, custom `.ttf`/`.otf` loading

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
8. **Planets & NPCs** — Fills the universe with planets (one homeworld per major faction) and per-faction NPCs

Each sector may contain: a port, a planet, NPC ships, and/or an anomaly (asteroid field, nebula, gravity well, etc.).

### Factions

The galaxy is home to four factions. Three are playable at registration; the fourth exists as a hostile NPC presence.

**The Duran Hegemony** — A militaristic empire of insectoid warriors. They conquer through strength, view other species as resources, and patrol their borders aggressively. Their society is rigidly hierarchical, built on conquest and dominance.

**The Vinari Collective** — A decentralized alliance of bio-luminescent, semi-corporeal beings. They are nomadic explorers who value knowledge and harmony. Their technology is grown from crystalline seeds rather than built.

**The Independent Traders Guild** — A loose coalition of humanoid Terrans who turned to commerce after a failed federation. Pragmatic and profit-driven, they navigate the galaxy by staying neutral and exploiting opportunities.

**The Pirates** — A loose scattering of raiders, pillagers, and hunters with no central government. They prey on trade lanes, raid weakly-defended ports, and are a constant threat to players and NPCs alike. Their three archetypes (Raider, Pillager, Hunter) are the most aggressive personalities in the game.

### Economy & Trading

The economy revolves around commodities traded at ports. By default, three commodities exist, but the data-driven `CommodityRegistry` system makes adding new ones trivial (two entries in `commodity.dart`):

- **Minerals** — Basic raw materials
- **Organics** — Biological resources
- **Industrial** — Manufactured goods

**Port types:**

Each port is assigned a dynamic type string where each character corresponds to a commodity (in registry order). `S` = port sells (you buy), `B` = port buys (you sell). Type strings are generated at port-creation time with at least one `S` and one `B`. A port never buys and sells the same commodity.

A port class (Federal/Free/Independent/Hardware Emporium) affects appearance and reputation only — all classes draw from the same type-generation logic.

**How prices work (guaranteed profitable):**

Each commodity's `[priceMin, priceMax]` range is split at the mid-point (`splitPoint`):

- **Sell price** (what you pay to buy from the port) = random in `[priceMin, splitPoint)` — the **lower half**
- **Buy price** (what you receive when selling to the port) = random in `[splitPoint, priceMax]` — the **upper half**

This guarantees `maxSellPrice < minBuyPrice` for every commodity at every port. **Every trade route is inherently profitable.**

**Making a profit:**

Since sell prices are always in the lower half and buy prices always in the upper half, every port pair generates a profit:

```
Port A (sell price): 20 cr     ← lower half of [10, 75]
Port B (buy price): 60 cr      ← upper half of [10, 75]
Profit: 60 - 20 = 40 cr per unit (200% return)
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
| Hull | Ship structural integrity |
| Shields | Energy shields |
| Cargo | Used / Max cargo holds |
| Drones | Available / Max drones |
| Turns | Remaining / Max actions |
| Credits | On-hand credits |
| Equipment | Hull / Shield / Engine type + installed level |
| Modules | Installed modules (cargo expander, scanner, cloaking, etc.) |
| Scrap | Scrap Metal / Scrap Tech currency |
| Weapons | Laser, Pulse, Phaser, Torpedo/Missile levels |

**Equipment stats** — Each equipment displays its stats scaled by level:
- **Weapons**: Damage and Fire Rate
- **Hull**: Hull Bonus and Defense Rating
- **Shields**: Shield Bonus and Regen Rate
- **Engine**: Speed Bonus, Warp Capacity, and Efficiency

**Ship renaming** — Rename your ship via the Ship Status screen with an inline dialog.

**Owned ports** — Navigate to owned ports directly from the Ship Status screen.

**Ship classes** — Your ship is selected at registration from per-faction interceptor/battleship/freighter/capital-ship definitions (non-default classes can be milestone-locked via Settings).

### Galaxy Map

The interactive galaxy map visualizes all sectors as nodes connected by warp lines:

- **Zoom** — Pinch or scroll to zoom (0.1x - 5x)
- **Tap** — Select the nearest sector within tap range
- **Search** — Filter sectors by name or ID
- **Navigate** — Click "Move to Sector" to warp to the selected sector
- **NPC dots** — Faction-colored dots showing current NPC positions (updated per tick)
- **Planet markers** — Brown planet nodes showing type, homeworld/owner status
- **Layout** — Circular arrangement: FedSpace at 55% radius, others at 85%; optional force-directed layout for sectors ≤ 100

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

**Port Management** — Port owners unlock a full management screen:
- Upgrade port defenses (levels 0-4)
- Set commodity buy/sell prices and supply
- Collect port revenue
- Rename the port
- View owner summary

**NPC Port Owners** — ~40% of non-FedSpace ports have NPC owners (Trader Vex, Captain Rourke, Mama Duran, The Vinari Council, etc.)

### Planets

A planet system inspired by the classic TW2002 Citadel mechanics is partially implemented:

- **Scanning** — Planets require a scan (1 turn) to identify type, atmosphere, and owner. Scan results persist per planet.
- **10 planet types** — Terran, Jungle, Desert, Ocean, Ice, Lava, Gas Giant, Moon, Barren, and Toxic; each with its own atmosphere, production multipliers, colonist capacity, and animated image set.
- **Claiming & ownership** — Unclaimed planets can be claimed by your faction. Faction-owned planets display in the Planet tab with management actions.
- **Colonies** — Assign colonists and stock resources; the Colony card reports each planet type's minerals/organics/industrial/fighter output scaled by type multipliers and efficiency. (Automated per-tick production processing is pending.)
- **Citadel levels** — Outpost → Settlement → Colony → Fortified Colony → Planetary Base → Citadel. Leveling consumes stored resources and requires a colonist population minimum.
- **Transfers** — Move credits, resources, colonists, and drones between your ship and the planet (deposit/withdraw), and recruit colonists.
- **Homeworlds** — Each major faction (Duran, Vinari, Traders) has a designated homeworld at universe generation, sized for future NPC repopulation.
- **Defense** — Planets track defense level, shield, armor/hull, and stored fighters. Invasion combat is planned.

Not yet implemented: per-tick automated production, homeworld-based NPC repopulation, planet invasion combat, scanner module auto-scan, and backup homeworld claiming. See `planets.md` for the full design.

### Tools & Intelligence

The **Computer** hub provides five tools:

1. **Banking** — Full banking interface with deposit, withdraw, interest, and statistics
2. **Port Report** — Browse all ports in the universe with commodity filters and price sorting (Best Buy / Best Sell)
3. **Knowledge Base** — In-depth faction lore with expandable cards, faction selection, and copy-to-clipboard
4. **Ports Guide** — Static reference for port classes, buying mechanics, defenses, and management
5. **Faction Power Rankings** — Live leaderboard with pie/bar charts, top-10 pilots, power scores, and wealth rankings

### Hardware Emporium

Special violet-marked ports (density configurable in Settings) where you can upgrade your ship across 7 tabs:

- **Services** — Hull/shield repair, drone and ship purchases, respec
- **Weapons** — Buy and replace weapons (each level has its own stats)
- **Hull / Shields / Engines** — Buy and replace equipment by level
- **Modules** — Install hardware modules (cargo expander, scanner, cloaking, etc.)
- **Scrap** — Scrap metal/tech inventory: sell scrap for credits, spend it on upgrades

Listings are filtered by your faction. Purchases cost credits **and** scrap metal/tech; replacing equipped gear refunds a portion of its scrap value.

---

## Roadmap

### Phase 1: Core Systems (✅ Complete)
- [x] Universe generation (8-phase algorithm)
- [x] Navigation & warp (adjacent, long-range)
- [x] Port trading (data-driven commodity system, guaranteed profitable spreads)
- [x] Ship management (hull, shields, cargo, drones, turns, equipment, modules)
- [x] Banking (deposit, withdraw, 1% daily interest)
- [x] Lottery mini-game (pick-6, animated draw, 10M jackpot)
- [x] Galaxy map (interactive zoom, force-directed layout, search)
- [x] Knowledge Base (faction lore browser)
- [x] Settings & persistence (JSON file-based save system, commodity editor)
- [x] Hacking mini-game (3-digit code cracking, escalating penalties)
- [x] Frequency Jamming mini-game (oscilloscope matching, 45s timer)
- [x] Port defense levels (0-4) and net worth display
- [x] Port ownership & haggling system (negotiation, bank financing)
- [x] Ship renaming
- [x] Equipment stats display (damage, fire rate, defense, regen, speed, warp, efficiency)
- [x] Player faction assignment (Duran/Vinari/Trader)
- [x] Hardware Emporium (faction-filtered equipment purchasing — all 7 tabs)
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
- [ ] **NPC repopulation** — Spawn new NPCs over time to maintain faction density (homeworld fields exist; wiring pending)
- [ ] **Damage-based fleeing** — NPCs retreat when hull drops below caution-scaled threshold
- [ ] **Low-aggression immediate flee** — NPCs with aggression<0.3 flee from any hostile presence
- [ ] **Faction standing tracking** — Player actions (kills, trades, port purchases) affect reputation; combat checks standings
- [ ] **Player faction reputation UI** — Visible standing meter for each faction with effects shown

### Phase 3: Ship Equipment & Enhancements (Partial)
- [x] **Equipment purchasing** — Weapons, hull, shields, engines, and modules purchased from Hardware Emporiums (credits + scrap); services and scrap exchange live
- [x] **Ship selection at registration** — Multiple classes per faction (interceptor/battleship/freighter/capital), milestone-locked option
- [ ] **Ship damage & repair persistence** — Hull/shield repair service exists; persistent damage model pending
- [ ] **Shipyard** — Buy different ship classes in-galaxy (models and classes exist)
- [ ] **Additional weapon types** — Mines (area denial), missiles (high damage, ammo-limited)
- [ ] **Cloaking devices** — Temporarily hide from NPC detection; energy cost per tick
- [ ] **Scanners** — Detect cloaked ships, scan cargo at range
- [ ] **Hull plating & shield boosters** — Permanent damage reduction / shield capacity increase
- [ ] **Hacking computers** — Improve hacking mini-game success rates
- [ ] **Insurance system** — Pay premium to recover partial credits on ship destruction

### Phase 4: Economy, Ports & Black Market (Planned)
- [ ] **Full port upgrade tree** — Storage capacity, deeper defense/pricing influence, revenue generation
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

### Phase 5: Planets & Colonies (In Progress — see `planets.md`)
- [x] Planet model (10 types, atmospheres, production multipliers, images)
- [x] Planet scanning (1 turn), claiming, and ownership
- [x] Colony population + per-type production assignment and storage
- [x] Citadel leveling (Outpost → Citadel, 6 tiers)
- [x] Resource/colonist/drone transfers between ship and planet
- [x] Homeworld assignment per major faction at generation
- [ ] Planetary defenses & invasion combat (defense stats exist; combat pending)
- [x] Planetary resource extraction (minerals/organics/industrial/fighters per tick)
- [ ] Planet-to-port supply chains (colony production feeds adjacent port prices)
- [ ] Colonist system refinement (3 colonist types matching factions — each gives different bonuses)
- [ ] Planet colonization by NPC factions (autonomous empire building)
- [ ] Homeworld NPC repopulation + backup homeworld claiming
- [ ] Per-tick automated production engine

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
- [ ] Sound effects & music polish (musical tracks bundled)
- [ ] Test coverage — Unit + widget tests for all core systems (2 smoke tests exist today)

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
| Audio | audioplayers + file_picker (folder scanning, equalizer) |
| Desktop windowing | window_manager (fullscreen, size, window scale) |
| Code quality | flutter_lints, dart format |

### Project layout

```
lib/
  main.dart               # App entry point, theme, window_manager desktop setup
  core/                   # Theme, layout helpers, name generators
  data/
    models/               # Data models (Player, Sector, Planet, Port, Commodity, Faction, NpcShip, ...)
    storage/              # JSON file I/O (Player/Universe/Settings/Npc/Exploration storage)
  screens/                # UI screens (13+ screens)
  services/               # Game services (NPC AI engine, combat, tick system, audio, pathfinding)
  widgets/                # Reusable widgets (CombatScreen, BankingWidget, HardwareEmporium, StarField, ...)
```

### Assets

- `assets/images/factions/` — 3 SVG faction banners
- `assets/images/planets/` — 27 planet GIFs (10 types × 3 variants)
- `assets/music/` — 5 bundled music tracks (mp3/ogg)
- `assets/fonts/` — empty (custom fonts loaded at runtime)

### Architecture decisions

- **No DI framework** — Screens import storage singletons directly
- **Immutable player state** — `Player.copyWith()` for all updates
- **Versioned async writes** — Counter prevents stale writes from overwriting newer state
- **IndexedStack for tabs** — Preserves tab state while navigating; Computer and Planet keys regenerate on tab-select to reset screens
- **Adaptive layout** — `LayoutBuilder` + breakpoints for mobile vs desktop
- **Run checks** — `flutter analyze` is clean (7 informational deprecation hints); `flutter test` passes (2 widget tests)

---

## Contributing

This is an early-stage project. Contributions, ideas, and bug reports are welcome.

Areas where help is most valuable:
- UI polish and theming
- Combat balance and ship equipment system
- NPC repopulation and faction standing mechanics
- Planet automation (production, invasion, homeworlds)
- Dynamic economy and port upgrade design
- Black market goods and risk/reward balancing
- Test coverage (unit + widget)
- Bug fixes

---

## License

MIT — see LICENSE file for details.