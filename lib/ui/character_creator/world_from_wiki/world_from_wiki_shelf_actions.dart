// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Shelf step's helpers on the wizard state: taking the scout's shelf
// with every card signed, the kind filter, the counts behind the chips,
// "Only the backbone" (era, places, factions, events) as a trim, and
// "Sign all here" / "Unsign all here" for one place. The Review step at
// the end is where a written card gets fixed, so the shelf is a trim, not
// a chore (the maintainer's ruling, 2026-10-24).

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

/// The filter chips in order: label, and the kinds each gathers.
const List<({String label, List<String> kinds})> kWorldShelfFilters = [
  (label: 'Places', kinds: ['place']),
  (label: 'Factions', kinds: ['faction']),
  (label: 'Events', kinds: ['event']),
  (label: 'Powers & terms', kinds: ['concept', 'race', 'item']),
  (label: 'People', kinds: ['person']),
];

/// The kinds that make a world's backbone: what "Only the backbone" keeps.
const Set<String> kWorldBackboneKinds = {'place', 'faction', 'event'};

extension WorldFromWikiShelfActions on WorldFromWikiState {
  /// Takes the scout's [result] as the shelf: the catalog counts, the
  /// cards, the places, the reviewer's word, every card signed, and the
  /// places with a weather hint on their own sky.
  void takeShelf(WorldScoutResult result) {
    catalogTitleCount = result.catalog.titles.length;
    catalogArticleCount = result.catalog.articleCount;
    catalogRanked = result.catalog.ranked;
    proposed = result.proposed;
    places = result.places;
    shelfNotes = result.auditNotes;
    shelfRevised = result.revised;
    shelfFilter = '';
    signed
      ..clear()
      ..addAll(Iterable<int>.generate(proposed.length));
    placeClimate
      ..clear()
      ..addAll([
        for (final p in places)
          if (p.climateHint.isNotEmpty) p.key,
      ]);
  }

  /// A card's kind, with the role standing in when the scout gave none.
  String kindOf(WorldProposedCard c) =>
      c.kind.isNotEmpty ? c.kind : c.role.name;

  /// How many cards each filter chip gathers.
  int countFor(List<String> kinds) =>
      proposed.where((c) => kinds.contains(kindOf(c))).length;

  /// Whether [i] shows under the current filter.
  bool passesFilter(int i) {
    if (shelfFilter.isEmpty) return true;
    final f = kWorldShelfFilters.where((x) => x.label == shelfFilter);
    if (f.isEmpty) return true;
    return f.first.kinds.contains(kindOf(proposed[i]));
  }

  void setShelfFilter(String label) {
    shelfFilter = shelfFilter == label ? '' : label;
    notify();
  }

  /// Leaves exactly the era card and every place, faction and event card
  /// signed: the short write.
  void keepBackbone() {
    signed.clear();
    for (var i = 0; i < proposed.length; i++) {
      final c = proposed[i];
      if (c.role == WorldCraftRole.era ||
          kWorldBackboneKinds.contains(kindOf(c))) {
        signed.add(i);
      }
    }
    notify();
  }

  /// Signs, or unsigns, every card that lives in [placeKey] ('' = root).
  void signAllIn(String placeKey, {required bool on}) {
    final indices = indicesByPlace[placeKey] ?? const <int>[];
    for (final i in indices) {
      if (on) {
        signed.add(i);
      } else {
        signed.remove(i);
      }
    }
    notify();
  }

  /// How many of a place's cards are signed.
  int signedIn(String placeKey) =>
      (indicesByPlace[placeKey] ?? const <int>[]).where(signed.contains).length;

  /// The one-line word on the shelf review for the banner.
  String get shelfReviewLine {
    final parts = <String>[];
    if (shelfNotes.isNotEmpty) {
      final first = shelfNotes.first;
      final short = first.contains(';') ? first.split(';').first : first;
      parts.add(
        shelfRevised
            ? 'The reviewer sent this shelf back once and passed the revise: $short.'
            : 'The reviewer noted: $short.',
      );
    } else if (proposed.isNotEmpty) {
      parts.add('The reviewer passed this shelf first time.');
    }
    if (catalogTitleCount > 0) {
      parts.add(
        '$catalogTitleCount pages read'
        '${catalogRanked ? ', the ones this wiki links to most' : ''}.',
      );
    }
    return parts.join(' ');
  }
}
