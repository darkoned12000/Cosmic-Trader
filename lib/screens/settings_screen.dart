import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tradewars_2050/core/theme_service.dart';
import 'package:tradewars_2050/data/models/game_settings.dart';
import 'package:tradewars_2050/services/audio_service.dart';
import 'package:tradewars_2050/widgets/audio_settings_widget.dart';
import 'package:tradewars_2050/widgets/system_resources_widget.dart';

class SettingsScreen extends StatefulWidget {
  final GameSettings currentSettings;
  final ValueChanged<GameSettings> onRegenerate;
  final ValueChanged<GameSettings>? onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.currentSettings,
    required this.onRegenerate,
    this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _seedController;
  late TextEditingController _sectorCountController;
  late TextEditingController _portDensityController;
  late TextEditingController _planetDensityController;
  late TextEditingController _anomalyDensityController;
  late TextEditingController _hardwareEmporiumDensityController;
  late TextEditingController _traderDensityController;
  late TextEditingController _duranDensityController;
  late TextEditingController _vinariDensityController;
  late TextEditingController _pirateDensityController;
  late TextEditingController _mineralPriceMinController;
  late TextEditingController _mineralPriceMaxController;
  late TextEditingController _organicsPriceMinController;
  late TextEditingController _organicsPriceMaxController;
  late TextEditingController _industrialPriceMinController;
  late TextEditingController _industrialPriceMaxController;
  late TextEditingController _mineralQtyMinController;
  late TextEditingController _mineralQtyMaxController;
  late TextEditingController _organicsQtyMinController;
  late TextEditingController _organicsQtyMaxController;
  late TextEditingController _industrialQtyMinController;
  late TextEditingController _industrialQtyMaxController;
  late TextEditingController _initTurnsController;
  late TextEditingController _initCreditsController;
  late TextEditingController _initHoldsController;
  late TextEditingController _initDronesController;
  late TextEditingController _warp1PctController;
  late TextEditingController _warp2PctController;
  late TextEditingController _warp3PctController;
  late TextEditingController _warp4PctController;
  late TextEditingController _warp5PctController;
  late TextEditingController _warp6PctController;
  late TextEditingController _warp7PctController;
  late bool _resetOnRegen;
  late bool _deleteAllPlayers;
  late bool _unlockAllShips;
  double _musicVolume = 0.5;
  double _sfxVolume = 0.7;

