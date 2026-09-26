import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/port.dart';

/// Dialog for purchasing a port through haggling. Styled to match the
/// compact HUD look used in port_trade_view.dart: a terminal-style
/// negotiation log with a talkative owner, a hard round limit, and a
/// heartbeat-pulsing "think fast" timer on the offer box.
class BuyPortDialog extends StatefulWidget {
  final Port port;
  final Player player;
  final Function(Player) onPlayerUpdate;
  final void Function(Port) onPortUpdated;
  final VoidCallback onCancel;

  const BuyPortDialog({
    super.key,
    required this.port,
    required this.player,
    required this.onPlayerUpdate,
    required this.onPortUpdated,
    required this.onCancel,
  });

  @override
  State<BuyPortDialog> createState() => _BuyPortDialogState();
}

enum _ChannelPhase { connecting, open }

class _BuyPortDialogState extends State<BuyPortDialog>
    with SingleTickerProviderStateMixin {
  static const int _maxRounds = 4;
  static const double _thinkSeconds = 20;
  static const Duration _connectDelay = Duration(milliseconds: 5000);

  // ---------------------------------------------------------------------
  // Owner flavor lines. Picked based on how good/bad the offer is, or how
  // the negotiation ultimately ends. Tweak freely -- purely cosmetic.
  // ---------------------------------------------------------------------

  static const _acceptLines = [
    "Pleasure doing business! First round of synth-ale is on me tonight.",
    "Deal! I've been eyeing a new hyperdrive coil for this old girl.",
    "You drive a hard bargain, captain. Enjoy the keys -- I'm retiring to the Kepler resorts.",
    "Sold! Finally enough for that plasma cannon upgrade I've wanted.",
    "A pleasure, captain. This'll cover my daughter's academy tuition nicely.",
    "Deal done. Time to pay off some... let's call them 'business debts'.",
    "Excellent! This is going straight into a new cargo freighter.",
    "Sold, and not a moment too soon -- my creditors were getting impatient.",
    "You've got yourself a port! I hear Alpha Centauri has lovely beaches this time of year.",
    "Deal! This buys a lot of drinks at the Nova Cantina. Fly safe, captain.",
  ];

  static const _closeCounterLines = [
    "Getting warmer, captain. Sweeten it a little more?",
    "Close, but my ship needs new thrusters too. Come up a bit?",
    "You're almost there. One more push and we've got a deal.",
    "Not bad at all. Meet me a little higher and it's yours.",
    "I like where this is going. Just a touch more, captain.",
    "Reasonable offer. Let's split the difference.",
    "You're a serious buyer, I can tell. Nudge it up and we're square.",
    "Almost fair. Show me you mean business.",
  ];

  static const _grudgingCounterLines = [
    "Insulting, but I'll pretend I didn't hear that. Try again.",
    "That offer stings, captain. Come back with something respectable.",
    "I've had better offers from pirates. Try harder.",
    "You want a discount, not a port. Raise it.",
    "That's cargo-hold change, not port money. Try again.",
    "My grandmother offers better than that, and she's been dead ten years.",
    "I'm insulted, but business is business. Counter's on the table.",
    "Do I look desperate to you, captain? Raise your offer.",
  ];

  static const _lowballRejectLines = [
    "Are you serious right now? Get out of my sector.",
    "That offer is an insult to this station's ancestors.",
    "I'd sooner sell to space pirates than take that garbage offer.",
    "Laughable. Come back when you've actually got credits, captain.",
    "You must think I fell off a cargo hauler yesterday.",
    "That's not an offer, that's a joke with extra steps.",
    "Absolutely not. Try that again and I'm cutting comms.",
    "Cute number. Now offer me something real.",
    "I run a port, not a charity. Try again.",
    "That's less than my scrap metal is worth. Pathetic.",
  ];

  static const _impatienceLines = [
    "Hey! You contacted me, captain. Quit wasting my time.",
    "I don't have all cycle. Make an offer or move along.",
    "Silence isn't a negotiating tactic. Say something.",
    "You still there, captain, or did your comms freeze up?",
    "Tick tock. I've got other buyers lined up, you know.",
    "This isn't a staring contest. Offer me a number.",
    "I'm a busy owner, captain. Don't leave me hanging.",
    "You went quiet. Cold feet, or just slow on the keypad?",
    "Every second you stall, I like this deal less.",
    "Speak up or sign off, captain. My patience has a timer too.",
  ];

  static const _farewellPolite = [
    "No hard feelings, captain. Maybe next visit.",
    "You were close. Come back when the credits catch up.",
    "Fair effort. The offer's on the record, but we're done for now.",
    "Almost had a deal there. Until next time, safe travels.",
    "You're clearly serious, just not quite there yet. Try again later.",
    "Respectable haggling, captain. This port isn't going anywhere.",
    "We'll call this round a draw. Come back with a fresh offer sometime.",
    "Good effort. I'll keep the airlock open for you next time.",
  ];

  static const _farewellSarcastic = [
    "That's as close as we're getting today. Nice try, captain.",
    "You'll have to do better than that next time around.",
    "I've heard worse offers, I suppose. That's not a compliment.",
    "We're done here. Bring real credits next time.",
    "Charming effort. Charmingly insufficient.",
    "That'll be a no from me. Go rob a cargo hauler and come back.",
    "Negotiations closed. Your offers were... memorable, at least.",
    "I admire the persistence. Not the numbers, though.",
  ];

  static const _farewellSavage = [
    "Get off my frequency. You wasted my whole cycle, captain.",
    "This channel is closed. Don't bother calling back.",
    "You want a port? Save up for a decade and try again.",
    "I've dealt with vacuum leaks more reasonable than you.",
    "That's it. I'm flagging your ship's registry at this port.",
    "Negotiations over. Go sell scrap somewhere else.",
    "You showed up empty-handed and left the same way. Typical.",
    "This was a waste of good oxygen. Goodbye, captain.",
    "I've had asteroids offer better deals. Get lost.",
    "Some captains negotiate. You just wasted my morning. Don't come back.",
  ];

  final _rng = Random();
  String _pick(List<String> pool) => pool[_rng.nextInt(pool.length)];

  late final TextEditingController _offerController;
  late final AnimationController _heartbeatController;

  double _askingPrice = 0;
  double _ownerCounter = 0;
  double _bestOfferRatio = 0; // best offer ever made, as a fraction of asking
  int _round = 0;
  bool _negotiating = false;
  bool _dealClosed = false;
  String _inputError = '';

  final List<({int round, String speaker, String text, String type})> _log = [];

  Timer? _thinkTimer;
  Timer? _connectTimer;
  double _timeLeft = _thinkSeconds;
  _ChannelPhase _phase = _ChannelPhase.connecting;

  @override
  void initState() {
    super.initState();
    _offerController = TextEditingController();
    _heartbeatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..repeat(reverse: true);
    _calculateAskingPrice();
    _connectTimer = Timer(_connectDelay, () {
      if (!mounted) return;
      setState(() {
        _phase = _ChannelPhase.open;
        _log.add((
          round: 0,
          speaker: 'system',
          text:
              'Negotiations opened. Send your offer -- ${_thinkSeconds.toInt()}s on the clock.',
          type: 'system',
        ));
      });
      _startThinkTimer();
    });
  }

  void _calculateAskingPrice() {
    final netWorth = widget.port.netWorth;
    _askingPrice = netWorth * (1.2 + (netWorth > 100000 ? 0.3 : 0.1));
    _ownerCounter = _askingPrice;
  }

  String _formatCredits(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(2)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    }
    return value.toStringAsFixed(0);
  }

  // ---------------------------------------------------------------------
  // Think-timer: player has _thinkSeconds to submit an offer each round.
  // The heartbeat border speeds up as time runs low. Running out burns a
  // round and gets a scolding instead of silently doing nothing.
  // ---------------------------------------------------------------------

  void _startThinkTimer() {
    _thinkTimer?.cancel();
    setState(() => _timeLeft = _thinkSeconds);
    _thinkTimer = Timer.periodic(const Duration(milliseconds: 100), (t) {
      if (!mounted) return;
      setState(() {
        _timeLeft -= 0.1;
        final urgency = (1 - (_timeLeft / _thinkSeconds)).clamp(0.0, 1.0);
        _heartbeatController.duration =
            Duration(milliseconds: (700 - urgency * 480).round());
      });
      if (_timeLeft <= 0) {
        t.cancel();
        _handleTimeout();
      }
    });
  }

  void _handleTimeout() {
    if (_negotiating || _dealClosed) return;
    setState(() {
      _round++;
      _offerController.clear();
      _log.add((
        round: _round,
        speaker: 'owner',
        text: _pick(_impatienceLines),
        type: 'error',
      ));
      if (_round >= _maxRounds) {
        _dealClosed = true;
        _log.add((
          round: _round,
          speaker: 'owner',
          text: _pickFarewellLine(),
          type: 'error',
        ));
      }
    });
    if (!_dealClosed) {
      _startThinkTimer();
    }
  }

  String _pickFarewellLine() {
    if (_bestOfferRatio >= 0.85) return _pick(_farewellPolite);
    if (_bestOfferRatio >= 0.6) return _pick(_farewellSarcastic);
    return _pick(_farewellSavage);
  }

  void _makeOffer() {
    if (_dealClosed || _negotiating) return;

    final offer = double.tryParse(_offerController.text)?.roundToDouble();
    if (offer == null || offer <= 0) {
      setState(() => _inputError = 'Enter a valid offer amount');
      return;
    }

    _thinkTimer?.cancel();

    final ratioToAsking = offer / _askingPrice;
    if (ratioToAsking > _bestOfferRatio) _bestOfferRatio = ratioToAsking;

    setState(() {
      _inputError = '';
      _negotiating = true;
      _round++;
      _log.add((
        round: _round,
        speaker: 'you',
        text: 'Offered ${_formatCredits(offer)} cr',
        type: 'you',
      ));
    });

    final preCounter = _ownerCounter;

    // Simulate owner response
    Future.delayed(const Duration(milliseconds: 800), () {
      if (!mounted) return;

      if (offer >= preCounter) {
        setState(() {
          _log.add((
            round: _round,
            speaker: 'owner',
            text:
                'Deal! ${_formatCredits(offer)} cr accepted. ${_pick(_acceptLines)}',
            type: 'success',
          ));
        });
        _completePurchase(offer);
        return;
      }

      final atRoundLimit = _round >= _maxRounds;

      if (offer >= preCounter * 0.7) {
        _ownerCounter = (offer + preCounter) / 2;
        final tierRatio = offer / preCounter;
        final line = tierRatio >= 0.85
            ? _pick(_closeCounterLines)
            : _pick(_grudgingCounterLines);
        setState(() {
          _negotiating = false;
          _log.add((
            round: _round,
            speaker: 'owner',
            text: atRoundLimit
                ? '$line (Counter: ${_formatCredits(_ownerCounter)} cr.)'
                : '$line Counter: ${_formatCredits(_ownerCounter)} cr.',
            type: 'warning',
          ));
          if (atRoundLimit) {
            _dealClosed = true;
            _log.add((
              round: _round,
              speaker: 'owner',
              text: _pickFarewellLine(),
              type: 'error',
            ));
          }
        });
      } else {
        setState(() {
          _negotiating = false;
          _log.add((
            round: _round,
            speaker: 'owner',
            text: _pick(_lowballRejectLines),
            type: 'error',
          ));
          if (atRoundLimit) {
            _dealClosed = true;
            _log.add((
              round: _round,
              speaker: 'owner',
              text: _pickFarewellLine(),
              type: 'error',
            ));
          }
        });
      }

      if (!_dealClosed) {
        _startThinkTimer();
      }
    });
  }

  void _completePurchase(double price) {
    if (widget.player.credits < price) {
      if (widget.player.bankBalance >= price) {
        final updated = widget.player.copyWith(
          credits: widget.player.credits,
          bankBalance: widget.player.bankBalance - price.toInt(),
          ownedPorts: [...widget.player.ownedPorts, widget.port.name],
        );
        widget.onPlayerUpdate(updated);
      } else {
        setState(() {
          _negotiating = false;
          _log.add((
            round: _round,
            speaker: 'system',
            text: 'Insufficient funds. Need ${_formatCredits(price)} cr.',
            type: 'error',
          ));
        });
        return;
      }
    } else {
      final updated = widget.player.copyWith(
        credits: widget.player.credits - price.toInt(),
        ownedPorts: [...widget.player.ownedPorts, widget.port.name],
      );
      widget.onPlayerUpdate(updated);
    }

    widget.onPortUpdated(widget.port.copyWith(
      owner: widget.player.name,
      ownerId: widget.player.id,
      ownerFaction: widget.player.faction,
    ));

    setState(() => _dealClosed = true);

    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        widget.onCancel();
      }
    });
  }

  @override
  void dispose() {
    _thinkTimer?.cancel();
    _connectTimer?.cancel();
    _heartbeatController.dispose();
    _offerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const mono = 'monospace';
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final interactive =
        _phase == _ChannelPhase.open && !_negotiating && !_dealClosed;
    final urgency =
        interactive ? (1 - (_timeLeft / _thinkSeconds)).clamp(0.0, 1.0) : 0.0;

    return AlertDialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.onSurface.withValues(alpha: 0.12)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      title: Row(
        children: [
          Icon(Icons.handshake_rounded, color: cs.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'Negotiate port purchase',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.85,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),

              // Port identity
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border:
                      Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.store_rounded, size: 18, color: cs.tertiary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.port.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          if (widget.port.owner != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'current owner: ${widget.port.owner}',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface.withValues(alpha: 0.5),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      '${_formatCredits(widget.port.netWorth)} net',
                      style: TextStyle(
                        fontFamily: mono,
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Deal stats strip: current ask / your credits / bank balance
              Container(
                decoration: BoxDecoration(
                  border:
                      Border.all(color: cs.onSurface.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: _dealStat(
                        cs,
                        mono,
                        'current ask',
                        _formatCredits(_ownerCounter),
                        valueColor: cs.primary,
                        subValue: _ownerCounter != _askingPrice
                            ? _formatCredits(_askingPrice)
                            : null,
                      ),
                    ),
                    SizedBox(
                      height: 28,
                      child: VerticalDivider(
                        width: 1,
                        thickness: 1,
                        color: cs.onSurface.withValues(alpha: 0.1),
                      ),
                    ),
                    Expanded(
                      child: _dealStat(
                        cs,
                        mono,
                        'your credits',
                        _formatCredits(widget.player.credits.toDouble()),
                      ),
                    ),
                    if (widget.player.bankBalance > 0) ...[
                      SizedBox(
                        height: 28,
                        child: VerticalDivider(
                          width: 1,
                          thickness: 1,
                          color: cs.onSurface.withValues(alpha: 0.1),
                        ),
                      ),
                      Expanded(
                        child: _dealStat(
                          cs,
                          mono,
                          'bank',
                          _formatCredits(widget.player.bankBalance.toDouble()),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Negotiation log -- terminal-style comms channel
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.22),
                  border:
                      Border.all(color: cs.onSurface.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.04),
                        border: Border(
                          bottom: BorderSide(
                              color: cs.onSurface.withValues(alpha: 0.1)),
                        ),
                      ),
                      child: Row(
                        children: [
                          _channelDot(
                            _dealClosed
                                ? Colors.redAccent
                                : _phase == _ChannelPhase.connecting
                                    ? Colors.amberAccent
                                    : Colors.greenAccent,
                            animate: !_dealClosed,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'SELLER CHANNEL',
                            style: TextStyle(
                              fontFamily: mono,
                              fontSize: 10,
                              letterSpacing: 1,
                              color: cs.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _phase == _ChannelPhase.connecting
                                ? 'CONNECTING...'
                                : 'ROUND $_round/$_maxRounds',
                            style: TextStyle(
                              fontFamily: mono,
                              fontSize: 10,
                              letterSpacing: 0.5,
                              color: _phase == _ChannelPhase.connecting
                                  ? Colors.amberAccent.shade200
                                  : cs.onSurface.withValues(alpha: 0.45),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(
                        minHeight: 56,
                        maxHeight: 170,
                      ),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: _log.isEmpty
                          ? Text(
                              _phase == _ChannelPhase.connecting
                                  ? 'Establishing connection with port owner... please standby.'
                                  : 'No transmissions yet. Make an offer to open negotiations.',
                              style: TextStyle(
                                fontFamily: mono,
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.35),
                              ),
                            )
                          : SingleChildScrollView(
                              reverse: true,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final entry in _log)
                                    _logLine(cs, mono, entry),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Offer input + countdown
              Row(
                children: [
                  Text(
                    'YOUR OFFER',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.6,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  const Spacer(),
                  if (interactive)
                    Text(
                      '${_timeLeft.clamp(0, _thinkSeconds).toStringAsFixed(1)}s',
                      style: TextStyle(
                        fontFamily: mono,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color:
                            Color.lerp(cs.primary, Colors.redAccent, urgency),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (interactive)
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: (_timeLeft / _thinkSeconds).clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: cs.onSurface.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation(
                        Color.lerp(cs.primary, Colors.redAccent, urgency)!),
                  ),
                ),
              const SizedBox(height: 6),
              AnimatedBuilder(
                animation: _heartbeatController,
                builder: (context, child) {
                  final beat = 0.5 + 0.5 * sin(_heartbeatController.value * pi);
                  final borderColor = interactive
                      ? Color.lerp(cs.primary, Colors.redAccent, urgency)!
                      : cs.onSurface.withValues(alpha: 0.15);
                  final glow = interactive
                      ? (0.12 + 0.3 * beat) * (0.4 + urgency * 0.6)
                      : 0.0;
                  return Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: interactive
                            ? borderColor.withValues(alpha: 0.55 + 0.45 * beat)
                            : borderColor,
                        width: interactive ? 1.4 + beat * 0.8 : 1,
                      ),
                      boxShadow: interactive
                          ? [
                              BoxShadow(
                                color: borderColor.withValues(alpha: glow),
                                blurRadius: 10,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: child,
                  );
                },
                child: TextField(
                  controller: _offerController,
                  keyboardType: TextInputType.number,
                  enabled: interactive,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _makeOffer(),
                  style: const TextStyle(fontFamily: mono, fontSize: 15),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    hintText: _dealClosed
                        ? 'Channel closed'
                        : _phase == _ChannelPhase.connecting
                            ? 'Connecting...'
                            : 'Enter amount',
                    hintStyle: TextStyle(
                      fontFamily: mono,
                      color: cs.onSurface.withValues(alpha: 0.3),
                    ),
                    suffixText: 'cr',
                    suffixStyle: TextStyle(
                      fontFamily: mono,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (_inputError.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _inputError,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.redAccent.shade200,
                    ),
                  ),
                ),
              const SizedBox(height: 10),

              // Quick offer chips -- based on the current live ask
              Row(
                children: [
                  _quickOfferChip(
                      cs, mono, '50%', _ownerCounter * 0.5, interactive),
                  const SizedBox(width: 6),
                  _quickOfferChip(
                      cs, mono, '75%', _ownerCounter * 0.75, interactive),
                  const SizedBox(width: 6),
                  _quickOfferChip(
                      cs, mono, '90%', _ownerCounter * 0.9, interactive),
                  const SizedBox(width: 6),
                  _quickOfferChip(cs, mono, '100%', _ownerCounter, interactive),
                ],
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actions: [
        TextButton(
          onPressed: _negotiating ? null : widget.onCancel,
          child: Text(
            _dealClosed ? 'Close' : 'Cancel',
            style: TextStyle(color: cs.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        FilledButton.icon(
          onPressed: interactive ? _makeOffer : null,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          ),
          icon: _negotiating
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.handshake_rounded, size: 16),
          label: Text(
            _negotiating
                ? 'Transmitting...'
                : _dealClosed
                    ? 'Channel closed'
                    : 'Make offer',
          ),
        ),
      ],
    );
  }

  Widget _dealStat(
    ColorScheme cs,
    String mono,
    String label,
    String value, {
    Color? valueColor,
    String? subValue,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 10, color: cs.onSurface.withValues(alpha: 0.5)),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            if (subValue != null) ...[
              Text(
                subValue,
                style: TextStyle(
                  fontFamily: mono,
                  fontSize: 10,
                  decoration: TextDecoration.lineThrough,
                  color: cs.onSurface.withValues(alpha: 0.3),
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              value,
              style: TextStyle(
                fontFamily: mono,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: valueColor ?? cs.onSurface,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickOfferChip(
    ColorScheme cs,
    String mono,
    String label,
    double amount,
    bool enabled,
  ) {
    return Expanded(
      child: OutlinedButton(
        onPressed: enabled
            ? () {
                _offerController.text = amount.toStringAsFixed(0);
              }
            : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: const Size(0, 0),
          side: BorderSide(color: cs.onSurface.withValues(alpha: 0.18)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.8),
              ),
            ),
            Text(
              _formatCredits(amount),
              style: TextStyle(
                fontFamily: mono,
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _channelDot(Color color, {required bool animate}) {
    return AnimatedBuilder(
      animation: _heartbeatController,
      builder: (context, _) {
        final opacity = animate
            ? 0.3 + 0.7 * (0.5 + 0.5 * sin(_heartbeatController.value * pi))
            : 1.0;
        return Opacity(
          opacity: opacity,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        );
      },
    );
  }

  Widget _logLine(
    ColorScheme cs,
    String mono,
    ({int round, String speaker, String text, String type}) entry,
  ) {
    final roleLabel = switch (entry.speaker) {
      'you' => 'YOU',
      'owner' => 'OWNER',
      _ => 'SYS',
    };
    final roleColor = switch (entry.type) {
      'you' => Colors.cyanAccent.shade200,
      'success' => Colors.greenAccent.shade200,
      'warning' => Colors.amberAccent.shade200,
      'error' => Colors.redAccent.shade100,
      'system' => Colors.lightBlueAccent.shade100,
      _ => cs.onSurface.withValues(alpha: 0.7),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: mono,
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.85),
          ),
          children: [
            TextSpan(
              text: '[R${entry.round}] ',
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.35)),
            ),
            TextSpan(
              text: '$roleLabel  ',
              style: TextStyle(color: roleColor, fontWeight: FontWeight.w700),
            ),
            TextSpan(text: entry.text),
          ],
        ),
      ),
    );
  }
}
