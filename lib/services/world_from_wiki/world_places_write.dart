// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 8 (design §9.4/§9.5): the tree-shaped write. The flat
// `WorldFromWikiEngine.write` is untouched and still pinned; this pass
// runs the SAME batch machinery per place, asks each place (and the
// root) for a short profile — description plus, only where the sources
// show one, that place's own biome — and returns a WorldWriteTree the
// save turns into a root World with children. Lives beside the engine,
// not inside it: the engine file is close to the 500-line bar and one
// responsibility per file is the house law.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_entry_polish.dart';
import 'world_entry_review.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_engine.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_places.dart';
import 'world_progress_copy.dart';

extension WorldFromWikiPlacesWrite on WorldFromWikiEngine {
  /// Signed cards + scout places → one book per place, profiles per
  /// place, build-ordered. With no places this is the flat write
  /// wearing its tree clothes (one root, empty children).
  Future<WorldWriteTree> writeTree(
    List<WorldProposedCard> signed, {
    required List<WorldProposedPlace> places,
    required String worldName,
    required String premise,
    String extraLore = '',
    bool climateEnabled = false,
    Set<String> climatePlaces = const {},
  }) async {
    rememberShelf(signed);
    if (places.isEmpty) {
      final flat = await write(
        signed,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
        climateEnabled: climateEnabled,
      );
      return WorldWriteTree(
        root: WorldPlaceWrite(
          name: worldName.trim(),
          parentName: '',
          description: '',
          entries: flat,
          biome: biome,
        ),
        places: const [],
      );
    }

    final kept = _dedupeByName(signed);
    final groups = groupCardsByPlace(liftPlaceHubCards(kept, places), places);
    // A place's own card now sits in the book around it, so "this place
    // has no cards" no longer means the author pruned it: a signed card
    // bearing the place's name keeps the place, even with nothing inside.
    final named = {for (final c in kept) c.name.trim().toLowerCase()};
    final written = <WorldPlaceWrite>[];
    final all = <LorebookEntry>[];

    for (final entry in <(String, WorldProposedPlace?)>[
      ('', null),
      for (final p in places) (p.key, p),
    ]) {
      if (aborted) break;
      final bucketKey = entry.$1;
      final place = entry.$2;
      final cards = groups[bucketKey] ?? const <WorldProposedCard>[];
      final label = place?.name ?? worldName.trim();
      if (place != null && cards.isEmpty && !named.contains(bucketKey)) {
        // An unsigned place with no signed cards is dropped (design
        // §9.3) — the author pruned its cast, the shelf stays clean.
        continue;
      }
      final drafts = await _writeCardsForPlace(
        cards,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
        label: label,
      );
      if (aborted) break;
      final ownClimate =
          climateEnabled &&
          place != null &&
          (place.climateHint.isNotEmpty || climatePlaces.contains(bucketKey));
      final profile = await _profileFor(
        place: place,
        cards: cards,
        worldName: worldName,
        premise: premise,
        wantBiome: ownClimate || place == null && climateEnabled,
      );
      final entries = applyWorldCraftMechanics(
        polishWorldDrafts(drafts, allNames: kept.map((c) => c.name)),
      );
      all.addAll(entries);
      written.add(
        WorldPlaceWrite(
          name: label,
          parentName: place?.parentName ?? '',
          description: profile?.description ?? '',
          entries: entries,
          biome: profile?.biome,
        ),
      );
    }

    if (aborted) {
      entries.clear();
      return WorldWriteTree(
        root: WorldPlaceWrite(
          name: worldName.trim(),
          parentName: '',
          description: '',
          entries: const [],
        ),
        places: const [],
      );
    }
    // Keep the engine's legacy surface honest: `entries` is the whole
    // product and `biome` the root's, so every existing gate (canSave,
    // preview, abort-clears-everything) reads the tree correctly.
    entries
      ..clear()
      ..addAll(all);
    final rootWrite = written.first;
    biome = rootWrite.biome;
    return WorldWriteTree(
      root: rootWrite,
      places: [for (final w in written.skip(1)) w],
    );
  }

