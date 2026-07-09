# Port Attacking Plan (Capture & Destroy)

## Key Rules

- **Capture threshold**: Port shields drop below 5% → port surrenders, stops fighting
- **Destroy**: After surrender, one extra free volley destroys the port (no fight-back)
- **Shield regen**: Between encounters only (not during active combat)
- **Safe zones**: Sectors 1-10 are protected — neither players nor NPCs can attack ports there
- **Notoriety**: Global 0-100 score for both players and NPCs

---

## 1. Port Defense Configuration — NEW FILE

`lib/data/models/port_defense_config.dart`

Configurable defense stats per level. Keeps balancing data separate from logic.

Per-level stats (0-4):
- Level 0: shields 500, firepower 30, ability none
- Level 1: shields 1000, firepower 60, ability none
- Level 2: shields 2000, firepower 120, ability counterAttack
- Level 3: shields 3500, firepower 200, ability shieldRegen (5%/round between encounters)
- Level 4: shields 6000, firepower 300, ability allAbilities (counterAttack + shieldRegen + empBurst)

Single source of truth for balancing. Change numbers here, everything else follows.

PortDefenseStats class with shieldCapacity, firepower, specialAbility, shieldRegenPct, empDrainPct.

PortSpecialAbility enum: none, counterAttack, shieldRegen, empBurst, allAbilities.

PortDefenseConfig static class with _defaults map and defenseStats(int level) helper.

---

## 2. Port Model Updates — EDIT

`lib/data/models/port.dart`

New fields:
- int currentShields (init = max from config)
- bool isUnderAttack
- bool isDestroyed
- String? attackerId
- String? attackMode ("capture" or "destroy")

Derived getters:
- maxShields → PortDefenseConfig.defenseStats(defenseLevel).shieldCapacity
- captureThreshold → maxShields * 0.05 (5% threshold)
- canSurrender → currentShields <= captureThreshold && isUnderAttack
- canDefend → currentShields > captureThreshold && !isDestroyed

On port victory (attacker defeated/retreats): currentShields restores to maxShields, isUnderAttack = false.

Update copyWith, toJson, fromJson for new fields.

---

## 3. Port Combat Service — NEW FILE

`lib/services/npc_ai/port_combat_service.dart`

PortCombatResult class:
- bool portSurrendered, portDestroyed, attackerDefeated
- int damageToPort, damageToAttacker
- Port updatedPort
- Player? updatedPlayer
- NpcShip? updatedNpc

Core methods:
- resolvePortAttack(Player attacker, Port port, String mode) → PortCombatResult
- resolveNpcPortAttack(NpcShip npc, Port port, String mode) → PortCombatResult
- canPortDefend(Port port)
- applyPortDamage(Port port, int damage) → Port
- applyPortCounterAttack(Port port, Player attacker) → Player
- applyNpcPortCounterAttack(Port port, NpcShip attacker) → NpcShip
- applySpecialAbility(Port port, Player attacker) → {Player updated, int bonusDamage}
- calculatePortFirepower(Port port) → int
- determineOutcome(Port port, bool attackerAlive) → "continue" | "surrender" | "destroyed" | "attackerDefeated"
- destroyPort(Port port) → Port
- capturePort(Port port, String newOwnerId, String? newOwnerFaction) → Port

Combat flow per round:
1. Attacker fires → damage from attacker firepower
2. Damage applied to port.currentShields
3. Check port special abilities (EMP burst drains attacker shields at level 4, counter-attack at level 2+)
4. If port.canDefend (shields > captureThreshold): Port fires back → damage to attacker shields, then hull
5. Check outcome: continue, surrender, attackerDefeated

Surrender flow: Port shields < 5% → port stops firing → offer capture/destroy choice
Destroy flow: One free final volley after surrender → port.isDestroyed = true

---

## 4. Notoriety System — EDIT

Player model (lib/data/models/player.dart):
- New field: double notoriety (0.0 to 100.0)
- Update constructor, copyWith, toJson, fromJson

NPC Ship model (lib/data/models/npc_ship.dart):
- New field: double notoriety (0.0 to 100.0)
- Update constructor, copyWith, toJson, fromJson

Notoriety changes:
- Attack any port: +5
- Capture a port: +10
- Destroy a port: +20
- Attack opposing faction port: +15
- Repel NPC port attack: -2

Notoriety thresholds:
- 0-25: No effect
- 25-50: NPCs slightly more aggressive
- 50-75: NPCs actively hunt, more distress responses
- 75-100: NPCs swarm, port owners prepare defenses

NotorietyX extension with isLow, isMedium, isHigh, isExtreme, and color getter.

---

## 5. Port Combat Screen — NEW FILE

`lib/widgets/port_combat_screen.dart`

Turn-based UI, patterned after CombatScreen (~1000 lines).

Layout:
- Top: Port name, defense level, shields progress bar, ability indicators
- Center: Combat visualization (port turrets firing, ship taking hits)
- Bottom: Player actions (fire all weapons, send drones, flee)
- Side: Combat log (round-by-round text)

State class with _player, _port, _combatLog, _combatOver, _portSurrendered, _animating, _currentRound.
Animation controllers same pattern as CombatScreen.

