# Hack Port Mini-Game Update

## Goal

Make the existing **Hack Port** mini-game feel more tense, visual, and replayable while preserving its current Mastermind-style code-breaking core.

The game should feel like the player is actively breaking into a living computer system, not simply guessing three digits in a dialog.

---

## Current State

The current `HackingWidget` includes:

- A 3-digit security code
- Five code guesses per hacking session
- Three failed hacking sessions per port before the 24-hour ban
- Exact digit locking after correct guesses
- A guess history and animated terminal log
- Number pad with delete and submit controls
- Keyboard input: number keys, numpad, Backspace/Delete, and Enter
- A blinking cursor that defaults to slot 1 and advances automatically
- Attempt counter and live security trace meter
- Cyberpunk color scheme
- Scanline overlay
- Narrow and wide layouts
- Animated digit slots and success/failure transitions
- Credit/cargo reward selection
- Escalating failure penalties
- Reward previews that match the actual reward
- Animated packet-sniffer style terminal traffic
- Separate visible attempt history in the status panel
- Conservative, aggressive, and resource extraction choices after a successful hack
- Port security profiles that increase trace pressure on hardened ports
- Persistent 30-minute sabotage that halves starting port combat shields
- Persistent successful-hack record with a capped credit bonus for experienced hackers
- Persistent per-port hack failure counts and 24-hour ban timestamps
- Persistent faction standing changes for successful hacks and sabotage
- Successful hacks add notoriety; sabotage adds more notoriety

## Review TODO

### Resolved cleanup items

- [x] Keep per-session guesses separate from per-port failed-session bans
- [x] Keep reward previews and actual rewards synchronized
- [x] Stop packet capture and animation controllers on disposal/game over
- [x] Make the Codex dialog safe inside intrinsic-width dialog layouts
- [x] Preserve hack history, reputation, and ban state across sessions
- [x] Add keyboard input and non-scrolling attempt history

### Deferred visual polish / feature discussion

- [ ] Add richer port-network node animation
- [ ] Add optional hacking sound effects
- [ ] Add faction-specific breach dialogue
- [ ] Add a breach progress sequence between stages
- [ ] Add a more complete multi-stage code format with variable code length
- [ ] Add mission/quest-specific reputation outcomes

Phase 1 is complete, Phase 2 is complete, and Phase 3 is now focused on strategic gameplay.

---

# Proposed Features

## 1. Live Security Trace Meter

Add a trace meter showing how close the port security system is to detecting the intrusion.

Example:

```text
SECURITY TRACE
[████████░░] 78%
WARN: COUNTER-INTRUSION PROCESS ACTIVE
```

### Suggested behavior

- Start at 0% or a small value based on port difficulty.
- Increase after every incorrect submission.
- Increase faster on later attempts.
- Change color from cyan to amber to red as the trace rises.
- Add warnings to the terminal log.
- Trigger a short screen shake or visual glitch when the trace increases.
- At the final attempt, use a strong red alert state.

The trace should provide atmosphere and urgency, but should not make the reward selection unexpectedly unfair.

---

## 2. Animated Terminal Events

Enhance the terminal log with system messages that appear over time instead of showing only guessed digits.

Example messages:

```text
> Establishing uplink...
> Bypassing local firewall...
> Injecting false authentication packet...
> Probing port node [2/3]...
> WARNING: Counter-intrusion process detected.
```

### Suggested events

- Initial connection message
- Before each hack attempt
- Correct digit lock message
- Incorrect attempt warning
- Trace escalation warning
- Final breach or lockdown message

Messages should use a blinking cursor and appear with a short animation delay.

---

## 3. Port-Specific Hacking Themes

The visual style and terminal language should vary based on the port being hacked.

### Federal port

- Clean military terminal
- Cyan and red security colors
- Formal warnings
- Grid/reticle visual elements
- Lockdown language

### Independent port

- Green monochrome terminal
- More informal messages
- Warning signs and unstable display effects
- Generic commercial security language

### Free port

