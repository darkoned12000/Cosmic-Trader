import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';

/// Resolves the pilot portrait for an NPC.
///
/// **Flutter-free by design**, like [AvatarCatalog], so this can be called from
/// the data layer and tested without a widget binding.
///
/// ## Nothing is stored
///
/// An NPC's face is *derived*, not persisted. There is no portrait field on
/// [NpcShip] and no change to `npcs.json`, which means:
///
/// - **Zero migration.** Every existing save has faces on first render.
/// - **Unlimited variety.** NPCs are not limited to the 27 catalogue entries;
///   each gets its own seed, so a roster of hundreds shows no repeats. Drawing
///   from the catalogue instead would repeat constantly at NPC scale.
/// - **Free regeneration.** Regenerating the universe mints new ids, so every
///   face is new with no bookkeeping to unwind.
///
/// The seed is the NPC's `id` — a UUID minted by `NpcShip.create` and already
/// persisted — so a face is stable across reloads and re-derives identically on
/// every platform. It is deliberately *not* derived from the pilot name (which
/// can collide) or the sector (which changes as the ship moves).
///
/// ## Pirates have no species yet
///
/// [AvatarSpecies.forFaction] maps `pirate` to `AvatarSpecies.terran`, so
/// roughly one NPC in seven is drawn from the human pool, and a pirate and a
/// Trader can land on the same face — the faction ring is the only thing
/// distinguishing them. A dedicated pirate species (scarred Terran/Duran) is a
/// deliberate follow-on. When one is added, this is the only place that needs to
/// know: it would map a pirate NPC to it and nothing else would change.
abstract final class NpcPortraits {
  /// The synthetic catalogue id an NPC's portrait is derived from.
  ///
  /// Prefixed so it can never collide with a real catalogue entry, which keeps
  /// [AvatarCatalog.byId] from resolving one by accident.
  static String idFor(String npcId) => 'npc_$npcId';

  /// The portrait to draw. Never null and never throws.
  static AvatarPortrait of(NpcShip npc) =>
      forId(npc.id, npc.faction, npc.pilotName);

  /// The primitive [of] is built on, taking the three inputs directly.
  ///
  /// Separate because `NpcShip.create` mints a random UUID, so a caller — or a
  /// test — that needs a *specific* id cannot get one through the model.
  static AvatarPortrait forId(
    String npcId,
    FactionClass faction,
    String pilotName,
  ) {
    final id = idFor(npcId);
    return AvatarPortrait(
      id: id,
      species: AvatarSpecies.forFaction(faction),
      presentation: _presentationFor(id),
      // The pilot's own name, so the spoken label is the pilot's name rather
      // than a catalogue callsign that belongs to somebody else.
      label: pilotName,
    );
  }

  /// Presentation drawn from the id.
  ///
  /// NPC models carry no gender, so this is simply the next plausible-looking
  /// split. Uses a different XOR salt from
  /// [AvatarCatalog.seededStyleFor] so presentation is not correlated with the
  /// first axis the style draws — otherwise every NPC would land on one
  /// presentation/style pairing.
  ///
  /// Park–Miller draw, matching the catalogue's method for the same reason: no
  /// global RNG state, and `seed * 16807` stays inside 2^53 so web and native
  /// agree.
  static AvatarPresentation _presentationFor(String id) {
    var seed = (AvatarCatalog.stableSeedFor(id) ^ 0x2545F491) % 0x7FFFFFFF;
    if (seed <= 0) seed += 0x7FFFFFFE;
    seed = (seed * 16807) % 0x7FFFFFFF;
    return AvatarPresentation.values[seed % AvatarPresentation.values.length];
  }
}
