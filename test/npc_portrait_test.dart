import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/avatar_selection.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/widgets/avatar/avatar_catalog.dart';
import 'package:cosmic_trader/widgets/avatar/npc_portrait.dart';

/// A portrait with a controlled id, via the primitive `NpcPortraits.of` is
/// built on. `NpcShip.create` mints a random UUID, so a test that needs a
/// *specific* id has to go through `forId`.
AvatarPortrait _p(
  String id, {
  FactionClass faction = FactionClass.duran,
  String pilotName = 'Tester',
}) =>
    NpcPortraits.forId(id, faction, pilotName);

/// A real NPC, for the one test that must go through the model.
NpcShip _npc(FactionClass faction) => NpcShip.create(
      faction: faction,
      shipDef: ShipDefinition.allShips.first,
      currentSectorId: 5,
      startingCredits: 5000,
      seed: 1234,
    );

void main() {
  group('NpcPortraits', () {
    test('is a pure function of the NPC id', () {
      // The whole design rests on this: nothing is stored, so the same NPC must
      // derive the same face every time it is drawn, in any session.
      final first = _p('stable-id-42');
      for (var i = 0; i < 25; i++) {
        expect(_p('stable-id-42').id, first.id);
        expect(_p('stable-id-42').presentation, first.presentation);
        expect(_p('stable-id-42').drawSeed, first.drawSeed);
      }
      // And through the real model, not just the primitive.
      final npc = _npc(FactionClass.duran);
      expect(NpcPortraits.of(npc).id, NpcPortraits.of(npc).id);
      expect(
          NpcPortraits.of(npc).presentation, NpcPortraits.of(npc).presentation);
    });

    test('pirates are drawn from all three species, not handed a human face',
        () {
      // Pirates are an affiliation, not a race — see [AvatarAffiliation]. Before
      // this, [AvatarSpecies.forFaction] mapped them to Terran, so roughly one
      // NPC in seven shared the human pool and a pirate could draw the same face
      // as a Trader. The ring was the only thing telling them apart.
      final ids = List.generate(240, (i) => 'pirate-sweep-$i');
      final species =
          ids.map((id) => _p(id, faction: FactionClass.pirate).species).toSet();

      expect(species, AvatarSpecies.values.toSet(),
          reason: 'every species should turn up among pirates — they are a '
              'mixture of defectors, not a fourth race');
    });

    test('a non-pirate keeps exactly their own faction species', () {
      for (final faction in FactionClass.values.where((f) => f.isSelectable)) {
        for (var i = 0; i < 12; i++) {
          expect(_p('n-$faction-$i', faction: faction).species,
              AvatarSpecies.forFaction(faction));
        }
      }
    });

    test('only pirates carry the pirate affiliation', () {
      for (var i = 0; i < 20; i++) {
        expect(_p('aff-$i', faction: FactionClass.pirate).affiliation,
            AvatarAffiliation.pirate);
        for (final faction
            in FactionClass.values.where((f) => f.isSelectable)) {
          expect(_p('aff-$faction-$i', faction: faction).affiliation,
              AvatarAffiliation.native);
        }
      }
    });

    test('a pirate ring is pirate-orange whatever species they are', () {
      // The defect this catches: deriving the accent from `species.faction`, so a
      // pirate Duran wears Hegemony red and reads as a loyalist at a glance.
      for (var i = 0; i < 90; i++) {
        final p = _p('accent-$i', faction: FactionClass.pirate);
        expect(p.accentFaction, FactionClass.pirate,
            reason: 'a ${p.species.label} pirate should be identified by the '
                'pirate colour, not the faction they left');
      }
      // And a native still gets their own species' colour.
      for (final faction in FactionClass.values.where((f) => f.isSelectable)) {
        expect(_p('accent-n-$faction', faction: faction).accentFaction,
            AvatarSpecies.forFaction(faction).faction);
      }
    });

    test('pirate species and presentation are not correlated', () {
      // Both are drawn from the NPC id, so sharing a salt would lock every
      // pirate of a species to one presentation — a pattern that shows up the
      // moment two land in the same sector.
      final pairs = <String>{};
      for (var i = 0; i < 300; i++) {
        final p = _p('corr-$i', faction: FactionClass.pirate);
        pairs.add('${p.species.name}/${p.presentation.name}');
      }
      // A single shared salt would produce at most 3 pairs (one per species).
      expect(pairs.length, greaterThan(3),
          reason:
              'species and presentation look correlated: only ${pairs.length} '
              'pair(s) across 300 pirates');
    });

    test('a different NPC gets a different portrait', () {
      // If this ever collapsed, a whole sector would show the same face.
      final a = _p('a');
      final b = _p('b');
      expect(a.id, isNot(b.id));
      expect(a.drawSeed, isNot(b.drawSeed));
    });

    test('species follows the faction for everyone a player can join', () {
      expect(
        _p('x', faction: FactionClass.duran).species,
        AvatarSpecies.duran,
      );
      expect(
        _p('x', faction: FactionClass.vinari).species,
        AvatarSpecies.vinari,
      );
      expect(
        _p('x', faction: FactionClass.trader).species,
        AvatarSpecies.terran,
      );
      // Pirates used to be pinned here to the human pool, with the comment that
      // the ring was the only thing telling a pirate from a trader. That is the
      // defect [AvatarAffiliation] removed: they are now drawn from all three
      // species, asserted in the sweep test above. This test keeps the *native*
      // mapping, which is the half that must not move.
    });

    test('a derived id can never collide with a real catalogue entry', () {
      // The `npc_` prefix is what guarantees this, so it is asserted rather than
      // assumed — a collision would make AvatarCatalog.byId resolve an NPC to a
      // player's portrait.
      for (final entry in AvatarCatalog.portraits) {
        expect(entry.id, isNot(startsWith('npc_')));
        expect(AvatarCatalog.byId(NpcPortraits.idFor(entry.id)), isNull,
            reason: '${entry.id} must not resolve as an NPC portrait');
      }
      for (final id in ['a', 'b', 'c', 'npc-1', '']) {
        expect(AvatarCatalog.byId(NpcPortraits.idFor(id)), isNull);
      }
    });

    test('the label is the pilot name, not a catalogue callsign', () {
      // A portrait announced as "Veth Kaal" when the pilot is someone else
      // would be a straight accessibility bug.
      final portrait = _p('x', pilotName: 'Keth Vaan');
      expect(portrait.label, 'Keth Vaan');
      final callsigns = AvatarCatalog.portraits.map((p) => p.label).toSet();
      expect(portrait.label, isNot(startsWith('npc')));
      // Sanity: the name really is a plausible collision with a callsign, which
      // is why label must come from the NPC rather than the catalogue.
      expect(callsigns, contains('Keth Vaan'));
    });

    test('presentation is spread across all three values over a roster', () {
      // A derivation that always returned one presentation would make every NPC
      // look identically gendered, which is worse than picking at random.
      final seen = <AvatarPresentation>{};
      for (var i = 0; i < 300; i++) {
        seen.add(_p('npc-$i').presentation);
      }
      expect(seen, AvatarPresentation.values.toSet(),
          reason: 'all three presentations should be reachable');
    });

    test('a large roster produces no repeated faces', () {
      // The reason NPCs are not drawn from the 27-entry catalogue. At NPC scale
      // the catalogue would repeat constantly.
      final seeds = <int>{};
      final styles = <String>{};
      for (var i = 0; i < 200; i++) {
        final portrait = _p('npc-$i');
        seeds.add(portrait.drawSeed);
        styles.add(portrait.seededStyle.toString());
      }
      // Seed collisions are astronomically unlikely at 32 bits over 200 draws;
      // allow a hair of slack rather than asserting perfection.
      expect(seeds.length, greaterThan(195),
          reason: 'draw seeds should be near-unique across a roster');
      expect(styles.length, greaterThan(150),
          reason: 'seeded appearances should vary across a roster');
    });

    test('deriving never throws, whatever the id looks like', () {
      // It is called from build methods against persisted ids, so an odd value
      // must not be able to take a screen down.
      for (final id in ['', ' ', 'npc_', 'üñïçø∂é', '0' * 512, r'$pecial']) {
        final portrait = _p(id);
        expect(portrait.drawSeed, inInclusiveRange(0, 0xFFFFFFFF));
        expect(AvatarPresentation.values, contains(portrait.presentation));
      }
    });

    test('a destroyed or respawned NPC is a different person, and says so', () {
      // Repopulation mints a fresh id, so a respawned pilot gets a new face.
      // That is intended — `NpcShip.create` also regenerates the name and ship —
      // but it is worth pinning so nobody "fixes" it by deriving from the name.
      final before = _p('pilot-1', pilotName: 'Keth');
      final after = _p('pilot-2', pilotName: 'Keth');
      expect(after.drawSeed, isNot(before.drawSeed));
    });
  });
}
