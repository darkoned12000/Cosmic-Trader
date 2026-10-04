import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/tw_layout.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_panel.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/sector_interaction_panel.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/ship_status_summary.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/communications_panel.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/tactical_map.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/warp_console.dart';
import 'package:cosmic_trader/services/energy_service.dart';

class SectorView extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;
  final VoidCallback? onOpenPort;
  final VoidCallback? onOpenPlanet;
  final List<NpcShip> npcs;
  final VoidCallback? onRefreshNpcs;
  final int fedSpaceEnd;

  /// Universe settings for post-death clone reissue in player combat.
  final GameSettings settings;

  const SectorView({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
    this.onOpenPort,
    this.onOpenPlanet,
    this.npcs = const [],
    this.onRefreshNpcs,
    this.fedSpaceEnd = 0,
    required this.settings,
  });

  @override
  State<SectorView> createState() => _SectorViewState();
}

class _SectorViewState extends State<SectorView> {
  List<Sector> _allSectors = [];
  Sector? _currentSector;
  bool _loading = true;
  String? _statusMessage;

  // NEW: This is the state variable that connects the TacticalMap to the WarpConsole
  int? _selectedWarpTargetId;

  @override
  void initState() {
    super.initState();
    ActionLogProvider.global.system('Sector View V2 initialized');
    _loadUniverse();
    // Repaint whenever *anything* writes the universe, wherever it was written
    // from. Without this the tab showed a snapshot taken at mount: firing a
    // Genesis Torpedo from the Ship screen wrote the world, the snackbar
    // confirmed it, and the Sector Contents panel sitting right beside it went on
    // showing the sector as it had been — a world you had just paid for,
    // invisible until you left the tab and came back.
    //
    // The signal comes from storage because the writer knows nothing about this
    // tab; patching the launching screen cannot work. What the listener now does
    // with it is *only* repaint — the data is already in this widget's hands
    // because it holds the shared graph. The re-read below is a cache hit, kept
    // for the one case identity does not survive (see [_refreshFromDisk]).
    UniverseStorage.instance.revision.addListener(_onUniverseChanged);
  }

  void _onUniverseChanged() => _refreshFromDisk();

