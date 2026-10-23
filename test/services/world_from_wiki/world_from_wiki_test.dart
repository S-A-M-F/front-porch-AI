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
      final heavy = auditWorldShelf(
        shelf(people: 20, places: 5, factions: 4),
        places: const [],
        tagged: false,
      );
      expect(heavy.problems, hasLength(1));
      expect(heavy.problems.single, contains('20 of 30 cards are people'));
      final good = auditWorldShelf(
        shelf(people: 8, places: 9, factions: 6),
        places: const [],
        tagged: false,
      );
      expect(good.ok, isTrue);
      final thin = auditWorldShelf(
        shelf(people: 6, places: 1, factions: 1, concepts: 6),
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
        final llm = _ReviewLlm(second: _ReviewLlm.balanced);
        final run =
            await WorldScoutRunner(
              llm: llm,
              budget: const WorldWikiBudget(65536),
            ).run(
              titles: _ReviewLlm.titles,
              tags: const {},
              worldName: 'Bleach (TYBW)',
              premise: 'The Thousand-Year Blood War.',
            );
        expect(llm.prompts, hasLength(2));
        expect(llm.prompts.last, contains('REVIEW FOUND'));
        expect(llm.prompts.last, contains('cards are people'));
        expect(llm.prompts.last, contains('FIRST SHELF'));
        expect(llm.prompts.last, contains('INDEX TITLES'));
        expect(run.revised, isTrue);
        expect(run.auditNotes.single, contains('cards are people'));
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
          );
          final run =
              await WorldScoutRunner(
                llm: llm,
                budget: const WorldWikiBudget(65536),
              ).run(
                titles: _ReviewLlm.titles,
                tags: const {},
                worldName: 'Bleach (TYBW)',
                premise: 'The Thousand-Year Blood War.',
              );
          expect(
            llm.prompts,
            hasLength(2),
            reason: 'one revise, never a loop ($second)',
          );
          expect(run.revised, isFalse, reason: second);
          expect(run.auditNotes, isNotEmpty, reason: second);
          expect(
            run.cards.where((c) => c.kind == 'person').length,
            20,
            reason: 'the first shelf stays ($second)',
          );
        }
      },
    );

    test('a shelf that already reads as a world is not reviewed', () async {
      final llm = _ReviewLlm(second: _ReviewLlm.balanced, firstBalanced: true);
      final run =
          await WorldScoutRunner(
            llm: llm,
            budget: const WorldWikiBudget(65536),
          ).run(
            titles: _ReviewLlm.titles,
            tags: const {},
            worldName: 'Bleach (TYBW)',
            premise: 'The Thousand-Year Blood War.',
          );
      expect(llm.prompts, hasLength(1));
      expect(run.revised, isFalse);
      expect(run.auditNotes, isEmpty);
    });
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
  _FlakyWriteLlm({required this.failFirst});
  final int failFirst;
  int writeCalls = 0;
  final List<int> batchSizes = [];

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
