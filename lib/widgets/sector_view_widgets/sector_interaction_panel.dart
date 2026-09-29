import 'dart:math';

import 'package:flutter/material.dart' hide Hero;
import 'package:cosmic_trader/core/faction_colors.dart';
import 'package:cosmic_trader/core/ui_scale.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/game_settings.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/ship_equipment_types.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/npc_storage.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_canvas.dart';
import 'package:cosmic_trader/widgets/avatar/npc_portrait.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';
import 'package:cosmic_trader/widgets/combat_screen.dart';
import 'package:cosmic_trader/widgets/npc_trade_dialog.dart';
import 'package:cosmic_trader/services/energy_service.dart';

const _factionIcons = {
  FactionClass.trader: Icons.shopping_cart_rounded,
  FactionClass.duran: Icons.shield_rounded,
  FactionClass.vinari: Icons.science_rounded,
  FactionClass.pirate: Icons.local_fire_department_rounded,
};

class SectorInteractionPanel extends StatefulWidget {
  final Sector currentSector;
  final List<NpcShip> npcs;
  final Player player;
  final Function(Player) onPlayerUpdate;
  final VoidCallback? onRefreshNpcs;
  final int fedSpaceEnd;
  final VoidCallback? onLandOnPlanet;

  /// Universe settings, for post-death clone reissue in player combat and for
  /// `planetsPerSector` when firing a Genesis Torpedo.
  final GameSettings settings;

  /// Worlds a sector may hold before a torpedo would over-stack it. Fixed at
  /// universe creation, so every sector in a given galaxy obeys the same
  /// physics.
  int get worldCap => settings.planetsPerSector;

  const SectorInteractionPanel({
    super.key,
    required this.currentSector,
    this.npcs = const [],
    required this.player,
    required this.onPlayerUpdate,
    this.onRefreshNpcs,
    this.fedSpaceEnd = 0,
    this.onLandOnPlanet,
    required this.settings,
  });

  bool get isFedSpace =>
      fedSpaceEnd > 0 && player.currentSectorId <= fedSpaceEnd;

  @override
  State<SectorInteractionPanel> createState() => _SectorInteractionPanelState();
}

class _SectorInteractionPanelState extends State<SectorInteractionPanel> {
  String? _selectedId;