  @override
  void initState() {
    super.initState();
    final s = widget.currentSettings;
    _seedController = TextEditingController(
        text: s.rawSeed.isNotEmpty ? s.rawSeed : s.seed.toString());
    _sectorCountController =
        TextEditingController(text: s.totalSectors.toString());
    _portDensityController =
        TextEditingController(text: (s.portDensity * 100).toStringAsFixed(0));
    _planetDensityController =
        TextEditingController(text: (s.planetDensity * 100).toStringAsFixed(0));
    _anomalyDensityController = TextEditingController(
        text: (s.anomalyDensity * 100).toStringAsFixed(0));
    _hardwareEmporiumDensityController = TextEditingController(
        text: (s.hardwareEmporiumDensity * 100).toStringAsFixed(0));
    _traderDensityController =
        TextEditingController(text: (s.traderDensity * 100).toStringAsFixed(0));
    _duranDensityController =
        TextEditingController(text: (s.duranDensity * 100).toStringAsFixed(0));
    _vinariDensityController =
        TextEditingController(text: (s.vinariDensity * 100).toStringAsFixed(0));
    _pirateDensityController =
        TextEditingController(text: (s.pirateDensity * 100).toStringAsFixed(0));
    _mineralPriceMinController =
        TextEditingController(text: s.mineralPriceMin.toStringAsFixed(0));
    _mineralPriceMaxController =
        TextEditingController(text: s.mineralPriceMax.toStringAsFixed(0));
    _organicsPriceMinController =
        TextEditingController(text: s.organicsPriceMin.toStringAsFixed(0));
    _organicsPriceMaxController =
        TextEditingController(text: s.organicsPriceMax.toStringAsFixed(0));
    _industrialPriceMinController =
        TextEditingController(text: s.industrialPriceMin.toStringAsFixed(0));
    _industrialPriceMaxController =
        TextEditingController(text: s.industrialPriceMax.toStringAsFixed(0));
    _mineralQtyMinController =
        TextEditingController(text: s.mineralQtyMin.toString());
    _mineralQtyMaxController =
        TextEditingController(text: s.mineralQtyMax.toString());
    _organicsQtyMinController =
        TextEditingController(text: s.organicsQtyMin.toString());
    _organicsQtyMaxController =
        TextEditingController(text: s.organicsQtyMax.toString());
    _industrialQtyMinController =
        TextEditingController(text: s.industrialQtyMin.toString());
    _industrialQtyMaxController =
        TextEditingController(text: s.industrialQtyMax.toString());
    _initTurnsController = TextEditingController(text: s.initTurns.toString());
    _initCreditsController =
        TextEditingController(text: s.initCredits.toString());
    _initHoldsController = TextEditingController(text: s.initHolds.toString());
    _initDronesController =
        TextEditingController(text: s.initDrones.toString());
    _warp1PctController =
        TextEditingController(text: (s.pct1Warp * 100).toStringAsFixed(0));
    _warp2PctController =
        TextEditingController(text: (s.pct2Warp * 100).toStringAsFixed(0));
    _warp3PctController =
        TextEditingController(text: (s.pct3Warp * 100).toStringAsFixed(0));
    _warp4PctController =
        TextEditingController(text: (s.pct4Warp * 100).toStringAsFixed(0));
    _warp5PctController =
        TextEditingController(text: (s.pct5Warp * 100).toStringAsFixed(0));
    _warp6PctController =
        TextEditingController(text: (s.pct6Warp * 100).toStringAsFixed(0));
    _warp7PctController =
        TextEditingController(text: (s.pct7Warp * 100).toStringAsFixed(0));
    _resetOnRegen = s.resetPlayersOnRegen;
    _deleteAllPlayers = s.deleteAllPlayersOnRegen;
    _unlockAllShips = s.unlockAllShips;
    _musicVolume = s.musicVolume;
    _sfxVolume = s.sfxVolume;

    for (final c in [
      _warp1PctController,
      _warp2PctController,
      _warp3PctController,
      _warp4PctController,
      _warp5PctController,
      _warp6PctController,
      _warp7PctController,
    ]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _seedController.dispose();
    _sectorCountController.dispose();
    _portDensityController.dispose();
    _planetDensityController.dispose();
    _anomalyDensityController.dispose();
    _hardwareEmporiumDensityController.dispose();
    _traderDensityController.dispose();
    _duranDensityController.dispose();
    _vinariDensityController.dispose();
    _pirateDensityController.dispose();
    _mineralPriceMinController.dispose();
    _mineralPriceMaxController.dispose();
    _organicsPriceMinController.dispose();
    _organicsPriceMaxController.dispose();
    _industrialPriceMinController.dispose();
    _industrialPriceMaxController.dispose();
    _mineralQtyMinController.dispose();
    _mineralQtyMaxController.dispose();
    _organicsQtyMinController.dispose();
    _organicsQtyMaxController.dispose();
    _industrialQtyMinController.dispose();
    _industrialQtyMaxController.dispose();
    _initTurnsController.dispose();
    _initCreditsController.dispose();
    _initHoldsController.dispose();
    _initDronesController.dispose();
    _warp1PctController.dispose();
    _warp2PctController.dispose();
    _warp3PctController.dispose();
    _warp4PctController.dispose();
    _warp5PctController.dispose();
    _warp6PctController.dispose();
    _warp7PctController.dispose();
    super.dispose();
  }

  int _parseSeed(String text) {
    final parsed = int.tryParse(text);
    if (parsed != null) return parsed;
    return text.hashCode;
  }

  GameSettings _buildSettings() {
    return GameSettings(
      totalSectors: int.tryParse(_sectorCountController.text) ?? 50,
      seed: _parseSeed(_seedController.text),
      rawSeed: _seedController.text,
      portDensity: (double.tryParse(_portDensityController.text) ?? 35) / 100,
      planetDensity:
          (double.tryParse(_planetDensityController.text) ?? 25) / 100,
      anomalyDensity:
          (double.tryParse(_anomalyDensityController.text) ?? 10) / 100,
      hardwareEmporiumDensity:
          (double.tryParse(_hardwareEmporiumDensityController.text) ?? 5) / 100,
      traderDensity:
          (double.tryParse(_traderDensityController.text) ?? 12) / 100,
      duranDensity: (double.tryParse(_duranDensityController.text) ?? 10) / 100,
      vinariDensity:
          (double.tryParse(_vinariDensityController.text) ?? 8) / 100,
      pirateDensity:
          (double.tryParse(_pirateDensityController.text) ?? 5) / 100,
      fedSpaceEnd: 9,
      bubbleChance: 0.15,
      maxBubbleSize: 6,
      pct1Warp: (double.tryParse(_warp1PctController.text) ?? 10) / 100,
      pct2Warp: (double.tryParse(_warp2PctController.text) ?? 30) / 100,
      pct3Warp: (double.tryParse(_warp3PctController.text) ?? 28) / 100,
      pct4Warp: (double.tryParse(_warp4PctController.text) ?? 15) / 100,
      pct5Warp: (double.tryParse(_warp5PctController.text) ?? 10) / 100,
      pct6Warp: (double.tryParse(_warp6PctController.text) ?? 5) / 100,
      pct7Warp: (double.tryParse(_warp7PctController.text) ?? 2) / 100,
      resetPlayersOnRegen: _resetOnRegen,
      deleteAllPlayersOnRegen: _deleteAllPlayers,
      unlockAllShips: _unlockAllShips,
      anomalyTypes: widget.currentSettings.anomalyTypes,
      mineralPriceMin: double.tryParse(_mineralPriceMinController.text) ?? 8,
      mineralPriceMax: double.tryParse(_mineralPriceMaxController.text) ?? 12,
      organicsPriceMin: double.tryParse(_organicsPriceMinController.text) ?? 16,
      organicsPriceMax: double.tryParse(_organicsPriceMaxController.text) ?? 24,
      industrialPriceMin:
          double.tryParse(_industrialPriceMinController.text) ?? 40,
      industrialPriceMax:
          double.tryParse(_industrialPriceMaxController.text) ?? 60,
      mineralQtyMin: int.tryParse(_mineralQtyMinController.text) ?? 10000,
      mineralQtyMax: int.tryParse(_mineralQtyMaxController.text) ?? 50000,
      organicsQtyMin: int.tryParse(_organicsQtyMinController.text) ?? 5000,
      organicsQtyMax: int.tryParse(_organicsQtyMaxController.text) ?? 40000,
      industrialQtyMin: int.tryParse(_industrialQtyMinController.text) ?? 3000,
      industrialQtyMax: int.tryParse(_industrialQtyMaxController.text) ?? 30000,
      initTurns: int.tryParse(_initTurnsController.text) ?? 1000,
      initCredits: int.tryParse(_initCreditsController.text) ?? 1000000,
      initHolds: int.tryParse(_initHoldsController.text) ?? 50,
      initDrones: int.tryParse(_initDronesController.text) ?? 100,
      musicVolume: _musicVolume,
      sfxVolume: _sfxVolume,
      musicFolderPath: AudioService.musicFolderPath.value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Settings',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
          const SizedBox(height: 16),

          // ==================== GAME THEME ====================
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.palette_rounded),
                title: Text('Game Theme',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                children: [
                  _themePicker(cs, theme),
                  _brightnessToggle(cs, theme),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ==================== UNIVERSE GENERATION ====================
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.public_rounded),
                title: Text('Universe Generation',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Size & Seed',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _intField(
                            'Total Sectors', _sectorCountController, 10, 500),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: TextField(
                            controller: _seedController,
                            decoration: InputDecoration(
                              labelText: 'Seed',
                              hintText: '0 / 12345 / "my universe"',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              isDense: true,
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: Text(
                            '0 = random (You can use any value like: "my universe"). '
                            'Current numerical seed value is: ${widget.currentSettings.seed}',
                            style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurface.withValues(alpha: 0.6)),
                          ),
                        ),

                        Text('Densities (percent)',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _pctField('Ports', _portDensityController),
                        _pctField('Planets', _planetDensityController),
                        _pctField('Anomalies', _anomalyDensityController),
                        _pctField(
                            'Hardware', _hardwareEmporiumDensityController),
                        _pctField('Trader NPCs', _traderDensityController),
                        _pctField('Duran NPCs', _duranDensityController),
                        _pctField('Vinari NPCs', _vinariDensityController),
                        _pctField('Pirate NPCs', _pirateDensityController),

                        const SizedBox(height: 24),

                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                  'Warp Distribution (must sum to 100%)',
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            TextButton.icon(
                              onPressed: _randomizeWarpDistribution,
                              icon: const Icon(Icons.shuffle_rounded, size: 16),
                              label: const Text('Randomize',
                                  style: TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _warpDistributionIndicator(),
                        const SizedBox(height: 8),
                        _pctField('1 Connection', _warp1PctController),
                        _pctField('2 Connections', _warp2PctController),
                        _pctField('3 Connections', _warp3PctController),
                        _pctField('4 Connections', _warp4PctController),
                        _pctField('5 Connections', _warp5PctController),
                        _pctField('6 Connections', _warp6PctController),
                        _pctField('7 Connections', _warp7PctController),

                        const SizedBox(height: 24),

                        Text('Economy (price ranges)',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _rangeField('Minerals', _mineralPriceMinController,
                            _mineralPriceMaxController),
                        _rangeField('Organics', _organicsPriceMinController,
                            _organicsPriceMaxController),
                        _rangeField('Industrial', _industrialPriceMinController,
                            _industrialPriceMaxController),

                        const SizedBox(height: 16),
                        Text('Economy (quantity ranges)',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _rangeField('Minerals', _mineralQtyMinController,
                            _mineralQtyMaxController,
                            isInt: true),
                        _rangeField('Organics', _organicsQtyMinController,
                            _organicsQtyMaxController,
                            isInt: true),
                        _rangeField('Industrial', _industrialQtyMinController,
                            _industrialQtyMaxController,
                            isInt: true),

                        const SizedBox(height: 24),

                        Text('Player Initial Values',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 12),
                        _intField('Turns', _initTurnsController, 1, 99999),
                        _intField(
                            'Credits', _initCreditsController, 0, 999999999),
                        _intField('Cargo Holds', _initHoldsController, 1, 999),
                        _intField('Drones', _initDronesController, 0, 9999),

                        const SizedBox(height: 24),

                        // ==================== ADVANCED OPTIONS ====================
                        Theme(
                          data:
                              theme.copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            initiallyExpanded: false,
                            title: Text('Advanced Options',
                                style: theme.textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.bold)),
                            children: [
                              CheckboxListTile(
                                value: _resetOnRegen,
                                onChanged: (v) =>
                                    setState(() => _resetOnRegen = v ?? true),
                                title: const Text(
                                    'Reset players to sector 1 on regen'),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              CheckboxListTile(
                                value: _unlockAllShips,
                                onChanged: (v) =>
                                    setState(() => _unlockAllShips = v ?? true),
                                title: const Text(
                                    'Unlock all ships on account creation'),
                                subtitle: const Text(
                                  'When off, only the default ship is selectable. '
                                  'Other ships are locked behind milestones.',
                                  style: TextStyle(fontSize: 11),
                                ),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                              CheckboxListTile(
                                value: _deleteAllPlayers,
                                onChanged: (v) => setState(
                                    () => _deleteAllPlayers = v ?? true),
                                title: const Text(
                                    'Delete all player accounts on regen'),
                                subtitle: const Text(
                                  'Permanently removes all saved player data. '
                                  'Use for testing new features.',
                                  style: TextStyle(fontSize: 11),
                                ),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Generate Button
                        FilledButton.icon(
                          onPressed: () =>
                              widget.onRegenerate(_buildSettings()),
                          icon: const Icon(Icons.auto_fix_high_rounded),
                          label: const Text('Generate New Universe',
                              style: TextStyle(fontSize: 16)),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ==================== VIDEO SETTINGS ====================
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: const Icon(Icons.video_settings_rounded),
                title: Text('Video Settings',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Tactical Display',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Animation speed for display effects is controlled '
                          'via the slider on the Tactical Display header.',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // ==================== AUDIO SETTINGS ====================
          AudioSettingsWidget(
            musicVolume: _musicVolume,
            sfxVolume: _sfxVolume,
            onMusicVolumeChanged: (v) {
              setState(() => _musicVolume = v);
              AudioService.musicVolume.value = v;
            },
            onSfxVolumeChanged: (v) {
              setState(() => _sfxVolume = v);
              AudioService.sfxVolume.value = v;
            },
            onSaveSettings: widget.onSettingsChanged,
            buildSettings: _buildSettings,
          ),

          const SizedBox(height: 12),

          // ==================== SYSTEM RESOURCES ===================
          const SystemResourcesWidget(),
          const SizedBox(height: 12),

          // ==================== ABOUT ====================
          Card(
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: false,
                leading: Icon(Icons.info_outline_rounded, color: cs.primary),
                title: Text('About',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TradeWars 2050',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'A sci-fi space trading and combat simulator. '
                          'Navigate the galaxy, trade commodities, battle NPCs, '
                          'capture ports, upgrade your ship, and build your empire. '
                          'Inspired by the classic TradeWars 2002.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.5,
                            color: cs.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Open Source',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Built with Flutter. Community-driven development.',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Audio / Music',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Music and sound effects provided by Eric Matyas.',
                          style: TextStyle(
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: () {
                            Clipboard.setData(const ClipboardData(
                                text: 'https://soundimage.org/sfx-scifi/'));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: const Text('Link copied to clipboard'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          },
                          child: Text(
                            'https://soundimage.org/sfx-scifi/',
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.primary,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Theme widgets
  // ---------------------------------------------------------------------------

  Widget _themePicker(ColorScheme cs, ThemeData theme) {
    final currentSeed = ThemeService.colorNotifier.value;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Colour Scheme',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: themePresets.map((preset) {
                final selected = preset.seed == currentSeed;
                return ChoiceChip(
                  selected: selected,
                  label:
                      Text(preset.name, style: const TextStyle(fontSize: 12)),
                  avatar: Icon(preset.icon, size: 18),
                  onSelected: (_) {
                    ThemeService.colorNotifier.value = preset.seed;
                  },
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _brightnessToggle(ColorScheme cs, ThemeData theme) {
    final isDark = ThemeService.brightnessNotifier.value == Brightness.dark;
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: cs.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(isDark ? 'Dark Mode' : 'Light Mode',
                  style: theme.textTheme.bodyLarge),
            ),
            Switch.adaptive(
              value: isDark,
              onChanged: (v) {
                ThemeService.brightnessNotifier.value =
                    v ? Brightness.dark : Brightness.light;
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  void _randomizeWarpDistribution() {
    final rng = math.Random();
    final values = List.generate(7, (_) => rng.nextDouble());
    final sum = values.fold(0.0, (a, b) => a + b);
    final List<int> pcts = values.map((v) => (v / sum * 100).round()).toList();
    var diff = 100 - pcts.fold(0, (a, b) => a + b);
    while (diff != 0) {
      for (int i = 0; i < 7 && diff != 0; i++) {
        if (diff > 0) {
          pcts[i]++;
          diff--;
        } else if (pcts[i] > 0) {
          pcts[i]--;
          diff++;
        }
      }
    }

    _warp1PctController.text = pcts[0].toString();
    _warp2PctController.text = pcts[1].toString();
    _warp3PctController.text = pcts[2].toString();
    _warp4PctController.text = pcts[3].toString();
    _warp5PctController.text = pcts[4].toString();
    _warp6PctController.text = pcts[5].toString();
    _warp7PctController.text = pcts[6].toString();
  }

  Widget _intField(String label, TextEditingController ctrl,
      [int? min, int? max]) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }

  Widget _rangeField(
    String label,
    TextEditingController minCtrl,
    TextEditingController maxCtrl, {
    bool isInt = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: minCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Min',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('–'),
          ),
          Expanded(
            child: TextField(
              controller: maxCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Max',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _warpDistributionIndicator() {
    final controllers = [
      _warp1PctController,
      _warp2PctController,
      _warp3PctController,
      _warp4PctController,
      _warp5PctController,
      _warp6PctController,
      _warp7PctController,
    ];

    final values = controllers.map((c) {
      return double.tryParse(c.text) ?? 0;
    }).toList();

    final total = values.fold(0.0, (a, b) => a + b);
    final ok = (total - 100).abs() < 0.5;

    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          size: 18,
          color: ok ? Colors.green : Colors.red.shade400,
        ),
        const SizedBox(width: 6),
        Text(
          'Total: ${total.toStringAsFixed(0)}% ${ok ? "✓" : "(must be 100%)"}',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: ok ? Colors.green : Colors.red.shade400,
          ),
        ),
      ],
    );
  }

  Widget _pctField(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(
          labelText: label,
          suffixText: '%',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      ),
    );
  }
}
