// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure row plan for the Worlds library with locations (slice 3,
// docs/design/locations-within-worlds.md §5): roots with places render as
// a wide header card plus their children indented beneath; everything else
// keeps today's flat grid. No Flutter here — the page consumes
// [planWorldLibrary] and renders; the widget test pins the plan.

import 'package:front_porch_ai/models/world.dart';

enum WorldLibraryFilter { all, rootsOnly, modelMade }

/// A root that has places inside it, rendered as its own section.
class WorldLibrarySection {
  final World root;
  final List<World> places;

  const WorldLibrarySection({required this.root, required this.places});
}

class WorldLibraryPlan {
  /// Sections: roots with children, in repo order. Children are ordered by
  /// name — the author picks places up by reading them, not by sort keys.
  final List<WorldLibrarySection> sections;

  /// Flat grid cards: childless roots, and — only when [WorldLibraryFilter
  /// .modelMade] is active — model-made worlds at any depth.
  final List<World> flat;

  /// Total places inside any root (drives the "N places" chips and the
  /// section count the empty-state copy quotes).
  final int locationCount;

  const WorldLibraryPlan({
    required this.sections,
    required this.flat,
    required this.locationCount,
  });

  bool get isFlatLibrary => sections.isEmpty;
}

/// A world is a location iff its parent id is set AND that parent resolves
/// in [all]. A dangling parent (deleted behind the re-root, hand-edited
/// library) must still be VISIBLE, so it counts as flat, not as a child.
bool _isLocation(World w, Map<String, World> byId) {
  final p = w.parentWorldId;
  return p != null && p.isNotEmpty && byId.containsKey(p);
}

/// Pure planning step. [worlds] arrives in library order (repo.placeWorlds);
/// a collapsed root keeps its section but reports its children hidden —
/// expansion is the caller's state, echoed back verbatim here.
WorldLibraryPlan planWorldLibrary({
  required List<World> worlds,
  required WorldLibraryFilter filter,
}) {
  final byId = {for (final w in worlds) w.id: w};
  final locations = worlds.where((w) => _isLocation(w, byId)).toList();
  final byParent = <String, List<World>>{};
  for (final w in locations) {
    byParent.putIfAbsent(w.parentWorldId!, () => []).add(w);
  }
  for (final list in byParent.values) {
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  if (filter == WorldLibraryFilter.modelMade) {
    return WorldLibraryPlan(
      sections: const [],
      flat: worlds.where((w) => w.isModelMade).toList(),
      locationCount: locations.length,
    );
  }

  final sections = <WorldLibrarySection>[];
  final flat = <World>[];
  for (final w in worlds) {
    if (_isLocation(w, byId)) continue; // children render inside sections
    final children = filter == WorldLibraryFilter.rootsOnly
        ? const <World>[]
        : (byParent[w.id] ?? const []);
    // The root itself always renders through its section when it has
    // children — never also in the flat grid (no duplicate cards).
    if (byParent.containsKey(w.id)) {
      sections.add(WorldLibrarySection(root: w, places: children));
    } else {
      flat.add(w);
    }
  }
  return WorldLibraryPlan(
    sections: sections,
    flat: flat,
    locationCount: locations.length,
  );
}

/// Children count for a root card's "N places" chip.
int placesUnder(String rootId, List<World> worlds) {
  final byId = {for (final w in worlds) w.id: w};
  // Direct children only for the chip — "2 places inside" on the card,
  // per the mockup, not the whole subtree.
  return worlds
      .where((w) => w.parentWorldId != null && byId[w.parentWorldId] != null)
      .where((w) => byId[w.parentWorldId]!.id == rootId)
      .length;
}
