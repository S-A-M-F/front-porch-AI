// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_budget.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_ops.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_scout.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_places.dart';

/// Scout result: index size plus proposed cards (default unsigned).
class WorldScoutResult {
  const WorldScoutResult({
    required this.catalog,
    required this.proposed,
    this.places = const [],
    this.failure,
    this.parts = 0,
    this.partsCut = 0,
    this.revised = false,
    this.auditNotes = const [],
  });

  final WikiStudioCatalog catalog;
  final List<WorldProposedCard> proposed;

  /// The shelf review's verdict: [revised] when the model's second shelf
  /// replaced the first, [auditNotes] what the review found (empty when
  /// the first shelf already read as a world).
  final bool revised;
  final List<String> auditNotes;

  /// How many requests the index took: 1 when it fit the wizard's context
  /// whole, more when it was asked in parts and merged.
  final int parts;

  /// Parts the model could not finish even at the smallest size; their
  /// titles are missing from [proposed].
  final int partsCut;

  /// Plain words for why [proposed] is empty when the model never gave
  /// its answer: the reply hit the token limit, the server was busy, the
  /// call could not be read. Null when the model did answer — the wizard
  /// then keeps its own "try a clearer premise" line.
  final String? failure;

  /// Slice 8 (design §9.2): the places the scout named from tag
  /// evidence, already resolved into build order. Empty on an untagged
  /// wiki — every consumer must treat that as "flat world, as before".
  final List<WorldProposedPlace> places;
}

/// Headless scout + write. Not ChatService. Signed-card count is the loop cap.
class WorldFromWikiEngine {
  WorldFromWikiEngine({
    required this.wiki,
    required this.llm,
    this.onProgress,
    this.contextTokens = kWorldWikiContextFloor,
  });

  final WikiSearchService wiki;
  final LLMService llm;
  final void Function(String message)? onProgress;

  /// The wizard's context window (the Book step pick, or chat's). Every
  /// request is sized from it: the scout asks the index in parts that
  /// leave reply room, write batches pack what fits, and each reply gets
  /// what the window leaves after its prompt.
  final int contextTokens;

  late final WorldWikiBudget budget = WorldWikiBudget(contextTokens);

  bool _aborted = false;
  final List<LorebookEntry> entries = [];
  final Set<String> _written = {};
  Map<String, dynamic>? biome;

  bool get aborted => _aborted;

  /// The tag sets from the newest [scan] — the scout prompt shows them
  /// so a tags-only wiki (Neokosmos) can reveal its places (slice 8).
  Map<String, List<String>> lastCatalogTags = const {};

  void abort() {
    _aborted = true;
    llm.abortGeneration();
    debugPrint('[World] abort');
  }

  Future<WikiStudioCatalog> scan({String? seedQuery}) async {
    final catalog = await wiki.listStudioTitles(seedQuery: seedQuery);
    lastCatalogTags = catalog.tagsByTitle;
    debugPrint(
      '[World] scan backend=${catalog.backend.name} '
      'titles=${catalog.titles.length} skipped=${catalog.skipped} '
      'parsed=${catalog.parsed}',
    );
    return catalog;
  }

  /// Index titles → proposed cards. One tool call. Does not write lore.
  Future<WorldScoutResult> scout({
    required String worldName,
    required String premise,
  }) async {
    _aborted = false;
    final catalog = await scan(
      seedQuery: [
        worldName.trim(),
        premise.trim(),
      ].where((s) => s.isNotEmpty).join(' '),
    );
    if (_aborted) {
      return WorldScoutResult(catalog: catalog, proposed: const []);
    }
    onProgress?.call('Scouting ${catalog.titles.length} titles…');
    final scouted =
        await WorldScoutRunner(
          llm: llm,
          budget: budget,
          onProgress: onProgress,
          isAborted: () => _aborted,
        ).run(
          titles: catalog.titles,
          tags: lastCatalogTags,
          worldName: worldName,
          premise: premise,
        );
    final proposed = scouted.cards;
    debugPrint(
      '[World] scout titles=${catalog.titles.length} proposed=${proposed.length} '
      'places=${scouted.places.length} context=$contextTokens '
      'parts=${scouted.parts} cut=${scouted.partsCut}',
    );
    if (proposed.isNotEmpty && proposed.length < kWorldScoutCardMin) {
      debugPrint('[World] scout short proposed=${proposed.length}');
    }
    return WorldScoutResult(
      catalog: catalog,
      proposed: proposed,
      places: resolvePlaceOrder(scouted.places),
      failure: scouted.failure,
      parts: scouted.parts,
      partsCut: scouted.partsCut,
      revised: scouted.revised,
      auditNotes: scouted.auditNotes,
    );
  }

