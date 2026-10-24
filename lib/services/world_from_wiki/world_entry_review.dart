// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The entry loop, per write batch: every written entry is gated in Dart,
// the ones that pass are read by a second model call against the Moment
// and the article, and only the failing ones go back with the findings.
// An entry that passed on any try is kept from that try; one that never
// passes keeps its latest draft rather than vanishing.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/services/llm_service.dart';

import 'world_craft_mechanics.dart';
import 'world_entry_polish.dart';
import 'world_from_wiki_budget.dart';
import 'world_build_mode.dart';
import 'world_from_wiki_depth.dart';
import 'world_from_wiki_engine.dart';
import 'world_from_wiki_ops.dart';
import 'world_from_wiki_tools.dart';
import 'world_review_loop.dart';
import 'world_review_tools.dart';
import 'world_progress_copy.dart';
import 'world_write_rules.dart';

/// Characters of each article the reviewer sees beside its entry.
const int kWorldEntryReviewArticleChars = kWorldWriteArticleChars;

extension WorldEntryReviewLoop on WorldFromWikiEngine {
  Future<String> joinSources(List<String> titles) async {
    final buf = StringBuffer();
    for (final title in titles.take(3)) {
      final t = title.trim();
      if (t.isEmpty) continue;
      final article = await source.article(t);
      if (article.isEmpty) {
        debugPrint('[World] write miss $t');
        continue;
      }
      if (buf.isNotEmpty) buf.writeln();
      buf.writeln('=== $t ===');
      buf.writeln(article);
    }
    return buf.toString().trim();
  }

  /// The text a card is written from: its sources joined, or, under a
  /// mode that allows it, a note that the card is invented. '' drops the
  /// card from the write (the batcher's miss).
  Future<String> articleForCard(WorldProposedCard card) async {
    final joined = await joinSources(card.sourceTitles);
    if (joined.isNotEmpty) return joined;
    if (card.invented && (mode?.allowsUnsourced ?? false)) {
      return 'NO SOURCE LINES. This card was proposed from the premise, '
          'not the record: write it to fit the world and contradict '
          'nothing the other cards say.';
    }
    return '';
  }

  /// A card nothing in the source supports. The wiki keeps its silent
  /// skip; under a mode the Review step says why the card is missing.
  void noteMiss(WorldProposedCard card) {
    debugPrint('[World] write miss ${card.name}');
    final m = mode;
    if (m == null) return;
    entryNotes[card.name.trim().toLowerCase()] = WorldEntryNote(
      tries: 0,
      passed: false,
      problem: m.missCopy,
    );
  }

  /// The lines every write-side prompt opens with: world, premise, the
  /// Moment, the shelf's names, and the attached notes.
  String writeHeader({
    required String worldName,
    required String premise,
    required String extraLore,
  }) {
    final extra = extraLore.trim();
    final extraBlock = extra.isEmpty
        ? ''
        : '\nATTACHED NOTES (optional; do not override the articles):\n$extra\n';
    final m = mode;
    return 'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
        'Premise: ${premise.trim()}\n'
        '${worldMomentLine(moment)}'
        '${worldShelfLine(shelfNames)}'
        '${m == null ? '' : '${m.writeRule}\n'}'
        '$extraBlock';
  }

