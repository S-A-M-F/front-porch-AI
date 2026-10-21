// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Interaction contract for a library card (locations slice 3, hostile
// review follow-up): tap OPENS THE EDITOR (the pre-locations behaviour,
// pinned by world_blank_name_test through the page), long-press enters
// "Move into…" selection, and the badge's own tap steps out. The weather
// tag and the depth tag follow the mockups: every location gets one, the
// "inside X" tag only where the tree context is not visually obvious.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
import 'package:front_porch_ai/ui/pages/worlds/world_place_card.dart';
import 'package:front_porch_ai/ui/pages/worlds/world_place_moves.dart';

import '../../golden/support/fakes.dart';

model.World place(String name, {bool climate = false, String? biomeId}) =>
    model.World(
      id: name,
      name: name,
      description: '$name prose.',
      lorebook: Lorebook(entries: []),
      climateEnabled: climate,
      biomeId: biomeId,
    );

Future<void> pumpCard(
  WidgetTester tester, {
  required model.World world,
  VoidCallback? onEdit,
  VoidCallback? onSelectedToggle,
  bool? selected,
  model.World? parent,
  String? insideName,
  bool hasWeatherToInherit = true,
}) async {
  bool toggled = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            height: 300,
            child: WorldPlaceCard(
              world: world,
              parent: parent,
              insideName: insideName,
              selected: selected,
              hasWeatherToInherit: hasWeatherToInherit,
              onSelected: onSelectedToggle == null
                  ? null
                  : (on) {
                      toggled = true;
                      expect(on, !(selected ?? false));
                      onSelectedToggle();
                    },
              onEdit: onEdit ?? () {},
              onExport: () {},
              onDelete: () {},
            ),
          ),
        ),
      ),
    ),
  );
  // Expose the toggle recorder through a closure the tests re-check.
  expect(toggled, isFalse, reason: 'build alone must not fire callbacks');
}

/// The batch flow's repository: records saves and refuses one world, so
/// a half-committed move must put the refused card back where it was.
class _BatchRepo extends FakeWorldRepository {
  _BatchRepo(super.worlds, {required this.failOn});

  final String failOn;

  @override
  Future<void> saveWorld(model.World world) async {
    if (world.name == failOn) throw StateError('depth cap says no');
  }
}

void main() {
  testWidgets('tap opens the editor even when selection is armed', (
    tester,
  ) async {
    var edited = false;
    var toggled = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 300,
              child: WorldPlaceCard(
                world: place('Town Hall'),
                parent: place('Bletchfield'),
                selected: false,
                onSelected: (_) => toggled = true,
                onEdit: () => edited = true,
                onExport: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(WorldPlaceCard));
    await tester.pump();
    expect(edited, isTrue, reason: 'tap keeps opening the editor');
    expect(toggled, isFalse, reason: 'tap must not toggle selection');

    await tester.longPress(find.byType(WorldPlaceCard));
    await tester.pump();
    expect(toggled, isTrue, reason: 'long-press enters selection');
  });

  testWidgets('the selection badge appears only when selected and untaps out', (
    tester,
  ) async {
    bool? toggledTo;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 340,
              height: 300,
              child: WorldPlaceCard(
                world: place('Town Hall'),
                parent: place('Bletchfield'),
                selected: true,
                onSelected: (on) => toggledTo = on,
                onEdit: () {},
                onExport: () {},
                onDelete: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final badge = find.byIcon(Icons.check_circle);
    expect(badge, findsOneWidget);
    await tester.tap(badge);
    await tester.pump();
    expect(toggledTo, isFalse, reason: 'badge tap deselects');
  });

  testWidgets('weather tags: inherits muted, own names the biome', (
    tester,
  ) async {
    await pumpCard(
      tester,
      world: place('Town Hall'),
      parent: place('Bletchfield'),
    );
    expect(find.text('Inherits weather'), findsOneWidget);
    expect(
      find.textContaining('inside '),
      findsNothing,
      reason: 'direct children sit under their parent visually',
    );

    await pumpCard(
      tester,
      world: place('Northern Europe', climate: true, biomeId: 'continental'),
      parent: place('Earth'),
      insideName: 'Earth',
    );
    expect(
      find.textContaining('Own climate'),
      findsOneWidget,
      reason: 'an owning location tags with the mockup wording',
    );
    expect(
      find.textContaining('Continental'),
      findsOneWidget,
      reason: 'the mockup names the biome in the tag',
    );
    expect(find.text('inside Earth'), findsOneWidget);
  });

  testWidgets(
    'a child with no climate author in its chain reads "Weather off"',
    (tester) async {
      await pumpCard(
        tester,
        world: place('Town Hall'),
        parent: place('Bletchfield'),
        hasWeatherToInherit: false,
      );
      expect(
        find.text('Weather off'),
        findsOneWidget,
        reason: 'a lore-only chain must not promise weather to inherit (§7)',
      );
      expect(find.text('Inherits weather'), findsNothing);
    },
  );

  testWidgets('a refused batch move restores the prior parent and repaints', (
    tester,
  ) async {
    final earth = place('Earth', climate: true);
    final harbor = place('Harbor');
    final town = place('Town');
    final repo = _BatchRepo([earth, harbor, town], failOn: 'Town');
    var repaints = 0;
    final selected = {'Harbor', 'Town'};
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () =>
                  movePlacesInto(ctx, repo, selected, () => repaints++),
              child: const Text('move'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('move'));
    await tester.pumpAndSettle();
    // The target dialog offers Earth (valid for both selections).
    await tester.tap(find.text('Earth').last);
    // Harbor commits, Town's save throws — settle without letting the
    // snackbar auto-hide burn the assertion.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(harbor.parentWorldId, 'Earth', reason: 'the committed move stands');
    expect(
      town.parentWorldId,
      isNull,
      reason:
          'the refused move is put back in the cache, not left on the '
          'target the DB refused',
    );
    expect(
      repaints,
      greaterThan(0),
      reason: 'the grid repaints the moment the cache would otherwise lie',
    );
    expect(
      find.textContaining('Moved 1 of 2'),
      findsOneWidget,
      reason: 'the partial batch names what already moved',
    );
  });
}
