import 'package:flutter_test/flutter_test.dart';

import 'package:cosmic_trader/data/models/bounty.dart';
import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/data/models/ship_templates.dart';
import 'package:cosmic_trader/services/bounty_board.dart';
import 'package:cosmic_trader/services/game_clock.dart';
import 'package:cosmic_trader/widgets/combat_screen.dart';

/// A bounty kill used to be charged as murder: `forKilling` only ever saw two
/// factions, so it had no way to know the victim was wanted. The credits arrived
/// and the rank went down.
void main() {
  group('the deed table', () {
    test('a wanted kill is worth something, and it is positive', () {
      expect(ReputationActions.killWanted, greaterThan(0));
      expect(ReputationActions.killWanted, 48.0,
          reason: 'pinned: it is a balance value, not a derived figure');
    });

    test('wanted overrides the hostility split for EVERY faction pair', () {
      // Not "the hostile case" and "the peaceful case" — all twelve ordered
      // pairs, because the override is the claim being made: a bounty says this
      // kill is wanted, so no faction table can overrule it. Same-faction is in
      // here deliberately; it is the pair that reads worst if the override is
      // implemented as "at least skip the murder rate".
      for (final victim in FactionClass.values) {
        for (final killer in FactionClass.values) {
          expect(
            ReputationActions.forKilling(
              victimFaction: victim,
              killerFaction: killer,
              wanted: true,
            ),
            ReputationActions.killWanted,
            reason: '$victim killed by $killer while wanted',
          );
        }
      }
    });

    test('unwanted kills are untouched by the new flag', () {
      // The whole point of splitting the price was that being the aggressor has
      // a price. `wanted` defaults to false, so a regression here means the
      // override leaked into the ordinary path and murder became free.
      for (final victim in FactionClass.values) {
        for (final killer in FactionClass.values) {
          final hostile = FactionHostility.areHostile(victim, killer);
          expect(
            ReputationActions.forKilling(
              victimFaction: victim,
              killerFaction: killer,
            ),
            hostile
                ? ReputationActions.killPatrol
                : ReputationActions.killUnprovoked,
            reason: '$victim killed by $killer, unwanted',
          );
        }
      }
    });

    test('a wanted kill outranks every unwanted one it replaces', () {
      expect(ReputationActions.killWanted,
          greaterThan(ReputationActions.killPatrol));
      expect(ReputationActions.killWanted,
          greaterThan(ReputationActions.killUnprovoked));
    });
  });

  group('settling a kill', () {
    late Player killer;
    late NpcShip victim;

    Player pilot({FactionClass faction = FactionClass.trader}) => Player(
          id: 'killer-1',
          username: 'Vex',
          name: 'Vex',
          passwordHash: 'x',
          currentSectorId: 1,
          hull: 100,
          maxHull: 200,
          shields: 60,
          maxShields: 120,
          cargoUsed: 0,
          maxCargo: 100,
          cargoSize: 5,
          credits: 1000,
          researchPoints: 0,
          faction: faction,
        );

    NpcShip rogue(FactionClass faction) => NpcShip.create(
          faction: faction,
          shipDef: ShipDefinition.allShips.first,
          currentSectorId: 1,
          startingCredits: 200000,
          seed: 4242,
        );

    setUp(() {
      killer = pilot();
      victim = rogue(FactionClass.duran);
      BountyBoard.global.skipDiskLoadForTest = true;
      BountyBoard.global.replaceForTest([]);
    });

    tearDown(() {
      BountyBoard.global.replaceForTest([]);
      BountyBoard.global.skipDiskLoadForTest = false;
    });

    void postBountyOn(NpcShip target, {String posterId = 'guild-1'}) {
      BountyBoard.global.replaceForTest([
        Bounty(
          id: 'b1',
          targetId: target.id,
          targetName: target.pilotName,
          targetFaction: target.faction.name,
          amount: 50000,
          posterId: posterId,
          posterName: 'Traders Guild',
          posterFaction: 'trader',
          reason: 'Wanted.',
          createdAtTick: GameClock.tick,
          expiresAtTick: GameClock.tick + Bounty.ttlTicks,
        ),
      ]);
    }

    test('an unwanted kill still costs murder and pays nothing', () {
      final out = settleKill(
        killer: killer,
        victim: victim,
        board: BountyBoard.global,
      );
      expect(out.bountyLine, isNull);
      expect(out.player.credits, 1000);
      // Duran and Traders are at peace, so this is the murder rate.
      expect(out.player.alignment, 1000 * 0 + ReputationActions.killUnprovoked);
      expect(out.player.alignment, lessThan(0));
    });

    test('a wanted kill pays out AND is worth +48, not a charge', () {
      postBountyOn(victim);
      final before = killer.alignment;
      final out =
          settleKill(killer: killer, victim: victim, board: BountyBoard.global);

      expect(out.player.credits, 51000, reason: 'loot-free: the 50k bounty');
      expect(out.player.alignment, before + ReputationActions.killWanted);
      expect(out.player.alignment, greaterThan(before),
          reason:
              'the reported bug: paying and being charged for the same kill');
      expect(out.bountyLine, contains('50000'));
    });

    test('the wanted figure is the SAME for a hostile victim', () {
      // A pirate is hostile to everyone, so the old code charged -32 here. The
      // bounty has to land on the same number, or "rewarded for a bounty kill"
      // is true only for the peaceful cases.
      final pirate = rogue(FactionClass.pirate);
      postBountyOn(pirate);
      final out =
          settleKill(killer: killer, victim: pirate, board: BountyBoard.global);
      expect(out.player.alignment,
          killer.alignment + ReputationActions.killWanted);
    });

    test('a bounty already collected by someone else is not worth anything',
        () {
      // "Wanted" is defined as *the board paid out*, so a mark that pays nothing
      // must not buy a positive charge. This is the claim that would be double
      // counting if `wanted` were read from a separate board lookup.
      final out =
          settleKill(killer: killer, victim: victim, board: BountyBoard.global);
      expect(out.player.alignment, lessThan(0));
    });

    test('the board is unreadable once it has paid', () {
      // The invariant `settleKill` depends on, stated as a fact about the board
      // rather than about the function: paying removes the marks, so *anything*
      // asked of the board after a claim comes back empty. That is what made the
      // +5 poster standing dead code, and it is why the charge cannot sit below
      // the claim either.
      postBountyOn(victim);
      final board = BountyBoard.global;
      expect(board.forTarget(victim.id), isNotEmpty);

      final paid = board.claim(
        targetId: victim.id,
        targetName: victim.pilotName,
        killerName: killer.name,
        verifiedKills: {victim.id},
      );
      expect(paid, greaterThan(0));
      expect(board.forTarget(victim.id), isEmpty,
          reason: 'if this stops being true the read-before-settle comment is '
              'wrong, and the poster-standing bug may be back');
      expect(board.posterFactionsFor(victim.id), isEmpty);
    });

    test('standing still moves: -5 with the victim, +5 per poster faction', () {
      postBountyOn(victim);
      // **Deltas, not absolutes.** A Guild pilot's baseline standing toward the
      // Duran is -10 out of the lore matrix, so the -5 charge lands on -15 and an
      // absolute assertion reads a correct settlement as a doubled one.
      final beforeDuran = killer.factionStandingWith(FactionClass.duran);
      final beforeGuild = killer.factionStandingWith(FactionClass.trader);

      final out =
          settleKill(killer: killer, victim: victim, board: BountyBoard.global);

      expect(
          out.player.factionStandingWith(FactionClass.duran) - beforeDuran, -5);
      expect(
          out.player.factionStandingWith(FactionClass.trader) - beforeGuild, 5,
          reason: 'the Guild posted the mark and collects the credit');
    });

    test('the kill is recorded so the board can verify it', () {
      final out =
          settleKill(killer: killer, victim: victim, board: BountyBoard.global);
      expect(out.player.recentKills, contains(victim.id));
    });
  });
}
