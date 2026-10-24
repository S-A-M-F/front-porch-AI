// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The fill loop: the coverage audit reads the catalog the scout read —
// its most-linked pages and their categories — and names the gaps; each
// gap is one focused call with its candidate titles; rounds by depth,
// until the gaps close or the card target is reached. This is how the
// Royal Guard gets its five, and a place its residents.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_from_wiki_budget.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_places_tools.dart';
import 'world_from_wiki_scout.dart';
import 'world_from_wiki_tools.dart';
import 'world_places.dart';
import 'world_shelf_audit.dart';
import 'world_progress_copy.dart';

/// Gaps worked per round at most; the rest wait for the next round.
const int kWorldFillGapsPerRound = 6;

extension WorldScoutFillLoop on WorldScoutRunner {
  Future<WorldScoutRun> fillLoop(
    WorldScoutRun run, {
    required List<String> titles,
    required Map<String, List<String>> tags,
    required String worldName,
    required String premise,
  }) async {
    var cards = List<WorldProposedCard>.from(run.cards);
    var places = List<WorldProposedPlace>.from(run.places);
    final notes = List<String>.from(run.notes);
    final seenCards = {for (final c in cards) c.name.trim().toLowerCase()};
    final seenPlaces = {for (final p in places) p.key};
    final lineByTitle = {
      for (final line in worldScoutIndexLines(titles, tags))
        worldScoutBareTitle(line.substring(2)).toLowerCase(): line,
    };
    for (var round = 1; round <= depth.fillRounds; round++) {
      if (isAborted?.call() ?? false) break;
      if (cards.length >= depth.cardTarget) break;
      final gaps = auditWorldCoverage(
        cards: cards,
        places: places,
        titles: titles,
        tags: tags,
        depth: depth,
      );
      if (gaps.isEmpty) {
        notes.add('Fill round $round: nothing missing');
        break;
      }
      var added = 0;
      for (final gap in gaps.take(kWorldFillGapsPerRound)) {
        if (isAborted?.call() ?? false) break;
        final room = depth.cardTarget - cards.length;
        if (room <= 0) break;
        onProgress?.call(
          worldProgressFill(
            _gapLabel(gap),
            round,
            depth.fillRounds,
            gap.candidates.length,
          ),
        );
        final answer = await _askGap(
          gap,
          cards: cards,
          places: places,
          lineByTitle: lineByTitle,
          titles: titles,
          worldName: worldName,
          premise: premise,
          room: room,
        );
        if (answer == null) {
          notes.add('Fill ${_gapLabel(gap)}: no answer');
          continue;
        }
        var got = 0;
        for (final p in answer.places) {
          if (places.length >= kWorldScoutPlaceMax) break;
          if (seenPlaces.add(p.key)) places.add(p);
        }
        for (final c in answer.cards) {
          if (cards.length >= depth.cardTarget) break;
          if (!seenCards.add(c.name.trim().toLowerCase())) continue;
          cards.add(
            gap.place != null && c.place.trim().isEmpty
                ? WorldProposedCard(
                    name: c.name,
                    keys: c.keys,
                    role: c.role,
                    sourceTitles: c.sourceTitles,
                    group: c.group,
                    kind: c.kind,
                    place: gap.place!,
                  )
                : c,
          );
          got++;
        }
        added += got;
        notes.add('Fill ${_gapLabel(gap)}: $got cards');
      }
      debugPrint(
        '[World] fill round $round: +$added cards, shelf=${cards.length}, '
        'places=${places.length}',
      );
      if (added == 0) break;
    }
    return run.copyWith(
      cards: liftPlaceHubCards(cards, places),
      places: resolvePlaceOrder(places),
      notes: notes,
    );
  }

  String _gapLabel(WorldCoverageGap gap) => switch (gap.kind) {
    'place' => 'the missing places',
    'faction' => '${gap.name} members',
    'thinPlace' => gap.name,
    _ => 'the main cast',
  };

  Future<({List<WorldProposedCard> cards, List<WorldProposedPlace> places})?>
  _askGap(
    WorldCoverageGap gap, {
    required List<WorldProposedCard> cards,
    required List<WorldProposedPlace> places,
    required Map<String, String> lineByTitle,
    required List<String> titles,
    required String worldName,
    required String premise,
    required int room,
  }) async {
    final want = gap.candidates.length.clamp(1, room);
    final task = switch (gap.kind) {
      'place' =>
        'These top pages of the wiki are places this world lacks. Add each '
            'that belongs as a place (with parentName from the places list '
            'where it lies inside one, or empty) and give it one hub card '
            '(kind place).',
      'faction' =>
        'The wiki files these pages under ${gap.name}. Add the ones that '
            'matter as cards (kind person for people), each with place set '
            'to where they stand at the moment'
            '${gap.place == null ? '' : ' ("${gap.place}" unless the article says otherwise)'}.',
      'thinPlace' =>
        'The wiki files these pages under ${gap.name}, a place on this shelf '
            'with too few cards. Add its ${depth.memberCards ? 'people, factions and smaller places' : 'factions, smaller places and only its main people'} '
            'as cards with place "${gap.name}".',
      _ =>
        'These are the wiki\'s most-linked characters not yet on the shelf. '
            'Add the ones that belong in this world at the moment (kind '
            'person), each with place set to where they stand.',
    };
    final prompt =
        'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        'PLACES: ${places.map((p) => p.name).join(', ')}\n'
        'ALREADY ON THE SHELF: ${cards.map((c) => c.name).join(', ')}\n'
        'CANDIDATES (sourceTitles must come from these):\n'
        '${[for (final t in gap.candidates) lineByTitle[t.toLowerCase()] ?? '- $t'].join('\n')}\n\n'
        '$task Up to $want cards; skip a candidate that does not belong. '
        'Set kind on every card. Do not repeat a name already on the shelf. '
        '${worldMomentRule(moment)}\nCall $kWorldScoutToolName once.';
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
      label: 'fill ${gap.kind} ${gap.name}',
      note: onProgress,
      toolName: kWorldScoutToolName,
      floorKey: 'cards',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) return null;
    return (
      cards: parseWorldScoutToolCalls(resp.calls, catalog: titles, max: room),
      places: parseWorldScoutPlaces(resp.calls),
    );
  }
}
