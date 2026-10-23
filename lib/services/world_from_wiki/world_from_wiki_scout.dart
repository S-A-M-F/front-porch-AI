// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scout inside the wizard's context: the index is asked in parts that
// each leave the reply room, a part the model cannot finish is asked again
// in halves, and the answers merge into one shelf. Size never fails the
// wizard while a smaller part is left to try.

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_from_wiki_tools.dart';
import 'world_places.dart';
import 'world_shelf_audit.dart';

/// What one scout pass produced across every part of the index.
class WorldScoutRun {
  const WorldScoutRun({
    this.cards = const [],
    this.places = const [],
    this.failure,
    this.parts = 0,
    this.partsCut = 0,
    this.revised = false,
    this.auditNotes = const [],
  });

  final List<WorldProposedCard> cards;
  final List<WorldProposedPlace> places;

  /// True when the review pass replaced the scout's shelf with a better
  /// one; [auditNotes] then says what was wrong with the first.
  final bool revised;

  /// What the shelf review found; empty when the shelf read as a world.
  /// With [revised] false these are the problems that remain.
  final List<String> auditNotes;

  /// Plain words when the shelf is empty for a reason other than the
  /// model's judgement.
  final String? failure;

  /// How many requests the index took (1 = asked whole).
  final int parts;

  /// Parts the model could not finish even at the smallest size; their
  /// titles are missing from the shelf.
  final int partsCut;
}

class WorldScoutRunner {
  WorldScoutRunner({
    required this.llm,
    required this.budget,
    this.onProgress,
    this.isAborted,
  });

  final LLMService llm;
  final WorldWikiBudget budget;
  final void Function(String message)? onProgress;
  final bool Function()? isAborted;

  Future<WorldScoutRun> run({
    required List<String> titles,
    required Map<String, List<String>> tags,
    required String worldName,
    required String premise,
  }) async {
    if (titles.isEmpty) return const WorldScoutRun();
    final lines = worldScoutIndexLines(titles, tags);
    final queue = splitWorldScoutIndex(
      lines,
      budget: budget,
      promptFor: (part) =>
          _prompt(part, worldName: worldName, premise: premise, total: 1),
    );
    var total = queue.length;
    var asked = 0;
    var cut = 0;
    var lengthCuts = 0;
    String? firstFailure;
    final cards = <WorldProposedCard>[];
    final seenCards = <String>{};
    final places = <WorldProposedPlace>[];
    final seenPlaces = <String>{};

    while (queue.isNotEmpty) {
      if (isAborted?.call() ?? false) break;
      final part = queue.removeAt(0);
      asked++;
      if (total > 1) {
        onProgress?.call(
          'Scouting part $asked of $total (${part.length} titles)…',
        );
      }
      final prompt = _prompt(
        part,
        worldName: worldName,
        premise: premise,
        index: asked,
        total: total,
      );
      final reply = budget.replyFor(prompt, floor: kWorldScoutReplyFloor);
      LlmToolResponse? resp;
      try {
        resp = await llm.generateWithTools(
          GenerationParams(
            prompt: prompt,
            maxLength: reply,
            minLength: 16,
            temperature: 0.3,
            reasoningEnabled: true,
            toolChoice: kWorldScoutToolName,
          ),
          worldScoutToolSchema(),
        );
      } catch (e) {
        // A busy or unreachable server will not answer a smaller part
        // either; keep what earlier parts gave and say why this stopped.
        debugPrint('[World] scout tools miss ($e)');
        return WorldScoutRun(
          cards: cards,
          places: places,
          failure: cards.isEmpty ? worldScoutTransportCopy(e) : null,
          parts: asked,
          partsCut: cut,
        );
      }
      final got = resp == null
          ? const <WorldProposedCard>[]
          : parseWorldScoutToolCalls(resp.calls, catalog: titles);
      if (got.isEmpty && resp != null && resp.calls.isNotEmpty) {
        // A list came back and nothing in it survived the parse: say what
        // the first item looked like, or this reads as the model's choice.
        final raw = resp.calls.first.arguments['cards'];
        final first = raw is List && raw.isNotEmpty ? raw.first : null;
        final shown = first == null ? 'none' : jsonEncode(first);
        final count = raw is List ? raw.length : 0;
        debugPrint(
          '[World] scout answered $count raw cards, none usable; '
          'first=${shown.length > 400 ? '${shown.substring(0, 400)}…' : shown}',
        );
        if (count > 0) {
          firstFailure ??=
              'The model answered with $count cards, but none of them named '
              'a page from the index, so there was nothing to read. Press '
              'Scout again, or pick a different model.';
        }
      }
      if (got.isEmpty && worldScoutReplyWasCut(resp)) {
        if (part.length > kWorldScoutMinPart) {
          final (a, b) = halveWorldScoutPart(part);
          queue.insertAll(0, [a, b]);
          total += 1;
          debugPrint(
            '[World] scout part of ${part.length} titles cut at $reply '
            'tokens — asking again as ${a.length} + ${b.length}',
          );
          continue;
        }
        cut++;
        if (resp?.finishReason == 'length') {
          lengthCuts++;
        } else {
          // Not cut for room: a call the server dropped or a list that
          // would not parse. Its own words beat "give it more context".
          firstFailure ??= worldScoutEmptyReason(
            resp,
            budget: reply,
            contextTokens: budget.contextTokens,
          );
        }
        debugPrint(
          '[World] scout part of ${part.length} titles cut at $reply tokens '
          '— smallest part, its titles are skipped',
        );
        continue;
      }
      if (got.isEmpty) {
        firstFailure ??= worldScoutEmptyReason(
          resp,
          budget: reply,
          contextTokens: budget.contextTokens,
        );
        if (firstFailure != null) {
          debugPrint(
            '[World] scout part empty finish=${resp?.finishReason} '
            'calls=${resp?.calls.length ?? 0}: $firstFailure',
          );
        }
        continue;
      }
      for (final c in got) {
        if (cards.length >= kWorldScoutCardMax) break;
        if (seenCards.add(c.name.toLowerCase())) cards.add(c);
      }
      for (final p in parseWorldScoutPlaces(resp!.calls)) {
        if (places.length >= kWorldScoutPlaceMax) break;
        if (seenPlaces.add(p.key)) places.add(p);
      }
    }
    String? failure;
    if (cards.isEmpty) {
      failure = lengthCuts > 0
          ? worldScoutCutCopy(contextTokens: budget.contextTokens, parts: asked)
          : firstFailure;
    }
    final first = WorldScoutRun(
      cards: liftPlaceHubCards(cards, places),
      places: places,
      failure: failure,
      parts: asked,
      partsCut: cut,
    );
    if (cards.isEmpty || (isAborted?.call() ?? false)) return first;
    return _review(
      first,
      lines: lines,
      titles: titles,
      tagged: tags.values.any((t) => t.isNotEmpty),
      worldName: worldName,
      premise: premise,
    );
  }