  @override
  void didUpdateWidget(SectorInteractionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentSector.id != widget.currentSector.id) {
      _selectedId = null;
    }
  }

  List<_SectorEntry> _getEntries() {
    final entries = <_SectorEntry>[];
    final s = widget.currentSector;

    if (s.navHaz) {
      entries.add(_SectorEntry(
        id: 'haz_${s.id}',
        type: _EntryType.hazard,
        label: 'NAVIGATION HAZARD',
        detail: 'Debris field. Warp navigation impaired.',
        color: Colors.orange,
        icon: Icons.warning_amber_rounded,
      ));
    }

    if (s.anomaly != null) {
      entries.add(_SectorEntry(
        id: 'anom_${s.id}',
        type: _EntryType.anomaly,
        label: 'SPACE ANOMALY',
        detail: s.anomaly!,
        color: Colors.purple,
        icon: Icons.auto_awesome_rounded,
      ));
    }

    // Live NPC ships in this sector
    for (final npc in widget.npcs) {
      if (npc.isDestroyed) continue;
      final color = factionColor(npc.faction);
      entries.add(_SectorEntry(
        id: 'npc_${npc.id}',
        type: _EntryType.npc,
        npcShip: npc,
        label: npc.shipName.toUpperCase(),
        detail:
            '${npc.shipDef.name}  •  ${npc.shipDef.shipClass.name.toUpperCase()}  •  ${npc.personality.name.toUpperCase().replaceAll('_', ' ')}  •  HP ${npc.hull}/${npc.maxHull}  SH ${npc.shields}/${npc.maxShields}',
        color: color,
        icon: _factionIcons[npc.faction] ?? Icons.directions_boat_rounded,
      ));
    }

    // Every world in this sector, one entry each. A three-world sector is three
    // distinct things you can scan and land on, and the entry id carries the
    // planet's own stable id rather than the sector's — the sector no longer
    // identifies which world is meant.
    for (final p in s.planets) {
      entries.add(_SectorEntry(
        id: 'planet_${p.id}',
        type: _EntryType.planet,
        planet: p,
        label: p.name.toUpperCase(),
        detail: p.isHomeworld && p.homeworldOf != null
            ? '${p.planetType}  •  ${p.homeworldOf!.name.toUpperCase()} HOMEWORLD'
            : '${p.planetType}  •  ${p.scanned ? (p.owner != null ? 'OWNED: ${p.owner!.name.toUpperCase()}' : 'UNCLAIMED') : 'NOT SCANNED'}',
        color: Colors.brown,
        icon: Icons.public_rounded,
      ));
    }

    // A torpedo is fired at an **orbit**, not at a world, so it gets its own
    // entry rather than a button on some existing world. Shown whenever there
    // is room, and kept when over-stacked: firing past the cap is allowed, it
    // is just a warning (see `WorldForging`).
    if (widget.player.genesisTorpedoes > 0) {
      final used = s.worldSlotsUsed;
      // At the cap is *full*, not unstable: the warning is for the shot that
      // would go past it.
      final over = used >= widget.worldCap;
      entries.add(_SectorEntry(
        id: 'genesis_${s.id}',
        type: _EntryType.genesis,
        label: over ? 'LAUNCH (UNSTABLE)' : 'LAUNCH TORPEDO',
        detail: over
            ? 'NO FREE SLOTS · $used/${widget.worldCap} worlds · collision risk'
            : 'Creates a random world · ${widget.player.genesisTorpedoes} held '
                '· $used/${widget.worldCap} slots used',
        color: over ? Colors.red.shade400 : Colors.deepPurple.shade300,
        icon: Icons.blur_circular_rounded,
      ));
    }

    return entries;
  }

  Future<void> _handleScan(_SectorEntry entry) async {
    if (entry.npcShip case final npc?) {
      if (!mounted) return;
      widget.onPlayerUpdate(
        widget.player.withFactionStandingChange(npc.faction, 1),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('SCAN — ${npc.shipName}'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _detailRow('Ship', npc.shipDef.name),
                  _detailRow('Class', npc.shipDef.shipClass.name.toUpperCase()),
                  _detailRow('Faction', npc.faction.name.toUpperCase()),
                  _detailRow('Personality', npc.personality.name.toUpperCase()),
                  _detailRow('Hull', '${npc.hull}/${npc.maxHull}'),
                  _detailRow('Shields', '${npc.shields}/${npc.maxShields}'),
                  _detailRow('Credits', '${npc.credits} cr'),
                  _detailRow('Cargo', '${npc.cargoUsed} units'),
                  _detailRow('Sector', '#${npc.currentSectorId}'),
                  const SizedBox(height: 8),
                  Text(
                    'Weapons:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.cyan.shade300,
                      fontSize: 11,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final e in npc.weaponSlots.entries)
                    Text(
                      () {
                        final idx = npc.shipDef.weaponSlots.indexOf(e.key);
                        final wt = (idx >= 0 &&
                                idx < npc.shipDef.preferredWeapons.length)
                            ? npc.shipDef.preferredWeapons[idx]
                            : null;
                        final typeName = wt?.name.replaceAllMapped(
                                RegExp(r'[A-Z]'), (m) => ' ${m.group(0)}') ??
                            e.key;
                        final dmg = wt != null ? wt.damage * e.value : 0;
                        return '  $typeName Lv${e.value}  ${dmg}dmg';
                      }(),
                      style: const TextStyle(
                          fontSize: 11, fontFamily: 'monospace'),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      });
      return;
    }

    if (entry.type == _EntryType.genesis) {
      _launchTorpedo();
      return;
    }

    if (entry.type == _EntryType.planet) {
      // Resolve by the entry's id, not by position. A tap on the third world in
      // the list has to open the third world, and "first match" would open the
      // first one every time.
      final planet = entry.planet;
      if (planet == null) return;

      if (!planet.scanned) {
        if (!EnergyService.canQuickScan(widget.player)) {
          if (!mounted) return;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            showDialog(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Scan Failed'),
                content: Text(
                  'Not enough energy remaining (${EnergyService.quickScanCost} required).',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
          });
          return;
        }
        widget.onPlayerUpdate(
          widget.player.spendEnergy(EnergyService.quickScanCost),
        );
        planet.scanned = true;
        await UniverseStorage.instance.saveSectors([widget.currentSector]);
        ActionLogProvider.global.info(
          'Scan complete: ${planet.name} — ${planet.planetType}',
        );
      }

      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(planet.name),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (planet.imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ConstrainedBox(
                          // AlertDialog measures its content with an
                          // IntrinsicWidth. A double.infinity width on the
                          // image makes that measurement infinite. Keep a
                          // finite maximum so the image can still shrink
                          // with the dialog on smaller panels.
                          constraints: const BoxConstraints(maxWidth: 220),
                          child: Image.asset(
                            planet.imagePath!,
                            height: 120,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => Container(
                              height: 120,
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              child: Center(
                                child: Icon(
                                  Icons.image_not_supported_rounded,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.3),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  _detailRow('Type', 'Planet Type: ${planet.planetType}'),
                  _detailRow('Atmosphere', planet.atmosphere),
                  _detailRow('Population', planet.population.toString()),
                  _detailRow('Level', planet.level.toString()),
                  if (planet.owner != null)
                    _detailRow('Owner', planet.owner!.displayName),
                  _detailRow(
                      'Status', planet.isHomeworld ? 'HOMEWORLD' : 'Colony'),
                  const SizedBox(height: 8),
                  _detailRow('Shields',
                      '${planet.shield.toInt()} / ${planet.maxShield.toInt()}'),
                  _detailRow('Armor',
                      '${planet.hull.toInt()} / ${planet.maxHull.toInt()}'),
                  _detailRow('Defense Level', '${planet.defenseLevel} / 4'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      });
      return;
    }
  }

  Future<void> _handleHail(_SectorEntry entry) async {
    if (entry.npcShip case final npc?) {
      final factionData = Faction.allFactions().firstWhere(
        (f) => f.factionClass == npc.faction,
        orElse: () => Faction.allFactions().first,
      );
      // Living legends (C4c) hail as themselves: title, bio, legend.
      Hero? hero;
      if (npc.heroName != null) {
        for (final h in factionData.notableHeroes) {
          if (h.name == npc.heroName) hero = h;
        }
      }
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(hero != null
              ? 'HAIL — ${hero.name}, ${npc.heroTitle ?? hero.title}'
              : 'HAIL — ${npc.shipName}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Ship', npc.shipName),
                _detailRow('Faction', factionData.name),
                if (hero != null) ...[
                  Text(
                    hero.shortBio,
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Legend: ${hero.notableAchievement}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.shade200,
                    ),
                  ),
                  const SizedBox(height: 12),
                ] else
                  Text(
                    factionData.background,
                    style: const TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic),
                  ),
                if (hero == null) const SizedBox(height: 12),
                Text(
                  'Personality: ${npc.personality.name.toUpperCase().replaceAll('_', ' ')}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.amber.shade300,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  factionData.philosophy,
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _handleTrade(_SectorEntry entry) async {
    if (entry.npcShip case final npc?) {
      if (!mounted) return;
      GameTickService.lockNpc(npc.id);
      try {
        await showDialog<bool>(
          context: context,
          builder: (ctx) => NpcTradeDialog(
            player: widget.player,
            npc: npc,
            onTradeComplete: (updatedPlayer, updatedNpc) async {
              widget.onPlayerUpdate(updatedPlayer);
              final allNpcs = await NpcStorage().loadAll();
              final updatedList =
                  allNpcs.map((n) => n.id == npc.id ? updatedNpc : n).toList();
              await NpcStorage().saveAll(updatedList);
              ActionLogProvider.global.trade(
                'Traded with ${npc.shipName} — '
                '${updatedPlayer.credits > widget.player.credits ? '+' : ''}'
                '${updatedPlayer.credits - widget.player.credits} cr',
              );
              widget.onRefreshNpcs?.call();
            },
          ),
        );
      } finally {
        GameTickService.unlockNpc(npc.id);
      }
    }
  }

  Future<void> _handleAttack(_SectorEntry entry) async {
    if (entry.npcShip case final npc?) {
      if (npc.isDestroyed) return;
      if (!mounted) return;

      GameTickService.lockNpc(npc.id);
      try {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => CombatScreen(
              player: widget.player,
              npc: npc,
              settings: widget.settings,
              onCombatEnd: (updatedPlayer, updatedNpc) async {
                widget.onPlayerUpdate(updatedPlayer);
                final allNpcs = await NpcStorage().loadAll();
                // Player kills make witnesses (vendetta symmetry with C1c):
                // same-faction onlookers record the pilot's id.
                if (updatedNpc.isDestroyed) {
                  NpcAiService.noteWitnessedKill(
                    allNpcs: allNpcs,
                    victimId: npc.id,
                    victimFaction: npc.faction,
                    sectorId: updatedNpc.currentSectorId,
                    killerId: updatedPlayer.id,
                    killerName: updatedPlayer.name,
                  );
                }
                final updatedList = allNpcs
                    .map((n) => n.id == npc.id ? updatedNpc : n)
                    .toList();
                await NpcStorage().saveAll(updatedList);
                widget.onRefreshNpcs?.call();
              },
            ),
          ),
        );
      } finally {
        GameTickService.unlockNpc(npc.id);
      }
    }
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: UiScale.spacing(2)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: Colors.white54,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  void _handleInteraction(String type, _SectorEntry entry) {
    switch (type) {
      case 'scan':
        _handleScan(entry);
      case 'hail':
        _handleHail(entry);
      case 'trade':
        _handleTrade(entry);
      case 'attack':
        _handleAttack(entry);
      case 'land':
        _handleLand(entry);
    }
  }

  void _handleLand(_SectorEntry entry) {
    widget.onLandOnPlanet?.call();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final entries = _getEntries();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.radar, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'SECTOR CONTENTS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: cs.tertiaryContainer.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${entries.length} detected',
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.tertiary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: entries.isEmpty
                ? _emptySectorMessage()
                : SizedBox(
                    height: _listHeight(entries.length),
                    child: _buildEntriesList(entries),
                  ),
          ),
        ],
      ),
    );
  }

  /// Height of one entry tile.
  ///
  /// Shared by the tile and [_listHeight] so the scroll extent cannot drift from
  /// what the tiles actually are — the same lesson as the gallery's thumbnail
  /// strip, whose hard-coded `thumbnailSize + spacing(30)` overflowed as soon as
  /// a caller passed a different size.
  ///
  /// Fixed height is only safe because the tile's captions are capped to one
  /// line, so the content cannot grow. 120 is the measured minimum: it has to fit
  /// a 46px portrait, a two-line caption block, and the expanded interaction
  /// buttons, and 112 overflowed by 4px in the expanded state.
  /// `test/npc_portrait_widget_test.dart` guards both the collapsed and expanded
  /// tile at 360px and 420px.
  static const double _kEntryTileHeight = 120.0;

  double _listHeight(int entryCount) {
    const tileHeight = _kEntryTileHeight;
    const separatorHeight = 6.0;
    const maxVisible = 5;
    final total =
        (tileHeight * entryCount) + (separatorHeight * (entryCount - 1));
    final maxHeight =
        (tileHeight * maxVisible) + (separatorHeight * (maxVisible - 1));
    return total.clamp(0, maxHeight);
  }

  Widget _buildEntriesList(List<_SectorEntry> entries) {
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      separatorBuilder: (_, __) => SizedBox(height: UiScale.spacing(6)),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _entryTile(entry);
      },
    );
  }

  Widget _emptySectorMessage() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline,
              size: 32, color: Colors.green.shade700),
          const SizedBox(height: 8),
          Text(
            'SECTOR CLEAR',
            style: TextStyle(
              color: Colors.green.shade700,
              fontSize: 12,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'No ships, hazards, or anomalies detected.',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryTile(_SectorEntry entry) {
    final isSelected = _selectedId == entry.id;
    final npc = entry.npcShip;

    return Container(
      height: _kEntryTileHeight,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: entry.color.withValues(alpha: isSelected ? 0.2 : 0.1),
        border: Border.all(color: entry.color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // NPCs get a face; planets, hazards, and anomalies keep their
              // icon, because there is nothing to depict a mountain as.
              if (npc != null)
                AvatarPortraitView(
                  portrait: NpcPortraits.of(npc),
                  size: 46,
                )
              else
                Icon(entry.icon, size: 18, color: entry.color),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.label,
                      // Single-line: the tile has a fixed height, and a long
                      // ship name wrapping would overflow the panel.
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'monospace',
                      ),
                    ),
                    Text(
                      entry.detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                IconButton(
                  icon: Icon(Icons.close_rounded, size: 16, color: entry.color),
                  onPressed: () => setState(() => _selectedId = null),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Close',
                ),
            ],
          ),
          const Spacer(),
          if (isSelected)
            _interactionButtons(entry)
          else
            TextButton(
              onPressed: () {
                setState(() => _selectedId = entry.id);
              },
              child: Text(
                '[ SELECT ]',
                style: TextStyle(
                  color: entry.color,
                  fontSize: 10,
                  fontFamily: 'monospace',
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Fires a Genesis Torpedo into this sector.
  ///
  /// The over-stack case asks first, and the dialog is unmissable on purpose: a
  /// silent destabilisation that destroys a million-colonist colony overnight
  /// reads as a bug, not as a risk the player chose to take.
  Future<void> _launchTorpedo() async {
    final sector = widget.currentSector;
    final over = sector.isFull(widget.worldCap);

    if (over) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: Icon(Icons.warning_amber_rounded, color: Colors.red.shade400),
          title: const Text('Unstable orbit'),
          content: Text(
            '${sector.name} already holds ${sector.worldSlotsUsed} worlds '
            'against a limit of ${widget.worldCap}.\n\n'
            'Over-stacking is legal, and it is also a weapon: a gravity check is '
            'rolled every 24 hours and two colliding worlds are destroyed, '
            'colony and all. The roll does not care that you are watching.\n\n'
            'Fire anyway?',
            style: const TextStyle(height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade700,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Fire torpedo'),
            ),
          ],
        ),
      );
      if (go != true) return;
    }

    final (result, world) = WorldForging.launch(
      player: widget.player,
      sector: sector,
      cap: widget.worldCap,
      rng: Random(),
    );

    if (result == LaunchResult.noTorpedoes) {
      _toast('No Genesis Torpedoes. Hardware emporiums stock them.');
      return;
    }
    if (result == LaunchResult.holdFull) {
      _toast('Cargo hold is full — no room for the torpedo.');
      return;
    }
    if (world == null) return;

    // The torpedo is consumed even when the launch over-stacks: the item was
    // fired, and owning the risk is the whole point.
    final spent = widget.player.copyWith(
      genesisTorpedoes: widget.player.genesisTorpedoes - 1,
      cargoUsed: widget.player.cargoUsed + WorldForging.cargoPerUnit,
    );
    widget.onPlayerUpdate(spent);
    await UniverseStorage.instance.saveSectors([sector]);
    ActionLogProvider.global.trade(
      'Genesis Torpedo fired in ${sector.name}: a new ${world.planetType} '
      'world, ${world.name}',
    );
    widget.onRefreshNpcs?.call();
    if (!mounted) return;
    setState(() {});
    _toast(over
        ? '${world.planetType} world created — ${sector.name} is now UNSTABLE'
        : '${world.planetType} world created: ${world.name}');
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        duration: const Duration(seconds: 3),
      ));
  }

  Widget _interactionButtons(_SectorEntry entry) {
    // A torpedo is fired at the orbit, not at a world, so it has no per-world
    // buttons — the entry itself is the action.
    if (entry.type == _EntryType.genesis) {
      return const SizedBox.shrink();
    }

    if (entry.type == _EntryType.planet) {
      return Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          _interactionButton(
            icon: Icons.science_rounded,
            label: 'SCAN',
            color: Colors.cyan,
            onTap: () => _handleInteraction('scan', entry),
          ),
          _interactionButton(
            icon: Icons.public_rounded,
            label: 'LAND',
            color: Colors.brown,
            onTap: () => _handleInteraction('land', entry),
          ),
        ],
      );
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _interactionButton(
          icon: Icons.science_rounded,
          label: 'SCAN',
          color: Colors.cyan,
          onTap: () => _handleInteraction('scan', entry),
        ),
        if (entry.type != _EntryType.hazard && entry.type != _EntryType.anomaly)
          _interactionButton(
            icon: Icons.chat_rounded,
            label: 'HAIL',
            color: Colors.white70,
            onTap: () => _handleInteraction('hail', entry),
          ),
        if (_canTrade(entry))
          _interactionButton(
            icon: Icons.shopping_cart_rounded,
            label: 'TRADE',
            color: Colors.green,
            onTap: () => _handleInteraction('trade', entry),
          ),
        if (entry.type != _EntryType.hazard &&
            entry.type != _EntryType.anomaly &&
            !widget.isFedSpace)
          _interactionButton(
            icon: Icons.local_fire_department_rounded,
            label: 'ATTACK',
            color: Colors.red,
            onTap: () => _handleInteraction('attack', entry),
          ),
      ],
    );
  }

  bool _canTrade(_SectorEntry entry) {
    if (entry.type != _EntryType.npc || entry.npcShip == null) return false;
    return entry.npcShip!.cargo.isNotEmpty;
  }

  Widget _interactionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: 8, vertical: UiScale.spacing(4)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _EntryType { hazard, anomaly, npc, planet, genesis }

class _SectorEntry {
  final String id;
  final _EntryType type;
  final String label;
  final String detail;
  final Color color;
  final IconData icon;
  final NpcShip? npcShip;

  /// The world this entry refers to, for planet entries.
  ///
  /// Carried on the entry rather than re-derived from the entry id at the point
  /// of use. Re-parsing an id string to find an object is the kind of coupling
  /// that breaks silently the moment the id format changes — and a planet entry's
  /// id and its world are created together, so there is no reason to separate
  /// them.
  final Planet? planet;

  const _SectorEntry({
    required this.id,
    required this.type,
    required this.label,
    required this.detail,
    required this.color,
    required this.icon,
    this.npcShip,
    this.planet,
  });
}
