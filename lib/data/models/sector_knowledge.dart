import 'dart:convert';

/// Represents everything the player knows about a sector.
///
/// This is the foundation of the Navigation Computer.
/// Today only a few fields are used, but this model is
/// intentionally designed to grow without requiring save-game
/// changes later.
class SectorKnowledge {
  final int sectorId;

  /// Player has seen this sector on the map.
  bool discovered;

  /// Player has actually entered this sector.
  bool visited;

  /// Number of times player has entered.
  int visitCount;

  /// Player has marked this sector.
  bool bookmarked;

  /// Optional player notes.
  String notes;

  /// When first discovered.
  DateTime? firstDiscovered;

  /// Last time entered.
  DateTime? lastVisited;

  SectorKnowledge({
    required this.sectorId,
    this.discovered = false,
    this.visited = false,
    this.visitCount = 0,
    this.bookmarked = false,
    this.notes = '',
    this.firstDiscovered,
    this.lastVisited,
  });

  factory SectorKnowledge.unknown(int id) {
    return SectorKnowledge(
      sectorId: id,
    );
  }

  void discover() {
    if (!discovered) {
      discovered = true;
      firstDiscovered ??= DateTime.now();
    }
  }

  void visit() {
    discover();

    visited = true;
    visitCount++;
    lastVisited = DateTime.now();
  }

  Map<String, dynamic> toJson() {
    return {
      'sectorId': sectorId,
      'discovered': discovered,
      'visited': visited,
      'visitCount': visitCount,
      'bookmarked': bookmarked,
      'notes': notes,
      'firstDiscovered': firstDiscovered?.toIso8601String(),
      'lastVisited': lastVisited?.toIso8601String(),
    };
  }

  factory SectorKnowledge.fromJson(Map<String, dynamic> json) {
    return SectorKnowledge(
      sectorId: json['sectorId'],
      discovered: json['discovered'] ?? false,
      visited: json['visited'] ?? false,
      visitCount: json['visitCount'] ?? 0,
      bookmarked: json['bookmarked'] ?? false,
      notes: json['notes'] ?? '',
      firstDiscovered: json['firstDiscovered'] != null
          ? DateTime.parse(json['firstDiscovered'])
          : null,
      lastVisited: json['lastVisited'] != null
          ? DateTime.parse(json['lastVisited'])
          : null,
    );
  }

  String encode() => jsonEncode(toJson());

  static SectorKnowledge decode(String json) =>
      SectorKnowledge.fromJson(jsonDecode(json));
}