  /// The review pass: audit the merged shelf as a world; when it fails,
  /// ask the model once to revise it against the problems and the index,
  /// and keep whichever shelf has fewer problems. Never fewer cards than
  /// the minimum, never a shelf from a call that did not answer.
  Future<WorldScoutRun> _review(
    WorldScoutRun first, {
    required List<String> lines,
    required List<String> titles,
    required bool tagged,
    required String worldName,
    required String premise,
  }) async {
    final audit = auditWorldShelf(
      first.cards,
      places: first.places,
      tagged: tagged,
    );
    if (audit.ok) return first;
    debugPrint('[World] shelf review: ${audit.problems.join('; ')}');
    onProgress?.call('Reviewing the shelf…');
    final kept = WorldScoutRun(
      cards: first.cards,
      places: first.places,
      failure: first.failure,
      parts: first.parts,
      partsCut: first.partsCut,
      auditNotes: audit.problems,
    );
    final prompt = _revisePrompt(
      first,
      audit,
      lines: lines,
      worldName: worldName,
      premise: premise,
    );
    LlmToolResponse? resp;
    try {
      resp = await llm.generateWithTools(
        GenerationParams(
          prompt: prompt,
          maxLength: budget.replyFor(prompt, floor: kWorldScoutReplyFloor),
          minLength: 16,
          temperature: 0.3,
          reasoningEnabled: true,
          toolChoice: kWorldScoutToolName,
        ),
        worldScoutToolSchema(),
      );
    } catch (e) {
      debugPrint('[World] shelf review miss ($e)');
      return kept;
    }
    if (resp == null) return kept;
    final cards = parseWorldScoutToolCalls(resp.calls, catalog: titles);
    if (cards.length < kWorldScoutCardMin) {
      debugPrint('[World] shelf review returned ${cards.length} cards — kept');
      return kept;
    }
    final places = parseWorldScoutPlaces(resp.calls);
    final after = auditWorldShelf(cards, places: places, tagged: tagged);
    if (after.problems.length >= audit.problems.length) {
      debugPrint(
        '[World] shelf review did not improve: ${after.problems.join('; ')}',
      );
      return kept;
    }
    debugPrint(
      '[World] shelf revised cards=${cards.length} places=${places.length} '
      'left=${after.problems.join('; ')}',
    );
    return WorldScoutRun(
      cards: liftPlaceHubCards(cards, places),
      places: places,
      parts: first.parts,
      partsCut: first.partsCut,
      revised: true,
      auditNotes: audit.problems,
    );
  }

  String _revisePrompt(
    WorldScoutRun run,
    WorldShelfAudit audit, {
    required List<String> lines,
    required String worldName,
    required String premise,
  }) {
    final shelf = [
      for (final c in run.cards)
        '- ${c.name} | ${c.kind.isEmpty ? '?' : c.kind} | ${c.role.name}'
            '${c.place.isEmpty ? '' : ' | in ${c.place}'}'
            ' | ${c.sourceTitles.join(', ')}',
    ].join('\n');
    final placesLine = run.places.isEmpty
        ? ''
        : 'PLACES NAMED: ${run.places.map((p) => p.name).join(', ')}\n';
    final head =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'FIRST SHELF (name | kind | role | place | sources):\n$shelf\n'
        '$placesLine'
        'REVIEW FOUND:\n- ${audit.problems.join('\n- ')}\n\n'
        'Revise the shelf into a world: fix every finding above, keep what '
        'already serves the setting, and return the COMPLETE corrected '
        'shelf (20–40 cards, places included) with $kWorldScoutToolName.\n'
        '$kWorldScoutPrompt\n';
    // The index rides along as far as the window allows, so the revise
    // can swap people for the places and factions the wiki really has.
    final index = budget.clipForReply(
      lines.join('\n'),
      want: kWorldScoutReplyWant,
      fixedTokens: worldWikiEstimateTokens(head) + 64,
    );
    return '${head}INDEX TITLES:\n$index\n\nCall $kWorldScoutToolName once.';
  }

  String _prompt(
    List<String> part, {
    required String worldName,
    required String premise,
    int index = 1,
    required int total,
  }) {
    final partNote = total > 1
        ? ' (part $index of $total — the parts are merged after; propose '
              'the cards these titles support)'
        : '';
    return 'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        'INDEX TITLES$partNote:\n${part.join('\n')}\n\n'
        '$kWorldScoutPrompt\n'
        'Call $kWorldScoutToolName once.';
  }
}
