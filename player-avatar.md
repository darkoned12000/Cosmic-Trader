# Player Avatar System — Design & Implementation Plan

**Status:** Draft for review
**Scope:** Give each pilot a visual identity selected during account creation, persist it on the
`Player`, and show it on the Ship Status screen. Start with a polished gallery of finished faction
portraits; keep deeper customization and user-uploaded images optional.
**Related docs:** `planets.md` (same doc-driven pattern), `AGENTS.md` (architecture, commands,
A2 shared widgets, A3 faction color language)

---

## 1. Goal

Today an account is just a username, faction, and ship. There is **no visual identity** for the
pilot. This plan adds:

1. An **avatar** — a portrait representing the player's pilot.
2. A portrait gallery for each playable faction (**Duran**, **Vinari**, **Trader**) with male and
   female presentation options. Treat these as visual presentation styles; species biology and
   gender are not otherwise defined by the existing lore.
3. A quick selector during account creation, with a good default and optional deeper customization
   or image upload (and later editing).
4. The avatar rendered **prominently on the Ship Status screen**.

Design constraint driving most decisions below: **the repo currently ships zero character art.**
Only 3 faction banner SVGs and 27 planet GIFs exist. Portrait assets therefore need to be created,
commissioned, or licensed; drawing plausible, polished character art procedurally is not a free
substitute for an art pipeline.

---

## 2. Current state (verified in code)

### Registration flow — `lib/screens/register_screen.dart` (624 lines)

Three hard-coded steps, `_step` ∈ {0,1,2}:

| Step | Builder | Notes |
|------|---------|-------|
| 0 | `_buildCredentialsStep()` | username, password + strength meter, confirm |
| 1 | `_buildFactionStep()` | RadioGroup over `FactionClass.values.where((f) => f != FactionClass.pirate)` → **exactly 3 factions** |
| 2 | `_buildShipStep()` | ship picker, milestone locking, LAUNCH button |

**Recommendation: do not add a mandatory fourth step for v1.** Fold a quick portrait choice into
the identity/faction stage; show a default immediately and let players continue without opening a
customizer. If customization grows into a substantial editor, open it as an optional sub-screen.
If a separate step is ultimately preferred, replace the numeric step literals with a named step
enum/list and test the complete back/continue flow rather than only incrementing the indicator.

**Registration integration points:**

- The step indicator loops `for (int i = 0; i < 3; i++)` (line 138), and navigation is hard-coded.
  Keep the existing three-step flow if avatar choice is embedded into the faction step.
- Changing faction resets the ship (`_selectedShip = ShipDefinition.getDefaultInterceptor(value).name`,
  line 333); it must also update the available portraits and select a valid faction default.
- `_register()` (104-133) calls `PlayerStorage.instance.register(username, password, faction:, shipName:)` then pushes `GameShell`. No avatar parameter exists yet.

### Faction/species lore — `lib/data/models/faction.dart`

Each faction already carries an `appearance` string we can honour rather than inventing new art direction:

| Faction | `displayName` | `appearance` (authoritative source) |
|---|---|---|
| `duran` | Duran Hegemony | *"Scaly, insectoid warriors with glowing red eyes, clad in battle-armor"* |
| `vinari` | Vinari Collective | *"Glowing, fluid forms with shifting colors, like living auroras"* |
| `trader` | Independent Traders Guild | *"Diverse Terrans in practical jumpsuits or merchant finery"* |

`pirate` exists in the enum but **is excluded from registration** (also excluded from
`Faction.allFactions()`), so it gets no species in v1 — see §11 for a later reuse.

### Persistence — `lib/data/models/player.dart` (538 lines)

Immutable `Player` with `copyWith` (~50 named params), `toJson`, `fromJson` using tolerant
`as String? ?? default` patterns. Adding a field requires **five** coordinated edits: field
declaration, constructor param, `copyWith` param, `toJson` entry, `fromJson` entry. Existing
`nullable-specific migration` precedent exists (legacy `turns` keys, `Sector.planetType`).

