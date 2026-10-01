import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/npc_ai/npc_chatter.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

// P5 aliveness: hailing an NPC used to return the same datasheet every time.
// The guard that matters is not "a line appeared" — it is that **the line
// cannot contradict the simulation**. A pilot who calls you a friend must be
// one the tick would not open fire on, and a pilot who refuses you must be at
// or below the standing threshold the ports use to slam the door. A greeting
// that disagrees with the AI is worse than no greeting, because it teaches the
// player to trust a number that is fiction.

NpcShip _npc(FactionClass faction, NpcPersonality personality, {int seed = 5}) {
  return NpcShip.create(
    faction: faction,
    shipDef: ShipDefinition.allShips.first,
    currentSectorId: 1,
    startingCredits: 1000,
    seed: seed,
  ).copyWith(personality: personality);
}

Player _player(FactionClass faction, {Map<String, int>? standings}) {
  return Player(
    name: 'Cap',
    currentSectorId: 1,
    hull: 100,
    maxHull: 100,
    shields: 50,
    maxShields: 50,
    cargoUsed: 0,
    maxCargo: 20,
    cargoSize: 20,
    credits: 1000,
    researchPoints: 0,
    faction: faction,
    factionStandings: standings ?? const {},
  );
}

void main() {
  group('the line matches the disposition it was chosen for', () {
    // **The mapping was untested.** Every guard above asserts the *disposition*
    // is computed correctly; none asserted that `greeting()` draws from the
    // matching corpus. Swapping the hostile and friendly pools produced **zero**
    // failures across the whole suite — a pirate would have greeted you warmly
    // and everything stayed green. Asserting the register rather than "a line
    // appeared" is the whole reason `greeting` takes an `rng`.
    for (final faction in FactionClass.values) {
      test('a ${faction.name} hail draws from the pool for its disposition',
          () {
        final npc = _npc(faction, NpcPersonality.traderMerchant);
        for (final disposition in HailDisposition.values) {
          final pool = NpcChatter.poolFor(disposition, faction);
          expect(pool, isNotEmpty,
              reason: '${faction.name}/${disposition.name} has no corpus');

          // Every line the generator can produce for this disposition must be
          // a member of that disposition's corpus. Sweeping the seed covers the
          // whole pool, so a single lucky match cannot pass it.
          for (var seed = 0; seed < pool.length * 3; seed++) {
            final line =
                NpcChatter.greeting(npc, disposition, rng: math.Random(seed));
            expect(pool.any(line.startsWith), isTrue,
                reason: '${disposition.name} produced a line from another '
                    'register: "$line"');
          }
        }
      });
    }

    test('each register holds the lines it is supposed to', () {
      // **Pinned content, because a pool swap is invisible to a structural
      // check.** The membership assertion above reads `poolFor`, which is the
      // same switch `greeting` uses — so swapping hostile and friendly moves
      // *both sides* together and still passes. Measured: the swap produced 0
      // failures both before and after that test was added.
      //
      // A swap is a *semantic* error — which words belong to which disposition —
      // and the only thing that can catch it is an absolute claim about the
      // words. That is prose-shaped, but here the prose **is** the artifact, the
      // same way the Planet Guide's numbers are. One representative line per
      // register is enough to make a swap fail loudly, and it is deliberately
      // not a full transcription of the corpus (which would be a second copy to
      // maintain).
      expect(
        NpcChatter.poolFor(HailDisposition.hostile, FactionClass.pirate),
        contains('That is my rock. Turn around and keep walking.'),
        reason: 'a pirate threatening you must not greet you with the friendly '
            'corpus — see the swap that nothing caught',
      );
      expect(
        NpcChatter.poolFor(HailDisposition.friendly, FactionClass.pirate),
        contains('Well, well. My favourite sort of fool.'),
        reason: 'and the friendly corpus must be the one that likes you',
      );
      // And the two must not be the same list.
      expect(
        NpcChatter.poolFor(HailDisposition.hostile, FactionClass.pirate),
        isNot(equals(
            NpcChatter.poolFor(HailDisposition.friendly, FactionClass.pirate))),
      );
    });

    test('the four registers are actually distinct corpora', () {
      // Guards the other direction: if two dispositions shared one pool, the
      // membership assertion above would still pass and the player would be
      // told a hostile pilot is friendly.
      final npc = _npc(FactionClass.trader, NpcPersonality.traderMerchant);
      final samples = <HailDisposition, String>{
        for (final d in HailDisposition.values)
          d: NpcChatter.greeting(npc, d, rng: math.Random(0)),
      };
      expect(samples.values.toSet().length, HailDisposition.values.length,
          reason: 'two dispositions opened with the same line: $samples');
    });
  });

  group('disposition cannot contradict the hostility rule', () {
    test('pirates are never above wary, however much they like you', () {
      // A pirate is hostile to every faction. Positive standing must not buy
      // a friendly greeting from one, or the player is told a pirate is a
      // friend by a pilot whose next move is to open fire.
      expect(
        NpcChatter.dispositionFor(
            _npc(FactionClass.pirate, NpcPersonality.pirateHunter),
            _player(FactionClass.trader, standings: const {'pirate': 100})),
        HailDisposition.wary,
      );
    });

    test('Duran and Vinari are hostile regardless of standing', () {
      expect(
        NpcChatter.dispositionFor(
            _npc(FactionClass.duran, NpcPersonality.duranWarlord),
            _player(FactionClass.vinari, standings: const {'duran': 100})),
        HailDisposition.wary,
      );
    });

    test('at or below the refusal threshold everyone is hostile', () {
      for (final standing in [-50, -75, -100]) {
        expect(NpcChatter.dispositionForStandingOnly(standing),
            HailDisposition.hostile,
            reason: 'standing $standing is the refusal band');
        // Even a same-faction pilot stops being polite at that point.
        expect(
          NpcChatter.dispositionFor(
              _npc(FactionClass.trader, NpcPersonality.traderMerchant),
              _player(FactionClass.trader, standings: {'trader': standing})),
          HailDisposition.hostile,
        );
      }
    });

    test('standing bands map to the expected registers', () {
      expect(NpcChatter.dispositionForStandingOnly(0), HailDisposition.neutral);
      expect(
          NpcChatter.dispositionForStandingOnly(10), HailDisposition.neutral);
      expect(
          NpcChatter.dispositionForStandingOnly(50), HailDisposition.friendly);
      expect(NpcChatter.dispositionForStandingOnly(-10), HailDisposition.wary);
      expect(NpcChatter.dispositionForStandingOnly(-49), HailDisposition.wary);
    });

    test('a friendly faction with good standing is friendly', () {
      expect(
        NpcChatter.dispositionFor(
            _npc(FactionClass.trader, NpcPersonality.traderMerchant),
            _player(FactionClass.trader, standings: const {'trader': 80})),
        HailDisposition.friendly,
      );
    });
  });

  group('every pilot has something to say', () {
    test('all 12 archetypes produce a non-empty line in every register', () {
      for (final personality in NpcPersonality.values) {
        for (final disposition in HailDisposition.values) {
          for (final faction in FactionClass.values) {
            final npc = _npc(faction, personality);
            final line =
                NpcChatter.greeting(npc, disposition, rng: math.Random(3));
            expect(line.trim(), isNotEmpty,
                reason: '$personality/$faction/$disposition said nothing');
            expect(line, isNot(contains('null')),
                reason:
                    '$personality/$faction/$disposition interpolated a null');
            expect(line, isNot(contains('undefined')),
                reason: '$personality/$faction/$disposition has a hole');
          }
        }
      }
    });
  });

  group('factions speak differently', () {
    test('a line is faction-flavoured, not shared boilerplate', () {
      // Every faction must own its own lines in every register, or the corpus
      // collapses to one voice. Compares the *pools* by drawing every line
      // from each faction and requiring the union to differ.
      Set<String> corpusFor(FactionClass faction) {
        final npc = _npc(faction, NpcPersonality.traderMerchant);
        final out = <String>{};
        for (final d in HailDisposition.values) {
          for (var i = 0; i < 40; i++) {
            out.add(NpcChatter.greeting(npc, d, rng: math.Random(i)));
          }
        }
        return out;
      }

      final duran = corpusFor(FactionClass.duran);
      final vinari = corpusFor(FactionClass.vinari);
      final trader = corpusFor(FactionClass.trader);
      final pirate = corpusFor(FactionClass.pirate);

      // Every faction must own its own lines in every register, or the corpus
      // collapses to one voice. Suffix flavour can coincide, so the bound is
      // small but strict: a recognisable faction is close to disjoint.
      for (final other in [vinari, trader, pirate]) {
        expect(duran.intersection(other).length, lessThan(3),
            reason: 'Duran and another faction share too many lines');
      }
      expect(trader.intersection(pirate).length, lessThan(3));
      expect(vinari.intersection(duran).length, lessThan(3));

      // And each faction must be drawing from a pool of its own rather than
      // falling through to the shared three-line default.
      for (final corpus in [duran, vinari, trader, pirate]) {
        expect(corpus.length, greaterThan(4),
            reason: 'a faction with no distinct lines is using the default');
      }
    });

    test('a hostile greeting is never the same sentence as a friendly one', () {
      // The register has to be visible in the text, not just in a label.
      final npc = _npc(FactionClass.trader, NpcPersonality.traderMerchant);
      final hostile = {
        for (var i = 0; i < 60; i++)
          NpcChatter.greeting(npc, HailDisposition.hostile, rng: math.Random(i))
      };
      final friendly = {
        for (var i = 0; i < 60; i++)
          NpcChatter.greeting(npc, HailDisposition.friendly,
              rng: math.Random(i))
      };
      // Suffix flavour can overlap, so allow a little intersection, but the
      // base sentences must not be the same pool.
      expect(hostile.intersection(friendly).length, lessThan(5));
    });
  });

  group('the register is derived from the model, not rolled', () {
    // `_flavourFor` consults caution FIRST, so an archetype that clears the
    // 0.6 caution gate always draws a flavour line, while one below the gate
    // with no other strong trait never does. That is a falsifiable difference
    // in the OUTPUT — an earlier version of this test compared a set's size
    // to itself, so it could not have failed for any input.
    const cautiousFlavour = [
      'Margins are thin',
      'I can do a rate',
      'Nobody ships for free',
    ];

    List<String> linesFor(NpcPersonality personality) => [
          for (var i = 0; i < 80; i++)
            NpcChatter.greeting(
                _npc(FactionClass.trader, personality), HailDisposition.neutral,
                rng: math.Random(i)),
        ];

    test('caution 0.7 clears the gate and colours the line', () {
      final merchant = _npc(FactionClass.trader, NpcPersonality.traderMerchant);
      expect(merchant.personalityConfig.caution, greaterThan(0.6),
          reason: 'the fixture must actually clear the gate under test');

      final lines = linesFor(NpcPersonality.traderMerchant);
      final coloured = lines.where((l) => cautiousFlavour.any(l.contains));
      // Appended on a 55% roll, so a sample of 80 must catch plenty — and
      // must catch some, or the gate is not being read at all.
      expect(coloured, isNotEmpty,
          reason: 'a cautious merchant never added a caution line');
      expect(coloured.length, greaterThan(lines.length ~/ 4),
          reason: 'the caution gate is not driving the flavour');
    });

    test('caution 0.5 with no other strong trait is never coloured', () {
      final explorer = _npc(FactionClass.trader, NpcPersonality.traderExplorer);
      final config = explorer.personalityConfig;
      expect(config.caution, lessThan(0.6));
      expect(config.greed, lessThan(0.7));
      expect(config.aggression, lessThan(0.7),
          reason: 'the fixture must be bland in every dimension, or this '
              'measures the wrong trait');

      for (final line in linesFor(NpcPersonality.traderExplorer)) {
        expect(cautiousFlavour.any(line.contains), isFalse,
            reason: 'a bland explorer produced a caution line: "$line"');
      }
    });

    // The pair above pins the pools; neither can see the *gate*, because
    // widening `caution > 0.6` to `> 0.0` still drew from the explorer's own
    // `_explorer` pool and every assertion held. This one pins the gate by
    // using a pilot where the gate decides WHICH pool wins.
    test('the gate is what stops caution claiming a greedy pilot', () {
      // duranCollector: caution 0.5 (below the gate), greed 0.8 (above its
      // own). Intact, the gate declines it and greed supplies the flavour.
      // Widen the gate and caution would claim it first, and the pilot would
      // start quoting the clan instead of asking about your hold.
      const greedyFlavour = [
        'What is in your hold?',
        'carrying something valuable',
        'full hold and an open wallet',
      ];
      const duranFlavour = [
        'The clan does not forget',
        'Krythos watches',
        'Steel answers steel',
      ];

      final collector = _npc(FactionClass.duran, NpcPersonality.duranCollector);
      final config = collector.personalityConfig;
      expect(config.caution, lessThan(0.6), reason: 'below the gate');
      expect(config.greed, greaterThan(0.7), reason: 'above the greed gate');

      final lines = [
        for (var i = 0; i < 80; i++)
          NpcChatter.greeting(collector, HailDisposition.neutral,
              rng: math.Random(i)),
      ];
      expect(lines.where((l) => greedyFlavour.any(l.contains)), isNotEmpty,
          reason: 'greed should be supplying this pilot\'s flavour');
      for (final line in lines) {
        expect(duranFlavour.any(line.contains), isFalse,
            reason: 'the caution gate was claimed when it should not have '
                'been: "$line"');
      }
    });

    test('a pilot at the top of the aggression scale states it and stops', () {
      // Above 0.85 the suffix is dropped entirely: a warlord does not
      // qualify a threat. duranWarlord aggression is 0.95.
      const duranFlavour = [
        'The clan does not forget',
        'Krythos watches',
        'Steel answers steel',
        'buried better pilots',
      ];
      final warlord = _npc(FactionClass.duran, NpcPersonality.duranWarlord);
      expect(warlord.personalityConfig.aggression, greaterThan(0.85));

      for (final line in [
        for (var i = 0; i < 40; i++)
          NpcChatter.greeting(warlord, HailDisposition.hostile,
              rng: math.Random(i)),
      ]) {
        expect(duranFlavour.any(line.contains), isFalse,
            reason: 'a warlord qualified a threat: "$line"');
      }
    });
  });
}
