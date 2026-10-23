// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from wiki studio: tools gate, climate off, K signed cards → K entries,
// abort does not save, full article not the chat 3500 clip. Chat clerk cap
// stays 3.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

String _tiddlyFixture() {
  final store = jsonEncode([
    {
      'title': 'Ceolwynn',
      'text': 'A singer of the Alnhama Republic. ' * 200,
      'type': 'text/vnd.tiddlywiki',
      'tags': ['Characters', 'Alnhama Republic'],
    },
    {
      'title': 'Alnhama',
      'text': 'The Alnhama Republic is a coastal city-state.',
      'type': 'text/vnd.tiddlywiki',
      'tags': ['Nations', 'Alnhama Republic'],
    },
    {
      'title': 'River Faith',
      'text': 'The temple of the river faith stands on the quay.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': '3 On Climate, Wind, and Currents',
      'text': 'A hidden warm current keeps the southern seas livable. ' * 40,
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'Chapter 1: Ceolwynn',
      'text': 'A draft of the singer on the quay.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': 'Alnhama (draft)',
      'text': 'Notes toward the coastal city-state.',
      'type': 'text/vnd.tiddlywiki',
    },
    {
      'title': r'$:/core',
      'text': 'system kernel',
      'type': 'text/vnd.tiddlywiki',
    },
    {'title': 'Ceolwynn.png', 'text': 'iVBORw0KGgo=', 'type': 'image/png'},
    {'title': 'Image Gallery', 'text': 'pics', 'type': 'text/vnd.tiddlywiki'},
  ]);
  return '<!doctype html><html><body>'
      '<script class="tiddlywiki-tiddler-store" type="application/json">'
      '$store'
      '</script></body></html>';
}

WikiSearchService _wiki() {
  return WikiSearchService(
    getBaseUrl: () => 'https://quietoak.github.io/NeokosmosWiki/',
    sendRequest: (request) async {
      if (request.url.path.endsWith('api.php')) {
        return http.Response('nope', 404);
      }
      return http.Response(_tiddlyFixture(), 200);
    },
  );
}

List<Map<String, dynamic>> _homemadeCards() => [
  {
    'name': "Baker's Street",
    'keys': ["Baker's Street", 'the street'],
    'role': 'hub',
    'sourceTitles': ['Alnhama'],
  },
  {
    'name': 'The River Faith',
    'keys': ['River Faith'],
    'role': 'hub',
    'sourceTitles': ['River Faith'],
    'group': 'river-faith',
  },
  {
    'name': 'Mira the Scout',
    'keys': ['Mira'],
    'role': 'leaf',
    'sourceTitles': ['Ceolwynn'],
    'group': 'river-faith',
  },
];

class _ToolsLlm extends LLMService {
  int writeCalls = 0;
  int scoutCalls = 0;
  bool returnNull = false;
  bool climateNull = false;
  String lastPrompt = '';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    lastPrompt = params.prompt;
    if (returnNull) return null;
    final names = [
      for (final t in tools)
        if (t['function'] is Map)
          (t['function'] as Map)['name']?.toString() ?? '',
    ];
    if (names.contains(kWorldScoutToolName)) {
      scoutCalls++;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {'cards': _homemadeCards()},
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldClimateToolName)) {
      writeCalls++;
      if (climateNull) return null;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldClimateToolName,
            arguments: {
              'displayName': 'Southern current',
              'description': 'Warm sea under the hull.',
              'feel': 'Mild winters, salt air.',
              'diurnalAmplitude': 0.85,
              'seasonLabels': {
                'winter': 'Brief Frost',
                'spring': 'Gulf Rise',
                'summer': 'High Current',
                'autumn': 'Trade Winds',
              },
              'baseTemp': {'winter': 2, 'spring': 3, 'summer': 4, 'autumn': 3},
              'weights': {
                'winter': [32, 22, 16, 12, 12, 4, 2],
                'spring': [38, 22, 12, 10, 14, 4, 0],
                'summer': [48, 20, 8, 6, 10, 8, 0],
                'autumn': [36, 22, 14, 10, 14, 4, 0],
              },
              'loreCards': [
                {
                  'name': 'Warm current',
                  'keys': ['warm current', 'Sea of Neokosmos'],
                  'content':
                      'A hidden warm current keeps the southern seas livable. Lands at this latitude elsewhere are ice. The gulf pulls that heat inland.',
                },
              ],
            },
          ),
        ],
        text: '',
      );
    }
    writeCalls++;
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final c in _homemadeCards())
                {
                  'name': c['name'],
                  'keys': c['keys'],
                  'content': 'A baker on the quay keeps the oven lit for them.',
                },
            ],
          },
        ),
      ],
      text: '',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