`PlayerStorage.register()` (lines 72-136) builds the `Player` literal and calls `savePlayers`.
> Coupling note: `register()` currently mints ids as
> `DateTime.now().millisecondsSinceEpoch.toString()` (line 101). The earlier storage review
> flagged same-millisecond collisions as M4 and recommended `Uuid().v4()` (`uuid` is already a
> dependency). This plan depends on a stable unique id for avatar seeding — see §6.3.

### Ship Status — `lib/screens/ship_status.dart` (1183 lines)

- `_shipHeaderCard()` (336-383) describes the vessel and uses a rocket icon. Keep that ship cue;
  replacing it with a face weakens the meaning of this header.
- `_playerInfoCard()` (385-413): `PanelCard(icon: Icons.person_rounded, title: 'Player Info')` with
  `_detailRow`s (Username, Ship Name, Ship Class, Credits, Energy, Scrap Metal, Scrap Tech), a
  divider, and a `ListTile` for **Change Password**. This is the natural place for a matching
  portrait beside the username and a **Change Appearance** row.
- Layout: `_buildContent` (272-309) uses `_shipHeaderCard` then either a single column or
  `_buildTwoColumnGrid` (311-334), whose `SliverGridDelegateWithFixedCrossAxisCount` pins
  `mainAxisExtent: 440`. Any new *card* must fit that fixed cell height (or be added to the
  header, which is not height-constrained).

### Shared conventions to follow

- `PanelCard`, `StatBar`, `HudPill`, `DataTableShell` in `lib/widgets/shared/` (A2), density-aware
  via `UiScale.spacing()` (`lib/core/ui_scale.dart:66`).
- **Single source of truth for faction colors:** `factionColor(FactionClass)` +
  `FactionPalette` in `lib/core/faction_colors.dart`. Avatars must derive accents from here, never
  from local literals.
- `flutter_svg` is available (`SvgPicture.asset` used in `knowledge_base_screen.dart:125`).
- Portrait assets will require a `pubspec.yaml` asset-directory entry. Prefer a predictable asset
  naming convention and inventory test so a missing portrait fails visibly during development.

---

## 3. Decision: gallery first, designer as an optional layer

### Option A — Curated portrait gallery ✅ **recommended for v1**

Show finished, consistent portraits. Start with a small but meaningful set for each playable
faction and presentation (for example, 3 portraits × 3 factions × 2 presentations = 18 images).
Use art created for the game or assets with clear redistribution rights. Players get a good-looking
result quickly; they can choose a portrait without understanding a list of technical options.

This is more than the initial six portraits: a single male/female portrait per faction technically
meets the matrix but offers little personal choice. Build a naming/inventory check and keep each
set visually cohesive in framing, lighting, and scale.

### Option B — Layered portrait designer (recommended follow-on)

Let players combine **artist-authored, compatible layers**—for example, base portrait, species
features, hair/crest, clothing, accessory, and background. The designer is a composition tool, not
a free-form drawing canvas. Only expose combinations that have been authored and checked to fit.
This can provide real choice while preserving visual quality, but requires a planned art pack and
compatibility rules.

### Option C — Procedural `CustomPainter` (prototype/fallback, not the v1 quality bet)

A deterministic painter can make simple faction-themed icons or stylized busts without image
assets. It is useful for prototyping, default placeholders, or small effects such as faction glows
and frames. It is **not automatically polished character art**: facial anatomy, distinct species
silhouettes, attractive combinations, and readable details at small sizes still require design and
visual iteration. Do not choose it solely to avoid an art pipeline.

### Option D — Player-uploaded image (optional source)

Uploads are independent of the gallery and designer. They should be optional, previewed and
cropped/validated before saving, and must not block account creation. Platform storage and account
portability are separate concerns (§7).

