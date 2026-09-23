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

Phase 1 is complete. Phase 2 is now focused on atmosphere and feedback.

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

## Phase 2: Atmosphere — In Progress

- Improve the scanline/grid painter.
- Add moving data packets.
- Add packet-sniffer style terminal traffic with timestamps, protocols, endpoints, flags, and byte counts.
- Show player input packets in a distinct brighter shade within the network feed.
- Keep submitted code attempts in a separate, visible attempt-history panel so they do not scroll out of the network feed.
- Add port-specific colors and terminal language.
- Add optional audio feedback hooks.
- Keep the existing accessibility and narrow-panel behavior intact.

## Phase 3: Strategic Gameplay

- Add conservative/aggressive extraction.
- Add temporary sabotage outcomes.
- Add port security difficulty profiles.
- Add additional codes or multi-stage hacks for high-security ports.
- Add replay-specific rewards or codex entries.

## Phase 4: Port Integration

- Pass the current `Port` into the hacking widget.
- Use port class, owner, defense level, and hardware status for theming.
- Add reputation or faction consequences.
- Persist temporary hack results if they affect future port actions.
- Display recent hack history in the port screen.

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

Phase 2 will build on the completed Phase 1 foundation:

1. Expand the scanline painter into a subtle animated grid and packet layer.
2. Add restrained screen shake/glitch feedback after incorrect submissions.
3. Pass the current port into the hacking widget and derive colors and terminal language from its class/ownership.
4. Keep the visual effects decorative and readable.
5. Add audio feedback only where a safe platform-supported hook is available.
