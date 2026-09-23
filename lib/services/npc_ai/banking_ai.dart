import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';
import 'package:cosmic_trader/services/npc_ai/trade_evaluator.dart';

class BankingAi {
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