**Recommendation:** ship the curated gallery first, with a clean model/widget boundary that can
later support layered choices and uploads. Use a painter only for supporting visuals or a temporary
fallback. Do not build a large integer-driven procedural designer before validating its art quality
with an in-app prototype.

---

## 4. Data model — `lib/data/models/avatar_selection.dart`

Persist **stable asset IDs**, not list positions or user-visible labels. Reordering a gallery must
not change a player's saved portrait. Use a versioned, compact JSON payload (negligible in
`players.json`). If a saved ID is removed in a future release, resolve it to the faction's default.

```dart
enum AvatarSpecies { duran, vinari, terran }        // one per playable faction
enum AvatarPresentation { male, female, neutral }   // visual style, not biological lore
enum AvatarSource { preset, custom }                // add layered with that feature's schema change

@immutable
class AvatarSelection {
  final int schemaVersion;
  final AvatarSpecies species;              // derived from player's faction
  final AvatarPresentation presentation;    // displayed as Male / Female / Neutral
  final String portraitId;                  // stable key, e.g. duran_male_scout_01
  final AvatarSource source;                // preset or custom
  final String? customFile;                 // bare filename under avatars/, never an absolute path

  Map<String, dynamic> toJson();
  factory AvatarSelection.fromJson(Map<String, dynamic> json); // tolerant, version-aware
  factory AvatarSelection.defaultFor(FactionClass faction);
  AvatarSelection forFaction(FactionClass faction); // validates species/portrait against faction
  AvatarSelection copyWith(...);
}
```

Required behaviour:
- `fromJson` **never throws**: unknown/legacy/missing keys → a valid faction default.
- `==`/`hashCode` implemented (needed for `setState` diffing and tests).
- Round-trip invariant: `AvatarSelection.fromJson(selection.toJson()) == selection`.
- Unknown enum names and removed portrait IDs resolve to a faction default rather than crashing a
  login or displaying a missing-asset box.
- `customFile` is consulted only when `source == custom`; the selected preset ID remains available
  as a fallback if the custom file is lost.
- Keep the registry of portrait IDs and faction/presentation metadata in one place; avoid index
  values whose meaning changes when a list is reordered.

Existing accounts with no saved selection should receive the faction's curated default. If a
deterministic variety is desired, select from that faction's gallery using a stable hash of
`player.id`; do not rely on `String.hashCode`, which is not a persistence contract. New players
should see and be able to change their actual selection before account creation completes.

### Future layer catalogue (only if the layered designer is approved)

| Layer | Duran (insectoid) | Vinari (luminous) | Terran (human) |
|---|---|---|---|
| tones | obsidian, rust, bone-chitin, jade-shell | aurora violet, cyan, pearl, ember | 5 skin tones + neutral base |
| features | mandible plates, brow ridge, horn pair | tendril fall, bioluminescent frill | brow/beard variations |
| crests | war-crest, horn arcs, plate ridge | lumen halo, drifting filaments | short crop, long hair, undercut, braid |
| eyes | glowing red slit | luminous pupil, no sclera | visor reflection / standard |
| headgear | battle-helm, jaw guard (none option) | psi-crown, veil (none option) | cap, hooded coat collar, none |
| backdrop | forge glow | nebula | hangar / starfield |

Treat male/female/neutral as visual presentation styles. Species-specific silhouettes and
presentation should be art-directed with references and reviewed at thumbnail size; avoid assuming
that a palette swap alone makes a distinct portrait. The first gallery should prove the visual
direction before this layer catalogue is expanded.

---

## 5. Rendering and selection — `lib/widgets/avatar/`

### `avatar_catalog.dart`

Single source of truth mapping stable `portraitId`s to faction, presentation, asset path, preview
metadata, and default status. The gallery builds from this catalogue; `AvatarSelection` stores the
stable id. Add a test that every catalogue asset exists and every selectable faction/presentation
has at least one portrait.

### `avatar_canvas.dart`

