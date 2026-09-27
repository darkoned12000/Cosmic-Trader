// NPC perception and memory upkeep: sector scans, dead-vendetta pruning, wingmate gossip.
part of 'npc_ai_service.dart';

// ────────────────────────────────────────────────────────────────
// Step 1 — Sector scanner
// ────────────────────────────────────────────────────────────────

NpcShip _scanSector(
  NpcShip npc,
  List<Sector> sectors,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  var memory = npc.memory;

  // Find the sector
  final sector = NpcAiService._findSector(sectors, npc.currentSectorId);
  if (sector == null) return npc;

  // Mark visited
  memory = memory.withVisitedSector(sector.id);

  // Time-decay grudges every turn (C2): returns `this` when nothing
  // expired, so the steady state costs nothing.
  memory = memory.pruneVendettas();

  // Discover port
  if (sector.hasPort && sector.port != null) {
    final p = sector.port!;
    memory = memory.withDiscoveredPort(
      sector.id,
      PortInfo(
        name: p.name,
        portClass: p.portClass,
        buyPrices: Map.from(p.buyPrices),
        sellPrices: Map.from(p.sellPrices),
        defenseLevel: p.defenseLevel,
        portCredits: p.portCredits,
        desiredCredits: p.desiredCredits,
        owner: p.owner,
        ownerFaction: p.ownerFaction,
        pricingOverride: switch (p.pricingOverride) {
          null => const {},
          final o => Map<String, double>.from(o),
        },
        sellFactors: {
          for (final c in p.sellPrices.keys)
            c: p.supplyPriceMultiplier(c) * p.driftFor(c),
        },
        buyFactors: {
          for (final c in p.buyPrices.keys)
            c: p.demandPriceMultiplier(c) *
                p.driftFor(c) *
                (p.regionalBuyBonus[c] ?? 1.0) *
                p.anomalyBuyBonus,
        },
      ),
    );
  }

  // Record hazards
  if (sector.navHaz || sector.anomaly != null) {
    memory = memory.withKnownHazard(
      sector.id,
      HazardInfo(navHaz: sector.navHaz, anomaly: sector.anomaly),
    );
  }

  // Detect threats (other factions in the same sector). Co-located
  // candidates come from the tick index when present (P2); the write
  // path below still resolves live objects, so stale refs only ever
  // nominate, never act.
  final mates =
      NpcAiService.npcsBySector?[sector.id] ?? allNpcs;
  final aliveIds = <String>{npc.id};
  for (final player in players) {
    aliveIds.add(player.id);
    if (player.currentSectorId == sector.id &&
        NpcAiService._isHostileFaction(npc.faction, player.faction)) {
      memory = memory.withThreat(player.id);
    }
  }
  final tickAlive = NpcAiService.livingIds;
  if (tickAlive != null) {
    aliveIds.addAll(tickAlive);
  }
  for (final other in mates) {
    if (tickAlive == null && !other.isDestroyed) {
      aliveIds.add(other.id);
    }
    if (other.id != npc.id &&
        other.currentSectorId == sector.id &&
        !other.isDestroyed &&
        NpcAiService._isHostileFaction(npc.faction, other.faction)) {
      memory = memory.withThreat(other.id);
    }
  }
  // Threats whose holders are gone stop being threats (review batch
  // 3, P1): without this the set only ever grows.
  memory = memory.pruneThreats(aliveIds);

  return npc.copyWith(memory: memory);
}

/// Wingmate gossip (C2d): co-located, same-faction, living allies trade
/// sightings after acting. Sightings only — each pilot keeps their own
/// grievance, and unknown killers arrive as hearsay (below the hunt
/// threshold). Both directions run: I learn theirs, they learn mine
/// (written back in place, like combat updates). Only genuinely new
/// adoptions get log lines; routine refreshes stay quiet so crowded
/// homeworlds don't flood the combat feed.
NpcShip _shareIntel(NpcShip npc, List<NpcShip> allNpcs) {
  var mine = npc.memory;
  var changed = false;
  // Candidacy from the tick index when present (P2); write-back always
  // resolves the live list slot by id, since indexed copies go stale as
  // turns run.
  final mates =
      NpcAiService.npcsBySector?[npc.currentSectorId] ?? allNpcs;
  for (final mate in mates) {
    if (mate.id == npc.id || mate.isDestroyed) continue;
    if (mate.faction != npc.faction) continue;
    if (mate.currentSectorId != npc.currentSectorId) continue;
    final learn = mine.mergeSightings(mate.memory.vendettas);
    if (learn.adopted > 0 || learn.refreshed > 0) {
      mine = learn.memory;
      changed = true;
      if (learn.adopted > 0) {
        GameEventLog.global
            .combat('[${npc.pilotName}] Heard about ${learn.adopted} killer(s) '
                'from ${mate.pilotName}');
      }
    }
    final teach = mate.memory.mergeSightings(mine.vendettas);
    if (teach.adopted > 0 || teach.refreshed > 0) {
      final li = allNpcs.indexWhere((n) => n.id == mate.id);
      if (li != -1) allNpcs[li] = mate.copyWith(memory: teach.memory);
      if (teach.adopted > 0) {
        GameEventLog.global.combat(
            '[${mate.pilotName}] Heard about ${teach.adopted} killer(s) '
            'from ${npc.pilotName}');
      }
    }
  }
  if (!changed) return npc;
  return npc.copyWith(memory: mine);
}

/// Drops vendetta entries whose targets are gone from the world (C2b):
/// absent from both the NPC roster and the player list, or present but
/// destroyed. Vengeance needs a living target. Returns the NPC
/// unchanged when nothing expired so callers can skip pointless saves.
NpcShip _pruneDeadVendettas(
  NpcShip npc,
  List<Player> players,
  List<NpcShip> allNpcs,
) {
  if (npc.memory.vendettas.isEmpty) return npc;
  var memory = npc.memory;
  // Liveness from the tick index when present (P2); a target destroyed
  // earlier this tick lingers one extra turn, then prunes.
  final tickAlive = NpcAiService.livingIds;
  for (final id in memory.vendettas.keys) {
    final npcGone = tickAlive != null
        ? !tickAlive.contains(id)
        : !allNpcs.any((n) => n.id == id && !n.isDestroyed);
    final playerGone = !players.any((p) => p.id == id);
    if (npcGone && playerGone) {
      memory = memory.withVendettaResolved(id);
      GameEventLog.global
          .combat('[${npc.pilotName}] Letting go of $id — gone from the world');
    }
  }
  if (identical(memory, npc.memory)) return npc;
  return npc.copyWith(memory: memory);
}