List<WorldProposedCard> _signed(WorldScoutResult scout, Iterable<int> idx) {
  return [for (final i in idx) scout.proposed[i]];
}

class _PlacesLlm extends LLMService {
  _PlacesLlm({this.flatMode = false});
  final bool flatMode;
  String lastScoutPrompt = '';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final t in tools)
        if (t['function'] is Map)
          (t['function'] as Map)['name']?.toString() ?? '',
    ];
    if (names.contains(kWorldScoutToolName)) {
      lastScoutPrompt = params.prompt;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {
              'cards': [
                for (final c in _homemadeCards())
                  if (c['name'] == 'Mira the Scout')
                    {...c, 'place': 'Alnhama Republic'}
                  else
                    c,
              ],
              if (!flatMode)
                'places': [
                  {
                    'name': 'Alnhama Republic',
                    'keys': 'Alnhama',
                    'sourceTitles': ['Alnhama'],
                    'climateHint': 'coastal city-state, mild seas',
                  },
                ],
            },
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldPlaceProfileToolName)) {
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldPlaceProfileToolName,
            arguments: {
              'description': 'A coastal city-state of shipwrights and singers.',
              'biome': _biomeJson('Coastal mild'),
            },
          ),
        ],
        text: '',
      );
    }
    // Lore batch: echo one entry per card, like _ToolsLlm.
    final cards = _cardsFromPrompt(params.prompt);
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final name in cards)
                {
                  'name': name,
                  'keys': [name],
                  'content': 'A citizen of the quay keeps the lamps lit. ' * 8,
                },
            ],
          },
        ),
      ],
      text: '',
    );
  }

  /// The batch prompt lists card names on 'CARD n:' lines; mirror what
  /// the real contract must answer so name-matching has something to
  /// match (the same honesty as _ToolsLlm answering the fixed shelf).
  List<String> _cardsFromPrompt(String prompt) {
    final all = _homemadeCards().map((c) => c['name']!.toString()).toList();
    return [
      for (final n in all)
        if (prompt.contains(n)) n,
    ];
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'places-test';
}

Map<String, dynamic> _biomeJson(String displayName) => {
  'displayName': displayName,
  'description': 'Mild seas, salt air.',
  'feel': 'Wind off the water.',
  'diurnalAmplitude': 0.8,
  'seasonLabels': {
    'winter': 'Wet Season',
    'spring': 'Fresh Water',
    'summer': 'Long Tide',
    'autumn': 'Return Fair',
  },
  'baseTemp': {'winter': 2, 'spring': 3, 'summer': 4, 'autumn': 3},
  'weights': {
    'winter': [30, 24, 18, 12, 10, 4, 2],
    'spring': [36, 22, 14, 10, 12, 4, 2],
    'summer': [46, 20, 10, 6, 10, 6, 2],
    'autumn': [34, 24, 16, 10, 10, 4, 2],
  },
};

