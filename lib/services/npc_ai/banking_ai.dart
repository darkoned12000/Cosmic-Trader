import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/faction_standing.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

class BankingAi {
  /// Base daily rate; the Trade Guild scales it by standing.
  static const double baseDailyRate = 0.01;

  /// Daily bank rate for [faction] with [standings] toward the Guild —
  /// beloved clients earn up to 1.2%, blacklisted ones as little as 0.5%.
  /// Shared by player banking and NPC accrual so both sides play by it.
  static double interestRateFor(
    FactionClass faction,
    Map<String, int> standings,
  ) {
    final standing =
        FactionStanding.resolveFor(faction, FactionClass.trader, standings);
    return (baseDailyRate * (1 + standing * 0.002)).clamp(0.005, 0.015);
  }

  /// Interest owed since [lastInterestTime], or null when no period has
  /// elapsed yet (first balance starts the clock with no retro payout).
  /// Pure math — the tick loop applies the result.
  /// Credits owed for whole days elapsed since [lastInterestTick].
  ///
  /// Same rule as the player's, deliberately: one game day is
  /// `GameClock.ticksPerDay` ticks and the stamp advances by **whole days only**,
  /// so a partial day carries forward instead of being discarded. The old code
  /// stamped "now" after paying, so an NPC paid every tick paid `floor(one day's
  /// worth)` over and over — which at a 30-second tick is 2,880 partial payouts
  /// instead of one, and silently *over*-paid by the discarded remainders. Two
  /// copies of one rule with opposite rounding errors is the shape that motivated
  /// putting the period in `GameClock` at all.
  ///
  /// Returns the interest and the stamp to write, or null when nothing is due.
  static ({int interest, int stamp})? accrueInterest({
    required int bankBalance,
    required int? lastInterestTick,
    required double rate,
    required int nowTick,
  }) {
    if (bankBalance <= 0) return null;
    if (lastInterestTick == null) {
      return (interest: 0, stamp: nowTick);
    }
    final elapsed = nowTick - lastInterestTick;
    if (elapsed < GameClock.ticksPerDay) return null;
    // Pay for the **whole days consumed** and advance by exactly those.
    //
    // The two halves have to agree or the rule leaks. My first version paid for
    // the fractional `days` (1.5 days of interest) while advancing the stamp by
    // the whole ones (1 day), so the next payout charged a full day for the same
    // half day: 2,500 cr over two days where the rate says 2,000. Paying only
    // for `wholeDays` makes the two agree by construction, and the remainder
    // stays owed instead of being paid twice.
    final wholeDays = elapsed ~/ GameClock.ticksPerDay;
    final interest = (bankBalance * rate * wholeDays).floor();
    if (interest <= 0) return null;
    return (
      interest: interest,
      stamp: lastInterestTick + wholeDays * GameClock.ticksPerDay,
    );
  }

  /// Check if NPC should deposit on-ship credits at a port.
  static bool shouldDeposit(NpcShip npc) {
    if (npc.credits <= 0) return false;
    final threshold = (npc.personalityConfig.caution * 100000).round();
    return npc.credits > threshold && npc.bankBalance < npc.credits * 0.5;
  }

  /// Check if NPC should withdraw banked credits for a big purchase.
  static bool shouldWithdraw(NpcShip npc) {
    if (npc.bankBalance <= 0) return false;
    // Withdraw when planning upgrades or running low on cash
    final goal = npc.currentGoal;
    if (goal?.type == NpcGoalType.upgradeEquipment && npc.credits < 50000) {
      return npc.bankBalance >= 50000;
    }
    // General case: withdraw if nearly out of cash and have bank reserves
    return npc.credits < 10000 && npc.bankBalance >= 50000;
  }

  /// Create a bank deposit goal for the nearest port.
  static NpcGoal? createDepositGoal(NpcShip npc, List<Sector> sectors) {
    final portSectorId =
        TradeEvaluator.findNearestPort(npc.currentSectorId, sectors);
    if (portSectorId == null) return null;

    final depositAmount = (npc.credits * 0.7).round().clamp(1, npc.credits);

    return NpcGoal(
      type: NpcGoalType.bankDeposit,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': portSectorId,
        'depositAmount': depositAmount,
      },
    );
  }

  /// Create a bank withdraw goal for the nearest port.
  static NpcGoal? createWithdrawGoal(NpcShip npc, List<Sector> sectors) {
    final portSectorId =
        TradeEvaluator.findNearestPort(npc.currentSectorId, sectors);
    if (portSectorId == null) return null;

    final withdrawAmount = (50000).clamp(1, npc.bankBalance);

    return NpcGoal(
      type: NpcGoalType.bankWithdraw,
      status: NpcGoalStatus.travelling,
      createdAt: DateTime.now(),
      params: {
        'targetSectorId': portSectorId,
        'withdrawAmount': withdrawAmount,
      },
    );
  }

  /// Execute a deposit goal: transfer credits from ship to bank.
  static ({NpcShip npc, bool executed}) executeDeposit(
    NpcShip npc,
    NpcGoal goal,
  ) {
    final depositAmount =
        (goal.params['depositAmount'] as int?)?.clamp(1, npc.credits) ?? 0;
    if (depositAmount <= 0) return (npc: npc, executed: false);

    return (
      npc: npc.copyWith(
        credits: npc.credits - depositAmount,
        bankBalance: npc.bankBalance + depositAmount,
      ),
      executed: true,
    );
  }

  /// Execute a withdraw goal: transfer credits from bank to ship.
  static ({NpcShip npc, bool executed}) executeWithdraw(
    NpcShip npc,
    NpcGoal goal,
  ) {
    final withdrawAmount =
        (goal.params['withdrawAmount'] as int?)?.clamp(1, npc.bankBalance) ?? 0;
    if (withdrawAmount <= 0) return (npc: npc, executed: false);

    return (
      npc: npc.copyWith(
        credits: npc.credits + withdrawAmount,
        bankBalance: npc.bankBalance - withdrawAmount,
      ),
      executed: true,
    );
  }
}
