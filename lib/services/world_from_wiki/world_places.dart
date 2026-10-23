// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 8 (design §9): the place half of World-from-Wiki. The scout may
// now name the places its tags imply (Neokosmos keeps nations in tags,
// never pages); every card then belongs to one place or the root, the
// write pass runs per place, and the save creates a root World with
// children instead of one flat world. An untagged wiki yields an empty
// [WorldScoutPlan.places] and the pipeline behaves EXACTLY as before —
// that path is a pinned test, not an assumption.

import 'package:front_porch_ai/models/models.dart';

import 'world_craft_mechanics.dart';

/// Deepest place nesting the wizard will build (root's children are
/// depth 1; the World ladder caps the same way elsewhere).
const int kWorldPlaceMaxDepth = 3;

/// One scout-named place, from tags/categories evidence.
class WorldProposedPlace {
  const WorldProposedPlace({
    required this.name,
    this.keys = const [],
    this.sourceTitles = const [],
    this.parentName = '',
    this.climateHint = '',
  });

  final String name;
  final List<String> keys;

  /// Wiki pages to read when writing this place's profile.
  final List<String> sourceTitles;

  /// Name of the containing place, empty for a direct child of the root.
  final String parentName;

  /// The scout's one-line reading of the climate, e.g. "mist-bound
  /// winter forest". Evidence for the profile call, never a biome id —
  /// a local model guessing 'tundra' from a label is how wrong weather
  /// ships.
  final String climateHint;

  String get key => name.trim().toLowerCase();

  Map<String, dynamic> toJson() => {
    'name': name,
    if (keys.isNotEmpty) 'keys': keys,
    if (sourceTitles.isNotEmpty) 'sourceTitles': sourceTitles,
    if (parentName.isNotEmpty) 'parentName': parentName,
    if (climateHint.isNotEmpty) 'climateHint': climateHint,
  };

  static WorldProposedPlace? tryParse(Map<String, dynamic> json) {
    final name = json['name']?.toString().trim() ?? '';
    if (name.isEmpty) return null;
    final sources = _strings(
      json['sourceTitles'] ?? json['source_titles'],
      max: 4,
    );
    return WorldProposedPlace(
      name: name,
      keys: _strings(json['keys'], max: 8),
      sourceTitles: sources,
      parentName:
          (json['parentName'] ?? json['parent_place'] ?? json['parent'])
              ?.toString()
              .trim() ??
          '',
      climateHint:
          (json['climateHint'] ?? json['climate_hint'])?.toString().trim() ??
          '',
    );
  }