  List<WorldProposedCard> _dedupeByName(List<WorldProposedCard> cards) {
    final seen = <String>{};
    return [
      for (final c in cards)
        if (c.name.trim().isNotEmpty && seen.add(c.name.trim().toLowerCase()))
          c,
    ];
  }

  /// The batch loop from `write`, scoped to one place's cards. Same
  /// batcher, same join, same matcher — one prompt family.
  Future<List<WorldCraftDraft>> _writeCardsForPlace(
    List<WorldProposedCard> cards, {
    required String worldName,
    required String premise,
    required String extraLore,
    required String label,
  }) async {
    final drafts = <WorldCraftDraft>[];
    final k = cards.length;
    var done = 0;
    final batches = planWorldWriteBatches(
      cards,
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
      stop: () => aborted,
    );
    final planned = await batches.toList();
    final written = await forEachLimited(planned, writeConcurrency, (
      i,
      batch,
    ) async {
      if (aborted) return const <WorldCraftDraft>[];
      done += batch.cards.length;
      onProgress?.call(
        worldProgressWriting(
          done - batch.cards.length + 1,
          done,
          k,
          book: label,
        ),
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
    for (final r in written) {
      drafts.addAll(r);
    }
    return drafts;
  }

  /// One profile call: the place's short description and (when asked
  /// and shown) its own biome. A miss is an empty description, never a
  /// throw — the place still saves with whatever the author typed.
  Future<({String description, Map<String, dynamic>? biome})?> _profileFor({
    required WorldProposedPlace? place,
    required List<WorldProposedCard> cards,
    required String worldName,
    required String premise,
    required bool wantBiome,
  }) async {
    if (aborted) return null;
    final name = place?.name ?? worldName.trim();
    onProgress?.call(worldProgressProfile(name));
    final titles = <String>[
      ...?place?.sourceTitles,
      for (final c in cards.take(4)) ...c.sourceTitles,
    ].take(3).toList();
    var sources = await joinSources(titles);
    const cap = kWorldPlaceProfileSourceChars * 3;
    if (sources.length > cap) sources = sources.substring(0, cap);
    final prompt =
        'World: ${worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'PLACE: $name'
        '${place != null && place.parentName.isNotEmpty ? ' (inside ${place.parentName})' : ''}\n'
        '${place != null && place.climateHint.isNotEmpty ? 'CLIMATE EVIDENCE (the wiki\'s own words): ${place.climateHint}\n' : ''}'
        'MEMBERS ON SHELF: ${cards.map((c) => c.name).take(12).join(', ')}\n'
        'SOURCES:\n$sources\n\n'
        'Call $kWorldPlaceProfileToolName once. Write 2–4 sentences '
        'a scene set here must know. '
        '${wantBiome ? 'The evidence above speaks to THIS place\'s weather: author the biome from it.' : 'Omit the biome — this place takes the weather of the world around it.'}';
    try {
      final resp = await askToolsTwice(
        llm,
        params: GenerationParams(
          prompt: prompt,
          maxLength: budget.replyFor(prompt, floor: 1024),
          minLength: 16,
          temperature: 0.3,
          reasoningEnabled: true,
          toolChoice: kWorldPlaceProfileToolName,
        ),
        tools: worldPlaceProfileToolSchema(),
        label: 'profile $name',
        note: onProgress,
        toolName: kWorldPlaceProfileToolName,
        floorKey: 'description',
        pause: retryPause,
        timeout: callTimeout,
      );
      if (resp == null) return null;
      final parsed = parseWorldPlaceProfileCall(
        resp.calls,
        expectTool: kWorldPlaceProfileToolName,
      );
      if (parsed == null) return null;
      // Respect the gate even if a chatty model sent a biome anyway.
      return (
        description: parsed.description,
        biome: wantBiome ? parsed.biome : null,
      );
    } catch (e) {
      debugPrint('[World] place profile miss ($e)');
      return null;
    }
  }
}
