// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 8 (design §9.3): the review shelf groups by place when the
// scout saw tags, each place row carries its own-weather switch, and a
// flat scout (no places) renders the old flat shelf untouched.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/review_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

void main() {
  testWidgets('the shelf groups signed-candidates by place and offers '
      'per-place weather', (tester) async {
    final state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.climateEnabled = true;
    state.places = const [
      WorldProposedPlace(
        name: 'Alnhama Republic',
        climateHint: 'coastal city-state',
      ),
    ];
    state.proposed = const [
      WorldProposedCard(
        name: "Baker's Street",
        keys: ["Baker's Street"],
        role: WorldCraftRole.hub,
        sourceTitles: ['Alnhama'],
      ),
      WorldProposedCard(
        name: 'Mira the Scout',
        keys: ['Mira'],
        role: WorldCraftRole.leaf,
        sourceTitles: ['Ceolwynn'],
        place: 'Alnhama Republic',
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiReviewStep(state: state)),
      ),
    );

    expect(find.text('Alnhama Republic'), findsOneWidget);
    expect(find.textContaining('Weather hint: coastal'), findsOneWidget);
    expect(find.text('Own weather'), findsOneWidget);

    // Root card renders before the place block (root bucket first).
    final cards = find.byType(CheckboxListTile);
    expect(cards, findsNWidgets(2));
    final first = tester.widget<CheckboxListTile>(cards.first);
    expect((first.title as Text).data, "Baker's Street");

    // Toggling the place switch lands in state, per place key.
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(state.placeClimate, contains('alnhama republic'));
    expect(state.signed, isEmpty, reason: 'no select-all, still');
  });

  testWidgets('no places renders the flat shelf exactly as before', (
    tester,
  ) async {
    final state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.proposed = const [
      WorldProposedCard(
        name: "Baker's Street",
        keys: ["Baker's Street"],
        role: WorldCraftRole.hub,
        sourceTitles: ['Alnhama'],
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiReviewStep(state: state)),
      ),
    );
    expect(find.text('Own weather'), findsNothing);
    expect(find.byType(Switch), findsNothing);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(state.signed, {0});
  });
}
