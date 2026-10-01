import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';
import 'package:cosmic_trader/data/models/npc_ship.dart';
import 'package:cosmic_trader/data/models/player.dart';
import 'package:cosmic_trader/data/models/reputation.dart';
import 'package:cosmic_trader/services/npc_ai/npc_personality.dart';

/// What a pilot makes of you at a glance. Derived from the same
/// hostility and standing rules the AI itself acts on, so the greeting
/// agrees with what would actually happen if you kept talking.
enum HailDisposition {
  /// Hostile faction, or standing at or below the refusal line.
  hostile,

  /// Not hostile, but you are disliked.
  wary,

  /// No history either way.
  neutral,

  /// Friendly faction and standing in your favour.
  friendly,
}

/// Spoken lines for a hail.
///
/// **Why this exists.** Hailing an NPC used to return the same datasheet every
/// time — ship, faction, the full background paragraph, the personality's enum
/// name, the full philosophy. It reads like a codex entry, and it is the one
/// interaction the player can perform with *every* ship in their sector. So it
/// is the cheapest possible place to make the galaxy feel inhabited: give the
/// pilot an actual sentence, chosen from who they are and what they make of
/// you, and let the lore sit underneath as background rather than as the
/// whole encounter.
///
/// **Tone is derived, not rolled.** Aggression, greed and caution pick the
/// register, so a warlord does not greet you like a smuggler, and a greedy
/// trader asks about cargo. The randomness only chooses *within* the register
/// the model has already chosen.
///
/// Flutter-free, so it is testable without a widget tree.
class NpcChatter {
  NpcChatter._();

  /// Standing at or below which a port slams the door, and a pilot stops
  /// being polite about it. Mirrors [Port.hostileServiceThreshold] rather than
  /// restating the number.
  static const int _refusalStanding = -50;

  /// The corpus a disposition draws from, exposed for testing.
  ///
  /// **This exists because the mapping was untested.** `greeting()` switches
  /// disposition → pool, and every guard asserted only that the *disposition*
  /// was computed correctly — never that the line came from the matching
  /// corpus. Swapping the hostile and friendly pools produced **zero** failures
  /// across the whole suite: a pirate would have greeted you warmly and every
  /// test stayed green. A `@visibleForTesting` accessor is the cheap fix; the
  /// alternative is a prose match on hostile-sounding words, which is brittle
  /// and would be deleted the first time a line was reworded.
  /// (No `@visibleForTesting` annotation: this file is deliberately
  /// Flutter-free so the model layer can import it, and the annotation lives in
  /// `package:flutter/foundation.dart`.)
  static List<String> poolFor(HailDisposition disposition, FactionClass f) =>
      switch (disposition) {
        HailDisposition.hostile => _hostile[f] ?? _hostileDefault,
        HailDisposition.wary => _wary[f] ?? _waryDefault,
        HailDisposition.neutral => _neutral[f] ?? _neutralDefault,
        HailDisposition.friendly => _friendly[f] ?? _friendlyDefault,
      };

  /// Deterministic-by-seed variant, for tests and for a repeatable line.
  ///
  /// The production path passes a shared RNG; passing `rng` makes a hail
  /// reproducible, which is what the guards need in order to assert on a
  /// specific register instead of "some line appeared".
  static String greeting(
    NpcShip npc,
    HailDisposition disposition, {
    math.Random? rng,
  }) {
    final pool = poolFor(disposition, npc.faction);
    final r = rng ?? _rng;
    final line = pool[r.nextInt(pool.length)];

    // A personality with a strong opinion colours the line. Applied as a
    // suffix rather than a separate pool, so the base line still carries the
    // disposition and a cautious smuggler and a cautious warlord differ in
    // register without four duplicated corpora.
    final flavour = _flavourFor(npc, rng: r);
    if (flavour == null) return line;
    // Pilots at the very top of the aggression scale do not qualify their
    // threats, so they get the line and nothing else.
    if (npc.personalityConfig.aggression > 0.85) return line;
    return r.nextDouble() < 0.55 ? '$line $flavour' : line;
  }

  /// The register this pilot greets you in.
  ///
  /// Uses the same hostility rule the AI uses to decide whether to attack and
  /// the same standing threshold the ports use to refuse service, so the line
  /// can never contradict the simulation: a pilot calling you a friend is one
  /// the tick will not open fire on. A hostile faction is never above `wary`
  /// however much it likes you, which is what stops a Duran warlord with
  /// positive standing from opening with a welcome.
  static HailDisposition dispositionFor(NpcShip npc, Player player) {
    final standing = player.factionStandingWith(npc.faction);
    final byStanding = dispositionForStandingOnly(standing);
    if (byStanding == HailDisposition.hostile) return byStanding;
    if (_hostileFaction(npc.faction, player.faction)) {
      return byStanding == HailDisposition.friendly
          ? HailDisposition.wary
          : byStanding;
    }
    return byStanding;
  }

