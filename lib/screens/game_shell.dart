import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cosmic_trader/core/app_exit.dart';
import 'package:cosmic_trader/core/tw_layout.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/player_storage.dart';
import 'package:cosmic_trader/data/storage/settings_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/screens/computer_screen.dart';
import 'package:cosmic_trader/screens/galaxy_map.dart';
import 'package:cosmic_trader/screens/planet_screen.dart';
import 'package:cosmic_trader/screens/login_screen.dart';
import 'package:cosmic_trader/screens/port_screen.dart';
import 'package:cosmic_trader/screens/sector_view.dart';
import 'package:cosmic_trader/screens/settings_screen.dart';
import 'package:cosmic_trader/screens/ship_status.dart';
import 'package:cosmic_trader/services/audio_service.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/economy_metrics.dart';
import 'package:cosmic_trader/services/game_event_log.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/widgets/combat_screen.dart';
import 'package:cosmic_trader/widgets/equalizer_widget.dart';
import 'package:cosmic_trader/widgets/hud_strip.dart';

class GameShell extends StatefulWidget {
  final Player initialPlayer;

  const GameShell({super.key, required this.initialPlayer});

  /// While a game session is mounted, the app-level close guard (main.dart)
  /// calls this to flush the session before the process exits.
  static Future<void> Function()? exitSaveHook;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> {
  late Player _player;
  int _currentIndex = 0;
  Key _universeKey = UniqueKey();
  Key _computerKey = UniqueKey();
  Key _planetKey = UniqueKey();
  GameSettings _settings = GameSettings.defaults();
  int _playerUpdateVersion = 0;
  List<NpcShip> _npcs = [];

  /// Universe sectors loaded once by the shell for the persistent HUD strip
  /// (sector name + faction ambiance). Tab screens still load their own copy.
  List<Sector> _hudSectors = [];

  final GameTickService _tickService = GameTickService(
    tickInterval: const Duration(seconds: 30),
  );

  @override
  void initState() {
    super.initState();
    _player = widget.initialPlayer;
    _loadSettings();
    _loadNpcs();
    _loadHudSectors();
    BountyBoard.global.ensureLoaded();
    EconomyMetrics.global.restore();
    _tickService.onTickComplete = (_) {
      _reloadNpcs();
      _applySolarRecharge();
    };
    _tickService.onTickError = (error) {
      debugPrint('[GameShell] Tick error: $error');
    };
    _tickService.onNpcAttacksPlayer = _handleNpcAttack;
    _tickService.start();
    // Hand the app-level close guard a way to flush this session if the OS
    // sends a close request (WM keybind / session end).
    GameShell.exitSaveHook = () async {
      _tickService.stop();
      await _persistSessionState();
    };
    // Mark the tick service with the FedSpace boundary after settings load
    _loadSettings().then((_) {
      _tickService.fedSpaceEnd = _settings.fedSpaceEnd;
      NpcAiService.safeZoneEnd = _settings.fedSpaceEnd;
      Port.safeZoneEnd = _settings.fedSpaceEnd;
    });
  }

  @override
  void dispose() {
    GameShell.exitSaveHook = null;
    _tickService.stop();
    super.dispose();
  }

  Future<void> _loadHudSectors() async {
    try {
      await UniverseStorage.instance.ensureUniverse();
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (mounted) setState(() => _hudSectors = sectors);
    } catch (_) {
      // HUD strip degrades gracefully to "…" until the universe is available.
    }
  }

  Future<void> _loadNpcs() async {
    try {
      final loaded = await NpcStorage().loadAll();
      if (mounted) setState(() => _npcs = loaded);
    } catch (_) {}
  }

  Future<void> _reloadNpcs() async {
    try {
      final loaded = await NpcStorage().loadAll();
      if (mounted) setState(() => _npcs = loaded);
    } catch (_) {}
  }

  /// Solar Array modules trickle-charge the active player each tick.
  ///
  /// This intentionally does nothing unless the module is installed and the
  /// tank has room, so it stays a slow backup rather than free infinite fuel.
  void _applySolarRecharge() {
    final result = EnergyService.solarRecharge(_player);
    if (result.unitsAdded <= 0) return;
    _updatePlayer(result.player);
  }

  void _handleNpcAttack(NpcAttackEvent event) {
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CombatScreen(
          player: event.player,
          npc: event.npc,
          sectorWarps: event.sectorWarps,
          onCombatEnd: (updatedPlayer, updatedNpc) {
            _updatePlayer(updatedPlayer);
            final idx = _npcs.indexWhere((n) => n.id == updatedNpc.id);
            if (idx >= 0) {
              setState(() => _npcs[idx] = updatedNpc);
            }
            NpcStorage().saveAll(_npcs);
            GameTickService.unlockNpc(updatedNpc.id);
          },
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    final saved = await SettingsStorage.instance.load();
    if (saved != null && mounted) {
      setState(() => _settings = saved);
    }
  }

  Future<void> _handleRegenerateUniverse(GameSettings settings) async {
    try {
      await UniverseStorage.instance.deleteUniverse();
      final actualSettings =
          await UniverseStorage.instance.generateWithSettings(settings);
      await SettingsStorage.instance.save(actualSettings);
      if (settings.deleteAllPlayersOnRegen) {
        await PlayerStorage.instance.savePlayers([]);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('All player accounts deleted'),
              backgroundColor: Colors.orange.shade800,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (route) => false,
          );
        }
        return;
      }
      setState(() {
        _settings = actualSettings;
        if (settings.resetPlayersOnRegen) {
          _player = _player.copyWith(
            currentSectorId: 1,
            energy: settings.initEnergy,
            maxEnergy: settings.initEnergy,
            credits: settings.initCredits,
            maxCargo: settings.initHolds,
            cargoSize: settings.initHolds,
            drones: settings.initDrones,
            maxDrones: settings.initDrones,
            hull: 100,
            shields: 100,
            cargo: const {},
            cargoUsed: 0,
          );
        }
        _universeKey = UniqueKey();
      });
      _updatePlayer(_player);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Universe regenerated successfully'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to regenerate universe: $e');
      }
    }
  }

  Future<void> _updatePlayer(Player updated) async {
    final prevSector = _player.currentSectorId;
    final version = ++_playerUpdateVersion;
    try {
      await PlayerStorage.instance.savePlayer(updated);
      if (mounted && version == _playerUpdateVersion) {
        setState(() => _player = updated);
        // Any sector change (warp console, combat flee, …) runs the jump
        // flash. Galaxy-map moves trigger via _onSectorSelected instead
        // (they mutate _player before calling back in here).
        if (updated.currentSectorId != prevSector) {
          _triggerWarp(updated.currentSectorId);
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to save player: $e');
      }
    }
  }

  /// Plays the warp SFX cue on any sector change (warp console, galaxy map,
  /// combat flee). The visual transition overlay was removed per playtest
  /// feedback — jumps are instant now.
  void _triggerWarp(int targetSectorId) {
    if (!mounted) return;
    AudioService.instance.playSfx('assets/sfx/warp.ogg');
  }

  /// Current sector for the HUD strip (name/ID), or null before the
  /// universe finishes loading in the shell.
  Sector? get _currentHudSector {
    for (final s in _hudSectors) {
      if (s.id == _player.currentSectorId) return s;
    }
    return null;
  }

  /// Dominant non-destroyed NPC faction in the current sector — tints the
  /// HUD accent bar and the warp rush (per-sector faction ambiance).
  FactionClass? _dominantFaction() {
    final counts = <FactionClass, int>{};
    for (final n in _npcs) {
      if (n.isDestroyed || n.currentSectorId != _player.currentSectorId) {
        continue;
      }
      counts[n.faction] = (counts[n.faction] ?? 0) + 1;
    }
    FactionClass? best;
    var bestCount = 0;
    counts.forEach((f, c) {
      if (c > bestCount) {
        best = f;
        bestCount = c;
      }
    });
    return best;
  }

  Future<void> _handleSettingsChanged(GameSettings updated) async {
    await SettingsStorage.instance.save(updated);
    if (mounted) {
      setState(() => _settings = updated);
    }
  }

  // ── Automation dev controls (F2) ──────────────────────────────

  bool _tickPaused = false;

  void _setAutomationTickInterval(int seconds) {
    if (_tickPaused) {
      _tickPaused = false;
      _tickService.start();
    }
    _tickService.updateInterval(Duration(seconds: seconds));
    GameEventLog.global.system('DEV tick interval → ${seconds}s');
    if (mounted) setState(() {});
  }

  void _setAutomationTickPaused(bool paused) {
    _tickPaused = paused;
    if (paused) {
      _tickService.stop();
    } else {
      _tickService.start();
    }
    GameEventLog.global
        .system(paused ? 'DEV ticks paused' : 'DEV ticks resumed');
    if (mounted) setState(() {});
  }

  void _grantAutomationCredits() {
    _updatePlayer(_player.copyWith(credits: _player.credits + 100000));
    GameEventLog.global.system('DEV granted player +100000 cr');
  }

  void _grantAutomationScrapMetal() {
    _updatePlayer(_player.copyWith(scrapMetal: _player.scrapMetal + 500));
    GameEventLog.global.system('DEV granted player +500 scrap metal');
  }

  void _grantAutomationScrapTech() {
    _updatePlayer(_player.copyWith(scrapTech: _player.scrapTech + 50));
    GameEventLog.global.system('DEV granted player +50 scrap tech');
  }

  void _drainAutomationPlayerEnergy() {
    _updatePlayer(_player.copyWith(energy: 0));
    GameEventLog.global.system('DEV drained player energy → 0');
  }

  Future<void> _drainAutomationNpcEnergy() async {
    final drained = _npcs
        .map((n) => n.copyWith(energy: (n.maxEnergy * 0.10).ceil()))
        .toList();
    if (mounted) setState(() => _npcs = drained);
    await NpcStorage().saveAll(drained);
    GameEventLog.global
        .system('DEV drained ${drained.length} NPCs → 10% energy');
  }

  /// One-click trading diagnostic: snapshots every NPC's goal/energy/
  /// credits/memory and every port's books into the event log and the
  /// clipboard. Built to answer "why did trading stop after a restart?"
  /// with ground truth instead of guesses.
  Future<void> _dumpTradeDiagnostics() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      final lines = <String>['=== Trade diagnostics ==='];

      var tradeGoals = 0;
      for (final n in _npcs) {
        if (n.isDestroyed) continue;
        final g = n.currentGoal;
        if (g?.type == NpcGoalType.tradeRoute) tradeGoals++;
        lines.add(
          'NPC ${n.pilotName} sector=${n.currentSectorId} '
          'goal=${g?.type} status=${g?.status} '
          'phase=${g?.params['phase']} target=${g?.targetSectorId} '
          'energy=${n.energy}/${n.maxEnergy} credits=${n.credits} '
          'bank=${n.bankBalance} ports=${n.memory.discoveredPorts.length} '
          'cargo=${n.cargoUsed}/${n.cargoHoldCapacity} '
          'personality=${n.personality.name}',
        );
      }
      lines.add('NPCs with active tradeRoute goals: $tradeGoals');

      var emptySupply = 0;
      var emptyDemand = 0;
      var brokePorts = 0;
      for (final s in sectors) {
        final port = s.port;
        if (port == null) continue;
        final supplyTotal = port.supply.values.fold(0, (a, b) => a + b);
        final demandTotal = port.demand.values.fold(0, (a, b) => a + b);
        if (supplyTotal <= 0) emptySupply++;
        if (demandTotal <= 0) emptyDemand++;
        if (port.portCredits < 1000) brokePorts++;
        lines.add(
          'PORT sector=${s.id} ${port.name} supply=$supplyTotal '
          'demand=$demandTotal credits=${port.portCredits.toStringAsFixed(0)}',
        );
      }
      lines.add(
        'Ports: empty-supply=$emptySupply empty-demand=$emptyDemand '
        'broke(<1000cr)=$brokePorts',
      );

      final text = lines.join('\n');
      GameEventLog.global.system(text);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trade diagnostics copied')),
        );
      }
    } catch (e) {
      GameEventLog.global.system('DEV diagnostics failed: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  void _onSectorSelected(int sectorId) {
    if (!EnergyService.canMove(_player)) {
      _showError('Retract the Solar Array before moving.');
      return;
    }
    if (_player.currentSectorId != sectorId) {
      setState(() {
        _player = _player.copyWith(currentSectorId: sectorId);
      });
      _updatePlayer(_player);
      _triggerWarp(sectorId);
    }
    setState(() => _currentIndex = 0);
  }

  /// Switches to the Planet tab with a fresh PlanetScreen and plays the
  /// docking thump.
  void _openPlanet() {
    AudioService.instance.playSfx('assets/sfx/land.ogg');
    setState(() {
      _currentIndex = 5;
      _planetKey = UniqueKey();
    });
  }

  Future<void> _handleLogout() async {
    await PlayerStorage.instance.savePlayer(_player);
    await PlayerStorage.instance.clearPlayer();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  /// Saves everything and exits to the desktop cleanly.
  Future<void> _handleExitGame() async {
    // Stop background processing first so nothing mutates state mid-save.
    _tickService.stop();
    await _persistSessionState();
    quitApplication();
  }

  /// Flushes all in-memory game state to disk. Stores use crash-safe atomic
  /// writes (FileSafe), so an interrupted write can never leave a truncated
  /// file behind.
  Future<void> _persistSessionState() async {
    try {
      await Future.wait([
        PlayerStorage.instance.savePlayer(_player),
        NpcStorage().saveAll(_npcs),
        SettingsStorage.instance.save(_settings),
        EconomyMetrics.global.persist(),
      ]).timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[GameShell] Final save on exit failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > TWLayout.largeScreenMinWidth) {
          return _buildLargeScreenLayout(constraints.maxWidth);
        }
        return _buildSmallScreenLayout();
      },
    );
  }

  Widget _buildSmallScreenLayout() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cosmic Trader'),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([
              AudioService.isMusicEnabled,
              AudioService.isPlaying,
            ]),
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EqualizerWidget(
                    bandCount: 14,
                    barWidth: 2.5,
                    barSpacing: 1.5,
                    height: 18,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => AudioService.instance.toggleMusicEnabled(),
                    child: Icon(
                      AudioService.isMusicEnabled.value
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      size: 20,
                      color: AudioService.isMusicEnabled.value
                          ? null
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(
              _currentIndex == 6
                  ? Icons.settings_rounded
                  : Icons.settings_outlined,
            ),
            onPressed: () => setState(() => _currentIndex = 6),
            tooltip: 'Settings',
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: _handleLogout,
            tooltip: 'Logout',
          ),
          IconButton(
            icon: const Icon(Icons.power_settings_new_rounded),
            onPressed: _handleExitGame,
            tooltip: 'Exit Game',
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              HudStrip(
                player: _player,
                sector: _currentHudSector,
                dominantFaction: _dominantFaction(),
              ),
              Expanded(
                child: IndexedStack(
                  index: _currentIndex,
                  children: [
                    SectorView(
                      key: _universeKey,
                      npcs: _npcs,
                      player: _player,
                      onPlayerUpdate: _updatePlayer,
                      onRefreshNpcs: _reloadNpcs,
                      onOpenPort: () => setState(() => _currentIndex = 4),
                      onOpenPlanet: _openPlanet,
                      fedSpaceEnd: _settings.fedSpaceEnd,
                    ),
                    GalaxyMap(
                      key: _universeKey,
                      npcs: _npcs,
                      currentSectorId: _player.currentSectorId,
                      onSectorSelected: _onSectorSelected,
                    ),
                    ShipStatusView(
                        player: _player, onPlayerUpdate: _updatePlayer),
                    ComputerScreen(
                      key: _universeKey,
                      player: _player,
                      onPlayerUpdate: _updatePlayer,
                    ),
                    PortScreen(
                      key: _universeKey,
                      player: _player,
                      onPlayerUpdate: _updatePlayer,
                    ),
                    PlanetScreen(
                      key: _planetKey,
                      player: _player,
                      onPlayerUpdate: _updatePlayer,
                    ),
                    SettingsScreen(
                      key: ValueKey('settings_${_settings.seed}'),
                      currentSettings: _settings,
                      onRegenerate: _handleRegenerateUniverse,
                      onSettingsChanged: _handleSettingsChanged,
                      automationTickIntervalSeconds:
                          _tickService.tickInterval.inSeconds,
                      automationTickPaused: _tickPaused,
                      onAutomationTickIntervalChanged:
                          _setAutomationTickInterval,
                      onAutomationTickPausedChanged: _setAutomationTickPaused,
                      automationPlayerCredits: _player.credits,
                      automationPlayerScrapMetal: _player.scrapMetal,
                      automationPlayerScrapTech: _player.scrapTech,
                      automationPlayerEnergy: _player.energy,
                      automationPlayerMaxEnergy: _player.maxEnergy,
                      onAutomationGrantCredits: _grantAutomationCredits,
                      onAutomationGrantScrapMetal: _grantAutomationScrapMetal,
                      onAutomationGrantScrapTech: _grantAutomationScrapTech,
                      onAutomationDrainPlayerEnergy:
                          _drainAutomationPlayerEnergy,
                      onAutomationDrainNpcEnergy: _drainAutomationNpcEnergy,
                      onAutomationDumpDiagnostics: _dumpTradeDiagnostics,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex < 6 ? _currentIndex : 0,
        onDestinationSelected: (index) => setState(() {
          _currentIndex = index;
          if (index == 3) _computerKey = UniqueKey();
          if (index == 5) _planetKey = UniqueKey();
          _tickService.playerDocked = (index == 4 || index == 5);
        }),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined),
            selectedIcon: Icon(Icons.location_on_rounded),
            label: 'Sector',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Galaxy Map',
          ),
          NavigationDestination(
            icon: Icon(Icons.rocket_launch_outlined),
            selectedIcon: Icon(Icons.rocket_launch_rounded),
            label: 'Ship',
          ),
          NavigationDestination(
            icon: Icon(Icons.computer_outlined),
            selectedIcon: Icon(Icons.computer_rounded),
            label: 'Computer',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store_rounded),
            label: 'Port',
          ),
          NavigationDestination(
            icon: Icon(Icons.public_outlined),
            selectedIcon: Icon(Icons.public_rounded),
            label: 'Planet',
          ),
        ],
      ),
    );
  }

  Widget _buildLargeScreenLayout(double maxWidth) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cosmic Trader'),
        actions: [
          ListenableBuilder(
            listenable: Listenable.merge([
              AudioService.isMusicEnabled,
              AudioService.isPlaying,
            ]),
            builder: (context, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  EqualizerWidget(
                    bandCount: 14,
                    barWidth: 2.5,
                    barSpacing: 1.5,
                    height: 18,
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => AudioService.instance.toggleMusicEnabled(),
                    child: Icon(
                      AudioService.isMusicEnabled.value
                          ? Icons.music_note_rounded
                          : Icons.music_off_rounded,
                      size: 20,
                      color: AudioService.isMusicEnabled.value
                          ? null
                          : Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.4),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // Left Navigation Rail
          IntrinsicWidth(
            child: Container(
              color: Theme.of(context).scaffoldBackgroundColor,
              child: Column(
                children: [
                  Expanded(
                    child: NavigationRail(
                      // NavigationRail's built-in scrolling keeps all
                      // destinations available when a short desktop panel
                      // cannot fit the full labelled rail.
                      scrollable: true,
                      minWidth: 88,
                      selectedIndex: _currentIndex < 6 ? _currentIndex : 0,
                      onDestinationSelected: (index) => setState(() {
                        _currentIndex = index;
                        if (index == 3) _computerKey = UniqueKey();
                        if (index == 5) _planetKey = UniqueKey();
                        _tickService.playerDocked = (index == 4 || index == 5);
                      }),
                      labelType: NavigationRailLabelType.all,
                      destinations: const [
                        NavigationRailDestination(
                          icon: Icon(Icons.location_on_outlined),
                          selectedIcon: Icon(Icons.location_on_rounded),
                          label: Text('Sector'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.map_outlined),
                          selectedIcon: Icon(Icons.map_rounded),
                          label: Text('Galaxy Map'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.rocket_launch_outlined),
                          selectedIcon: Icon(Icons.rocket_launch_rounded),
                          label: Text('Ship'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.computer_outlined),
                          selectedIcon: Icon(Icons.computer_rounded),
                          label: Text('Computer'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.store_outlined),
                          selectedIcon: Icon(Icons.store_rounded),
                          label: Text('Port'),
                        ),
                        NavigationRailDestination(
                          icon: Icon(Icons.public_outlined),
                          selectedIcon: Icon(Icons.public_rounded),
                          label: Text('Planet'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Bottom buttons (Settings + Logout)
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton.icon(
                      onPressed: () => setState(() => _currentIndex = 6),
                      icon: Icon(
                        _currentIndex == 6
                            ? Icons.settings_rounded
                            : Icons.settings_outlined,
                        size: 18,
                      ),
                      label: const Text('Settings'),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton.icon(
                      onPressed: _handleLogout,
                      icon: const Icon(Icons.logout_rounded, size: 18),
                      label: const Text('Logout'),
                    ),
                  ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton.icon(
                      onPressed: _handleExitGame,
                      icon: const Icon(Icons.power_settings_new_rounded,
                          size: 18),
                      label: const Text('Exit Game'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(thickness: 1, width: 1),

          // Main Content Area
          Expanded(
            child: Stack(
              children: [
                Column(
                  children: [
                    HudStrip(
                      player: _player,
                      sector: _currentHudSector,
                      dominantFaction: _dominantFaction(),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: _currentIndex,
                        children: [
                          SectorView(
                            key: _universeKey,
                            npcs: _npcs,
                            player: _player,
                            onPlayerUpdate: _updatePlayer,
                            onRefreshNpcs: _reloadNpcs,
                            onOpenPort: () => setState(() => _currentIndex = 4),
                            onOpenPlanet: _openPlanet,
                            fedSpaceEnd: _settings.fedSpaceEnd,
                          ),
                          GalaxyMap(
                            key: _universeKey,
                            npcs: _npcs,
                            currentSectorId: _player.currentSectorId,
                            onSectorSelected: _onSectorSelected,
                          ),
                          ShipStatusView(
                              player: _player, onPlayerUpdate: _updatePlayer),
                          ComputerScreen(
                            key: _computerKey,
                            player: _player,
                            onPlayerUpdate: _updatePlayer,
                          ),
                          PortScreen(
                            key: _universeKey,
                            player: _player,
                            onPlayerUpdate: _updatePlayer,
                          ),
                          PlanetScreen(
                            key: _planetKey,
                            player: _player,
                            onPlayerUpdate: _updatePlayer,
                          ),
                          SettingsScreen(
                            key: ValueKey('settings_${_settings.seed}'),
                            currentSettings: _settings,
                            onRegenerate: _handleRegenerateUniverse,
                            onSettingsChanged: _handleSettingsChanged,
                            automationTickIntervalSeconds:
                                _tickService.tickInterval.inSeconds,
                            automationTickPaused: _tickPaused,
                            onAutomationTickIntervalChanged:
                                _setAutomationTickInterval,
                            onAutomationTickPausedChanged:
                                _setAutomationTickPaused,
                            automationPlayerCredits: _player.credits,
                            automationPlayerScrapMetal: _player.scrapMetal,
                            automationPlayerScrapTech: _player.scrapTech,
                            automationPlayerEnergy: _player.energy,
                            automationPlayerMaxEnergy: _player.maxEnergy,
                            onAutomationGrantCredits: _grantAutomationCredits,
                            onAutomationGrantScrapMetal:
                                _grantAutomationScrapMetal,
                            onAutomationGrantScrapTech:
                                _grantAutomationScrapTech,
                            onAutomationDrainPlayerEnergy:
                                _drainAutomationPlayerEnergy,
                            onAutomationDrainNpcEnergy:
                                _drainAutomationNpcEnergy,
                            onAutomationDumpDiagnostics: _dumpTradeDiagnostics,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