  /// Signed cards only. One tool call per [kWorldWriteBatchSize] cards.
  Future<List<LorebookEntry>> write(
    List<WorldProposedCard> signed, {
    required String worldName,
    required String premise,
    String extraLore = '',
    bool climateEnabled = false,
  }) async {
    _aborted = false;
    biome = null;
    entries.clear();
    _written.clear();
    final pending = <WorldProposedCard>[];
    for (final card in signed) {
      final name = card.name.trim();
      if (name.isEmpty || !_written.add(name.toLowerCase())) continue;
      pending.add(card);
    }
    final k = pending.length;
    debugPrint('[World] review signed=$k context=$contextTokens');
    final drafts = <WorldCraftDraft>[];
    var done = 0;
    final batches = planWorldWriteBatches(
      pending,
      budget: budget,
      headerTokens: worldWikiEstimateTokens(
        writeHeader(
          worldName: worldName,
          premise: premise,
          extraLore: extraLore,
        ),
      ),
      articleFor: (card) => joinSources(card.sourceTitles),
      onMiss: (card) => debugPrint('[World] write miss ${card.name}'),
      stop: () => _aborted,
    );
    await for (final batch in batches) {
      if (_aborted) {
        debugPrint('[World] abort');
        break;
      }
      done += batch.cards.length;
      debugPrint(
        '[World] write batch ${done - batch.cards.length + 1}–$done/$k '
        'names=${batch.cards.map((c) => c.name).join(', ')}',
      );
      onProgress?.call('Writing ${batch.cards.length} cards ($done/$k)');
      final generated = await writeBatch(
        cards: batch.cards,
        articles: batch.articles,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
      );
      drafts.addAll(matchWorldWriteBatch(batch.cards, generated));
    }
    if (climateEnabled && !_aborted) {
      final climate = await _writeClimate(
        worldName: worldName,
        premise: premise,
      );
      if (climate != null) {
        biome = climate.biome;
        debugPrint(
          '[World] climate biome=${climate.biome['displayName']} '
          'lore=${climate.lore.length}',
        );
        for (final w in climate.lore) {
          if (!_written.add(w.name.toLowerCase())) continue;
          drafts.add(
            WorldCraftDraft(
              name: w.name,
              keys: w.keys,
              content: w.content,
              role: WorldCraftRole.hub,
            ),
          );
        }
      }
    }
    if (_aborted) {
      entries.clear();
      return List<LorebookEntry>.unmodifiable(entries);
    }
    entries.addAll(applyWorldCraftMechanics(drafts));
    return List<LorebookEntry>.unmodifiable(entries);
  }

  Future<String> joinSources(List<String> titles) async {
    final buf = StringBuffer();
    for (final title in titles.take(3)) {
      final t = title.trim();
      if (t.isEmpty || skipWikiStudioTitle(t)) continue;
      final article = await wiki.getArticleFull(t);
      if (!article.ok) {
        debugPrint('[World] write miss $t');
        continue;
      }
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('=== $t ===');
      buf.writeln(article.snippet);
    }
    return buf.toString().trim();
  }

  /// The part of a write prompt every batch repeats: world, premise and
  /// the attached notes. Sized once so the batcher knows the fixed cost.
  String writeHeader({
    required String worldName,
    required String premise,
    required String extraLore,
  }) {
    final extra = extraLore.trim();
    final extraBlock = extra.isEmpty
        ? ''
        : '\nATTACHED NOTES (optional; do not override the articles):\n$extra\n';
    return 'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '$extraBlock';
  }

  Future<List<WorldLoreWrite>> writeBatch({
    required List<WorldProposedCard> cards,
    required List<String> articles,
    required String worldName,
    required String premise,
    required String extraLore,
  }) async {
    final buf = StringBuffer(
      writeHeader(worldName: worldName, premise: premise, extraLore: extraLore),
    );
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final aliases = card.keys.isEmpty ? card.name : card.keys.join(', ');
      buf.writeln();
      buf.writeln('--- CARD ${i + 1}/${cards.length} ---');
      buf.writeln('Name: ${card.name}');
      buf.writeln('Role: ${card.role.name}');
      buf.writeln('Suggested keys: $aliases');
      buf.writeln('ARTICLES:');
      buf.writeln(articles[i]);
    }
    buf.writeln();
    buf.writeln(
      'Call $kWorldLoreBatchToolName once. One entry per card above, '
      'same names. HARD CAP $kWorldLoreContentMax characters — two short '
      'sentences. Alias keys as separate words, with the spellings a chat '
      'would type. Write every person and faction as they are in the '
      'premise\'s time, not their whole history. they/them for unnamed '
      'people. Do not invent climate, biomes, or facts missing from the '
      'articles.',
    );
    final prompt = buf.toString();
    try {
      final resp = await llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: budget.replyFor(prompt, floor: kWorldWriteReplyWant),
          minLength: 16,
          temperature: 0.4,
          reasoningEnabled: true,
          toolChoice: kWorldLoreBatchToolName,
        ),
        worldLoreBatchToolSchema(),
      );
      if (resp == null || resp.isUnusableNativeToolCall) return const [];
      return parseWorldLoreBatchCalls(resp.calls);
    } catch (e) {
      debugPrint('[World] write batch miss ($e)');
      return const [];
    }
  }

  Future<WorldClimateWrite?> _writeClimate({
    required String worldName,
    required String premise,
  }) async {
    onProgress?.call('Writing climate…');
    final catalog = await scan();
    final titles = [
      for (final t in catalog.titles)
        if (wikiTitleLooksClimate(t)) t,
    ].take(4).toList();
    if (titles.isEmpty) {
      debugPrint('[World] climate miss no titles');
      return null;
    }
    // The four climate articles must leave the biome call its room.
    final article = budget.clipForReply(
      await joinSources(titles),
      want: kWorldClimateReplyWant,
      fixedTokens: 512,
    );
    if (article.isEmpty) return null;
    final prompt =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'ARTICLES:\n$article\n\n'
        'Call $kWorldClimateToolName once. Custom biome for THIS place, '
        'not Earth temperate Midwest. Optional loreCards (max 3) for the '
        'warm current, boreal winter, or storms — $kWorldLoreContentMin–'
        '$kWorldLoreContentMax characters each.';
    try {
      final resp = await llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: budget.replyFor(prompt, floor: kWorldClimateReplyWant),
          minLength: 16,
          temperature: 0.4,
          reasoningEnabled: true,
          toolChoice: kWorldClimateToolName,
        ),
        worldClimateToolSchema(),
      );
      if (resp == null || resp.isUnusableNativeToolCall) return null;
      return parseWorldClimateCalls(resp.calls);
    } catch (e) {
      debugPrint('[World] climate miss ($e)');
      return null;
    }
  }
}
