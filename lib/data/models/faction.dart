// faction.dart

enum FactionClass {
  duran,
  vinari,
  trader,
  pirate;

  String get displayName {
    switch (this) {
      case FactionClass.duran:
        return 'Duran Hegemony';
      case FactionClass.vinari:
        return 'Vinari Collective';
      case FactionClass.trader:
        return 'Independent Traders Guild';
      case FactionClass.pirate:
        return 'Pirates';
    }
  }
}

class Hero {
  final String name;
  final String title;
  final String shortBio;
  final String notableAchievement;

  const Hero({
    required this.name,
    required this.title,
    required this.shortBio,
    required this.notableAchievement,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'title': title,
        'shortBio': shortBio,
        'notableAchievement': notableAchievement,
      };

  factory Hero.fromJson(Map<String, dynamic> json) => Hero(
        name: json['name'] as String,
        title: json['title'] as String,
        shortBio: json['shortBio'] as String,
        notableAchievement: json['notableAchievement'] as String,
      );
}

class Faction {
  final FactionClass factionClass;
  final String name;
  final String banner; // e.g. 'assets/images/factions/duran_banner.png'

  final String background;
  final String philosophy;
  final String motto;
  final String motivations;
  final String racerelations;
  final String appearance;

  final String history;
  final String governmentType;
  final String economicStyle;
  final String techSignature;

  final List<String> keyEvents;
  final List<Hero> notableHeroes;
  final List<String> loreHooks;
  final Map<String, String> notableLocations;

  const Faction({
    required this.factionClass,
    required this.name,
    this.banner = '',
    required this.background,
    required this.philosophy,
    required this.motto,
    required this.motivations,
    required this.racerelations,
    required this.appearance,
    required this.history,
    required this.governmentType,
    required this.economicStyle,
    required this.techSignature,
    this.keyEvents = const [],
    this.notableHeroes = const [],
    this.loreHooks = const [],
    this.notableLocations = const {},
  });

  // ── JSON Support ───────────────────────────────
  Map<String, dynamic> toJson() => {
        'factionClass': factionClass.name,
        'name': name,
        'banner': banner,
        'background': background,
        'philosophy': philosophy,
        'motto': motto,
        'motivations': motivations,
        'racerelations': racerelations,
        'appearance': appearance,
        'history': history,
        'governmentType': governmentType,
        'economicStyle': economicStyle,
        'techSignature': techSignature,
        'keyEvents': keyEvents,
        'notableHeroes': notableHeroes.map((h) => h.toJson()).toList(),
        'loreHooks': loreHooks,
        'notableLocations': notableLocations,
      };

  factory Faction.fromJson(Map<String, dynamic> json) => Faction(
        factionClass: FactionClass.values
            .firstWhere((e) => e.name == json['factionClass']),
        name: json['name'] as String,
        banner: json['banner'] as String? ?? '',
        background: json['background'] as String,
        philosophy: json['philosophy'] as String,
        motto: json['motto'] as String,
        motivations: json['motivations'] as String,
        racerelations: json['racerelations'] as String,
        appearance: json['appearance'] as String,
        history: json['history'] as String? ?? '',
        governmentType: json['governmentType'] as String? ?? '',
        economicStyle: json['economicStyle'] as String? ?? '',
        techSignature: json['techSignature'] as String? ?? '',
        keyEvents: List<String>.from(json['keyEvents'] ?? []),
        notableHeroes: (json['notableHeroes'] as List? ?? [])
            .map((h) => Hero.fromJson(h as Map<String, dynamic>))
            .toList(),
        loreHooks: List<String>.from(json['loreHooks'] ?? []),
        notableLocations:
            Map<String, String>.from(json['notableLocations'] ?? {}),
      );

  static List<Faction> allFactions() => [
        _duranHegemony,
        _vinariCollective,
        _independentTraders,
      ];

