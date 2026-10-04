import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/services/energy_service.dart';
import 'package:cosmic_trader/widgets/sector_view_widgets/action_log_provider.dart';

/// What a scan attempt did.
///
/// [performed] is false when the world was already scanned or the player could
/// not afford it — both are "nothing happened", and the caller needs to tell them
/// apart from a scan that succeeded only to learn nothing new.
class ScanResult {
  final Player player;
  final bool performed;

  const ScanResult(this.player, this.performed);
}

/// One scan verb, shared by every entry point.
///
/// There used to be two, and they had drifted into a state where the *cheap* one
/// was on the sector panel and the *expensive* one was on the planet tab, both
/// setting the same `scanned` flag and revealing the same detail — so the
/// 4-energy path was strictly dominated with nothing to recommend it. That was
/// not a balance question, it was the same rule implemented twice.
///
/// Scanning is a **simple** act: it costs one energy and tells you what a world
/// is. In-depth reconnaissance is a separate, more expensive verb that does not
/// exist yet, so there is deliberately nothing here for it to be confused with.
/// When it lands it should be a second cost constant and a second method on this
/// class, not a third price on this one.
///
/// **The standing reward is not information.** Scanning a world is a diplomatic
/// act toward whoever owns it, so it grants +1 standing — which is why merging
/// the two paths means the panel scan grants it too. Leaving the reward on only
/// one path would just have inverted the dominance: the *cheap* path would become
/// the poor one.
class ScanService {
  ScanService._();

  /// Scan [planet]: spend energy, set the flag, credit the owner, persist, log.
  ///
  /// [onPersist] is supplied by the caller because *how* to save is a property
  /// of the screen, not of the rule. The planet screen's version reports whether
  /// the write landed and retries it if not, and that must not be duplicated
  /// here or bypassed — a caller that swallows the result is a scan the player
  /// pays for twice with nothing on disk.
  ///
  /// Every step is committed before the call returns. A scan that costs energy
  /// but never persists is a scan the player pays for twice.
  static Future<ScanResult> scanPlanet({
    required Player player,
    required Planet planet,
    required Future<void> Function() onPersist,
  }) async {
    if (planet.scanned) return ScanResult(player, false);
    if (!EnergyService.canScan(player)) return ScanResult(player, false);

    var updated = player.spendEnergy(EnergyService.scanCost);
    final ownerFaction = planet.owner;
    if (ownerFaction != null) {
      updated = updated.withFactionStandingChange(ownerFaction, 1);
    }

    planet.scanned = true;
    await onPersist();
    ActionLogProvider.global.info(
      'Scan complete: ${planet.name} \u2014 ${planet.planetType}',
    );
    return ScanResult(updated, true);
  }
}
