// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Shelf. Every card the scout proposed starts signed once its shelf is
// taken (the maintainer's ruling of 2026-10-24: the Review step at the end
// is where a written card gets fixed, so the shelf is a trim, not a chore).
// Before that ruling the first test here pinned "nothing signed by
// default", which is now false. Still no select-all pill over the whole
// shelf. The uplift's kind filters, "Only the backbone" and "Sign all
// here" are pinned here too.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/review_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_shelf_actions.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

const _cards = [
  WorldProposedCard(
    name: 'The Age of Three Fires',
    keys: ['Three Fires'],
    role: WorldCraftRole.era,
    sourceTitles: ['Quincy Blood War'],
    kind: 'event',
  ),
  WorldProposedCard(
    name: "Baker's Street",
    keys: ["Baker's Street"],
    role: WorldCraftRole.hub,
    sourceTitles: ["Baker's Street"],
    kind: 'place',
  ),
  WorldProposedCard(
    name: 'River Faith',
    keys: ['River Faith'],
    role: WorldCraftRole.leaf,
    sourceTitles: ['River Faith'],
    group: 'river-faith',
    kind: 'faction',
    place: 'Alnhama Republic',
  ),
  WorldProposedCard(
    name: 'Mira the Scout',
    keys: ['Mira'],
    role: WorldCraftRole.leaf,
    sourceTitles: ['Mira the Scout'],
    group: 'river-faith',
    kind: 'person',
    place: 'Alnhama Republic',
  ),
];

WorldScoutResult _scouted({List<WorldProposedPlace> places = const []}) =>
    WorldScoutResult(
      catalog: const WikiStudioCatalog(
        backend: WikiBackend.mediawiki,
        titles: ['a', 'b', 'c'],
      ),
      proposed: _cards,
      places: places,
    );

Future<WorldFromWikiState> _mount(
  WidgetTester tester, {
  List<WorldProposedPlace> places = const [],
}) async {
  await tester.binding.setSurfaceSize(const Size(1300, 1800));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final state = WorldFromWikiState();
  addTearDown(state.disposeControllers);
  state.takeShelf(_scouted(places: places));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (_, _) => WorldFromWikiReviewStep(state: state),
        ),
      ),
    ),
  );
  return state;
}

Finder _tile(String title) => find.ancestor(
  of: find.text(title),
  matching: find.byType(CheckboxListTile),
);

void main() {
  testWidgets('the scout\'s shelf lands with every card signed; an untick '
      'is one card; no select-all pill', (tester) async {
    final state = await _mount(tester);
    expect(state.signed, {0, 1, 2, 3});
    expect(state.catalogTitleCount, 3);

    expect(find.text('All'), findsNothing, reason: 'no select-all pill');
    expect(find.text("Baker's Street"), findsOneWidget);
    expect(find.textContaining('river-faith'), findsWidgets);
    expect(
      find.descendant(
        of: find.byKey(const Key('world-shelf-count-signed')),
        matching: find.text('4'),
      ),
      findsOneWidget,
    );

    await tester.tap(_tile("Baker's Street"));
    await tester.pump();
    expect(state.signed, {0, 2, 3});
    expect(
      state.signedCards.map((c) => c.name),
      isNot(contains("Baker's Street")),
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('world-shelf-count-signed')),
        matching: find.text('3'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('Only the backbone leaves exactly the era, places, factions '
      'and events signed', (tester) async {
    final state = await _mount(tester);
    state.signed.remove(1);
    await tester.tap(find.byKey(const Key('world-shelf-only-backbone')));
    await tester.pump();
    expect(state.signed, {
      0,
      1,
      2,
    }, reason: 'the person is the short write\'s cut');
  });

  testWidgets('a kind filter shows that kind only, and Sign all here flips '
      'one place', (tester) async {
    final state = await _mount(
      tester,
      places: const [WorldProposedPlace(name: 'Alnhama Republic')],
    );
    await tester.tap(find.byKey(const Key('world-shelf-filter-People')));
    await tester.pump();
    expect(find.text('Mira the Scout'), findsOneWidget);
    expect(find.text("Baker's Street"), findsNothing);
    await tester.tap(find.byKey(const Key('world-shelf-filter-People')));
    await tester.pump();
    expect(find.text("Baker's Street"), findsOneWidget);

    // The root group has its own button, so look inside the place's.
    final placeKey = state.places.single.key;
    final button = find.byKey(Key('world-shelf-sign-all-$placeKey'));
    expect(
      find.descendant(of: button, matching: find.text('Unsign all here')),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    expect(state.signed, {0, 1});
    expect(
      find.descendant(of: button, matching: find.text('Sign all here')),
      findsOneWidget,
    );
    await tester.tap(button);
    await tester.pump();
    expect(state.signed, {0, 1, 2, 3});
  });
}