`AvatarCanvas(selection, size: 96)` resolves a preset asset or custom file, clips it consistently,
and supplies an accessible semantic label. Its API hides whether the selection is a preset or
custom upload; screens do not branch on source. Missing/removed preset assets resolve to the
faction default. Missing custom files resolve to the saved preset fallback (§7.5).

Use `cacheWidth`/`cacheHeight` appropriate to the display size where supported, since a 512px
source portrait may appear as a 48px thumbnail in future NPC/comms lists.

### `avatar_gallery.dart`

Reusable selector for account creation and later editing:
- Show portraits as tappable cards with a **large live preview**, clear selected state, and faction
  accent from `factionColor()`.
- Filter/organize by selected faction and presentation; show a short flavour line from
  `Faction.forClass(fc).appearance`.
- Provide a **Random pick** action that chooses a catalogue entry, not an unconstrained painter
  combination.
- Keep optional controls such as upload and later customization secondary to the gallery.
- Every option has a text label/semantics; users must not have to distinguish portraits by color.

### Optional `avatar_designer.dart` (follow-on)

If visual prototyping supports a designer, make it a **layered composition UI** over authored
assets. Expose only compatible options; use stable layer IDs in the saved schema. Keep a persistent
preview and provide reset/undo. Do not expose dozens of numeric palette/feature fields before the
art set exists. A `CustomPainter` may draw simple frames, glows, or backgrounds, but is not the
assumed source of finished character artwork.

### `../screens/avatar_editor_screen.dart`

A `Scaffold` + Save/Cancel wrapper around the gallery (and the optional designer/upload actions),
reachable later from Player Info. Draft changes are not written to the player until Save.

---

## 6. Integration

### 6.1 Registration: keep three stages, make avatar choice quick and optional

| Step | Builder | Content |
|---|---|---|
| 0 | `_buildCredentialsStep()` | unchanged |
| 1 | `_buildFactionStep()` + portrait gallery | faction selection and a matching portrait preview/gallery |
| 2 | `_buildShipStep()` | unchanged; ship selection and LAUNCH |

Implementation notes:
- Keep the faction step's selection and portrait gallery understandable on narrow layouts; use a
  compact grid/list with one prominent preview rather than forcing a separate full-screen editor.
- Selecting a faction updates the available portraits and selects a valid faction default, alongside
  the existing default-ship reset (line 333).
- Make the choice skippable: a recommended portrait is preselected, and Continue works without
  opening customization or upload.
- The step indicator remains three stages. If the gallery grows enough to justify a dedicated step,
  revisit that based on playtesting and replace numeric step literals with named steps.
- `_register()` passes the selected `AvatarSelection` and any pending upload draft to the account
  creation/storage flow.

### 6.2 `Player` and `PlayerStorage`

Five coordinated `player.dart` edits (field, constructor default, `copyWith`, `toJson`,
`fromJson`) following the existing tolerant pattern:

```dart
// fromJson — legacy saves simply fall back to a stable default
avatar: json['avatar'] is Map
    ? AvatarSelection.fromJson((json['avatar'] as Map).cast<String, dynamic>())
    : null,   // resolved to a faction default by a getter/helper
```

Store **`AvatarSelection?` as a nullable field** and expose one consistently named effective getter,
for example `AvatarSelection get effectiveAvatar => avatar?.forFaction(faction) ?? AvatarSelection.defaultFor(faction)`.
This keeps migration inert (no backfill pass over `players.json`) and self-healing. Ensure
`copyWith` can distinguish “leave unchanged” from “clear the custom selection”; use an explicit
clear flag or sentinel if needed, rather than relying only on nullable `??` semantics.
Because the selection carries species metadata while `Player` separately stores faction, the getter
and registration validation must repair mismatches rather than showing a portrait from the wrong
species after a save edit or future faction change.

`PlayerStorage.register(...)` gains an `AvatarSelection` parameter and assigns a valid faction
default when no selection is supplied. Keep upload bytes out of the model and JSON; the storage
workflow receives pending bytes separately (§7.4).