Surrender dialog: When port shields < 5%, show AlertDialog with Capture Port and Destroy Port buttons.

Capture flow: Call PortCombatService.capturePort, +10 notoriety, log message, end combat.

Destroy flow: Call PortCombatService.destroyPort, +20 notoriety, show destroy animation (free final volley), end combat.

Flee flow: Port shields fully restore, log message, navigate back to sector view.

Combat round: Fire weapons, call resolvePortAttack, update player/port, log results, check surrender/defeat.

---

## 6. Port Screen Attack Entry Point — EDIT

`lib/screens/port_screen.dart`

Attack button in port header area. Visible when:
- Port not owned by player
- Sector ID > 10 (not safe zone)
- Player not in combat

Safe zone indicator: Chip with "Safe Zone" text for sectors 1-10.

Attack mode dialog: Modal bottom sheet with port defense info, warning text, Capture and Destroy buttons.

Initiate attack:
- Update port state (isUnderAttack, attackerId, attackMode, currentShields = maxShields)
- Update sector/port in universe storage
- Log action in ActionLogProvider
- +5 notoriety for initiating attack
- Navigate to PortCombatScreen

---

## 7. NPC AI Integration — EDIT

`lib/services/npc_ai/npc_ai_service.dart`

Safe zone enforcement: Add _isSafeZone(int sectorId) helper. Check in all NPC attack goals. If safe zone, skip attack.

Replace instant plunder with combat:
- Check safe zone
- Check if NPC can attempt attack (existing canRaidPort check)
- Choose mode based on NPC state (capture if credits low, destroy if aggressive)
- Run port combat round via PortCombatService.resolveNpcPortAttack
- On surrender: capture (NPC becomes owner) or destroy (port removed)
- On defeat: NPC destroyed
- Update NPC notoriety

---

## 8. NPC Owner Defense Response

When port attack starts, check for NPC owner.

If port.owner != null:
- Look up NPC owner by name
- If owner.aggression > 0.5: Owner joins defense, fires at attacker alongside port each round
- If owner.aggression <= 0.5: Owner flees to adjacent sector

Owner has own shields/hull (can be defeated independently during port combat).

---

## 9. Port Destruction Handling — EDIT

`lib/data/storage/universe_storage.dart`

When port.isDestroyed:
- sector.port = null
- sector.hasPort = false
- NPC owner removed or relocated
- Action log entry: "Port [name] in Sector [id] has been destroyed!"
- Save universe

---

## 10. Notoriety Display — EDIT

`lib/screens/ship_status.dart`

Add notoriety row to ship status card:
- Text: "Notoriety: [value]/100" with color-coded text
- LinearProgressIndicator showing notoriety level
- Color: green (0-25), yellow (25-50), orange (50-75), red (75-100)

---

## File Summary

| File | Action | Role |
|------|--------|------|
| lib/data/models/port_defense_config.dart | NEW | Defense stats per level, PortDefenseStats class, PortSpecialAbility enum |
| lib/data/models/port.dart | EDIT | Combat state fields, derived getters, copyWith/toJson/fromJson updates |
| lib/data/models/player.dart | EDIT | Notoriety field, constructor/copyWith/toJson/fromJson updates |
| lib/data/models/npc_ship.dart | EDIT | Notoriety field, constructor/copyWith/toJson/fromJson updates |
| lib/services/npc_ai/port_combat_service.dart | NEW | PortCombatResult class, combat resolution, special abilities, capture/destroy handling |
| lib/services/npc_ai/npc_ai_service.dart | EDIT | Replace instant plunder with combat, safe zone enforcement, NPC notoriety |
| lib/widgets/port_combat_screen.dart | NEW | Full turn-based port combat UI, surrender dialog, capture/destroy flows, flee handling |
| lib/screens/port_screen.dart | EDIT | Attack button, attack mode dialog, safe zone indicator, initiate attack navigation |
| lib/screens/ship_status.dart | EDIT | Notoriety display row with color-coded progress bar |
| lib/data/storage/universe_storage.dart | EDIT | Port destruction save handling |

---

## Implementation Order

1. Port defense config + Port model updates (foundation)
2. Port combat service (core logic)
3. Notoriety on Player + NPC (reputation tracking)
4. Port combat screen (player-facing UI)
5. Port screen attack entry point (attack button + dialog + navigation)
6. NPC AI integration + safe zone enforcement (NPC port attacks)
7. NPC owner defense response (owner joins or flees)
8. Port destruction handling (save/destroy persistence)
9. Notoriety display on ship status (UI for reputation)

---

## Notes

- Port shields initialize to maxShields (from defense config) when a port is first loaded
- Shield regen between encounters only — no regen during active combat rounds
- Safe zones (sectors 1-10) apply to both players and NPCs
- The surrender dialog gives the player a clear choice: capture (ownership transfer) or destroy (one free volley)
- NPC owner defense adds tactical depth — aggressive owners make ports harder to attack
- Notoriety is clamped to 0-100 and persists across sessions via existing storage
- All defense stats are configurable in port_defense_config.dart for easy balancing
