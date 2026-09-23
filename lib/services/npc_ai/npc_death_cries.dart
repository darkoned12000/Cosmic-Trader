import 'dart:math' as math;

import 'package:cosmic_trader/data/models/faction.dart';

class NpcDeathCries {
  static final _rng = math.Random();

  static String getCry(FactionClass faction) {
    final list = _cries[faction] ?? _defaultCries;
    return list[_rng.nextInt(list.length)];
  }

  static String formatDeathCry(String pilotName, FactionClass faction) {
    final cry = getCry(faction);
    return '$pilotName broadcasts: "$cry"';
  }

  static const _duranCries = [
    'For the Hegemony! Avenge my steel!',
    'My scales shatter, but our will endures!',
    'You dare defy Krythos\'s wrath? You\'ll burn!',
    'The clan will carve your name in blood!',
    'Iron bends, but the Duran never break!',
    'This is not defeat... it\'s a signal for war!',
    'My hull\'s gone, but our forge burns eternal!',
    'You\'ll choke on the ashes of this mistake!',
    'Grah! My warlord will crush your bones!',
    'The Monolith will grind you to dust!',
    'Tell the fleet... I held the line...',
    'Our claws will rend your worlds apart!',
    'This wreck fuels our vengeance!',
    'Ugh! My bonus was *this* close to vesting!',
    'Who parked that asteroid in my flight path?!',
  ];

  static const _vinariCries = [
    'The Collective weeps... but the cosmos remembers!',
    'My light fades, yet the Veil endures!',
    'You fracture the harmony... we\'ll realign you!',
    'This anomaly will be corrected, interloper!',
    'My essence joins the stellar currents...',
    'The Spire will sing of this betrayal!',
    'Our data binds us... you cannot erase us!',
    'Celestara weeps for this disruption!',
    'The stars will judge your recklessness!',
    'My tendrils dissolve... but the Collective rises!',
    'This chaos offends the cosmic flow!',
    'The calculations... were flawless...',
    'You dim our glow, but not our purpose!',
    'Error... my warranty doesn\'t cover explosions!',
    'Whoops... miscalculated the escape vector!',
  ];

  static const _traderCries = [
    'My cargo! My margins! Ruined!',
    'You\'ll pay for this... in credits or blood!',
    'This deal just cost me everything!',
    'The Guild won\'t cover this insurance claim!',
    'Vionis will hear of this outrage!',
    'You wrecked my best trade run yet!',
    'This is why I hate rush deliveries!',
    'My profits... sinking into the void...',
    'Tell my clients... the deal\'s off!',
    'Should\'ve upgraded the shields!',
    'My ledger\'s redder than a supernova!',
    'This wreck\'s coming out of your paycheck!',
    'Why didn\'t I stick to safe sectors?!',
    'I knew that discount warp drive was a scam!',
    'My stash was hidden in— nooo!',
  ];

  static const _pirateCries = [
    'The booty was mine! All mine!',
    'You\'ll make a fine treasure chest... when you\'re dead!',
    'Yarr... the void takes me... but me crew\'ll get ya!',
    'This ain\'t over, scallywag! I\'ll haunt yer nav computer!',
    'Me cutlass is bent but me spirit\'s still sharp!',
    'Bury me with me credits... wait, they\'re already gone!',
    'A space kraken could\'ve taken me, but YOU?! Unacceptable!',
    'Tell the boys... I went out... looting...',
    'The ghost fleet\'s gonna have words with you!',
    'So this is what it feels like to be on the receiving end!',
    'I\'ve been double-crossed by better scoundrels than you!',
    'Me ship may be scrap, but me legend\'s just getting started!',
    'Next time... I\'m investing in better hull plating...',
    'You call that a broadside? My granny fires harder!',
    'Funny... I always figured I\'d go out in an explosion...',
  ];

  static const _defaultCries = [
    'My ship! My pride!',
    'This is not how I go out!',
    'You\'ll regret this, spacer!',
    'The void claims me...',
    'Tell my crew... I tried...',
    'Engines failing... stars fading...',
    'This wreck\'s on you!',
    'Nooo! My life\'s work!',
    'Hull breached... hope\'s gone...',
    'Guess I\'m space dust now!',
  ];

  static const Map<FactionClass, List<String>> _cries = {
    FactionClass.duran: _duranCries,
    FactionClass.vinari: _vinariCries,
    FactionClass.trader: _traderCries,
    FactionClass.pirate: _pirateCries,
  };
}
