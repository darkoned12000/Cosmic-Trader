import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/tw_layout.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/star_field.dart';
import 'package:cosmic_trader/data/storage/player_exploration_storage.dart';
// TODO: adjust this path to wherever you place galaxy_hit_test.dart in your
// project. Following galaxymap_upgrade.md's proposed layout here:
import 'package:cosmic_trader/widgets/galaxy_map/galaxy_hit_test.dart';
// TODO: adjust these two paths to match wherever you place the extracted
// painter files in your project.
import 'package:cosmic_trader/widgets/galaxy_map/minimap_painter.dart';
import 'package:cosmic_trader/widgets/galaxy_map/galaxy_map_painter.dart';

class GalaxyMap extends StatefulWidget {
  final int currentSectorId;
  final ValueChanged<int>? onSectorSelected;
  final List<NpcShip> npcs;

  const GalaxyMap({
    super.key,
    required this.currentSectorId,
    this.onSectorSelected,
    this.npcs = const [],
  });

  @override
  State<GalaxyMap> createState() => _GalaxyMapState();
}

class _GalaxyMapState extends State<GalaxyMap> with TickerProviderStateMixin {
  List<Sector> _sectors = [];
  // Sector Cache: O(1) id -> Sector lookup, rebuilt whenever _sectors
  // changes. Replaces repeated `_sectors.firstWhere((s) => s.id == x)`
  // scans, which were O(n) each and scattered across build methods.
  Map<int, Sector> _sectorIndex = {};
  bool _loading = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int? _selectedSectorId;
  bool _showForceLayout = true;
  int? _lastCenteredSectorId;
  bool _showStarfield = true;

  // Force-directed layout positions
  Map<int, Offset> _nodePositions = {};
  Set<int>? _localSectorIds;
  Size? _lastCanvasSize;
  double _scaledNodeRadius = 10;

  final TransformationController _transformationController =
      TransformationController();

  final GlobalKey _canvasKey = GlobalKey();
  late final AnimationController _starAnimController;

  // IMPROVEMENT: Added pulse controller for current sector animation
  late final AnimationController _pulseController;

  // IMPROVEMENT: Added async layout tracking
  bool _layoutInProgress = false;

  // IMPROVEMENT: Added search navigation state
  int _searchResultIndex = 0;
  List<Sector> _searchResults = [];

  // IMPROVEMENT: Added fog of war / exploration state
  Set<int> _visitedSectors = {};

  static const int fedSpaceEnd = 9;

  @override
  void initState() {
    super.initState();
    _starAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();

    // IMPROVEMENT: Initialize pulse controller
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // IMPROVEMENT: Initialize visited sectors (mock exploration for demo)
    _visitedSectors = {widget.currentSectorId};

    _loadSectors();
  }

  /// O(1) sector lookup by id, falling back to the first sector if the id
  /// isn't found (matches the previous firstWhere(... orElse: ...) behavior).
  Sector _sectorById(int? id) {
    return _sectorIndex[id] ?? _sectors.first;
  }

  Future<void> _markVisited(int sectorId) async {
    final isNewlyDiscovered = !_visitedSectors.contains(sectorId);
    if (isNewlyDiscovered) {
      setState(() => _visitedSectors.add(sectorId));
    }
    // Fire-and-forget the disk write. Always stamp the timestamp, even on
    // revisits, so "Last Visited" reflects the most recent time the player
    // was actually in this sector.
    PlayerExplorationStorage.instance.markVisited(sectorId);
  }

  @override
  void dispose() {
    _starAnimController.dispose();
    _pulseController.dispose(); // IMPROVEMENT: Dispose pulse controller
    _searchController.dispose();
    _transformationController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(GalaxyMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentSectorId != oldWidget.currentSectorId) {
      _lastCenteredSectorId = null; // force re-center
      _markVisited(widget.currentSectorId);
      _centerOnCurrentSector();
    }
  }

  void _centerOnCurrentSector() {
    if (_nodePositions.isEmpty || _lastCanvasSize == null) {
      _lastCenteredSectorId = null;
      return;
    }
    _centerOnSector(widget.currentSectorId);
  }

  Future<void> _loadSectors() async {
    try {
      // 1. Load persisted exploration data from disk
      await PlayerExplorationStorage.instance.load();
      _visitedSectors = Set.from(PlayerExplorationStorage.instance.visited);

      // 2. Ensure the sector we are currently in is marked visited
      _visitedSectors.add(widget.currentSectorId);
      await PlayerExplorationStorage.instance
          .markVisited(widget.currentSectorId);

      // 3. Load universe (your existing code)
      await UniverseStorage.instance.ensureUniverse();
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (!mounted) return;
      setState(() {
        _sectors = sectors;
        _sectorIndex = {for (final s in sectors) s.id: s};
        _loading = false;
        _nodePositions = {};
        _lastCanvasSize = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load galaxy: $e'),
          backgroundColor: Colors.red.shade800,
        ),
      );
    }
  }

