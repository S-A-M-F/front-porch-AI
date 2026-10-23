// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The wizard's context window and what is sized from it. Every number here
// is arithmetic the engine relies on: a wrong split or a wrong clip sends
// a prompt the window cannot hold, and KoboldCpp trims it from the front.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

// A Fandom-sized index line: a title and four category names, ~25 tokens,
// so 500 of them (~12.5K tokens) outgrow a 16K window's prompt room.
String _line(int i) =>
    '- The Chronicle of Title ${i.toString().padLeft(3, '0')} '
    '[Nations of the Northern Reach ${i % 7}, Peoples of the River ${i % 5}, '
    'Characters introduced in volume ${i % 9}, Settlements and keeps]';

String _promptFor(List<String> part) =>
    'World: Neokosmos\nPremise: A coastal republic.\nINDEX TITLES:\n'
    '${part.join('\n')}\n\n$kWorldScoutPrompt\nCall $kWorldScoutToolName once.';

WorldProposedCard _card(int i) => WorldProposedCard(
  name: 'Card $i',
  keys: const [],
  role: WorldCraftRole.leaf,
  sourceTitles: ['Title $i'],
);

void main() {
  group('wizard context', () {
    test('0 follows the chat, a pick wins, nothing goes under the floor', () {
      expect(worldWikiContextTokens(setting: 0, chatContext: 65536), 65536);
      expect(worldWikiContextTokens(setting: 32768, chatContext: 65536), 32768);
      expect(
        worldWikiContextTokens(setting: 0, chatContext: 8192),
        kWorldWikiContextFloor,
      );
      expect(worldWikiContextSettingValid(0), isTrue);
      expect(worldWikiContextSettingValid(65536), isTrue);
      expect(worldWikiContextSettingValid(4096), isFalse);
    });

    test('labels read in K', () {
      expect(worldWikiContextLabel(16384), '16K');
      expect(worldWikiContextLabel(65536), '64K');
      expect(worldWikiContextLabel(262144), '256K');
      expect(worldWikiContextLabel(20000), '20000');
    });

    test('the reply gets what the window leaves after the prompt', () {
      const budget = WorldWikiBudget(65536);
      final prompt = 'x' * 4000; // 1000 tokens
      expect(
        budget.roomAfter(prompt),
        65536 - 1000 - kWorldWikiPromptOverheadTokens,
      );
      expect(
        budget.replyFor(prompt),
        65536 - 1000 - kWorldWikiPromptOverheadTokens,
      );
      expect(budget.leaves(prompt, 60000), isTrue);
      expect(budget.leaves(prompt, 64000), isFalse);
      // A prompt that outgrows the window still asks for the floor.
      const tiny = WorldWikiBudget(16384);
      expect(tiny.replyFor('y' * 80000, floor: 2048), 2048);
      expect(
        tiny.clipForReply('z' * 80000, want: 2048).length,
        (16384 - kWorldWikiPromptOverheadTokens - 2048) * 4,
      );
      expect(tiny.clipForReply('z' * 80000, want: 16000), isEmpty);
    });
  });

  group('scout index parts', () {
    final lines = List.generate(500, _line);

    test(
      'a 16K window asks a 500-title tagged index in parts that each leave the reply room',
      () {
        const budget = WorldWikiBudget(16384);
        final parts = splitWorldScoutIndex(
          lines,
          budget: budget,
          promptFor: _promptFor,
        );
        expect(parts.length, greaterThan(1));
        expect(
          parts.expand((p) => p).toList(),
          lines,
          reason: 'every title once, in order',
        );
        for (final part in parts) {
          expect(
            budget.leaves(_promptFor(part), kWorldScoutReplyWant),
            isTrue,
            reason:
                'a part of ${part.length} lines must leave $kWorldScoutReplyWant tokens',
          );
        }
      },
    );

    test(
      'a big ask is split by cards too, each part taking every n-th line',
      () {
        final parts = splitWorldScoutIndex(
          lines,
          budget: const WorldWikiBudget(65536),
          promptFor: _promptFor,
          minParts: 3,
        );
        expect(parts, hasLength(3));
        expect(parts[0].take(2).toList(), [lines[0], lines[3]]);
        expect(parts[1].first, lines[1]);
        expect(
          parts.expand((p) => p).toSet(),
          lines.toSet(),
          reason: 'every title once',
        );
        // A small index is not cut into parts under the minimum.
        expect(
          splitWorldScoutIndex(
            lines.take(30).toList(),
            budget: const WorldWikiBudget(65536),
            promptFor: _promptFor,
            minParts: 3,
          ),
          hasLength(1),
        );
      },
    );

    test('one card\'s article grows with the wizard\'s context', () {
      expect(worldWriteArticleCharsFor(16384), kWorldWriteArticleChars);
      expect(worldWriteArticleCharsFor(32768), kWorldWriteArticleChars);
      expect(worldWriteArticleCharsFor(65536), kWorldWriteArticleChars * 2);
      expect(worldWriteArticleCharsFor(131072), kWorldWriteArticleChars * 4);
      expect(worldWriteArticleCharsFor(262144), kWorldWriteArticleChars * 4);
    });

    test('a 64K window asks the same index whole', () {
      final parts = splitWorldScoutIndex(
        lines,
        budget: const WorldWikiBudget(65536),
        promptFor: _promptFor,
      );
      expect(parts, hasLength(1));
    });

    test(
      'a part never shrinks under the minimum, even in a window too small for it',
      () {
        final parts = splitWorldScoutIndex(
          lines.take(30).toList(),
          budget: const WorldWikiBudget(1),
          promptFor: _promptFor,
        );
        expect(parts.first.length, greaterThanOrEqualTo(kWorldScoutMinPart));
      },
    );

    test(
      'halving keeps every line and gives the odd one to the first half',
      () {
        final (a, b) = halveWorldScoutPart(lines.take(25).toList());
        expect(a.length, 13);
        expect(b.length, 12);
        expect([...a, ...b], lines.take(25).toList());
      },
    );
  });

  group('write batches', () {
    test(
      'long articles pack fewer cards per batch and never outgrow the window',
      () async {
        const budget = WorldWikiBudget(16384);
        const header = 120;
        final cards = List.generate(10, _card);
        final batches = await planWorldWriteBatches(
          cards,
          budget: budget,
          headerTokens: header,
          articleFor: (card) async => 'a' * 20000, // 5,000 tokens each
        ).toList();
        final capacity =
            budget.contextTokens -
            kWorldWikiPromptOverheadTokens -
            kWorldWriteReplyWant -
            header;
        // Changed 2026-10-23: a per-card article cap (kWorldWriteArticleChars)
        // clips 20K-char articles to 6K, so six cards fit a 16K batch where
        // three did; the window arithmetic below is the pin that matters.
        expect(batches.length, 2, reason: 'six clipped cards, then four');
        expect(batches.expand((b) => b.cards).length, 10);
        for (final b in batches) {
          expect(b.cards.length, lessThanOrEqualTo(kWorldWriteBatchSize));
          final cost = b.articles.fold<int>(
            0,
            (sum, a) =>
                sum +
                kWorldWriteCardOverheadTokens +
                worldWikiEstimateTokens(a),
          );
          expect(cost, lessThanOrEqualTo(capacity));
        }
      },
    );

    test('a 64K window packs eight short cards per batch as before', () async {
      final batches = await planWorldWriteBatches(
        List.generate(10, _card),
        budget: const WorldWikiBudget(65536),
        headerTokens: 120,
        articleFor: (card) async => 'short article',
      ).toList();
      expect(batches.map((b) => b.cards.length), [8, 2]);
    });

    test(
      'one huge article is clipped so the card still fits; a miss is skipped',
      () async {
        const budget = WorldWikiBudget(16384);
        final missed = <String>[];
        final batches = await planWorldWriteBatches(
          [_card(1), _card(2)],
          budget: budget,
          headerTokens: 100,
          articleFor: (card) async => card.name == 'Card 2' ? '' : 'b' * 200000,
          onMiss: (card) => missed.add(card.name),
        ).toList();
        expect(missed, ['Card 2']);
        expect(batches, hasLength(1));
        final capacity =
            budget.contextTokens -
            kWorldWikiPromptOverheadTokens -
            kWorldWriteReplyWant -
            100;
        // Changed 2026-10-23: the per-card cap now binds before the window
        // does at 16K (6,000 chars < what the window would allow).
        expect(batches.single.articles.single.length, kWorldWriteArticleChars);
        expect(
          kWorldWriteArticleChars,
          lessThan((capacity - kWorldWriteCardOverheadTokens) * 4),
        );
      },
    );

    test('a window too small for the cap clips to its own floor', () async {
      final batches = await planWorldWriteBatches(
        [_card(1)],
        budget: const WorldWikiBudget(4096),
        headerTokens: 100,
        articleFor: (card) async => 'c' * 200000,
      ).toList();
      expect(
        batches.single.articles.single.length,
        800,
        reason:
            'the window leaves nothing; 800 chars is the floor one card always gets',
      );
    });

    test('stop ends the planning between cards', () async {
      var fetched = 0;
      final batches = await planWorldWriteBatches(
        List.generate(10, _card),
        budget: const WorldWikiBudget(65536),
        headerTokens: 100,
        articleFor: (card) async {
          fetched++;
          return 'article';
        },
        stop: () => fetched >= 3,
      ).toList();
      expect(fetched, 3);
      expect(batches, isEmpty, reason: 'a stopped plan yields nothing more');
    });
  });
}
