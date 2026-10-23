// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scout inside the wizard's context: the index is asked in parts that
// each leave the reply room, a part the model cannot finish is asked again
// in halves, and the answers merge into one shelf. Size never fails the
// wizard while a smaller part is left to try.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_from_wiki_tools.dart';
import 'world_places.dart';
import 'world_scout_fill.dart';
import 'world_scout_review.dart';
import 'world_progress_copy.dart';

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
    this.notes = const [],
  });

  final List<WorldProposedCard> cards;
  final List<WorldProposedPlace> places;

  /// The run log: one line per loop try, for the status and the relay.
  final List<String> notes;

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

  WorldScoutRun copyWith({
    List<WorldProposedCard>? cards,
    List<WorldProposedPlace>? places,
    bool? revised,
    List<String>? auditNotes,
    List<String>? notes,
  }) => WorldScoutRun(
    cards: cards ?? this.cards,
    places: places ?? this.places,
    failure: failure,
    parts: parts,
    partsCut: partsCut,
    revised: revised ?? this.revised,
    auditNotes: auditNotes ?? this.auditNotes,
    notes: notes ?? this.notes,
  );
}

class WorldScoutRunner {
  WorldScoutRunner({
    required this.llm,
    required this.budget,
    this.depth = kWorldWikiDepthDefault,
    this.moment = '',
    this.onProgress,
    this.isAborted,
  });

  final LLMService llm;
  final WorldWikiBudget budget;
  final WorldWikiDepth depth;
  final String moment;
  final void Function(String message)? onProgress;
  final bool Function()? isAborted;

  /// How long one part's call may take before it is abandoned.
  Duration callTimeout = kWorldToolCallTimeout;

  /// The wait before a stumbled review, revise or fill call is asked again.
  Duration retryPause = const Duration(seconds: 2);

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
          scoutPrompt(part, worldName: worldName, premise: premise, total: 1),
      minParts: depth.scoutParts,
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
        onProgress?.call(worldProgressScoutPart(asked, total, part.length));
      }
      final prompt = scoutPrompt(
        part,
        worldName: worldName,
        premise: premise,
        index: asked,
        total: total,
      );
      final reply = budget.replyFor(prompt, floor: kWorldScoutReplyFloor);
      LlmToolResponse? resp;
      try {
        resp = await _askPart(prompt);
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
          : parseWorldScoutToolCalls(
              resp.calls,
              catalog: titles,
              max: depth.cardTarget,
            );
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
          onProgress?.call(worldProgressHalving(a.length, b.length));
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
        if (cards.length >= depth.cardTarget) break;
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
    final tagged = tags.values.any((t) => t.isNotEmpty);
    var run = first;
    if (depth.reviews) {
      run = await reviewLoop(
        run,
        lines: lines,
        titles: titles,
        tagged: tagged,
        worldName: worldName,
        premise: premise,
      );
    }
    if (depth.fillRounds > 0) {
      run = await fillLoop(
        run,
        titles: titles,
        tags: tags,
        worldName: worldName,
        premise: premise,
      );
    }
    return run;
  }

  /// One part's call. A prose answer is read for a JSON shelf first (the
  /// text floor under the native call); failing that the model is asked
  /// once more with its thinking off and the one line that usually settles
  /// it (gemma-4 on oMLX answered in prose two runs in four). A second
  /// prose answer with no shelf in it stands.
  Future<LlmToolResponse?> _askPart(String prompt) async {
    LlmToolResponse? resp;
    for (var attempt = 1; attempt <= 2; attempt++) {
      final nudge = attempt == 1
          ? ''
          : '\nAnswer ONLY with the $kWorldScoutToolName tool call — no prose, '
                'no preamble, no markdown.';
      final sent = '$prompt$nudge';
      // Sized from what is actually sent: the nudge costs a line.
      final want = budget.replyFor(sent, floor: kWorldScoutReplyFloor);
      final deadline = worldToolTimeoutFor(callTimeout, want);
      try {
        resp = await llm
            .generateWithTools(
              GenerationParams(
                prompt: sent,
                maxLength: want,
                minLength: 16,
                temperature: 0.3,
                reasoningEnabled: attempt == 1,
                // Thinking within a budget on the first try, off on the
                // second: unbounded thinking over a long index is what
                // ran Kimi past the cutoff.
                reasoningMaxTokens: attempt == 1 ? kWorldThinkTokens : 0,
                toolChoice: kWorldScoutToolName,
              ),
              worldScoutToolSchema(),
            )
            .timeout(deadline);
      } on TimeoutException {
        // A part the server never answers is asked once more, not waited
        // on for ever; a second silence is a transport failure upstream.
        debugPrint('[World] scout part try $attempt: no answer in $deadline');
        llm.abortGeneration();
        if (attempt == 2) rethrow;
        onProgress?.call(worldProgressTimeout(deadline));
        continue;
      }
      final prose =
          resp != null && resp.calls.isEmpty && resp.finishReason != 'length';
      if (!prose) return resp;
      final head = resp.text.replaceAll('\n', ' ');
      debugPrint(
        '[World] scout part answered in prose on try $attempt '
        '(${resp.text.length} chars): '
        '${head.length > 300 ? '${head.substring(0, 300)}…' : head}',
      );
      final floor = worldScoutArgsFromText(resp.text);
      if (floor != null) {
        debugPrint('[World] scout read the shelf from the prose (text floor)');
        onProgress?.call(worldProgressProseRead());
        return LlmToolResponse(
          calls: [LlmToolCall(name: kWorldScoutToolName, arguments: floor)],
          text: '',
          finishReason: resp.finishReason,
        );
      }
      if (attempt == 1) onProgress?.call(worldProgressAskingAgain());
    }
    return resp;
  }

  /// The scout prompt for one part of the index.
  String scoutPrompt(
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
    // Each part is asked for its share; the parts are merged after.
    final (lo0, hi0) = depth.scoutRange;
    final lo = total > 1
        ? max(kWorldScoutPartCardsMin, (lo0 / total).ceil())
        : lo0;
    final hi = total > 1 ? max(lo + 5, (hi0 / total).ceil()) : hi0;
    return 'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        'INDEX TITLES$partNote:\n${part.join('\n')}\n\n'
        '$lo–$hi cards. $kWorldScoutPrompt\n'
        '${worldMomentRule(moment)}\n'
        'Call $kWorldScoutToolName once.';
  }
}