  static Faction forClass(FactionClass fc) =>
      allFactions().firstWhere((f) => f.factionClass == fc);

  // Faction Data
  static const Faction _duranHegemony = Faction(
    factionClass: FactionClass.duran,
    name: 'The Duran Hegemony',
    banner: 'assets/images/factions/duran_banner.svg',
    background:
        'The Duran Hegemony is a militaristic empire ruled by the insectoid Duran, a species of chitinous, multi-limbed warriors from the volcanic world of Kravos. Their star systems are harsh, with molten landscapes and toxic atmospheres, forging a culture of conquest and dominance. The Hegemony spans dozens of sectors, its fleets patrolling borders like the Kravos Rend, a massive warship that enforces Duran law. Their ships, such as the Vorath Dreadnought or Sylvaris Marauder, are built for war, with heavy armor and devastating weapons.<br>The Duran view weaker species as resources to exploit. They colonize planets like Voryn, strip-mining them for minerals and organics, and enslave populations to fuel their war machine. Their society is rigid, with a caste system led by warlords and overseen by the Hegemony\'s central command. Despite their brutality, the Duran are highly organized, with efficient logistics and a culture that reveres strength.',
    philosophy:
        'The Duran believe in "Strength Through Dominion." They see the galaxy as a hierarchy where only the strong deserve to rule. Weakness is punished, and submission is the only path for lesser species to survive.',
    motto: 'Conquer or Be Conquered.',
    motivations:
        'The Duran Hegemony is driven by expansion and control. They seek to dominate the galaxy, subjugate rivals, and secure resources for their war machine. Their key goals include: Expansion, Subjugation, Resource Control',
    racerelations:
        'The Duran view the Vinari as elusive pests, their cloaking tech and nomadic ways frustrating Duran conquest. They consider the Vinari\'s reliance on stealth dishonorable and see their fragile ships (like the Sylvara Wisp) as easy prey. Skirmishes are common over resource-rich systems, with the Duran attempting to seize Vinari-explored planets like Elara. However, the Vinari\'s agility and cloaking tech often frustrate Duran assaults, leading to a grudging respect for their evasiveness. Diplomacy is rare, as the Duran demand submission, which the Vinari reject.',
    appearance:
        'Scaly, insectoid warriors with glowing red eyes, clad in battle-armor',
    history:
        'Born on the brutal volcanic world of Kravos, the Duran rose to power through centuries of brutal internal conflict before turning their gaze outward. The Great Expansion began in Cycle 347 when High Warlord Varak Thul united the clans.',
    governmentType: 'Centralized Militarist Caste Hierarchy led by Warlords',
    economicStyle: 'Command Economy based on conquest and resource extraction',
    techSignature:
        'Heavy brute-force armor, plasma weaponry, volcanic metallurgy, nanite self-repair systems',
    keyEvents: [
      'Cycle 347: The Kravos Expansion begins',
      'Cycle 412-419: The Veil War against the Vinari',
      'Cycle 433: The Fracture Accords brokered by Traders',
      'Recent: The Voryn Scourge and renewed hostilities',
    ],
    notableHeroes: [
      Hero(
        name: 'High Warlord Varak Thul',
        title: 'Supreme Commander',
        shortBio: 'Massive battle-scarred warrior who leads from the front.',
        notableAchievement:
            'Personally led the conquest of 12 sectors and commands the flagship Kravos Rend.',
      ),
      Hero(
        name: 'Matriarch Krixa',
        title: 'Logistics Overlord',
        shortBio:
            'Ruthless organizer who turned Kravos into a self-sustaining war machine.',
        notableAchievement:
            'Masterminded the biomass-to-resource conversion programs.',
      ),
    ],
    loreHooks: [
      'Rumors of a secret "Project Dominion" attempting to fuse Vinari bio-tech with Duran armor',
      'A rebellious lower caste on Kravos may be open to outside contact',
      'Duran are hunting a lost ancient weapon on Voryn',
    ],
    notableLocations: {
      'Kravos': 'Volcanic forge world and capital',
      'Voryn': 'Currently contested resource world',
      'Kravos Rend': 'Both a ship class and the Hegemony flagship',
    },
  );

