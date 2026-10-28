// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The creator's loop and the coverage audit it feeds: generate, gate,
// review, feed back, bounded tries, best valid answer kept; and the gaps
// the catalog's categories reveal. New machinery, so a file of its own.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

WorldProposedCard _card(
  String name,
  String kind, {
  String place = '',
  WorldCraftRole role = WorldCraftRole.leaf,
}) => WorldProposedCard(
  name: name,
  keys: [name],
  role: role,
  sourceTitles: [name],
  kind: kind,
  place: place,
);

void main() {
  group('runWorldLoop', () {
    test(
      'a gate failure is fed back and the next try passes without a reviewer',
      () async {
        final seen = <List<String>>[];
        final r = await runWorldLoop<String>(
          stage: 's',
          tries: 3,
          generate: (attempt, previous, feedback) async {
            seen.add(feedback);
            return attempt == 1 ? 'bad' : 'good';
          },
          gate: (o) => o == 'bad' ? ['too short'] : const [],
        );
        expect(r.best, 'good');
        expect(r.passed, isTrue);
        expect(r.bestAttempt, 2);
        expect(seen, [
          <String>[],
          ['too short'],
        ]);
        expect(r.notes.map((n) => n.verdict), ['INVALID', 'PASS']);
      },
    );

    test(
      'a reviewer objection is fed back; an unreadable review accepts',
      () async {
        var reviews = 0;
        final r = await runWorldLoop<String>(
          stage: 's',
          tries: 3,
          generate: (attempt, previous, feedback) async =>
              'v$attempt${feedback.isEmpty ? '' : '+${feedback.single}'}',
          gate: (o) => const [],
          review: (o) async {
            reviews++;
            return reviews == 1
                ? const WorldVerdict(pass: false, problems: ['no era card'])
                : WorldVerdict.skipped;
          },
        );
        expect(r.best, 'v2+no era card');
        expect(r.passed, isTrue);
        expect(r.notes.map((n) => n.verdict), ['FAIL', 'PASS']);
        expect(r.notes.last.note, contains('could not be read'));
      },
    );

    test(
      'when every try fails the best valid answer stands, never null',
      () async {
        final r = await runWorldLoop<String>(
          stage: 's',
          tries: 3,
          generate: (attempt, previous, feedback) async => 'try$attempt',
          gate: (o) => o == 'try2' ? const [] : ['x', 'y'],
          review: (o) async =>
              const WorldVerdict(pass: false, problems: ['still wrong']),
        );
        expect(r.passed, isFalse);
        expect(
          r.best,
          'try2',
          reason: 'the one that passed the gate beats the ones that did not',
        );
        expect(r.bestAttempt, 2);
        expect(r.tries, 3);
      },
    );

    test('a null answer is noted and the loop goes on; stop ends it', () async {
      var calls = 0;
      final r = await runWorldLoop<String>(
        stage: 's',
        tries: 5,
        generate: (attempt, previous, feedback) async {
          calls++;
          return attempt == 1 ? null : 'ok';
        },
        gate: (o) => const [],
        stop: () => calls >= 2,
      );
      expect(r.notes.first.verdict, 'NONE');
      expect(r.best, 'ok');
      expect(calls, 2);
    });
  });

  group('shelf verdicts', () {
    test('missing titles fold into the problems and fail the shelf', () {
      final v = parseWorldShelfVerdict([
        const LlmToolCall(
          name: kWorldShelfReviewToolName,
          arguments: {
            'pass': true,
            'problems': [],
            'missing': ['Rukongai', 'Rukia Kuchiki'],
          },
        ),
      ]);
      expect(v.pass, isFalse);
      expect(
        v.problems.single,
        'missing from the shelf: Rukongai, Rukia Kuchiki',
      );
      expect(parseWorldShelfVerdict(const []).parsed, isFalse);
    });

    test('entry verdicts are keyed by name; an unnamed entry passes', () {
      final v = parseWorldEntryVerdicts([
        const LlmToolCall(
          name: kWorldEntriesReviewToolName,
          arguments: {
            'verdicts': [
              {
                'name': 'Yhwach',
                'pass': false,
                'problems': ['states his death'],
              },
              {'name': 'Silbern', 'pass': true},
            ],
          },
        ),
      ]);
      expect(v['yhwach']!.pass, isFalse);
      expect(v['yhwach']!.problems, ['states his death']);
      expect(v['silbern']!.pass, isTrue);
      expect(v.containsKey('rukongai'), isFalse);
    });
  });

  group('coverage audit', () {
    final titles = [
      'Ichigo Kurosaki',
      'Rukia Kuchiki',
      'Soul Society',
      'Royal Guard',
      'Karakura Town',
      'Senjumaru Shutara',
      'Ōetsu Nimaiya',
      'Kirio Hikifune',
      'Tenjirō Kirinji',
      'Inuzuri',
    ];
    final tags = {
      'Ichigo Kurosaki': ['Characters', 'Human'],
      'Rukia Kuchiki': ['Characters', 'Shinigami'],
      'Soul Society': ['Locations'],
      'Royal Guard': ['Organizations'],
      'Karakura Town': ['Locations', 'Human World'],
      'Senjumaru Shutara': ['Characters', 'Royal Guard'],
      'Ōetsu Nimaiya': ['Characters', 'Royal Guard'],
      'Kirio Hikifune': ['Characters', 'Royal Guard'],
      'Tenjirō Kirinji': ['Characters', 'Royal Guard'],
      'Inuzuri': ['Locations', 'Rukongai'],
    };
    final places = const [
      WorldProposedPlace(name: 'Soul Society'),
      WorldProposedPlace(name: 'Rukongai', parentName: 'Soul Society'),
    ];
    final cards = [
      _card('The war', 'event', role: WorldCraftRole.era),
      _card('Soul Society', 'place', role: WorldCraftRole.hub),
      _card(
        'Rukongai',
        'place',
        place: 'Soul Society',
        role: WorldCraftRole.hub,
      ),
      _card(
        'Royal Guard',
        'faction',
        place: 'Soul Society',
        role: WorldCraftRole.hub,
      ),
      _card('Ichigo Kurosaki', 'person'),
    ];

    test(
      'at Deep it names the missing top place, the faction members, the thin place and the top people, each title once',
      () {
        // Changed 2026-10-23: a faction's members get cards only at Deep;
        // at Full the faction's own card names them (the maintainer's
        // ruling after the four-hour Kimi run).
        final gaps = auditWorldCoverage(
          cards: cards,
          places: places,
          titles: titles,
          tags: tags,
          depth: WorldWikiDepth.deep,
        );
        final byKind = {for (final g in gaps) g.kind: g};
        expect(byKind['place']!.candidates, [
          'Karakura Town',
          'Inuzuri',
        ], reason: 'tagged as places, not on the shelf; Soul Society is');
        expect(byKind['faction']!.name, 'Royal Guard');
        expect(byKind['faction']!.candidates, [
          'Senjumaru Shutara',
          'Ōetsu Nimaiya',
          'Kirio Hikifune',
          'Tenjirō Kirinji',
        ]);
        expect(byKind['faction']!.place, 'Soul Society');
        expect(
          byKind.containsKey('thinPlace'),
          isFalse,
          reason:
              'Inuzuri went to the places gap first; a gap with no candidates is not raised',
        );
        expect(
          byKind['people']!.candidates,
          ['Rukia Kuchiki'],
          reason:
              'Ichigo is on the shelf; the Royal Guard four were taken by their faction',
        );
      },
    );

    test('at Full a faction raises no members gap; its card carries the '
        'roster, and the top people still come', () {
      final gaps = auditWorldCoverage(
        cards: cards,
        places: places,
        titles: titles,
        tags: tags,
        depth: WorldWikiDepth.full,
      );
      final kinds = gaps.map((g) => g.kind).toSet();
      expect(kinds, isNot(contains('faction')));
      expect(kinds, contains('place'));
      final people = gaps.firstWhere((g) => g.kind == 'people');
      expect(people.candidates, contains('Rukia Kuchiki'));
    });

    test('a full shelf has no gaps', () {
      final full = [
        ...cards,
        for (final t in [
          'Rukia Kuchiki',
          'Karakura Town',
          'Senjumaru Shutara',
          'Ōetsu Nimaiya',
          'Kirio Hikifune',
          'Tenjirō Kirinji',
          'Inuzuri',
        ])
          _card(t, 'person', place: 'Rukongai'),
      ];
      final gaps = auditWorldCoverage(
        cards: full,
        places: places,
        titles: titles,
        tags: tags,
        depth: WorldWikiDepth.full,
      );
      expect(
        gaps,
        isEmpty,
        reason:
            'a thin place with no pages filed under it is not a gap the catalog can fill',
      );
    });
  });
}