### 6.3 Migration for existing accounts

Old records have no `avatar` key → the nullable getter resolves a valid **faction default portrait**.
No migration script or JSON backfill is needed. A one-time “Choose your pilot portrait” hint may
point to the gallery, but must be dismissible and must not block play. Avoid making a neutral or
androgynous look the unexplained default for existing accounts.

Player IDs are not needed to render a fixed faction default. Independently, the storage review
identified millisecond-timestamp ID collisions that can make accounts unaddressable in
`updatePlayer`; switching new registrations to `Uuid().v4()` is recommended as a contained fix in
the persistence phase, not as an avatar-generation requirement.

### 6.4 Ship Status display

Keep the rocket icon in `_shipHeaderCard()` because it labels the ship-focused header. In
`_playerInfoCard()`, show `AvatarCanvas(widget.player.effectiveAvatar)` adjacent to the username or
as a compact identity row. Use faction color as a restrained border/accent, not as a tint that
obscures the portrait artwork.

`_playerInfoCard()` (385-413): add a **Change Appearance** `ListTile` mirroring the Change Password
row (same `leading` icon size 20, same zero `contentPadding`, same chevron), opening
`AvatarEditorScreen`; return a draft selection on Save and call `onPlayerUpdate` only after any new
custom file has been committed successfully.

> Avoid adding a *new* grid card: `_buildTwoColumnGrid` pins `mainAxisExtent: 440` (line 330), so a
> fresh card would either overflow or force a grid-delegate change.

---

## 7. Optional custom image uploads

Uploads are a useful personal touch, but should be **optional and secondary** to the gallery. The
player should see a preview, crop or confirm it, and be able to cancel back to a preset without
losing their account-creation progress.

### 7.1 Existing support and platform constraints

- `file_picker: ^8.1.7` is already a dependency (`audio_service.dart` uses it), and can provide
  selected bytes with `withData: true`.
- The project targets web as well as native/desktop. `path_provider` currently does not provide the
  same file storage behavior on web; hiding upload on web is a possible **first local-storage
  release constraint**, not a complete cross-platform design. Keep storage behind an interface so a
  future browser-backed implementation (such as IndexedDB) can be added.
- Verify `dart:ui` metadata APIs against the minimum Flutter version the project supports. The
  repository specifies a Dart SDK range but not a Flutter minimum. If using
  `ImageDescriptor.encoded`, dispose **both** the descriptor and its `ImmutableBuffer`.
- `Image.file` is not the web solution. `AvatarCanvas` should resolve platform-specific bytes via
  the image-store interface and render via an appropriate image provider.

### 7.2 Friendly validation and normalization

Prefer accepting common PNG/JPEG images and guiding the player through a square crop/preview over
requiring the player to prepare an exact 128/256/512 image themselves. Put named limits in one
policy module:

| Rule | Initial proposal | UX / implementation note |
|---|---|---|
| Crop | square 1:1 preview | Player chooses crop/position; image remains unchanged until confirmation |
| Output | normalized 256×256 | Keeps display/cache behavior predictable; source can be larger |
| Max input bytes | 5 MB initial cap | Reject before decode; tune from real devices and test assets |
| Formats | PNG and JPEG | Sniff bytes, don't trust extensions or picker filters |
| Animation | reject animated formats | Avoid surprising frame behavior and repeated decode cost |
| Pixel ceiling | set a conservative maximum before decode | Guard memory use; still handle decode errors safely |

The existing 512 KB and exact-size rule may be appropriate for prepared assets but will reject many
normal user images. If normalization is out of scope for the first upload release, allow a range of
square sizes, clearly list the requirements before opening the picker, and explain each rejection.
Avoid accepting a JPEG and saving it under a `.png` filename: either normalize bytes to PNG or
preserve the verified format and extension in the stored reference.