  /// Standing-only half of [dispositionFor], split out so it is directly
  /// testable without constructing a player for every case.
  static HailDisposition dispositionForStandingOnly(int standing) {
    if (standing <= _refusalStanding) return HailDisposition.hostile;
    if (standing < 0) return HailDisposition.wary;
    if (standing > 25) return HailDisposition.friendly;
    return HailDisposition.neutral;
  }

  /// Delegates rather than mirroring. This used to be a private copy of the
  /// AI's rule so that the two could be "compared directly in a test" — which is
  /// a test that passes precisely because the copies agree, and says nothing the
  /// moment one of them is edited. Now there is one rule and one owner, and the
  /// guard asserts the *behaviour* (a peaceful pilot is not greeted as an
  /// enemy) rather than that two transcriptions match.
  static bool _hostileFaction(FactionClass a, FactionClass b) =>
      FactionHostility.areHostile(a, b);

  /// A single sentence of personality colour, or null for a bland archetype.
  static String? _flavourFor(NpcShip npc, {required math.Random rng}) {
    final config = npc.personalityConfig;
    final pool = switch (npc.personality) {
      NpcPersonality.duranConqueror ||
      NpcPersonality.duranWarlord ||
      NpcPersonality.duranCollector =>
        _duran,
      NpcPersonality.pirateRaider ||
      NpcPersonality.piratePillager ||
      NpcPersonality.pirateHunter =>
        _pirate,
      NpcPersonality.traderMerchant || NpcPersonality.traderSmuggler => _trader,
      NpcPersonality.traderExplorer => _explorer,
      NpcPersonality.vinariExplorer || NpcPersonality.vinariSeeker => _seeker,
      NpcPersonality.vinariProtector => _protector,
    };
    // Caution speaks first, then greed, then aggression: the trait that most
    // colours a *greeting* is how careful they are, not how hard they hit.
    if (config.caution > 0.6) return pool[rng.nextInt(pool.length)];
    if (config.greed > 0.7) return _greedy[rng.nextInt(_greedy.length)];
    if (config.aggression > 0.7) return _hard[rng.nextInt(_hard.length)];
    return null;
  }

  static final math.Random _rng = math.Random();

  // ── Disposition pools ──────────────────────────────────────────

  static const Map<FactionClass, List<String>> _hostile = {
    FactionClass.duran: [
      'State your business or be a stain on the deck.',
      'Hegemony does not parley. Turn around.',
      'You are standing in a conqueror\'s firing solution.',
      'Claws out. You are not welcome on this hull.',
      'Say it fast, spacer. I am busy.',
    ],
    FactionClass.vinari: [
      'Your approach is an intrusion. We note it.',
      'The harmony is disturbed. You are the disturbance.',
      'Step back from the Collective, intruder.',
      'You read as an error. Errors get corrected.',
      'We see you. That is not a greeting.',
    ],
    FactionClass.trader: [
      'No. Not to you. Not today.',
      'Clear the gangway, or I clear it with you in it.',
      'You are on my blacklist. Move.',
      'Trade is closed. Everything is closed.',
      'I would ask nicely, but I already decided.',
    ],
    FactionClass.pirate: [
      'That is my rock. Turn around and keep walking.',
      'You picked the wrong lane, friend.',
      'Everything here is mine, including you, briefly.',
      'Hand over the hold and nobody has to get wet.',
      'Wrong ship, wrong sector, wrong life.',
    ],
  };

  static const List<String> _hostileDefault = [
    'State your business.',
    'You are not welcome here.',
    'Move along.',
  ];

  static const Map<FactionClass, List<String>> _wary = {
    FactionClass.duran: [
      'I know your face. I do not like it.',
      'Hegemony is watching. Speak plainly.',
      'You have a reputation. Use it carefully.',
      'I will hear you out. Once.',
      'Do not waste my time, spacer.',
    ],
    FactionClass.vinari: [
      'Your record precedes you. It is not flattering.',
      'We have observed you. Ambiguously.',
      'The Collective has notes on you.',
      'You are tolerated. Do not mistake that for welcome.',
      'Speak. The Veil is listening.',
    ],
    FactionClass.trader: [
      'I know what your lot did to the last guild crew.',
      'I will trade, but I am counting under my breath.',
      'Bad reputation, thin margins, worse odds.',
      'You want credit? Earn it first.',
      'I do not enjoy this, but I am listening.',
    ],
    FactionClass.pirate: [
      'You are known. Not liked, just known.',
      'Keep your hands visible and we can talk.',
      'I have taken worse company, but not today.',
      'You smell like a bounty. I am watching you.',
      'Talk fast, and talk honest.',
    ],
  };

