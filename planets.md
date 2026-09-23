# Planets — Design & Implementation Plan

## Current State (updated)

The planet model (`lib/data/models/planet.dart`) and `PlanetScreen` (tab 5 in the game shell) now implement **much of the design below**:

- **Model**: 10 planet types (Terran, Jungle, Desert, Ocean, Ice, Lava, Gas Giant, Moon, Barren, Toxic), each with atmosphere, production multipliers, colonist max, and an image pool (3 GIFs each). ~34 fields total incl. ownership, homeworld flag, colonists, storage, Citadel level 1-6 + progress, defense (level/shield/hull), and NPC spawn fields (`productionTimer`/`spawnInterval`)
- **UI (`PlanetScreen`)**: scan (costs 1 turn and persists), planet header + image, resources/defense cards, colony production readout (computed `X/tick`), transfer resources/colonists/drones both ways (credits-based), claim unowned planets, level-up (Outpost → Citadel, gated by colonists + stored resources). Attack is currently a stub (log-only)
- **Generator**: planets placed at `planetDensity` (default 0.25) outside FedSpace with images; one homeworld per major faction (duran/vinari/trader) with preferred types and unique names
- **Maps**: galaxy map & tactical map show planet markers (brown) with type/homeworld/owner status; sector view has a "land on planet" action
- **Not yet implemented**: per-tick automated production processing, homeworld NPC repopulation, invasion combat, scanner-module auto-scan, backup homeworld claiming, planet-to-port supply chains, NPC faction colonization, planet defense combat
- `Sector` now stores a structured `Planet?` object (`hasPlanet` + `planet`); the old `planetType` string field was removed (migrated via `fromJson`)

## Design Goals (from user conversation)

1. **NPC repopulation via homeworlds** — Each faction gets a homeworld planet that periodically spawns new NPC ships. Destroying/claiming the homeworld stops that faction from spawning.
2. **Colonist-driven production** — Planets produce resources only when populated with colonists (brought from Terra). More colonists = more output. Planet type determines production efficiency per commodity.
3. **Planet levels (Citadel 1–6)** — Planets level up by investing resources + colonists. Each level unlocks more production capacity, defense options, and storage. Based on the classic Citadel system from BBS-era space trading games.
4. **Scan before landing** — Must scan the planet first (requires scanner module or manual scan). Scanner module auto-scans when entering sector.
5. **Claiming & ownership** — Unowned planets can be claimed. Becomes property of the claiming player or faction. Claimed planets appear on Ship Status.
6. **Resource abundance** — Planets have effectively unlimited resources. The bottleneck is extraction rate, which scales with colonists and planet level.
7. **Max production rate** — Each planet has a cap per commodity per tick based on type + level + colonist count.
8. **Backup homeworld** — If a homeworld is destroyed, surviving faction NPCs can claim an unclaimed planet as a new homeworld (starts weak, builds up).
9. **Invasion** — Turn-based combat similar to port combat, targeting planet defenses.

## Inspiration (Research Summary)

Classic BBS-era planet system core mechanics:

| Mechanic | Classic BBS | Our adaptation |
|----------|--------|----------------|
| Planet creation | Genesis Torpedo in empty sector | Random gen at universe creation + future Genesis Torpedo item |
| Planet types | 7 types (M/K/O/L/C/H/U) with different production multipliers | 10 types, each with production rate multipliers for all 3 commodities |
| Colonists | Brought from Terra (sector 1) in cargo holds | Same — ship cargo holds carry colonists from Terra |
| Production assignment | Assign colonists to Fuel Ore / Organics / Equipment tracks | Assign colonists to Minerals / Organics / Industrial tracks |
| Citadel levels | 6 levels, each requires resources + colonists, takes real days | 6 levels, each requires resource investment, triggers on tick |
| Defense | Fighters + Quasar Cannons per level | Shield/hull per level + special abilities (matching port defense model) |
| Fighter production | Colonists produce fighters per day as passive output | Passive fighter production per tick (stored on planet) |

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

  // Colony
  int population;                    // total colonists on planet
  int colonistsMinerals;             // colonists assigned to mineral production
  int colonistsOrganics;             // colonists assigned to organic production
  int colonistsIndustrial;           // colonists assigned to industrial production
  int colonistsFighters;             // colonists assigned to fighter production
  double productionEfficiency;       // 0.5–1.5, random per planet

  // Storage (per commodity)
  int storedMinerals;
  int storedOrganics;
  int storedIndustrial;
  int storedFighters;
  int maxStorage;                    // scales with planet level

  // Level / Citadel (1–6)
  int level;                         // 1 = basic colony, 6 = max fortress
  int levelProgress;                 // resources invested toward next level

  // Resources needed for next level
  int requiredMinerals;
  int requiredOrganics;
  int requiredIndustrial;
  int requiredColonists;

  // Defense
  int defenseLevel;                  // 0–4, derived from planet level
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
}
```

## Planet Types & Production Multipliers

Each planet type has production multipliers for each commodity (1.0 = baseline).
Colonist output per tick = `baseOutput * multiplier * productionEfficiency`.

| Type        | Description           | Atm.    | Minerals | Organics | Industrial | Fighters |
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

## Planet Levels (Citadel)

Inspired by the classic 6-level Citadel system. Each level requires accumulating resources on the planet:

| Level | Title            | Minerals | Organics | Industrial | Colonists | Max Storage | Defense |
|-------|------------------|----------|----------|------------|-----------|-------------|---------|
| 1     | Outpost          | 500      | 300      | 200        | 100       | 5,000       | 0       |
| 2     | Settlement       | 2,000    | 1,000    | 1,000      | 500       | 25,000      | 1       |
| 3     | Colony           | 8,000    | 4,000    | 5,000      | 2,000     | 100,000     | 2       |
| 4     | Fortified Colony | 25,000   | 12,000   | 20,000     | 8,000     | 250,000     | 3       |
| 5     | Planetary Base   | 75,000   | 35,000   | 60,000     | 25,000    | 500,000     | 4       |
| 6     | Citadel          | 200,000  | 100,000  | 150,000    | 75,000    | 1,000,000   | 4       |

- Resources must be **shipped to the planet** and stored there.
- `levelProgress` tracks how much has been contributed toward the next level.
- Once all requirements are met, the planet upgrades on the next tick.
- Defense: shield/hull values are set per level at upgrade time.

## Colonists & Production

### Sourcing Colonists
- **Terra** (sector 1) is the sole source of colonists — matches the classic Citadel system.
- Colonists take up **1 cargo hold per colonist**.
- Load colonists at Terra (new UI action at Terra port or sector 1 planet interaction).
- Transport them to your planet and unload.
- Colonists consume 1 unit of Organics per 100 colonists per tick (upkeep).

### Assigning Colonists
When viewing a claimed planet, player can assign colonists to tracks:
- **Minerals** — produces `baseMinerals * mineralMultiplier * efficiency` per colonist per tick
- **Organics** — produces `baseOrganics * organicMultiplier * efficiency` per colonist per tick
- **Industrial** — produces `baseIndustrial * industrialMultiplier * efficiency` per colonist per tick
- **Fighters** — produces `baseFighters * fighterMultiplier * efficiency` per colonist per tick

Total assigned colonists cannot exceed `population`.

### Production Formula
```
outputPerTick = colonistsOnTrack * typeMultiplier * efficiency * tickIntervalFactor
```

Example: 100 colonists on Minerals on a Lava planet (2.0×) with 1.0 efficiency:
- `100 * 2.0 * 1.0 = 200 minerals per tick`

### Max Production Rate
Per commodity per planet per tick:
```
maxOutput = planetLevel * 500 * typeMultiplier * populationCapped
```
Hard ceiling prevents infinite scaling.

## Homeworld System

### Universe Generation
- Each major faction (Duran, Vinari, Trader) gets **one homeworld planet** in a random non-FedSpace sector.
- Homeworld type is weighted by faction lore:
  - **Duran**: biased Lava/Toxic/Barren/Moon (CO2/Acid/None) — `kron`/`mammat` class
  - **Vinari**: biased Terran/Jungle/Ocean (N2-O2) — `slyland` class
  - **Trader**: biased Terran/Desert/Moon (N2-O2/Thin/None) — `human` class
- Pirates get no homeworld (distributed threat).
- FedSpace planets stay unowned.

### Homeworld Properties
- Starts at **level 4** (Fortified Colony) with high defense stats
- `isHomeworld: true`, `homeworldOf: FactionClass`
- Populated with starting colonists (auto-assigned to balanced tracks)
- Name drawn from faction's `notableLocations` map, else the name pool

### NPC Spawning
- Every tick, each homeworld increments `productionTimer`.
- When `productionTimer >= spawnInterval`, spawn an NPC ship:
  - Faction matches `homeworldOf`
  - Ship appears in homeworld sector (or adjacent if full)
  - Ship power scales with homeworld level and population
- Default: 1 NPC per 10 ticks (5 min at 30s/tick).
- Spawning stops if `isHomeworld` is set to `false` (destruction).

### Homeworld Destruction
- Planet hull reduced to 0 via invasion combat.
- `isHomeworld = false`, `homeworldOf = null`, `owner = null` (or invader).
- Faction can no longer spawn NPCs.
- Existing NPCs continue their behaviors.

### Backup Homeworld
- If a faction has no homeworld but surviving NPCs exist, an NPC with `goal == patrol` or `explore` can be flagged as colonist.
- On visiting a sector with an unclaimed planet, they claim it as a new homeworld.
- New homeworld starts at level 1, low population, long spawn interval.
- Builds up over time (every N ticks: population grows, level progresses).

## Planet UI

### Navigation
- **Planets** is its own tab button on the left nav bar/rail, directly below Ports.
- Tab index in `GameShell`: 6 (after Settings) or re-sequenced.
- Shows planet in current sector, or "No planet in this sector."

### Entry Point
- "Land on Planet" button on tactical map / sector interaction panel.
- Only visible when `sector.hasPlanet == true`.
- If planet is not scanned, button says "Scan Planet" instead.
- Once scanned, button says "Land on Planet."
- Scanning gated: without scanner module, manual scan uses 1 turn.

### Planet Screen Layout

**Unscanned:**
```
┌─────────────────────────────────────┐
│  [Scan Planet] (1 turn)             │
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
│  └─ Fighters:    800 ████░░░░       │
│  Storage: 24,700 / 250,000          │
├─────────────────────────────────────┤
│  Production / tick:                 │
│  Minerals: 240 · Organics: 120      │
│  Industrial: 40 · Fighters: 16      │
├─────────────────────────────────────┤
│  Defense Level: ████░ 4             │
│  Shield: ██████████ 8000/8000       │
│  Hull:   ██████████ 20000/20000     │
├─────────────────────────────────────┤
│  [Manage] [Attack] [Leave]          │
└─────────────────────────────────────┘
```

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

## Implementation Phases

### Phase A: Model Replacement
- Replace `PlanetClass` enum with `planetType` String
- Rewrite `Planet` model with all enhanced fields
- Update `toJson`/`fromJson`
- Add `PlanetTypeConfig` map (multipliers + atmosphere per type)
- Update `Sector` — remove `planetType` field (now on `Planet`)

### Phase B: Universe Generator Updates
- Update `_createPlanet()` to:
  - Pick from 10 planet types with weighted distribution
  - Assign atmosphere based on type
  - Set random `productionEfficiency`
  - Generate starting resources (small amount already mined)
  - Pick random image from type pool
- Add homeworld placement logic for 3 factions
- Replace PlanetClass references with planetType

### Phase C: Scanning & Discovery
- Add `scanned` field to Planet
- "Scan Planet" button on sector interaction panel (costs 1 turn without scanner module)
- Scanner module auto-scans on sector entry (future hardware)

### Phase D: Colonist Transport
- Add colonist cargo type to Player ship (count as cargo holds)
- "Load Colonists" interaction at Terra (sector 1)
- "Unload Colonists" on planet screen
- Colonist count tracked on Planet model

### Phase E: Planet Production (Tick-Based)
- In `GameTickService`, iterate planets with population > 0
- For each, calculate production per track
- Add produced resources to planet storage
- Deduct organic upkeep
- Option: produce fighters
- Persist planet state

### Phase F: Planet Levels (Citadel)
- Track `level` and `levelProgress`
- Resources can be deposited toward next level via planet management UI
- On reaching thresholds, auto-upgrade on tick
- Defense values set on upgrade
- Max storage increases

### Phase G: Planet UI
- Planet tab on nav bar
- Planet screen: view, scan, claim, manage colonists, manage construction
- Planet management screen with tabs
- "Land on Planet" button on tactical map

### Phase H: Planet Combat
- Adapt `PortCombatScreen` for planet defense
- Planet shield/hull damage, surrender, loot, destruction

### Phase I: NPC Repopulation + Backup Homeworld
- Homeworld NPC spawning in game tick
- Backup homeworld claiming by NPC AI
- Colonist goal for orphaned faction NPCs

## References

- `lib/data/models/planet.dart` — current model (to be replaced)
- `lib/data/models/faction.dart` — FactionClass enum, faction lore with homeworld planet names
- `lib/data/models/sector.dart` — Sector with `hasPlanet` and `planet` field (remove `planetType`)
- `lib/data/models/universe_generator.dart` — phase 8 planet creation
- `lib/services/game_tick_service.dart` — 30s tick where production and spawning hooks in
- `lib/widgets/port_combat_screen.dart` — reusable combat pattern for invasions
- `lib/screens/port_screen.dart` — pattern for planet screen UI
- `lib/screens/port_management_screen.dart` — pattern for planet management screen
- `lib/widgets/sector_view_widgets/sector_interaction_panel.dart` — where "Land on Planet" / "Scan Planet" buttons go
- `lib/data/models/ship_equipment_types.dart` — for scanner module
