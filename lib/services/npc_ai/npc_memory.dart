import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/port.dart';

class PortInfo {
  final String name;
  final PortClass portClass;
  final Map<String, double> buyPrices;
  final Map<String, double> sellPrices;
  final int defenseLevel;
  final double portCredits;
  final double desiredCredits;
  final String? owner;
  final FactionClass? ownerFaction;

  /// Scanned local multipliers (supply depth for sells, demand depth +
  /// drift + regionals + anomaly for buys), snapshotted at scan time so
  /// route selection prices the same stack as live execution. Missing keys
  /// read 1.0 (older saves).
  final Map<String, double> sellFactors;
  final Map<String, double> buyFactors;

  /// Owner price overrides, snapshotted (review batch 3, P1): live
  /// execution applies them outright, so selection must too — otherwise
  /// owner-customized ports misprice during route evaluation.
  final Map<String, double> pricingOverride;

  const PortInfo({
    required this.name,
    required this.portClass,
    required this.buyPrices,
    required this.sellPrices,
    this.defenseLevel = 0,
    this.portCredits = 0,
    this.desiredCredits = 0,
    this.owner,
    this.ownerFaction,
    this.sellFactors = const {},
    this.buyFactors = const {},
    this.pricingOverride = const {},
  });

  /// Deep equality so scans can skip unchanged snapshots (review batch
  /// 3, P1): map `==` is identity, so compare contents.
  static bool _pricesEqual(Map<String, double> a, Map<String, double> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) {
    return other is PortInfo &&
        other.name == name &&
        other.portClass == portClass &&
        _pricesEqual(other.buyPrices, buyPrices) &&
        _pricesEqual(other.sellPrices, sellPrices) &&
        other.defenseLevel == defenseLevel &&
        other.portCredits == portCredits &&
        other.desiredCredits == desiredCredits &&
        other.owner == owner &&
        other.ownerFaction == ownerFaction &&
        _pricesEqual(other.sellFactors, sellFactors) &&
        _pricesEqual(other.buyFactors, buyFactors) &&
        _pricesEqual(other.pricingOverride, pricingOverride);
  }

  @override
  int get hashCode => Object.hash(
        name,
        portClass,
        defenseLevel,
        portCredits,
        desiredCredits,
        owner,
        ownerFaction,
      );

  double get cashRatio {
    if (desiredCredits <= 0) return 1.0;
    return (portCredits / desiredCredits).clamp(0.1, 3.0);
  }

  double get priceMultiplier => 0.5 + 0.5 * cashRatio;

  double getEffectiveSellPrice(String commodity, {int standing = 0}) {
    final base = sellPrices[commodity] ?? 0;
    if (base <= 0) return 0;
    // Owner override wins outright, mirroring live execution exactly.
    if (pricingOverride.containsKey(commodity)) {
      return base * pricingOverride[commodity]!;
    }
    final mult = (priceMultiplier *
            (sellFactors[commodity] ?? 1.0) *
            Port.standingBuyMultiplier(standing))
        .clamp(Port.minEffectiveMultiplier, Port.maxEffectiveMultiplier);
    return base * mult;
  }

