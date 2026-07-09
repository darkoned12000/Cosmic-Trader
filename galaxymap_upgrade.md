# Galaxy Map Upgrade Plan

## Goals

-   Reliable sector clicking.
-   Persistent exploration across sessions.
-   Clean separation of rendering, interaction, and persistence.
-   Preserve existing public API so the rest of the game continues to
    work.

------------------------------------------------------------------------

# Existing Structure

Current `GalaxyMap` owns too many responsibilities:

-   Rendering
-   Hit testing
-   Zoom/pan
-   Search
-   Detail panel
-   Exploration state
-   Selected sector
-   Coordinate transforms

Target architecture:

``` text
GalaxyMap
 ├── GalaxyMapPainter
 ├── GalaxyHitTester
 ├── GalaxyMapController
 └── PlayerExplorationStorage
```

------------------------------------------------------------------------

# Directory Layout

``` text
lib/
  data/
    models/
      sector_knowledge.dart
    storage/
      player_exploration_storage.dart

  widgets/
    galaxy_map/
      galaxy_map.dart
      galaxy_map_controller.dart
      galaxy_map_painter.dart
      galaxy_hit_test.dart
```

------------------------------------------------------------------------

# Stage 1 - Extract Hit Testing

Create `galaxy_hit_test.dart`.

Remove all distance calculations from GalaxyMap.

GalaxyMap should only call:

``` dart
final id = hitTester.hitTest(
    canvasPosition: point,
    sectorPositions: sectorPositions,
);
```

No coordinate math should exist anywhere else.

------------------------------------------------------------------------

# Stage 2 - Controller

Move these members into GalaxyMapController:

-   selectedSectorId
-   search controller
-   transformation controller
-   zoom level
-   pan position
-   centerOnSector()
-   zoomToFit()
-   search()
-   clearSearch()

GalaxyMap becomes mostly widget layout.

------------------------------------------------------------------------

# Stage 3 - Painter

Move ALL drawing code into GalaxyMapPainter.

The painter receives:

-   sectors
-   currentSector
-   selectedSector
-   visited sectors
-   NPCs
-   colors

Painter never performs hit testing.

Painter never updates state.

------------------------------------------------------------------------

# Stage 4 - Exploration

Replace

``` dart
Set<int> visited;
```

internally with

``` dart
Map<int, SectorKnowledge>
```

Keep this getter for compatibility:

``` dart
Set<int> get visited => ...
```

Add:

-   knowledgeFor()
-   bookmarkSector()
-   addNote()
-   visitSector()

Automatically migrate existing saves.

------------------------------------------------------------------------

# Stage 5 - Selection

Current behavior:

Click

↓

Sector

↓

Panel

New behavior:

Click

↓

Hit Tester

↓

Controller

↓

Selected Sector

↓

Detail Panel

No UI widget should directly search for sectors.

------------------------------------------------------------------------

# Stage 6 - Sector Cache

Instead of:

``` dart
sectors.firstWhere(...)
```

build once:

``` dart
Map<int, Sector> sectorIndex;
```

Lookups become:

``` dart
sectorIndex[id]
```

This improves scalability.

------------------------------------------------------------------------

# Stage 7 - Unknown / Discovered / Visited

Three states:

Unknown

-   Hide all information.

Discovered

-   Show exits and location.
-   Hide economic data.

Visited

-   Show everything.

------------------------------------------------------------------------

# Stage 8 - Detail Panel

Break into sections:

-   Overview
-   Navigation
-   Trade
-   NPC Activity
-   Notes

If not visited:

Display:

Unknown Sector

Only reveal:

-   Sector ID
-   Warp count
-   Distance

------------------------------------------------------------------------

# Stage 9 - Future Features

-   Route planner
-   Autopilot
-   Bookmarks
-   Favorite ports
-   Player notes
-   Pirate sightings
-   Mission markers
-   Trade overlays
-   Faction overlays

------------------------------------------------------------------------

# Coding Rules

1.  Painter only draws.
2.  Controller owns interaction.
3.  Storage owns persistence.
4.  Widgets never write save files.
5.  Never duplicate coordinate transforms.
6.  Never use firstWhere() repeatedly for sector lookup.

------------------------------------------------------------------------

# Testing Checklist

After every stage verify:

-   Game compiles.
-   Galaxy map opens.
-   Zoom works.
-   Pan works.
-   Clicking selects the correct sector.
-   Unknown sectors display correctly.
-   Visited sectors display details.
-   Save game.
-   Reload game.
-   Visited sectors remain visited.
-   Current sector is highlighted.
-   Search still works.
-   No Flutter exceptions.

Only proceed to the next stage after all tests pass.
