import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/storage/bounty_storage.dart';
import 'package:cosmic_trader/services/game_event_log.dart';

/// The bounty board (B4): post bounties, auto-pay NPC kills, player claims.
///
/// Posting is open to everyone: players post from the Computer → Bounty
/// Board view (credits deducted on post); NPC survivors of an attack post
/// from their own bankroll. NPC kills pay the killer immediately (they
/// have no UI to file with); player kills record the victim id and pay
/// out through the board's Claim action. Paid history is kept (last 20).
class BountyBoard extends ChangeNotifier {
  static BountyBoard get global => _instance ??= BountyBoard._();
  static BountyBoard? _instance;

  BountyBoard._();

  final List<Bounty> _active = [];
  final List<PaidBounty> _paid = [];
  bool _loaded = false;

  List<Bounty> get active => List.unmodifiable(_active);
  List<PaidBounty> get paid => List.unmodifiable(_paid);

  /// Federation bounty for a notoriety level: 0 below 50, otherwise
  /// notoriety × 100 clamped to [5000, 100000]. Pure rule for tests.
  static int fedAmount(double notoriety) {
    if (notoriety < 50) return 0;
    return (notoriety * 100).round().clamp(5000, 100000);
  }

  /// Distinct poster factions owed on [targetId] (for completion
  /// standing). Empty factions (Federation Marshal) carry no standing.
  List<String> posterFactionsFor(String targetId) => {
        for (final b in forTarget(targetId))
          if (b.posterFaction.isNotEmpty) b.posterFaction,
      }.toList();

  /// Total active credits per target id (multiple posters stack).
  int totalFor(String targetId) => _active
      .where((b) => b.targetId == targetId)
      .fold(0, (a, b) => a + b.amount);

  List<Bounty> forTarget(String targetId) =>
      _active.where((b) => b.targetId == targetId).toList();

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    final data = await BountyStorage.instance.loadAll();
    _active
      ..clear()
      ..addAll(data.active);
    _paid
      ..clear()
      ..addAll(data.paid);
    notifyListeners();
  }

  Future<void> _persist() => BountyStorage.instance.saveAll(_active, _paid);

  /// Posts a bounty. Returns null when [amount] is not positive. The
  /// caller deducts the credits (player wallet or NPC bankroll).
  Bounty? post({
    required String targetId,
    required String targetName,
    required String targetFaction,
    bool targetIsPlayer = false,
    required int amount,
    required String posterId,
    required String posterName,
    String posterFaction = '',
    String reason = '',
  }) {
    if (amount <= 0) return null;
    final bounty = Bounty(
      id: const Uuid().v4(),
      targetId: targetId,
      targetName: targetName,
      targetFaction: targetFaction,
      targetIsPlayer: targetIsPlayer,
      amount: amount,
      posterId: posterId,
      posterName: posterName,
      posterFaction: posterFaction,
      reason: reason,
      createdAt: DateTime.now(),
    );
    _active.add(bounty);
    GameEventLog.global.system(
      '[Bounty] $posterName posted $amount cr on $targetName'
      '${reason.isNotEmpty ? ' ($reason)' : ''}',
    );
    notifyListeners();
    _persist();
    return bounty;
  }

  /// Pays all active bounties on [targetId] to the killer. Used by NPC
  /// kill resolution (instant underworld payout). Returns credits paid.
  int payKiller({
    required String targetId,
    required String killerName,
    required String targetName,
  }) {
    final owed = forTarget(targetId);
    if (owed.isEmpty) return 0;
    var total = 0;
    for (final b in owed) {
      total += b.amount;
      _active.remove(b);
    }
    _recordPaid(targetName, killerName, total);
    GameEventLog.global.combat(
      '[Bounty] $killerName collected $total cr for $targetName',
    );
    notifyListeners();
    _persist();
    return total;
  }

  /// Player files a claim through the board view. The kill MUST be
  /// verified here (not just in the UI): [verifiedKills] are victim ids
  /// this killer definitively destroyed. Returns credits paid, 0 when
  /// nothing is owed or the kill is unverified. A bare targetId is never
  /// enough — otherwise any caller could drain any stacked bounty.
  int claim({
    required String targetId,
    required String targetName,
    required String killerName,
    required Set<String> verifiedKills,
  }) {
    if (!verifiedKills.contains(targetId)) {
      GameEventLog.global.system(
        '[Bounty] Claim denied for $killerName on $targetName '
        '(kill not verified)',
      );
      return 0;
    }
    final total = payKiller(
      targetId: targetId,
      killerName: killerName,
      targetName: targetName,
    );
    return total;
  }

  void _recordPaid(String targetName, String killerName, int total) {
    _paid.insert(
      0,
      PaidBounty(
        targetName: targetName,
        killerName: killerName,
        amount: total,
        paidAt: DateTime.now(),
      ),
    );
    while (_paid.length > 20) {
      _paid.removeLast();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _instance = null;
  }
}
