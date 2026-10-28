// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/facade/world_character_source.dart';
import 'package:front_porch_ai/services/web/streaming/stream_hub.dart';
import 'package:front_porch_ai/services/web/util/lorebook_json.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

/// Web twin of the desktop World-from-wiki wizard. Scout is request/response.
/// Write reports over the hub; save is the existing POST /api/worlds.
/// The tools gate is chat's own tool check on the chat model, which is the
/// model scout and write run on here.
class WorldFromWikiFacade {
  WorldFromWikiFacade(
    this._llm,
    this._storage,
    this._hub,
    this._chat, {
    AppDatabase? db,
    CharacterRepository? characters,
  }) : characterSources = db == null || characters == null
           ? null
           : WorldCharacterSources(db: db, characters: characters);

  /// The character sources this relay can build; null when the host has
  /// no library or database to read, and the Book step then offers the
  /// wiki alone.
  final WorldCharacterSources? characterSources;

  final LLMProvider _llm;
  final StorageService _storage;
  final StreamHub? _hub;
  final ChatService _chat;

  WorldFromWikiEngine? _live;
  bool _writing = false;

  /// The last written world, kept for the phone's Review step: the engine
  /// that wrote it (its shelf, reviewers and notes carry over), the tree
  /// as it stands after each action, and the write's own body.
  WorldFromWikiEngine? reviewEngine;
  WorldWriteTree? reviewTree;
  Map<String, dynamic> reviewBody = const {};

  /// Whether a Review action (rewrite, direction, add) is running.
  bool reviewing = false;

  void broadcast(Map<String, dynamic> event) => _hub?.broadcast(event);

  bool get available => _llm.activeService.isReady;

  Future<Map<String, dynamic>> status() async {
    final gate = _toolsGate();
    return {
      'available': available,
      'toolsAdvertised': gate == WorldToolsGate.ready,
      'toolsGate': gate.name,
      'savedWikis': _storage.webSearchSettings.savedWikiUrls,
      // The wizard's own context pick (0 = same as chat), the chat's
      // context it would follow, and the sizes the Book step offers.
      'contextSize': _storage.webSearchSettings.worldWikiContextSize,
      'chatContextSize': _storage.backendSettings.contextSize,
      'contextChoices': kWorldWikiContextChoices,
      // Depth: 0 quick, 1 full, 2 deep, with the labels the Book step shows.
      'depth': _storage.webSearchSettings.worldWikiDepth,
      'depthChoices': [
        for (final d in WorldWikiDepth.values)
          {
            'value': d.index,
            'label': d.label,
            'cards': d.cardTarget,
            'blurb': d.blurb,
          },
      ],
      // Additive (World from Character): which sources this host can
      // build from, the three modes with their tile copy, and the depth
      // tiles a chat offers (no Deep). An older PWA ignores all three.
      'sources': ['wiki', if (characterSources != null) 'character'],
      'modes': [
        for (final m in WorldBuildMode.values)
          {
            'value': m.name,
            'label': m.label,
            'does': m.does,
            'never': m.never,
            'addedLabel': m.addedLabel,
          },
      ],
      'characterDepthChoices': [
        for (final d in const [WorldWikiDepth.quick, WorldWikiDepth.full])
          {
            'value': d.index,
            'label': d.label,
            'cards': worldCharacterCardTarget(d),
            'blurb': worldCharacterDepthBlurb(d),
            'time': worldCharacterDepthTime(d),
          },
      ],
    };
  }

