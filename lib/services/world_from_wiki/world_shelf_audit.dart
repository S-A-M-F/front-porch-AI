// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The shelf review: does the scout's shelf read as a WORLD (era, places,
// factions, events, powers, then a few people) or as a cast list? Plain
// rules the runner checks before it asks the model to revise once.

import 'world_craft_mechanics.dart';
import 'world_from_wiki_depth.dart';
import 'world_places.dart';

/// A shelf of twelve or more cards needs at least this many places or
/// factions — the settings and the powers that be.
const int kWorldShelfBackboneMin = 4;

/// Shelves under this size are too small to judge by share.
const int kWorldShelfJudgeFrom = 12;

class WorldShelfAudit {
  const WorldShelfAudit(this.problems);

  final List<String> problems;

  bool get ok => problems.isEmpty;
}

/// The problems a shelf has as a world, in the words the revise call and
/// the status line use. Empty when it passes.
WorldShelfAudit auditWorldShelf(
  List<WorldProposedCard> cards, {
  required List<WorldProposedPlace> places,
  required bool tagged,
}) {
  final problems = <String>[];
  // A shelf under twelve cards is not a world yet, and not worth a second
  // model call; the author signs what is there.
  if (cards.length < kWorldShelfJudgeFrom) return WorldShelfAudit(problems);
  final eras = cards.where((c) => c.role == WorldCraftRole.era).length;
  if (eras == 0) problems.add("no era card for the premise's time");
  if (eras > 1) problems.add('$eras era cards; a world has one');
  final kinded = cards.where((c) => c.kind.isNotEmpty).length;
  if (kinded * 2 >= cards.length) {
    // People are not rationed: the reviewer asks for members and the fill
    // loop gives every place its residents (the live run showed the gate
    // rejecting the very revise the reviewer had asked for). What the
    // shelf must have is its backbone.
    final backbone = cards
        .where((c) => c.kind == 'place' || c.kind == 'faction')
        .length;
    if (backbone < kWorldShelfBackboneMin) {
      problems.add(
        'only $backbone place or faction cards; a world needs its settings '
        'and the powers that be',
      );
    }
    if (tagged && places.isEmpty && cards.any((c) => c.kind == 'place')) {
      problems.add(
        'the index carries tags and the shelf has place cards, but no '
        'places were named in the places list',
      );
    }
  } else {
    problems.add('cards carry no kind; set kind on every card');
  }
  return WorldShelfAudit(problems);
}

/// Tag words that say a page is a place.
const List<String> kWorldPlaceTagWords = [
  'location',
  'place',
  'city',
  'town',
  'realm',
  'world',
  'region',
  'nation',
  'district',
  'fortress',
  'palace',
  'castle',
  'kingdom',
  'village',
  'island',
];

/// Tag words that say a page is a person.
const List<String> kWorldPersonTagWords = ['character', 'people'];

/// Candidates a gap carries to the model at most.
const int kWorldGapCandidateMax = 12;

/// Ranked titles the must-have-place check reads: a place that deep in
/// the link ranking is a place the world needs.
const int kWorldGapPlaceRank = 60;

/// A hole the coverage audit found: the kind of hole, what it is about,
/// the catalog titles that could fill it, and the place those cards
/// belong to (null: the model decides).
class WorldCoverageGap {
  const WorldCoverageGap({
    required this.kind,
    required this.name,
    required this.candidates,
    this.place,
  });

  /// 'place' (a top page tagged as a place that is not a place),
  /// 'faction' (a faction whose members the index lists), 'thinPlace' (a
  /// place under the per-place minimum) or 'people' (top characters
  /// missing).
  final String kind;
  final String name;
  final List<String> candidates;
  final String? place;

  @override
  String toString() => '$kind:$name (${candidates.length})';
}

bool _tagsSay(List<String> tags, List<String> words) =>
    tags.any((t) => words.any((w) => t.toLowerCase().contains(w)));

bool _tagsName(List<String> tags, String name) {
  final n = name.trim().toLowerCase();
  return tags.any((t) => t.trim().toLowerCase() == n);
}

/// The gaps between [cards] and what the catalog shows, in the order the
/// fill loop works them. [titles] are the catalog in rank order and [tags]
/// their categories. A title is offered to one gap only.
List<WorldCoverageGap> auditWorldCoverage({
  required List<WorldProposedCard> cards,
  required List<WorldProposedPlace> places,
  required List<String> titles,
  required Map<String, List<String>> tags,
  required WorldWikiDepth depth,
}) {
  final onShelf = {
    for (final c in cards) c.name.trim().toLowerCase(),
    for (final c in cards)
      for (final s in c.sourceTitles) s.trim().toLowerCase(),
    for (final p in places) p.key,
  };
  final taken = <String>{};
  final gaps = <WorldCoverageGap>[];
  List<String> pick(Iterable<String> from, {int max = kWorldGapCandidateMax}) {
    final out = <String>[];
    for (final t in from) {
      final k = t.toLowerCase();
      if (onShelf.contains(k) || taken.contains(k)) continue;
      out.add(t);
      taken.add(k);
      if (out.length >= max) break;
    }
    return out;
  }

  // Must-have places: top-ranked pages the wiki tags as places.
  final topPlaces = pick(
    titles
        .take(kWorldGapPlaceRank)
        .where((t) => _tagsSay(tags[t] ?? const [], kWorldPlaceTagWords)),
    max: 8,
  );
  if (topPlaces.isNotEmpty) {
    gaps.add(
      WorldCoverageGap(kind: 'place', name: 'places', candidates: topPlaces),
    );
  }

  // Factions whose members the index lists: a card each only at a depth
  // that wants them; otherwise the faction's own card carries the roster.
  for (final f in cards.where(
    (c) => c.kind == 'faction' && depth.memberCards,
  )) {
    final members = pick(
      titles.where(
        (t) =>
            _tagsName(tags[t] ?? const [], f.name) &&
            _tagsSay(tags[t] ?? const [], kWorldPersonTagWords),
      ),
    );
    if (members.length >= 2) {
      gaps.add(
        WorldCoverageGap(
          kind: 'faction',
          name: f.name,
          candidates: members,
          place: f.place.isEmpty ? null : f.place,
        ),
      );
    }
  }

  // Places under the minimum, with pages the wiki files under them.
  for (final p in places) {
    final inside = cards
        .where((c) => c.place.trim().toLowerCase() == p.key)
        .length;
    if (inside >= depth.perPlaceMin) continue;
    final residents = pick(
      titles.where((t) => _tagsName(tags[t] ?? const [], p.name)),
    );
    if (residents.isNotEmpty) {
      gaps.add(
        WorldCoverageGap(
          kind: 'thinPlace',
          name: p.name,
          candidates: residents,
          place: p.name,
        ),
      );
    }
  }

  // The wiki's most-linked characters.
  final people = pick(
    titles
        .take(depth.topPeople * 2)
        .where((t) => _tagsSay(tags[t] ?? const [], kWorldPersonTagWords)),
    max: depth.topPeople,
  );
  if (people.isNotEmpty) {
    gaps.add(
      WorldCoverageGap(kind: 'people', name: 'people', candidates: people),
    );
  }
  return gaps;
}
