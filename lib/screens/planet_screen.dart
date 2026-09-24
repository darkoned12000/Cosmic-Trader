import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';

class PlanetScreen extends StatefulWidget {
  final Player player;
  final Function(Player) onPlayerUpdate;

  const PlanetScreen({
    super.key,
    required this.player,
    required this.onPlayerUpdate,
  });

  @override
  State<PlanetScreen> createState() => _PlanetScreenState();
}

class _PlanetScreenState extends State<PlanetScreen> {
  List<Sector> _allSectors = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUniverse();
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

    // Deduct a turn for manual scan
    var updatedPlayer = widget.player.copyWith(
      turns: widget.player.turns - 1,
    );
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
                  onPressed: widget.player.turns > 0 ? _scanPlanet : null,
                  icon: const Icon(Icons.science_rounded),
                  label: Text('Scan Planet (1 turn)'),
                ),
                if (widget.player.turns <= 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Not enough turns',
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _buildResourcesCard(planet, cs),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildDefenseCard(planet, cs),
                ),
              ],
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
                  Text(
                    'Owned by ${widget.player.faction.displayName}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.green.shade400,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _buildTransfersSection(planet, cs),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildLevelUpSection(planet, cs),
                  ),
                ],
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

  static const _transferPrices = {
    'minerals': 5,
    'organics': 8,
    'industrial': 12,
    'drones': 10,
    'colonists': 20,
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
        return planet.storedFighters;
      case 'colonists':
        return planet.population;
      default:
        return 0;
    }
  }

  int _maxFor(String type, Planet planet) {
    if (type == 'colonists') return planet.colonistMax;
    return planet.maxStorage;
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

  Widget _transferRow(String type, Planet planet, ColorScheme cs) {
    final stored = _storedFor(type, planet);
    final max = _maxFor(type, planet);
    final amount = _transferAmounts[type] ?? 10;
    final pricePerUnit = _transferPrices[type] ?? 0;
    final depositCost = amount * pricePerUnit;
    final canDeposit =
        widget.player.credits >= depositCost && stored + amount <= max;
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
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            const Spacer(),
            Text(
              '${_formatNumber(stored)} / ${_formatNumber(max)}',
              style: TextStyle(
                fontSize: 10,
                fontFamily: 'monospace',
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${pricePerUnit}cr',
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurface.withValues(alpha: 0.4),
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

    widget.onPlayerUpdate(widget.player.copyWith(
      credits: widget.player.credits - cost,
    ));

    switch (type) {
      case 'minerals':
        planet.storedMinerals += amount;
      case 'organics':
        planet.storedOrganics += amount;
      case 'industrial':
        planet.storedIndustrial += amount;
      case 'drones':
        planet.storedFighters += amount;
      case 'colonists':
        planet.population += amount;
    }

    await UniverseStorage.instance.saveSectors([sector]);
    ActionLogProvider.global.info(
      'Transferred $amount $type to ${planet.name} ($cost cr)',
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
        planet.storedFighters -= actualAmount;
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
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace')),
        ],
      ),
    );
  }

  Widget _resourceBar(String label, int value, int max, Color color) {
    final cs = Theme.of(context).colorScheme;
    final fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 11)),
              Text(_formatNumber(value),
                  style: TextStyle(
                      fontSize: 11, fontFamily: 'monospace', color: color)),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: cs.surfaceContainerHighest,
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _defenseBar(String label, double value, double max, Color color) {
    final cs = Theme.of(context).colorScheme;
    final fraction = max > 0 ? (value / max).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label,
                  style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.6),
                      fontSize: 11)),
              Text('${value.toInt()} / ${max.toInt()}',
                  style: TextStyle(
                      fontSize: 11, fontFamily: 'monospace', color: color)),
            ],
          ),
          const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: fraction,
              backgroundColor: cs.surfaceContainerHighest,
              color: color,
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColonyCard(Planet planet, ColorScheme cs) {
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
            _infoRow('Colonists', _formatNumber(planet.population)),
            _infoRow('Minerals',
                '${planet.colonistsMinerals} → ${_formatNumber((planet.colonistsMinerals * (Planet.typeMultipliers[planet.planetType]?.minerals ?? 1.0) * planet.productionEfficiency).toInt())}/tick'),
            _infoRow('Organics',
                '${planet.colonistsOrganics} → ${_formatNumber((planet.colonistsOrganics * (Planet.typeMultipliers[planet.planetType]?.organics ?? 1.0) * planet.productionEfficiency).toInt())}/tick'),
            _infoRow('Industrial',
                '${planet.colonistsIndustrial} → ${_formatNumber((planet.colonistsIndustrial * (Planet.typeMultipliers[planet.planetType]?.industrial ?? 1.0) * planet.productionEfficiency).toInt())}/tick'),
            _infoRow('Drones',
                '${planet.colonistsFighters} → ${_formatNumber((planet.colonistsFighters * (Planet.typeMultipliers[planet.planetType]?.fighters ?? 1.0) * planet.productionEfficiency).toInt())}/tick'),
          ],
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

    final canLevel = planet.canLevelUp;
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
      ],
    );
  }

  Future<void> _levelUpPlanet(Planet planet) async {
    final sector = _currentSector;
    if (sector == null) return;

    if (!planet.levelUp()) return;

    await UniverseStorage.instance.saveSectors([sector]);
    ActionLogProvider.global.info(
      '${planet.name} reached level ${planet.level}',
    );
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
            _resourceBar('Minerals', planet.storedMinerals, planet.maxStorage,
                Colors.orange),
            _resourceBar('Organics', planet.storedOrganics, planet.maxStorage,
                Colors.green),
            _resourceBar('Industrial', planet.storedIndustrial,
                planet.maxStorage, Colors.blue),
            const SizedBox(height: 8),
            _infoRow('Storage',
                '${_formatNumber(planet.storedMinerals + planet.storedOrganics + planet.storedIndustrial)} / ${_formatNumber(planet.maxStorage)}'),
          ],
        ),
      ),
    );
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
                'Drones', planet.storedFighters, planet.maxStorage, Colors.red),
            const SizedBox(height: 4),
            _defenseBar('Shield', planet.shield, planet.maxShield, Colors.cyan),
            _defenseBar('Armor', planet.hull, planet.maxHull, Colors.green),
          ],
        ),
      ),
    );
  }
}