  double getEffectiveBuyPrice(String commodity, {int standing = 0}) {
    final base = buyPrices[commodity] ?? 0;
    if (base <= 0) return 0;
    if (pricingOverride.containsKey(commodity)) {
      return base * pricingOverride[commodity]!;
    }
    final mult = (priceMultiplier *
            (buyFactors[commodity] ?? 1.0) *
            Port.standingSellMultiplier(standing))
        .clamp(Port.minEffectiveMultiplier, Port.maxEffectiveMultiplier);
    return base * mult;
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'portClass': portClass.name,
      'buyPrices': buyPrices,
      'sellPrices': sellPrices,
      'defenseLevel': defenseLevel,
      'portCredits': portCredits,
      'desiredCredits': desiredCredits,
      'owner': owner,
      'ownerFaction': ownerFaction?.name,
      'sellFactors': sellFactors,
      'buyFactors': buyFactors,
      'pricingOverride': pricingOverride,
    };
  }

  factory PortInfo.fromJson(Map<String, dynamic> json) {
    return PortInfo(
      name: json['name'] as String? ?? 'Unknown Port',
      portClass: PortClass.values.firstWhere(
        (e) => e.name == json['portClass'],
        orElse: () => PortClass.free,
      ),
      buyPrices: Map<String, double>.from(
        (json['buyPrices'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ) ??
            {},
      ),
      sellPrices: Map<String, double>.from(
        (json['sellPrices'] as Map?)?.map(
              (k, v) => MapEntry(k as String, (v as num).toDouble()),
            ) ??
            {},
      ),
      defenseLevel: json['defenseLevel'] as int? ?? 0,
      portCredits: (json['portCredits'] as num?)?.toDouble() ?? 0.0,
      desiredCredits: (json['desiredCredits'] as num?)?.toDouble() ?? 0.0,
      owner: json['owner'] as String?,
      ownerFaction: _parseFactionClass(json['ownerFaction'] as String?),
      sellFactors: (json['sellFactors'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
      buyFactors: (json['buyFactors'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
      pricingOverride: (json['pricingOverride'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toDouble()),
          ) ??
          {},
    );
  }

  static FactionClass? _parseFactionClass(String? name) {
    if (name == null) return null;
    for (final v in FactionClass.values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

class HazardInfo {
  final bool navHaz;
  final String? anomaly;

  const HazardInfo({this.navHaz = false, this.anomaly});

  Map<String, dynamic> toJson() {
    return {
      'navHaz': navHaz,
      'anomaly': anomaly,
    };
  }

  factory HazardInfo.fromJson(Map<String, dynamic> json) {
    return HazardInfo(
      navHaz: json['navHaz'] as bool? ?? false,
      anomaly: json['anomaly'] as String?,
    );
  }
}

/// One remembered attacker. Keyed by stable pilot id in
/// [NpcMemory.vendettas] — never by display name (names can collide across
/// seeded generators).
///
/// This is the memory layer only: it records what happened. Intent
/// (revenge / avoid / demand) derives from it in C2, and `NpcGoal`
/// changes still go through the interruption policy — a grudge never
/// overwrites a committed goal by itself.
class VendettaRecord {
  /// Sector where the target was last seen.
  final int sectorId;

  /// Epoch ms of the first recorded encounter.
  final int firstSeenMs;

  /// Epoch ms of the most recent encounter/sighting.
  final int lastSeenMs;

  /// 0–100. Bumped on hostile contact, decays with time (see
  /// [NpcMemory.vendettaMemory]).
  final int grievance;

  const VendettaRecord({
    required this.sectorId,
    required this.firstSeenMs,
    required this.lastSeenMs,
    this.grievance = 0,
  });

  VendettaRecord refreshed({
    required int sectorId,
    required int nowMs,
    int grievanceBump = 0,
  }) {
    return VendettaRecord(
      sectorId: sectorId,
      firstSeenMs: firstSeenMs,
      lastSeenMs: nowMs,
      grievance: (grievance + grievanceBump).clamp(0, 100),
    );
  }

  Map<String, dynamic> toJson() => {
        'sectorId': sectorId,
        'firstSeenMs': firstSeenMs,
        'lastSeenMs': lastSeenMs,
        'grievance': grievance,
      };

  factory VendettaRecord.fromJson(Map<String, dynamic> json) {
    return VendettaRecord(
      sectorId: (json['sectorId'] as num?)?.toInt() ?? 0,
      firstSeenMs: (json['firstSeenMs'] as num?)?.toInt() ?? 0,
      lastSeenMs: (json['lastSeenMs'] as num?)?.toInt() ?? 0,
      grievance: ((json['grievance'] as num?)?.toInt() ?? 0).clamp(0, 100),
    );
  }
}

class NpcMemory {
  final Set<int> visitedSectors;
  final Map<int, PortInfo> discoveredPorts;
  final Map<int, HazardInfo> knownHazards;
  final Set<String> knownThreatIds;
  final Map<String, int> factionStandings;
  final DateTime? lastTradeTime;
  final DateTime? lastBankTime;

  /// Failed trade routes ("buyId>sellId:commodity" → epoch ms). A route
  /// that just failed is skipped by route selection until the cooldown
  /// lapses, so NPCs don't spin on doomed routes built from stale prices.
  final Map<String, int> failedRoutes;

  /// Cooldown before a failed route becomes eligible again.
  static const Duration routeCooldown = Duration(minutes: 5);

  /// Encounter memory ("pilotId" → record). Grudges older than
  /// [vendettaMemory] (by last sighting) are dropped by [pruneVendettas].
  final Map<String, VendettaRecord> vendettas;

  /// How long a grudge survives without fresh contact.
  static const Duration vendettaMemory = Duration(hours: 6);

  /// Profitable trade routes ("buyId>sellId:commodity" → completed
  /// profitable runs, capped). Positive mirror of [failedRoutes]: routes
  /// that paid get a ranking boost in selection, so pilots learn what
  /// works instead of only what doesn't.
  final Map<String, int> profitableRoutes;

  /// Cap on remembered wins per route — recent success matters, ancient
  /// history shouldn't outshout fresh prices.
  static const int maxRouteWins = 10;

  /// Cap on remembered ports per pilot (review batch 3, P3).
  static const int maxDiscoveredPorts = 40;

  /// Cap on tracked route keys (review batch 3, P3): cooldowns prune by
  /// time, but a busy trader would still accumulate keys all session.
  static const int maxFailedRoutes = 50;
  static const int maxProfitableRoutes = 50;

  /// Hearsay grievance for gossiped sightings (C2d): knowing OF a killer
  /// is not the same as watching them kill. Below the hunt threshold, so
  /// gossip informs but never launches hunts by itself.
  static const int hearsayGrievance = 10;

  const NpcMemory({
    this.visitedSectors = const {},
    this.discoveredPorts = const {},
    this.knownHazards = const {},
    this.knownThreatIds = const {},
    this.factionStandings = const {},
    this.lastTradeTime,
    this.lastBankTime,
    this.failedRoutes = const {},
    this.vendettas = const {},
    this.profitableRoutes = const {},
  });

  factory NpcMemory.empty() => const NpcMemory();

  NpcMemory copyWith({
    Set<int>? visitedSectors,
    Map<int, PortInfo>? discoveredPorts,
    Map<int, HazardInfo>? knownHazards,
    Set<String>? knownThreatIds,
    Map<String, int>? factionStandings,
    DateTime? lastTradeTime,
    DateTime? lastBankTime,
    Map<String, int>? failedRoutes,
    Map<String, VendettaRecord>? vendettas,
    Map<String, int>? profitableRoutes,
  }) {
    return NpcMemory(
      visitedSectors: visitedSectors ?? this.visitedSectors,
      discoveredPorts: discoveredPorts ?? this.discoveredPorts,
      knownHazards: knownHazards ?? this.knownHazards,
      knownThreatIds: knownThreatIds ?? this.knownThreatIds,
      factionStandings: factionStandings ?? this.factionStandings,
      lastTradeTime: lastTradeTime ?? this.lastTradeTime,
      lastBankTime: lastBankTime ?? this.lastBankTime,
      failedRoutes: failedRoutes ?? this.failedRoutes,
      vendettas: vendettas ?? this.vendettas,
      profitableRoutes: profitableRoutes ?? this.profitableRoutes,
    );
  }

  NpcMemory withVisitedSector(int sectorId) {
    if (visitedSectors.contains(sectorId)) return this;
    final updated = Set<int>.from(visitedSectors);
    updated.add(sectorId);
    return copyWith(visitedSectors: updated);
  }

  NpcMemory withDiscoveredPort(int sectorId, PortInfo port) {
    // No-op when the snapshot is unchanged (review batch 3, P1): a
    // parked NPC otherwise copies its whole port book every turn.
    if (discoveredPorts[sectorId] == port) return this;
    final updated = Map<int, PortInfo>.from(discoveredPorts);
    updated[sectorId] = port;
    // Bound the book (review batch 3, P3): explorers in huge universes
    // would otherwise carry hundreds of ports into every save.
    // Insertion-ordered, so the first key is the stalest lead.
    while (updated.length > maxDiscoveredPorts) {
      updated.remove(updated.keys.first);
    }
    return copyWith(discoveredPorts: updated);
  }

  NpcMemory withKnownHazard(int sectorId, HazardInfo hazard) {
    final existing = knownHazards[sectorId];
    if (existing != null &&
        existing.navHaz == hazard.navHaz &&
        existing.anomaly == hazard.anomaly) {
      return this;
    }
    final updated = Map<int, HazardInfo>.from(knownHazards);
    updated[sectorId] = hazard;
    return copyWith(knownHazards: updated);
  }

  NpcMemory withThreat(String threatId) {
    if (knownThreatIds.contains(threatId)) return this;
    final updated = Set<String>.from(knownThreatIds);
    updated.add(threatId);
    return copyWith(knownThreatIds: updated);
  }

  /// Drops threat ids with no living holder in [aliveIds] (review batch
  /// 3, P1): `removeThreat` had no callers, so the set only grew.
  /// Returns `this` when nothing expired.
  NpcMemory pruneThreats(Set<String> aliveIds) {
    if (knownThreatIds.every(aliveIds.contains)) return this;
    final updated = Set<String>.from(knownThreatIds)
      ..retainWhere(aliveIds.contains);
    return copyWith(knownThreatIds: updated);
  }

  NpcMemory removeThreat(String threatId) {
    final updated = Set<String>.from(knownThreatIds);
    updated.remove(threatId);
    return copyWith(knownThreatIds: updated);
  }

  NpcMemory withFactionStanding(String faction, int standing) {
    final updated = Map<String, int>.from(factionStandings);
    updated[faction] = standing;
    return copyWith(factionStandings: updated);
  }

  /// Route key for cooldown tracking.
  static String routeKey(int? buyPortId, int? sellPortId, String? commodity) =>
      '$buyPortId>$sellPortId:$commodity';

  /// Records a failed route, starting its cooldown. Expired entries
  /// prune on write and the map caps at [maxFailedRoutes] (review batch
  /// 3, P3): `coolingRoutes` only filters on read, so without this the
  /// keys accumulate all session.
  NpcMemory withFailedRoute(String key, {int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final updated = Map<String, int>.from(failedRoutes);
    updated[key] = now;
    updated.removeWhere(
        (k, at) => k != key && now - at >= routeCooldown.inMilliseconds);
    while (updated.length > maxFailedRoutes) {
      final victim =
          updated.keys.firstWhere((k) => k != key, orElse: () => key);
      if (victim == key) break;
      updated.remove(victim);
    }
    return copyWith(failedRoutes: updated);
  }

  /// True when [key] failed within [routeCooldown] (stale entries are
  /// pruned on read).
  bool isRouteCooling(String key, {int? nowMs}) {
    final at = failedRoutes[key];
    if (at == null) return false;
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return now - at < routeCooldown.inMilliseconds;
  }

  /// Live (unexpired) failed-route keys for route selection to skip.
  Set<String> coolingRoutes({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    return {
      for (final entry in failedRoutes.entries)
        if (now - entry.value < routeCooldown.inMilliseconds) entry.key,
    };
  }

  /// Records a profitable run on [key] (see [routeKey]), capped at
  /// [maxRouteWins]. Returns `this` at the cap so callers can skip
  /// pointless saves.
  NpcMemory withProfitableRoute(String key) {
    final wins = profitableRoutes[key] ?? 0;
    if (wins >= maxRouteWins) return this;
    // Cap keys as well as wins (review batch 3, P3).
    if (!profitableRoutes.containsKey(key) &&
        profitableRoutes.length >= maxProfitableRoutes) {
      return this;
    }
    final updated = Map<String, int>.from(profitableRoutes);
    updated[key] = wins + 1;
    return copyWith(profitableRoutes: updated);
  }

  /// Merges gossiped sightings from a wingmate (C2d): sightings ONLY.
  /// Newer sectors win; each pilot keeps their own grievance, and unknown
  /// killers are adopted at [hearsayGrievance] — knowing OF a killer is
  /// not watching them kill. Returns the merged memory plus what changed
  /// (for log lines), or `this` untouched when there is nothing newer.
  ({NpcMemory memory, int adopted, int refreshed}) mergeSightings(
    Map<String, VendettaRecord> other, {
    int? nowMs,
  }) {
    if (other.isEmpty) return (memory: this, adopted: 0, refreshed: 0);
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    var updated = Map<String, VendettaRecord>.from(vendettas);
    var adopted = 0;
    var refreshed = 0;
    var changed = false;
    for (final entry in other.entries) {
      final mine = updated[entry.key];
      if (mine == null) {
        updated[entry.key] = VendettaRecord(
          sectorId: entry.value.sectorId,
          firstSeenMs:
              now < entry.value.lastSeenMs ? now : entry.value.lastSeenMs,
          lastSeenMs: entry.value.lastSeenMs,
          grievance: hearsayGrievance,
        );
        adopted++;
        changed = true;
      } else if (entry.value.lastSeenMs > mine.lastSeenMs) {
        updated[entry.key] = VendettaRecord(
          sectorId: entry.value.sectorId,
          firstSeenMs: mine.firstSeenMs,
          lastSeenMs: entry.value.lastSeenMs,
          grievance: mine.grievance,
        );
        refreshed++;
        changed = true;
      }
    }
    if (!changed) return (memory: this, adopted: 0, refreshed: 0);
    return (
      memory: copyWith(vendettas: updated),
      adopted: adopted,
      refreshed: refreshed
    );
  }

  /// Records hostile contact with [targetId] (stable pilot id): creates
  /// or refreshes the vendetta, bumping grievance. First sighting time is
  /// preserved across refreshes. Capped at [maxVendettas] entries (review
  /// batch 1): the 6h time prune never fires inside a soak session, so
  /// without a count cap the map only grows — beyond the cap the
  /// coldest grudge (lowest grievance, oldest sighting) is forgotten.
  static const int maxVendettas = 20;

  NpcMemory withVendetta({
    required String targetId,
    required int sectorId,
    int grievanceBump = 20,
    int? nowMs,
  }) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final updated = Map<String, VendettaRecord>.from(vendettas);
    final existing = updated[targetId];
    updated[targetId] = existing?.refreshed(
          sectorId: sectorId,
          nowMs: now,
          grievanceBump: grievanceBump,
        ) ??
        VendettaRecord(
          sectorId: sectorId,
          firstSeenMs: now,
          lastSeenMs: now,
          grievance: grievanceBump.clamp(0, 100),
        );
    // Count cap: forget the coldest grudge when a new one overflows.
    // Refreshes never evict — only genuine newcomers trigger this.
    if (existing == null && updated.length > maxVendettas) {
      String? coldest;
      for (final entry in updated.entries) {
        if (entry.key == targetId) continue;
        final c = coldest == null ? null : updated[coldest];
        if (c == null ||
            entry.value.grievance < c.grievance ||
            (entry.value.grievance == c.grievance &&
                entry.value.lastSeenMs < c.lastSeenMs)) {
          coldest = entry.key;
        }
      }
      updated.remove(coldest);
    }
    return copyWith(vendettas: updated);
  }

  /// Relocates a grudge's intel without touching grievance or the decay
  /// window (C3 dry-hole search spread): checking next door is searching,
  /// not sighting. Returns `this` when absent or unchanged.
  NpcMemory withVendettaRelocated(String targetId, int sectorId) {
    final existing = vendettas[targetId];
    if (existing == null || existing.sectorId == sectorId) return this;
    final updated = Map<String, VendettaRecord>.from(vendettas);
    updated[targetId] = VendettaRecord(
      sectorId: sectorId,
      firstSeenMs: existing.firstSeenMs,
      lastSeenMs: existing.lastSeenMs,
      grievance: existing.grievance,
    );
    return copyWith(vendettas: updated);
  }

  /// Drops grudges with no contact inside [vendettaMemory]. Returns `this`
  /// when nothing expired so callers can skip pointless saves.
  NpcMemory pruneVendettas({int? nowMs}) {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final cutoff = now - vendettaMemory.inMilliseconds;
    if (vendettas.values.every((v) => v.lastSeenMs >= cutoff)) {
      return this;
    }
    final updated = Map<String, VendettaRecord>.from(vendettas)
      ..removeWhere((_, v) => v.lastSeenMs < cutoff);
    return copyWith(vendettas: updated);
  }

  /// Vengeance satisfied (C2b): the target is dead / paid / parleyed.
  /// Returns `this` when the entry is absent.
  NpcMemory withVendettaResolved(String targetId) {
    if (!vendettas.containsKey(targetId)) return this;
    final updated = Map<String, VendettaRecord>.from(vendettas)
      ..remove(targetId);
    return copyWith(vendettas: updated);
  }

  /// Eases a grudge by [amount] (dry-hole arrivals, escapes, partial
  /// payments). Drops the entry when grievance reaches 0; returns `this`
  /// when absent so callers can skip pointless saves. Sightings are NOT
  /// refreshed — a fruitless revisit must not extend the memory window,
  /// or camping a sector would keep a grudge alive forever.
  NpcMemory withVendettaEased(String targetId, int amount) {
    final existing = vendettas[targetId];
    if (existing == null) return this;
    final updated = Map<String, VendettaRecord>.from(vendettas);
    final eased = existing.grievance - amount;
    if (eased <= 0) {
      updated.remove(targetId);
    } else {
      updated[targetId] = VendettaRecord(
        sectorId: existing.sectorId,
        firstSeenMs: existing.firstSeenMs,
        lastSeenMs: existing.lastSeenMs,
        grievance: eased,
      );
    }
    return copyWith(vendettas: updated);
  }

  Map<String, dynamic> toJson() {
    return {
      'visitedSectors': visitedSectors.toList(),
      'discoveredPorts': discoveredPorts.map(
        (k, v) => MapEntry(k.toString(), v.toJson()),
      ),
      'knownHazards': knownHazards.map(
        (k, v) => MapEntry(k.toString(), v.toJson()),
      ),
      'knownThreatIds': knownThreatIds.toList(),
      'factionStandings': factionStandings,
      'lastTradeTime': lastTradeTime?.toIso8601String(),
      'lastBankTime': lastBankTime?.toIso8601String(),
      'failedRoutes': failedRoutes.map((k, v) => MapEntry(k, v)),
      'vendettas': vendettas.map((k, v) => MapEntry(k, v.toJson())),
      'profitableRoutes': profitableRoutes.map((k, v) => MapEntry(k, v)),
    };
  }

  factory NpcMemory.fromJson(Map<String, dynamic> json) {
    return NpcMemory(
      visitedSectors: (json['visitedSectors'] as List?)
              ?.map((e) => (e as num).toInt())
              .toSet() ??
          const {},
      discoveredPorts: (json['discoveredPorts'] as Map?)?.map(
            (k, v) => MapEntry(
              int.parse(k as String),
              PortInfo.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          const {},
      knownHazards: (json['knownHazards'] as Map?)?.map(
            (k, v) => MapEntry(
              int.parse(k as String),
              HazardInfo.fromJson(v as Map<String, dynamic>),
            ),
          ) ??
          const {},
      knownThreatIds:
          (json['knownThreatIds'] as List?)?.map((e) => e as String).toSet() ??
              const {},
      factionStandings: (json['factionStandings'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, (v as num).toInt())) ??
          const {},
      lastTradeTime: json['lastTradeTime'] != null
          ? DateTime.parse(json['lastTradeTime'] as String)
          : null,
      lastBankTime: json['lastBankTime'] != null
          ? DateTime.parse(json['lastBankTime'] as String)
          : null,
      failedRoutes: (json['failedRoutes'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const {},
      vendettas: (json['vendettas'] as Map?)?.map(
            (k, v) => MapEntry(
              k as String,
              VendettaRecord.fromJson((v as Map).cast<String, dynamic>()),
            ),
          ) ??
          const {},
      profitableRoutes: (json['profitableRoutes'] as Map?)?.map(
            (k, v) => MapEntry(k as String, (v as num).toInt()),
          ) ??
          const {},
    );
  }
}