- Corrupted text and visual glitches
- Scrambled status messages
- More frequent scanline distortion
- Unreliable-looking diagnostics

### Pirate-controlled port

- Red/black palette
- Pirate-themed symbols
- Aggressive warning language
- More dramatic intrusion alerts

### Hardware emporium

- Circuit-board-inspired background
- Component/node terminology
- Cyan and amber accents
- Messages related to firmware, hardware nodes, and system components

The current game already exposes port metadata such as port class and ownership, so this can eventually be driven from the `Port` model.

---

## 4. Improved Digit Feedback

Make each guess and locked digit more expressive.

### Correct digit

- Green pulse
- Lock animation
- Small `LOCKED` label
- Glow around the digit slot

### Incorrect digit

- Short red flicker
- Temporary shake or scanline distortion
- Clear terminal warning

### Near-correct position

Use an amber state to indicate that a digit exists in the code but is in the wrong position, if the game rules are expanded to support this feedback.

### Active slot

- Animated cyan scan line
- Pulsing border
- Visible cursor position

### Successful breach

- Sequential lock animation across all digits
- Brief screen-wide green flash
- Port network access animation

---

## 5. Port-Network Visual

Add a small animated diagram representing the port's security system.

Possible elements:

- Three or four security nodes
- Connections between nodes
- Packets moving along connections
- Firewall barriers
- A red trace line chasing the player's connection
- Node states such as `LOCKED`, `BYPASSED`, and `EXPOSED`

This can be implemented with a custom painter and a repeating animation controller. It should be decorative and readable rather than replacing the digit puzzle.

---

## 6. Animated Breach Phase

After the player discovers the correct code, add a short breach sequence before rewards are offered.

Example:

```text
CODE ACCEPTED
ESTABLISHING ROOT ACCESS...

[████████████████] 100%
```

Possible stages:

1. Authentication accepted
2. Firewall opened
3. Port node reached
4. Root access established
5. Reward selection enabled

The sequence should be short, visually satisfying, and skippable after the first play to avoid repetitive waiting.

---

## 7. Extraction and Risk Choices

Allow the player to choose how aggressively to extract data after gaining access.

### Conservative extraction

- Lower reward
- Lower trace risk
- Safer result

### Aggressive extraction

- Higher reward
- Trace continues advancing
- Higher risk of failure

### Sabotage

- Grants a temporary or immediate gameplay advantage
- Highest risk
- Should be limited by port ownership or port state

Example:

```text
EXTRACTION MODE

[CONSERVATIVE] 500–1,000 credits
[AGGRESSIVE]   1,500–3,000 credits
[SABOTAGE]     Temporary port disadvantage
```

This adds a strategic decision after the code puzzle rather than making the reward purely random.

---

## 8. Audio and Haptic Feedback

The existing audio service could provide short hacking sound effects:

- Keypress click
- Digit lock confirmation
- Incorrect-entry static
- Warning beep
- Trace escalation alarm
- Firewall bypass sound
- Access granted chord
- Lockdown failure alarm

Use short synthesized or bundled effects where possible. Avoid constant loud alarms, especially in a game that may be played for long periods.

---

# Visual and Interaction Plan

## Wide layout

- Left panel: scrolling terminal log
- Center panel:
  - Header
  - Security trace meter
  - Attempt counter
  - Current code slots
  - Animated port-network visual
  - Number pad and submit control
- Right panel:
  - Port identity
  - Trace status
  - Locked digits
  - Security type
  - Current connection state

## Narrow layout

The existing narrow layout should remain compact and scroll-safe:

- Header
- Trace meter
- Attempt counter
- Current code
- Short recent log
- Number pad
- Submit/cancel controls

On small panels, the port-network visual should be hidden or reduced to a compact status bar.

---

# Implementation Phases

## Phase 1: Polish and Feedback — Complete

Low-risk improvements:

- Fixed reward preview/randomness consistency.
- Initialized the per-session code-attempt count from `maxAttempts`.
- Kept the separate per-port failure limit for the 24-hour ban.
- Added attempt lock and result animations.
- Added terminal messages and a live security trace meter.
- Added color changes based on remaining attempts.
- Added keyboard input and a blinking slot cursor.
- Added success/failure visual transitions.