Sniff magic bytes before decoding and enforce byte/pixel limits first. A metadata probe is useful,
but do not assume metadata validation alone makes arbitrary image bytes safe. The decode/normalizer
must catch malformed input and release native image resources in every path. Phone JPEG EXIF
orientation must be honored during normalization or the preview can appear sideways.

### 7.3 Storage and registration lifecycle

The upload is selected **before** the account is registered, so `playerId` does not exist when the
registration gallery is open. Do not try to write `avatars/<playerId>` at pick time.

Recommended lifecycle:

1. Pick, validate, crop/preview, and normalize in a temporary registration draft. Keep bytes in
   memory while the draft is active; the input-size cap makes that bounded. Cancel/dispose releases
   the draft without leaving orphan files.
2. On account creation, generate the player ID first (use `Uuid().v4()` as separately recommended
   in §6.3).
3. Persist the normalized image to `<appDir>/avatars/<playerId>.<verified-extension>` using an
   atomic byte write; ensure the parent directory exists.
4. Save the `Player` with the custom source and **bare filename only**—never an absolute path or
   base64 image in `players.json`.
5. If player persistence fails, delete the newly written avatar and report the registration failure.
   Because current storage methods may swallow save errors, this flow needs a save result/exception
   contract before it can reliably know whether to commit the image.

When editing an existing account, write the replacement image first, save the updated player, and
only then delete the previous custom file. If saving fails, retain the old image/selection. Switching
back to a preset deletes the old file only after the player update succeeds. Account deletion should
remove its avatar file when account deletion is implemented.

Do not store image bytes in `players.json`: it is rewritten wholesale on player updates. Add a
`FileSafe.writeBytes` helper only if it preserves the existing crash-safe temp/rename behavior and
has appropriate directory creation and error reporting.

### 7.4 Upload flow

1. Open picker from an **Upload image…** action; request bytes (`withData: true`) and handle cancel.
2. Reject oversized input before decode; verify supported byte signature and decode safely.
3. Show an interactive square crop/position preview and the final 256×256 preview.
4. Normalize orientation, dimensions, and output format; write only after the player confirms.
5. Store normalized bytes in the in-memory registration draft (registration) or temporary edit
   draft (existing account). Commit to the permanent avatar store only at Save/Launch.
6. Return `AvatarSelection(source: custom, customFile: filename, portraitId: selectedPresetId)` so
   the preset is a valid fallback if the custom file is missing.

### 7.5 Rendering and fallback

`AvatarCanvas` resolves the custom file asynchronously through the store. While loading, show the
selected preset; on missing file, decode error, or unsupported platform, fall back to that preset
without a broken-image icon. If the preset itself is missing, use a faction-neutral placeholder and
log the missing asset in development. Cache decoded images at a display-appropriate size.

### 7.6 UI details

- Upload is optional and never blocks account creation.
- Show the crop, preview, and a clear **Use this image** confirmation before changing the draft.
- Distinct, actionable errors: file too large, unsupported image, unreadable image, invalid
  dimensions, or storage failure. Include actual dimensions where known.
- Show the current source and a **Use selected portrait** action to revert; do not use “generated”
  if the fallback is a curated preset.
- On web, either implement a browser-backed image store or clearly disable uploads for the first
  storage milestone. Do not silently accept an upload that won't survive reload or be available on
  another platform.

## 8. New & modified files

**New — v1 gallery and shared rendering (4)**

| File | Responsibility |
|---|---|
| `lib/data/models/avatar_selection.dart` | Versioned selection model, stable portrait IDs, tolerant JSON |
| `lib/widgets/avatar/avatar_catalog.dart` | Portrait registry, faction/presentation metadata, defaults |
| `lib/widgets/avatar/avatar_canvas.dart` | Preset/custom resolver, clipping, caching, semantics and fallbacks |
| `lib/widgets/avatar/avatar_gallery.dart` | Reusable selection gallery and preview |

**New — optional editor and custom upload (3)**

