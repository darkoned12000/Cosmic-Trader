import 'dart:math' as math;

import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';

/// Scrap recovered from a destroyed ship.
class SalvageReward {
  final int scrapMetal;
  final int scrapTech;

  const SalvageReward({
    required this.scrapMetal,
    required this.scrapTech,
  });
}

/// Salvage rules for destroyed NPC ships.
///
/// Previously combat only dropped credits + cargo, so players had no way to
/// build up the scrap metal / scrap tech required by Hardware Emporium modules.
/// This service owns the drop ranges so combat surfaces stay thin and rates can
/// be tuned in one place.
class SalvageService {
  SalvageService._();

  /// Base scrap-metal drop by ship class.
  static const Map<ShipClassType, int> scrapMetalBase = {
    ShipClassType.interceptor: 20,
    ShipClassType.battleship: 45,
    ShipClassType.freighter: 40,
    ShipClassType.capitalShip: 90,
  };

  /// Base scrap-tech drop by ship class.
  static const Map<ShipClassType, int> scrapTechBase = {
    ShipClassType.interceptor: 4,
    ShipClassType.battleship: 8,
    ShipClassType.freighter: 7,
    ShipClassType.capitalShip: 15,
  };

  /// Rolls salvage for destroying [npc].
  ///
  /// Ships that were generated with explicit scrap loot keep that value; older
  /// saves fall back to a class-based roll so existing saves are not dead ends.
  static SalvageReward rollForNpc(
    NpcShip npc, {
    math.Random? rng,
  }) {
    if (npc.scrapMetal > 0 || npc.scrapTech > 0) {
      return SalvageReward(
        scrapMetal: npc.scrapMetal,
        scrapTech: npc.scrapTech,
      );
    }

    final random = rng ?? math.Random();
    final metalBase = scrapMetalBase[npc.shipDef.shipClass] ?? 20;
    final techBase = scrapTechBase[npc.shipDef.shipClass] ?? 4;

    final metalMin = (metalBase * 0.6).round();
    final metalMax = (metalBase * 1.4).round();
    final techMin = math.max(1, (techBase * 0.5).round());
    final techMax = math.max(techMin, (techBase * 1.5).round());

    final scrapMetal = metalMin + random.nextInt(metalMax - metalMin + 1);
    final scrapTech = techMin + random.nextInt(techMax - techMin + 1);

    return SalvageReward(
      scrapMetal: scrapMetal,
      scrapTech: scrapTech,
    );
  }

  /// Adds [reward] to a player, clamped at zero negatives for safety.
  static Player applyToPlayer(Player player, SalvageReward reward) {
    return player.copyWith(
      scrapMetal:
          player.scrapMetal + (reward.scrapMetal < 0 ? 0 : reward.scrapMetal),
      scrapTech:
          player.scrapTech + (reward.scrapTech < 0 ? 0 : reward.scrapTech),
    );
  }
}