## Phase 2: Atmosphere — Complete

- Improved the scanline/grid painter.
- Added moving data packets.
- Added packet-sniffer style terminal traffic with timestamps, protocols, endpoints, flags, and byte counts.
- Added player input packets in a distinct brighter shade within the network feed.
- Kept submitted code attempts in a separate, visible attempt-history panel.
- Added screen shake and glitch effects.
- Added port-specific colors and terminal language.
- Kept the existing accessibility and narrow-panel behavior intact.

## Phase 3: Strategic Gameplay — Complete

- Add conservative/aggressive extraction.
- Add temporary sabotage outcomes.
- Add port security difficulty profiles.
- Add multi-stage codes for hardened ports.
- Add persistent codex/history views.

The first Phase 3 slice adds four extraction choices after a successful hack:

- Conservative credits: 750–1,250 credits guaranteed
- Aggressive credits: 2,000–4,000 credits when the security trace is low, reduced when the trace is high
- Resources: 10 units of cargo
- Port security profiles influence trace pressure and are shown in the terminal
- Sabotage grants 15 research points and temporarily halves the port's starting combat shields for 30 minutes

The replay record and codex are also implemented:

- Successful hacks increment a persistent `successfulHacks` player record.
- Each prior successful hack adds 25 credits to credit extraction rewards.
- The replay bonus caps at 500 credits.
- The record is shown on the extraction screen when a bonus is active.
- Successfully hacked port names and the last breach timestamp are persisted.
- The port screen includes a Hack Codex dialog for viewing the history.

Hardened ports now use a two-stage hack: cracking the first code advances to a fresh secondary code with a new five-guess attempt counter.

## Phase 4: Port Integration — Complete

- Faction standing and notoriety changes are connected to hacking, combat, trade, planet, and NPC interactions.
- Successful trades, NPC scans/trades, and planet scans improve standing with the relevant faction.
- Hostile actions such as sabotage, combat victories, port capture/destruction, and claiming occupied planets reduce standing.
- The Ship view displays notoriety and faction-standing meters for all four factions.
- The Hack Codex persists successful port history, timestamps, security profiles, extraction rewards, and faction standing.
- Temporary sabotage and per-port hack bans persist across sessions.
- The core reputation system is ready to be extended by future missions and quest actions.

---

# Suggested Difficulty Scaling

| Port Security | Code Length | Attempts | Trace | Possible Rewards |
|---|---:|---:|---|---|
| Low | 3 digits | 5 | Slow | Credits/cargo |
| Standard | 3 digits | 4 | Normal | Credits/cargo/data |
| High | 4 digits | 4 | Fast | Better data/scrap |
| Military | 4 digits | 3 | Aggressive | High-value rewards |
| Hardware Core | Variable | 3 | Aggressive | Hardware/ship upgrades |

The first implementation should keep the existing 3-digit/5-attempt format to avoid disrupting the current game economy.

---

# Acceptance Criteria

The update is successful when:

- The core 3-digit puzzle remains understandable.
- Incorrect guesses produce clear visual and terminal feedback.
- The trace meter creates meaningful tension.
- The interface adapts to both narrow and wide panels.
- The success flow feels more rewarding than the current static overlay.
- Port identity is reflected in the hacking presentation.
- No random reward is shown that differs from the reward actually granted.
- Audio and animation can be disabled or reduced for accessibility.
- The game remains usable with keyboard input and reduced motion settings.
- Existing hacking economy and penalty behavior remain balanced.

---

# First Implementation Target

Phase 3 now builds on the completed Phase 2 foundation:

1. Offer conservative, aggressive, and resource extraction choices after a successful hack. — Complete
2. Make aggressive extraction depend on the final security trace. — Complete
3. Add temporary sabotage outcomes. — Complete
4. Add port security difficulty profiles. — Complete
5. Add multi-stage codes and replay-specific rewards/codex entries. — Complete