  /// The engine for [body]: the wiki at [wikiUrl], or the character
  /// source the body names (built once per pick, so the chat is skimmed
  /// once between scout and write). Deep runs as Full on a chat.
  Future<WorldFromWikiEngine> _engineFor(
    Map<String, dynamic> body,
    String wikiUrl,
    LLMService svc,
  ) async {
    final pick = WorldSourcePick.fromBody(body);
    final sources = characterSources;
    final source = pick == null || sources == null
        ? WikiWorldSource(WikiSearchService(getBaseUrl: () => wikiUrl))
        : await sources.sourceFor(pick);
    return WorldFromWikiEngine(
      source: source,
      llm: svc,
      contextTokens: _contextTokens(),
      depth: pick == null ? _depth : worldCharacterDepth(_depth),
      moment: body['moment']?.toString() ?? '',
      mode: pick?.mode,
      onProgress: (msg) {
        _hub?.broadcast({'event': 'world_wiki_status', 'data': msg});
      },
    );
  }

  /// Why [body] cannot be read as a source, or null: a wiki body needs an
  /// address, a character body a character this host knows.
  Future<String?> _sourceError(Map<String, dynamic> body, String wikiUrl) {
    final pick = WorldSourcePick.fromBody(body);
    if (pick == null) {
      return Future.value(
        parseWikiBaseUrl(wikiUrl) == null ? 'wikiUrl is required' : null,
      );
    }
    final sources = characterSources;
    if (sources == null) {
      return Future.value('this host cannot build a world from a character');
    }
    return sources.pickError(pick);
  }

  /// The Book step's context pick from the phone: 0 (same as chat) or a
  /// size at or over the floor. A bad body is refused, never read as 0.
  /// The Book step's picks from the phone: contextSize (0 = same as chat,
  /// or at least the floor) and/or depth (0–2). A bad value is refused,
  /// never read as 0; a missing one leaves that pick alone.
  Future<Map<String, dynamic>> setContext(Map<String, dynamic> body) async {
    int? intOf(String key) {
      final raw = body[key];
      return raw is int
          ? raw
          : raw is num
          ? raw.toInt()
          : int.tryParse(raw?.toString() ?? '');
    }

    final hasContext = body.containsKey('contextSize');
    final hasDepth = body.containsKey('depth');
    if (!hasContext && !hasDepth) {
      return {'ok': false, 'error': 'contextSize or depth is required'};
    }
    final context = intOf('contextSize');
    if (hasContext &&
        (context == null || !worldWikiContextSettingValid(context))) {
      return {
        'ok': false,
        'error':
            'contextSize must be 0 (same as chat) or at least '
            '$kWorldWikiContextFloor tokens',
      };
    }
    final depth = intOf('depth');
    if (hasDepth && (depth == null || depth < 0 || depth > 2)) {
      return {
        'ok': false,
        'error': 'depth must be 0 (quick), 1 (full) or 2 (deep)',
      };
    }
    if (context != null) {
      await _storage.webSearchSettings.setWorldWikiContextSize(context);
    }
    if (depth != null) {
      await _storage.webSearchSettings.setWorldWikiDepth(depth);
    }
    return {'ok': true, ...await status()};
  }

  WorldWikiDepth get _depth =>
      WorldWikiDepthX.fromIndex(_storage.webSearchSettings.worldWikiDepth);

  int _contextTokens() => worldWikiContextTokens(
    setting: _storage.webSearchSettings.worldWikiContextSize,
    chatContext: _storage.backendSettings.contextSize,
  );

  /// The wizard's "Check now": ask the chat model again, then report.
  Future<Map<String, dynamic>> testTools() async {
    await _chat.retestToolsFor();
    return status();
  }

