// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// An open promise carries the story day it was made, so after a long skip
// the prompt can say it has been open two weeks instead of reading as a
// plan for tonight.
//
// Proven red: dropping `storyDay: JournalStore.stampOf(card).$1` from
// PromiseDebtService.listOpen leaves the open promise undated.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/chat/journal_store.dart';
import 'package:front_porch_ai/services/chat/promise_debt_service.dart';

void main() {
  late AppDatabase db;
  late JournalStore store;
  setUp(() {
    db = AppDatabase.forTesting();
    store = JournalStore(getDb: () => db);
  });
  tearDown(() => db.close());

  test('an open promise knows the story day it was made', () async {
    final s = PromiseDebtService(
      journalStore: store,
      fireEval: (_) async => 'NEW user meet her at the cafe tomorrow',
      getMaxCards: () => 50,
      applyTrustDelta: (_) {},
      applyBondDelta: (_) {},
    );
    await s.evaluateTurn(
      sessionId: 's1',
      characterId: 'mara',
      characterName: 'Mara',
      userName: 'Ben',
      recentExchange: 'Ben: I promise I will meet you at the cafe tomorrow.',
      storyDay: 3,
    );
    expect((await s.listOpen('s1', 'mara')).single.storyDay, 3);
  });
}
