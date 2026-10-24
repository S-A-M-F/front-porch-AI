// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// World from Character (docs/design/world-from-character.md): the card's
// sections become titles, the chat is skimmed into an index the scout
// reads, each name's article is the lines that name it, the main character
// and the user are never titles, the persona is a macro, the short-chat
// floor warns, and the three modes gate what the scout may keep.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/story/story_chat_sources.dart';
import 'package:front_porch_ai/services/web/facade/world_character_source.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

CharacterCard _ines() => CharacterCard(
  name: 'Ines Calder',
  description: 'Ines runs the last open tea rooms in Bletchfield.',
  personality: 'Dry, patient, keeps a ledger of favours.',
  scenario: '{{char}} keeps the Salt Garden shut through the quarantine.',
  firstMessage: 'The curfew bell rings at dusk. {{char}} looks up.',
  lorebook: Lorebook(
    entries: [
      LorebookEntry(
        name: 'Salt leaf',
        keys: const ['salt leaf'],
        content: 'A bitter herb dried behind the tea rooms.',
      ),
    ],
  ),
);

const _chat = [
  ('Sam', 'We walked down to the Ropewalk at dusk, Sam shivering.'),
  ('Ines Calder', 'The Harbourmaster keeps the count from the Ropewalk door.'),
  ('Sam', 'Is the Salt Garden still shut?'),
  ('Ines Calder', 'Until the Harbourmaster hands back the key, yes.'),
  ('Sam', 'Sleet again. A north wind off the harbour.'),
  ('Ines Calder', 'Tomas slept in the Ropewalk shed last night.'),
];

WorldChatRecord _record() => WorldChatRecord(
  characterName: 'Ines Calder',
  characterId: 'ines_calder',
  sessionId: 's1',
  summary: 'The quarantine has lifted; the Salt Garden is still shut.',
  userName: 'Sam',
  lines: [
    for (var i = 0; i < _chat.length; i++)
      (
        index: i,
        position: i,
        sender: _chat[i].$1 == 'Sam'
            ? kWorldUserMacro
            : worldPersonaToMacro(_chat[i].$1, 'Sam'),
        text: worldPersonaToMacro(_chat[i].$2, 'Sam'),
      ),
  ],
);

/// Answers the Skim, the scout and the write with canned shelves; records
/// every prompt so a test can read what the model was told.
class _Llm extends LLMService {
  final List<String> prompts = [];
  final Set<String> toolsAsked = {};

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'character-test';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    final names = [
      for (final t in tools)
        if (t['function'] is Map)
          (t['function'] as Map)['name']?.toString() ?? '',
    ];
    toolsAsked.addAll(names);
    if (names.contains(kWorldSkimToolName)) {
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldSkimToolName,
            arguments: {
              'names': [
                {
                  'name': 'The Ropewalk',
                  'kind': 'place',
                  'aliases': ['Ropewalk', 'the shed'],
                  'parent': 'Bletchfield',
                  'note': 'the rope shed turned soup line',
                },
                {'name': 'The Harbourmaster', 'kind': 'person'},
                {'name': 'Salt Garden', 'kind': 'place'},
                {'name': 'Ines Calder', 'kind': 'person'},
                {'name': 'Sam', 'kind': 'person'},
                {'name': 'the quarantine', 'kind': 'nonsense'},
              ],
              'weather': 'sleet, a north wind',
            },
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldScoutToolName)) {
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {
              'cards': [
                {
                  'name': 'The Ropewalk',
                  'role': 'hub',
                  'kind': 'place',
                  'sourceTitles': ['The Ropewalk'],
                },
                {
                  'name': 'The Harbourmaster',
                  'role': 'leaf',
                  'kind': 'person',
                  'sourceTitles': ['The Harbourmaster'],
                },
                {
                  'name': 'Ghost Pier',
                  'role': 'leaf',
                  'kind': 'place',
                  'sourceTitles': ['Ghost Pier'],
                },
              ],
            },
          ),
        ],
        text: '',
      );
    }
    return null;
  }
}

