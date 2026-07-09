import 'package:flutter/material.dart';

class CommunicationsPanel extends StatefulWidget {
  const CommunicationsPanel({super.key});

  @override
  State<CommunicationsPanel> createState() => _CommunicationsPanelState();
}

class _CommunicationsPanelState extends State<CommunicationsPanel>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              border: Border(
                bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: cs.primary,
              indicatorWeight: 2,
              labelColor: cs.primary,
              unselectedLabelColor: cs.onSurface.withValues(alpha: 0.5),
              labelStyle: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
              tabs: const [
                Tab(icon: Icon(Icons.chat_rounded, size: 14), text: 'CHAT'),
                Tab(icon: Icon(Icons.email_rounded, size: 14), text: 'MAIL'),
                Tab(
                    icon: Icon(Icons.assignment_rounded, size: 14),
                    text: 'QUESTS'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _ChatTab(),
                _MailTab(),
                _QuestsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat Tab ───────────────────────────────────────────────────

class _ChatTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final messages = _mockChatMessages;

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(8),
            itemCount: messages.length,
            separatorBuilder: (_, __) => const SizedBox(height: 4),
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _ChatBubble(
                sender: msg.sender,
                text: msg.text,
                isSystem: msg.isSystem,
                isNpc: msg.isNpc,
                colorScheme: cs,
              );
            },
          ),
        ),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            border: Border(
              top: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  enabled: false,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Transmit... (offline)',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: cs.onSurface.withValues(alpha: 0.25),
                    ),
                    filled: true,
                    fillColor:
                        cs.surfaceContainerHighest.withValues(alpha: 0.2),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.send_rounded,
                size: 18,
                color: cs.onSurface.withValues(alpha: 0.2),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String sender;
  final String text;
  final bool isSystem;
  final bool isNpc;
  final ColorScheme colorScheme;

  const _ChatBubble({
    required this.sender,
    required this.text,
    required this.isSystem,
    required this.isNpc,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final Color tagColor;
    final String tag;

    if (isSystem) {
      tagColor = colorScheme.primary;
      tag = 'SYS';
    } else if (isNpc) {
      tagColor = colorScheme.tertiary;
      tag = 'NPC';
    } else {
      tagColor = Colors.amber.shade300;
      tag = 'PLR';
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tagColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: tagColor,
                    fontFamily: 'monospace',
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                sender,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: tagColor,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurface.withValues(alpha: 0.8),
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

final _mockChatMessages = [
  _ChatMessage('System', 'Communications array online — 3 channels active.',
      isSystem: true),
  _ChatMessage('Duran Trader',
      'Hail, captain. If you\'ve got industrial goods, I\'ve got credits.',
      isNpc: true),
  _ChatMessage(
      'Vinari Scout', 'Pirate activity spiking near Sector 88. Advise caution.',
      isNpc: true),
  _ChatMessage('System', 'Encrypted transmission received on secure channel.',
      isSystem: true),
];

class _ChatMessage {
  final String sender;
  final String text;
  final bool isSystem;
  final bool isNpc;

  const _ChatMessage(this.sender, this.text,
      {this.isSystem = false, this.isNpc = false});
}

// ─── Mail Tab ───────────────────────────────────────────────────

class _MailTab extends StatefulWidget {
  @override
  State<_MailTab> createState() => _MailTabState();
}

class _MailTabState extends State<_MailTab> {
  final List<_MailEntry> _mails = List.of(_mockMail);

  void _openMail(int index) {
    final mail = _mails[index];
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => _MailDialog(
        mail: mail,
        colorScheme: cs,
        onDelete: () {
          setState(() => _mails.removeAt(index));
          Navigator.of(ctx).pop();
        },
        onMarkRead: () {
          if (mail.isNew) {
            setState(() => _mails[index] = _MailEntry(
                  sender: mail.sender,
                  subject: mail.subject,
                  body: mail.body,
                  timestamp: mail.timestamp,
                  isNew: false,
                ));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_mails.isEmpty) {
      return Center(
        child: Text(
          'INBOX CLEAR',
          style: TextStyle(
            fontSize: 11,
            fontFamily: 'monospace',
            letterSpacing: 2,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(8),
      itemCount: _mails.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: cs.outline.withValues(alpha: 0.1),
      ),
      itemBuilder: (context, index) {
        final mail = _mails[index];
        return InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => _openMail(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Row(
              children: [
                Icon(
                  mail.isNew
                      ? Icons.mark_email_unread_rounded
                      : Icons.email_rounded,
                  size: 16,
                  color: mail.isNew
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.3),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mail.sender,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        mail.subject,
                        style: TextStyle(
                          fontSize: 10,
                          fontFamily: 'monospace',
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (mail.isNew)
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _MailDialog extends StatelessWidget {
  final _MailEntry mail;
  final ColorScheme colorScheme;
  final VoidCallback onDelete;
  final VoidCallback onMarkRead;

  const _MailDialog({
    required this.mail,
    required this.colorScheme,
    required this.onDelete,
    required this.onMarkRead,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = colorScheme;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(14)),
                border: Border(
                  bottom: BorderSide(color: cs.outline.withValues(alpha: 0.2)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.email_rounded, size: 16, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          mail.subject,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      if (mail.isNew)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'NEW',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: cs.primary,
                              fontFamily: 'monospace',
                              letterSpacing: 1,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        'FROM',
                        style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontFamily: 'monospace',
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        mail.sender,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.tertiary,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const Spacer(),
                      Text(
                        mail.timestamp,
                        style: TextStyle(
                          fontSize: 9,
                          color: cs.onSurface.withValues(alpha: 0.4),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Body
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Text(
                  mail.body,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.6,
                    color: cs.onSurface.withValues(alpha: 0.85),
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),

            // Actions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: cs.outline.withValues(alpha: 0.15)),
                ),
              ),
              child: Row(
                children: [
                  _dialogButton(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text(
                            'Transmission offline — message queued',
                            style: TextStyle(fontFamily: 'monospace'),
                          ),
                          backgroundColor: cs.primary.withValues(alpha: 0.8),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    icon: Icons.reply_rounded,
                    label: 'RESPOND',
                    color: cs.primary,
                    cs: cs,
                  ),
                  const SizedBox(width: 8),
                  _dialogButton(
                    onPressed: onDelete,
                    icon: Icons.delete_outline_rounded,
                    label: 'DELETE',
                    color: cs.error,
                    cs: cs,
                  ),
                  const Spacer(),
                  _dialogButton(
                    onPressed: () {
                      onMarkRead();
                      Navigator.of(context).pop();
                    },
                    icon: Icons.close_rounded,
                    label: 'CLOSE',
                    color: cs.onSurface.withValues(alpha: 0.6),
                    cs: cs,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogButton({
    required VoidCallback onPressed,
    required IconData icon,
    required String label,
    required Color color,
    required ColorScheme cs,
  }) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1,
          fontFamily: 'monospace',
          color: color,
        ),
      ),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        foregroundColor: color,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: color.withValues(alpha: 0.3)),
        ),
      ),
    );
  }
}

final _mockMail = [
  _MailEntry(
    sender: 'Fleet Command',
    subject: 'Operation Titan — deployment orders',
    body:
        'Captain,\n\nYou have been selected for Operation Titan. Report to Sector 12 for briefing. This is a high-priority assignment.\n\nExpected duration: 7 cycles\nAssets: 1 light freighter\n\nAcknowledge receipt at your earliest convenience.\n\n— Fleet Command, Office of Naval Operations',
    timestamp: '2247.06.12 09:34',
    isNew: true,
  ),
  _MailEntry(
    sender: 'Trade Guild',
    subject: 'Monthly credit statement',
    body:
        'Greetings,\n\nYour account activity for this cycle:\n\n  Credits earned:    12,450\n  Credits spent:     8,200\n  Net change:       +4,250\n  Current balance:   67,890\n\nOutstanding trades: 3\nPending deliveries: 1\n\nThank you for your continued patronage.\n\n— Trade Guild Accounting Division',
    timestamp: '2247.06.10 14:12',
    isNew: false,
  ),
  _MailEntry(
    sender: 'Unknown Sender',
    subject: 'Your claim is waiting',
    body:
        'Captain,\n\nYou have been selected to receive a prize of 10,000 credits! To claim, simply provide your port access codes to the courier upon arrival.\n\nThis message will self-destruct.\n\n— A Benefactor',
    timestamp: '2247.06.13 03:01',
    isNew: true,
  ),
];

class _MailEntry {
  final String sender;
  final String subject;
  final String body;
  final String timestamp;
  final bool isNew;

  const _MailEntry({
    required this.sender,
    required this.subject,
    required this.body,
    required this.timestamp,
    this.isNew = false,
  });
}

// ─── Quests Tab ────────────────────────────────────────────────

enum _QuestStatus { active, completed, available }

class _QuestsTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(8),
      children: [
        _sectionHeader('ACTIVE', cs),
        ..._mockQuests
            .where((q) => q.status == _QuestStatus.active)
            .map((q) => _QuestTile(quest: q, colorScheme: cs)),
        const SizedBox(height: 12),
        _sectionHeader('COMPLETED', cs),
        ..._mockQuests
            .where((q) => q.status == _QuestStatus.completed)
            .map((q) => _QuestTile(quest: q, colorScheme: cs)),
        const SizedBox(height: 12),
        _sectionHeader('AVAILABLE', cs),
        ..._mockQuests
            .where((q) => q.status == _QuestStatus.available)
            .map((q) => _QuestTile(quest: q, colorScheme: cs)),
      ],
    );
  }

  Widget _sectionHeader(String title, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6, left: 2),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.5,
          fontFamily: 'monospace',
          color: cs.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }
}

class _QuestTile extends StatelessWidget {
  final _QuestEntry quest;
  final ColorScheme colorScheme;

  const _QuestTile({required this.quest, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final iconColor = switch (quest.status) {
      _QuestStatus.active => colorScheme.primary,
      _QuestStatus.completed => Colors.green,
      _QuestStatus.available => colorScheme.onSurface.withValues(alpha: 0.3),
    };
    final icon = switch (quest.status) {
      _QuestStatus.active => Icons.radio_button_checked_rounded,
      _QuestStatus.completed => Icons.check_circle_rounded,
      _QuestStatus.available => Icons.radio_button_unchecked_rounded,
    };
    final available = quest.status == _QuestStatus.available;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: available
              ? Colors.transparent
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: available
              ? Border.all(
                  color: colorScheme.outline.withValues(alpha: 0.15),
                )
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    quest.title,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                      color: available
                          ? colorScheme.onSurface.withValues(alpha: 0.5)
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text(
                quest.description,
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: available
                      ? colorScheme.onSurface.withValues(alpha: 0.35)
                      : colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
            if (quest.status == _QuestStatus.active && quest.progress > 0) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: quest.progress,
                    backgroundColor: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.3),
                    valueColor: AlwaysStoppedAnimation(
                      quest.progress >= 1.0
                          ? Colors.green
                          : colorScheme.primary,
                    ),
                    minHeight: 4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final _mockQuests = [
  _QuestEntry('Trade Route', 'Deliver 100 minerals to Sector 12',
      progress: 0.2, status: _QuestStatus.active),
  _QuestEntry('Explore Fringe', 'Visit 5 unexplored sectors beyond FedSpace',
      progress: 0.6, status: _QuestStatus.active),
  _QuestEntry('First Contact', 'Complete your first warp through a jump gate',
      progress: 1.0, status: _QuestStatus.completed),
  _QuestEntry('Bounty: Corsairs', 'Eliminate 3 pirate vessels near Sector 55',
      progress: 0.0, status: _QuestStatus.available),
  _QuestEntry('Supply Run', 'Sell 50 organics at an Independent port',
      progress: 0.0, status: _QuestStatus.available),
];

class _QuestEntry {
  final String title;
  final String description;
  final double progress;
  final _QuestStatus status;

  const _QuestEntry(this.title, this.description,
      {this.progress = 0.0, required this.status});
}
