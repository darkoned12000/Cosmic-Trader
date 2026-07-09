# 🎮 TRADEWARS 2050 - NPC IMPLEMENTATION PLAN

## 📋 PROJECT OVERVIEW

**Objective:** Implement fully autonomous NPCs in separate storage system with faction-specific ship classes, unique name generation, tactical display indicators, and player-side integration.

**Current State:** NPC AI fully implemented (Phases 1-4). Live NPC ships appear in Sector Interaction Panel with SCAN/HAIL/TRADE/ATTACK buttons. Tactical Map draws live NPC position dots that update as NPCs move. GameTickService runs on a 30s background timer processing all NPCs. Combat resolves with player-vs-NPC damage and loot.

---

## ✅ COMPLETED PHASES

### Phase 1 — Foundation (complete)

| Component | File | Status |
|-----------|------|--------|
| NpcShip model (enhanced) | `lib/data/models/npc_ship.dart` | ✅ Banking, weapons, equipment, AI state, combat stats |
| NpcPersonality + PersonalityConfig | `lib/services/npc_ai/npc_personality.dart` | ✅ 12 personalities (3 per faction), goal weights, aggression/greed/caution |
| NpcGoal model (state machine) | `lib/services/npc_ai/npc_goal.dart` | ✅ Types: trade, explore, attack, bank, flee, patrol, raid, upgrade |
| NpcMemory model | `lib/services/npc_ai/npc_memory.dart` | ✅ Visited sectors, discovered ports, threats, hazards |
| PathfindingService (extracted) | `lib/services/npc_ai/pathfinding_service.dart` | ✅ BFS pathfinding, distance, nearest-where |
| FactionStanding model | `lib/data/models/faction_standing.dart` | ✅ Default standings per faction pair, hostility check |
| NpcStorage (enhanced) | `lib/data/storage/npc_storage.dart` | ✅ Singleton, loadAll/saveAll/findInSector |
| NpcNameGenerator | `lib/core/npc_name_generator.dart` | ✅ Faction + pirate name pools |

### Phase 2 — Core AI Engine (complete)

| Component | File | Status |
|-----------|------|--------|
| TradeEvaluator | `lib/services/npc_ai/trade_evaluator.dart` | ✅ Best-trade-route with profit-per-hop ranking |
| CombatService | `lib/services/npc_ai/combat_service.dart` | ✅ Damage resolution, canWin, canRaidPort, player-vs-NPC combat |
| BankingAi | `lib/services/npc_ai/banking_ai.dart` | ✅ Deposit/withdraw decisions with caution-based thresholds |
| NpcAiService | `lib/services/npc_ai/npc_ai_service.dart` | ✅ Orchestrator: scan → execute → evaluate → plan → move |

### Phase 3 — Turn Processing (complete)

| Component | File | Status |
|-----------|------|--------|
| GameTickService | `lib/services/game_tick_service.dart` | ✅ 30s background timer, batch NPC processing, turn replenishment |
| GameShell integration | `lib/screens/game_shell.dart` | ✅ Start/stop with widget lifecycle, NPC reload on tick complete |

### Phase 4 — UI Integration (complete)

| Component | Status | Notes |
|-----------|--------|-------|
| NPC ship cards in Sector Interaction Panel | ✅ | Named cards per NPC with faction colors + SCAN/HAIL/TRADE/ATTACK |
| SCAN overlay | ✅ | Dialog shows hull, shields, credits, cargo, equipment |
| HAIL overlay | ✅ | Dialog shows faction lore + personality description |
| TRADE interaction | ✅ | Shows NPC cargo contents (if any) |
| ATTACK flow | ✅ | Combat resolution via CombatService, damage report + loot dialog |
| Tactical Map live NPC dots | ✅ | Draws faction-colored dots at sector positions from active NPC list; map re-paints when NPCs move |
| Galaxy Map NPC icons | ✅ | Faction-colored dots on galaxy map nodes, updates on tick |
| Event log notifications | ✅ | NPC warps, kills, trades, destruction logged to ActionLogPanel via global ActionLogProvider singleton |
| Galaxy Map legend | ✅ | Already shows "PIRATE" (no "Aliens" existed in galaxy map) |

---

