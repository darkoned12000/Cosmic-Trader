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
    _refresh = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _fingerprintOf(_currentSector?.planet);
      if (next != _fingerprint) {
        _fingerprint = next;
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _refresh?.cancel();
    super.dispose();
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
    if (sector == null || sector.planet == null) return;

    final planet = sector.planet!;
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
    await UniverseStorage.instance.saveSectors([sector]);
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
    final planet = sector?.planet;

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

  /// Flat unit prices for everything that is not colonists. Colonists are
  /// priced by [ColonistSupply] from the real BFS distance to the faction's
  /// homeworld, because a flat rate made every planet equally cheap to populate.
  static const _transferPrices = {
    'minerals': 5,
    'organics': 8,
    'industrial': 12,
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

  int _priceFor(String type, Sector sector) {
    if (type == 'colonists') {
      return ColonistSupply.pricePerColonist(_hopsFor(sector),
          orphan: _sourceFor().isOrphan);
    }
    return _transferPrices[type] ?? 0;
  }

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
    final pricePerUnit = sector == null ? 0 : _priceFor(type, sector);
    final depositCost = amount * pricePerUnit;
    // Every shipment burns the energy it would cost to fly there, whatever its
    // size — so batching pays, and a distant empire is a fuel problem.
    final shipmentEnergy = sector == null
        ? 0
        : ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    final canDeposit = widget.player.credits >= depositCost &&
        stored + amount <= max &&
        widget.player.energy >= shipmentEnergy;
    final canWithdraw =
        stored >= amount && type != 'colonists'; // can't withdraw colonists
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
                '${pricePerUnit}cr',
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
              final maxBuy = max - stored;
              final maxCredits = widget.player.credits ~/
                  (pricePerUnit > 0 ? pricePerUnit : 1);
              final maxAmount = type == 'colonists'
                  ? (max - stored)
                  : (maxBuy < maxCredits ? maxBuy : maxCredits).clamp(0, max);
              final next = amount + 10 > maxAmount ? maxAmount : amount + 10;
              if (next > amount) {
                setState(() => _transferAmounts[type] = next.clamp(1, max));
              }
            }),
            const Spacer(),
            if (type == 'colonists')
              _miniActionButton(
                  'Recruit', Colors.green, canDeposit && depositCost > 0, () {
                _transferToPlanet(type, amount, depositCost, planet);
              })
            else ...[
              _miniActionButton(
                  'Dep', Colors.blue, canDeposit && depositCost > 0, () {
                _transferToPlanet(type, amount, depositCost, planet);
              }),
              const SizedBox(width: 4),
              _miniActionButton('Wdr', Colors.orange, canWithdraw, () {
                _transferFromPlanet(type, amount, pricePerUnit, planet);
              }),
            ],
          ],
        ),
      ],
    );
  }

  Widget _miniStepper(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.all(3),
          child: Icon(icon, size: 14),
        ),
      ),
    );
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

  Future<void> _transferToPlanet(
      String type, int amount, int cost, Planet planet) async {
    final sector = _currentSector;
    if (sector == null || widget.player.credits < cost) return;

    // Every shipment burns the energy of flying there, whatever its size. Charged
    // per shipment rather than per unit, so batching pays and a distant empire is
    // a fuel problem rather than a credit problem alone.
    final energy =
        ColonistSupply.energyPerShipment(widget.player, _hopsFor(sector));
    if (widget.player.energy < energy) return;

    var updated = widget.player.copyWith(
      credits: widget.player.credits - cost,
    );
    if (energy > 0) {
      updated = updated.copyWith(energy: widget.player.energy - energy);
    }
    widget.onPlayerUpdate(updated);

    switch (type) {
      case 'minerals':
        planet.storedMinerals += amount;
      case 'organics':
        planet.storedOrganics += amount;
      case 'industrial':
        planet.storedIndustrial += amount;
      case 'drones':
        planet.storedDrones += amount;
      case 'colonists':
        planet.population += amount;
    }

    await UniverseStorage.instance.saveSectors([sector]);
    ActionLogProvider.global.info(
      'Transferred $amount $type to ${planet.name} '
      '($cost cr${energy > 0 ? ', $energy energy' : ''})',
    );
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _transferFromPlanet(
      String type, int amount, int pricePerUnit, Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    final stored = _storedFor(type, planet);
    final actualAmount = amount > stored ? stored : amount;
    if (actualAmount <= 0) return;

    final creditsGained = actualAmount * pricePerUnit;

    widget.onPlayerUpdate(widget.player.copyWith(
      credits: widget.player.credits + creditsGained,
    ));

    switch (type) {
      case 'minerals':
        planet.storedMinerals -= actualAmount;
      case 'organics':
        planet.storedOrganics -= actualAmount;
      case 'industrial':
        planet.storedIndustrial -= actualAmount;
      case 'drones':
        planet.storedDrones -= actualAmount;
    }

    await UniverseStorage.instance.saveSectors([sector]);
    ActionLogProvider.global.info(
      'Withdrew $actualAmount $type from ${planet.name} (+$creditsGained cr)',
    );
    if (mounted) {
      setState(() {});
    }
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
    await UniverseStorage.instance.saveSectors([sector]);
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

    await UniverseStorage.instance.saveSectors([sector]);
    if (mounted) setState(() {});
  }

  Widget _buildColonyCard(Planet planet, ColorScheme cs) {
    final canAssign = planet.owner == widget.player.faction;
    final step = _workforceStep(planet.population);
    final starving = planet.organicsUpkeep > planet.storedOrganics;

    Widget trackRow(
      String label,
      int count,
      int perTick,
      Color colour,
      String track,
    ) {
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
            if (canAssign)
              _stepButton(
                icon: Icons.remove,
                enabled: count >= step,
                onTap: () => _adjustWorkforce(planet, track, -step),
              ),
            const SizedBox(width: 6),
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
                perTick > 0 ? '+${_formatNumber(perTick)}/tick' : '—',
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
              _stepButton(
                icon: Icons.add,
                enabled: planet.reserveColonists >= step,
                onTap: () => _adjustWorkforce(planet, track, step),
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
            _infoRow('Organics upkeep',
                '${_formatNumber(planet.organicsUpkeep)}/tick'),
            if (starving) ...[
              const SizedBox(height: 8),
              _buildStarvationWarning(planet, cs),
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
                  ? 'Reserve colonists are not on a track. They still eat, and '
                      'they are who you draw from when you reassign a workforce.'
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

  /// The colony cannot feed itself. Worth a loud, specific line: it is the one
  /// colony state a player must *act* on, and the per-tick rates above will
  /// happily keep looking fine while it happens.
  Widget _buildStarvationWarning(Planet planet, ColorScheme cs) {
    final short = planet.organicsUpkeep - planet.storedOrganics;
    final perTick = (planet.population * Planet.maxStarvationRatePerTick)
        .floor()
        .clamp(1, planet.population);
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
            child: Text(
              'Starving — ${_formatNumber(short)} organics short per tick. '
              'About ${_formatNumber(perTick)} colonists are being lost each '
              'tick. Send organics, or put more colonists on the Organics track.',
              style: TextStyle(fontSize: 10, color: cs.onErrorContainer),
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
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
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
    final colonistsOk = planet.population >= cost.requiredColonists;
    final mineralsOk = planet.storedMinerals >= cost.requiredMinerals;
    final organicsOk = planet.storedOrganics >= cost.requiredOrganics;
    final industrialOk = planet.storedIndustrial >= cost.requiredIndustrial;

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
        _infoRow('Colonists',
            '${_formatNumber(planet.population)} / ${_formatNumber(cost.requiredColonists)} ${colonistsOk ? '✓' : ''}'),
        _infoRow('Minerals',
            '${_formatNumber(planet.storedMinerals)} / ${_formatNumber(cost.requiredMinerals)} ${mineralsOk ? '✓' : ''}'),
        _infoRow('Organics',
            '${_formatNumber(planet.storedOrganics)} / ${_formatNumber(cost.requiredOrganics)} ${organicsOk ? '✓' : ''}'),
        _infoRow('Industrial',
            '${_formatNumber(planet.storedIndustrial)} / ${_formatNumber(cost.requiredIndustrial)} ${industrialOk ? '✓' : ''}'),
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
      await UniverseStorage.instance.saveSectors([sector]);
      ActionLogProvider.global.info(
        '${planet.name} reached level ${planet.level}',
      );
    } else {
      if (!planet.startConstruction(timeScale: scale)) return;
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
    await UniverseStorage.instance.saveSectors([sector]);
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