  static List<String> _strings(dynamic raw, {int max = 8}) {
    if (raw is List) {
      return [
        for (final e in raw.take(max))
          if (e?.toString().trim() case final s? when s.isNotEmpty) s,
      ];
    }
    if (raw is! String) return const [];
    return [
      for (final part in raw.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    ].take(max).toList();
  }
}

/// Places resolved into a build order: every entry appears AFTER its
/// parent, cycles collapse to root-level, and over-deep branches are
/// raised to the cap instead of refused (a wiki that nests five deep
/// still gets its places, just flatter).
List<WorldProposedPlace> resolvePlaceOrder(List<WorldProposedPlace> places) {
  final byKey = <String, WorldProposedPlace>{};
  for (final p in places) {
    if (p.key.isNotEmpty) byKey.putIfAbsent(p.key, () => p);
  }
  WorldProposedPlace resolvedParent(WorldProposedPlace p) {
    var parent = p.parentName.trim().toLowerCase();
    final guard = <String>{p.key};
    while (parent.isNotEmpty && byKey.containsKey(parent)) {
      if (guard.contains(parent)) {
        // Cycle: the ancestor claim dissolves; the place rides at root.
        return WorldProposedPlace(
          name: p.name,
          keys: p.keys,
          sourceTitles: p.sourceTitles,
          climateHint: p.climateHint,
        );
      }
      guard.add(parent);
      parent = byKey[parent]!.parentName.trim().toLowerCase();
    }
    if (parent.isEmpty || !byKey.containsKey(parent)) return p;
    return p;
  }

  int depthOf(WorldProposedPlace p, {Set<String>? seen}) {
    final visited = seen ?? <String>{p.key};
    final pk = p.parentName.trim().toLowerCase();
    if (pk.isEmpty || !byKey.containsKey(pk) || !visited.add(pk)) return 1;
    return 1 + depthOf(byKey[pk]!, seen: visited);
  }

  final ordered = <WorldProposedPlace>[];
  final placed = <String>{};

  WorldProposedPlace raiseToCap(WorldProposedPlace p) {
    var out = p;
    while (depthOf(out) > kWorldPlaceMaxDepth) {
      final pk = out.parentName.trim().toLowerCase();
      final grand = pk.isEmpty ? '' : (byKey[pk]?.parentName.trim() ?? '');
      out = WorldProposedPlace(
        name: out.name,
        keys: out.keys,
        sourceTitles: out.sourceTitles,
        parentName: grand,
        climateHint: out.climateHint,
      );
    }
    return out;
  }

  var remaining = [for (final p in places) raiseToCap(resolvedParent(p))];
  while (remaining.isNotEmpty) {
    final ready = [
      for (final p in remaining)
        if (p.parentName.trim().isEmpty ||
            placed.contains(p.parentName.trim().toLowerCase()))
          p,
    ];
    if (ready.isEmpty) {
      // Defensive: anything still waiting (should be unreachable after
      // the cycle pass) rides at root so no place is silently dropped.
      for (final p in remaining) {
        ordered.add(
          WorldProposedPlace(
            name: p.name,
            keys: p.keys,
            sourceTitles: p.sourceTitles,
            climateHint: p.climateHint,
          ),
        );
        placed.add(p.key);
      }
      break;
    }
    for (final p in ready) {
      ordered.add(p);
      placed.add(p.key);
    }
    remaining = [
      for (final p in remaining)
        if (!placed.contains(p.key)) p,
    ];
  }
  return ordered;
}

/// Cards grouped by the place they name; unknown or empty places fall to
/// the root bucket (key ''). Grouping is TOTAL — a card never vanishes
/// because the scout mis-labelled it.
Map<String, List<WorldProposedCard>> groupCardsByPlace(
  List<WorldProposedCard> cards,
  List<WorldProposedPlace> places,
) {
  final known = <String>{for (final p in places) p.key};
  final out = <String, List<WorldProposedCard>>{'': []};
  for (final p in places) {
    out.putIfAbsent(p.key, () => []);
  }
  for (final card in cards) {
    final pk = card.place.trim().toLowerCase();
    final bucket = pk.isNotEmpty && known.contains(pk) ? pk : '';
    out[bucket]!.add(card);
  }
  return out;
}

/// A place's own hub card belongs in the book AROUND it — its parent's,
/// or the root's for a top-level place — so a scene anywhere in the world
/// can mention the place and have its card fire. Inside its own book the
/// card would only ever fire while the scene is already there (the first
/// live Bleach run put "Seireitei" inside Seireitei; from Karakura nothing
/// answered to the name).
List<WorldProposedCard> liftPlaceHubCards(
  List<WorldProposedCard> cards,
  List<WorldProposedPlace> places,
) {
  if (places.isEmpty) return cards;
  final byKey = {for (final p in places) p.key: p};
  return [
    for (final c in cards)
      if (byKey[c.name.trim().toLowerCase()] case final place?
          when c.place.trim().toLowerCase() == place.key)
        WorldProposedCard(
          name: c.name,
          keys: c.keys,
          role: c.role,
          sourceTitles: c.sourceTitles,
          group: c.group,
          kind: c.kind,
          place: place.parentName,
        )
      else
        c,
  ];
}

/// One place's written product: what the review/preview shows and what
/// the save turns into a World.
class WorldPlaceWrite {
  const WorldPlaceWrite({
    required this.name,
    required this.parentName,
    required this.description,
    required this.entries,
    this.biome,
  });

  final String name;
  final String parentName;
  final String description;
  final List<LorebookEntry> entries;

  /// Authored biome for THIS place, null = inherit (or off).
  final Map<String, dynamic>? biome;

  bool get hasClimate => biome != null && biome!.isNotEmpty;

  Map<String, dynamic> toJson() => {
    'name': name,
    'parentName': parentName,
    'description': description,
    'entries': entries,
    if (biome != null) 'biome': biome,
  };
}

/// The whole write's shape: a root plus ordered children. With no
/// places the root carries every entry and the children list is empty —
/// the flat world, exactly today's product.
class WorldWriteTree {
  const WorldWriteTree({required this.root, required this.places});

  final WorldPlaceWrite root;
  final List<WorldPlaceWrite> places;

  bool get isFlat => places.isEmpty;
}
