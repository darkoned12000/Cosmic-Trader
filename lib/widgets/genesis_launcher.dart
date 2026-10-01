import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/data/storage/universe_storage.dart';
import 'package:cosmic_trader/services/world_forging.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';

/// What a completed launch produced, for the call site to narrate.
class GenesisLaunchOutcome {
  /// The world now in the sector.
  final Planet world;

  /// The player with the torpedo already spent. `WorldForging.launch` owns that
  /// decrement, so this must be what the caller hands back to the shell —
  /// decrementing again here would make a launch cost two torpedoes.
  final Player player;

  /// Whether this launch pushed the sector past `planetsPerSector`.
  final bool overStacked;

  const GenesisLaunchOutcome({
    required this.world,
    required this.player,
    required this.overStacked,
  });
}

/// The whole Genesis Torpedo flow: roll, name, launch, warn, persist.
///
/// Shared by both launch controls — the Ship screen's Cargo & Equipment card
/// and the Sector Contents panel's orbit row — because they used to carry two
/// hand-written copies of the over-stack warning, and the only thing keeping
/// them equal was remembering to edit both. A rule or a dialog that two screens
/// both need belongs to one function; that is the same reasoning that moved the
/// torpedo decrement out of the caller and into `WorldForging`.
///
/// Order matters and is not negotiable. The **type is rolled first**, then the
/// dialog names what the player got, then the launch happens. Rolling inside
/// the launch would mean the naming dialog is asking about a world that does
/// not exist yet and can only describe it in the abstract; showing the roll
/// first means the dialog can say "a Desert world" instead of "something".
/// Aborting costs nothing, because the torpedo is spent by [WorldForging.launch]
/// and that is never reached.
///
/// Returns null when the player aborted, or had no torpedoes. The caller is
/// responsible for handing [GenesisLaunchOutcome.player] back to the shell and
/// for telling the player what happened; persistence happens here.
Future<GenesisLaunchOutcome?> runGenesisLaunch({
  required BuildContext context,
  required Player player,
  required Sector sector,
  required int worldCap,
  math.Random? rng,
}) async {
  if (player.genesisTorpedoes <= 0) return null;

  final random = rng ?? math.Random();
  final type = WorldForging.rollType(random);
  // Offered as the prefill rather than generated inside `launch`, so the field
  // is never empty in front of a player who has just committed to a world.
  final suggested = WorldForging.suggestName(type, sector, random);

  // The type is deliberately **not** passed to the dialog. It was shown in the
  // title ("A Mountain World"), which turned the naming step into a free reroll:
  // read the type, abort if it was wrong, fire again. Abort costs nothing today
  // because the torpedo is spent inside `launch`, which an abort never reaches.
  // The type is revealed after the fact — the action log and the landing.
  final name = await _askForName(
    context,
    suggested: suggested,
    sectorName: sector.name,
    slotsUsed: sector.worldSlotsUsed,
    worldCap: worldCap,
  );
  if (name == null || !context.mounted) return null;

  final (result, world, spent) = WorldForging.launch(
    player: player,
    sector: sector,
    cap: worldCap,
    rng: random,
    tick: GameClock.tick,
    // Both handed back explicitly: passing the rolled type is what keeps the
    // dialog honest, and passing the name is the whole point of the dialog.
    type: type,
    name: name,
  );
  if (world == null || !context.mounted) return null;

  final overStacked = result == LaunchResult.wouldOverstack;

  if (overStacked && !context.mounted) return null;
  if (overStacked) {
    final proceed = await _confirmOverStack(
      context,
      sector: sector,
      world: world,
      worldCap: worldCap,
    );
    // The torpedo is already spent — it was fired, and owning the risk is the
    // point of the hazard. Aborting this dialog cannot un-fire it, so it is a
    // warning with a continue, not a confirmation gate.
    if (proceed != true) {
      await _persist(sector);
      return GenesisLaunchOutcome(
        world: world,
        player: spent,
        overStacked: true,
      );
    }
  }

  await _persist(sector);
  ActionLogProvider.global.trade(
    'Genesis Torpedo fired in ${sector.name}: a new ${world.planetType} '
    'world, ${world.name} '
    '(reputation +${ReputationActions.createWorld.toInt()})',
  );
  return GenesisLaunchOutcome(
    world: world,
    player: spent,
    overStacked: overStacked,
  );
}

