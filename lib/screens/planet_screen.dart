import 'dart:async';

import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';
import 'package:cosmic_trader/widgets/shared/stat_bar.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/services/colonist_supply.dart';

class PlanetScreen extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  /// Construction-speed preference, passed in rather than read from storage.
  ///
  /// `GameShell` already holds the loaded [GameSettings], so handing the value
  /// down keeps the level-up button synchronous. Reading storage inside the tap
  /// handler made levelling a world depend on an async disk load for no benefit,
  /// and in a widget test that await never completes at all.
  final double constructionTimeScale;

  const PlanetScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
    this.constructionTimeScale = 1.0,
  });

  @override
  State<PlanetScreen> createState() => _PlanetScreenState();
}

class _PlanetScreenState extends State<PlanetScreen> {
  List<Sector> _allSectors = [];
  bool _loading = true;

  /// Live refresh. Colony production runs on the game tick, which mutates the
  /// planet in place — the screen already holds the same object references, so
  /// the numbers were *current* and simply never repainted. That made a live
  /// colony look frozen until you left the tab and came back.
  ///
  /// A poll rather than a push, because the tick service has no notifier for
  /// this and adding one just for this screen is not worth the coupling. Guarded
  /// by [_fingerprint] so `setState` only fires when something actually moved —
  /// the tick is 30s, so the alternative is ~30 pointless rebuilds a minute.
  Timer? _refresh;

  /// Cheap digest of everything on the planet screen that the tick can change.
  int _fingerprint = 0;

  /// True while this screen has a write in flight.
  ///
  /// The reload in [_syncFromDisk] must not run during one, or it can read the
  /// file *before* the screen's own write lands and swap in a stale sector,
  /// visibly undoing the action the player just took.
  bool _writeInFlight = false;

  /// Writes this screen's copy of [sector] to disk, suppressing the poll.
  ///
  /// Every mutating action on this screen has to go through here rather than
  /// calling [UniverseStorage.saveSectors] directly, because the poll and the
  /// write race each other.
  Future<void> _persist(Sector sector) async {
    _writeInFlight = true;
    try {
      await UniverseStorage.instance.saveSectors([sector]);
    } finally {
      _writeInFlight = false;
    }
  }

  /// Which world in this sector the screen is showing.
  ///
  /// `null` means "the first one", which is the right default for a
  /// single-world sector and the only sane fallback before the universe loads.
  /// A sector can hold up to `planetsPerSector` worlds, and the screen can only
  /// show one at a time, so this is state the player controls.
  String? _selectedPlanetId;

  /// The world to display: the selection if it still exists, else the first
  /// living one, else the first of any.
  ///
  /// Falls back rather than going blank. A world can be destroyed or removed
  /// while its id is selected, and a screen that renders nothing at all is a
  /// far worse outcome than one that quietly shows a neighbour.
  Planet? _resolvePlanet(Sector? sector) =>
      sector == null ? null : _selectFrom(sector.planets);

  /// Picks the world to display out of [planets], honouring the selection.
  Planet? _selectFrom(List<Planet> planets) {
    if (planets.isEmpty) return null;
    final id = _selectedPlanetId;
    if (id != null) {
      for (final p in planets) {
        if (p.id == id) return p;
      }
    }
    return planets.where((p) => !p.isDestroyed).isNotEmpty
        ? planets.firstWhere((p) => !p.isDestroyed)
        : planets.first;
  }

  static int _fingerprintOf(Planet? p) {
    if (p == null) return 0;
    return Object.hash(
      p.storedMinerals,
      p.storedOrganics,
      p.storedIndustrial,
      p.storedDrones,
      p.population,
      p.colonistsMinerals,
      p.colonistsOrganics,
      p.colonistsIndustrial,
      p.colonistsDrones,
      p.level,
      p.shield,
      p.hull,
      p.owner,
      // The build countdown, so a running construction shows progress without
      // anything having to call setState when the tick decrements it.
      p.constructionTicksRemaining,
      p.constructionTarget,
    );
  }

  @override
  void initState() {
    super.initState();
    _loadUniverse();
    // Reload from disk rather than fingerprinting a private copy.
    //
    // This screen and [GameTickService] each call `loadUniverse()`, which
    // **parses a fresh object graph every time**. The tick decrements the
    // countdown on *its* copy and saves it; this screen was fingerprinting
    // *its own* copy, which nothing else mutates. So a running build appeared
    // frozen at whatever it was set to, forever, and then vanished on the way
    // out. The same divergence hid every production change made by the tick.
    //
    // Reading every second is affordable next to a tick that already re-reads
    // the whole file every 30s, and it is what makes the progress bar move
    // promptly: the countdown only actually changes once per tick, so this
    // polls for a change and repaints within a second of it happening.
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _syncFromDisk();
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
  }

  /// Re-reads the universe and swaps in the current sector if it changed.
  ///
  /// Swaps the whole list rather than merging, so the screen holds exactly what
  /// the tick last wrote. Only the selected world's id is carried across, since
  /// a re-parse produces new object identities and would otherwise reset the
  /// selection to slot 0 on every poll.
  Future<void> _syncFromDisk() async {
    if (_writeInFlight) return;
    final previousId = _currentSector?.id;
    final List<Sector> fresh;
    try {
      fresh = await UniverseStorage.instance.loadUniverse();
    } catch (_) {
      return; // a transient read failure must not blank the screen
    }
    if (!mounted || fresh.isEmpty) return;
    // A write that started while we were reading wins: the file we just read may
    // predate it, and clobbering it would make a button look inert.
    if (_writeInFlight) return;

    final next = _fingerprintOf(_resolvePlanetFrom(fresh));
    if (next == _fingerprint && previousId == _currentSector?.id) {
      _allSectors = fresh;
      return;
    }
    _fingerprint = next;
    setState(() {
      _allSectors = fresh;
    });
  }

  /// The selected world, resolving against an explicit sector list.
  Planet? _resolvePlanetFrom(List<Sector> all) {
    if (all.isEmpty) return null;
    final sector = all.firstWhere(
      (s) => s.id == widget.player.currentSectorId,
      orElse: () => all.first,
    );
    return _selectFrom(sector.planets);
  }