  void _ensurePositions(Size canvasSize) {
    if (_sectors.isEmpty || canvasSize.isEmpty || _layoutInProgress) return;
    if (_lastCanvasSize == canvasSize &&
        _nodePositions.isNotEmpty &&
        _lastCenteredSectorId == widget.currentSectorId) {
      return;
    }

    _lastCanvasSize = canvasSize;
    _scaledNodeRadius = max(8.0, min(canvasSize.width, canvasSize.height) / 50);

    // IMPROVEMENT: Trigger async layout instead of blocking UI
    _computeLayoutAsync(canvasSize);
  }

  // IMPROVEMENT: Async layout computation to prevent frame drops
  Future<void> _computeLayoutAsync(Size canvasSize) async {
    if (_layoutInProgress) return;
    _layoutInProgress = true;

    final localIds = <int>{};
    final queue = <int>[widget.currentSectorId];
    localIds.add(widget.currentSectorId);

    while (queue.isNotEmpty && localIds.length < 40) {
      final id = queue.removeAt(0);
      final sector = _sectorById(id);
      for (final warpId in sector.warpRoutes) {
        if (!localIds.contains(warpId) && localIds.length < 40) {
          localIds.add(warpId);
          queue.add(warpId);
        }
      }
    }

    if (localIds.length < 40) {
      final current = _sectorById(widget.currentSectorId);
      final sorted = _sectors.where((s) => !localIds.contains(s.id)).toList()
        ..sort((a, b) {
          final da = pow(a.x - current.x, 2) + pow(a.y - current.y, 2);
          final db = pow(b.x - current.x, 2) + pow(b.y - current.y, 2);
          return da.compareTo(db);
        });
      for (final s in sorted) {
        if (localIds.length >= 40) break;
        localIds.add(s.id);
      }
    }

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final radius = min(canvasSize.width, canvasSize.height) * 0.35;
    final angleStep = 2 * pi / localIds.length;
    final newPositions = <int, Offset>{};
    var i = 0;
    for (final id in localIds) {
      final angle = angleStep * i++;
      newPositions[id] =
          center + Offset(cos(angle) * radius, sin(angle) * radius);
    }

    // Run force layout in chunks
    final scale = min(canvasSize.width, canvasSize.height) / 800.0;
    final connectionDist = 140.0 * scale;
    final repulsionStrength = 20000.0 * scale;
    final springStrength = 0.04;
    final damping = 0.85;
    const totalIterations = 150;
    const chunkSize = 30;

    final activeList = localIds.toList();
    var positions = Map<int, Offset>.from(newPositions);
    final velocities = <int, Offset>{};
    for (final id in localIds) {
      velocities[id] = Offset.zero;
    }

    for (var start = 0; start < totalIterations; start += chunkSize) {
      final end = min(start + chunkSize, totalIterations);
      for (var iter = start; iter < end; iter++) {
        final forces = <int, Offset>{};
        for (final id in localIds) {
          forces[id] = Offset.zero;
        }

        for (var ii = 0; ii < activeList.length; ii++) {
          for (var j = ii + 1; j < activeList.length; j++) {
            final id1 = activeList[ii];
            final id2 = activeList[j];
            final pos1 = positions[id1]!;
            final pos2 = positions[id2]!;
            final dx = pos2.dx - pos1.dx;
            final dy = pos2.dy - pos1.dy;
            final dist = sqrt(dx * dx + dy * dy);
            if (dist > 0) {
              final force = repulsionStrength / (dist * dist);
              final fx = (dx / dist) * force;
              final fy = (dy / dist) * force;
              forces[id1] = forces[id1]! - Offset(fx, fy);
              forces[id2] = forces[id2]! + Offset(fx, fy);
            }
          }
        }

        for (final sector in _sectors) {
          if (!localIds.contains(sector.id)) continue;
          for (final warpId in sector.warpRoutes) {
            if (!localIds.contains(warpId)) continue;
            final pos1 = positions[sector.id];
            final pos2 = positions[warpId];
            if (pos1 == null || pos2 == null) continue;
            final dx = pos2.dx - pos1.dx;
            final dy = pos2.dy - pos1.dy;
            final dist = sqrt(dx * dx + dy * dy);
            if (dist > 0) {
              final force = (dist - connectionDist) * springStrength;
              final fx = (dx / dist) * force;
              final fy = (dy / dist) * force;
              forces[sector.id] = forces[sector.id]! + Offset(fx, fy);
              forces[warpId] = forces[warpId]! - Offset(fx, fy);
            }
          }
        }

        for (final id in localIds) {
          final force = forces[id]!;
          final vel = velocities[id]!;
          velocities[id] = (vel + force) * damping;
          positions[id] = positions[id]! + velocities[id]!;
        }
      }
      // Yield to the framework between chunks
      await Future.delayed(Duration.zero);
      if (!mounted) return;
    }

    if (!mounted) return;
    setState(() {
      _nodePositions = positions;
      _localSectorIds = localIds;
    });

    _lastCenteredSectorId = widget.currentSectorId;
    _centerOnCurrentSector();
    _layoutInProgress = false;
  }

