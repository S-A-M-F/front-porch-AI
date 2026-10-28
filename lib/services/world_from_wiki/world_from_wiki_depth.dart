// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// How deep the wizard digs. One pick on the Book step sets every budget
// the loops read: how many cards the scout asks for, how many rounds the
// fill loop runs, how full a place must be, how many of the wiki's
// top-linked characters must be on the shelf, and how many tries each
// review loop gets. Plain Dart.

enum WorldWikiDepth { quick, full, deep }

/// The Book step's default: reviews on, a hundred cards.
const WorldWikiDepth kWorldWikiDepthDefault = WorldWikiDepth.full;

/// The most cards one scout part is asked for. Sixty cards with thinking on
/// took Kimi K2.6 past a six-minute cutoff twice, and each time the answer
/// was thrown away; forty is what the quick runs answered in minutes.
const int kWorldScoutCardsPerPart = 40;

/// The fewest cards a part is asked for once the range is shared out.
const int kWorldScoutPartCardsMin = 10;

extension WorldWikiDepthX on WorldWikiDepth {
  static WorldWikiDepth fromIndex(int? i) => switch (i) {
    0 => WorldWikiDepth.quick,
    2 => WorldWikiDepth.deep,
    _ => WorldWikiDepth.full,
  };

  String get label => switch (this) {
    WorldWikiDepth.quick => 'Quick',
    WorldWikiDepth.full => 'Full',
    WorldWikiDepth.deep => 'Deep',
  };

  /// The Book step's one-line explanation.
  String get blurb => switch (this) {
    WorldWikiDepth.quick =>
      'About 40 cards, no review passes. Fast; the shelf may be thin.',
    WorldWikiDepth.full =>
      'About 60 cards. Factions and places name their people in their own '
          'card; the main cast gets cards. Reviewers check the shelf and '
          'every entry.',
    WorldWikiDepth.deep =>
      'About 200 cards. Every place gets its people; slow on a local model.',
  };

  /// "~60 cards", for a tile's corner.
  String get cardsLabel => '~$cardTarget cards';

  /// How long a remote provider takes, in the user's words; a local model
  /// is slower and says so elsewhere.
  String get timeHint => switch (this) {
    WorldWikiDepth.quick => 'About 10 min on a remote model',
    WorldWikiDepth.full => 'About 40 min on a remote model',
    WorldWikiDepth.deep => 'Hours; run it overnight',
  };

  /// The most cards the shelf holds once the fill loop is done.
  int get cardTarget => switch (this) {
    WorldWikiDepth.quick => 40,
    WorldWikiDepth.full => 60,
    WorldWikiDepth.deep => 200,
  };

  /// Whether a faction's members each get a card of their own. Below Deep
  /// the faction's card names them instead (the maintainer's ruling,
  /// 2026-10-23: sixty cards with rosters is less error-prone than a
  /// hundred with a page per member; the four-hour Kimi run proved it).
  bool get memberCards => this == WorldWikiDepth.deep;

  /// What the first scout call asks for; the fill loop adds the rest.
  (int, int) get scoutRange => switch (this) {
    WorldWikiDepth.quick => (30, 40),
    WorldWikiDepth.full => (30, 45),
    WorldWikiDepth.deep => (50, 80),
  };

  /// How many parts the index is asked in at least, so that no one answer
  /// runs past [kWorldScoutCardsPerPart] cards (a small index stays one).
  int get scoutParts => (scoutRange.$2 / kWorldScoutCardsPerPart).ceil();

  /// A place with fewer cards than this is a gap the fill loop works.
  int get perPlaceMin => switch (this) {
    WorldWikiDepth.quick => 2,
    WorldWikiDepth.full => 4,
    WorldWikiDepth.deep => 6,
  };

  /// How many of the wiki's most-linked characters must be on the shelf.
  int get topPeople => switch (this) {
    WorldWikiDepth.quick => 6,
    WorldWikiDepth.full => 20,
    WorldWikiDepth.deep => 40,
  };

  /// Rounds of the fill loop; zero means the scout's shelf stands.
  int get fillRounds => switch (this) {
    WorldWikiDepth.quick => 0,
    WorldWikiDepth.full => 2,
    WorldWikiDepth.deep => 3,
  };

  /// Tries per review loop (one generate plus revises).
  int get tries => switch (this) {
    WorldWikiDepth.quick => 1,
    WorldWikiDepth.full => 2,
    WorldWikiDepth.deep => 3,
  };

  /// Whether a second model call reviews the shelf and the entries.
  bool get reviews => this != WorldWikiDepth.quick;
}
