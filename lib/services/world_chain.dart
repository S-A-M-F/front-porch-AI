// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure Location-chain resolution (docs/design/locations-within-worlds.md §3).
// No DB, no Flutter: the repository feeds worlds in, gets an ordered chain,
// a climate author, or a save verdict back. The engine walks any chain; the
// two-level depth cap is editor policy, not a law of this file.

import 'package:front_porch_ai/models/world.dart';

/// What saving a location whose parent cannot be found reports.
const kWorldParentUnknown = 'That parent place no longer exists.';

/// What saving a place inside one of its own rooms reports.
const kWorldParentCycle = 'A place cannot live inside one of its own rooms.';

/// Ancestor chain leaf-first: `[S, parent(S), …, root]`.
///
/// Stops at a null parent, a lookup miss (a parent row deleted behind this
/// one, e.g. while a re-root is still in flight), and a repeat visit — a
/// ring left by a direct DB edit must never spin the walker. Deduped by id,
/// so the result is finite on any input.
List<World> worldChain(World leaf, World? Function(String id) lookup) {
  final chain = <World>[leaf];
  final seen = <String>{leaf.id};
  var cursor = leaf.parentWorldId;
  while (cursor != null && cursor.isNotEmpty && seen.add(cursor)) {
    final next = lookup(cursor);
    if (next == null) break;
    chain.add(next);
    cursor = next.parentWorldId;
  }
  return chain;
}

/// The first climate-enabled world in a [worldChain] — the place whose
/// biome, weather and traits the leaf reads. Null when the whole chain is
/// lore-only (a climate-off root as Setting ⇒ weather off, as today).
World? climateAuthorOf(List<World> chain) {
  for (final w in chain) {
    if (w.climateEnabled) return w;
  }
  return null;
}

/// Why saving [worldId] with parent [parentId] must be refused, or null
/// when it is legal. [parents] is every known id → parent id, straight from
/// the database — the cache can still be loading.
///
/// Unknown parents are refused: silently dropping one would quietly detach
/// somebody's rooms. A cycle is refused: a parent may not be the world
/// itself or any descendant of it. A ring further upstream that does not
/// pass through [worldId] is not this save's sin and does not block it.
String? parentRejection({
  required String worldId,
  required String? parentId,
  required Map<String, String?> parents,
}) {
  if (parentId == null || parentId.isEmpty) return null;
  if (!parents.containsKey(parentId)) return kWorldParentUnknown;
  if (parentId == worldId) return kWorldParentCycle;
  var cursor = parents[parentId];
  final visited = <String>{parentId};
  while (cursor != null && cursor.isNotEmpty && visited.add(cursor)) {
    if (cursor == worldId) return kWorldParentCycle;
    cursor = parents[cursor];
  }
  return null;
}