  /// Re-reads the universe **without** the `ensureUniverse` side effect.
  ///
  /// [ensureUniverse] can *generate and write* a universe when the file is
  /// missing, so calling it from a write listener would close a loop: write →
  /// bump → refresh → ensure → write → bump. [initState] still calls it once,
  /// which is the only place that is allowed to author a universe.
  ///
  /// There used to be in-flight/queued coalescing here, to stop two reads racing
  /// and resolving out of order. That guarded a real hazard and it is now
  /// structurally impossible: the reads were two *different parses* of the file,
  /// so the older one could land last and win. Storage shares one graph, so every
  /// read returns the same list and the order two of them resolve in cannot
  /// change the result. The coalescing flags are gone rather than left in place
  /// describing a race that no longer has anywhere to occur.
  ///
  /// What the read *is* still for: `generateWithSettings` installs a brand-new
  /// list, and this tab has to notice. That is the single case where the shared
  /// graph's identity changes, and it is a one-line comparison away.
  Future<void> _refreshFromDisk() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (!mounted) return;
      if (sectors.isNotEmpty) {
        setState(() => _allSectors = sectors);
        _updateCurrentSector();
      }
    } catch (e) {
      // A failed read must not blank the tab; the snapshot already on screen
      // is older but true, and the next write will try again.
      debugPrint('SectorView universe refresh failed: $e');
    }
  }

  @override
  void didUpdateWidget(SectorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.currentSectorId != widget.player.currentSectorId) {
      // A warp moves the player, and the destination may have been written by
      // anything, so go to disk rather than trusting the mount-time list.
      _refreshFromDisk();
      // NEW: Clear the selection when the player moves to a new sector
      setState(() {
        _selectedWarpTargetId = null;
      });
    }
  }

  Future<void> _loadUniverse() async {
    try {
      await UniverseStorage.instance.ensureUniverse();
      final sectors = await UniverseStorage.instance.loadUniverse();
      UniverseStorage.instance.logSectorStats(sectors);
      if (!mounted) return;
      setState(() {
        _allSectors = sectors;
        _loading = false;
      });
      _updateCurrentSector();
      ActionLogProvider.global
          .system('Universe loaded: ${sectors.length} sectors');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _statusMessage = 'Failed to load universe: $e';
      });
      ActionLogProvider.global.error('Failed to load universe: $e');
    }
  }

  List<NpcShip> get _npcsInSector => widget.npcs
      .where((n) => n.currentSectorId == widget.player.currentSectorId)
      .toList();

  void _updateCurrentSector() {
    if (_allSectors.isEmpty) return;
    final match =
        _allSectors.where((s) => s.id == widget.player.currentSectorId);
    if (match.isEmpty) {
      _refreshUniverse();
      return;
    }
    setState(() => _currentSector = match.first);
  }

  Future<void> _refreshUniverse() async {
    final sectors = await UniverseStorage.instance.loadUniverse();
    if (!mounted) return;
    _allSectors = sectors;
    _updateCurrentSector();
  }

  Future<void> _warpTo(int targetSectorId) async {
    final target = _allSectors.firstWhere((s) => s.id == targetSectorId);

    if (!EnergyService.canMove(widget.player)) {
      ActionLogProvider.global
          .error('Solar Array deployed — retract it before warping');
      return;
    }

    final warpCost = EnergyService.warpCost(widget.player);
    if (!widget.player.hasEnergy(warpCost)) {
      ActionLogProvider.global
          .error('Insufficient energy to warp ($warpCost required)');
      return;
    }

    final updatedPlayer = widget.player
        .spendEnergy(warpCost)
        .copyWith(currentSectorId: targetSectorId);

    final sectorName = _currentSector?.name ?? 'Unknown';
    ActionLogProvider.global
        .movement('Warped from $sectorName to ${target.name}');

    // NEW: Clear the tactical map selection once the warp is executed
    setState(() {
      _selectedWarpTargetId = null;
    });

    widget.onPlayerUpdate(updatedPlayer);
  }

  @override
  void dispose() {
    // A listener left attached outlives the State, so a disposed Sector tab
    // would keep asking for reads and `setState` after dispose. The tab is
    // rebuilt on every universe key change, so this is not hypothetical.
    UniverseStorage.instance.revision.removeListener(_onUniverseChanged);
    super.dispose();
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
            Text('Loading sector data...'),
          ],
        ),
      );
    }

    if (_currentSector == null) {
      return const Center(child: Text('No sector data available.'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > TWLayout.extraLargeScreenMinWidth) {
          return _buildDesktopLayout();
        } else if (constraints.maxWidth > TWLayout.largeScreenMinWidth) {
          return _buildTabletLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statusMessage != null) _statusBanner(),
          SizedBox(
            height: 220,
            child: TacticalMap(
              currentSector: _currentSector!,
              allSectors: _allSectors,
              player: widget.player,
              npcs: widget.npcs,
              // NEW: Listen for taps on the tactical map
              onWarpTargetSelected: (targetId) {
                setState(() {
                  _selectedWarpTargetId = targetId;
                });
              },
            ),
          ),
          const SizedBox(height: 12),
          SectorInteractionPanel(
            currentSector: _currentSector!,
            npcs: _npcsInSector,
            player: widget.player,
            onPlayerUpdate: widget.onPlayerUpdate,
            onRefreshNpcs: widget.onRefreshNpcs,
            fedSpaceEnd: widget.fedSpaceEnd,
            settings: widget.settings,
            onLandOnPlanet: widget.onOpenPlanet,
          ),
          const SizedBox(height: 12),
          ShipStatusSummary(player: widget.player),
          const SizedBox(height: 12),
          WarpConsole(
            currentSector: _currentSector!,
            allSectors: _allSectors,
            player: widget.player,
            onWarp: _warpTo,
            // NEW: Pass the selected ID down to the WarpConsole
            highlightedSectorId: _selectedWarpTargetId,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: ActionLogPanel(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 250,
            child: CommunicationsPanel(),
          ),
          const SizedBox(height: 12),
          if (_currentSector!.hasPort) _openPortButton(),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statusMessage != null) _statusBanner(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  children: [
                    SizedBox(
                      height: 280,
                      child: TacticalMap(
                        currentSector: _currentSector!,
                        allSectors: _allSectors,
                        player: widget.player,
                        npcs: widget.npcs,
                        // NEW: Listen for taps on the tactical map
                        onWarpTargetSelected: (targetId) {
                          setState(() {
                            _selectedWarpTargetId = targetId;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    WarpConsole(
                      currentSector: _currentSector!,
                      allSectors: _allSectors,
                      player: widget.player,
                      onWarp: _warpTo,
                      // NEW: Pass the selected ID down to the WarpConsole
                      highlightedSectorId: _selectedWarpTargetId,
                    ),
                    const SizedBox(height: 12),
                    SectorInteractionPanel(
                      currentSector: _currentSector!,
                      npcs: _npcsInSector,
                      player: widget.player,
                      onPlayerUpdate: widget.onPlayerUpdate,
                      onRefreshNpcs: widget.onRefreshNpcs,
                      fedSpaceEnd: widget.fedSpaceEnd,
                      onLandOnPlanet: widget.onOpenPlanet,
                      settings: widget.settings,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: Column(
                  children: [
                    ShipStatusSummary(player: widget.player),
                    const SizedBox(height: 12),
                    if (_currentSector!.hasPort) _openPortButton(),
                    const SizedBox(height: 12),
                    // Fixed heights inside a scroll view — vertical
                    // Expanded children are invalid under unbounded
                    // height constraints (UI scale can shrink the
                    // logical view size into this layout).
                    SizedBox(
                      height: 300,
                      child: ActionLogPanel(),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 250,
                      child: CommunicationsPanel(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_statusMessage != null) _statusBanner(),
          // On very wide displays (4K), cap the row width so panels don't
          // stretch into unreadable columns; the extra space is centered.
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1760),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: ActionLogPanel(),
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            flex: 2,
                            child: CommunicationsPanel(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 4,
                      child: Column(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TacticalMap(
                              currentSector: _currentSector!,
                              allSectors: _allSectors,
                              player: widget.player,
                              npcs: widget.npcs,
                              // NEW: Listen for taps on the tactical map
                              onWarpTargetSelected: (targetId) {
                                setState(() {
                                  _selectedWarpTargetId = targetId;
                                });
                              },
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_currentSector!.hasPort)
                            SizedBox(
                              width: double.infinity,
                              child: _openPortButton(),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 3,
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            WarpConsole(
                              currentSector: _currentSector!,
                              allSectors: _allSectors,
                              player: widget.player,
                              onWarp: _warpTo,
                              // NEW: Pass the selected ID down to the WarpConsole
                              highlightedSectorId: _selectedWarpTargetId,
                            ),
                            const SizedBox(height: 12),
                            SectorInteractionPanel(
                                currentSector: _currentSector!,
                                npcs: _npcsInSector,
                                player: widget.player,
                                onPlayerUpdate: widget.onPlayerUpdate,
                                onRefreshNpcs: widget.onRefreshNpcs,
                                fedSpaceEnd: widget.fedSpaceEnd,
                                onLandOnPlanet: widget.onOpenPlanet,
                                settings: widget.settings),
                            const SizedBox(height: 12),
                            ShipStatusSummary(player: widget.player),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBanner() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.navigation_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _statusMessage!,
              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _openPortButton() {
    final cs = Theme.of(context).colorScheme;
    final isEmporium = _currentSector?.port?.isHardwareEmporium == true;
    final portName = _currentSector?.port?.name ?? 'Port';
    final label = isEmporium ? 'Dock with $portName' : 'Dock with Port';
    return ElevatedButton.icon(
      onPressed: widget.onOpenPort,
      icon: Icon(
        isEmporium ? Icons.build_rounded : Icons.store_rounded,
        size: 18,
      ),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: cs.tertiary,
        foregroundColor: cs.onTertiary,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}