| File | Responsibility |
|---|---|
| `lib/screens/avatar_editor_screen.dart` | Save/Cancel wrapper for post-creation appearance changes |
| `lib/data/storage/avatar_image_storage.dart` | Platform-aware image store; stage/commit/resolve/delete custom files |
| `lib/widgets/avatar/avatar_image_policy.dart` | Byte, format, pixel, and decode validation rules |

**Optional follow-on — layered designer (only after an art prototype)**

| File | Responsibility |
|---|---|
| `lib/widgets/avatar/avatar_designer.dart` | Compatible art-layer composition controls; uses stable layer IDs |

**Modified (7)**

| File | Change |
|---|---|
| `lib/screens/register_screen.dart` | faction-linked gallery in existing identity stage; optional upload draft; thread selection |
| `lib/data/models/player.dart` | nullable `AvatarSelection` field, `copyWith`, JSON, effective default getter |
| `lib/data/storage/player_storage.dart` | persist selection; create UUID before committing upload; expose save failure |
| `lib/screens/ship_status.dart` | portrait in Player Info; "Change Appearance" row; preserve ship icon |
| `lib/data/storage/file_safe.dart` | add `writeBytes(File, Uint8List)` if required by image-store implementation |
| `pubspec.yaml` | declare portrait asset directory; add image-normalization dependency only if selected |
| `AGENTS.md` | file inventory count, new files table rows, test count |

Optional: test files (§9). `file_picker` is already present; a crop/normalize flow may require
evaluating a small image-processing dependency. Keep it only if its cross-platform behavior and
maintenance cost are justified.

---

## 9. Phases & acceptance criteria

**Phase 1 — Art direction and gallery prototype.** Create/commission a small consistent portrait
set and display it in a test route at the actual sizes used by registration and Ship Status.
✓ Players can distinguish options at thumbnail size; each faction/presentation has enough choices;
assets have approved rights, consistent framing, and default portraits.

**Phase 2 — Selection model and catalog.** Implement `AvatarSelection` and the portrait registry.
✓ Stable IDs survive catalog reordering; removed IDs and malformed/legacy JSON resolve to a valid
faction default; every catalog path exists; round-trip and fallback tests pass.

**Phase 3 — Gallery in registration.** Add the preview/gallery to the existing faction/identity
stage; keep a default selected and allow Continue without customization.
✓ Registration remains three stages; faction changes update valid portraits and reset the ship as
before; selected portrait reaches account creation; narrow and wide layouts are usable.

**Phase 4 — Persistence and Ship Status.** Add `Player` selection persistence and show the portrait
beside player identity in the Player Info card. Add Change Appearance with Save/Cancel.
✓ Existing saves load with a valid faction default; new selection survives relaunch; ship header
retains its ship cue; layout still fits the current 440px grid cells.

**Phase 5 — Optional upload.** Validate/preview/crop/normalize in a bounded draft, then commit the
file and player reference transactionally (§7.3).
✓ Cancelled registration leaves no permanent file; failed save removes a newly committed file;
replacing an image preserves the previous one until successful save; missing file falls back to the
selected preset; filename extension matches normalized bytes; unsupported platforms report that
uploads are unavailable instead of silently losing the image.

**Phase 6 — Optional layered designer.** Proceed only if the prototype art supports coherent layer
combinations. Add compatible layers and stable IDs; use painter effects only for supporting details.
✓ Every offered combination has a valid preview at target sizes; reset/undo work; serialized layer
IDs survive catalog updates.

### Tests

- Unit: `AvatarSelection` JSON round-trip, legacy/malformed values, unknown IDs, equality, faction
  remapping, and catalog completeness for all playable factions/presentations.
- Widget: gallery selection and preview, default/continue flow, faction change, three-stage
  registration navigation, Ship Status identity placement, Change Appearance Save/Cancel.
- Upload policy: supported signatures/formats, malformed bytes, byte/pixel limits, normalized output
  dimensions and format, actionable validation failures.
