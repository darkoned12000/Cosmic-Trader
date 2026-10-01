import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/services/npc_ai/npc_ai_service.dart';

/// Killing a peaceful pilot costs twice what killing a raider does.
///
/// The distinction is not cosmetic. `killPatrol` used to be charged for *every*
/// NPC death, so opening fire on a passing hauler cost exactly as much as
/// shooting back at a pirate \u2014 which is to say it cost the same either way, and
/// being the aggressor was free. The player is now charged for the difference.
///
/// The guard's real subject is *whose* rule decides. The screen must read the
/// hostility the **AI acts on** (`NpcAiService.areFactionsHostile`), not its own
/// guess from the personality enum or the port list: if the two ever disagreed,
/// a player could be billed for defending themselves or let off for murder.
void main() {
  group('the peace-time killing is the expensive one', () {
    test('a pirate is a legitimate kill', () {
      // Pirates are hostile to everyone, so a trader shooting a pirate is doing
      // the obvious thing.
      expect(
        NpcAiService.areFactionsHostile(
            FactionClass.pirate, FactionClass.trader),
        isTrue,
      );
      expect(ReputationActions.killPatrol, -32.0);
    });

    test('a same-faction trader is a peaceful pilot', () {
      expect(
        NpcAiService.areFactionsHostile(
            FactionClass.trader, FactionClass.trader),
        isFalse,
      );
    });

    test('the two costs differ, and the peaceful one is the dearer', () {
      // Pinned because both are named in the deed table and a retune that
      // collapsed them would quietly remove the whole mechanic.
      expect(ReputationActions.killUnprovoked, -64.0);
      expect(ReputationActions.killUnprovoked,
          lessThan(ReputationActions.killPatrol),
          reason: 'murder must cost more than shooting back');
      expect(
          ReputationActions.killUnprovoked, 2 * ReputationActions.killPatrol);
    });
  });

  group('the chooser reads the galaxy\u2019s rule, not a second one', () {
    // Every ordered faction pair, both directions. One-sided checking would pass
    // on a symmetric-broken rule, and the AI reads this for real combat
    // decisions \u2014 so the symmetry is load-bearing, not cosmetic.
    test('for all twelve ordered pairs', () {
      final pairs = <(FactionClass, FactionClass)>[
        (FactionClass.duran, FactionClass.vinari),
        (FactionClass.vinari, FactionClass.duran),
        (FactionClass.pirate, FactionClass.duran),
        (FactionClass.duran, FactionClass.pirate),
        (FactionClass.trader, FactionClass.trader),
        (FactionClass.trader, FactionClass.duran),
        (FactionClass.vinari, FactionClass.vinari),
        (FactionClass.duran, FactionClass.duran),
        (FactionClass.pirate, FactionClass.pirate),
        (FactionClass.pirate, FactionClass.trader),
        (FactionClass.trader, FactionClass.pirate),
        (FactionClass.trader, FactionClass.vinari),
      ];
      for (final (a, b) in pairs) {
        // The AI's entry point and the shared rule must be the same answer.
        expect(NpcAiService.areFactionsHostile(a, b),
            FactionHostility.areHostile(a, b),
            reason: '$a vs $b');
        // And the rule is symmetric, which the AI relies on.
        expect(NpcAiService.areFactionsHostile(b, a),
            NpcAiService.areFactionsHostile(a, b),
            reason: '$a vs $b is not symmetric');
      }
    });

    test('and the price follows that rule, not the NPC\u2019s personality', () {
      // A raider personality on a trader faction is still a peaceful pilot: the
      // galaxy does not care what it calls itself, it cares who it flies for.
      for (final hostile in [FactionClass.pirate, FactionClass.duran]) {
        expect(
          ReputationActions.forKilling(
              victimFaction: hostile, killerFaction: FactionClass.vinari),
          ReputationActions.killPatrol,
          reason: '$hostile is at war with the Vinari',
        );
      }
      for (final peaceful in [FactionClass.trader, FactionClass.vinari]) {
        expect(
          ReputationActions.forKilling(
              victimFaction: peaceful, killerFaction: FactionClass.trader),
          ReputationActions.killUnprovoked,
          reason: '$peaceful is not at war with the Guild',
        );
      }
      // Same faction: nobody is shooting at anybody.
      expect(
        ReputationActions.forKilling(
            victimFaction: FactionClass.trader,
            killerFaction: FactionClass.trader),
        ReputationActions.killUnprovoked,
      );
    });
  });
}
