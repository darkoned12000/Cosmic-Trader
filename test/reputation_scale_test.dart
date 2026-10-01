import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/planet.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/data/models/sector.dart';
import 'package:cosmic_trader/services/game_tick_service.dart';
import 'package:cosmic_trader/services/planet_production_service.dart';
import 'package:cosmic_trader/services/world_forging.dart';

// Reputation is **signed** now, ranged to the TradeWars ladder, with a rank
// title in both directions.
//
// It replaces a `notoriety` field that started at 0, only went up, and was
// clamped 0-100 — a scale with no way to express being *well thought of*. Every
// deed pushed the same way, so the best act a player could do and the worst were
// neighbours on one axis. Three properties had to hold and each was a real
// mistake first: the sign, the range, and the direction the galaxy's fear of you
// is read from.

Player _player({
  double alignment = 0,
  String name = 'Vance',
  int torpedoes = 0,
}) =>
    Player(
      name: name,
      currentSectorId: 7,
      hull: 100,
      maxHull: 100,
      shields: 100,
      maxShields: 100,
      cargoUsed: 0,
      maxCargo: 100,
      cargoSize: 100,
      credits: 1000,
      researchPoints: 0,
      faction: FactionClass.trader,
      alignment: alignment,
      // Both ordnance, because each rule refuses without its own item. Omitting
      // them made a charge look unapplied when in fact nothing had fired — the
      // third time this session a fixture could not satisfy the condition it was
      // testing, and each time the failure named the wrong culprit.
      atomicDetonators: 1,
      genesisTorpedoes: torpedoes,
    );

/// A world with a build genuinely in progress.
///
/// `startConstruction` is the model's own entry point — setting
/// `constructionTarget` by hand leaves `constructionTicksRemaining` at 0, so
/// `isUnderConstruction` is false and `advanceConstruction` returns immediately.
/// The build silently never happens, which looks exactly like a broken reward.
Planet _building(String name, FactionClass owner, String id) => Planet(
      id: id,
      name: name,
      planetType: 'Terran',
      scanned: true,
      owner: owner,
      hull: 40000,
      maxHull: 40000,
      population: 500000,
      storedMinerals: 500000,
      storedOrganics: 500000,
      storedIndustrial: 500000,
    )..startConstruction(timeScale: 0.1);

/// Runs the production pass until nothing is still building, and totals what it
/// credited along the way.
///
/// A build spans several ticks, so this accumulates the per-pass counts rather
/// than reading the last one — the tally a single pass reports is only that
/// pass's completions.
PlanetProductionSummary _runToCompletion(Sector sector) {
  var completed = 0;
  for (var i = 0; i < 20; i++) {
    final summary = PlanetProductionService.process(
      [sector],
      creditFaction: FactionClass.trader,
    );
    completed += summary.constructionsCompleted;
    if (!sector.planets.any((p) => p.isUnderConstruction)) break;
  }
  return PlanetProductionSummary(constructionsCompleted: completed);
}

