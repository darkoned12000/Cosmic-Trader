import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/services/npc_ai/npc_goal.dart';

enum NpcPersonality {
  traderMerchant,
  traderExplorer,
  traderSmuggler,
  duranConqueror,
  duranWarlord,
  duranCollector,
  vinariExplorer,
  vinariProtector,
  vinariSeeker,
  pirateRaider,
  piratePillager,
  pirateHunter,
}

class PersonalityConfig {
  final Map<NpcGoalType, double> goalWeights;
  final double aggression;
  final double greed;
  final double caution;
  final double explorationDrive;
  final int maxTravelDistance;

  const PersonalityConfig({
    required this.goalWeights,
    required this.aggression,
    required this.greed,
    required this.caution,
    required this.explorationDrive,
    required this.maxTravelDistance,
  });

  static const Map<NpcPersonality, PersonalityConfig> all = {
    // ── Traders ──────────────────────────────────────
    NpcPersonality.traderMerchant: PersonalityConfig(
      goalWeights: {
        NpcGoalType.tradeRoute: 0.60,
        NpcGoalType.explore: 0.15,
        NpcGoalType.patrol: 0.05,
      },
      aggression: 0.1,
      greed: 0.6,
      caution: 0.7,
      explorationDrive: 0.4,
      maxTravelDistance: 30,
    ),
    NpcPersonality.traderExplorer: PersonalityConfig(
      goalWeights: {
        NpcGoalType.explore: 0.60,
        NpcGoalType.tradeRoute: 0.25,
        NpcGoalType.patrol: 0.05,
      },
      aggression: 0.05,
      greed: 0.3,
      caution: 0.5,
      explorationDrive: 0.9,
      maxTravelDistance: 60,
    ),
    NpcPersonality.traderSmuggler: PersonalityConfig(
      goalWeights: {
        NpcGoalType.tradeRoute: 0.50,
        NpcGoalType.patrol: 0.05,
      },
      aggression: 0.2,
      greed: 0.8,
      caution: 0.6,
      explorationDrive: 0.5,
      maxTravelDistance: 40,
    ),

    // ── Duran ────────────────────────────────────────
    NpcPersonality.duranConqueror: PersonalityConfig(
      goalWeights: {
        NpcGoalType.attack: 0.40,
        NpcGoalType.raidPort: 0.20,
        NpcGoalType.tradeRoute: 0.20,
        NpcGoalType.upgradeEquipment: 0.10,
        NpcGoalType.explore: 0.10,
      },
      aggression: 0.9,
      greed: 0.5,
      caution: 0.3,
      explorationDrive: 0.6,
      maxTravelDistance: 50,
    ),
    NpcPersonality.duranWarlord: PersonalityConfig(
      goalWeights: {
        NpcGoalType.attack: 0.50,
        NpcGoalType.upgradeEquipment: 0.20,
        NpcGoalType.patrol: 0.10,
        NpcGoalType.tradeRoute: 0.05,
        NpcGoalType.explore: 0.15,
      },
      aggression: 0.95,
      greed: 0.4,
      caution: 0.2,
      explorationDrive: 0.5,
      maxTravelDistance: 40,
    ),
    NpcPersonality.duranCollector: PersonalityConfig(
      goalWeights: {
        NpcGoalType.raidPort: 0.35,
        NpcGoalType.attack: 0.25,
        NpcGoalType.tradeRoute: 0.20,
        NpcGoalType.explore: 0.05,
      },
      aggression: 0.7,
      greed: 0.8,
      caution: 0.5,
      explorationDrive: 0.3,
      maxTravelDistance: 35,
    ),

    // ── Vinari ───────────────────────────────────────
    NpcPersonality.vinariExplorer: PersonalityConfig(
      goalWeights: {
        NpcGoalType.explore: 0.65,
        NpcGoalType.patrol: 0.15,
        NpcGoalType.tradeRoute: 0.10,
        NpcGoalType.upgradeEquipment: 0.05,
      },
      aggression: 0.05,
      greed: 0.2,
      caution: 0.6,
      explorationDrive: 1.0,
      maxTravelDistance: 80,
    ),
    NpcPersonality.vinariProtector: PersonalityConfig(
      goalWeights: {
        NpcGoalType.patrol: 0.45,
        NpcGoalType.attack: 0.25,
        NpcGoalType.explore: 0.15,
        NpcGoalType.upgradeEquipment: 0.10,
        NpcGoalType.tradeRoute: 0.05,
      },
      aggression: 0.5,
      greed: 0.1,
      caution: 0.4,
      explorationDrive: 0.3,
      maxTravelDistance: 30,
    ),
    NpcPersonality.vinariSeeker: PersonalityConfig(
      goalWeights: {
        NpcGoalType.explore: 0.55,
        NpcGoalType.patrol: 0.20,
        NpcGoalType.tradeRoute: 0.15,
      },
      aggression: 0.1,
      greed: 0.3,
      caution: 0.5,
      explorationDrive: 0.8,
      maxTravelDistance: 60,
    ),

    // ── Pirates ──────────────────────────────────────
    NpcPersonality.pirateRaider: PersonalityConfig(
      goalWeights: {
        NpcGoalType.attack: 0.45,
        NpcGoalType.raidPort: 0.25,
        NpcGoalType.tradeRoute: 0.10,
      },
      aggression: 0.8,
      greed: 0.9,
      caution: 0.2,
      explorationDrive: 0.5,
      maxTravelDistance: 40,
    ),
    NpcPersonality.piratePillager: PersonalityConfig(
      goalWeights: {
        NpcGoalType.raidPort: 0.45,
        NpcGoalType.attack: 0.25,
        NpcGoalType.tradeRoute: 0.10,
      },
      aggression: 0.85,
      greed: 0.95,
      caution: 0.3,
      explorationDrive: 0.4,
      maxTravelDistance: 35,
    ),
    NpcPersonality.pirateHunter: PersonalityConfig(
      goalWeights: {
        NpcGoalType.attack: 0.55,
        NpcGoalType.explore: 0.20,
        NpcGoalType.tradeRoute: 0.10,
      },
      aggression: 0.9,
      greed: 0.7,
      caution: 0.1,
      explorationDrive: 0.6,
      maxTravelDistance: 50,
    ),
  };
}

NpcPersonality assignPersonalityForFaction(
    FactionClass faction, math.Random rng) {
  switch (faction) {
    case FactionClass.trader:
      return [
        NpcPersonality.traderMerchant,
        NpcPersonality.traderExplorer,
        NpcPersonality.traderSmuggler,
      ][rng.nextInt(3)];
    case FactionClass.duran:
      return [
        NpcPersonality.duranConqueror,
        NpcPersonality.duranWarlord,
        NpcPersonality.duranCollector,
      ][rng.nextInt(3)];
    case FactionClass.vinari:
      return [
        NpcPersonality.vinariExplorer,
        NpcPersonality.vinariProtector,
        NpcPersonality.vinariSeeker,
      ][rng.nextInt(3)];
    case FactionClass.pirate:
      return [
        NpcPersonality.pirateRaider,
        NpcPersonality.piratePillager,
        NpcPersonality.pirateHunter,
      ][rng.nextInt(3)];
  }
}