  void _centerOnSector(int sectorId) {
    final pos = _nodePositions[sectorId];
    if (pos == null || _lastCanvasSize == null) return;
    final size = _lastCanvasSize!;
    final offset = Offset(size.width / 2 - pos.dx, size.height / 2 - pos.dy);
    _transformationController.value =
        Matrix4.translationValues(offset.dx, offset.dy, 0);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading galaxy data...'),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > TWLayout.largeScreenMinWidth) {
          return _buildLargeScreenLayout(constraints);
        }
        return _buildSmallScreenLayout();
      },
    );
  }

  Widget _buildSmallScreenLayout() {
    return Column(
      children: [
        _searchBar(),
        Expanded(
          child: Stack(
            children: [
              _galaxyMapView(),
              if (_selectedSectorId != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: _sectorDetailCard(_sectorById(_selectedSectorId)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLargeScreenLayout(BoxConstraints constraints) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _searchBar(),
              Expanded(
                child: Stack(
                  children: [
                    _galaxyMapView(),
                  ],
                ),
              ),
            ],
          ),
        ),
        const VerticalDivider(thickness: 1, width: 1),
        Expanded(
          flex: 2,
          child: _selectedSectorId != null
              ? _sectorDetailPanel(_sectorById(_selectedSectorId))
              : _emptyDetailPanel(),
        ),
      ],
    );
  }

  // IMPROVEMENT: Upgraded Search Bar with Navigation
  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search sectors...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchResults.length > 1) ...[
                            IconButton(
                              icon:
                                  const Icon(Icons.keyboard_arrow_up, size: 20),
                              onPressed: () {
                                _searchResultIndex = (_searchResultIndex - 1)
                                    .clamp(0, _searchResults.length - 1);
                                _navigateToSearchResult();
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.keyboard_arrow_down,
                                  size: 20),
                              onPressed: () {
                                _searchResultIndex = (_searchResultIndex + 1)
                                    .clamp(0, _searchResults.length - 1);
                                _navigateToSearchResult();
                              },
                            ),
                          ],
                          IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _searchController.clear();
                              _updateSearch('');
                            },
                          ),
                        ],
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: _updateSearch,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(_showForceLayout ? Icons.auto_awesome : Icons.grid_view),
            onPressed: () {
              setState(() {
                _showForceLayout = !_showForceLayout;
                _lastCanvasSize = null; // force recompute
              });
            },
            tooltip: 'Toggle layout',
          ),
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: () {
              _transformationController.value = Matrix4.identity();
            },
            tooltip: 'Reset view',
          ),
          IconButton(
            icon: Icon(
                _showStarfield ? Icons.stars_rounded : Icons.stars_outlined),
            onPressed: () => setState(() => _showStarfield = !_showStarfield),
            tooltip: 'Toggle starfield',
          ),
        ],
      ),
    );
  }

  // IMPROVEMENT: Search Navigation Logic
  void _updateSearch(String query) {
    _searchQuery = query;
    if (query.isEmpty) {
      _searchResults = [];
      _searchResultIndex = 0;
    } else {
      _searchResults = _sectors
          .where((s) =>
              s.name.toLowerCase().contains(query.toLowerCase()) ||
              s.id.toString().contains(query))
          .toList();
      _searchResultIndex = 0;
      if (_searchResults.isNotEmpty) {
        _navigateToSearchResult();
      }
    }
    setState(() {});
  }

  void _navigateToSearchResult() {
    if (_searchResults.isEmpty) return;
    final sector = _searchResults[_searchResultIndex];
    _centerOnSector(sector.id);
    setState(() {
      _selectedSectorId = sector.id;
      // Note: searching for a sector only selects/centers it on the map —
      // it does NOT mark it visited. Fog of war should only clear when the
      // player actually flies there (see didUpdateWidget).
    });
  }

  Widget _galaxyMapView() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cs = Theme.of(context).colorScheme;
        final canvasW = constraints.maxWidth;
        final canvasH = constraints.maxHeight;
        final canvasSize = Size(canvasW, canvasH);

        _ensurePositions(canvasSize);

        return Stack(
          children: [
            if (_showStarfield)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: StarfieldPainter(
                      size: canvasSize,
                      animation: _starAnimController,
                      starCount: 240,
                    ),
                  ),
                ),
              ),
            Focus(
              autofocus: true,
              onKeyEvent: _onMapKeyEvent,
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(500),
                transformationController: _transformationController,
                minScale: 0.1,
                maxScale: 5.0,
                child: SizedBox(
                  key: _canvasKey,
                  width: canvasW,
                  height: canvasH,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return CustomPaint(
                        size: canvasSize,
                        painter: GalaxyMapPainter(
                          sectors: _sectors,
                          positions: _nodePositions,
                          localSectorIds: _localSectorIds,
                          selectedSectorId: _selectedSectorId,
                          currentSectorId: widget.currentSectorId,
                          searchQuery: _searchQuery,
                          colors: cs,
                          nodeRadius: _scaledNodeRadius,
                          npcs: widget.npcs,
                          pulseValue: _pulseController.value,
                          visitedSectors: _visitedSectors,
                          fedSpaceEnd: fedSpaceEnd,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.translucent,
                // NOTE: `event.localPosition` here is relative to this
                // Listener itself, which sits as a sibling of
                // InteractiveViewer in the Stack — i.e. viewport space,
                // untouched by the pan/zoom transform. _handleTap converts
                // that into canvas-content space itself.
                onPointerUp: (event) => _handleTap(event.localPosition),
              ),
            ),
            // IMPROVEMENT: Minimap Overlay
            if (_lastCanvasSize != null && _nodePositions.isNotEmpty)
              Positioned(
                top: 16,
                right: 16,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: cs.surface.withValues(alpha: 0.8),
                    borderRadius: BorderRadius.circular(8),
                    border:
                        Border.all(color: cs.outline.withValues(alpha: 0.3)),
                  ),
                  child: CustomPaint(
                    painter: MinimapPainter(
                      positions: _nodePositions,
                      localSectorIds: _localSectorIds,
                      currentSectorId: widget.currentSectorId,
                      selectedSectorId: _selectedSectorId,
                      viewportTransform: _transformationController.value,
                      canvasSize: _lastCanvasSize!,
                      colors: cs,
                    ),
                  ),
                ),
              ),
            // IMPROVEMENT: Legend Overlay
            Positioned(
              bottom: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Legend',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface.withValues(alpha: 0.6))),
                    const SizedBox(height: 6),
                    _legendItem(cs.tertiary, 'Current Sector'),
                    _legendItem(cs.primary, 'FedSpace'),
                    _legendItem(
                        cs.onSurface.withValues(alpha: 0.4), 'Unexplored'),
                    _legendItem(Colors.greenAccent, '◆ Port'),
                    _legendItem(Colors.brown, '● Planet'),
                    _legendItem(factionColor(FactionClass.trader), '● Trader'),
                    _legendItem(factionColor(FactionClass.duran), '● Duran'),
                    _legendItem(factionColor(FactionClass.vinari), '● Vinari'),
                    _legendItem(factionColor(FactionClass.pirate), '● Pirate'),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // IMPROVEMENT: Legend Item Helper
  Widget _legendItem(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 11)),
        ],
      ),
    );
  }

  KeyEventResult _onMapKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _lastCanvasSize == null) {
      return KeyEventResult.ignored;
    }
    const step = 30.0;
    Offset pan;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowUp:
        pan = const Offset(0, step);
      case LogicalKeyboardKey.arrowDown:
        pan = const Offset(0, -step);
      case LogicalKeyboardKey.arrowLeft:
        pan = const Offset(step, 0);
      case LogicalKeyboardKey.arrowRight:
        pan = const Offset(-step, 0);
      default:
        return KeyEventResult.ignored;
    }
    final current = _transformationController.value.clone();
    current.translateByDouble(pan.dx, pan.dy, 0.0, 1.0);
    _transformationController.value = current;
    return KeyEventResult.handled;
  }

  // IMPROVEMENT: Tap detection delegated to GalaxyHitTester so coordinate
  // math lives in exactly one place. Tolerance (+4px) is folded into the
  // radius passed in, matching the old inline behavior — GalaxyHitTester
  // itself doesn't know about tap-tolerance, that's a GalaxyMap concern.
  //
  // `viewportPosition` is in viewport space (untransformed by pan/zoom —
  // see the Listener above). We invert the current InteractiveViewer
  // transform ourselves to map it into canvas-content space, which is the
  // space _nodePositions live in.
  void _handleTap(Offset viewportPosition) {
    final inverse = Matrix4.inverted(_transformationController.value);
    final canvasPos = MatrixUtils.transformPoint(inverse, viewportPosition);

    final hitTester = GalaxyHitTester(nodeRadius: _scaledNodeRadius + 4);
    final hitSectorId = hitTester.hitTest(
      canvasPosition: canvasPos,
      sectorPositions: _nodePositions,
    );

    setState(() {
      _selectedSectorId = hitSectorId;
      // Note: tapping a node only selects it — it does NOT mark it
      // visited. Only actually flying to a sector should clear fog of
      // war (see didUpdateWidget).
    });
  }

  // IMPROVEMENT: Compact detail panel shown for sectors the player hasn't
  // actually flown to yet. Deliberately withholds name/ports/planets/NPCs —
  // only what's visible from the outside (id, and that it connects here)
  // should ever be shown for an unvisited sector.
  Widget _unknownSectorPanel(Sector sector) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.help_outline,
                      size: 40, color: cs.onSurface.withValues(alpha: 0.4)),
                  const SizedBox(height: 12),
                  Text(
                    'Unknown Sector',
                    style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withValues(alpha: 0.7)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sector #${sector.id}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurface.withValues(alpha: 0.5)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'You haven\'t explored this sector yet. Fly here to '
                    'reveal what it holds.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: cs.onSurface.withValues(alpha: 0.6),
                        fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onSectorSelected?.call(sector.id),
              icon: const Icon(Icons.navigation_rounded),
              label: Text('Move to Sector #${sector.id}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectorDetailPanel(Sector sector) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (!_visitedSectors.contains(sector.id)) {
      return _unknownSectorPanel(sector);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 0,
            color: cs.primaryContainer.withValues(alpha: 0.3),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    sector.name,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Sector #${sector.id}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                  const SizedBox(height: 8),
                  if (sector.id <= fedSpaceEnd)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primary.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'FedSpace',
                        style: TextStyle(
                            color: cs.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Details',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _detailRow(cs, 'Coordinates', sector.quadrant),
                  _detailRow(cs, 'Warp Routes',
                      '${sector.warpRoutes.length} connections'),
                  _detailRow(
                      cs,
                      'NPCs',
                      (sector.traderCount +
                              sector.duranCount +
                              sector.vinariCount +
                              sector.pirateCount)
                          .toString()),
                  _detailRow(cs, 'Port', sector.hasPort ? 'Yes' : 'No'),
                  if (sector.hasPlanet)
                    _detailRow(
                        cs, 'Planet', sector.planet?.planetType ?? 'Unknown'),
                  if (sector.anomaly != null)
                    _detailRow(cs, 'Anomaly', sector.anomaly!),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // IMPROVEMENT: Tappable Warp Connections
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Warp Connections',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  ...sector.warpRoutes.map((warpId) {
                    final targetSector = _sectorIndex[warpId] ?? sector;
                    final isFedTarget = targetSector.id <= fedSpaceEnd;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() => _selectedSectorId = warpId);
                          _centerOnSector(warpId);
                          // Note: browsing a neighboring warp connection only
                          // selects/centers it — it does NOT mark it visited.
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: isFedTarget
                                      ? cs.primary
                                      : cs.onSurface.withValues(alpha: 0.4),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text('#${targetSector.id}'),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  targetSector.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color:
                                          cs.onSurface.withValues(alpha: 0.7)),
                                ),
                              ),
                              if (targetSector.hasPort)
                                Icon(Icons.store,
                                    size: 14, color: Colors.greenAccent),
                              if (targetSector.hasPlanet)
                                Icon(Icons.public,
                                    size: 14, color: Colors.cyanAccent),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => widget.onSectorSelected?.call(sector.id),
              icon: const Icon(Icons.navigation_rounded),
              label: Text('Move to Sector #${sector.id}'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectorDetailCard(Sector sector) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(sector.name,
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => _selectedSectorId = null),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Sector #${sector.id} • ${sector.warpRoutes.length} warps',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => widget.onSectorSelected?.call(sector.id),
                icon: const Icon(Icons.navigation_rounded, size: 18),
                label: Text('Move to Sector #${sector.id}'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(ColorScheme cs, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6), fontSize: 13)),
          Text(value,
              style:
                  const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _emptyDetailPanel() {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_rounded,
              size: 64, color: cs.onSurface.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Select a sector to view details',
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.5), fontSize: 16)),
        ],
      ),
    );
  }
}
