// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

// The Book step after the uplift: four cards with a job each, the saved
// wikis as tiles, Depth as tiles that write the stored pick, the context
// as pills, the Moment as a story card, and the progress card over a
// dimmed form while Scout runs. Every colour comes from the theme; the
// test runs the real step over a real StorageService.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/book_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_progress_panel.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late StorageService storage;
  late WorldFromWikiState state;

  Future<void> mount(WidgetTester tester, {double width = 1300}) async {
    await tester.binding.setSurfaceSize(Size(width, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      dir = await Directory.systemTemp.createTemp('fpai wiki book');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (call) async => call.method == 'getApplicationDocumentsDirectory'
                ? dir.path
                : null,
          );
      SharedPreferences.setMockInitialValues({'update_auto_check': false});
      storage = StorageService();
      await storage.initialized;
      await storage.webSearchSettings.addSavedWikiUrl(
        'https://bleach.fandom.com',
      );
      await storage.webSearchSettings.addSavedWikiUrl(
        'https://quietoak.github.io/NeokosmosWiki/',
      );
    });
    addTearDown(() async => dir.delete(recursive: true));
    state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.wikiUrl = 'https://bleach.fandom.com';
    await tester.pumpWidget(
      ChangeNotifierProvider<StorageService>.value(
        value: storage,
        child: MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (_, _) => WorldFromWikiBookStep(state: state),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('four cards; a depth tile and a context pill write the stored '
      'picks; the wiki tiles say what each is', (tester) async {
    await mount(tester);

    expect(find.text('The world'), findsOneWidget);
    expect(find.text('The wiki'), findsOneWidget);
    expect(find.text('How deep'), findsOneWidget);
    expect(find.text('What to make'), findsOneWidget);
    expect(find.text('Where the story stands'), findsOneWidget);
    expect(find.byKey(const Key('world-from-wiki-moment')), findsOneWidget);
    expect(find.text('MediaWiki'), findsOneWidget, reason: 'the fandom tile');
    expect(find.text('Tiddly'), findsOneWidget, reason: 'the github tile');

    expect(storage.webSearchSettings.worldWikiDepth, 1, reason: 'Full');
    await tester.tap(find.byKey(const Key('world-from-wiki-depth-deep')));
    await tester.pump();
    expect(storage.webSearchSettings.worldWikiDepth, 2);
    expect(find.text('Hours; run it overnight'), findsOneWidget);

    expect(storage.webSearchSettings.worldWikiContextSize, 0);
    await tester.tap(find.byKey(const Key('world-from-wiki-context-131072')));
    await tester.pump();
    expect(storage.webSearchSettings.worldWikiContextSize, 131072);

    await tester.tap(
      find.byKey(
        const Key(
          'world-from-wiki-wiki-https://quietoak.github.io/NeokosmosWiki/',
        ),
      ),
    );
    await tester.pump();
    expect(state.wikiUrl, 'https://quietoak.github.io/NeokosmosWiki/');
  });

  testWidgets('while Scout runs the progress card shows the stage and the '
      'form is dimmed', (tester) async {
    await mount(tester);
    state.scouting = true;
    state.progress.start();
    state.noteProgress(
      'Hunting for what the shelf forgot: Gotei 13 members (round 1 of 2, '
      '12 candidates)…',
    );
    await tester.pump();

    expect(find.byType(WorldProgressPanel), findsOneWidget);
    expect(find.byKey(const Key('world-from-wiki-stop')), findsOneWidget);
    expect(find.byKey(const Key('world-from-wiki-stage-2')), findsOneWidget);
    expect(
      tester.widget<Opacity>(find.byType(Opacity).first).opacity,
      lessThan(1),
      reason: 'the form dims while the scout runs',
    );
    expect(worldScoutStageOf(state.status), 2);
  });

  testWidgets('narrow: the cards stack and still show every section', (
    tester,
  ) async {
    await mount(tester, width: 420);
    expect(find.text('The world'), findsOneWidget);
    expect(find.text('What to make'), findsOneWidget);
    expect(find.byKey(const Key('world-from-wiki-depth-full')), findsOneWidget);
  });
}
