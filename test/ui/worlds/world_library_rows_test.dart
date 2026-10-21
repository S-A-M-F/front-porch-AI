// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Pure guards for the Worlds library planner and the parent/reachable
// resolvers (locations slice 3). No widget tree: these pin the exact
// grouping, filter and candidate rules the UI renders, so a regression in
// the plan shows here and not in a screenshot.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_library_rows.dart';

World w(
  String name, {
  String? parent,
  bool model = false,
  bool climate = true,
}) {
  final world = World(
    id: name,
    name: name,
    lorebook: Lorebook(entries: []),
    parentWorldId: parent,
    climateEnabled: climate,
  );
  if (model) world.placeTraits['madeBy'] = 'model';
  return world;
}

World? Function(String) index(List<World> all) {
  final byId = {for (final x in all) x.id: x};
  return (id) => byId[id];
}

void main() {
  group('planWorldLibrary', () {
    // A town with two places, a lone childless world, a place whose parent
    // was deleted (dangling), and a model-made place.
    final town = w('Bletchfield');
    final hall = w('Town Hall', parent: 'Bletchfield');
    final tea = w('Tea Rooms', parent: 'Bletchfield');
    final station = w('Red Dust Station');
    final ghost = w('Ghost Room', parent: 'gone');
    final shadow = w('Shadow Hall', parent: 'Bletchfield', model: true);

    final library = [town, station, hall, tea, ghost, shadow];

    test('all: roots with children become sections; childless + dangling go '
        'flat; children sorted by name', () {
      final plan = planWorldLibrary(
        worlds: library,
        filter: WorldLibraryFilter.all,
      );
      expect(plan.sections.single.root.id, 'Bletchfield');
      // name order: Shadow Hall, Tea Rooms, Town Hall.
      expect(plan.sections.single.places.map((p) => p.id), [
        'Shadow Hall',
        'Tea Rooms',
        'Town Hall',
      ]);
      // The town renders through its section only — never also in flat.
      expect(plan.flat.map((f) => f.id), ['Red Dust Station', 'Ghost Room']);
      // Three places under the town — the ghost's dangling parent is flat
      // cargo, not anyone's child.
      expect(plan.locationCount, 3);
      expect(plan.isFlatLibrary, isFalse);
    });

    test(
      'roots only: every root flat or a header; no child cards anywhere',
      () {
        final plan = planWorldLibrary(
          worlds: library,
          filter: WorldLibraryFilter.rootsOnly,
        );
        // The town has children, so it is a section header (empty places);
        // the childless and dangling roots are flat.
        expect(plan.sections.single.root.id, 'Bletchfield');
        expect(plan.sections.single.places, isEmpty);
        expect(
          plan.flat.map((f) => f.id),
          containsAll(['Red Dust Station', 'Ghost Room']),
        );
        expect(plan.flat.map((f) => f.id), isNot(contains('Bletchfield')));
      },
    );

    test('model made: only the flagged worlds, at any depth, flat', () {
      final plan = planWorldLibrary(
        worlds: library,
        filter: WorldLibraryFilter.modelMade,
      );
      expect(plan.sections, isEmpty);
      expect(plan.flat.map((f) => f.id), ['Shadow Hall']);
    });

    test('a library with no locations is flat — the pre-locations shape', () {
      final plan = planWorldLibrary(
        worlds: [station],
        filter: WorldLibraryFilter.all,
      );
      expect(plan.isFlatLibrary, isTrue);
      expect(plan.sections, isEmpty);
      expect(plan.flat.map((f) => f.id), ['Red Dust Station']);
    });

    test('placesUnder counts direct children only, resolved parents', () {
      expect(placesUnder('Bletchfield', library), 3);
      // Dangling parent id counts under nobody.
      expect(placesUnder('gone', library), 0);
    });
  });

  group('libraryDisplayOrder', () {
    test('roots first with subtrees beneath, dangling parents last', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final room = w('Room', parent: 'Town Hall');
      final cafe = w('Cafe', parent: 'Bletchfield');
      final lone = w('Red Dust Station');
      final ghost = w('Ghost Room', parent: 'gone');
      final order = libraryDisplayOrder([
        room,
        lone,
        cafe,
        ghost,
        hall,
        town,
      ]).map((x) => x.id).toList();
      // Roots come in library order; each root is immediately followed by
      // its subtree, children by name. The dangling "Ghost Room" reads as
      // a root (its parent row is gone) — never hidden, never orphaned.
      expect(order, [
        'Red Dust Station',
        'Ghost Room',
        'Bletchfield',
        'Cafe',
        'Town Hall',
        'Room',
      ]);
    });
  });

  group('parentPickCandidates', () {
    test(
      'excludes self and descendants; a childless root can adopt a depth-1',
      () {
        final town = w('Bletchfield');
        final hall = w('Town Hall', parent: 'Bletchfield');
        final room = w('Room', parent: 'Town Hall');
        final lone = w('Lone');
        final all = [town, hall, room, lone];
        // Creating a new place: the depth-2 Room cannot be a parent (a child
        // would sit at depth 3), the rest can.
        final create = parentPickCandidates(null, all, index(all));
        expect(create.map((c) => c.id), ['Bletchfield', 'Town Hall', 'Lone']);
        // Re-parenting the town: its subtree already sits at the depth-2 cap
        // (room), so nothing can take it — under its own children rings,
        // under the lone root the room would land at depth 3.
        final reparent = parentPickCandidates(town, all, index(all));
        expect(reparent, isEmpty);
        // A shallower town (childless) could go under Lone.
        final shallowTown = w('Quiet Ville');
        final moveUp = parentPickCandidates(shallowTown, [
          ...all,
          shallowTown,
        ], index([...all, shallowTown]));
        expect(moveUp.map((c) => c.id), containsAll(['Lone', 'Bletchfield']));
      },
    );
  });

  group('reachablePlaces', () {
    test('self, parent, children and siblings — one move step', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final tea = w('Tea Rooms', parent: 'Bletchfield');
      final room = w('Back Room', parent: 'Town Hall');
      final far = w('Red Dust Station');
      final all = [town, hall, tea, room, far];
      final reach = reachablePlaces(hall, all, index(all));
      expect(reach.map((r) => r.id).toSet(), {
        'Town Hall',
        'Bletchfield',
        'Back Room',
        'Tea Rooms',
      });
      expect(reach.map((r) => r.id), isNot(contains('Red Dust Station')));
    });

    test('a root reaches its children but has no parent or siblings', () {
      final town = w('Bletchfield');
      final hall = w('Town Hall', parent: 'Bletchfield');
      final far = w('Red Dust Station');
      final reach = reachablePlaces(town, [
        town,
        hall,
        far,
      ], index([town, hall, far]));
      expect(reach.map((r) => r.id).toSet(), {'Bletchfield', 'Town Hall'});
    });
  });

  group('isModelMade', () {
    test('reads the madeBy trait, ignores other values', () {
      expect(w('A', model: true).isModelMade, isTrue);
      expect(w('B').isModelMade, isFalse);
      final forged = w('C');
      forged.placeTraits['madeBy'] = 'wizard';
      expect(forged.isModelMade, isFalse);
    });
  });
}