- Upload lifecycle: in-memory staging and cancellation; create directory; atomic commit; rollback on
  player-save failure; replacement/revert cleanup only after successful save; missing-file fallback.
- Cross-platform: image store contract tests for native files and browser-backed implementation if
  web uploads are included in scope.
- Optional visual goldens for portrait thumbnails. Validate manually on target devices too; goldens
  can be renderer/platform sensitive.

Per `AGENTS.md`, before committing:
```bash
flutter analyze
dart format --set-exit-if-changed lib/ test/
flutter test
```

---

## 10. Risks & open questions

1. **Art quality and scope.** The curated gallery needs a coherent art direction and enough choices
   to feel personal. Validate a small set before commissioning/creating a large pack or building a
   complex designer.
2. **Presentation and species lore.** Keep species tied to faction in v1, but describe male/female
   as visual presentations; decide whether to offer a neutral presentation. Do not infer species
   biology beyond established lore.
3. **Designer combinatorics.** Layered customization requires compatible assets, masks/alignment,
   and a set of tested combinations. Do not expose unconstrained combinations that can produce
   broken or unattractive portraits.
4. **Registration friction.** Portrait selection should have an obvious default and be skippable.
   Keep registration at three stages unless playtesting shows a dedicated editor improves rather
   than delays account creation.
5. **Stable catalog IDs.** Renaming/reordering display options must not change existing selections.
   Use stable IDs and a schema version; unknown/removed values resolve to a faction default.
6. **Upload transaction.** Account ID is unavailable until creation; stage bytes in memory, then
   write after UUID creation. Player JSON currently saves through APIs that may swallow failures;
   dependable rollback requires a success/error contract.
7. **Upload normalization.** Decide whether to add an image package for crop/resize/orientation. If
   not, simplify v1 to a clearly explained square-image acceptance policy; do not claim crop,
   normalization, or EXIF handling that is not implemented.
8. **Format and extension.** If storing original bytes, preserve the validated format and extension;
   if normalizing, ensure the extension matches the normalized format.
9. **Web and portability.** A native path-provider file is local to that installation. If player
   saves move between platforms/devices, custom image files must move too; a browser-backed store or
   package/export support may be needed.
10. **Resource safety.** Enforce input byte and decoded-pixel limits before expensive work; catch
    malformed files and dispose image descriptors/buffers. Verify APIs against the supported
    Flutter version.
11. **Accessibility.** Portrait choices need names/semantic labels and a visible selected state;
    never rely on faction color alone.
12. **Data cleanup and privacy.** Replacing/reverting/deleting an account must clean files. Local
    uploads are not moderated; if portraits are later shared or uploaded to a server, moderation,
    consent, and storage policy become part of the design.

---

## 11. Natural follow-ons (out of scope for v1)

- **NPC portraits** — reuse `avatar_catalog.dart` and `AvatarCanvas` with stable NPC portrait IDs,
  so comms and bounty surfaces can show faces without requiring the player designer.
- **HUD / comms thumbnail** — small `AvatarCanvas` in the top HUD strip or the communications panel.
- **Pirate species** — scarred Terran/Duran variants, once pirates are selectable anywhere.
- **Crew roster** — multiple avatars per ship.
- **Unlockable cosmetics** — headgear/capes purchased with the existing scrap metal/tech currencies
  or earned via the hacking codex and faction standing.
- **Layered designer** — expand compatible artist-authored face, species feature, clothing, and
  accessory layers after the gallery and art direction are validated.
- **Shareable avatar codes** — stable catalog/layer IDs can be serialized for sharing or server sync.
- **Expanded upload tools** — richer crop/rotate/edit controls if the first upload flow proves useful.
- **Content-hash avatar store** — dedupe identical uploads across accounts instead of one file per
  account (§7.3).
- **Moderation & remote avatars** — if a server ever syncs portraits, §10.12 becomes a real
  requirement (quarantine, review, size-normalising pipeline) rather than a local-only concern.
