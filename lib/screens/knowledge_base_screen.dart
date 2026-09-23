import 'package:flutter/material.dart' hide Hero;
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:flutter_svg/flutter_svg.dart';

class KnowledgeBaseScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const KnowledgeBaseScreen({super.key, this.onBack});

  @override
  State<KnowledgeBaseScreen> createState() => _KnowledgeBaseScreenState();
}

class _KnowledgeBaseScreenState extends State<KnowledgeBaseScreen> {
  final Set<int> _expandedIds = {};

  void _toggleExpand(int id) {
    setState(() {
      if (_expandedIds.contains(id)) {
        _expandedIds.remove(id);
      } else {
        _expandedIds.add(id);
      }
    });
  }

  IconData _factionIcon(FactionClass fc) {
    switch (fc) {
      case FactionClass.duran:
        return Icons.shield_moon_rounded;
      case FactionClass.vinari:
        return Icons.auto_awesome_rounded;
      case FactionClass.trader:
        return Icons.storefront_rounded;
      case FactionClass.pirate:
        return Icons.warning_rounded;
    }
  }

  Color _factionColor(FactionClass fc) {
    switch (fc) {
      case FactionClass.duran:
        return Colors.redAccent;
      case FactionClass.vinari:
        return Colors.purpleAccent;
      case FactionClass.trader:
        return Colors.amber;
      case FactionClass.pirate:
        return Colors.cyanAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final factions = Faction.allFactions();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: widget.onBack,
        ),
        title: const Text('Knowledge Base'),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: factions.length,
        itemBuilder: (context, index) {
          final faction = factions[index];
          final isExpanded = _expandedIds.contains(index);
          final color = _factionColor(faction.factionClass);

          return Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                  color: Colors.grey.withValues(alpha: 0.2), width: 1),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _toggleExpand(index),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            _factionIcon(faction.factionClass),
                            color: color,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                faction.name,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Text(
                                faction.motto,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontStyle: FontStyle.italic,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down),
                      ],
                    ),
                    if (isExpanded) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      // Banner Image
                      if (faction.banner.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SvgPicture.asset(
                            faction.banner,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            placeholderBuilder: (context) => const SizedBox(
                              height: 160,
                              child: Center(child: CircularProgressIndicator()),
                            ),
                            errorBuilder: (context, error, stackTrace) =>
                                Container(
                              height: 160,
                              width: double.infinity,
                              color: Colors.grey[900],
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.image_not_supported,
                                      size: 48, color: Colors.grey),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Banner not found\n${faction.banner}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      _section(theme, 'Background', faction.background, color),
                      _section(theme, 'History', faction.history, color),
                      _section(theme, 'Philosophy', faction.philosophy, color),
                      _section(
                          theme, 'Government', faction.governmentType, color),
                      _section(theme, 'Economy', faction.economicStyle, color),
                      _section(
                          theme, 'Technology', faction.techSignature, color),
                      _section(
                          theme, 'Motivations', faction.motivations, color),
                      _section(theme, 'Race Relations', faction.racerelations,
                          color),
                      _section(theme, 'Appearance', faction.appearance, color),
                      if (faction.notableHeroes.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          'NOTABLE HEROES',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...faction.notableHeroes
                            .map((hero) => _heroCard(theme, hero)),
                      ],

                      if (faction.keyEvents.isNotEmpty)
                        _section(theme, 'Key Events',
                            faction.keyEvents.join('\n• '), color),

                      if (faction.loreHooks.isNotEmpty)
                        _section(theme, 'Lore Hooks',
                            faction.loreHooks.join('\n• '), color),

                      if (faction.notableLocations.isNotEmpty)
                        _section(
                          theme,
                          'Notable Locations',
                          faction.notableLocations.entries
                              .map((e) => "• ${e.key}: ${e.value}")
                              .join('\n'),
                          color,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _section(
      ThemeData theme, String title, String content, Color accentColor) {
    if (content.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            content.replaceAll('<br>', '\n'),
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.55),
          ),
        ],
      ),
    );
  }

  Widget _heroCard(ThemeData theme, Hero hero) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hero.name,
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            Text(hero.title,
                style:
                    theme.textTheme.bodyMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 6),
            Text(hero.shortBio),
            if (hero.notableAchievement.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text("Notable Achievement: ${hero.notableAchievement}",
                  style: const TextStyle(fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }
}