## 📋 REMAINING WORK (ordered by priority)

### Phase 4.5 — UI Polish (next)

#### 1. Galaxy Map NPC Presence Icons
**File:** `lib/screens/galaxy_map.dart`
Add NPC position dots to the galaxy map so players can see where NPCs are concentrated.

```dart
// In galaxy map painter:
final npcsInSector = npcs.where((n) => n.currentSectorId == sector.id).toList();
if (npcsInSector.isNotEmpty) {
  // Draw a small faction-colored dot for each NPC
  // Offset dots around sector node to show multiple NPCs
}
```
- Show up to 3 dots per faction per sector (to avoid visual clutter)
- Color matches faction legend (blue=trader, red=duran, teal=vinari, black=pirate)
- Re-paint on NPC list changes

#### 2. Event Log Integration
**File:** `lib/screens/sector/widgets/action_log_provider.dart`
Pipe NPC actions into the Action Log panel so players see what NPCs do.

```dart
// When GameTickService processes a tick, inject log entries:
logProvider.system('Pirate "Bloodfang" destroyed in sector 14');
logProvider.movement('Trader "Starhawk" warped from sector 5 → sector 12');
logProvider.combat('Duran warship attacked player in sector 7');
```

Types of events to log:
- NPC warps between sectors (by faction)
- NPC destroyed in combat (by whom)
- NPC trades at port (commodity + profit)
- NPC banks credits (deposit/withdraw)
- NPC attacks player

#### 3. Galaxy Map Legend Update
**File:** `lib/screens/galaxy_map.dart`
Replace "Aliens" legend with "Pirates" (keep it red).

---

### Phase 5 — NPC Behavior & Balance

#### 1. NPC Attacks on Player (while in same sector)
**Currently:** Player can attack NPCs via the ATTACK button, but NPCs don't initiate combat against the player.

**Files:** `lib/services/npc_ai/npc_ai_service.dart`, `lib/screens/sector/widgets/sector_interaction_panel.dart`

**How it should work:**
- During NPC tick processing, `_evaluateThreat` already checks for enemies in the same sector
- Aggressive NPCs (`personalityConfig.aggression > 0.6`) should attack the player if:
  1. Same sector as the player
  2. `CombatService.canWin(npc, player)` returns true (NPC judges it can win)
  3. NPC has enough hull/shields (> 50%)
- If outmatched, the NPC should flee instead of attacking

```dart
// In NpcAiService.processTurn:
if (npc.currentSectorId == player.currentSectorId) {
  if (personalityConfig.aggression > 0.6 &&
      CombatService.canWin(npc, playerAsNpcProxy)) {
    return _executeNpcAttacksPlayer(npc, player);
  } else if (personalityConfig.caution > 0.5) {
    return _executeFlee(npc, sectors);
  }
}
```

**Retreat options:**
- NPCs with `caution > 0.5` will flee the sector if damaged below 40% hull
- NPCs with `aggression < 0.3` flee immediately if any hostile ship is present
- Flee target: nearest sector NOT containing the threat
- Flee path: `PathfindingService.findPath()` away from threat

#### 2. NPC Cleanup (destroyed ship removal)
**Currently:** Destroyed NPCs have `isDestroyed = true` but remain in the NPC list forever.

**File:** `lib/services/npc_ai/npc_ai_service.dart`, `lib/data/storage/npc_storage.dart`

**Requirements:**
- Periodically remove NPCs with `isDestroyed = true` from storage (during GameTickService)
- Track why they were destroyed (player kill, NPC kill, natural causes)

```dart
// In GameTickService._processTick or NpcAiService:
npcs.removeWhere((n) => n.isDestroyed);
```

#### 3. NPC Repopulation
**Currently:** No new NPCs spawn after universe generation. Factions would die off over time.

**File:** `lib/services/game_tick_service.dart`

**Design decision needed (deferred per user):**
- Option A: Periodic respawn — new NPCs spawn every N ticks to maintain density
- Option B: Spawn on entry — new NPCs spawn when player enters a sector with low NPC count  
- Option C: Manual only — player triggers regeneration, which re-creates all NPCs