void main() {
  test('chat clerk cap is still 3', () {
    expect(kClerkMaxDispatchRounds, 3);
  });

  test('chat wiki_search still asks for 3 hits', () {
    final uri = mediawikiSearchUri(
      Uri.parse('https://bleach.fandom.com'),
      'aizen',
    );
    expect(uri.queryParameters['srlimit'], '3');
  });

  test('tools gate follows chat\'s tool check, never the file name', () {
    WorldToolsGate gate(
      ToolCallSupport support, {
      bool testing = false,
      bool ready = true,
    }) => worldFromWikiToolsGate((
      support: support,
      testing: testing,
      backendReady: ready,
    ));

    expect(gate(ToolCallSupport.supported), WorldToolsGate.ready);
    expect(
      gate(ToolCallSupport.supported, ready: false),
      WorldToolsGate.notRunning,
    );
    expect(
      gate(ToolCallSupport.untested, testing: true),
      WorldToolsGate.checking,
    );
    expect(gate(ToolCallSupport.unsupported), WorldToolsGate.failed);
    expect(
      gate(ToolCallSupport.untested, ready: false),
      WorldToolsGate.notRunning,
    );
    expect(gate(ToolCallSupport.untested), WorldToolsGate.notChecked);
    for (final g in WorldToolsGate.values) {
      final copy = worldFromWikiToolsCopy(g);
      expect(copy == null, g == WorldToolsGate.ready, reason: g.name);
    }
    expect(worldFromWikiToolsCanRetest(WorldToolsGate.notChecked), isTrue);
    expect(worldFromWikiToolsCanRetest(WorldToolsGate.failed), isFalse);
  });

  test('climate off writes no biome json; recursion is on', () {
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'A notebook world.',
      entries: const [],
    );
    expect(world.climateEnabled, isFalse);
    expect(world.biomeJson, isNull);
    expect(world.biomeId, isNull);
    expect(world.lorebook.recursiveScanning, isTrue);
    expect(world.lorebook.scanDepth, 10);
    expect(world.lorebook.tokenBudget, 2800);
    final json = world.toJson();
    expect(json.containsKey('biome_json'), isFalse);
    expect(json.containsKey('biome_id'), isFalse);
    expect(json.containsKey('place_traits'), isFalse);
    expect(json['climate_enabled'], isFalse);
    expect(json['lorebook']['recursive_scanning'], isTrue);
  });

  test('skip \$:/ media galleries', () {
    expect(skipWikiStudioTitle(r'$:/core'), isTrue);
    expect(skipWikiStudioTitle('Ceolwynn.png'), isTrue);
    expect(skipWikiStudioTitle('Image Gallery'), isTrue);
    expect(skipWikiStudioTitle('File:Map.png'), isTrue);
    expect(skipWikiStudioTitle('Ceolwynn'), isFalse);
  });

  test('scan skips junk and logs catalog size', () async {
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: _ToolsLlm());
    final catalog = await engine.scan();
    expect(catalog.backend, WikiBackend.tiddly);
    expect(catalog.titles, containsAll(['Ceolwynn', 'Alnhama', 'River Faith']));
    expect(catalog.titles, isNot(contains(r'$:/core')));
    expect(catalog.titles, isNot(contains('Ceolwynn.png')));
    expect(catalog.titles, isNot(contains('Image Gallery')));
  });

  test(
    'wiki_page chat clip stays 3500; studio full article is longer',
    () async {
      final wiki = _wiki();
      final clipped = await wiki.getArticle('Ceolwynn');
      expect(clipped.ok, isTrue);
      expect(clipped.snippet.length, lessThanOrEqualTo(kWikiInjectCharCap));
      final full = await wiki.getArticleFull('Ceolwynn');
      expect(full.ok, isTrue);
      expect(full.snippet.length, greaterThan(kWikiInjectCharCap));
    },
  );

  test('scout proposes cards from Tiddly titles, not one per page', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final result = await engine.scout(
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    expect(result.catalog.titles.length, greaterThan(result.proposed.length));
    expect(result.proposed, hasLength(3));
    expect(llm.scoutCalls, 1);
    expect(llm.writeCalls, 0);
    expect(result.proposed.map((c) => c.group), contains('river-faith'));
    expect(llm.lastPrompt, contains(kWorldScoutPrompt));
  });

  test('K signed cards → K lorebook entries, not wiki title count', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    final catalogSize = scout.catalog.titles.length;
    expect(catalogSize, greaterThan(2));
    final entries = await engine.write(
      _signed(scout, [0, 2]),
      worldName: 'The quay',
      premise: 'A coastal republic.',
    );
    expect(entries, hasLength(2));
    expect(llm.writeCalls, 1);
    expect(entries.length, isNot(catalogSize));
    expect(engine.aborted, isFalse);
    expect(entries.every((e) => e.depth == 4), isTrue);
  });

  test('same signed name is not written twice', () async {
    final llm = _ToolsLlm();
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    final entries = await engine.write(
      [scout.proposed.first, scout.proposed.first],
      worldName: 'The quay',
      premise: 'x',
    );
    expect(entries, hasLength(1));
    expect(llm.writeCalls, 1);
  });

  test('abort stops the loop and does not save a World', () async {
    final llm = _ToolsLlm();
    final scout = await WorldFromWikiEngine(
      wiki: _wiki(),
      llm: llm,
    ).scout(worldName: 'The quay', premise: 'x');
    late WorldFromWikiEngine engine;
    engine = WorldFromWikiEngine(
      wiki: _wiki(),
      llm: llm,
      onProgress: (_) => engine.abort(),
    );
    final entries = await engine.write(
      scout.proposed,
      worldName: 'The quay',
      premise: 'x',
    );
    expect(engine.aborted, isTrue);
    expect(entries, isEmpty);
    expect(
      worldFromWikiCanSave(
        aborted: engine.aborted,
        lorebooksOn: true,
        entries: entries,
      ),
      isFalse,
    );
    final leftover = [
      LorebookEntry(name: 'Partial', keys: const ['partial'], content: 'x'),
    ];
    expect(
      worldFromWikiCanSave(aborted: true, lorebooksOn: true, entries: leftover),
      isFalse,
      reason: 'abort refuses save even if a batch already produced cards',
    );
  });

  test('climate on + miss does not enable climate on the World', () async {
    final llm = _ToolsLlm()..climateNull = true;
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    final entries = await engine.write(
      _signed(scout, [0]),
      worldName: 'The quay',
      premise: 'x',
      climateEnabled: true,
    );
    expect(entries, isNotEmpty);
    expect(engine.biome, isNull);
    final world = worldFromWikiDraft(
      name: 'The quay',
      description: 'x',
      entries: entries,
      climateEnabled: true,
      biome: engine.biome,
    );
    expect(world.climateEnabled, isFalse);
    expect(world.biomeId, isNull);
    expect(world.biomeJson, isNull);
  });

  test('tools miss does not dump the article as a lorebook card', () async {
    final llm = _ToolsLlm()..returnNull = true;
    final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
    final scout = await engine.scout(worldName: 'The quay', premise: 'x');
    expect(scout.proposed, isEmpty);
    final entries = await engine.write(
      [
        WorldProposedCard(
          name: 'Mira the Scout',
          keys: const ['Mira'],
          role: WorldCraftRole.leaf,
          sourceTitles: const ['Ceolwynn'],
        ),
      ],
      worldName: 'The quay',
      premise: 'x',
    );
    expect(entries, isEmpty);
  });

  test('lore content is clipped to 330; comma keys split', () {
    final long = 'Word. ' * 80;
    final parsed = parseWorldLoreToolCall({
      'name': 'Allevia',
      'keys': ['Sol Allevia, Order of Sol Allevia, sisters'],
      'content': long,
    })!;
    expect(parsed.content.length, lessThanOrEqualTo(kWorldLoreContentMax));
    expect(
      parsed.keys,
      containsAll(['Sol Allevia', 'Order of Sol Allevia', 'sisters']),
    );
  });
  group('slice 8 — places from tags', () {
    test('the scout prompt shows the tags and the places come back', () async {
      final llm = _PlacesLlm();
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
      final result = await engine.scout(worldName: 'Neokosmos', premise: 'p');
      // A nation that exists ONLY as a tag must reach the model's eyes.
      expect(
        llm.lastScoutPrompt,
        contains('Ceolwynn [Characters, Alnhama Republic]'),
      );
      expect(result.places.map((p) => p.name), contains('Alnhama Republic'));
      final place = result.places.firstWhere(
        (p) => p.name == 'Alnhama Republic',
      );
      expect(place.climateHint, contains('coastal'));
      // Cards keep their place; an unknown one rides the root.
      final byName = {for (final c in result.proposed) c.name: c};
      expect(byName['Mira the Scout']!.place, 'Alnhama Republic');
      expect(byName["Baker's Street"]!.place, isEmpty);
    });

    test('writeTree writes a place book with its OWN biome and keeps the '
        'root book for root cards', () async {
      final llm = _PlacesLlm();
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm);
      final result = await engine.scout(worldName: 'Neokosmos', premise: 'p');
      final signed = [
        for (final c in result.proposed)
          WorldProposedCard(
            name: c.name,
            keys: c.keys,
            role: c.role,
            sourceTitles: c.sourceTitles,
            group: c.group,
            place: c.place,
          ),
      ];
      final tree = await engine.writeTree(
        signed,
        places: result.places,
        worldName: 'Neokosmos',
        premise: 'p',
        climateEnabled: true,
        climatePlaces: {'alnhama republic'},
      );
      expect(tree.isFlat, isFalse);
      final place = tree.places.single;
      expect(place.name, 'Alnhama Republic');
      expect(place.hasClimate, isTrue, reason: 'flagged → its own biome');
      expect(place.biome!['displayName'], 'Coastal mild');
      expect(place.description, contains('city-state'));
      expect(
        place.entries.map((e) => e.name),
        contains('Mira the Scout'),
        reason: 'the place holds its characters\' cards',
      );
      expect(
        tree.root.entries.map((e) => e.name),
        contains("Baker's Street"),
        reason: 'root cards stay at the root',
      );
      expect(
        tree.root.entries.map((e) => e.name),
        isNot(contains('Mira the Scout')),
      );
    });

    test(
      'an untagged wiki still yields ONE flat world exactly as today',
      () async {
        // Same engine, places empty (what an untagged wiki produces): the
        // tree write must return the flat product — design §9.7's pinned
        // unchanged path, asserted by parity with `write`.
        final flatLlm = _ToolsLlm();
        final flat = await WorldFromWikiEngine(wiki: _wiki(), llm: flatLlm)
            .write(
              _homemadeCards()
                  .map(WorldProposedCard.tryParse)
                  .nonNulls
                  .toList(),
              worldName: 'W',
              premise: 'p',
            );
        final treeLlm = _PlacesLlm(flatMode: true);
        final tree = await WorldFromWikiEngine(wiki: _wiki(), llm: treeLlm)
            .writeTree(
              _homemadeCards()
                  .map(WorldProposedCard.tryParse)
                  .nonNulls
                  .toList(),
              places: const [],
              worldName: 'W',
              premise: 'p',
            );
        expect(tree.isFlat, isTrue);
        expect(
          tree.root.entries.map((e) => e.name).toList(),
          flat.map((e) => e.name).toList(),
        );
      },
    );
  });

  group('scout failures say why', () {
    test('the scout asks for the full reply budget', () async {
      final llm = _OutcomeLlm(
        response: const LlmToolResponse(
          calls: [],
          text: '',
          finishReason: 'stop',
        ),
      );
      await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: llm,
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(llm.lastMaxLength, kWorldScoutMaxTokens);
      expect(
        kWorldScoutMaxTokens,
        greaterThanOrEqualTo(8192),
        reason:
            '40 cards + 8 places is ~3.5K tokens of JSON before any '
            'thinking; 3072 cut Qwen3.6 off mid list (oMLX finish_reason='
            'length, incomplete_tool_call).',
      );
    });

    test(
      'a reply cut at the token limit says so, not "clearer premise"',
      () async {
        final result = await WorldFromWikiEngine(
          wiki: _wiki(),
          llm: _OutcomeLlm(
            response: const LlmToolResponse(
              calls: [],
              text: '',
              finishReason: 'length',
            ),
          ),
        ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
        expect(result.proposed, isEmpty);
        expect(result.failure, contains('ran out of room'));
        expect(result.failure, contains('$kWorldScoutMaxTokens-token'));
        expect(result.failure, isNot(contains('clearer premise')));
      },
    );

    test('a busy server says so and keeps the wiki out of it', () async {
      final result = await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _OutcomeLlm(
          error: LlmToolTransportException(
            'tool call HTTP 502 (server busy/unavailable)',
          ),
        ),
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(result.proposed, isEmpty);
      expect(result.failure, contains('HTTP 502'));
      expect(result.failure, contains('wait a moment'));
      expect(result.failure, contains('The wiki is fine'));
    });

    test('plain text instead of a tool call says so', () async {
      final result = await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _OutcomeLlm(
          response: const LlmToolResponse(
            calls: [],
            text: 'Here are some cards: Ceolwynn, Alnhama…',
            finishReason: 'stop',
          ),
        ),
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(result.failure, contains('plain text'));
    });

    test('a card list that will not parse says so', () async {
      final result = await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _OutcomeLlm(
          response: const LlmToolResponse(
            calls: [LlmToolCall(name: kWorldScoutToolName, arguments: {})],
            text: '',
            finishReason: 'tool_calls',
          ),
        ),
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(result.failure, contains('could not be read'));
    });

    test('no answer at all says so', () async {
      final result = await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _OutcomeLlm(),
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(result.failure, contains('did not answer with a card list'));
    });

    test('a real card list leaves failure null', () async {
      final result = await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _ToolsLlm(),
      ).scout(worldName: 'The quay', premise: 'A coastal republic.');
      expect(result.proposed, isNotEmpty);
      expect(result.failure, isNull);
    });
  });
}

/// One scripted scout answer: a fixed response, or a thrown error.
class _OutcomeLlm extends LLMService {
  _OutcomeLlm({this.response, this.error});
  final LlmToolResponse? response;
  final Object? error;
  int? lastMaxLength;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    lastMaxLength = params.maxLength;
    final err = error;
    if (err != null) throw err;
    return response;
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}