  static const Faction _vinariCollective = Faction(
    factionClass: FactionClass.vinari,
    name: 'The Vinari Collective',
    banner: 'assets/images/factions/vinari_banner.svg',
    background:
        'The Vinari Collective is a decentralized alliance of bio-luminescent, semi-corporeal beings native to Celestara, a lush, H2O-rich planet orbiting a G-Type star. Evolving in a nebula-shrouded system, the Vinari developed a symbiotic biology, blending organic tissues with energy-based structures, allowing them to manipulate electromagnetic fields. Their appearance is fluid, resembling glowing, humanoid shapes with tendril-like appendages, which inspired their sleek, organic ships (e.g., Celestryn Spire). Their society is nomadic, organized into migratory fleets that explore the galaxy, seeking knowledge and harmony with cosmic forces.<br>Vinari culture is deeply spiritual, viewing the universe as a living entity they must commune with. Their technology integrates bio-energy, with ships grown from crystalline seeds rather than built. Their settlements are temporary, often on habitable worlds like Elara or Sylvara, where they leave behind glowing monuments. They lack a central government, instead making decisions through telepathic consensus, which outsiders find chaotic but effective. Their history is peaceful but marked by evasion of threats, including early Duran invasions.',
    philosophy:
        'The Vinari embrace "Flow with the Cosmos," believing all life is interconnected and guided by universal energies. They value exploration, adaptability, and preservation, avoiding conflict unless necessary. Knowledge is sacred, and they seek to understand stars, planets, and even hazards like Black Holes to align with the galaxy\'s rhythm.',
    motto: 'Drift in Light, Bind in Truth.',
    motivations:
        'The Vinari Collective is driven by exploration and enlightenment. They aim to map the galaxy\'s mysteries and coexist with its diversity. Their key goals include: Discovery, Preservation, Connection',
    racerelations:
        'The Vinari see the Duran as destructive, their conquests disrupting the galaxy\'s harmony. They avoid direct conflict, using stealth and mobility (e.g., Elythar Caravan) to evade Duran fleets. When forced to fight, Vinari ships like Auralis Thorn outmaneuver rather than overpower. They\'ve tried diplomacy, offering knowledge in exchange for peace, but the Duran\'s demands for control stall talks. The Vinari protect planets like Voryn from Duran colonization, leading to tense standoffs.<br>The Vinari have a warm, cooperative relationship with the Traders, valuing their role as galactic connectors. They trade exotic artifacts and star charts for Terran tech or supplies, often via Elythar Caravans docking at Trader hubs. The Vinari\'s openness makes them ideal partners, though they warn Traders against aiding Duran aggression. Occasional tensions arise when Traders exploit Vinari worlds, but these are resolved through negotiation.',
    appearance:
        'Glowing, fluid forms with shifting colors, like living auroras',
    history:
        'The Vinari evolved in the nebula-shrouded system of Celestara. Their history is one of peaceful exploration occasionally interrupted by conflict with the Duran.',
    governmentType: 'Decentralized Telepathic Consensus',
    economicStyle: 'Resource Sharing & Gift Economy',
    techSignature:
        'Bio-energy integration, crystalline ship growth, harmonic field manipulation',
    keyEvents: [
      'Cycle 412-419: The Veil War - successfully repelled Duran invasion',
      'Cycle 433: Fracture Accords',
      'Recent: Increased cooperation with Traders while protecting sacred sites',
    ],
    notableHeroes: [
      Hero(
        name: 'Luminary Serath Veil',
        title: 'Star Singer',
        shortBio:
            'Ancient semi-corporeal elder who communes directly with cosmic energies.',
        notableAchievement:
            'Created the Living Nebula that ended the Veil War.',
      ),
    ],
    loreHooks: [
      'A prophecy speaks of the "Great Unraveling" coming from a black hole',
      'Some Vinari factions want to awaken dormant cosmic entities',
    ],
    notableLocations: {
      'Celestara': 'Homeworld and spiritual center',
      'Elara': 'Frequent meeting point with Traders',
    },
  );

