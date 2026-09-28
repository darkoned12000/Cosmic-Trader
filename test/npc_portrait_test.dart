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

    test('a different NPC gets a different portrait', () {
      // If this ever collapsed, a whole sector would show the same face.
      final a = _p('a');
      final b = _p('b');
      expect(a.id, isNot(b.id));
      expect(a.drawSeed, isNot(b.drawSeed));
    });

    test('species follows the faction, including the pirate fallback', () {
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
      // Pirates have no species yet and fall back to the human pool. Pinned so
      // that adding one is a deliberate change rather than a silent drift — the
      // bounty ring is currently the only thing telling a pirate from a trader.
      expect(
        _p('x', faction: FactionClass.pirate).species,
        AvatarSpecies.terran,
      );
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
