// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/reasoning_effort.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_craft_mechanics.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_budget.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_depth.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_entry_polish.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_entry_review.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_ops.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_scout.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki_tools.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_places.dart';
import 'world_build_mode.dart';
import 'world_progress_copy.dart';
import 'world_scout_result.dart';
import 'world_source.dart';
import 'world_write_rules.dart';
import 'world_review_tools.dart';

export 'world_scout_result.dart';

/// Headless scout + write. Not ChatService. Signed-card count is the loop cap.
class WorldFromWikiEngine {
  WorldFromWikiEngine({
    WikiSearchService? wiki,
    WorldSource? source,
    required this.llm,
    this.onProgress,
    this.contextTokens = kWorldWikiContextFloor,
    this.depth = kWorldWikiDepthDefault,
    this.moment = '',
    this.mode,
  }) : assert(wiki != null || source != null, 'a wiki or a source is needed'),
       source = source ?? WikiWorldSource(wiki!);

  /// How deep this run digs (card target, fill rounds, review tries).
  final WorldWikiDepth depth;

  /// When in the story the scene starts; '' means the premise's time.
  final String moment;

  /// What this run reads: the wiki, or a character and a chat.
  final WorldSource source;

  /// How far the writer may go beyond the record; null is the wiki's own
  /// rules, unchanged (docs/design/world-from-character.md §3.3).
  final WorldBuildMode? mode;

  final LLMService llm;
  final void Function(String message)? onProgress;

  /// The wizard's context window (the Book step pick, or chat's). Every
  /// request is sized from it: the scout asks the index in parts that
  /// leave reply room, write batches pack what fits, and each reply gets
  /// what the window leaves after its prompt.
  final int contextTokens;

  late final WorldWikiBudget budget = WorldWikiBudget(contextTokens);

  /// The wait before a stumbled tool call is asked again (tests pass zero).
  Duration retryPause = const Duration(seconds: 2);

  /// The write passes' run log: one line per entry-loop try.
  final List<String> writeLog = [];

  int? _writeConcurrency;

  /// Write batches in flight at once: two on a remote provider, one on a
  /// local server (one generation slot). Settable for tests.
  int get writeConcurrency =>
      _writeConcurrency ??
      (llm is LlmApiEndpoint &&
              !isLocalRemoteUrl((llm as LlmApiEndpoint).apiUrl)
          ? kWorldWriteConcurrencyRemote
          : 1);
  set writeConcurrency(int value) => _writeConcurrency = value;

  /// How long one tool call may take before it is abandoned and asked
  /// again (tests pass something short).
  Duration callTimeout = kWorldToolCallTimeout;

  bool _aborted = false;
  final List<LorebookEntry> entries = [];
  final Set<String> _written = {};
  Map<String, dynamic>? biome;

  bool get aborted => _aborted;

  /// Every signed card's name this run, so an entry can name the cards it
  /// should pull (the recipe's "chain, don't catalogue").
  List<String> shelfNames = const [];

  /// The signed cards by lowercase name, kept so the Review step can fetch
  /// a card's articles again for a rewrite.
  final Map<String, WorldProposedCard> shelfCards = {};

  /// What the entry loop did to each entry, by lowercase name.
  final Map<String, WorldEntryNote> entryNotes = {};

  /// The tag sets from the newest [scan] — the scout prompt shows them
  /// so a tags-only wiki (Neokosmos) can reveal its places (slice 8).
  Map<String, List<String>> lastCatalogTags = const {};

  void abort() {
    _aborted = true;
    llm.abortGeneration();
    debugPrint('[World] abort');
  }

  /// Hooks the source onto this run (the chat Skim needs the model and
  /// the budget; the wiki ignores it). Idempotent; every pass calls it.
  void bindSource() => source.bind(
    llm: llm,
    budget: budget,
    onProgress: onProgress,
    callTimeout: callTimeout,
    retryPause: retryPause,
    isAborted: () => _aborted,
  );

  /// The label a prompt gives a card's text: a wiki reads articles, a
  /// record reads source lines.
  String get sourceLabel => mode == null ? 'ARTICLES:' : 'SOURCE LINES:';