  Future<Map<String, dynamic>> scout(Map<String, dynamic> body) async {
    final wikiUrl = body['wikiUrl']?.toString().trim() ?? '';
    final sourceError = await _sourceError(body, wikiUrl);
    if (sourceError != null) return {'ok': false, 'error': sourceError};
    var gate = _toolsGate();
    if (gate == WorldToolsGate.notChecked || gate == WorldToolsGate.failed) {
      // The phone's Next: ask the model now, the way the desktop does; a
      // "no" is asked again rather than trusted.
      await _chat.retestToolsFor();
      gate = _toolsGate();
    }
    if (gate != WorldToolsGate.ready) {
      return {
        'ok': false,
        'error': worldFromWikiToolsCopy(gate, onPhone: true),
      };
    }
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    final engine = await _engineFor(body, wikiUrl, svc);
    final result = await engine.scout(
      worldName: body['name']?.toString() ?? '',
      premise: body['premise']?.toString() ?? '',
    );
    return {
      'ok': true,
      'backend': result.catalog.backend.name,
      'titles': result.catalog.titles.length,
      'skipped': result.catalog.skipped,
      'parsed': result.catalog.parsed,
      'proposed': [for (final c in result.proposed) c.toJson()],
      // Slice 8 (additive): the tag-named places. An older PWA simply
      // ignores them and saves one flat world, as before.
      'places': [for (final p in result.places) p.toJson()],
      // Additive: why the shelf is empty when the model never answered
      // (token limit, busy server, unreadable call). Absent on a real
      // empty answer; an older PWA keeps its own premise line.
      if (result.failure != null) 'failure': result.failure,
      // Additive: how the index was asked (parts > 1 = split and merged;
      // partsCut = parts the model could not finish at the smallest size).
      'parts': result.parts,
      'partsCut': result.partsCut,
      // Additive: the wiki's article count and whether the catalog is its
      // most-linked pages; the shelf review's verdict.
      if (result.catalog.articleCount != null)
        'articles': result.catalog.articleCount,
      'ranked': result.catalog.ranked,
      'revised': result.revised,
      'auditNotes': result.auditNotes,
      'notes': result.notes,
    };
  }

  Map<String, dynamic> startWrite(Map<String, dynamic> body) {
    if (_writing) return {'ok': false, 'error': 'already writing'};
    final wikiUrl = body['wikiUrl']?.toString().trim() ?? '';
    final pick = WorldSourcePick.fromBody(body);
    if (pick == null && parseWikiBaseUrl(wikiUrl) == null) {
      return {'ok': false, 'error': 'wikiUrl is required'};
    }
    if (pick != null && characterSources == null) {
      return {
        'ok': false,
        'error': 'this host cannot build a world from a character',
      };
    }
    final cards = parseSignedWorldWriteCards(
      body['cards'] ?? body['signed'],
      max: _depth.cardTarget,
    );
    if (cards.isEmpty) {
      return {'ok': false, 'error': 'signed cards are required'};
    }
    final svc = _llm.activeService;
    if (!svc.isReady) {
      return {'ok': false, 'error': 'the LLM backend is not ready'};
    }
    unawaited(_runWrite(wikiUrl, cards, body, svc));
    return {'ok': true};
  }

  void abort() {
    _live?.abort();
    if (reviewing) reviewEngine?.abort();
  }

