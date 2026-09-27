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

  /// Target ids paid out this session: load-merge must not resurrect
  /// them as zombies (paid pre-load, disk still carries them).
  final Set<String> _paidIds = {};

  /// Lifetime payouts this universe (the `_paid` list itself caps at 20
  /// for display). Answers "is it 20 again?" — yes, the window is full;
  /// the lifetime count keeps score.
  int paidLifetime = 0;

  /// Cap on live bounties (review batch 3, P3): only payKiller trims,
  /// so unclaimed marks on long-dead targets would pile up forever.
  /// Oldest evicts first.
  static const int maxActiveBounties = 200;

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
  /// [excludePosterId] drops self-posts (bounty review H3): posting on
  /// your own mark must never mint reputation.
  List<String> posterFactionsFor(String targetId,
      {String? excludePosterId}) {
    return {
      for (final b in forTarget(targetId))
        if (b.posterFaction.isNotEmpty &&
            b.posterId != excludePosterId)
          b.posterFaction,
    }.toList();
  }

  /// Removes live marks whose targets are gone from the world (bounty
  /// review M2): neither on the NPC roster nor among players. Logs the
  /// sweep; unclaimed poster credits lapse (escrow is roadmap).
  void pruneAbsent(Set<String> liveIds) {
    final before = _active.length;
    _active.removeWhere((b) => !liveIds.contains(b.targetId));
    final pruned = before - _active.length;
    if (pruned > 0) {
      GameEventLog.global.system(
        '[Bounty] Pruned $pruned mark(s) on vanished targets',
      );
      notifyListeners();
      _persist();
    }
  }

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
    // Merge, don't replace (bounty review M3): posts landing mid-load
    // used to be wiped when the disk snapshot applied. In-memory marks
    // (this session's posts) always survive; disk fills the rest, minus
    // ids already paid out this session (no zombie resurrection).
    for (final b in data.active) {
      if (_active.every((e) => e.id != b.id) &&
          !_paidIds.contains(b.targetId)) {
        _active.add(b);
      }
    }
    if (_paid.isEmpty) _paid.addAll(data.paid);
    if (paidLifetime == 0) paidLifetime = data.paidLifetime;
    notifyListeners();
  }

  Future<void> _persist() => BountyStorage.instance.saveAll(
        _active,
        _paid,
        paidLifetime: paidLifetime,
      );

  /// Clears the board for a fresh universe (soak-found bug: regen kept
  /// ~50 stale marks on dead NPC ids, and zero ever paid out against
  /// them). Persists the empty board so restarts stay clean too.
  Future<void> resetForNewUniverse() async {
    _active.clear();
    _paid.clear();
    _paidIds.clear();
    paidLifetime = 0;
    notifyListeners();
    await _persist();
  }

  /// Minimum postable amount (bounty review): dust marks are spam and
  /// rounding noise, not contracts.
  static const int minBountyAmount = 100;

  /// Max live marks per poster (bounty review): a 200-cr flood should
  /// never evict real contracts.
  static const int maxBountiesPerPoster = 10;

  /// Posts a bounty. Returns null when [amount] is below
  /// [minBountyAmount], [targetId] is empty, or the poster is at their
  /// [maxBountiesPerPoster] cap. The caller deducts the credits (player
  /// wallet or NPC bankroll).
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
    if (amount < minBountyAmount) return null;
    if (targetId.isEmpty) return null;
    final posterCount =
        _active.where((b) => b.posterId == posterId).length;
    if (posterCount >= maxBountiesPerPoster) {
      GameEventLog.global.system(
        '[Bounty] $posterName at poster cap — mark on $targetName refused',
      );
      return null;
    }
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
    // Evict the cheapest mark first (bounty review): a flood of minimum
    // posts pushes out other minimum posts, never the high-value heads.
    while (_active.length > maxActiveBounties) {
      var cheapest = 0;
      for (var i = 1; i < _active.length; i++) {
        if (_active[i].amount < _active[cheapest].amount) cheapest = i;
      }
      final evicted = _active.removeAt(cheapest);
      GameEventLog.global.system(
        '[Bounty] Board full — cheapest mark (${evicted.targetName} '
        '${evicted.amount} cr) expired unclaimed',
      );
    }
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
    String killerFaction = '',
    String targetFaction = '',
  }) {
    final owed = forTarget(targetId);
    if (owed.isEmpty) return 0;
    var total = 0;
    for (final b in owed) {
      total += b.amount;
      _active.remove(b);
    }
    _recordPaid(
      targetId,
      targetName,
      targetFaction.isNotEmpty
          ? targetFaction
          : owed.first.targetFaction,
      killerName,
      killerFaction,
      total,
    );
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
    String killerFaction = '',
    String targetFaction = '',
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
      killerFaction: killerFaction,
      targetFaction: targetFaction,
    );
    return total;
  }

  void _recordPaid(
    String targetId,
    String targetName,
    String targetFaction,
    String killerName,
    String killerFaction,
    int total,
  ) {
    paidLifetime++;
    _paidIds.add(targetId);
    _paid.insert(
      0,
      PaidBounty(
        targetName: targetName,
        targetFaction: targetFaction,
        killerName: killerName,
        killerFaction: killerFaction,
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
