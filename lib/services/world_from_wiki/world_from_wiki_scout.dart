// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The scout inside the wizard's context: the index is asked in parts that
// each leave the reply room, a part the model cannot finish is asked again
// in halves, and the answers merge into one shelf. Size never fails the
// wizard while a smaller part is left to try.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_from_wiki_tools.dart';
import 'world_places.dart';

/// What one scout pass produced across every part of the index.
class WorldScoutRun {
  const WorldScoutRun({
    this.cards = const [],
    this.places = const [],
    this.failure,
    this.parts = 0,
    this.partsCut = 0,
  });

  final List<WorldProposedCard> cards;
  final List<WorldProposedPlace> places;

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
    return WorldScoutRun(
      cards: cards,
      places: places,
      failure: failure,
      parts: asked,
      partsCut: cut,
    );
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