  Future<void> _runWrite(
    String wikiUrl,
    List<WorldProposedCard> cards,
    Map<String, dynamic> body,
    LLMService svc,
  ) async {
    _writing = true;
    final engine = _live = await _engineFor(body, wikiUrl, svc);
    final pick = WorldSourcePick.fromBody(body);
    final characterSource = engine.source;
    final provenance =
        pick != null &&
            characterSource is CharacterChatWorldSource &&
            characterSources != null
        ? characterSources!.provenance(characterSource, pick)
        : const <String, dynamic>{};
    try {
      final gate = _toolsGate();
      if (gate != WorldToolsGate.ready) {
        _hub?.broadcast({
          'event': 'world_wiki_error',
          'error': worldFromWikiToolsCopy(gate, onPhone: true),
        });
        return;
      }
      final tree = await engine.writeTree(
        cards,
        places: _placesFrom(body),
        worldName: body['name']?.toString() ?? '',
        premise: body['premise']?.toString() ?? '',
        climateEnabled: body['climateEnabled'] == true,
        climatePlaces: _climateSetFrom(body),
      );
      if (engine.aborted) {
        _hub?.broadcast({'event': 'world_wiki_abort', 'data': 'Stopped.'});
        return;
      }
      reviewEngine = engine;
      reviewTree = tree;
      reviewBody = Map<String, dynamic>.from(body);
      // Copy the card's lorebook in (character source, opt-in): the
      // character's own entries ride along on the root, unchanged.
      if (pick != null &&
          pick.copyCardLore &&
          characterSource is CharacterChatWorldSource) {
        final have = {
          for (final e in tree.root.entries) e.name.trim().toLowerCase(),
        };
        for (final e
            in characterSource.card.lorebook?.entries ??
                const <LorebookEntry>[]) {
          if (!e.enabled || !have.add(e.name.trim().toLowerCase())) continue;
          tree.root.entries.add(e);
        }
      }
      final entries = tree.root.entries.followedBy([
        for (final p in tree.places) ...p.entries,
      ]).toList();
      final book = Lorebook(
        entries: entries,
        recursiveScanning: true,
        scanDepth: kWorldFromWikiScanDepth,
        tokenBudget: kWorldFromWikiTokenBudget,
      );
      final climateOn = body['climateEnabled'] == true && engine.biome != null;
      final rootDescription = tree.root.description.isNotEmpty
          ? tree.root.description
          : body['premise']?.toString() ?? '';
      _hub?.broadcast({
        'event': 'world_wiki_done',
        'name': body['name']?.toString() ?? '',
        'description': rootDescription,
        'climateEnabled': climateOn,
        if (climateOn) 'biome': engine.biome,
        'recursiveScanning': true,
        'scanDepth': kWorldFromWikiScanDepth,
        'tokenBudget': kWorldFromWikiTokenBudget,
        'entries': lorebookEntriesToJson(book),
        // Additive: what the entry loop did to each entry, by name.
        'notes': {
          for (final e in engine.entryNotes.entries) e.key: e.value.toJson(),
        },
        // Additive (World from Character): the root's provenance, which
        // the PWA passes to its save. Absent on a wiki world.
        ...provenance,
        // Slice 8 (additive): per-place books so the PWA saves a root
        // plus children. Empty/absent → flat save, exactly today.
        'root': {
          'name': tree.root.name,
          'description': tree.root.description,
          'entries': lorebookEntriesToJson(
            Lorebook(
              entries: tree.root.entries,
              recursiveScanning: true,
              scanDepth: kWorldFromWikiScanDepth,
              tokenBudget: kWorldFromWikiTokenBudget,
            ),
          ),
          if (tree.root.biome != null) 'biome': tree.root.biome,
        },
        'places': [
          for (final p in tree.places)
            {
              'name': p.name,
              'parentName': p.parentName,
              'description': p.description,
              'entries': lorebookEntriesToJson(
                Lorebook(
                  entries: p.entries,
                  recursiveScanning: true,
                  scanDepth: kWorldFromWikiScanDepth,
                  tokenBudget: kWorldFromWikiTokenBudget,
                ),
              ),
              if (p.hasClimate) 'biome': p.biome,
            },
        ],
      });
    } catch (e) {
      _hub?.broadcast({'event': 'world_wiki_error', 'error': e.toString()});
    } finally {
      _writing = false;
      _live = null;
    }
  }

  /// Scout places the PWA kept across the review (verbatim round-trip of
  /// the scout response). Junk entries drop, never throw.
  List<WorldProposedPlace> _placesFrom(Map<String, dynamic> body) {
    final raw = body['places'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map)
          ?WorldProposedPlace.tryParse(Map<String, dynamic>.from(e)),
    ];
  }

  Set<String> _climateSetFrom(Map<String, dynamic> body) {
    final raw = body['placeClimate'];
    if (raw is! List) return const {};
    return {for (final e in raw) e?.toString().toLowerCase() ?? ''}..remove('');
  }

  /// Reads only; the phone's Next ([scout]) and Check now ([testTools])
  /// are the presses that ask the model, and so may load one.
  WorldToolsGate _toolsGate() =>
      worldFromWikiToolsGate(_chat.toolCheckFor(autoAsk: false));
}
