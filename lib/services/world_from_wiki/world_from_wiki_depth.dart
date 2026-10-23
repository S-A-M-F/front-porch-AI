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
      'About 100 cards. Reviewers check the shelf and every entry and '
          'send weak ones back.',
    WorldWikiDepth.deep =>
      'About 200 cards. Every place gets its people; slow on a local model.',
  };

  /// The most cards the shelf holds once the fill loop is done.
  int get cardTarget => switch (this) {
    WorldWikiDepth.quick => 40,
    WorldWikiDepth.full => 100,
    WorldWikiDepth.deep => 200,
  };

  /// What the first scout call asks for; the fill loop adds the rest.
  (int, int) get scoutRange => switch (this) {
    WorldWikiDepth.quick => (30, 40),
    WorldWikiDepth.full => (40, 60),
    WorldWikiDepth.deep => (50, 80),
  };

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
    WorldWikiDepth.full => 3,
    WorldWikiDepth.deep => 3,
  };

  /// Whether a second model call reviews the shelf and the entries.
  bool get reviews => this != WorldWikiDepth.quick;
}
