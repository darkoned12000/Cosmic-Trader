import 'package:flutter/material.dart';
import 'package:cosmic_trader/core/tw_layout.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
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

class SectorView extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;
  final VoidCallback? onOpenPort;
  final VoidCallback? onOpenPlanet;
  final List<NpcShip> npcs;
  final VoidCallback? onRefreshNpcs;
  final int fedSpaceEnd;

  const SectorView({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
    this.onOpenPort,
    this.onOpenPlanet,
    this.npcs = const [],
    this.onRefreshNpcs,
    this.fedSpaceEnd = 0,
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
  }

  @override
  void didUpdateWidget(SectorView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player.currentSectorId != widget.player.currentSectorId) {
      _updateCurrentSector();
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

    final updatedPlayer = widget.player.copyWith(
      currentSectorId: targetSectorId,
      turns: widget.player.turns - 1,
    );

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
          SizedBox(
            height: 200,
            child: SectorInteractionPanel(
              currentSector: _currentSector!,
              npcs: _npcsInSector,
              player: widget.player,
              onPlayerUpdate: widget.onPlayerUpdate,
              onRefreshNpcs: widget.onRefreshNpcs,
              fedSpaceEnd: widget.fedSpaceEnd,
              onLandOnPlanet: widget.onOpenPlanet,
            ),
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
                    SizedBox(
                      height: 200,
                      child: SectorInteractionPanel(
                        currentSector: _currentSector!,
                        npcs: _npcsInSector,
                        player: widget.player,
                        onPlayerUpdate: widget.onPlayerUpdate,
                        onRefreshNpcs: widget.onRefreshNpcs,
                        fedSpaceEnd: widget.fedSpaceEnd,
                        onLandOnPlanet: widget.onOpenPlanet,
                      ),
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
          Expanded(
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
                            onLandOnPlanet: widget.onOpenPlanet),
                        const SizedBox(height: 12),
                        ShipStatusSummary(player: widget.player),
                      ],
                    ),
                  ),
                ),
              ],
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