**Suggested default (until user decides):**
- Check total NPC count every 60 ticks (30min at 30s/tick)
- If total < initial count * 0.5, spawn new NPCs up to initial count
- New NPCs spawned at random sectors away from player's current sector

#### 4. NPC-vs-NPC Combat
**Currently:** Only player-vs-NPC combat resolves. NPCs attack each other in `_executeAttackGoal` but the defender is updated in-place in the list.

**File:** `lib/services/npc_ai/npc_ai_service.dart`

**Already implemented** in `_executeAttackGoal`:
- Attacker NPC checks `canWin` first
- On victory, defender is marked `isDestroyed`
- Attacker gains loot + kill credit

**Remaining:**
- Defending NPC should be able to flee if outmatched (check in same tick)
- If both NPCs are aggressive, resolve one round of combat

#### 5. Missing AI Behaviors

| Behavior | Status | Priority |
|----------|--------|----------|
| Equipment upgrade at hardware emporiums | ❌ Not implemented | Low |
| Port raiding (NPC attacks port for credits) | ❌ Not implemented | Low |
| Patrol loops within faction territory | ❌ Not implemented | Low |
| Faction standing tracking (per-NPC memory) | ✅ Model exists, not wired into combat | Medium |
| Player faction relations shown in UI | ❌ Not implemented | Low |

---

### Phase 6 — Future Enhancements (beyond this plan)

| Feature | Notes |
|---------|-------|
| Turns → Fuel conversion | Rename `Player.turns` → `Player.fuel` throughout |
| NPC ⇔ NPC trading | Direct NPC-to-NPC trade at ports or rendezvous |
| Planet colonization | NPCs claiming/developing planets |
| Multi-round combat | Turn-by-turn dialog with retreat, boarding, surrender |
| Fleet coordination | Multiple NPCs coordinating attacks or convoys |
| Dynamic economy | NPC trading affects port supply/demand |
| Chat / Message system | NPCs sending messages to players |

---

## 🔄 DATA FLOW (current)

```
GameShell
├── _player (Player) — immutable, updated via copyWith
├── _npcs (List<NpcShip>) — loaded from NpcStorage, passed to child widgets
│   ├── SectorViewV2 — npcs filtered to _npcsInSector
│   │   ├── TacticalMap — draws NPC dots from full npcs list
│   │   ├── SectorInteractionPanel — shows NPC cards for _npcsInSector
│   │   └── WarpConsole, ShipStatusSummary, ActionLogPanel
│   ├── GalaxyMap — accepts npcs parameter (icons not yet drawn)
│   └── SectorView (v1 fallback) — accepts npcs parameter
├── GameTickService — 30s timer
│   ├── Loads npcs + sectors + players
│   ├── NpcAiService.processTurn() × N
│   ├── Saves back to NpcStorage
│   └── Calls setState on GameShell → widgets refresh
└── onPlayerUpdate → PlayerStorage.savePlayer
```

---

## 🎯 KEY DESIGN RULES

1. **Banked credits are SAFE** — only on-ship credits lost on destruction
2. **NPCs respect turn budget** — 1 warp = 1 turn, replenished periodically
3. **Personality drives everything** — two NPCs of same faction behave differently
4. **No inter-NPC trading in MVP** — NPCs trade with ports only
5. **No planet colonization in MVP** — goal type defined, execution deferred
6. **Combat is simple** — one-shot resolution per engagement
7. **Pathfinding is BFS-only** — A* defined but not needed yet

---

## 🧪 TEST CHECKLIST

| Test | Expected |
|------|----------|
| NPCs appear in Sector Interaction Panel | Named cards with faction color + stats |
| SCAN shows detailed ship info | Hull, shields, credits, cargo, equipment |
| ATTACK resolves combat | Damage report, loot popup, player updated |
| Tactical Map dots update | Dots leave/enter sectors as NPCs move (re-paint on tick) |
| GameTickService processes NPCs | Console log: "Tick complete: X processed, Y skipped" |
| NPCs flee from danger | NPC in same sector as player flees if outmatched |
| Turn replenishment | Idle NPCs get +200 turns every 60 ticks |
| CombatService.playerCombat | Player can attack NPC, takes damage, gets loot |

**END OF PLAN** (v3 — Post Phase 4 UI Integration)
