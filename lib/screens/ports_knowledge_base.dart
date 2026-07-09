import 'package:flutter/material.dart';

class PortsKnowledgeBaseScreen extends StatelessWidget {
  const PortsKnowledgeBaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ports Guide'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            theme,
            cs,
            Icons.store_rounded,
            'Port Classes',
            [
              'Federal Ports — Government-controlled hubs in FedSpace. Cannot be purchased. Defense levels 0-4.',
              'Free Ports — Open trading ports outside FedSpace. Can be purchased through haggling.',
              'Independent Ports — Self-governed ports. Can be purchased through haggling.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.shield_rounded,
            'Port Defense Levels',
            [
              'Level 0: No defenses',
              'Level 1: Laser turrets',
              'Level 2: Laser turrets + drones',
              'Level 3: Laser turrets + drones + missiles',
              'Level 4: Laser turrets + drones + missiles + EMP pulse',
              '',
              'Defense level contributes to port net worth. Higher defense = higher asking price.',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.science_rounded,
            'Hacking Mini-Game',
            [
              'Crack a 3-digit security code to gain access to port systems.',
              '',
              'Rules:',
              '• 5 attempts per hacking session',
              '• 3 max hack attempts per port (daily)',
              '• Locked digits turn green and stay fixed',
              '• Unique digits only — no repeats in the code',
              '',
              'Penalties for failure:',
              '• 1st failure: 500 credits deducted',
              '• 2nd failure: 2,500 credits deducted',
              '• 3rd failure: 5,000 credits + 24-hour IP ban',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.bolt_rounded,
            'Frequency Jamming',
            [
              'Match the port\'s security frequency to steal resources.',
              '',
              'How it works:',
              '• Adjust frequency, amplitude, and phase parameters',
              '• Match the target signal within 45 seconds',
              '• Signal strength indicator shows how close you are',
              '• Circles appear at >70% match',
              '',
              'The oscilloscope displays 4 waveform layers:',
              '• Target signal (what you need to match)',
              '• Your signal (what you\'re producing)',
              '• Noise/static interference',
              '• Background static',
              '',
              'Success: You can steal resources from the port.',
              'Failure: Port security is alerted (DETECTED).',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.handshake_rounded,
            'Purchasing Ports',
            [
              'Non-Federal ports can be purchased through haggling with the owner.',
              '',
              'Asking price:',
              '• Based on port\'s net worth (resources + credits + defense value)',
              '• Multiplier: 1.2x-1.5x depending on net worth',
              '',
              'Negotiation:',
              '• Quick offers: 50%, 75%, 90%, or 100% of asking price',
              '• Custom offers: Enter any amount',
              '• Offers at 70%+ of counter offer → owner counters (average of both)',
              '• Offers below 70% → rejected',
              '• Match or exceed counter offer → accepted',
              '',
              'Payment:',
              '• Paid from your credits',
              '• Bank financing available if you have sufficient bank balance',
              '',
              'After purchase:',
              '• Port added to your owned ports list',
              '• Access to Port Management features',
            ],
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.admin_panel_settings_rounded,
            'Port Management',
            [
              'Available only to port owners.',
              '',
              'Coming soon:',
              '• Upgrade port defenses',
              '• Set commodity buy/sell prices',
              '• Collect port revenue',
              '• Manage port staff and operations',
            ],
            comingSoon: true,
          ),
          const SizedBox(height: 12),
          _sectionCard(
            theme,
            cs,
            Icons.info_outline_rounded,
            'Tips',
            [
              'Port net worth is displayed on the port screen. Use it to gauge asking price.',
              '',
              'When haggling, start at 75% and work up. The owner will counter-offer.',
              '',
              'Hacking penalties escalate quickly. Only hack if you\'re confident.',
              '',
              'Frequency jamming has a 45-second timer. Practice makes perfect.',
              '',
              'Owned ports appear on your Ship Status screen. Tap to navigate.',
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard(
    ThemeData theme,
    ColorScheme cs,
    IconData icon,
    String title,
    List<String> lines, {
    bool comingSoon = false,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: cs.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (comingSoon)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Coming Soon',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ...lines.map((line) {
              if (line.isEmpty) return const SizedBox(height: 6);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurface.withValues(alpha: 0.75),
                    height: 1.4,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