  static const List<String> _waryDefault = [
    'I know what you are.',
    'Say your piece.',
    'I am listening, barely.',
  ];

  static const Map<FactionClass, List<String>> _neutral = {
    FactionClass.duran: [
      'Hegemony. What do you want.',
      'You are aboard a warship. Be brief.',
      'State your rank and your purpose.',
      'Clans do not fraternise, but we are civilised.',
      'Make it quick. There is a campaign.',
    ],
    FactionClass.vinari: [
      'The Collective greets you. Formally.',
      'You are... unexpected.',
      'We have not decided about you yet.',
      'Greetings, traveller. The Veil shifts around you.',
      'Ask. We are not often interrupted.',
    ],
    FactionClass.trader: [
      'Guild prices today. Everything negotiable, nothing generous.',
      'Loading dock is open. Mind the forklift drones.',
      'You want cargo, credit, or both? Everyone wants both.',
      'Trade welcome. Keep your cargo manifest current.',
      'Careful where you step, the margins are thin.',
    ],
    FactionClass.pirate: [
      'Ah. A ship. Nice hull, underarmed.',
      'You are off my charts. That is either very good or very bad.',
      'No Guild, no trouble. Enjoy it while it lasts.',
      'Come to trade or come to hide? People always say trade.',
      'Plenty of room out here for the desperate.',
    ],
  };

  static const List<String> _neutralDefault = [
    'Greetings, captain.',
    'What brings you here?',
    'You are welcome aboard.',
  ];

  static const Map<FactionClass, List<String>> _friendly = {
    FactionClass.duran: [
      'Clans remember their friends. You are one. Currently.',
      'Hegemony salutes you. Do not make me regret it.',
      'You fought well. That earns more than credits.',
      'A friend of the forge. Sit, if you can.',
      'We do not offer this often. Remember that.',
    ],
    FactionClass.vinari: [
      'You are welcome in the harmony. Genuinely.',
      'The Collective remembers what you did. So do we.',
      'The Veil is calmer near you. That is not nothing.',
      'You are one of ours now, as far as we are concerned.',
      'Greetings, friend. Sit with us a while.',
    ],
    FactionClass.trader: [
      'Ah, my favourite kind of customer.',
      'For you, Guild rates. Do not spread that.',
      'You have good credit. That opens doors.',
      'Partners. I do not say that lightly.',
      'Come in, come in. The good stock is in the back.',
    ],
    FactionClass.pirate: [
      'Well, well. My favourite sort of fool.',
      'You are on the right side of history, for once.',
      'I do not trust you. I like you. Both are true.',
      'Come aboard. Leave your guns, we will not reach them.',
      'You are the only honest thing on this rock.',
    ],
  };

  static const List<String> _friendlyDefault = [
    'Good to see you again, captain.',
    'You are among friends here.',
    'Come in out of the cold.',
  ];

  // ── Personality flavours ───────────────────────────────────────

  static const List<String> _duran = [
    'The clan does not forget.',
    'Krythos watches.',
    'Steel answers steel.',
    'I have buried better pilots than you.',
  ];

  static const List<String> _pirate = [
    'No insurance, no complaints.',
    'Everything is negotiable except the price.',
    'I know a guy who owes me a favour.',
  ];

  static const List<String> _trader = [
    'Margins are thin, but they exist.',
    'I can do a rate. I cannot do a favour.',
    'Nobody ships for free, captain.',
  ];

  static const List<String> _explorer = [
    'There is more out here than maps admit.',
    'I go where nobody has charted.',
    'Wider orbits, stranger company.',
  ];

  static const List<String> _seeker = [
    'The data is incomplete. Everything is incomplete.',
    'Something is out there that should not be.',
    'I follow the signal. You are in the way, mildly.',
  ];

  static const List<String> _protector = [
    'The Collective is watching. So am I.',
    'Nothing happens here that I do not permit.',
    'You are safe. That is not a promise I make often.',
  ];

  static const List<String> _greedy = [
    'What is in your hold?',
    'I hope you are carrying something valuable.',
    'A full hold and an open wallet. My favourite combination.',
  ];

  static const List<String> _hard = [
    'I do not make a habit of conversation.',
    'Move along or be moved.',
    'This is not a friendly space.',
  ];
}