  Future<void> _loadUniverse() async {
    try {
      final sectors = await UniverseStorage.instance.loadUniverse();
      if (mounted) {
        setState(() {
          _allSectors = sectors;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Sector? get _currentSector {
    if (_allSectors.isEmpty) return null;
    return _allSectors.firstWhere(
      (s) => s.id == widget.player.currentSectorId,
      orElse: () => _allSectors.first,
    );
  }

  Future<void> _scanPlanet() async {
    final sector = _currentSector;
    final planet = _resolvePlanet(sector);
    if (sector == null || planet == null) return;

    if (planet.scanned) return;

    // Spend energy for the manual scan.
    if (!EnergyService.canScanPlanet(widget.player)) return;
    var updatedPlayer = widget.player.spendEnergy(EnergyService.planetScanCost);
    final ownerFaction = planet.owner;
    if (ownerFaction != null) {
      updatedPlayer = updatedPlayer.withFactionStandingChange(ownerFaction, 1);
    }
    widget.onPlayerUpdate(updatedPlayer);

    planet.scanned = true;
    await _persist(sector);
    ActionLogProvider.global.info(
      'Scan complete: ${planet.name} — ${planet.planetType}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final sector = _currentSector;
    final planet = _resolvePlanet(sector);

    if (sector == null || planet == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.public_rounded,
                  size: 64,
                  color: cs.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'No planet in this sector.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Travel to a sector with a planet to view it here.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (!planet.scanned) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Planet'),
          forceMaterialTransparency: true,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_rounded,
                  size: 64,
                  color: cs.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 16),
                Text(
                  'Planet detected in this sector.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Requires scan to identify.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withValues(alpha: 0.4),
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: EnergyService.canScanPlanet(widget.player)
                      ? _scanPlanet
                      : null,
                  icon: const Icon(Icons.science_rounded),
                  label: Text(
                      'Scan Planet (${EnergyService.planetScanCost} energy)'),
                ),
                if (!EnergyService.canScanPlanet(widget.player))
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Not enough energy',
                      style: TextStyle(
                        color: cs.error,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    // Scanned planet display
    return Scaffold(
      appBar: AppBar(
        title: Text(planet.name),
        forceMaterialTransparency: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sector.planets.length > 1) ...[
              _buildWorldSelector(sector, planet),
              const SizedBox(height: 12),
            ],
            // Planet header card — info left, image right
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      'Planet Type: ${planet.planetType}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  if (planet.isHomeworld) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.amber.withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(
                                          color: Colors.amber
                                              .withValues(alpha: 0.4),
                                        ),
                                      ),
                                      child: Text(
                                        'HOMEWORLD',
                                        style: TextStyle(
                                          fontSize: 8,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.amber,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Atmosphere: ${planet.atmosphere}',
                                style: TextStyle(
                                  color: cs.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _infoRow('Status',
                                  planet.isHomeworld ? 'Homeworld' : 'Colony'),
                              _infoRow('Colonists',
                                  _formatNumber(planet.population)),
                              _infoRow('Level',
                                  '${planet.level} ${_levelTitle(planet.level)}'),
                              if (planet.owner != null)
                                _infoRow('Owner',
                                    '${planet.owner!.displayName} (${planet.owner!.name.toUpperCase()})'),
                              if (planet.owner == null)
                                _infoRow('Claim', 'Unclaimed'),
                            ],
                          ),
                        ),
                      ),
                      if (planet.imagePath != null)
                        Expanded(
                          flex: 2,
                          child: Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.asset(
                                planet.imagePath!,
                                height: 100,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 100,
                                  color: cs.surfaceContainerHighest,
                                  child: Center(
                                    child: Icon(
                                        Icons.image_not_supported_rounded,
                                        color: cs.onSurface
                                            .withValues(alpha: 0.3)),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Same narrow-width fallback as Transfers / Level Up below. Two
            // halves of a 430px phone leaves each card ~198px, which is enough
            // for the bar but not for the "9.0K / 25.0K" readout beside it —
            // that had to be ellipsised to stop it overflowing, which made a
            // player's own stores unreadable. Stacking gives each card the
            // full width and the readout fits properly.
            LayoutBuilder(
              builder: (context, constraints) {
                final resources = _buildResourcesCard(planet, cs);
                final defense = _buildDefenseCard(planet, cs);
                if (constraints.maxWidth < 560) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      resources,
                      const SizedBox(height: 12),
                      defense,
                    ],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: resources),
                    const SizedBox(width: 12),
                    Expanded(child: defense),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            if (planet.population > 0) _buildColonyCard(planet, cs),
            if (planet.population > 0) const SizedBox(height: 12),
            // Actions / Management
            _buildActions(planet, cs),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(Planet planet, ColorScheme cs) {
    final isOwner = planet.owner == widget.player.faction;

    if (isOwner) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.flag_rounded,
                      size: 18, color: Colors.green.shade400),
                  const SizedBox(width: 8),
                  // Flexible: the faction display name is the only variable
                  // width part of this row, and at 430px it overflowed by
                  // 153px. The icon stays natural and the name ellipsises, so
                  // a long faction name can never push the header off-screen.
                  Expanded(
                    child: Text(
                      'Owned by ${widget.player.faction.displayName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.green.shade400,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Transfers and the level-up panel sit side by side on a wide
              // screen and stack on a narrow one.
              //
              // Pre-existing overflow, found by rendering this screen at 430px
              // rather than by reading it: two `Expanded` halves leave each
              // panel ~198px, and a transfer row needs its 80px label, the
              // stored/max readout, and two buttons. That overflowed by up to
              // 84px. It is the same `LayoutBuilder` fallback the faction
              // rankings screen uses for the same reason.
              LayoutBuilder(
                builder: (context, constraints) {
                  final transfers = _buildTransfersSection(planet, cs);
                  final levelUp = _buildLevelUpSection(planet, cs);
                  if (constraints.maxWidth < 560) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        transfers,
                        const SizedBox(height: 12),
                        levelUp,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: transfers),
                      const SizedBox(width: 12),
                      Expanded(child: levelUp),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      );
    }

    return Row(
      children: [
        if (planet.owner == null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _claimPlanet(planet),
              icon: const Icon(Icons.flag_rounded, size: 18),
              label: const Text('Claim'),
            ),
          ),
        if (planet.owner == null) const SizedBox(width: 12),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              ActionLogProvider.global.info('Attacking ${planet.name}...');
            },
            icon: const Icon(Icons.local_fire_department_rounded, size: 18),
            label: const Text('Attack'),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.error,
              side: BorderSide(color: cs.error.withValues(alpha: 0.5)),
            ),
          ),
        ),
      ],
    );
  }

  final Map<String, int> _transferAmounts = {
    'colonists': 10,
    'minerals': 10,
    'organics': 10,
    'industrial': 10,
    'drones': 10,
  };

  int _storedFor(String type, Planet planet) {
    switch (type) {
      case 'minerals':
        return planet.storedMinerals;
      case 'organics':
        return planet.storedOrganics;
      case 'industrial':
        return planet.storedIndustrial;
      case 'drones':
        return planet.storedDrones;
      case 'colonists':
        return planet.population;
      default:
        return 0;
    }
  }

  int _maxFor(String type, Planet planet) {
    if (type == 'colonists') return planet.colonistMax;
    return planet.capFor(type);
  }

  Widget _buildTransfersSection(Planet planet, ColorScheme cs) {
    const resourceTypes = [
      'minerals',
      'organics',
      'industrial',
      'drones',
      'colonists'
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transfers',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            for (final type in resourceTypes) ...[
              _transferRow(type, planet, cs),
              const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }

  /// BFS hops from the faction's colonist source to this planet, cached per
  /// sector so a rebuild does not re-walk the graph on every row.
  int? _cachedHops;
  ColonistSource? _cachedSource;

  ColonistSource _sourceFor() => _cachedSource ??=
      ColonistSupply.sourceFor(_allSectors, widget.player.faction);

  int _hopsFor(Sector sector) => _cachedHops ??=
      ColonistSupply.hopsBetween(_allSectors, _sourceFor().sectorId, sector.id);

  /// Price per colonist from the faction's capital. Colonists are the **only**
  /// transfer that has a price any more.
  ///
  /// The flat resource table that used to live here is **deleted rather than
  /// retuned**. It priced goods that no longer change hands: `Dep` and `Wdr`
  /// now move units between the hold and the store, and a per-unit credit rate
  /// for a haul that costs nothing is an invented number on screen. Worse, it
  /// gave the same minerals three different values within one screen — 5 cr on
  /// this row, 42.5 cr on the Collect shipment pool, and a live demand-driven
  /// price at any port.
  int _priceFor(String type, Sector sector) =>
      ColonistSupply.pricePerColonist(_hopsFor(sector),
          orphan: _sourceFor().isOrphan);

  /// The explanation behind the colonists row's amber info bubble.
  ///
  /// Colonists are the one transfer whose price is not a flat rate, and all
  /// three reasons for it used to be crammed into the price cell — which made
  /// the row read `5.4K / 200.0K  405cr · 9 hops from Vionis`. That is a
  /// sentence, not a number, and on a phone it ellipsised away the part that
  /// explains *why* the price is what it is.
  String _colonistTooltipText(Sector sector, int shipmentEnergy) {
    final source = _sourceFor();
    final hops = _hopsFor(sector);
    final price =
        ColonistSupply.pricePerColonist(hops, orphan: source.isOrphan);
    final buffer = <String>[
      'Colonists ship from ${source.label}.',
      '$price cr each, $hops ${hops == 1 ? 'hop' : 'hops'} away.',
      'Each shipment costs $shipmentEnergy energy, whatever the size — so send '
          'them in one lot rather than many.',
    ];
    if (source.isOrphan) {
      buffer.add(
        'With no capital under your control you are buying from Terra Prime at '
        'an exile rate. Recapture your homeworld to end it.',
      );
    }
    return buffer.join('\n\n');
  }

  Widget _transferRow(String type, Planet planet, ColorScheme cs) {
    final sector = _currentSector;
    final stored = _storedFor(type, planet);
    final max = _maxFor(type, planet);
    final amount = _transferAmounts[type] ?? 10;
    final isColonists = type == 'colonists';

    // Colonists still ship through ColonistSupply: distance-priced credits plus
    // a per-shipment energy cost, and the physical cargo half is still to come.
    // Everything else is now a plain haul between the hold and the store.
    final pricePerUnit =
        isColonists && sector != null ? _priceFor(type, sector) : 0;
    final depositCost = amount * pricePerUnit;
    final shipmentEnergy = sector == null
        ? 0
        : ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    final inHold = isColonists ? 0 : (widget.player.cargo[type] ?? 0);
    final holdSpace = widget.player.maxCargo - widget.player.cargoUsed;
    // The most that can move in one action: enough goods in the right place, and
    // enough room on the receiving side. Shared by the `+` ceiling and the Max
    // button so the number on screen is the number that will be transferred.
    final storeRoom = max - stored;
    final maxMovable = isColonists
        ? 0
        : (inHold < storeRoom ? inHold : storeRoom).clamp(0, holdSpace);

    // A deposit needs units in the hold and any room on the world; a withdrawal
    // needs units on the world and any free hold space. Both are gated on
    // "is this possible **at all**", not on the current stepper amount.
    //
    // Gating on the amount made the buttons lie. With 5 free slots and a stepper
    // reading 10, `10 <= 5` is false, so a player with 1,000 minerals on a
    // nearby world and a nearly-empty hold saw a dead button and no way to make
    // the one load that would have fitted. The handlers clamp to
    // `min(stored, space)`, so the button only has to say "yes, some of this
    // can move".
    final canDeposit = isColonists
        ? (widget.player.credits >= depositCost &&
            stored + amount <= max &&
            widget.player.energy >= shipmentEnergy)
        : (inHold > 0 && stored < max);
    final canWithdraw = !isColonists && stored > 0 && holdSpace > 0;
    final label = type[0].toUpperCase() + type.substring(1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 80,
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                  // Colonists are the only row whose price is not a flat rate,
                  // and the reasons are worth explaining rather than cramming
                  // into the row. The source, the distance and the per-shipment
                  // fuel cost all live here instead.
                  if (type == 'colonists' && sector != null)
                    Tooltip(
                      message: _colonistTooltipText(sector, shipmentEnergy),
                      waitDuration: const Duration(milliseconds: 400),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.info_outline_rounded,
                          size: 12,
                          color: Colors.amber.shade600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Spacer(),
            // Both trailing readouts flex and ellipsise. The colonist row grew a
            // hop count and overflowed by 8.6px at 430px, which is the same
            // two-natural-width-Texts-in-a-Row trap that has bitten this screen
            // three times now.
            Flexible(
              child: Text(
                '${_formatNumber(stored)} / ${_formatNumber(max)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                // For resources this used to read a price, which was a lie: no
                // credits change hands on an unload or a load. What the player
                // actually needs to see is how much of the goods is already in
                // the hold, because that is what bounds a deposit.
                isColonists
                    ? '${pricePerUnit}cr'
                    : 'hold ${_formatNumber(inHold)}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            _miniStepper(Icons.remove_rounded, () {
              setState(() {
                _transferAmounts[type] = (amount - 10).clamp(1, max);
              });
            }),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                '$amount',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            _miniStepper(Icons.add_rounded, () {
              // Bounded by whatever can actually move, so the figure is always
              // actionable on at least one button rather than reachable on
              // neither. Colonists have their own ceiling: they cost credits.
              final int ceiling;
              if (isColonists) {
                final byCredits = widget.player.credits ~/
                    (pricePerUnit > 0 ? pricePerUnit : 1);
                ceiling = (storeRoom < byCredits ? storeRoom : byCredits)
                    .clamp(0, max);
              } else {
                ceiling = maxMovable;
              }
              final next = amount + 10 > ceiling ? ceiling : amount + 10;
              if (next > amount) {
                setState(() => _transferAmounts[type] = next.clamp(1, max));
              }
            }),
            // One action instead of a held button's worth of taps. Sets the
            // amount rather than transferring directly, so the player can see
            // what is about to move and then press Unload or Load.
            if (!isColonists && maxMovable > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4, right: 2),
                child: InkWell(
                  onTap: () => _setTransferMax(type, maxMovable),
                  borderRadius: BorderRadius.circular(4),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Max',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            const Spacer(),
            if (isColonists)
              _miniActionButton(
                  'Recruit', Colors.green, canDeposit && depositCost > 0, () {
                _recruitColonists(type, amount, depositCost, planet);
              })
            else ...[
              // Labels say which way the goods move, because "Dep"/"Wdr" is
              // ambiguous about whether it is the planet or the ship that is
              // being unloaded. The icons carry the same information.
              _miniActionButton('Unload', Colors.blue, canDeposit, () {
                _depositToPlanet(type, amount, planet);
              }),
              const SizedBox(width: 4),
              _miniActionButton('Load', Colors.orange, canWithdraw, () {
                _withdrawToShip(type, amount, planet);
              }),
            ],
          ],
        ),
      ],
    );
  }

  /// A compact `-`/`+` control that repeats while held.
  ///
  /// Press-and-hold is not a convenience here, it is the difference between
  /// setting a transfer amount and giving up on it. Absorbing a colony's
  /// production into a hold takes hundreds of taps of `+10`, and a player who
  /// cannot do it will simply not use the feature — which is the same failure as
  /// the feature not existing.
  ///
  /// The repeat rate is the same 400ms delay / 80ms interval as
  /// `lib/widgets/hold_button.dart`, but this is a bare icon rather than a
  /// labelled button, and `HoldButton` is a `SizedBox(height: 36)` with a
  /// `FittedBox` label — wrong shape for a 24px square inside a dense row.
  Widget _miniStepper(IconData icon, VoidCallback onPressed) {
    return _HoldRepeatIcon(
      onPressed: onPressed,
      child: Container(
        padding: const EdgeInsets.all(3),
        child: Icon(icon, size: 14),
      ),
    );
  }

  /// Sets a transfer row's amount to everything that can actually move.
  ///
  /// Bounded by the *same* constraint the button will apply, so the number on
  /// screen is the number that will be transferred: the smaller of what is in
  /// the hold and what has room on the world, and never more than the free
  /// cargo space. Pressing it twice is harmless, which is the point.
  void _setTransferMax(String type, int max) {
    setState(() => _transferAmounts[type] = max < 1 ? 1 : max);
  }

  Widget _miniActionButton(
      String label, Color color, bool enabled, VoidCallback onPressed) {
    return Material(
      color: enabled ? color.withValues(alpha: 0.15) : Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
              color: enabled ? color : color.withValues(alpha: 0.3),
            ),
          ),
        ),
      ),
    );
  }

  /// Buys colonists from the faction's capital and settles them on the world.
  ///
  /// The one transfer that is **not** a haul. Colonists are priced by distance
  /// from the faction's own homeworld (`15 x hops^1.5`) and every shipment burns
  /// the energy of flying there, whatever its size, so batching pays. They are
  /// still an abstract count rather than cargo — the physical hold half is
  /// outstanding work, recorded in the design doc.
  Future<void> _recruitColonists(
      String type, int amount, int cost, Planet planet) async {
    final sector = _currentSector;
    if (sector == null || widget.player.credits < cost) return;

    // Every shipment burns the energy of flying there, whatever its size. Charged
    // per shipment rather than per unit, so batching pays and a distant empire is
    // a fuel problem rather than a credit problem alone.
    final energy =
        ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    if (widget.player.energy < energy) return;

    final moved = amount < planet.colonistMax - planet.population
        ? amount
        : planet.colonistMax - planet.population;
    if (moved <= 0) return;
    final actualCost = cost ~/ amount * moved;

    var updated = widget.player.copyWith(
      credits: widget.player.credits - actualCost,
    );
    if (energy > 0) {
      updated = updated.copyWith(energy: widget.player.energy - energy);
    }
    widget.onPlayerUpdate(updated);
    planet.population += moved;

    await _persist(sector);
    ActionLogProvider.global.info(
      'Recruited $moved colonists onto ${planet.name} '
      '($actualCost cr${energy > 0 ? ', $energy energy' : ''})',
    );
    if (mounted) setState(() {});
  }

  /// Moves units from the ship's hold into the planet's store. Free.
  ///
  /// This used to debit credits and energy and then credit the goods into the
  /// store **without ever touching `player.cargo`**, which made it a
  /// credits-to-goods printer rather than a transfer: it ignored
  /// `maxCargo` entirely, so a million minerals went into a hold that fits fifty,
  /// and there was nothing in the galaxy to haul.
  ///
  /// Unloading is free because the ship is already in orbit — the cost of
  /// getting the goods here was paid at the port, or earned on a colony.
  Future<void> _depositToPlanet(String type, int amount, Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final held = widget.player.cargo[type] ?? 0;
    final room = _maxFor(type, planet) - _storedFor(type, planet);
    final moved = amount < held ? amount : held;
    final movedFits = moved < room ? moved : room;
    if (movedFits <= 0) return;

    _applyToStore(type, planet, movedFits);
    final cargo = Map<String, int>.from(widget.player.cargo);
    final left = held - movedFits;
    if (left > 0) {
      cargo[type] = left;
    } else {
      cargo.remove(type);
    }
    widget.onPlayerUpdate(widget.player.copyWith(
      cargo: cargo,
      cargoUsed: widget.player.cargoUsed - movedFits,
    ));

    await _persist(sector);
    ActionLogProvider.global.info(
      'Unloaded $_format(movedFits) $type to ${planet.name}'
      '${movedFits < amount ? ' (store was full)' : ''}',
    );
    if (mounted) setState(() {});
  }

  /// Moves units from the planet's store into the ship's hold. Free.
  ///
  /// The counterpart to [_depositToPlanet], and it used to be worse: it paid the
  /// player credits, never touched the hold, and — unlike deposit — charged no
  /// energy at all. So the same goods had two invented prices (5 cr here, 42.5 cr
  /// on the Collect button, and a live price at a port) and neither moved a
  /// single unit into a ship.
  ///
  /// Bounded by free cargo space, which is what makes a hauler worth flying.
  Future<void> _withdrawToShip(String type, int amount, Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final stored = _storedFor(type, planet);
    final space = widget.player.maxCargo - widget.player.cargoUsed;
    final moved = amount < stored ? amount : stored;
    final movedFits = moved < space ? moved : space;
    if (movedFits <= 0) return;

    _applyToStore(type, planet, -movedFits);
    final cargo = Map<String, int>.from(widget.player.cargo);
    cargo[type] = (cargo[type] ?? 0) + movedFits;
    widget.onPlayerUpdate(widget.player.copyWith(
      cargo: cargo,
      cargoUsed: widget.player.cargoUsed + movedFits,
    ));

    await _persist(sector);
    ActionLogProvider.global.info(
      'Loaded $_format(movedFits) $type from ${planet.name}'
      '${movedFits < amount ? ' (hold is full)' : ''}',
    );
    if (mounted) setState(() {});
  }

  /// Adds (or, for a negative [delta], removes) units on a named store.
  ///
  /// Clamped at zero so a withdraw can never drive a store negative if two
  /// actions land in the same frame.
  void _applyToStore(String type, Planet planet, int delta) {
    int apply(int current) {
      final next = current + delta;
      return next < 0 ? 0 : next;
    }

    switch (type) {
      case 'minerals':
        planet.storedMinerals = apply(planet.storedMinerals);
      case 'organics':
        planet.storedOrganics = apply(planet.storedOrganics);
      case 'industrial':
        planet.storedIndustrial = apply(planet.storedIndustrial);
      case 'drones':
        planet.storedDrones = apply(planet.storedDrones);
    }
  }

  static String _format(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  Future<void> _claimPlanet(Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final previousOwner = planet.owner;
    planet.owner = widget.player.faction;
    var updatedPlayer = widget.player;
    if (previousOwner != null && previousOwner != widget.player.faction) {
      updatedPlayer =
          updatedPlayer.withFactionStandingChange(previousOwner, -3);
    }
    widget.onPlayerUpdate(updatedPlayer);
    await _persist(sector);
    ActionLogProvider.global.info(
      '${widget.player.faction.displayName} has claimed ${planet.name}',
    );
    if (mounted) {
      setState(() {});
    }
  }

  String _levelTitle(int level) {
    return level >= 1 && level <= 6 ? Planet.levelTitles[level - 1] : 'Unknown';
  }

  String _formatNumber(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return n.toString();
  }

  /// A level-gate row: `have / need`, with the **requirement** coloured.
  ///
  /// Two iterations on this. It started as a trailing `✓` glyph, which only
  /// appeared on success — a missed requirement showed nothing, so the two states
  /// were told apart by the absence of a character. That became a green tick or
  /// a red cross, which was unambiguous but noisy: a fourth icon column on every
  /// row, for a binary the numbers already carry.
  ///
  /// It is now just the colour of the **required** figure. Red means not yet,
  /// green means met, and the first number — what the world actually has — stays
  /// in the normal text colour, because colouring the total too would colour
  /// every cell in the card and tell you nothing the numbers do not.
  ///
  /// Colour alone is not an accessible signal, so the row also carries a
  /// semantic label; see the comment on the test that checks it.
  Widget _requirementRow(String label, int have, int need, ColorScheme cs) {
    final met = have >= need;
    return Semantics(
      // `container: true` is what makes this its **own** node. Without it
      // `Semantics` only annotates, and the label merges into an ancestor's
      // node — where it is indistinguishable from every other row and cannot be
      // addressed on its own. `excludeSemantics` then drops the inner Text so
      // the raw "250 / 250" is not announced as well.
      container: true,
      label: '$label requirement ${met ? 'met' : 'not met'}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.6),
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${_formatNumber(have)} / ${_formatNumber(need)}',
                textAlign: TextAlign.right,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  // Only the *need* is coloured, so the eye lands on the
                  // target rather than on the number that is merely your
                  // current position.
                  color: met
                      ? Colors.green.shade400
                      : cs.error.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: cs.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w500)),
          // The value is flexible and the label is not, so a long value (a
          // population against a million-colonist cap, say) ellipsises instead
          // of overflowing the row. Both were natural width once, which meant
          // adding any "12,450 / 1.5M" value broke every card at 430px.
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resourceBar(String label, int value, int max, Color color) {
    return StatBar(
      layout: StatBarLayout.stacked,
      label: label,
      // Current against cap, not just the current figure. The bar was already
      // drawn proportionally, so the number beside it was the only place a
      // player could not see how much room a world has left — which matters
      // because a full store spills the surplus into the shipment pool rather
      // than wasting it, and the player's next decision is whether to collect
      // or to reassign colonists.
      value: max > 0
          ? '${_formatNumber(value)}/${_formatNumber(max)}'
          : _formatNumber(value),
      percent: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
      color: color,
    );
  }

  Widget _defenseBar(String label, double value, double max, Color color) {
    return StatBar(
      layout: StatBarLayout.stacked,
      label: label,
      value: '${value.toInt()} / ${max.toInt()}',
      percent: max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0,
      color: color,
    );
  }

  /// Colonists moved per tap of a workforce stepper, scaled to the colony so a
  /// world of a million is not adjusted ten at a time.
  static int _workforceStep(int population) {
    if (population >= 100000) return 1000;
    if (population >= 10000) return 500;
    if (population >= 1000) return 100;
    return 10;
  }

  /// The step actually used for a move of [delta] colonists.
  ///
  /// A fixed step is unusable at the small end: a 900-colony world steps 100 at
  /// a time, so with 40 colonists in the reserve the add button was **dead** —
  /// `reserve >= 100` was false and there was no way to move any of them. The
  /// player saw a full population and four disabled buttons.
  ///
  /// So the step is clamped to what is actually available on the side being
  /// moved. A 40-colonist reserve still moves 40, not "nothing, because 100
  /// did not fit". `delta` is negative for a removal, hence the sign test.
  static int _effectiveStep(int step, int delta, int available) {
    if (available > 0 && step > available) {
      return delta < 0 ? available : available;
    }
    return step;
  }

  /// Moves colonists between the reserve and a production track.
  ///
  /// The reserve is implicit — `population - assigned` — so this can never drive
  /// the tracks above the population, and can never produce a negative count on
  /// either side. Both bounds are re-checked here rather than trusted to the
  /// button's `enabled` flag, because a held button keeps firing after the state
  /// it was enabled for has changed.
  Future<void> _adjustWorkforce(Planet planet, String track, int delta) async {
    final sector = _currentSector;
    if (sector == null) return;
    if (planet.owner != widget.player.faction) return;

    final reserve = planet.reserveColonists;
    final current = switch (track) {
      'minerals' => planet.colonistsMinerals,
      'organics' => planet.colonistsOrganics,
      'industrial' => planet.colonistsIndustrial,
      'drones' => planet.colonistsDrones,
      _ => 0,
    };

    // Moving into a track: only as many as are idling in the reserve.
    final into = delta > 0 ? delta.clamp(0, reserve) : delta;
    if (into == 0) return;
    final applied = current + into;
    if (applied < 0) return;

    switch (track) {
      case 'minerals':
        planet.colonistsMinerals = applied;
      case 'organics':
        planet.colonistsOrganics = applied;
      case 'industrial':
        planet.colonistsIndustrial = applied;
      case 'drones':
        planet.colonistsDrones = applied;
    }

    await _persist(sector);
    if (mounted) setState(() {});
  }

  Widget _buildColonyCard(Planet planet, ColorScheme cs) {
    final canAssign = planet.owner == widget.player.faction;
    final step = _workforceStep(planet.population);
    final unsupplied = planet.storesEmpty;

    Widget trackRow(
      String label,
      int count,
      int perTick,
      Color colour,
      String track,
    ) {
      // A track the world cannot produce is **locked**, not merely empty.
      // A stepper that accepts colonists onto a track yielding nothing looks
      // like a bug, and a player who cannot see why their organics stay at zero
      // will assume the mechanic is broken. The label says it outright.
      final producible = planet.canProduce(track);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            SizedBox(
              width: 74,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            SizedBox(
              width: 58,
              child: Text(
                _formatNumber(count),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                  color: colour,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                !producible
                    ? 'cannot produce'
                    : perTick > 0
                        ? '+${_formatNumber(perTick)}/tick'
                        : '—',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: perTick > 0
                      ? cs.onSurface.withValues(alpha: 0.6)
                      : cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ),
            if (canAssign) ...[
              const SizedBox(width: 6),
              // Each button's step is clamped to what is available on its own
              // side, so a 40-colonist reserve moves 40 rather than being
              // disabled for not fitting 100. Enabled on `> 0`, not `>= step`.
              _stepButton(
                icon: Icons.add,
                // Names the source, because a bare +/- pair on a row of numbers
                // does not say where the colonists come from. It is the reserve —
                // the implicit `population - on tracks` figure three rows above —
                // and the tooltip is the only place that says so.
                tooltip: producible
                    ? 'Assign from reserve (${_formatNumber(planet.reserveColonists)} idle)'
                    : 'Cannot produce this - the reserve is not assignable here',
                enabled: producible && planet.reserveColonists > 0,
                onTap: () => _adjustWorkforce(planet, track,
                    _effectiveStep(step, 1, planet.reserveColonists)),
              ),
              _stepButton(
                icon: Icons.remove,
                tooltip: 'Return to reserve',
                // Remove stays enabled even on a dead track: a colony generated
                // before a world became unable to produce something should not be
                // stuck holding colonists who will never work again. That is also
                // why the step is clamped to what is actually on the track rather
                // than being the full step.
                enabled: count > 0,
                onTap: () => _adjustWorkforce(
                    planet, track, -_effectiveStep(step, -1, count)),
              ),
            ],
          ],
        ),
      );
    }

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Colony',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoRow('Population',
                '${_formatNumber(planet.population)} / ${_formatNumber(planet.colonistMax)}'),
            _infoRow('On tracks', _formatNumber(planet.assignedColonists)),
            _infoRow('Reserve', _formatNumber(planet.reserveColonists)),
            _infoRow(
                'Supply draw',
                '${_formatNumber(planet.supplyDraw)} every '
                    '${Planet.supplyInterval} ticks'),
            _infoRow('Next supply', '${planet.ticksToSupply} ticks'),
            if (unsupplied) ...[
              const SizedBox(height: 8),
              _buildSupplyWarning(planet, cs),
            ],
            const SizedBox(height: 12),
            trackRow('Minerals', planet.colonistsMinerals, planet.mineralOutput,
                Colors.orange, 'minerals'),
            trackRow('Organics', planet.colonistsOrganics, planet.organicOutput,
                Colors.green, 'organics'),
            trackRow('Industrial', planet.colonistsIndustrial,
                planet.industrialOutput, Colors.blue, 'industrial'),
            trackRow('Drones', planet.colonistsDrones, planet.droneOutput,
                Colors.red, 'drones'),
            const SizedBox(height: 8),
            Divider(color: cs.onSurface.withValues(alpha: 0.1), height: 1),
            const SizedBox(height: 8),
            Text(
              canAssign
                  ? '+ moves colonists off the reserve and onto the track; '
                      '\u2212 brings them back. The reserve is everyone not on a '
                      'track \u2014 they still eat. Note the drones are not '
                      'production: they are your haul crew, and they do not work '
                      'this planet\u2019s stores.'
                  : 'This world is not yours to reassign.',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The colony cannot cover its supply draw.
  ///
  /// The replacement for the starvation warning, and deliberately softer in
  /// tone: nobody is dying, the colony is simply drawing on empty stores. The
  /// fix is a haul or a planted neighbour, not a rescue.
  Widget _buildSupplyWarning(Planet planet, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.error.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded, size: 16, color: cs.error),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Stores empty — supply unpaid',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: cs.error,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  planet.canProduce('organics')
                      ? 'Haul minerals, organics or industrial in, or collect '
                          'what is already queued.'
                      : 'This world cannot make organics. Unload organics from '
                          'your hold, or plant a world beside it that grows '
                          'them.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: cs.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final button = SizedBox(
      width: 26,
      height: 24,
      child: Material(
        color: enabled
            ? scheme.surfaceContainerHighest
            : scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: enabled ? onTap : null,
          child: Icon(
            icon,
            size: 14,
            color: enabled
                ? scheme.onSurface
                : scheme.onSurface.withValues(alpha: 0.25),
          ),
        ),
      ),
    );
    if (tooltip == null) return button;
    // Wrapping rather than putting the text in the row: a workforce row is four
    // numbers wide and there is no room to spell out what each glyph does. This
    // is the fix for a genuine confusion - a bare +/- pair on a row of numbers
    // does not say that the pair *moves colonists between two places*, which is
    // the only thing these buttons do.
    return Tooltip(message: tooltip, child: button);
  }

  Widget _buildLevelUpSection(Planet planet, ColorScheme cs) {
    final cost = planet.levelUpCost;
    if (cost == null) {
      return Text(
        'MAX LEVEL — ${Planet.levelTitles.last}',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.amber.shade400,
          fontSize: 13,
          fontFamily: 'monospace',
        ),
      );
    }

    // A build already under way takes the whole card over. The gate rows below
    // describe work that has already been paid for, so showing them again next
    // to a progress bar would invite the player to think they still had a choice.
    if (planet.isUnderConstruction) {
      return _buildConstructionPanel(planet, cs);
    }

    final canLevel = planet.canStartConstruction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Level ${planet.level} → ${planet.level + 1}  ',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: Colors.amber.shade400,
              ),
            ),
            Text(
              Planet.levelTitles[planet.level],
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _requirementRow(
            'Colonists', planet.population, cost.requiredColonists, cs),
        _requirementRow(
            'Minerals', planet.storedMinerals, cost.requiredMinerals, cs),
        _requirementRow(
            'Organics', planet.storedOrganics, cost.requiredOrganics, cs),
        _requirementRow(
            'Industrial', planet.storedIndustrial, cost.requiredIndustrial, cs),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: canLevel ? () => _levelUpPlanet(planet) : null,
            icon: const Icon(Icons.arrow_upward_rounded, size: 18),
            label: const Text('Level Up'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
              foregroundColor: Colors.black,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: () => _showLevelPreview(context, planet),
            icon: const Icon(Icons.help_outline_rounded, size: 15),
            label: const Text('What does this give me?',
                style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: cs.onSurface.withValues(alpha: 0.7),
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      ],
    );
  }

  /// Quick "what do I get" preview, shown under the level-up button.
  ///
  /// **Only the next tier, not all six.** The argument for that is the framing,
  /// not the space: a player standing at a level gate has one question, and the
  /// useful answer is a *delta* — "defence: none -> light". A six-row table
  /// cannot show a delta, and a delta is strictly more informative than the
  /// column it came from. Reference material belongs in the Planet Guide, which
  /// already generates the full table from the same model.
  ///
  /// The population row deliberately shows the new cap against the gate beside
  /// it. That pairing is the whole point of the derived cap, and it is the one
  /// place a player would otherwise have to check it by hand.
  void _showLevelPreview(BuildContext context, Planet planet) {
    final from = planet.level;
    final to = from + 1;
    if (to >= Planet.levelTitles.length) return;

    // levelTitles is 0-indexed from level 1, so a level L is titles[L - 1].
    // Getting this wrong labels the whole dialog one tier ahead, and it is
    // invisible unless a test names the expected string.
    final fromTitle = Planet.levelTitles[from - 1];
    final toTitle = Planet.levelTitles[to - 1];

    Future<void> show() => showDialog<void>(
          context: context,
          builder: (ctx) {
            final dialogCs = Theme.of(ctx).colorScheme;
            return AlertDialog(
              title: Text('$fromTitle -> $toTitle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _benefitRow(
                        ctx,
                        'Development',
                        '${(Planet.levelDevelopment[from] ?? 1.0).toStringAsFixed(2)}x',
                        '${(Planet.levelDevelopment[to] ?? 1.0).toStringAsFixed(2)}x'),
                    _benefitRow(
                        ctx,
                        'Defence',
                        _defenceWord(planet.defenseLevel),
                        _defenceWord(Planet.levelDefense[to] ?? 0)),
                    _benefitRow(
                        ctx,
                        'Armour',
                        _formatNumber(planet.maxHull.round()),
                        _formatNumber(Planet.levelArmour[to] ?? 0)),
                    _benefitRow(
                        ctx,
                        'Shields',
                        planet.maxShield.round() <= 0
                            ? 'none'
                            : _formatNumber(planet.maxShield.round()),
                        (Planet.levelShield[to] ?? 0) <= 0
                            ? 'none'
                            : _formatNumber(Planet.levelShield[to] ?? 0)),
                    _benefitRow(
                        ctx,
                        'Storage',
                        'x${_scale(Planet.levelStorageScale[from])}',
                        'x${_scale(Planet.levelStorageScale[to])}'),
                    const SizedBox(height: 12),
                    _previewStat(
                      ctx,
                      'New population cap',
                      _formatNumber((planet.baseColonistMax *
                              (Planet.levelColonistScale[to] ?? 1.0))
                          .round()),
                    ),
                    _previewStat(
                      ctx,
                      'Needed for this level',
                      _formatNumber(planet.levelUpCost!.requiredColonists),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'The full tier table is in the Planet Guide '
                      '(Computer -> Planet Guide).',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: dialogCs.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );

    // Fire and forget: the dialog owns its own lifetime, and nothing on the
    // planet screen needs to wait for it or react to its dismissal.
    show();
  }

  /// A "current -> next" line. The arrow is what makes this a delta rather
  /// than a lookup, so it is never elided and the row is allowed to wrap.
  Widget _benefitRow(
    BuildContext context,
    String label,
    String from,
    String to,
  ) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: [
                Text(from,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6))),
                Icon(Icons.arrow_right_alt_rounded,
                    size: 16, color: cs.onSurface.withValues(alpha: 0.5)),
                Text(to,
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber.shade400)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// A plain "label: value" line for figures with no "before" to show.
  Widget _previewStat(BuildContext context, String label, String value) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: cs.onSurface.withValues(alpha: 0.7))),
          ),
          Text(value,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  /// Defence levels are a 0-4 scale. Numbers mean nothing to a player.
  static String _defenceWord(int level) {
    const words = ['none', 'light', 'moderate', 'heavy', 'fortified'];
    return level < words.length ? words[level] : '$level';
  }

  static String _scale(double? v) => v == null
      ? '1'
      : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2));

  /// Chip row for choosing which world in this sector to work with.
  ///
  /// Only rendered when the sector holds more than one. Its absence in a
  /// single-world sector is deliberate: a one-chip selector that can only be
  /// tapped to select what is already selected is pure noise.
  ///
  /// A destroyed world stays in the list rather than disappearing. Removing it
  /// would shift every chip under the player's finger mid-session, and the
  /// collision roll can destroy a world while they are looking at it — so it is
  /// shown struck through and unselectable instead.
  Widget _buildWorldSelector(Sector sector, Planet current) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Worlds in this sector',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface.withValues(alpha: 0.7))),
            const Spacer(),
            Text('${sector.livingPlanets.length} / ${sector.planets.length}',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurface.withValues(alpha: 0.5))),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final p in sector.planets) ...[
                ChoiceChip(
                  label: Text(p.name,
                      style: TextStyle(
                        fontSize: 12,
                        decoration:
                            p.isDestroyed ? TextDecoration.lineThrough : null,
                      )),
                  selected: p.id == current.id,
                  onSelected: p.isDestroyed
                      ? null
                      : (_) => setState(() => _selectedPlanetId = p.id),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Progress panel shown in place of the level gate while a build runs.
  ///
  /// The wording is deliberate on one point: the countdown is **game ticks, not
  /// wall-clock time**. "40 ticks" is honest about what the player can actually
  /// affect; an "ETA" in hours would quietly lie every time they closed the game.
  Widget _buildConstructionPanel(Planet planet, ColorScheme cs) {
    final remaining = planet.constructionTicksRemaining;
    final total = planet.constructionTotalTicks;
    final title = planet.constructionTarget > 0 &&
            planet.constructionTarget <= Planet.levelTitles.length - 1
        ? Planet.levelTitles[planet.constructionTarget]
        : 'Level ${planet.constructionTarget}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // No spinner here. The bar below is determinate, so a spinner would be
            // redundant *and* worse: an indeterminate indicator animates forever,
            // which never settles, costs a frame every rebuild, and reads as
            // "working" even on a build the player has set to instant.
            const Icon(Icons.construction_rounded,
                size: 16, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Building $title — level ${planet.level + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.amber,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: planet.constructionProgress,
            minHeight: 10,
            // The track is a real requirement, not decoration: a determinate bar
            // at 0% is *only* its track, and `surfaceContainerHighest` on this
            // background is so close to the card fill that a freshly started
            // build looked like no bar at all.
            backgroundColor: Colors.amber.withValues(alpha: 0.18),
            valueColor: const AlwaysStoppedAnimation(Colors.amber),
          ),
        ),
        const SizedBox(height: 8),
        _infoRow(
          'Progress',
          '${total - remaining} / $total ticks'
              '${total > 0 ? '  (${_estimateMinutes(remaining)})' : ''}',
        ),
        const SizedBox(height: 6),
        Text(
          'Advances one step per game tick, so it only moves while you are '
          'playing — the same clock the galaxy runs on.',
          style: TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: cs.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }

  /// Ticks left rendered as play time, at the 30s tick interval.
  ///
  /// Prefers coarse units so the number stays short at phone width, and returns
  /// an empty string when the figure would be noise.
  String _estimateMinutes(int ticksLeft) {
    if (ticksLeft <= 0) return '';
    const secondsPerTick = 30;
    final minutes = (ticksLeft * secondsPerTick / 60).round();
    if (minutes < 1) return 'under a minute';
    if (minutes < 60) return '~$minutes min';
    final hours = minutes / 60;
    return '~${hours.toStringAsFixed(hours < 2 ? 1 : 0)} h';
  }

  Future<void> _levelUpPlanet(Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    // Instant when the player has asked for instant construction, otherwise a
    // real build. Both paths share one cost table, so a build at 0 seconds and
    // a build at 4 hours are the same transaction with a different wait.
    final scale = widget.constructionTimeScale;
    if (scale <= 0) {
      if (!planet.levelUp()) return;
      await _persist(sector);
      ActionLogProvider.global.info(
        '${planet.name} reached level ${planet.level}',
      );
    } else {
      if (!planet.startConstruction(timeScale: scale)) return;
      // **Persist before returning.** Omitting this was a live bug: the
      // countdown and the spent resources existed only in this screen's
      // in-memory copy of the sector, so leaving the tab threw the build away
      // and the level gate came back armed, at the same level, with the
      // resources back in the store. The countdown is the *authoritative*
      // state of a running build, so it has to reach disk before the player
      // can navigate away.
      await _persist(sector);
      final mins = _estimateMinutes(planet.constructionTicksRemaining);
      ActionLogProvider.global.info(
        '${planet.name} began building level ${planet.level + 1}'
        '${mins.isEmpty ? '' : ' ($mins of play time)'}',
      );
    }

    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildResourcesCard(Planet planet, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Resources',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            // Each commodity against its own cap. A single shared cap shown
            // next to a sum of three stores made a legal planet read as
            // overfull.
            _resourceBar('Minerals', planet.storedMinerals, planet.maxMinerals,
                Colors.orange),
            _resourceBar('Organics', planet.storedOrganics, planet.maxOrganics,
                Colors.green),
            _resourceBar('Industrial', planet.storedIndustrial,
                planet.maxIndustrial, Colors.blue),
            if (planet.pendingTotal > 0) ...[
              const SizedBox(height: 12),
              _buildShipmentPanel(planet, cs),
            ],
          ],
        ),
      ),
    );
  }

  /// Output waiting to be collected.
  ///
  /// A colony keeps producing once its working store is full — that surplus is
  /// queued here rather than discarded, so a world nobody has visited in a
  /// while is still earning. Collection pays the midpoint of the commodity
  /// spread, which is deliberately neutral; once colonies can supply an actual
  /// port, that payout should use the port's live buy price and the player's
  /// standing, which will be worth considerably more.
  Widget _buildShipmentPanel(Planet planet, ColorScheme cs) {
    final value = Planet.shipmentValue({
      if (planet.pendingMinerals > 0) 'minerals': planet.pendingMinerals,
      if (planet.pendingOrganics > 0) 'organics': planet.pendingOrganics,
      if (planet.pendingIndustrial > 0) 'industrial': planet.pendingIndustrial,
      if (planet.pendingDrones > 0) 'drones': planet.pendingDrones,
    });

    Widget line(String label, int amount, Color colour) {
      if (amount <= 0) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 11, color: colour)),
            Text('${_formatNumber(amount)} ready',
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: cs.onSurface.withValues(alpha: 0.6),
                )),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: cs.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.local_shipping_rounded, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text('Ready to collect',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: cs.primary)),
            ],
          ),
          const SizedBox(height: 6),
          line('Minerals', planet.pendingMinerals, Colors.orange),
          line('Organics', planet.pendingOrganics, Colors.green),
          line('Industrial', planet.pendingIndustrial, Colors.blue),
          line('Drones', planet.pendingDrones, Colors.red),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _collectShipment(planet, value),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: Text('Collect  ${_formatNumber(value)} cr'),
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
                foregroundColor: cs.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _collectShipment(Planet planet, int value) async {
    final sector = _currentSector;
    if (sector == null || planet.pendingTotal <= 0) return;

    final collected = planet.collectShipment();
    final payout = Planet.shipmentValue(collected);
    if (payout > 0) {
      widget.onPlayerUpdate(
        widget.player.copyWith(credits: widget.player.credits + payout),
      );
    }
    await _persist(sector);
    ActionLogProvider.global.trade(
      'Collected ${_formatNumber(planet.pendingTotal + collected.values.fold<int>(0, (a, b) => a + b))} units of colony output from ${planet.name} for ${_formatNumber(payout)} cr',
    );
    if (mounted) setState(() {});
  }

  Widget _buildDefenseCard(Planet planet, ColorScheme cs) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Defense',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _infoRow('Defense Level', '${planet.defenseLevel} / 4'),
            _resourceBar(
                'Drones', planet.storedDrones, planet.maxDrones, Colors.red),
            const SizedBox(height: 4),
            _defenseBar('Shield', planet.shield, planet.maxShield, Colors.cyan),
            _defenseBar('Armor', planet.hull, planet.maxHull, Colors.green),
          ],
        ),
      ),
    );
  }
}

/// A bare icon button that fires once on press and repeats while held.
///
/// Mirrors `lib/widgets/hold_button.dart`'s timing (400ms before the first
/// repeat, 80ms between) but takes a [child] instead of a label, because these
/// sit as 24px squares inside a dense table row where a 36px labelled button
/// would not fit and a `FittedBox` label is pointless on a `+` glyph.
class _HoldRepeatIcon extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget child;

  const _HoldRepeatIcon({required this.onPressed, required this.child});

  @override
  State<_HoldRepeatIcon> createState() => _HoldRepeatIconState();
}

class _HoldRepeatIconState extends State<_HoldRepeatIcon> {
  static const _delay = Duration(milliseconds: 400);
  static const _interval = Duration(milliseconds: 80);

  Timer? _timer;

  void _start() {
    widget.onPressed();
    _timer = Timer(_delay, () {
      _timer = Timer.periodic(_interval, (_) {
        if (!mounted) {
          _stop();
          return;
        }
        widget.onPressed();
      });
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTapDown: (_) => _start(),
      onTapUp: (_) => _stop(),
      onTapCancel: _stop,
      child: widget.child,
    );
  }
}
