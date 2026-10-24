// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from wiki studio: tools gate, climate off, K signed cards → K entries,
// abort does not save, full article not the chat 3500 clip. Chat clerk cap
// stays 3.

import 'dart:async';
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

  /// The scout's own prompt (the reviewer's comes after it now).
  String scoutPrompt = '';

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
      scoutPrompt = params.prompt;
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
    if (names.contains(kWorldShelfReviewToolName)) {
      return const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldShelfReviewToolName,
            arguments: {'pass': true, 'problems': []},
          ),
        ],
        text: '',
      );
    }
    if (names.contains(kWorldEntriesReviewToolName)) {
      // The entries reviewer passes everything; it is not a write.
      return const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldEntriesReviewToolName,
            arguments: {'verdicts': []},
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
                  // Two full sentences: the entry loop's gate sends a one-liner
                  // back for a rewrite, which is not what these tests count.
                  'content':
                      'A baker on the quay keeps the oven lit for them through '
                      'the long nights of the siege. Soldiers and scouts trade '
                      'news for bread at the back door, and nothing said there '
                      'leaves the room.',
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
    // Changed 2026-10-23: a failed verdict offers Check now too. A model
    // that answered in prose once (asked mid-load on oMLX) locked the wizard
    // until the user changed models; the old assertion pinned that lock.
    expect(worldFromWikiToolsCanRetest(WorldToolsGate.failed), isTrue);
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
    // Changed 2026-10-23: the shelf reviewer's call now follows the scout's,
    // so the last prompt is the review's; the scout's own prompt is pinned.
    expect(llm.scoutPrompt, contains(kWorldScoutPrompt));
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

  test(
    'a source title copied with its index tags still matches the catalog',
    () {
      // gemma-4 wrote "Quincy Blood War [Events, Fights]" for every card.
      expect(
        worldScoutBareTitle('Quincy Blood War [Events, Fights]'),
        'Quincy Blood War',
      );
      expect(worldScoutBareTitle('Plain Title'), 'Plain Title');
      expect(worldScoutBareTitle('[Bracketed] Title'), '[Bracketed] Title');
      final cards = parseWorldScoutToolCalls(
        [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {
              'cards': [
                {
                  'name': 'The Blood War',
                  'role': 'era',
                  'kind': 'event',
                  'sourceTitles': ['Quincy Blood War [Events, Fights]'],
                },
              ],
            },
          ),
        ],
        catalog: ['Quincy Blood War', 'Yhwach'],
      );
      expect(cards.single.sourceTitles, ['Quincy Blood War']);
      final place = WorldProposedPlace.tryParse({
        'name': 'Seireitei',
        'sourceTitles': ['Seireitei [Locations, Soul Society]'],
      })!;
      expect(place.sourceTitles, ['Seireitei']);
    },
  );

  test('an entry keeps at most eight keys', () {
    final parsed = parseWorldLoreToolCall({
      'name': 'Gotei 13',
      'keys': [for (var i = 0; i < 12; i++) 'key $i'],
      'content': 'The thirteen divisions hold the Seireitei. ' * 5,
    })!;
    expect(parsed.keys, hasLength(kWorldLoreKeysMax));
    expect(parsed.keys.first, 'key 0');
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
    // Changed 2026-10-23: the reply budget is no longer a constant. The
    // maintainer ruled the wizard must respect a context the user picks
    // (chat runs at 64K on oMLX; a fixed 8,192 "is not enough"), so the
    // scout now asks for whatever the wizard's context leaves after the
    // prompt. The old pin (budget == a constant >= 8192) is therefore false.
    test('the scout asks for what the wizard\'s context leaves', () async {
      final answer = const LlmToolResponse(
        calls: [],
        text: '',
        finishReason: 'stop',
      );
      final wide = _OutcomeLlm(response: answer);
      await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: wide,
        contextTokens: 65536,
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(
        wide.lastMaxLength,
        const WorldWikiBudget(
          65536,
        ).replyFor(wide.lastPrompt, floor: kWorldScoutReplyFloor),
      );
      expect(wide.lastMaxLength, greaterThan(50000));

      final narrow = _OutcomeLlm(response: answer);
      await WorldFromWikiEngine(
        wiki: _wiki(),
        llm: narrow,
      ).scout(worldName: 'Neokosmos', premise: 'A coastal republic.');
      expect(narrow.lastMaxLength, lessThan(kWorldWikiContextFloor));
      expect(narrow.lastMaxLength, greaterThanOrEqualTo(kWorldScoutReplyFloor));
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
        // Six titles is already under the smallest part, so the cut names
        // the wizard's context (the floor here) as the thing to raise.
        expect(result.failure, contains('16K'));
        expect(result.failure, contains('Book step'));
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

  group('depth and moment reach the prompts', () {
    test(
      'the scout prompt carries the depth range, the moment and its rule',
      () async {
        final llm = _ProseThenCallLlm(proseTimes: 0);
        await WorldScoutRunner(
          llm: llm,
          budget: const WorldWikiBudget(65536),
          depth: WorldWikiDepth.deep,
          moment: 'the night after the first invasion',
        ).run(
          titles: _ReviewLlm.titles,
          tags: const {},
          worldName: 'Bleach (TYBW)',
          premise: 'The war.',
        );
        final prompt = llm.prompts.first;
        expect(prompt, contains('Moment: the night after the first invasion'));
        expect(prompt, contains('50–80 cards.'));
        expect(prompt, contains('unknown to everyone'));
      },
    );

    test('the write header and rule carry the moment', () {
      final engine = WorldFromWikiEngine(
        wiki: _wiki(),
        llm: _ToolsLlm(),
        moment: 'the seventeen months',
      );
      expect(
        engine.writeHeader(worldName: 'B', premise: 'p', extraLore: ''),
        contains('Moment: the seventeen months'),
      );
      final plain = WorldFromWikiEngine(wiki: _wiki(), llm: _ToolsLlm());
      expect(
        plain.writeHeader(worldName: 'B', premise: 'p', extraLore: ''),
        isNot(contains('Moment:')),
      );
    });

    test(
      'the signed write payload accepts a deep shelf and still rejects a ToC',
      () {
        List<Map<String, dynamic>> cards(int n) => [
          for (var i = 0; i < n; i++)
            {
              'name': 'C$i',
              'role': 'leaf',
              'sourceTitles': ['T$i'],
              'signed': true,
            },
        ];
        expect(
          parseSignedWorldWriteCards(
            cards(150),
            max: WorldWikiDepth.deep.cardTarget,
          ),
          hasLength(150),
        );
        expect(
          parseSignedWorldWriteCards(cards(150)),
          isEmpty,
          reason: 'the default cap is the quick shelf',
        );
        expect(
          parseSignedWorldWriteCards(
            cards(500),
            max: WorldWikiDepth.deep.cardTarget,
          ),
          isEmpty,
        );
      },
    );
  });

  group('progress lines', () {
    test('a scout and a write say what they are doing, with cheek', () async {
      final lines = <String>[];
      final llm = _ToolsLlm();
      final engine = WorldFromWikiEngine(
        wiki: _wiki(),
        llm: llm,
        onProgress: lines.add,
      );
      final scout = await engine.scout(worldName: 'The quay', premise: 'x');
      expect(lines.first, 'Rummaging through the wiki…');
      expect(lines, contains(startsWith('Found ')));
      expect(lines.join('\n'), contains('Picking the ones that matter'));
      lines.clear();
      await engine.write(
        scout.proposed.take(2).toList(),
        worldName: 'The quay',
        premise: 'x',
        climateEnabled: true,
      );
      expect(lines, contains(startsWith('Reading up on ')));
      expect(lines, contains(startsWith('Writing card')));
      expect(lines, contains(startsWith('Reading 2 fresh entries')));
      expect(lines, contains('Checking the weather…'));
    });

    test('a stumble and a hang are said, not hidden', () async {
      WorldProposedCard card(String n) => WorldProposedCard(
        name: n,
        keys: [n],
        role: WorldCraftRole.leaf,
        sourceTitles: const ['Ceolwynn'],
      );
      final lines = <String>[];
      final flaky = _FlakyWriteLlm(failFirst: 1);
      final engine = WorldFromWikiEngine(
        wiki: _wiki(),
        llm: flaky,
        onProgress: lines.add,
      )..retryPause = Duration.zero;
      await engine.write(
        [card('Schrift')],
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      expect(lines, contains(startsWith('The server stumbled')));

      lines.clear();
      final hung = _FlakyWriteLlm(failFirst: 0, hangTimes: 1);
      final again = WorldFromWikiEngine(
        wiki: _wiki(),
        llm: hung,
        onProgress: lines.add,
      )
        ..retryPause = Duration.zero
        ..callTimeout = const Duration(milliseconds: 50);
      await again.write(
        [card('Schrift')],
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      expect(lines, contains(startsWith('No answer in ')));
    });

    test('elapsed time reads as a clock face', () {
      expect(worldElapsedLabel(Duration.zero), '0:00');
      expect(worldElapsedLabel(const Duration(seconds: 42)), '0:42');
      expect(worldElapsedLabel(const Duration(minutes: 12, seconds: 5)), '12:05');
      expect(
        worldElapsedLabel(const Duration(hours: 1, minutes: 3, seconds: 9)),
        '1:03:09',
      );
    });
  });

  group('chain, don\'t catalogue', () {
    test('a write sees the whole shelf and is told to name the cards a hub '
        'should pull; the reviewer holds it to that', () async {
      WorldProposedCard card(String n) => WorldProposedCard(
        name: n,
        keys: [n],
        role: WorldCraftRole.hub,
        sourceTitles: const ['Ceolwynn'],
      );
      final llm = _FlakyWriteLlm(failFirst: 0);
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
        ..retryPause = Duration.zero;
      await engine.write(
        [card('Ceolwynn'), card('Alnhama')],
        worldName: 'Neokosmos',
        premise: 'x',
      );
      final prompt = llm.params.first.prompt;
      expect(
        prompt,
        contains('SHELF (the other cards in this world): Ceolwynn, Alnhama'),
      );
      expect(prompt, contains('names one or two other cards from SHELF'));
      expect(prompt, contains('accentless spellings'));
      expect(worldShelfLine(const []), isEmpty);
    });
  });

  group('the Review step\'s loop', () {
    LorebookEntry entry(String n, {String content = 'Two sentences. Here.'}) =>
        LorebookEntry(name: n, keys: [n], content: content, order: 150);

    test('a direction is held to the shelf, and without a sort every name '
        'the note mentions is rewritten', () {
      final sorted = parseWorldDirection(
        [
          const LlmToolCall(
            name: kWorldDirectionToolName,
            arguments: {
              'rewrite': ['royal guard', 'Nobody', 'Seireitei'],
              'add': [
                {'name': 'Kurosaki Clinic', 'place': 'karakura town'},
                {'name': 'Seireitei', 'place': ''},
                {'name': ''},
              ],
              'drop': ['Aizen', 'Nobody'],
            },
          ),
        ],
        known: ['Seireitei', 'Royal Guard', 'Aizen'],
        places: ['Karakura Town'],
      );
      expect(sorted.rewrite, ['Royal Guard', 'Seireitei']);
      expect(sorted.add, [(name: 'Kurosaki Clinic', place: 'Karakura Town')]);
      expect(sorted.drop, ['Aizen']);
      expect(
        parseWorldDirection(const [], known: ['Seireitei']).isEmpty,
        isTrue,
      );
      final matched = matchDirectionNames(
        'The Royal Guard card should name all four; less about Aizen.',
        ['Seireitei', 'Royal Guard', 'Aizen', 'Yh'],
      );
      expect(matched.rewrite, ['Royal Guard', 'Aizen']);
    });

    test('the tree is edited by name: replace, remove, add under a place', () {
      final tree = WorldWriteTree(
        root: WorldPlaceWrite(
          name: 'Bleach',
          parentName: '',
          description: '',
          entries: [entry('Era')],
        ),
        places: [
          WorldPlaceWrite(
            name: 'Soul Society',
            parentName: '',
            description: '',
            entries: [entry('Seireitei'), entry('Royal Guard')],
          ),
        ],
      );
      final replaced = worldTreeReplace(tree, {
        'royal guard': worldEntryWithDraft(
          entry('Royal Guard'),
          const WorldCraftDraft(
            name: 'Royal Guard',
            keys: ['Royal Guard', 'Squad Zero'],
            content: 'Five who guard the Soul King. Not yet come down.',
            role: WorldCraftRole.hub,
          ),
        ),
      });
      final rg = replaced.places.single.entries.last;
      expect(rg.content, 'Five who guard the Soul King. Not yet come down.');
      expect(rg.keys, ['Royal Guard', 'Squad Zero']);
      expect(rg.order, 150, reason: 'the mechanics stay');
      final removed = worldTreeRemove(replaced, {'seireitei'});
      expect(removed.places.single.entries.map((e) => e.name), ['Royal Guard']);
      final added = worldTreeAdd(removed, 'soul society', entry('Rukongai'));
      expect(added.places.single.entries.map((e) => e.name), [
        'Royal Guard',
        'Rukongai',
      ]);
      final toRoot = worldTreeAdd(added, 'nowhere', entry('Hueco Mundo'));
      expect(toRoot.root.entries.map((e) => e.name), ['Era', 'Hueco Mundo']);
      expect(worldTreeEntries(toRoot).map((e) => e.name), [
        'Era',
        'Hueco Mundo',
        'Royal Guard',
        'Rukongai',
      ]);
    });

    test('the entry loop leaves a note on every entry, and the copy reads '
        'it back', () async {
      final llm = _EntryReviewLlm(failOnce: {'schrift': 'says how it ends'});
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
        ..retryPause = Duration.zero;
      await engine.write(
        [
          WorldProposedCard(
            name: 'Schrift',
            keys: const ['Schrift'],
            role: WorldCraftRole.leaf,
            sourceTitles: const ['Ceolwynn'],
          ),
        ],
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      final note = engine.entryNotes['schrift'];
      expect(note, isNotNull);
      expect(note!.passed, isTrue);
      expect(note.tries, 2);
      expect(note.problem, 'says how it ends');
      expect(worldEntryNoteCopy(note), 'Rewritten once · says how it ends');
      expect(
        worldEntryNoteCopy(const WorldEntryNote(tries: 1, passed: true)),
        'Passed first try',
      );
      expect(
        worldEntryNoteCopy(
          const WorldEntryNote(tries: 3, passed: false, problem: 'thin'),
        ),
        'Still failing after 3 tries · thin',
      );
      expect(worldEntryNoteCopy(null), 'Written without a reviewer');
      expect(WorldEntryNote.fromJson(note.toJson())?.problem, note.problem);
    });

    test('a rewrite with a note sends the note as the finding, with the '
        'entry as it stands, and reviews what comes back', () async {
      final llm = _FlakyWriteLlm(failFirst: 0);
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
        ..retryPause = Duration.zero;
      engine.rememberShelf([
        WorldProposedCard(
          name: 'Schrift',
          keys: const ['Schrift'],
          role: WorldCraftRole.leaf,
          sourceTitles: const ['Ceolwynn'],
        ),
      ]);
      final drafts = await engine.rewriteWithNote(
        entries: [entry('Schrift', content: 'The old text. As it stands.')],
        note: 'Name the letter it stands for.',
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      final prompt = llm.params.first.prompt;
      expect(prompt, contains('PREVIOUS ENTRY: The old text. As it stands.'));
      expect(
        prompt,
        contains('REVIEW FOUND: The author says: Name the letter it stands for.'),
      );
      expect(drafts.keys, contains('schrift'));
      expect(drafts['schrift']!.content, isNotEmpty);
    });
  });

  group('scout parts by cards', () {
    final titles = List.generate(
      300,
      (i) => 'Title ${i.toString().padLeft(3, '0')}',
    );
    test(
      'at Full depth a 300-title index that fits 64K is still asked in two '
      'parts, each for its share of cards and each seeing the top of the '
      'ranking',
      () async {
        final llm = _PartsLlm(cutAbove: 1000);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.full,
            ).run(
              titles: titles,
              tags: const {},
              worldName: 'Neokosmos',
              premise: 'A coastal republic.',
            );
        expect(run.parts, 2);
        // The review and fill loops ask after the two parts.
        expect(llm.partSizes.take(2).toList(), [150, 150]);
        expect(llm.prompts[0], contains('part 1 of 2'));
        // Full asks 30–45 in all; two parts share it out.
        expect(llm.prompts[0], contains('15–23 cards'));
        expect(llm.prompts[0], contains('Title 000'));
        expect(llm.prompts[0], contains('Title 002'));
        expect(
          llm.prompts[0],
          isNot(contains('Title 001')),
          reason: 'every part takes every n-th title',
        );
        expect(llm.prompts[1], contains('Title 001'));
        expect(run.cards.take(4).map((c) => c.name).toList(), [
          'Title 000',
          'Title 002',
          'Title 001',
          'Title 003',
        ]);
      },
    );
    test('the cutoff grows with the answer the call may run', () {
      expect(
        worldToolTimeoutFor(const Duration(minutes: 6), 8192),
        const Duration(minutes: 18),
      );
      expect(
        worldToolTimeoutFor(const Duration(minutes: 6), 2048),
        const Duration(minutes: 9),
      );
      expect(
        worldToolTimeoutFor(const Duration(milliseconds: 50), 4096),
        const Duration(milliseconds: 100),
      );
      expect(
        worldToolTimeoutFor(const Duration(minutes: 6), 0),
        const Duration(minutes: 6),
      );
    });
  });

  group('scout inside the wizard\'s context', () {
    final titles = List.generate(
      300,
      (i) => 'Title ${i.toString().padLeft(3, '0')}',
    );

    test(
      'a part the model cannot finish is asked again in halves and the shelf merges',
      () async {
        final llm = _PartsLlm(cutAbove: 100);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(16384),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: titles,
              tags: const {},
              worldName: 'Neokosmos',
              premise: 'A coastal republic.',
            );
        expect(run.partsCut, 0);
        expect(
          run.parts,
          greaterThan(1),
          reason:
              '300 short titles fit one 16K part; the fake cuts anything over 100',
        );
        expect(
          llm.partSizes.first,
          300,
          reason: 'the whole index is tried first',
        );
        expect(
          llm.partSizes.where((n) => n <= 100).length,
          greaterThanOrEqualTo(4),
        );
        // 300 → 150 + 150 → four parts of 75; each answered part gives
        // its first two titles, so the merged shelf is exactly those eight.
        expect(llm.partSizes, [300, 150, 75, 75, 150, 75, 75]);
        expect(run.cards.map((c) => c.name).toList(), [
          'Title 000',
          'Title 001',
          'Title 075',
          'Title 076',
          'Title 150',
          'Title 151',
          'Title 225',
          'Title 226',
        ]);
        expect(run.failure, isNull);
        for (final n in llm.partSizes) {
          expect(n, greaterThanOrEqualTo(kWorldScoutMinPart));
        }
      },
    );

    test(
      'a reply that never fits gives up at the smallest part and says so',
      () async {
        final llm = _PartsLlm(cutAbove: 0);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(16384),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: titles,
              tags: const {},
              worldName: 'Neokosmos',
              premise: 'A coastal republic.',
            );
        expect(run.cards, isEmpty);
        expect(run.partsCut, greaterThan(0));
        expect(llm.partSizes.last, lessThanOrEqualTo(kWorldScoutMinPart * 2));
        expect(run.failure, contains('ran out of room'));
        expect(run.failure, contains('parts'));
        expect(run.failure, contains('16K'));
      },
    );

    test(
      'a 64K window asks a 300-title index whole and the prompt says nothing of parts',
      () async {
        final llm = _PartsLlm(cutAbove: 1000);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: titles,
              tags: const {},
              worldName: 'Neokosmos',
              premise: 'A coastal republic.',
            );
        expect(run.parts, 1);
        expect(llm.prompts.single, isNot(contains('part 1 of')));
        expect(run.cards, hasLength(2));
      },
    );

    test(
      'a busy server stops the run with the reason, not a smaller part',
      () async {
        final llm = _PartsLlm(cutAbove: 100, throwOn: 2);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(16384),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: titles,
              tags: const {},
              worldName: 'Neokosmos',
              premise: 'A coastal republic.',
            );
        expect(llm.partSizes, hasLength(2), reason: 'the throw ends the run');
        expect(run.cards, isEmpty);
        expect(run.failure, contains('HTTP 502'));
      },
    );

    test('the status note names the parts and the cuts', () {
      expect(worldScoutPartsNote(parts: 1, partsCut: 0), '');
      expect(worldScoutPartsNote(parts: 3, partsCut: 0), ', asked in 3 parts');
      expect(
        worldScoutPartsNote(parts: 4, partsCut: 1),
        ', asked in 4 parts, 1 cut off',
      );
    });
  });

  group('a world, not a cast list', () {
    WorldProposedCard card(
      String name,
      String kind, {
      WorldCraftRole role = WorldCraftRole.leaf,
    }) => WorldProposedCard(
      name: name,
      keys: const [],
      role: role,
      sourceTitles: [name],
      kind: kind,
    );

    List<WorldProposedCard> shelf({
      required int people,
      required int places,
      required int factions,
      int concepts = 0,
      bool era = true,
      bool kinds = true,
    }) => [
      if (era) card('The war', kinds ? 'event' : '', role: WorldCraftRole.era),
      for (var i = 0; i < places; i++)
        card('Place $i', kinds ? 'place' : '', role: WorldCraftRole.hub),
      for (var i = 0; i < factions; i++)
        card('Faction $i', kinds ? 'faction' : '', role: WorldCraftRole.hub),
      for (var i = 0; i < concepts; i++)
        card('Concept $i', kinds ? 'concept' : ''),
      for (var i = 0; i < people; i++)
        card('Person $i', kinds ? 'person' : '', role: WorldCraftRole.crown),
    ];

    test('the audit flags a shelf of people and passes a setting bible', () {
      // Changed 2026-10-23: people are not rationed any more — the live run
      // saw the ratio gate reject the revise the reviewer had asked for
      // (members for the Schutzstaffel). A heavy shelf with its backbone
      // passes; the fill loop and the reviewer shape the cast.
      final heavy = auditWorldShelf(
        shelf(people: 20, places: 5, factions: 4),
        places: const [],
        tagged: false,
      );
      expect(heavy.ok, isTrue);
      final good = auditWorldShelf(
        shelf(people: 8, places: 9, factions: 6),
        places: const [],
        tagged: false,
      );
      expect(good.ok, isTrue);
      final thin = auditWorldShelf(
        shelf(people: 2, places: 1, factions: 1, concepts: 8),
        places: const [],
        tagged: false,
      );
      expect(thin.problems.single, contains('only 2 place or faction cards'));
      expect(thin.problems.single, contains('settings'));
    });

    test('the audit wants one era card and a kind on every card', () {
      final noEra = auditWorldShelf(
        shelf(people: 4, places: 6, factions: 4, era: false),
        places: const [],
        tagged: false,
      );
      expect(noEra.problems.single, contains('no era card'));
      final noKinds = auditWorldShelf(
        shelf(people: 4, places: 6, factions: 4, kinds: false),
        places: const [],
        tagged: false,
      );
      expect(noKinds.problems.single, contains('no kind'));
    });

    test('a tagged wiki with place cards but no named places is flagged; a '
        'small shelf is never judged', () {
      final unnamed = auditWorldShelf(
        shelf(people: 4, places: 6, factions: 4),
        places: const [],
        tagged: true,
      );
      expect(unnamed.problems.single, contains('no places were named'));
      final small = auditWorldShelf(
        shelf(people: 9, places: 0, factions: 0),
        places: const [],
        tagged: true,
      );
      expect(
        small.ok,
        isTrue,
        reason: 'ten cards: the author signs what is there',
      );
    });

    test(
      'a card keeps a known kind, drops an unknown one, and round-trips it',
      () {
        final person = WorldProposedCard.tryParse({
          'name': 'Yhwach',
          'role': 'crown',
          'sourceTitles': ['Yhwach'],
          'kind': 'Person',
        })!;
        expect(person.kind, 'person');
        expect(person.toJson()['kind'], 'person');
        final odd = WorldProposedCard.tryParse({
          'name': 'X',
          'role': 'leaf',
          'sourceTitles': ['X'],
          'kind': 'hero',
        })!;
        expect(odd.kind, '');
        expect(odd.toJson().containsKey('kind'), isFalse);
      },
    );

    test(
      'a title shows its place and type tags first and drops housekeeping',
      () {
        final shown = worldScoutTagsFor(
          [
            'Card pages with an unofficial Greek name',
            'Kurosaki Family',
            'Characters',
            'Soul Society',
            'Hollow',
            'Stubs',
          ],
          titlesLower: {'soul society', 'hollow'},
        );
        expect(shown, [
          'Soul Society',
          'Hollow',
          'Characters',
          'Kurosaki Family',
        ]);
      },
    );

    test(
      'the status note names a revised shelf, a review that did not take, and nothing when it passed',
      () {
        final notes = ['20 of 30 cards are people; keep at most 10'];
        expect(
          worldScoutShelfNote(revised: true, auditNotes: notes),
          ', shelf revised: 20 of 30 cards are people',
        );
        expect(
          worldScoutShelfNote(revised: false, auditNotes: notes),
          ', review: 20 of 30 cards are people',
        );
        expect(worldScoutShelfNote(revised: false, auditNotes: const []), '');
      },
    );

    test(
      'the review asks once with the findings and takes a better shelf',
      () async {
        final llm = _ReviewLlm(second: _ReviewLlm.balanced)..reviewFails = 1;
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.full,
            ).run(
              titles: _ReviewLlm.titles,
              tags: const {},
              worldName: 'Bleach (TYBW)',
              premise: 'The Thousand-Year Blood War.',
            );
        expect(
          llm.prompts,
          hasLength(4),
          reason: 'scout, review (fail), revise, review (pass)',
        );
        expect(llm.prompts[2], contains('REVIEW FOUND'));
        expect(llm.prompts[2], contains('the era card states the ending'));
        expect(llm.prompts[2], contains('FIRST SHELF'));
        expect(llm.prompts[2], contains('INDEX TITLES'));
        expect(run.revised, isTrue);
        expect(
          run.auditNotes.single,
          contains('the era card states the ending'),
        );
        expect(run.cards.where((c) => c.kind == 'person').length, 6);
        expect(run.cards.where((c) => c.kind == 'place').length, 7);
        expect(run.failure, isNull);
      },
    );

    test(
      'a revise that comes back worse, short or broken keeps the first shelf',
      () async {
        for (final second in [
          _ReviewLlm.balanced,
          _ReviewLlm.short,
          _ReviewLlm.boom,
        ]) {
          final llm = _ReviewLlm(
            second: second,
            stillHeavy: second == _ReviewLlm.balanced,
          )..reviewFails = 99;
          final runner = WorldScoutRunner(
            llm: llm,
            budget: const WorldWikiBudget(65536),
            depth: WorldWikiDepth.full,
          )..retryPause = Duration.zero;
          final run = await runner.run(
            titles: _ReviewLlm.titles,
            tags: const {},
            worldName: 'Bleach (TYBW)',
            premise: 'The Thousand-Year Blood War.',
          );
          // Changed 2026-10-23: Full gets one revise, not two (the first
          // Kimi loops run ran past four hours on three tries a batch).
          expect(
            llm.prompts,
            hasLength(second == _ReviewLlm.short ? 3 : 4),
            reason:
                'scout, review, then one revise (reviewed when it is a '
                'shelf; a thrown revise is asked twice; a short one is not '
                'reviewed), never a third try ($second)',
          );
          // A revise that answered (even still heavy) is the last valid shelf
          // and stands, as in Porch Stories; a short or broken one leaves the
          // first shelf in place.
          expect(run.revised, second == _ReviewLlm.balanced, reason: second);
          expect(run.auditNotes, isNotEmpty, reason: second);
          expect(
            run.cards.where((c) => c.kind == 'person').length,
            20,
            reason: 'the first shelf stays ($second)',
          );
        }
      },
    );

    test('a shelf written as JSON inside prose is read off the text floor', () {
      const prose =
          'Here is the world you asked for:\n```json\n'
          '{"places": [{"name": "Soul Society"}], "cards": [{"name": "Soul Society", '
          '"role": "hub", "kind": "place", "sourceTitles": ["Soul Society"]}]}\n```\n'
          'Let me know if you want changes.';
      final args = worldScoutArgsFromText(prose)!;
      expect(args['cards'] as List, hasLength(1));
      expect(
        worldScoutArgsFromText('No JSON here {"not": "cards"} either.'),
        isNull,
      );
      expect(
        worldToolArgsFromText(
          '{"entries": [{"name": "a \\"quoted\\" } brace"}]}',
          key: 'entries',
        )!['entries'],
        hasLength(1),
      );
    });

    test(
      'a prose answer with a JSON shelf in it counts as the answer',
      () async {
        // The fifth gemma run wrote the whole shelf as a ```json block.
        final llm = _ProseThenCallLlm(proseTimes: 99, proseWithShelf: true);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: _ReviewLlm.titles,
              tags: const {},
              worldName: 'Bleach (TYBW)',
              premise: 'The Thousand-Year Blood War.',
            );
        expect(
          llm.prompts,
          hasLength(1),
          reason: 'the text floor needs no second ask',
        );
        expect(run.cards.map((c) => c.name), ['Place 0', 'Place 1']);
      },
    );

    test(
      'a prose answer is asked once more with a nudge, then stands',
      () async {
        // The third gemma run on oMLX answered the scout in prose.
        final once = _ProseThenCallLlm(proseTimes: 1);
        final run =
            await WorldScoutRunner(
              llm: once,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: _ReviewLlm.titles,
              tags: const {},
              worldName: 'Bleach (TYBW)',
              premise: 'The Thousand-Year Blood War.',
            );
        expect(once.prompts, hasLength(2));
        expect(
          once.prompts.last,
          contains('Answer ONLY with the propose_world_cards tool call'),
        );
        expect(
          once.params.last.reasoningMaxTokens,
          0,
          reason: 'the second ask has thinking off',
        );
        // Changed 2026-10-23: the first ask thinks within a budget, not
        // open-ended (that ran Kimi past the cutoff).
        expect(once.params.first.reasoningMaxTokens, kWorldThinkTokens);
        expect(run.cards, isNotEmpty);
        expect(run.failure, isNull);

        final always = _ProseThenCallLlm(proseTimes: 99);
        final stuck =
            await WorldScoutRunner(
              llm: always,
              budget: const WorldWikiBudget(65536),
              depth: WorldWikiDepth.quick,
            ).run(
              titles: _ReviewLlm.titles,
              tags: const {},
              worldName: 'Bleach (TYBW)',
              premise: 'The Thousand-Year Blood War.',
            );
        expect(always.prompts, hasLength(2), reason: 'two tries, never a loop');
        expect(stuck.cards, isEmpty);
        expect(stuck.failure, contains('plain text'));
      },
    );

    test('a shelf that passes the gate is reviewed once and stands', () async {
      final llm = _ReviewLlm(second: _ReviewLlm.balanced, firstBalanced: true);
      final run =
          await WorldScoutRunner(
            llm: llm,
            budget: const WorldWikiBudget(65536),
            depth: WorldWikiDepth.full,
          ).run(
            titles: _ReviewLlm.titles,
            tags: const {},
            worldName: 'Bleach (TYBW)',
            premise: 'The Thousand-Year Blood War.',
          );
      expect(llm.prompts, hasLength(2), reason: 'scout, review');
      expect(run.revised, isFalse);
      expect(run.auditNotes, isEmpty);
    });
  });

  group('the fill loop', () {
    final titles = [
      'Ichigo Kurosaki',
      'Rukia Kuchiki',
      'Soul Society',
      'Soul King Palace',
      'Royal Guard',
      'Karakura Town',
      'Senjumaru Shutara',
      'Ōetsu Nimaiya',
      'Kirio Hikifune',
      'Tenjirō Kirinji',
    ];
    final tags = {
      'Ichigo Kurosaki': ['Characters'],
      'Rukia Kuchiki': ['Characters'],
      'Soul Society': ['Locations'],
      'Soul King Palace': ['Locations', 'Soul Society'],
      'Royal Guard': ['Organizations'],
      'Karakura Town': ['Locations'],
      'Senjumaru Shutara': ['Characters', 'Royal Guard'],
      'Ōetsu Nimaiya': ['Characters', 'Royal Guard'],
      'Kirio Hikifune': ['Characters', 'Royal Guard'],
      'Tenjirō Kirinji': ['Characters', 'Royal Guard'],
    };

    test(
      'at Deep the Royal Guard gets its five and a missing top place is added',
      () async {
        // Changed 2026-10-23: member cards are Deep's; Full keeps the
        // roster inside the faction card (the maintainer's ruling).
        final llm = _FillLlm();
        final runner = WorldScoutRunner(
          llm: llm,
          budget: const WorldWikiBudget(65536),
          depth: WorldWikiDepth.deep,
        )..retryPause = Duration.zero;
        final run = await runner.run(
          titles: titles,
          tags: tags,
          worldName: 'Bleach (TYBW)',
          premise: 'The Thousand-Year Blood War.',
        );
        final names = run.cards.map((c) => c.name).toList();
        expect(
          names,
          containsAll([
            'Senjumaru Shutara',
            'Ōetsu Nimaiya',
            'Kirio Hikifune',
            'Tenjirō Kirinji',
          ]),
        );
        expect(
          run.cards.where((c) => c.name == 'Senjumaru Shutara').single.place,
          'Soul King Palace',
          reason: "a faction member lands where the faction card stands",
        );
        expect(
          names,
          contains('Rukia Kuchiki'),
          reason: 'the top characters gap',
        );
        expect(
          run.places.map((p) => p.name),
          contains('Karakura Town'),
          reason: 'a top page tagged as a place becomes a place',
        );
        expect(
          llm.fillPrompts.where((p) => p.contains('Royal Guard')),
          isNotEmpty,
        );
        expect(
          run.notes.any((n) => n.startsWith('Fill Royal Guard members: 4')),
          isTrue,
          reason: run.notes.join(' | '),
        );
      },
    );

    test('at Full a faction\'s members stay on its own card; the main cast '
        'and the missing places are still filled', () async {
      final llm = _FillLlm();
      final run =
          await (WorldScoutRunner(
                llm: llm,
                budget: const WorldWikiBudget(65536),
                depth: WorldWikiDepth.full,
              )..retryPause = Duration.zero)
              .run(
                titles: titles,
                tags: tags,
                worldName: 'Bleach (TYBW)',
                premise: 'The Thousand-Year Blood War.',
              );
      final names = run.cards.map((c) => c.name).toList();
      // The fake answers every gap with all its candidates, so the proof
      // is the gap never asked: no faction-members prompt, no note.
      expect(
        llm.fillPrompts.any(
          (p) => p.contains('The wiki files these pages under Royal Guard'),
        ),
        isFalse,
        reason: 'a faction\'s members are its card\'s roster at Full',
      );
      expect(
        run.notes.any((n) => n.startsWith('Fill Royal Guard members')),
        isFalse,
        reason: run.notes.join(' | '),
      );
      expect(names, contains('Rukia Kuchiki'), reason: 'the main cast');
      expect(run.places.map((p) => p.name), contains('Karakura Town'));
    });

    test('quick depth runs no fill rounds', () async {
      final llm = _FillLlm();
      final run =
          await WorldScoutRunner(
            llm: llm,
            budget: const WorldWikiBudget(65536),
            depth: WorldWikiDepth.quick,
          ).run(
            titles: titles,
            tags: tags,
            worldName: 'Bleach (TYBW)',
            premise: 'x',
          );
      expect(llm.fillPrompts, isEmpty);
      expect(
        run.cards.map((c) => c.name),
        isNot(contains('Senjumaru Shutara')),
      );
    });
  });

  group('parallel writes', () {
    test(
      'a remote provider writes two batches at a time; a local server one; order is kept',
      () async {
        final llm = _SlowWriteLlm();
        final engine =
            WorldFromWikiEngine(
                wiki: _wiki(),
                llm: llm,
                depth: WorldWikiDepth.quick,
              )
              ..retryPause = Duration.zero
              ..writeConcurrency = 2;
        final cards = [
          for (var i = 0; i < 10; i++)
            WorldProposedCard(
              name: 'Card $i',
              keys: ['Card $i'],
              role: WorldCraftRole.leaf,
              sourceTitles: const ['Ceolwynn'],
            ),
        ];
        final entries = await engine.write(cards, worldName: 'B', premise: 'x');
        expect(llm.maxInFlight, 2);
        expect(entries.map((e) => e.keys.first).toList(), [
          for (var i = 0; i < 10; i++) 'Card $i',
        ], reason: 'batch order survives the parallelism');
        expect(
          WorldFromWikiEngine(
            wiki: _wiki(),
            llm: _SlowWriteLlm(),
          ).writeConcurrency,
          1,
          reason: 'a service with no URL is local',
        );
      },
    );
  });

  group('the entry loop', () {
    WorldProposedCard card(String n, {String kind = 'person'}) =>
        WorldProposedCard(
          name: n,
          keys: [n],
          role: WorldCraftRole.leaf,
          sourceTitles: const ['Ceolwynn'],
          kind: kind,
        );

    test(
      'a failing entry is sent back with the finding; the passing ones are kept',
      () async {
        final llm = _EntryReviewLlm(
          failOnce: {'yhwach': 'states his death, which is after the moment'},
        );
        final engine = WorldFromWikiEngine(
          wiki: _wiki(),
          llm: llm,
          moment: 'the night after the first invasion',
        )..retryPause = Duration.zero;
        final entries = await engine.write(
          [card('Yhwach'), card('Silbern', kind: 'place')],
          worldName: 'Bleach (TYBW)',
          premise: 'x',
        );
        expect(
          llm.kinds,
          ['write', 'review', 'revise', 'review'],
          reason:
              'write, review, one revise of the failing entry, review again',
        );
        expect(llm.prompts[2], contains('REVIEW FOUND: states his death'));
        expect(llm.prompts[2], contains('Name: Yhwach'));
        expect(
          llm.prompts[2],
          isNot(contains('Name: Silbern')),
          reason: 'only the failing entry goes back',
        );
        expect(
          llm.prompts[1],
          contains('Moment: the night after the first invasion'),
        );
        final byName = {for (final e in entries) e.keys.first: e.content};
        expect(byName['Yhwach'], contains('REVISED'));
        expect(byName['Silbern'], isNot(contains('REVISED')));
        expect(engine.writeLog.first, contains('1 sent back'));
      },
    );

    test(
      'an entry that never passes keeps its latest draft; quick depth asks no reviewer',
      () async {
        final llm = _EntryReviewLlm(
          failOnce: {'yhwach': 'still wrong'},
          failAlways: true,
        );
        final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
          ..retryPause = Duration.zero;
        final entries = await engine.write(
          [card('Yhwach')],
          worldName: 'B',
          premise: 'x',
        );
        // Changed 2026-10-23: Full gets two tries (one rewrite), not three;
        // Deep keeps three.
        expect(llm.kinds, [
          'write',
          'review',
          'revise',
          'review',
        ], reason: 'two tries at Full, never a third');
        expect(entries, hasLength(1), reason: 'never dropped');
        expect(entries.single.content, contains('REVISED'));

        final quick = _EntryReviewLlm(failOnce: {'yhwach': 'x'});
        final quickEngine = WorldFromWikiEngine(
          wiki: _wiki(),
          llm: quick,
          depth: WorldWikiDepth.quick,
        )..retryPause = Duration.zero;
        await quickEngine.write([card('Yhwach')], worldName: 'B', premise: 'x');
        expect(quick.kinds, ['write']);
      },
    );
  });

  group('writes that stumble, and where a place\'s card lives', () {
    WorldProposedCard card(
      String n, {
      String place = '',
      WorldCraftRole role = WorldCraftRole.leaf,
      String kind = 'concept',
    }) => WorldProposedCard(
      name: n,
      keys: [n],
      role: role,
      sourceTitles: const ['Ceolwynn'],
      place: place,
      kind: kind,
    );

    test('a 502 on a write batch is asked again, not swallowed', () async {
      final llm = _FlakyWriteLlm(failFirst: 1);
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
        ..retryPause = Duration.zero;
      final entries = await engine.write(
        [card('Schrift'), card('The Almighty')],
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      expect(llm.writeCalls, 2, reason: 'one stumble, one answer');
      expect(
        entries.map((e) => e.keys.first),
        containsAll(['Schrift', 'The Almighty']),
      );
    });

    test(
      'a batch that fails twice is asked as two halves, each twice at most',
      () async {
        final llm = _FlakyWriteLlm(failFirst: 99);
        final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
          ..retryPause = Duration.zero;
        final entries = await engine.write(
          [card('A'), card('B'), card('C'), card('D')],
          worldName: 'Bleach (TYBW)',
          premise: 'x',
        );
        expect(
          llm.batchSizes,
          [4, 4, 2, 2, 2, 2],
          reason: 'the batch twice, then each half twice; never a third level',
        );
        expect(entries, isEmpty);
      },
    );

    test(
      'a place whose only card is its own hub card is still written',
      () async {
        // The second live run lost four of ten places this way: the lift
        // moved each place's card to its parent, and the empty place was
        // then dropped as "pruned".
        final llm = _FlakyWriteLlm(failFirst: 0);
        final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
          ..retryPause = Duration.zero;
        final tree = await engine.writeTree(
          [
            card(
              'Soul Society',
              place: 'Soul Society',
              role: WorldCraftRole.hub,
              kind: 'place',
            ),
            card(
              'Karakura Town',
              place: 'Karakura Town',
              role: WorldCraftRole.hub,
              kind: 'place',
            ),
            card('Ichigo Kurosaki', kind: 'person'),
          ],
          places: const [
            WorldProposedPlace(name: 'Soul Society'),
            WorldProposedPlace(name: 'Karakura Town'),
            WorldProposedPlace(name: 'Pruned Place'),
          ],
          worldName: 'Bleach (TYBW)',
          premise: 'x',
        );
        expect(tree.places.map((p) => p.name), [
          'Soul Society',
          'Karakura Town',
        ], reason: 'kept by their signed card; the unsigned place is pruned');
        expect(
          tree.root.entries.map((e) => e.keys.first),
          containsAll(['Soul Society', 'Karakura Town', 'Ichigo Kurosaki']),
        );
        expect(
          tree.places.every((p) => p.entries.isEmpty),
          isTrue,
          reason: 'their own cards live in the root book',
        );
      },
    );

    test(
      'a write batch answered as a JSON block in prose is read off the text floor',
      () async {
        // The fifth gemma run answered three write batches in prose.
        final llm = _FlakyWriteLlm(failFirst: 0, proseTimes: 1);
        final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
          ..retryPause = Duration.zero;
        final entries = await engine.write(
          [card('Schrift'), card('Medallion')],
          worldName: 'Bleach (TYBW)',
          premise: 'x',
        );
        expect(
          llm.writeCalls,
          1,
          reason: 'the prose carried the entries; no second ask',
        );
        expect(
          entries.map((e) => e.keys.first),
          containsAll(['Schrift', 'Medallion']),
        );
      },
    );

    test('the second write ask has thinking off', () async {
      final llm = _FlakyWriteLlm(failFirst: 1);
      final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
        ..retryPause = Duration.zero;
      await engine.write(
        [card('Schrift')],
        worldName: 'Bleach (TYBW)',
        premise: 'x',
      );
      // Changed 2026-10-23: the first try thinks within a budget (open-ended
      // thinking over a long index ran Kimi past the cutoff); the second
      // still thinks not at all.
      expect(llm.params.map((p) => p.reasoningMaxTokens).toList(), [
        kWorldThinkTokens,
        0,
      ]);
    });

    test(
      'a write the server never answers is abandoned after the timeout and asked again',
      () async {
        // The third Kimi run sat 30 minutes inside one call.
        final llm = _FlakyWriteLlm(failFirst: 0, hangTimes: 1);
        final engine = WorldFromWikiEngine(wiki: _wiki(), llm: llm)
          ..retryPause = Duration.zero
          ..callTimeout = const Duration(milliseconds: 50);
        final entries = await engine.write(
          [card('Schrift')],
          worldName: 'Bleach (TYBW)',
          premise: 'x',
        );
        expect(llm.writeCalls, 2);
        expect(
          llm.aborts,
          1,
          reason: 'the hung request is closed, not left open',
        );
        expect(entries, hasLength(1));
      },
    );

    test("a place's own hub card is lifted into the book around it", () {
      const places = [
        WorldProposedPlace(name: 'Soul Society'),
        WorldProposedPlace(name: 'Seireitei', parentName: 'Soul Society'),
      ];
      final lifted = liftPlaceHubCards([
        card(
          'Soul Society',
          place: 'Soul Society',
          role: WorldCraftRole.hub,
          kind: 'place',
        ),
        card(
          'Seireitei',
          place: 'Seireitei',
          role: WorldCraftRole.hub,
          kind: 'place',
        ),
        card(
          'Gotei 13',
          place: 'Seireitei',
          role: WorldCraftRole.hub,
          kind: 'faction',
        ),
        card('Ichigo Kurosaki', kind: 'person'),
      ], places);
      expect(lifted.map((c) => c.place).toList(), [
        '',
        'Soul Society',
        'Seireitei',
        '',
      ]);
      final groups = groupCardsByPlace(lifted, places);
      expect(groups['']!.map((c) => c.name), [
        'Soul Society',
        'Ichigo Kurosaki',
      ]);
      expect(groups['soul society']!.map((c) => c.name), ['Seireitei']);
      expect(groups['seireitei']!.map((c) => c.name), ['Gotei 13']);
    });
  });
}

/// One scripted scout answer: a fixed response, or a thrown error.
class _OutcomeLlm extends LLMService {
  _OutcomeLlm({this.response, this.error});
  final LlmToolResponse? response;
  final Object? error;
  int? lastMaxLength;
  String lastPrompt = '';

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    lastMaxLength = params.maxLength;
    lastPrompt = params.prompt;
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

/// Scout fake that cannot finish a part over [cutAbove] index lines (it
/// answers finish_reason=length with no call) and otherwise proposes the
/// part's first two titles. [throwOn] makes the n-th request a 502.
class _PartsLlm extends LLMService {
  _PartsLlm({required this.cutAbove, this.throwOn});
  final int cutAbove;
  final int? throwOn;
  final List<int> partSizes = [];
  final List<String> prompts = [];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    final lines = params.prompt
        .split('\n')
        .where((l) => l.startsWith('- '))
        .map((l) => l.substring(2).split(' [').first.trim())
        .toList();
    partSizes.add(lines.length);
    if (throwOn != null && partSizes.length == throwOn) {
      throw LlmToolTransportException(
        'tool call HTTP 502 (server busy/unavailable)',
      );
    }
    if (lines.length > cutAbove) {
      return const LlmToolResponse(calls: [], text: '', finishReason: 'length');
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldScoutToolName,
          arguments: {
            'cards': [
              for (final t in lines.take(2))
                {
                  'name': t,
                  'role': 'leaf',
                  'sourceTitles': [t],
                },
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Scout fake for the review pass: the first call answers a people-heavy
/// shelf (or a balanced one with [firstBalanced]); the second answers per
/// [second] — a balanced shelf, a short one, or a thrown 502. With
/// [stillHeavy] the "balanced" second shelf is as people-heavy as the first.
class _ReviewLlm extends LLMService {
  _ReviewLlm({
    required this.second,
    this.firstBalanced = false,
    this.stillHeavy = false,
  });
  static const balanced = 'balanced';
  static const short = 'short';
  static const boom = 'boom';
  static final titles = [for (var i = 0; i < 40; i++) 'Title $i'];
  final String second;
  final bool firstBalanced;
  final bool stillHeavy;
  final List<String> prompts = [];

  /// How many times the shelf reviewer objects before it passes.
  int reviewFails = 0;
  int reviews = 0;

  Map<String, dynamic> _card(int i, String kind, String role) => {
    'name': '$kind $i',
    'role': role,
    'sourceTitles': ['Title ${i % 40}'],
    'kind': kind,
  };

  List<Map<String, dynamic>> _heavy() => [
    _card(0, 'event', 'era'),
    for (var i = 1; i <= 2; i++) _card(i, 'place', 'hub'),
    for (var i = 3; i <= 4; i++) _card(i, 'faction', 'hub'),
    for (var i = 5; i <= 24; i++) _card(i, 'person', 'crown'),
  ];

  List<Map<String, dynamic>> _balanced() => [
    _card(0, 'event', 'era'),
    for (var i = 1; i <= 7; i++) _card(i, 'place', 'hub'),
    for (var i = 8; i <= 12; i++) _card(i, 'faction', 'hub'),
    for (var i = 13; i <= 16; i++) _card(i, 'event', 'leaf'),
    for (var i = 17; i <= 19; i++) _card(i, 'concept', 'leaf'),
    for (var i = 20; i <= 25; i++) _card(i, 'person', 'crown'),
  ];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    final toolNames = [
      for (final t in tools)
        if (t['function'] is Map)
          (t['function'] as Map)['name']?.toString() ?? '',
    ];
    if (toolNames.contains(kWorldShelfReviewToolName)) {
      reviews++;
      final fail = reviews <= reviewFails;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldShelfReviewToolName,
            arguments: {
              'pass': !fail,
              'problems': fail ? ['the era card states the ending'] : [],
            },
          ),
        ],
        text: '',
        finishReason: 'tool_calls',
      );
    }
    List<Map<String, dynamic>> cards;
    if (prompts.length == 1) {
      cards = firstBalanced ? _balanced() : _heavy();
    } else {
      if (second == boom) {
        throw LlmToolTransportException(
          'tool call HTTP 502 (server busy/unavailable)',
        );
      }
      if (second == short) {
        cards = _balanced().take(5).toList();
      } else {
        cards = stillHeavy ? _heavy() : _balanced();
      }
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(name: kWorldScoutToolName, arguments: {'cards': cards}),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Write fake: the first [failFirst] write calls are a 502, the rest answer
/// one entry per card in the prompt. Counts calls and batch sizes.
class _FlakyWriteLlm extends LLMService {
  _FlakyWriteLlm({
    required this.failFirst,
    this.proseTimes = 0,
    this.hangTimes = 0,
  });
  final int failFirst;

  /// Write calls (after the failures) answered as a ```json block in prose.
  final int proseTimes;

  /// Write calls that never complete (a hung request).
  final int hangTimes;
  int writeCalls = 0;
  int aborts = 0;
  final List<int> batchSizes = [];
  final List<GenerationParams> params = [];

  @override
  void abortGeneration() {
    aborts++;
  }

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
    if (!names.contains(kWorldLoreBatchToolName)) return null;
    writeCalls++;
    this.params.add(params);
    final cardNames = [
      for (final line in params.prompt.split('\n'))
        if (line.startsWith('Name: ')) line.substring(6).trim(),
    ];
    batchSizes.add(cardNames.length);
    if (writeCalls <= failFirst) {
      throw LlmToolTransportException(
        'tool call HTTP 502 (server busy/unavailable): Upstream returned no '
        'tool call despite required tool_choice.',
      );
    }
    if (writeCalls <= failFirst + hangTimes) {
      return Completer<LlmToolResponse?>().future;
    }
    if (writeCalls <= failFirst + hangTimes + proseTimes) {
      final rows = [
        for (final n in cardNames)
          '{"name": "$n", "keys": ["$n"], "content": "${'Written in the war. ' * 12}"}',
      ].join(',');
      return LlmToolResponse(
        calls: const [],
        text: 'Here you go:\n```json\n{"entries": [$rows]}\n```',
        finishReason: 'stop',
      );
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final n in cardNames)
                {
                  'name': n,
                  'keys': [n],
                  'content': 'Written in the war. ' * 12,
                },
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Scout fake that answers in prose [proseTimes] times, then with a small
/// balanced card list.
class _ProseThenCallLlm extends LLMService {
  _ProseThenCallLlm({required this.proseTimes, this.proseWithShelf = false});
  final int proseTimes;
  final bool proseWithShelf;
  final List<String> prompts = [];
  final List<GenerationParams> params = [];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    prompts.add(params.prompt);
    this.params.add(params);
    if (prompts.length <= proseTimes) {
      return LlmToolResponse(
        calls: const [],
        text: proseWithShelf
            ? 'Sure! Here is the shelf:\n```json\n{"cards": ['
                  '{"name": "Place 0", "role": "hub", "kind": "place", "sourceTitles": ["Title 0"]},'
                  '{"name": "Place 1", "role": "hub", "kind": "place", "sourceTitles": ["Title 1"]}'
                  ']}\n```'
            : 'Here is a world for you: Soul Society, Seireitei…',
        finishReason: 'stop',
      );
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldScoutToolName,
          arguments: {
            'cards': [
              for (var i = 0; i < 3; i++)
                {
                  'name': 'Place $i',
                  'role': 'hub',
                  'kind': 'place',
                  'sourceTitles': ['Title $i'],
                },
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Scout fake for the fill loop: the first call answers a small backbone
/// shelf, the reviewer passes, and every CANDIDATES call answers one card
/// per candidate (a place with a hub card for the places gap).
class _FillLlm extends LLMService {
  final List<String> prompts = [];
  final List<String> fillPrompts = [];

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
    if (names.contains(kWorldShelfReviewToolName)) {
      return const LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldShelfReviewToolName,
            arguments: {'pass': true, 'problems': []},
          ),
        ],
        text: '',
      );
    }
    if (params.prompt.contains('CANDIDATES')) {
      fillPrompts.add(params.prompt);
      final after = params.prompt.split('CANDIDATES').last;
      final candidates = [
        for (final line in after.split('\n'))
          if (line.startsWith('- ')) line.substring(2).split(' [').first.trim(),
      ];
      final isPlaces = params.prompt.contains('are places this world lacks');
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldScoutToolName,
            arguments: {
              'cards': [
                for (final c in candidates)
                  {
                    'name': c,
                    'role': isPlaces ? 'hub' : 'leaf',
                    'kind': isPlaces ? 'place' : 'person',
                    'sourceTitles': [c],
                    if (isPlaces) 'place': c,
                  },
              ],
              if (isPlaces)
                'places': [
                  for (final c in candidates) {'name': c},
                ],
            },
          ),
        ],
        text: '',
        finishReason: 'tool_calls',
      );
    }
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldScoutToolName,
          arguments: {
            'cards': [
              {
                'name': 'The war',
                'role': 'era',
                'kind': 'event',
                'sourceTitles': ['Soul Society'],
              },
              {
                'name': 'Soul Society',
                'role': 'hub',
                'kind': 'place',
                'sourceTitles': ['Soul Society'],
                'place': 'Soul Society',
              },
              {
                'name': 'Soul King Palace',
                'role': 'hub',
                'kind': 'place',
                'sourceTitles': ['Soul King Palace'],
                'place': 'Soul King Palace',
              },
              {
                'name': 'Royal Guard',
                'role': 'hub',
                'kind': 'faction',
                'sourceTitles': ['Royal Guard'],
                'place': 'Soul King Palace',
              },
              {
                'name': 'Ichigo Kurosaki',
                'role': 'crown',
                'kind': 'person',
                'sourceTitles': ['Ichigo Kurosaki'],
              },
            ],
            'places': [
              {'name': 'Soul Society'},
              {'name': 'Soul King Palace', 'parentName': 'Soul Society'},
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Write fake with a reviewer: write calls answer one entry per card; the
/// review fails the names in [failOnce] on the first review (or always
/// with [failAlways]); a revise (a write prompt carrying REVIEW FOUND)
/// answers "REVISED" entries for the cards it names.
class _EntryReviewLlm extends LLMService {
  _EntryReviewLlm({required this.failOnce, this.failAlways = false});
  final Map<String, String> failOnce;
  final bool failAlways;
  final List<String> prompts = [];
  final List<String> kinds = [];
  int reviews = 0;

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
    if (names.contains(kWorldEntriesReviewToolName)) {
      reviews++;
      kinds.add('review');
      final entryNames = [
        for (final line in params.prompt.split('\n'))
          if (line.startsWith('--- ') && line.contains(' ('))
            line.substring(4).split(' (').first.trim(),
      ];
      final fail = reviews == 1 || failAlways;
      return LlmToolResponse(
        calls: [
          LlmToolCall(
            name: kWorldEntriesReviewToolName,
            arguments: {
              'verdicts': [
                for (final n in entryNames)
                  {
                    'name': n,
                    'pass': !(fail && failOnce.containsKey(n.toLowerCase())),
                    'problems': fail && failOnce.containsKey(n.toLowerCase())
                        ? [failOnce[n.toLowerCase()]]
                        : [],
                  },
              ],
            },
          ),
        ],
        text: '',
        finishReason: 'tool_calls',
      );
    }
    if (!names.contains(kWorldLoreBatchToolName)) return null;
    final revise = params.prompt.contains('REVIEW FOUND');
    kinds.add(revise ? 'revise' : 'write');
    final cardNames = [
      for (final line in params.prompt.split('\n'))
        if (line.startsWith('Name: ')) line.substring(6).trim(),
    ];
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final n in cardNames)
                {
                  'name': n,
                  'keys': [n],
                  'content':
                      '${revise ? 'REVISED. ' : ''}${'Written as things stand that night. ' * 6}',
                },
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}

/// Write fake that answers after a short wait and counts how many writes
/// are in flight at once.
class _SlowWriteLlm extends LLMService {
  int inFlight = 0;
  int maxInFlight = 0;

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    inFlight++;
    if (inFlight > maxInFlight) maxInFlight = inFlight;
    await Future<void>.delayed(const Duration(milliseconds: 30));
    inFlight--;
    final cardNames = [
      for (final line in params.prompt.split('\n'))
        if (line.startsWith('Name: ')) line.substring(6).trim(),
    ];
    return LlmToolResponse(
      calls: [
        LlmToolCall(
          name: kWorldLoreBatchToolName,
          arguments: {
            'entries': [
              for (final n in cardNames)
                {
                  'name': n,
                  'keys': [n],
                  'content': 'Written in the war. ' * 12,
                },
            ],
          },
        ),
      ],
      text: '',
      finishReason: 'tool_calls',
    );
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {}

  @override
  bool get isReady => true;

  @override
  String get backendName => 'test';
}