void main() {
  group('the short-chat floor', () {
    test('chips a chat under 40 as too short and under 100 as short', () {
      expect(worldChatLengthChip(14), 'too short to skim');
      expect(worldChatLengthChip(39), 'too short to skim');
      expect(worldChatLengthChip(40), 'short chat');
      expect(worldChatLengthChip(99), 'short chat');
      expect(worldChatLengthChip(100), '');
      expect(worldChatLengthChip(0), '');
    });

    test('warns at 39, 99 and 199 messages and says nothing at 200', () {
      String? warn(int n, WorldBuildMode m, WorldWikiDepth d) =>
          worldChatLengthWarning(n, mode: m, depth: d);
      expect(
        warn(39, WorldBuildMode.factsOnly, WorldWikiDepth.quick),
        contains('almost nothing to skim'),
      );
      expect(
        warn(99, WorldBuildMode.factsOnly, WorldWikiDepth.quick),
        contains('Facts only will give a thin shelf'),
      );
      expect(
        warn(99, WorldBuildMode.creative, WorldWikiDepth.quick),
        contains('invents around it'),
      );
      expect(
        warn(199, WorldBuildMode.factsOnly, WorldWikiDepth.full),
        contains('Quick is the better fit'),
      );
      expect(warn(199, WorldBuildMode.factsOnly, WorldWikiDepth.quick), isNull);
      expect(warn(200, WorldBuildMode.factsOnly, WorldWikiDepth.full), isNull);
      expect(warn(0, WorldBuildMode.factsOnly, WorldWikiDepth.full), isNull);
      expect(
        warn(76, WorldBuildMode.faithful, WorldWikiDepth.quick),
        contains('76 messages (about 38 turns)'),
      );
    });

    test('a character\'s 1:1 chats are the rows with their id', () {
      final rows = [
        StoryChatSourceRow(
          characterId: 'c1',
          characterName: 'Ines',
          sessionId: 's1',
          sessionName: 'Winter',
          summary: '',
          createdAt: DateTime(2026, 10, 12),
          messageCount: 212,
        ),
        StoryChatSourceRow(
          characterId: 'c2',
          characterName: 'Tomas',
          sessionId: 's2',
          sessionName: 'Docks',
          summary: '',
          createdAt: DateTime(2026, 9, 1),
          messageCount: 40,
        ),
      ];
      expect(worldChatRowsFor(rows, 'c1').map((r) => r.sessionId), ['s1']);
    });

    test('a chat yields fewer cards than a wiki and never offers Deep', () {
      expect(worldCharacterCardTarget(WorldWikiDepth.quick), 15);
      expect(worldCharacterCardTarget(WorldWikiDepth.full), 30);
      expect(worldCharacterDepth(WorldWikiDepth.deep), WorldWikiDepth.full);
      expect(worldCharacterDepth(WorldWikiDepth.quick), WorldWikiDepth.quick);
    });
  });

  group('the card as titles', () {
    test('each non-empty section and each lore entry is a title', () {
      final sections = worldCardSections(_ines());
      expect(sections.map((s) => s.title), [
        'Description',
        'Personality',
        'Scenario',
        'First greeting',
        'Salt leaf',
      ]);
      expect(
        sections.firstWhere((s) => s.title == 'Scenario').text,
        startsWith('Ines Calder keeps the Salt Garden'),
      );
      expect(sections.last.tag, 'card-lore');
    });

    test('the persona becomes the user macro, whole words only', () {
      expect(
        worldPersonaToMacro(
          "Sam shivered; Samantha didn't. Sam's coat.",
          'Sam',
        ),
        "{{user}} shivered; Samantha didn't. {{user}}'s coat.",
      );
      expect(worldPersonaToMacro('no names here', ''), 'no names here');
    });
  });

  group('the Skim', () {
    test('never lists the character or the user and maps odd kinds', () {
      final got = parseWorldSkimCalls(
        [
          const LlmToolCall(
            name: kWorldSkimToolName,
            arguments: {
              'names': [
                {'name': 'Ines Calder', 'kind': 'person'},
                {'name': 'Ines', 'kind': 'person'},
                {'name': 'Sam', 'kind': 'person'},
                {'name': '{{user}}', 'kind': 'person'},
                {
                  'name': 'The Ropewalk',
                  'kind': 'place',
                  'aliases': 'Ropewalk, Sam',
                },
                {'name': 'the quarantine', 'kind': 'era'},
              ],
              'weather': 'sleet',
            },
          ),
        ],
        exclude: worldSkimExclusions('Ines Calder', 'Sam'),
        part: 0,
      );
      expect(got.names.map((n) => n.name), ['The Ropewalk', 'the quarantine']);
      expect(got.names.first.aliases, ['Ropewalk']);
      expect(got.names.last.kind, 'concept');
      expect(got.weather, 'sleet');
    });

    test('merges the same thing under two spellings and ranks by mentions', () {
      final merged = mergeWorldSkimNames([
        [
          WorldSkimName(
            name: 'The Ropewalk',
            kind: 'place',
            aliases: const ['Ropewalk'],
            parts: {0},
          ),
          WorldSkimName(name: 'Salt Garden', kind: 'place', parts: {0}),
        ],
        [
          WorldSkimName(
            name: 'Ropewalk',
            kind: 'place',
            aliases: const ['the shed'],
            parent: 'Bletchfield',
            parts: {1},
          ),
        ],
        [
          WorldSkimName(name: 'the shed', kind: 'place', parts: {2}),
        ],
      ]);
      expect(merged.map((n) => n.name), ['The Ropewalk', 'Salt Garden']);
      expect(merged.first.mentions, 3);
      expect(merged.first.aliases, containsAll(['Ropewalk', 'the shed']));
      expect(merged.first.parent, 'Bletchfield');
      expect(merged.first.parts, {0, 1, 2});
    });
  });

  group('the character source', () {
    test(
      'Card only needs no model: the sections are the whole index',
      () async {
        final source = CharacterChatWorldSource(
          card: _ines(),
          record: WorldChatRecord(
            characterName: 'Ines Calder',
            characterId: 'ines_calder',
          ),
        );
        final catalog = await source.catalog();
        expect(catalog.titles, [
          'Description',
          'Personality',
          'Scenario',
          'First greeting',
          'Salt leaf',
        ]);
        expect(catalog.tagsByTitle['Salt leaf'], ['card-lore']);
        expect(await source.article('Scenario'), contains('Ines Calder keeps'));
        expect(await source.article('Nowhere'), '');
        expect(await source.climateTitles(), isEmpty);
        expect(await source.climateTitles(allowGuess: true), [
          'Description',
          'Scenario',
        ]);
        expect(source.label, "Ines Calder's card");
        expect(source.offersDeep, isFalse);
      },
    );

    test('with a chat the Skim builds the index and each name reads its '
        'lines, with the persona as a macro', () async {
      final llm = _Llm();
      final source = CharacterChatWorldSource(card: _ines(), record: _record());
      source.bind(
        llm: llm,
        budget: const WorldWikiBudget(32768),
        retryPause: Duration.zero,
      );
      final catalog = await source.catalog();
      expect(llm.toolsAsked, contains(kWorldSkimToolName));
      // Skim names first (the character and the user dropped, the odd
      // kind kept as a concept), the card's sections after.
      expect(catalog.titles.take(4), [
        'The Ropewalk',
        'The Harbourmaster',
        'Salt Garden',
        'the quarantine',
      ]);
      expect(catalog.titles, contains('Scenario'));
      expect(catalog.titles, isNot(contains('Ines Calder')));
      expect(catalog.titles, isNot(contains('Sam')));
      expect(catalog.ranked, isTrue);
      expect(catalog.tagsByTitle['The Ropewalk'], [
        'place',
        'Bletchfield',
        'chat',
      ]);
      expect(catalog.tagsByTitle['The Harbourmaster'], ['character', 'chat']);

      final article = await source.article('Ropewalk');
      expect(article, contains('the rope shed turned soup line'));
      expect(article, contains('Lies inside Bletchfield.'));
      expect(article, contains('{{user}}: We walked down to the Ropewalk'));
      expect(article, contains('Tomas slept in the Ropewalk shed'));
      expect(article, isNot(contains('Sam')));
      expect(article, isNot(contains('Is the Salt Garden still shut')));
      // The Skim prompt itself never saw the persona's name either.
      expect(llm.prompts.first, isNot(contains('Sam ')));
      expect(llm.prompts.first, contains('never list them'));

      expect(await source.climateTitles(), [kWorldChatWeatherTitle]);
      expect(await source.article(kWorldChatWeatherTitle), contains('sleet'));
      expect(source.label, "Ines Calder's chat");

      // A second catalog reuses the Skim: scout and write share one.
      final asked = llm.prompts.length;
      await source.catalog();
      expect(llm.prompts.length, asked);
    });

    test('the source needs a bound run before it can skim', () {
      final source = CharacterChatWorldSource(card: _ines(), record: _record());
      expect(source.catalog(), throwsStateError);
    });
  });

  group('the engine on a character source', () {
    Future<WorldScoutResult> scout(WorldBuildMode mode) async {
      final llm = _Llm();
      final source = CharacterChatWorldSource(card: _ines(), record: _record());
      final engine = WorldFromWikiEngine(
        source: source,
        llm: llm,
        depth: WorldWikiDepth.quick,
        mode: mode,
        contextTokens: 32768,
      )..retryPause = Duration.zero;
      return engine.scout(worldName: 'Bletchfield', premise: 'A harbour town');
    }

    test(
      'Facts only and Faithful drop a card the index does not know',
      () async {
        for (final mode in [
          WorldBuildMode.factsOnly,
          WorldBuildMode.faithful,
        ]) {
          final r = await scout(mode);
          expect(r.proposed.map((c) => c.name), [
            'The Ropewalk',
            'The Harbourmaster',
          ], reason: mode.label);
          expect(r.proposed.any((c) => c.invented), isFalse);
        }
      },
    );

    test('Creative keeps it, marked invented', () async {
      final r = await scout(WorldBuildMode.creative);
      expect(r.proposed.map((c) => c.name), [
        'The Ropewalk',
        'The Harbourmaster',
        'Ghost Pier',
      ]);
      final pier = r.proposed.last;
      expect(pier.invented, isTrue);
      expect(pier.toJson()['invented'], isTrue);
      expect(WorldProposedCard.tryParse(pier.toJson())!.invented, isTrue);
      expect(r.proposed.first.invented, isFalse);
      expect(r.proposed.first.toJson().containsKey('invented'), isFalse);
    });

    test('the shelf is sized for a chat, not a wiki', () {
      final source = CharacterChatWorldSource(card: _ines(), record: _record());
      expect(source.cardTarget(WorldWikiDepth.quick), 15);
      expect(source.scoutRange(WorldWikiDepth.full), (12, 30));
    });
  });

  group('the modes', () {
    test('only Creative fills, keeps the unsourced and guesses climate', () {
      expect(WorldBuildMode.factsOnly.fills, isFalse);
      expect(WorldBuildMode.faithful.fills, isFalse);
      expect(WorldBuildMode.creative.fills, isTrue);
      expect(WorldBuildMode.factsOnly.allowsUnsourced, isFalse);
      expect(WorldBuildMode.creative.allowsUnsourced, isTrue);
      expect(WorldBuildMode.faithful.guessesClimate, isFalse);
      expect(WorldBuildMode.creative.guessesClimate, isTrue);
      expect(WorldBuildModeX.fromName('faithful'), WorldBuildMode.faithful);
      expect(WorldBuildModeX.fromName('nope'), WorldBuildMode.factsOnly);
      expect(
        WorldBuildModeX.fromName(null, fallback: WorldBuildMode.creative),
        WorldBuildMode.creative,
      );
    });

    test('each mode says what it does and what it never does', () {
      for (final m in WorldBuildMode.values) {
        expect(m.does.length, greaterThan(20), reason: m.label);
        expect(m.never.length, greaterThan(20), reason: m.label);
        expect(m.writeRule, contains('{{user}}'));
      }
      expect(WorldBuildMode.factsOnly.addedLabel, 'beyond the lines');
      expect(WorldBuildMode.faithful.addedLabel, 'rounded out');
      expect(WorldBuildMode.creative.addedLabel, 'extrapolated');
    });

    test('an entry note carries what was added and says when nothing was '
        'written', () {
      const note = WorldEntryNote(
        tries: 1,
        passed: true,
        added: 'rounded out: the smell of tar',
      );
      expect(note.addedLabel, 'rounded out');
      expect(WorldEntryNote.fromJson(note.toJson())!.added, note.added);
      expect(
        worldEntryNoteCopy(note),
        'Passed first try · rounded out: the smell of tar',
      );
      expect(
        worldEntryNoteCopy(
          const WorldEntryNote(
            tries: 0,
            passed: false,
            problem: 'nothing in the chat to write this from',
          ),
        ),
        'Not written · nothing in the chat to write this from',
      );
      expect(
        const WorldEntryNote(
          tries: 1,
          passed: true,
        ).toJson().containsKey('added'),
        isFalse,
      );
    });
  });

  group('the relay source field', () {
    test('absent means the wiki; a character pick reads its mode and chat', () {
      expect(WorldSourcePick.fromBody({'wikiUrl': 'https://x'}), isNull);
      expect(
        WorldSourcePick.fromBody({
          'source': {'kind': 'wiki'},
        }),
        isNull,
      );
      final pick = WorldSourcePick.fromBody({
        'source': {
          'kind': 'character',
          'characterId': 'c1',
          'sessionId': 's1',
          'mode': 'faithful',
          'copyCardLore': true,
        },
      })!;
      expect(pick.characterId, 'c1');
      expect(pick.sessionId, 's1');
      expect(pick.mode, WorldBuildMode.faithful);
      expect(pick.copyCardLore, isTrue);
      // Facts only with a chat, Creative for Card only, when unsaid.
      expect(
        WorldSourcePick.fromBody({
          'source': {
            'kind': 'character',
            'characterId': 'c1',
            'sessionId': 's1',
          },
        })!.mode,
        WorldBuildMode.factsOnly,
      );
      expect(
        WorldSourcePick.fromBody({
          'source': {'kind': 'character', 'characterId': 'c1'},
        })!.mode,
        WorldBuildMode.creative,
      );
    });
  });
}
