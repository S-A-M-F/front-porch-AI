// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Write step Stop is reachable while a bake is in flight.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/write_step.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_progress_log.dart';

void main() {
  testWidgets('Stop is on the write step and aborts the engine', (
    tester,
  ) async {
    final state = WorldFromWikiState();
    addTearDown(state.disposeControllers);
    state.writing = true;
    state.status = 'Writing 1/3';
    state.engine = WorldFromWikiEngine(
      wiki: WikiSearchService(getBaseUrl: () => ''),
      llm: _SilentLlm(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiWriteStep(state: state)),
      ),
    );

    expect(find.byKey(const Key('world-from-wiki-stop')), findsOneWidget);
    await tester.tap(find.byKey(const Key('world-from-wiki-stop')));
    await tester.pump();
    expect(state.engine!.aborted, isTrue);
    expect(state.canSave, isFalse);
  });

  test('the progress log stamps each line with the time taken and keeps '
      'the last twelve', () {
    var now = DateTime(2026, 10, 23, 12);
    final log = WorldProgressLog(now: () => now);
    expect(log.running, isFalse);
    expect(log.elapsedLabel, '0:00');
    log.start();
    log.note('Rummaging through the wiki…');
    log.note('Rummaging through the wiki…');
    expect(log.lines, hasLength(1), reason: 'the same line twice is one');
    now = now.add(const Duration(seconds: 42));
    log.note('Found 464 pages. Picking the ones that matter…');
    expect(log.elapsedLabel, '0:42');
    expect(log.current, 'Found 464 pages. Picking the ones that matter…');
    expect(log.earlier.single, (
      at: '0:00',
      text: 'Rummaging through the wiki…',
    ));
    for (var i = 0; i < 20; i++) {
      now = now.add(const Duration(minutes: 1));
      log.note('line $i');
    }
    expect(log.lines, hasLength(12));
    expect(log.current, 'line 19');
    expect(log.earlier.first.text, 'line 18', reason: 'newest first');
    now = now.add(const Duration(hours: 1, minutes: 3, seconds: 9));
    expect(log.elapsedLabel, '1:23:51');
    log.stop();
    expect(log.running, isFalse);
    expect(log.lines, hasLength(12), reason: 'the lines stay for reading');
    log.start();
    expect(log.lines, isEmpty);
  });

  testWidgets('the write step shows what the engine is doing, the time '
      'taken, and the lines before', (tester) async {
    var now = DateTime(2026, 10, 23, 12);
    final state = WorldFromWikiState(now: () => now);
    addTearDown(state.disposeControllers);
    state.writing = true;
    state.progress.start();
    state.noteProgress('Reading up on 38 pages…');
    now = now.add(const Duration(seconds: 7));
    state.noteProgress('Writing cards 1–6 of 38…');
    now = now.add(const Duration(seconds: 65));
    state.noteProgress('Reading 6 fresh entries against the story…');
    state.engine = WorldFromWikiEngine(
      wiki: WikiSearchService(getBaseUrl: () => ''),
      llm: _SilentLlm(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: WorldFromWikiWriteStep(state: state)),
      ),
    );

    expect(
      tester
          .widget<Text>(find.byKey(const Key('world-from-wiki-progress')))
          .data,
      'Reading 6 fresh entries against the story…',
    );
    expect(
      tester
          .widget<Text>(find.byKey(const Key('world-from-wiki-elapsed')))
          .data,
      '1:12',
    );
    expect(
      find.textContaining('0:07  Writing cards 1–6 of 38…'),
      findsOneWidget,
    );
    expect(
      find.textContaining('0:00  Reading up on 38 pages…'),
      findsOneWidget,
    );
  });
}

class _SilentLlm extends LLMService {
  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async => null;

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}
