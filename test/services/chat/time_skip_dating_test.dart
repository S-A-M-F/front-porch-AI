// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// After a long skip every channel that carries the past says WHEN: the
// recap is stamped with the story moment it was written at, open promises
// say how long ago they were made, RAG lines carry their age in the
// Journal's words, a memory older than the loaded window goes unstamped
// instead of borrowing the window's first day, and the long date does not
// grow a year when a contemporary story's clock crosses New Year.
//
// Proven red: dropping `asOf` from buildRecapBlock, the `age` suffix in
// PromiseDebtInjection, the `ago` in formatRagLine, the
// `positionStart < basePosition` guard in storyDayAt, or the
// StoryClock.yearAnchorFor call in TimeService.displayDate each turns its
// test below red.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/promise_debt_service.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/chat/rag_injection.dart';
import 'package:front_porch_ai/services/chat/story_clock.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

ChatMessage _reply(String text, DateTime after) => ChatMessage(
  text: text,
  sender: 'Mae',
  isUser: false,
  metadata: {
    'story_clock_before': StoryClock.serializeClock(after),
    'story_clock_after': StoryClock.serializeClock(after),
  },
);

ChatMessage _user(String text) =>
    ChatMessage(text: text, sender: 'User', isUser: true);

void main() {
  final start = DateTime.utc(2026, 3, 3); // a Tuesday

  group('recap', () {
    final messages = [
      _user('Tonight we plan the porch.'),
      _reply('Tomorrow, then.', DateTime.utc(2026, 3, 3, 22, 30)),
      _user('Two weeks later...'),
      _reply('Hello again.', DateTime.utc(2026, 3, 17, 9)),
    ];

    test('is stamped with the moment its pass covered up to', () {
      final asOf = recapAsOf(
        messages: messages,
        cursor: 2,
        startDate: start,
        currentDay: 15,
      );
      expect(asOf, 'Day 1, Tuesday night — 2 weeks ago');
      expect(
        buildRecapBlock(recap: 'They planned the porch.', asOf: asOf),
        '\n[Earlier in this story (a recap for memory, as of Day 1, Tuesday '
        'night — 2 weeks ago; not new prose — do not continue or restate '
        'it): They planned the porch.]\n',
      );
    });

    test('with no clock stamp before the cursor it reads as before', () {
      expect(
        recapAsOf(
          messages: [_user('hi'), _user('again')],
          cursor: 2,
          startDate: start,
          currentDay: 1,
        ),
        isNull,
      );
      expect(
        buildRecapBlock(recap: 'x', asOf: null),
        buildRecapBlock(recap: 'x'),
      );
    });
  });

  group('open promises', () {
    late AppDatabase db;
    late PromiseDebtService service;

    setUp(() async {
      db = AppDatabase.forTesting();
      service = PromiseDebtService(
        journalStore: JournalStore(getDb: () => db),
        fireEval: (_) async => 'NEW user fix the porch',
        getMaxCards: () => 50,
        applyTrustDelta: (_) {},
        applyBondDelta: (_) {},
      );
      await service.evaluateTurn(
        sessionId: 's1',
        characterId: 'mae',
        characterName: 'Mae',
        userName: 'Sam',
        recentExchange: 'Sam: I promise I will fix the porch tomorrow.',
        storyDay: 1,
      );
      await service.listOpen('s1', 'mae');
    });

    tearDown(() => db.close());

    PromiseDebtInjection injection(int? today) => PromiseDebtInjection(
      getCurrentStoryDay: () => today,
      promiseDebtService: service,
      getSessionId: () => 's1',
      getActiveCharacter: () => CharacterCard(name: 'Mae'),
      getIsGroupNonObserverMode: () => false,
      getCurrentSpeakerIdForRealism: () => 'mae',
      getGroupCharacters: () => const [],
      getCharacterIdFromCard: (c) => 'mae',
      getUserName: () => 'Sam',
    );

    test('say when they were made and how long ago', () {
      expect(
        injection(15).buildPromiseDebtInjection(),
        contains('fix the porch (made Day 1 — 2 weeks ago)'),
      );
    });

    test('stay undated while the clock is stopped', () {
      expect(
        injection(null).buildPromiseDebtInjection(),
        isNot(contains('made Day')),
      );
    });
  });

  group('RAG lines', () {
    test('carry their age in the Journal\'s words', () {
      expect(
        formatRagLine('Mae: tomorrow', day: 3, otherChat: false, today: 17),
        '- (Day 3 — 2 weeks ago) Mae: tomorrow',
      );
      expect(
        formatRagLine('Mae: now', day: 17, otherChat: false, today: 17),
        '- (Day 17) Mae: now',
      );
    });

    test('a memory older than the loaded window is unstamped, not given '
        'the window\'s first day', () {
      final window = [
        ChatMessage(
          text: 'today',
          sender: 'Mae',
          isUser: false,
          metadata: {
            'realism_state': {'dayCount': 15},
          },
        ),
      ];
      expect(storyDayAt(window, 40, 41, basePosition: 100), isNull);
      expect(storyDayAt(window, 100, 100, basePosition: 100), 15);
    });
  });

  group('long date year', () {
    TimeService service(String startDate, int dayCount) =>
        TimeService(
          onNotify: () {},
          onSaveChat: () async {},
          onSetPendingRealismMetadata: (_, _) {},
          onPatchLastMessageRealismState: (_, _, _) {},
          getBackendIdentity: () => 'test-backend',
        )..seedFromV2OrExt(
          dayCount: dayCount,
          timeOfDay: 'morning',
          storyStartDate: startDate,
        );

    test('a contemporary story crossing New Year does not grow a year', () {
      final year = StoryClock.todayAnchor().year;
      final t = service('$year-12-30', 4);
      expect(t.clock.year, year + 1);
      expect(t.displayDate, isNot(contains('${year + 1}')));
    });

    test('a period story keeps its year', () {
      expect(service('1887-06-01', 1).displayDate, contains('1887'));
    });
  });
}
