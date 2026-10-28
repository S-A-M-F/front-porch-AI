// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The shelf loop: the merged shelf is gated in Dart (auditWorldShelf),
// reviewed by a second model call as a roleplay world, and revised with
// the findings, up to the depth's tries; the best valid shelf stands.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_build_mode.dart';
import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_from_wiki_scout.dart';
import 'world_from_wiki_tools.dart';
import 'world_places.dart';
import 'world_review_loop.dart';
import 'world_review_tools.dart';
import 'world_shelf_audit.dart';

/// A shelf as the loop passes it around.
typedef WorldShelf = ({
  List<WorldProposedCard> cards,
  List<WorldProposedPlace> places,
});

extension WorldScoutReviewLoop on WorldScoutRunner {
  /// Gate, review, revise. Returns [first] unchanged when it passes at
  /// once; otherwise the best shelf of the tries, with the notes.
  Future<WorldScoutRun> reviewLoop(
    WorldScoutRun first, {
    required List<String> lines,
    required List<String> titles,
    required bool tagged,
    required String worldName,
    required String premise,
  }) async {
    final result = await runWorldLoop<WorldShelf>(
      stage: 'Reading the shelf as a roleplay world',
      tries: depth.tries,
      status: (m) => onProgress?.call('$m…'),
      stop: () => isAborted?.call() ?? false,
      generate: (attempt, previous, feedback) async {
        if (attempt == 1) return (cards: first.cards, places: first.places);
        final base = previous ?? (cards: first.cards, places: first.places);
        return _revise(
          base,
          feedback,
          lines: lines,
          titles: titles,
          worldName: worldName,
          premise: premise,
        );
      },
      gate: (shelf) => auditWorldShelf(
        shelf.cards,
        places: shelf.places,
        tagged: tagged,
      ).problems,
      review: (shelf) => _reviewShelf(
        shelf,
        lines: lines,
        worldName: worldName,
        premise: premise,
      ),
    );
    final best = result.best;
    final notes = [for (final n in result.notes) n.toString()];
    if (best == null) return first.copyWith(notes: notes);
    final revised = result.bestAttempt > 1;
    final problems = [
      for (final n in result.notes)
        if (n.verdict == 'INVALID' || n.verdict == 'FAIL') n.note,
    ];
    return first.copyWith(
      cards: liftPlaceHubCards(best.cards, best.places),
      places: best.places,
      revised: revised,
      auditNotes: result.passed && !revised ? const [] : problems,
      notes: notes,
    );
  }

  /// The model's second look at the shelf.
  Future<WorldVerdict> _reviewShelf(
    WorldShelf shelf, {
    required List<String> lines,
    required String worldName,
    required String premise,
  }) async {
    final head =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        'SHELF (name | kind | role | place | sources):\n'
        '${_shelfLines(shelf)}\n'
        'PLACES: ${shelf.places.map((p) => p.parentName.isEmpty ? p.name : '${p.name} (inside ${p.parentName})').join('; ')}\n\n'
        'Conventions: role era marks the one era card and its kind is event; '
        'kind says what a card is about; a card\'s place is the book it lives '
        'in — for a person, where they stand at the moment, for a place, the '
        'place around it. Do not fault these.\n'
        '${mode == null ? '' : '${mode!.shelfRule}\n'}'
        'Review this shelf as the world a fan would roleplay in. '
        '${worldMomentRule(moment)} Judge: are the places nested the way '
        'the setting has them; does each place carry the people and '
        'smaller places the index shows for it; do factions have members; '
        'is there one era card and is it true as of the moment; is '
        'anything invented or from another setting. Name index titles '
        'that belong on the shelf and are missing. Pass only a shelf a fan '
        'would accept. Call $kWorldShelfReviewToolName once.\n';
    final index = budget.clipForReply(
      lines.join('\n'),
      want: kWorldScoutReplyFloor,
      fixedTokens: worldWikiEstimateTokens(head) + 64,
    );
    final prompt = '${head}INDEX TITLES:\n$index';
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: kWorldScoutReplyFloor),
        minLength: 16,
        temperature: 0.2,
        reasoningEnabled: true,
        toolChoice: kWorldShelfReviewToolName,
      ),
      tools: worldShelfReviewToolSchema(),
      label: 'shelf review',
      note: onProgress,
      toolName: kWorldShelfReviewToolName,
      floorKey: 'pass',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) return WorldVerdict.skipped;
    return parseWorldShelfVerdict(resp.calls);
  }

  /// The revise call: the shelf, the findings, as much of the index as
  /// the window leaves, and the same tool. Null when nothing came back.
  Future<WorldShelf?> _revise(
    WorldShelf shelf,
    List<String> findings, {
    required List<String> lines,
    required List<String> titles,
    required String worldName,
    required String premise,
  }) async {
    final (lo, hi) = scoutRange;
    final head =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        'FIRST SHELF (name | kind | role | place | sources):\n'
        '${_shelfLines(shelf)}\n'
        '${shelf.places.isEmpty ? '' : 'PLACES NAMED: ${shelf.places.map((p) => p.name).join(', ')}\n'}'
        'REVIEW FOUND:\n- ${findings.join('\n- ')}\n\n'
        'Revise the shelf into a world: fix every finding above, keep what '
        'already serves the setting, and return the COMPLETE corrected '
        'shelf ($lo–$hi cards, places included) with $kWorldScoutToolName.\n'
        '$kWorldScoutPrompt\n${worldMomentRule(moment)}\n';
    final index = budget.clipForReply(
      lines.join('\n'),
      want: kWorldScoutReplyWant,
      fixedTokens: worldWikiEstimateTokens(head) + 64,
    );
    final prompt =
        '${head}INDEX TITLES:\n$index\n\nCall $kWorldScoutToolName once.';
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: kWorldScoutReplyFloor),
        minLength: 16,
        temperature: 0.3,
        reasoningEnabled: true,
        toolChoice: kWorldScoutToolName,
      ),
      tools: worldScoutToolSchema(),
      label: 'shelf revise',
      note: onProgress,
      toolName: kWorldScoutToolName,
      floorKey: 'cards',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) return null;
    final cards = parseWorldScoutToolCalls(
      resp.calls,
      catalog: titles,
      max: cardTarget,
      keepUnsourced: keepUnsourced,
    );
    if (cards.length < kWorldScoutCardMin) {
      debugPrint('[World] shelf revise returned ${cards.length} cards');
      return null;
    }
    return (cards: cards, places: parseWorldScoutPlaces(resp.calls));
  }

  String _shelfLines(WorldShelf shelf) => [
    for (final c in shelf.cards)
      '- ${c.name} | ${c.kind.isEmpty ? '?' : c.kind} | ${c.role.name}'
          '${c.place.isEmpty ? '' : ' | in ${c.place}'}'
          ' | ${c.sourceTitles.join(', ')}'
          '${c.invented ? ' | invented' : ''}',
  ].join('\n');
}
