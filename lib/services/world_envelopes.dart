// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'package:front_porch_ai/models/fp_world_package.dart';
import 'package:front_porch_ai/models/models.dart' hide World;
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/services/chat/weather_biomes.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Slice 5: the envelope half of the locations feature, split out of
/// [WorldRepository] to keep both files under the 500-line ratchet and
/// because tree-shaping is its own job: which root an envelope carries,
/// which branch rides along, and how a `locations` array re-homes on
/// import. The repository stays the sole owner of persistence and the
/// save law; this class only reads the live cache and calls back through
/// the public repository surface, so there is still ONE source of truth
/// per law (design §2).
class WorldEnvelopeCodec {
  WorldEnvelopeCodec(this._repo);

  final WorldRepository _repo;

  /// Levels of nesting the importer accepts below an imported root:
  /// town > building > room. Deeper is corrupt or a hand-edited file —
  /// skipped with a log, never thrown at the caller mid-import.
  static const int kImportDepthCap = 2;

  /// Build the export envelope for [world]: always a ROOT's envelope.
  /// A root carries its whole subtree; a location carries its root with
  /// just the branch that reaches it (design §4 — siblings stay home).
  Map<String, dynamic> tree(model.World world) {
    final root = rootOf(world);
    return encodeFpWorld(
      world: root,
      biome: biomeFor(root),
      locations: root.id == world.id
          ? subtreeEnvelopes(root)
          : branchEnvelopes(root, world),
    );
  }

  /// Re-home child envelopes from a `locations` array under [parentId].
  /// Structure decides parentage, never the sender's ids — each child
  /// gets a fresh local id and keeps its envelope id as `sourceId`
  /// (the root importer's provenance law, applied per level). A broken
  /// child is skipped, never fatal: the root already imported.
  Future<void> importLocations(
    List<Map<String, dynamic>> envelopes,
    String parentId,
    int depth,
  ) async {
    if (envelopes.isEmpty) return;
    if (depth > kImportDepthCap) {
      debugPrint(
        'world import: skipped ${envelopes.length} location(s) below '
        'the depth cap ($kImportDepthCap)',
      );
      return;
    }
    const uuid = Uuid();
    for (final raw in envelopes) {
      try {
        final pkg = decodeFpWorld(raw);
        final child = pkg.world;
        child.sourceId ??= child.id.isNotEmpty ? child.id : null;
        child.id = uuid.v4();
        child.parentWorldId = parentId;
        child.name = uniqueWorldName(
          child.name,
          (n) => _repo.worlds.any((w) => w.name == n),
        );
        if (pkg.biome != null) {
          final biome = Biome.fromJson(pkg.biome!);
          child.biomeId = biome.id;
          child.biomeJson = Biome.builtInById(biome.id) != null
              ? null
              : biome.toJsonString();
        }
        await _repo.saveWorld(child);
        await importLocations(pkg.locations, child.id, depth + 1);
      } catch (e) {
        debugPrint('world import: skipped location "${raw['name']}": $e');
      }
    }
  }

  Map<String, dynamic>? biomeFor(model.World world) => world.climateEnabled
      ? Biome.resolve(
          biomeId: world.biomeId,
          biomeJson: world.biomeJson,
        ).toJson()
      : null;

  /// Walk parent ids to the root. Dangling or cyclic chains stop at the
  /// deepest resolvable place, which is then treated as the root — an
  /// export never loops, matching the planner's flat-dangling rule.
  model.World rootOf(model.World world) {
    var cur = world;
    final seen = <String>{cur.id};
    while (true) {
      final pid = cur.parentWorldId;
      if (pid == null) return cur;
      final parent = _repo.worldById(pid);
      if (parent == null || !seen.add(parent.id)) return cur;
      cur = parent;
    }
  }

  /// Full subtree as nested envelopes; the depth bound guards against
  /// corrupt parent chains, not policy — the save law caps the tree.
  List<Map<String, dynamic>> subtreeEnvelopes(
    model.World parent, {
    int depth = 1,
  }) {
    if (depth > 4) return const [];
    return [
      for (final child in _repo.placeWorlds.where(
        (w) => w.parentWorldId == parent.id,
      ))
        encodeFpWorld(
          world: child,
          biome: biomeFor(child),
          locations: subtreeEnvelopes(child, depth: depth + 1),
        ),
    ];
  }

  /// The path from [ancestor] (its root) down to [target]: each hop is an
  /// envelope carrying only the child that leads onward, until the target
  /// itself, whose subtree rides whole.
  List<Map<String, dynamic>> branchEnvelopes(
    model.World ancestor,
    model.World target,
  ) {
    final hop = childOnPath(ancestor, target);
    if (hop == null) return subtreeEnvelopes(ancestor);
    return [
      encodeFpWorld(
        world: hop,
        biome: biomeFor(hop),
        locations: hop.id == target.id
            ? subtreeEnvelopes(hop)
            : branchEnvelopes(hop, target),
      ),
    ];
  }

  /// The direct child of [parent] that is [start] or an ancestor of it.
  model.World? childOnPath(model.World parent, model.World start) {
    var cur = start;
    final seen = <String>{};
    while (true) {
      if (!seen.add(cur.id)) return null;
      final pid = cur.parentWorldId;
      if (pid == null) return null;
      final p = _repo.worldById(pid);
      if (p == null) return null;
      if (p.id == parent.id) return cur;
      cur = p;
    }
  }
}