  Future<WikiStudioCatalog> scan({String? seedQuery}) async {
    bindSource();
    final catalog = await source.catalog(seedQuery: seedQuery);
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
    onProgress?.call(worldProgressRummaging());
    final catalog = await scan(
      seedQuery: [
        worldName.trim(),
        premise.trim(),
      ].where((s) => s.isNotEmpty).join(' '),
    );
    if (_aborted) {
      return WorldScoutResult(catalog: catalog, proposed: const []);
    }
    onProgress?.call(
      worldProgressCatalog(catalog.titles.length, ranked: catalog.ranked),
    );
    final runner =
        WorldScoutRunner(
            llm: llm,
            budget: budget,
            depth: depth,
            moment: moment,
            onProgress: onProgress,
            isAborted: () => _aborted,
          )
          ..callTimeout = callTimeout
          ..concurrency = writeConcurrency
          ..retryPause = retryPause
          ..mode = mode
          ..cardTargetOverride = source.cardTarget(depth)
          ..scoutRangeOverride = source.scoutRange(depth);
    final scouted = await runner.run(
      titles: catalog.titles,
      tags: lastCatalogTags,
      worldName: worldName,
      premise: premise,
    );
    final proposed = scouted.cards;
    onProgress?.call(
      worldProgressShelfReady(proposed.length, scouted.places.length),
    );
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
      notes: scouted.notes,
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
    bindSource();
    rememberShelf(signed);
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
      articleFor: articleForCard,
      onMiss: noteMiss,
      stop: () => _aborted,
    );
    onProgress?.call(worldProgressReading(k));
    final planned = await batches.toList();
    final written = await forEachLimited(planned, writeConcurrency, (
      i,
      batch,
    ) async {
      if (_aborted) return const <WorldCraftDraft>[];
      done += batch.cards.length;
      debugPrint(
        '[World] write batch ${i + 1}/${planned.length} '
        'names=${batch.cards.map((c) => c.name).join(', ')}',
      );
      onProgress?.call(
        worldProgressWriting(done - batch.cards.length + 1, done, k),
      );
      final generated = await writeBatch(
        cards: batch.cards,
        articles: batch.articles,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
      );
      return reviewBatch(
        cards: batch.cards,
        articles: batch.articles,
        drafts: matchWorldWriteBatch(batch.cards, generated),
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
      );
    });
    if (_aborted) debugPrint('[World] abort');
    for (final r in written) {
      drafts.addAll(r);
    }
    if (climateEnabled && !_aborted) {
      final climate = await _writeClimate(
        worldName: worldName,
        premise: premise,
      );
      if (climate != null) {
        biome = climate.biome;
        onProgress?.call(
          worldProgressWeatherDone('${climate.biome['displayName'] ?? ''}'),
        );
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
    entries.addAll(
      applyWorldCraftMechanics(
        polishWorldDrafts(drafts, allNames: pending.map((c) => c.name)),
      ),
    );
    return List<LorebookEntry>.unmodifiable(entries);
  }

  /// A place's book is finished (the root last): a live harness keeps
  /// each one as it lands, so a run cut short still leaves its work.
  void Function(WorldPlaceWrite place)? onPlaceWritten;

  /// The part of a write prompt every batch repeats: world, premise and
  /// the attached notes. Sized once so the batcher knows the fixed cost.
  /// The run's shelf: names for the prompts, cards for later rewrites.
  void rememberShelf(List<WorldProposedCard> signed) {
    shelfNames = [for (final c in signed) c.name];
    for (final c in signed) {
      shelfCards[c.name.trim().toLowerCase()] = c;
    }
  }

  Future<List<WorldLoreWrite>> writeBatch({
    required List<WorldProposedCard> cards,
    required List<String> articles,
    required String worldName,
    required String premise,
    required String extraLore,
    bool split = true,
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
      buf.writeln(sourceLabel);
      buf.writeln(articles[i]);
    }
    buf.writeln();
    buf.writeln(
      'Call $kWorldLoreBatchToolName once. One entry per card above, '
      'same names. HARD CAP $kWorldLoreContentMax characters — two short '
      'sentences. Keys: 2–6 per entry, each a whole name or alias a chat '
      'would type ("Spiritual Pressure", "Soul Reaper"), never a name '
      'split into words. ${worldMomentRule(moment)} For a person: one '
      'clause of how they look or carry themselves, and where they are '
      'and who they are with at that moment. For a place: what a visitor '
      'sees and hears, and who holds it. $kWorldWriteChainRule they/them '
      'for unnamed people. Do not invent climate, biomes, or facts missing '
      'from the articles.',
    );
    final prompt = buf.toString();
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: kWorldWriteReplyWant),
        minLength: 16,
        temperature: 0.4,
        reasoningEnabled: true,
        toolChoice: kWorldLoreBatchToolName,
      ),
      tools: worldLoreBatchToolSchema(),
      label: 'write batch of ${cards.length}',
      note: onProgress,
      toolName: kWorldLoreBatchToolName,
      floorKey: 'entries',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp != null) return parseWorldLoreBatchCalls(resp.calls);
    // Twice is the server's fault or the batch's size. A batch of several
    // cards is asked once more as two halves (each with its own retry);
    // a single card that fails twice is a miss the status line counts.
    if (!split || cards.length < 2) {
      debugPrint(
        '[World] write batch miss for ${cards.map((c) => c.name).join(', ')}',
      );
      return const [];
    }
    final mid = (cards.length + 1) ~/ 2;
    debugPrint(
      '[World] write batch of ${cards.length} failed twice — asking as '
      '$mid + ${cards.length - mid}',
    );
    return [
      ...await writeBatch(
        cards: cards.sublist(0, mid),
        articles: articles.sublist(0, mid),
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
        split: false,
      ),
      ...await writeBatch(
        cards: cards.sublist(mid),
        articles: articles.sublist(mid),
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
        split: false,
      ),
    ];
  }

  Future<WorldClimateWrite?> _writeClimate({
    required String worldName,
    required String premise,
  }) async {
    onProgress?.call(worldProgressClimate());
    bindSource();
    final titles = await source.climateTitles(
      allowGuess: mode?.guessesClimate ?? false,
    );
    if (titles.isEmpty) {
      debugPrint('[World] climate miss no titles');
      if (mode != null) onProgress?.call(worldProgressNoWeather());
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
      final resp = await askToolsTwice(
        llm,
        params: GenerationParams(
          prompt: prompt,
          maxLength: budget.replyFor(prompt, floor: kWorldClimateReplyWant),
          minLength: 16,
          temperature: 0.4,
          reasoningEnabled: true,
          toolChoice: kWorldClimateToolName,
        ),
        tools: worldClimateToolSchema(),
        label: 'climate',
        note: onProgress,
        toolName: kWorldClimateToolName,
        floorKey: 'biome',
        pause: retryPause,
        timeout: callTimeout,
      );
      if (resp == null) return null;
      return parseWorldClimateCalls(resp.calls);
    } catch (e) {
      debugPrint('[World] climate miss ($e)');
      return null;
    }
  }
}