  static const Faction _independentTraders = Faction(
    factionClass: FactionClass.trader,
    name: 'The Independent Traders Guild',
    banner: 'assets/images/factions/traders_banner.svg',
    background:
        'The Independent Traders Guild is a loose coalition of humanoid Terrans, descended from Earth-like colonies scattered across G-Type and K-Type star systems, such as Elara (N2-O2 atmosphere). Originating from a failed federation, the Terrans turned to commerce for survival, forming the Guild to navigate a galaxy dominated by powers like the Duran and Vinari. Their ships are pragmatic, retrofitted for trade and survival, ranging from small shuttles to massive freighters. Guild hubs are bustling space stations or neutral planets like Vionis, where diverse cultures mingle.<br>Terran society is individualistic, driven by profit and opportunity. The Guild lacks a unified government, operating through merchant councils that prioritize trade routes over ideology. Their technology is eclectic, blending salvaged alien tech with human ingenuity, evident in their versatile but unpolished ships. Their history is one of adaptation, thriving in the shadows of larger empires by exploiting their conflicts and needs.',
    philosophy:
        'The Traders follow "Profit Through Opportunity," believing wealth and survival come from exploiting every situation. They\'re neutral, aligning with whoever pays best, but maintain a code of mutual benefit to avoid collapse. They value freedom and distrust centralized power, seeing it as a threat to their independence.',
    motto: 'Trade Turns the Stars.',
    motivations:
        'The Traders are driven by wealth and survival. They aim to dominate galactic trade while avoiding subjugation. Their goals include: Trade Dominance, Neutrality, Expansion',
    racerelations:
        'The Traders maintain a cautious, transactional relationship with the Duran, supplying raw materials or tech in exchange for safe passage. The Duran\'s extortion and blockades (e.g., near Kravos Rend) strain ties, forcing Traders to smuggle or bribe. Some Traders secretly arm Vinari allies, risking Duran wrath, but most stay neutral to preserve profits.<br>The Traders admire the Vinari\'s openness, forming strong trade partnerships. They exchange Terran goods for Vinari knowledge or artifacts, often at planets like Sylvara. The Vinari\'s idealism sometimes frustrates the profit-driven Traders, but their mutual respect prevents major conflicts. Traders act as intermediaries, relaying Vinari discoveries to other systems.',
    appearance: 'Diverse Terrans in practical jumpsuits or merchant finery',
    history:
        'Born from the ashes of a failed Terran federation, the Guild learned that profit is the best survival strategy in a dangerous galaxy.',
    governmentType: 'Loose Merchant Council / Corporate Oligarchy',
    economicStyle: 'Free Market Capitalism with Guild Regulations',
    techSignature:
        'Hybrid salvaged technology, modular retrofitting, pragmatic engineering',
    keyEvents: [
      'Cycle 433: Brokered the Fracture Accords',
      'The Elara Run: Famous smuggling operation that saved thousands',
    ],
    notableHeroes: [
      Hero(
        name: 'Tradebaron Silas Kane',
        title: 'Master Merchant',
        shortBio:
            'Charismatic captain of the Tradebaron Citadel "Void Dividend".',
        notableAchievement:
            'Executed the legendary Nebula Gambit against Duran forces.',
      ),
    ],
    loreHooks: [
      'A secret "Ghost Fleet" of captured alien ships is being built',
      'Internal power struggle between idealistic and ruthless merchant houses',
    ],
    notableLocations: {
      'Vionis': 'Main neutral trade hub',
      'Nexara': 'Key defensive outpost',
    },
  );
}