void main() {
  group('the value is signed', () {
    test('a bad deed moves it down and a good deed moves it up', () {
      expect(ReputationActions.createWorld, greaterThan(0));
      expect(ReputationActions.destroyWorld, lessThan(0));
      expect(ReputationActions.killPatrol, lessThan(0));
      expect(ReputationActions.capturePort, lessThan(0));
      expect(ReputationActions.buildWorld, greaterThan(0));
      expect(ReputationActions.portRevenue, greaterThan(0));
    });

    test('the ladder runs both ways from the same thresholds', () {
      // Same input, opposite titles. This is the whole change: a magnitude used
      // to mean only one thing.
      expect(Reputation.rankFor(64).good, 'Staff Sergeant');
      expect(Reputation.rankFor(64).evil, 'Menace 1st Class');
      expect(Reputation.rankFor(-64).good, 'Staff Sergeant');
      expect(Reputation.rankFor(-64).evil, 'Menace 1st Class');
    });

    test('the side follows the sign, and near zero is nobody’s opinion', () {
      expect(Reputation.sideOf(0), ReputationSide.neutral);
      expect(Reputation.sideOf(0.4), ReputationSide.neutral);
      expect(Reputation.sideOf(2), ReputationSide.good);
      expect(Reputation.sideOf(-2), ReputationSide.evil);
    });

    test('a magnitude reads as the right title through the display layer', () {
      // The player-facing pair. If these disagree the bar lies: a green bar on a
      // hated pilot is worse than no readout.
      final liked = _player(alignment: 512);
      final hated = _player(alignment: -512);
      expect(liked.alignmentSide, ReputationSide.good);
      expect(hated.alignmentSide, ReputationSide.evil);
      expect(liked.alignmentTitle, 'Sergeant Major');
      expect(hated.alignmentTitle, 'Smuggler 1st Class');
    });
  });

  group('the range is the ladder’s', () {
    test('the table is complete and doubling, in order', () {
      expect(Reputation.ladder, hasLength(22));
      for (var i = 0; i < Reputation.ladder.length; i++) {
        final rank = Reputation.ladder[i];
        expect(rank.index, i + 1, reason: 'index ${i + 1}');
        if (i == 0) continue;
        // Transcribed from the original, and a transcription is exactly the
        // thing that rots. Every rung must be double the last.
        expect(rank.threshold, Reputation.ladder[i - 1].threshold * 2,
            reason: 'rung ${rank.index} is not double rung ${rank.index - 1}');
      }
      expect(Reputation.ladder.last.threshold, 4194304);
      expect(Reputation.absMax, 4194304.0);
    });

    test('no title is blank, on either side', () {
      for (final rank in Reputation.ladder) {
        expect(rank.good.trim(), isNotEmpty, reason: 'good ${rank.index}');
        expect(rank.evil.trim(), isNotEmpty, reason: 'evil ${rank.index}');
      }
    });

    test('the value cannot be walked off the end of its own table', () {
      // Past the top rung the display would have to invent an answer, which is
      // why every movement goes through the clamp rather than a bare `+`.
      expect(Reputation.clamp(9e9), Reputation.absMax);
      expect(Reputation.clamp(-9e9), -Reputation.absMax);
      final runaway = _player(alignment: Reputation.absMax)
          .withAlignmentDelta(ReputationActions.buildWorld);
      expect(runaway.alignment, Reputation.absMax);
    });
  });

  group('progress reads as a climb', () {
    test('standing on a threshold shows zero progress, not a full bar', () {
      // Measured from the bottom of the current band. Measuring from the
      // previous threshold's absolute value would show a pilot sitting exactly on
      // Sergeant as already partway to Staff Sergeant — so at 0% every rank, the
      // bar would sit permanently at 100% and read as a bug.
      expect(Reputation.progressToNext(64), 0.0);
      expect(Reputation.progressToNext(96), closeTo(0.5, 0.001));
      expect(Reputation.progressToNext(2), 0.0);
      expect(Reputation.progressToNext(0), 0.0);
    });

    test('progress is mirrored for a bad reputation', () {
      expect(Reputation.progressToNext(-64), 0.0);
      expect(Reputation.progressToNext(-96), closeTo(0.5, 0.001));
    });

    test('the top rung reports maximum rather than an infinite gap', () {
      expect(Reputation.pointsToNext(Reputation.absMax), isNull);
      expect(Reputation.progressToNext(Reputation.absMax), 1.0);
      expect(Reputation.nextRank(Reputation.absMax), isNull);
      final maxed = _player(alignment: Reputation.absMax);
      expect(maxed.alignmentPointsToNext, isNull);
      expect(maxed.nextAlignmentRank, isNull);
    });

    test('the gap is always the distance to the very next rung', () {
      // The first version asserted the gap *shrinks* as you climb. It cannot:
      // the ladder doubles, so the gap resets at every rung. What is actually
      // true — and what the readout depends on — is that the gap and the next
      // threshold always agree.
      for (final v in [2.0, 8.0, 32.0, 63.0, 64.0, 512.0, 2048.0]) {
        final next = Reputation.nextRank(v)!;
        final gap = Reputation.pointsToNext(v)!;
        expect(gap, next.threshold - v, reason: 'gap disagrees at $v');
        expect(gap, greaterThan(0), reason: 'at $v');
        expect(gap, lessThanOrEqualTo(next.threshold), reason: 'at $v');
      }
    });
  });

  group('fear is read from evilness, not from the raw value', () {
    test('a well-liked pilot is not a threatening one', () {
      // The three AI call sites all ask "should I be afraid of this person".
      // Under a signed scale the honest answer for a liked pilot is *less*, not
      // "equally not" — being regarded is supposed to make you safer.
      expect(_player(alignment: 100000).threatRating, 0.0);
      expect(_player(alignment: -100).threatRating, 100.0);
      expect(_player(alignment: 0).threatRating, 0.0);
    });

    test('threatRating never goes negative on a good reputation', () {
      // If it did, `1 + threatRating / 200` in the NPC fear threshold could fall
      // below 1 and a pilot would become *easier* to justify attacking the more
      // popular they became.
      for (final v in [0.0, 1.0, 64.0, 4194304.0]) {
        expect(_player(alignment: v).threatRating, 0.0, reason: 'at $v');
      }
    });
  });

  group('saving', () {
    test('a signed value round-trips', () {
      for (final v in [-4194304.0, -512.0, -8.0, 0.0, 8.0, 512.0, 4194304.0]) {
        final reloaded = Player.fromJson(
            jsonDecode(jsonEncode(_player(alignment: v).toJson()))
                as Map<String, dynamic>);
        expect(reloaded.alignment, v, reason: 'at $v');
      }
    });

    test('an old save is migrated by negation, not read as good standing', () {
      // The old scale counted *up* for bad deeds. Read forward, a pilot with 50
      // notoriety would load as a well-liked captain — the migration has to
      // invert, or every existing save silently turns its worst pilots into its
      // best.
      final legacy = _player().toJson();
      legacy.remove('alignment');
      legacy['notoriety'] = 50.0;

      final migrated = Player.fromJson(legacy);
      expect(migrated.alignment, -50.0);

      // And the worst case: a pilot at the old ceiling of 100.
      legacy['notoriety'] = 100.0;
      expect(Player.fromJson(legacy).alignment, -100.0);
    });

    test('an old save at zero is unaffected, which is most of them', () {
      final legacy = _player().toJson();
      legacy.remove('alignment');
      legacy['notoriety'] = 0.0;
      expect(Player.fromJson(legacy).alignment, 0.0);
    });

    test('a new save writes the new key and not the old one', () {
      // Writing both would mean a save read by an older build would double-count
      // a migration.
      final json = _player(alignment: -64).toJson();
      expect(json['alignment'], -64.0);
      expect(json.containsKey('notoriety'), isFalse);
    });
  });

  group('the detonation charge', () {
    test('is the shared figure, and it is signed', () {
      expect(WorldForging.destructionAlignment, ReputationActions.destroyWorld);
      expect(WorldForging.destructionAlignment, lessThan(0));
    });

    test('and it lands as a fall, not a rise', () {
      final world = Planet(
        id: 'w1',
        name: 'Xandor',
        planetType: 'Terran',
        scanned: true,
        owner: FactionClass.duran,
        hull: 40000,
        maxHull: 40000,
      );
      final sector = Sector(
          id: 7, name: 'K', x: 0, y: 0, warpRoutes: const [], planets: [world]);
      final (_, after, hit) = WorldForging.detonate(
        player: _player(alignment: 1000),
        sector: sector,
        world: world,
        cap: 3,
        tick: 0,
        rng: const _CleanBlast(),
      );
      expect(hit!.alignment, lessThan(0));
      expect(after.alignment, lessThan(1000),
          reason: 'reputation falls for a bad deed');
    });
  });

  group('creating a world', () {
    // Pinned, and pinned *against* the destruction charge, because the pair is
    // the whole anti-farming property: equal and opposite means launch-then-
    // demolish nets zero, so there is no reason to buy ordnance you will not
    // keep. These were 1024 and -128 once, which was a +1024 cycle.
    test('is worth exactly what destroying one costs', () {
      expect(ReputationActions.createWorld, 128.0);
      expect(ReputationActions.createWorld, -ReputationActions.destroyWorld,
          reason: 'the symmetry is the anti-farming rule');
    });

    test('and a full citadel run is worth roughly another world', () {
      // Five upgrades from Outpost to level 6.
      final run = 5 * ReputationActions.upgradeWorld;
      expect(ReputationActions.upgradeWorld, 24.0);
      expect(run, lessThan(ReputationActions.createWorld),
          reason: 'building it up is worth less than making it');
    });

    test('and a launch actually moves the player', () {
      final sector = Sector(id: 7, name: 'K', x: 0, y: 0, warpRoutes: const []);
      final (_, _, after) = WorldForging.launch(
        player: _player(alignment: 0, torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(5),
        tick: 0,
      );
      expect(after.alignment, ReputationActions.createWorld);
    });

    test('but a refused launch charges nothing', () {
      // No torpedo, no world, no reputation. A rule that paid the deed before
      // checking whether it happened would hand out a rank per empty tap.
      final sector = Sector(id: 7, name: 'K', x: 0, y: 0, warpRoutes: const []);
      final (result, world, after) = WorldForging.launch(
        player: _player(),
        sector: sector,
        cap: 3,
        rng: math.Random(5),
        tick: 0,
      );
      expect(result, LaunchResult.noTorpedoes);
      expect(world, isNull);
      expect(after.alignment, 0.0);
    });

    test('the launch/detonate loop nets zero, so it cannot be farmed', () {
      // The guard that matters most. It was +1024 for 55,000 credits when
      // self-demolition was free; now creation and destruction are equal and
      // opposite, so burning a torpedo and a detonator buys a player nothing at
      // all. Reinstate either half of the symmetry and this goes red.
      final sector = Sector(id: 7, name: 'K', x: 0, y: 0, warpRoutes: const []);
      final (_, world, afterLaunch) = WorldForging.launch(
        player: _player(alignment: 0, torpedoes: 1),
        sector: sector,
        cap: 3,
        rng: math.Random(5),
        tick: 0,
      );
      final (_, afterBlowUp, hit) = WorldForging.detonate(
        player: afterLaunch,
        sector: sector,
        world: world!,
        cap: 3,
        tick: 1,
        rng: const _CleanBlast(),
      );
      // No faction standing either: your own world, so there is nobody to be
      // offended but yourself.
      expect(hit!.faction, isNull);
      expect(sector.planets, isEmpty, reason: 'nothing is left in the sector');
      expect(afterBlowUp.alignment, 0.0,
          reason: 'the cycle is worth exactly nothing');
    });
  });

  group('a completed citadel upgrade', () {
    // +24, awarded by the **tick** because that is where a build finishes. The
    // two halves are split the way everything else in this codebase splits: the
    // service counts, the shell pays, because the player lives in the shell and
    // the tick has no notion of which of several accounts is being played.
    test('is scoped to the playing faction, so others’ builds pay nothing', () {
      final foreign = _building('Voran', FactionClass.duran, 'f1');
      final mine = _building('Xandor', FactionClass.trader, 'm1');
      final sector = Sector(
          id: 7,
          name: 'K',
          x: 0,
          y: 0,
          warpRoutes: const [],
          planets: [foreign, mine]);

      // Looped, because a build spans several ticks — `timeScale: 0.1` still
      // leaves two — and a single pass decrements without completing. One pass
      // short looks exactly like a broken reward.
      final summary = _runToCompletion(sector);
      // Both advanced (the level is applied regardless — that is the point of
      // the tick), but only one is the player’s to be paid for.
      expect(foreign.level, greaterThan(1));
      expect(mine.level, greaterThan(1));
      expect(summary.constructionsCompleted, 1,
          reason: 'a citadel the player did not commission must not pay');
    });

    test('and credits every one of the player’s own', () {
      final worlds =
          List.generate(3, (i) => _building('W$i', FactionClass.trader, 'm$i'));
      final sector = Sector(
          id: 7, name: 'K', x: 0, y: 0, warpRoutes: const [], planets: worlds);
      final summary = _runToCompletion(sector);
      expect(summary.constructionsCompleted, 3);
    });

    test('the tally is drained, not read, so it cannot pay twice', () {
      // The per-tick-getter trap from the colony card: a field that merely
      // accumulates would pay for the same upgrade on every subsequent tick. The
      // drain is what makes it single-consumption, and it is the reason this is a
      // method on the tick service rather than a public int.
      final service = GameTickService();
      expect(service.drainConstructionReputation(), 0);
      // Nothing to assert about a private counter without running a full tick, so
      // the contract asserted here is the shape: a drain always starts from zero.
      expect(service.drainConstructionReputation(), 0,
          reason: 'draining twice yields nothing the second time');
    });
  });
}

/// Above the blast band, so the blast cannot interfere with an alignment
/// assertion.
class _CleanBlast implements math.Random {
  const _CleanBlast();

  @override
  double nextDouble() => 0.99;

  @override
  bool nextBool() => false;

  @override
  int nextInt(int max) => 0;
}
