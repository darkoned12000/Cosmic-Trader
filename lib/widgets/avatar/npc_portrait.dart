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
/// ## Pirates are an affiliation, not a species
///
/// A pirate is somebody who left their own faction, so their *body* is an
/// ordinary Duran, Vinari, or Terran — [_speciesFor] draws a pirate from all
/// three, evenly, instead of falling through
/// [AvatarSpecies.forFaction] and handing every pirate a human face. The
/// affiliation then supplies the pirate palette, the darker cloth, and a
/// higher chance of markings; see [AvatarAffiliation].
///
/// The split is drawn from the same id as everything else, so a pirate keeps
/// their species for the life of the NPC and re-derives identically everywhere.
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
    final species = _speciesFor(id, faction);
    return AvatarPortrait(
      id: id,
      species: species,
      presentation: _presentationFor(id),
      // The pilot's own name, so the spoken label is the pilot's name rather
      // than a catalogue callsign that belongs to somebody else. Falls back to the
      // species label rather than going empty, because an empty semantics label
      // makes the portrait invisible to a screen reader rather than merely
      // unlabelled.
      label: pilotName.isEmpty ? 'Unidentified ${species.label}' : pilotName,
      affiliation: faction == FactionClass.pirate
          ? AvatarAffiliation.pirate
          : AvatarAffiliation.native,
    );
  }

  /// The species a pirate can be, **pinned as an explicit list**.
  ///
  /// Not `AvatarSpecies.values`. A peer review pointed out that using `values`
  /// makes every existing pirate's species depend on the *size* of the enum, so
  /// adding a fourth species would reshuffle the whole pirate roster in one
  /// release — new faces for NPCs nobody touched, with no diff to point at. An
  /// explicit list makes that an edit here instead, and a new species is a
  /// deliberate decision to add.
  static const List<AvatarSpecies> _pirateSpecies = [
    AvatarSpecies.duran,
    AvatarSpecies.vinari,
    AvatarSpecies.terran,
  ];

  /// Salt for [AvatarSpecies] draws. Distinct from [_presentationSalt] and from
  /// [AvatarCatalog]'s own salt on purpose: sharing one would correlate species
  /// with presentation — every pirate Terran male, say — which reads as a pattern
  /// the moment two land in the same sector.
  static const int _speciesSalt = 0x6A09E667;

  /// Salt for [AvatarPresentation] draws. See [_speciesSalt] for why they differ.
  static const int _presentationSalt = 0x2545F491;

  /// Species for a non-pirate is exactly its faction's. A pirate is drawn from all
  /// three, evenly, and from their own id rather than from the faction they left —
  /// so a pirate keeps the same body for life even if their faction is reassigned.
  ///
  /// Park–Miller draw, matching the catalogue's method for the same reason: no
  /// global RNG state, and `seed * 16807` stays inside 2^53 so web and native agree.
  static AvatarSpecies _speciesFor(String id, FactionClass faction) {
    if (faction != FactionClass.pirate) {
      return AvatarSpecies.forFaction(faction);
    }
    return _pirateSpecies[_draw(id, _speciesSalt, _pirateSpecies.length)];
  }

  /// One Lehmer draw from a salted hash, reduced to [buckets].
  ///
  /// A peer review noted the species and presentation helpers were copy-pasted
  /// verbatim; they are one function now.
  static int _draw(String id, int salt, int buckets) {
    var seed = (AvatarCatalog.stableSeedFor(id) ^ salt) % 0x7FFFFFFF;
    if (seed <= 0) seed += 0x7FFFFFFE;
    seed = (seed * 16807) % 0x7FFFFFFF;
    return seed % buckets;
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
  static AvatarPresentation _presentationFor(String id) => AvatarPresentation
      .values[_draw(id, _presentationSalt, AvatarPresentation.values.length)];
}