  /// Gate, review, revise the failing, bounded by the depth's tries.
  /// [drafts] are the batch's matched drafts; the result keeps their order.
  Future<List<WorldCraftDraft>> reviewBatch({
    required List<WorldProposedCard> cards,
    required List<String> articles,
    required List<WorldCraftDraft> drafts,
    required String worldName,
    required String premise,
    required String extraLore,
  }) async {
    if (!depth.reviews || drafts.isEmpty) return drafts;
    final cardByName = {
      for (var i = 0; i < cards.length; i++)
        cards[i].name.trim().toLowerCase(): (
          card: cards[i],
          article: articles[i],
        ),
    };
    final current = {for (final d in drafts) d.name.trim().toLowerCase(): d};
    final accepted = <String, WorldCraftDraft>{};
    final lastProblem = <String, String>{};
    var pending = [for (final d in drafts) d.name.trim().toLowerCase()];
    var attempt = 1;
    for (; attempt <= depth.tries; attempt++) {
      if (aborted) break;
      final problems = <String, List<String>>{};
      final toReview = <WorldCraftDraft>[];
      for (final key in pending) {
        final d = current[key];
        if (d == null) continue;
        final gate = worldEntryGate(d);
        if (gate.isNotEmpty) {
          problems[key] = gate;
        } else {
          toReview.add(d);
        }
      }
      if (problems.isNotEmpty) {
        onProgress?.call(
          worldProgressThin(problems.length, problems.values.first.first),
        );
      }
      if (toReview.isNotEmpty) {
        onProgress?.call(
          worldProgressEntriesReview(
            toReview.length,
            attempt: attempt,
            of: depth.tries,
          ),
        );
        final verdicts = await _reviewEntries(
          toReview,
          cardByName: cardByName,
          worldName: worldName,
          premise: premise,
        );
        for (final d in toReview) {
          final key = d.name.trim().toLowerCase();
          final v = verdicts[key];
          if (v != null && v.parsed && !v.pass && v.problems.isNotEmpty) {
            debugPrint('[World] entry review ${d.name}: ${v.problems.first}');
          }
          final m = mode;
          if (v != null &&
              v.parsed &&
              v.pass &&
              v.added.isNotEmpty &&
              m == WorldBuildMode.factsOnly) {
            // Facts only: what the reviewer reports as added is a finding
            // even when it passed the entry on everything else.
            problems[key] = ['states more than its source lines: ${v.added}'];
          } else if (v == null || v.pass || !v.parsed) {
            accepted[key] = d;
            entryNotes[key] = WorldEntryNote(
              tries: attempt,
              passed: true,
              problem: lastProblem[key] ?? '',
              added: v == null || v.added.isEmpty || m == null
                  ? ''
                  : '${m.addedLabel}: ${v.added}',
            );
          } else {
            problems[key] = v.problems;
          }
        }
      }
      for (final e in problems.entries) {
        if (e.value.isNotEmpty) lastProblem[e.key] = e.value.first;
      }
      writeLog.add(
        'Entries try $attempt: ${accepted.length} accepted, '
        '${problems.length} sent back',
      );
      onProgress?.call(
        worldProgressReviewed(
          accepted.length,
          problems.length,
          problems.isEmpty ? '' : problems.values.first.first,
        ),
      );
      if (problems.isEmpty || attempt == depth.tries) break;
      final failingCards = <WorldProposedCard>[];
      final failingArticles = <String>[];
      for (final key in problems.keys) {
        final c = cardByName[key];
        if (c == null) continue;
        failingCards.add(c.card);
        failingArticles.add(c.article);
      }
      if (failingCards.isEmpty) break;
      onProgress?.call(
        worldProgressRewrite(failingCards.length, attempt + 1, depth.tries),
      );
      final revised = await reviseEntries(
        failingCards,
        failingArticles,
        problems: problems,
        current: current,
        worldName: worldName,
        premise: premise,
        extraLore: extraLore,
      );
      for (final d in revised) {
        current[d.name.trim().toLowerCase()] = d;
      }
      pending = [for (final c in failingCards) c.name.trim().toLowerCase()];
    }
    for (final key in pending) {
      if (accepted.containsKey(key)) continue;
      entryNotes[key] = WorldEntryNote(
        tries: attempt > depth.tries ? depth.tries : attempt,
        passed: false,
        problem: lastProblem[key] ?? '',
      );
    }
    return [
      for (final d in drafts)
        accepted[d.name.trim().toLowerCase()] ??
            current[d.name.trim().toLowerCase()] ??
            d,
    ];
  }

