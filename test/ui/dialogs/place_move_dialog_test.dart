// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scene-move question speaks both cases: arriving INTO a tree (the
// old setting demotes to lore) and arriving with no prior setting. The
// design sentence is law: it says the place, asks, and never implies the
// move already happened.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/models.dart' show World;
import 'package:front_porch_ai/services/chat/scene_move_state.dart';
import 'package:front_porch_ai/ui/dialogs/dialogs.dart';

void main() {
  const move = PendingPlaceMove(id: 'p-tea', name: 'Tea Rooms');
  final earth = World(name: 'Earth', lorebook: Lorebook(entries: []));

  test('inside a tree: names both places and the lore promise', () {
    final prompt = PlaceMoveDialog(move: move, setting: earth);
    expect(prompt.question, contains('Tea Rooms'));
    expect(prompt.question, contains('Earth'));
    expect(prompt.question, contains('Move the scene there?'));
    expect(prompt.consequence, contains('keeps Earth live as lore'));
  });

  test('no prior setting: no false "you are in"', () {
    final prompt = PlaceMoveDialog(move: move, setting: null);
    expect(prompt.question, isNot(contains('you are in')));
    expect(prompt.consequence, contains('weather and lore take over'));
  });

  testWidgets('the copy body renders (chrome + title come from the '
    'warm shell at open time, asserted by the shell suite)', (tester) async {
    final prompt = PlaceMoveDialog(move: move, setting: earth);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: prompt.build)),
      ),
    );
    expect(find.textContaining('arriving at Tea Rooms'), findsOneWidget);
    expect(find.textContaining('keeps Earth live as lore'), findsOneWidget);
  });
}