/// Write through, or the world is resurrected: every screen holds its own
/// object graph and the tick re-reads from disk, so a change living only in
/// this copy is undone on the next load and the player finds the world they
/// just paid for missing.
Future<void> _persist(Sector sector) =>
    UniverseStorage.instance.saveSectors([sector]);

/// The naming dialog. Prefilled, cancellable, and it says what was rolled.
///
/// A `StatefulWidget` purely so the controller has an owner with a real
/// lifecycle. Disposing it from the caller in a `finally` right after
/// `showDialog` returns disposes it *while the route is still animating out* —
/// the popping `TextField` then builds against a disposed controller, which
/// throws mid-frame and takes the rest of the launch flow down with it. It also
/// leaked focus state into every later test in the file.
Future<String?> _askForName(
  BuildContext context, {
  required String suggested,
  required String sectorName,
  required int slotsUsed,
  required int worldCap,
}) =>
    showDialog<String>(
      context: context,
      builder: (ctx) => _NameWorldDialog(
        suggested: suggested,
        sectorName: sectorName,
        slotsUsed: slotsUsed,
        worldCap: worldCap,
      ),
    );

class _NameWorldDialog extends StatefulWidget {
  final String suggested;
  final String sectorName;
  final int slotsUsed;
  final int worldCap;

  const _NameWorldDialog({
    required this.suggested,
    required this.sectorName,
    required this.slotsUsed,
    required this.worldCap,
  });

  @override
  State<_NameWorldDialog> createState() => _NameWorldDialogState();
}

class _NameWorldDialogState extends State<_NameWorldDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.suggested);

  /// Tracked in state so the confirm button can be **disabled** on an empty name.
  ///
  /// The first version silently substituted the suggestion instead. That is
  /// worse than refusing: the player who cleared the box to type their own name
  /// gets a world called something they never chose, with no indication that
  /// their input was discarded.
  late bool _hasName = widget.suggested.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    final has = _controller.text.trim().isNotEmpty;
    if (has == _hasName) return;
    setState(() => _hasName = has);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = _controller.text.trim();
    if (v.isEmpty) return; // belt and braces: the button is already disabled
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: Icon(Icons.rocket_launch_rounded,
          color: theme.colorScheme.primary, size: 30),
      title: const Text('Planet Creation Process Initiated\u2026'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'The torpedo resolves in ${widget.sectorName}. This world is yours '
            'from the moment it condenses — no survey needed.',
            style: const TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Name this world',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (widget.slotsUsed >= widget.worldCap)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Heads up: ${widget.sectorName} already holds '
                '${widget.slotsUsed} worlds against a limit of '
                '${widget.worldCap}, so this one leaves the system '
                'gravitationally unstable.',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abort'),
        ),
        FilledButton(
          onPressed: _hasName ? _submit : null,
          child: const Text('Launch'),
        ),
      ],
    );
  }
}

/// The over-stack confirmation. Says what the hazard is and what undoes it.
Future<bool> _confirmOverStack(
  BuildContext context, {
  required Sector sector,
  required Planet world,
  required int worldCap,
}) async {
  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.warning_amber_rounded,
          color: Theme.of(ctx).colorScheme.error, size: 30),
      title: const Text('System Unstable'),
      content: Text(
        '${sector.name} now holds ${sector.worldSlotsUsed} worlds against a '
        'limit of $worldCap. ${world.name} is legal, but the system will roll '
        'for a collision every 24 hours and a bad roll destroys a pair of '
        'worlds. The only way back is an Atomic Detonator.',
        style: const TextStyle(fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Continue'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Understood'),
        ),
      ],
    ),
  );
  return proceed ?? false;
}