  Future<Map<String, WorldVerdict>> _reviewEntries(
    List<WorldCraftDraft> drafts, {
    required Map<String, ({WorldProposedCard card, String article})> cardByName,
    required String worldName,
    required String premise,
  }) async {
    final buf = StringBuffer(
      'World: ${worldName.trim().isEmpty ? 'Untitled' : worldName.trim()}\n'
      'Premise: ${premise.trim()}\n'
      '${worldMomentLine(moment)}'
      '${worldShelfLine(shelfNames)}'
      'ENTRIES TO REVIEW, each with the article it was written from:\n',
    );
    for (final d in drafts) {
      final src = cardByName[d.name.trim().toLowerCase()];
      final article = src?.article ?? '';
      buf.writeln();
      buf.writeln('--- ${d.name} (${src?.card.kind ?? 'card'}) ---');
      buf.writeln('KEYS: ${d.keys.join(', ')}');
      buf.writeln('ENTRY: ${d.content}');
      buf.writeln(
        '${mode == null ? 'ARTICLE' : 'SOURCE LINES'}: ${article.length > kWorldEntryReviewArticleChars ? article.substring(0, kWorldEntryReviewArticleChars) : article}',
      );
    }
    final m = mode;
    final sourceRule = m == null
        ? 'contradicts the article (a fact you cannot find in this excerpt '
              'is not a failure; the writer read more of the page). '
        : 'contradicts its source lines. ${m.reviewRule} ';
    buf.writeln();
    buf.writeln(
      'Review each entry for roleplay. ${worldMomentRule(moment)} An entry '
      'fails when it states anything after the moment, when a person has no '
      'look-or-manner clause or no whereabouts, when a place has no sights '
      'or no holder, when it is one sentence or more than two, or when it '
      '$sourceRule'
      '$kWorldEntryChainRule Pass the '
      'rest; name the problem '
      'in one sentence the writer can act on. Call '
      '$kWorldEntriesReviewToolName once with a verdict per entry.',
    );
    final prompt = buf.toString();
    final resp = await askToolsTwice(
      llm,
      params: GenerationParams(
        prompt: prompt,
        maxLength: budget.replyFor(prompt, floor: kWorldWriteReplyWant),
        minLength: 16,
        temperature: 0.2,
        reasoningEnabled: true,
        toolChoice: kWorldEntriesReviewToolName,
      ),
      tools: worldEntriesReviewToolSchema(),
      label: 'entries review',
      note: onProgress,
      toolName: kWorldEntriesReviewToolName,
      floorKey: 'verdicts',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) return const {};
    return parseWorldEntryVerdicts(resp.calls);
  }

  /// The revise call: each card with what was found against its entry.
  /// Public so a note from the Review step can be the finding.
  Future<List<WorldCraftDraft>> reviseEntries(
    List<WorldProposedCard> cards,
    List<String> articles, {
    required Map<String, List<String>> problems,
    required Map<String, WorldCraftDraft> current,
    required String worldName,
    required String premise,
    required String extraLore,
  }) async {
    final buf = StringBuffer(
      writeHeader(worldName: worldName, premise: premise, extraLore: extraLore),
    );
    for (var i = 0; i < cards.length; i++) {
      final card = cards[i];
      final key = card.name.trim().toLowerCase();
      final old = current[key];
      buf.writeln();
      buf.writeln('--- CARD ${i + 1}/${cards.length} ---');
      buf.writeln('Name: ${card.name}');
      buf.writeln('Role: ${card.role.name}');
      if (old != null) buf.writeln('PREVIOUS ENTRY: ${old.content}');
      buf.writeln('REVIEW FOUND: ${(problems[key] ?? const []).join('; ')}');
      buf.writeln(sourceLabel);
      buf.writeln(articles[i]);
    }
    buf.writeln();
    buf.writeln(
      'Rewrite ONLY these entries so every finding is fixed, same names. '
      'Call $kWorldLoreBatchToolName once. HARD CAP $kWorldLoreContentMax '
      'characters — two short sentences. Keys: 2–6 whole names or aliases. '
      '${worldMomentRule(moment)} For a person: one clause of how they look '
      'or carry themselves, and where they are and who they are with at '
      'that moment. For a place: what a visitor sees and hears, and who '
      'holds it. Do not invent facts missing from the articles.',
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
      label: 'entries revise',
      note: onProgress,
      toolName: kWorldLoreBatchToolName,
      floorKey: 'entries',
      pause: retryPause,
      timeout: callTimeout,
    );
    if (resp == null) {
      debugPrint('[World] entries revise: no answer; the drafts stand');
      return const [];
    }
    return matchWorldWriteBatch(cards, parseWorldLoreBatchCalls(resp.calls));
  }
}
