// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Plain (non-ChangeNotifier) leaf sibling to LlmEvalEngine / realism_evals /
/// objective_proposal owning the Chat Summary feature (// ── Chat Summary ──
/// state coordination stays thin in god): periodic user-message-count driven
/// background generation using active LLM + RAG grounding, prompt template from
/// storage with {{words}}/{{user}}/{{char}} macros, history condensation (skip
/// __director__), previousSummaryBlock, think stripping + numbered analysis
/// block skip + trailing incomplete sentence trim, update scalars + persist,
/// the _isSummaryGenerating flag (via cbs), force/pause/cadence (god thin coord).
///
/// Per extraction order (step 12 after objective_proposal step 11 per
/// docs/refactoring-guide.md table and CLAUDE.md Critical Services / Path Map).
/// Summary is per-chat (not per-speaker like needs); generation context (charName/
/// userName, RAG) must be correct at trigger time (under any god impersonation
/// dance for group post-gen); cadence (user msg count since lastIndex >= interval
/// from storage), pause, force paths guarded in god thins; LLM call specifics
/// (low temp 0.3 for factual, maxLength=words*3 clamp, no reasoning, stops,
/// accumulate + strip completed+unclosed think + skip numbered analysis preamble,
/// keep only prose + final trim) owned here.
///
/// ChatService (god) owns via late final (after _objectiveProposal) +
/// thins/delegates at *every* prior call site for _generateSummaryInBackground,
/// _maybeUpdateSummary, forceSummaryUpdate (full excision of moved code from god).
/// 0 @Deprecated shims.
///
/// Granular callbacks for cross-state (~18: getLlmService for isReady +
/// generateStream with custom budget/temp; getSummaryEnabled/Interval/Prompt/
/// MaxWords from _storageService; getActiveCharacter/getActiveGroup/getUserName/
/// getMessages (history + prompt names + lastIndex on success); getCurrentSummary
/// (previous block); onNotify; onSaveChat (on success update); getIsSummaryGenerating/
/// setIsSummaryGenerating (flag, like isChecking); updateSummary/updateSummaryLastIndex
/// (mutation side-effect on success); isMemoryOperational/getMemorySourceIds/
/// getAllContentForCharacters (RAG grounding block via _getMemorySourceIds +
/// getAllContentForCharacters)). Live closures in god for test overrides + group per-chat context.
///
/// 0 *new* god private _ methods (live `grep -c '^\s*void _[a-zA-Z]'
/// lib/services/chat_service.dart` *must stay exactly 15* after every edit + final;
/// thins + late final + reset comment syncs only).
///
/// Dedicated test `test/services/chat/summary_service_test.dart` using factory
/// (`createTestSummaryService`) with *live* closures over group maps + cbs (real
/// dispatch exercised without forcing god internals); 15 `test()` bodies via
/// live `grep -c '^\s*test('` *post mandatory dead noop/placeholder/vestigial/
/// factory-setup deletion as part of task*.
///
/// aug/integration tests (chat_service_session_test etc.) receive *only* qualified
/// passive notes in headers/comments (exact precedent: "aug exercising only
/// passive/qualified (no summary-specific aug file edits; full in dedicated +
/// manual; exercised via god thins _maybeUpdateSummary/force/generate ;
/// qualified notes only in dedicated header + god + MD per precedent)");
/// no leaf-specific logic edits.
///
/// Strict 1:1 vs group parity for the summary feature (the _summary text,
/// lastIndex, paused, generating flag, generation trigger cadence, force, pause
/// must produce equivalent observable behavior whether 1:1 or group; dispatch
/// preserved via cbs). Group name resolution for {{char}} in prompt at post-gen
/// _maybe trigger (after prePostActiveChar restore in god) is best-effort/timing-
/// dependent (correct for decision/attach via dance; prompt context (charName)
/// may race restore in group non-obs; qualified per step 11 precedent).
///
/// Stateless/prompt-only leaf where possible (no owned reset/seed/load state for
/// the summary scalars — kept thin in god; no reset calls needed on leaf); god
/// reset "keep blocks in sync" comments expanded at *all* ~15+ documented sites
/// (full prior+current list + this leaf as "stateless or prompt-only; no reset
/// calls needed") + "incomplete zeroing of secondary config on group/0-session/
/// new-chat now complete" + *both* startNewChat branches explicit + cross-refs
/// (e.g. setActiveCharacter:1572).
///
/// Anti-accumulation/dead-code audit: explicit greps/audit of affected methods
/// in god (no new `_Summary/*Summary/GenSummary` privates in god); deletion of
/// moved code + any dead/vestigial as part of task.
///
/// Barrel not added (internal to ChatService only; per "unless 3+ locations").
///
/// Some coordination / cadence / state / flag / pause / force / _maybe count logic
/// thin in god per plan (qualify explicitly in leaf header + god thins + test + MD:
/// "thin delegation here; full summary in step 12").
///
/// Update any other headers/comments attributing summary gen to god (now in step
/// 12 sibling leaf; god provides cbs + thin delegation for generate).
class SummaryService {
  final LLMService Function() getLlmService;

  final bool Function() getSummaryEnabled;
  final int Function() getSummaryInterval;
  final String Function() getSummaryPrompt;
  final int Function() getSummaryMaxWords;

  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final String Function() getUserName;
  final List<ChatMessage> Function() getMessages;

  final String Function() getCurrentSummary; // for 'Previous summary' block

  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  final bool Function() getIsSummaryGenerating;
  final void Function(bool) setIsSummaryGenerating;

  final void Function(String) updateSummary;
  final void Function(int) updateSummaryLastIndex;

  final bool Function() isMemoryOperational;
  final Future<List<String>> Function() getMemorySourceIds;
  final Future<List<String>> Function(List<String>) getAllContentForCharacters;

  SummaryService({
    required this.getLlmService,
    required this.getSummaryEnabled,
    required this.getSummaryInterval,
    required this.getSummaryPrompt,
    required this.getSummaryMaxWords,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getUserName,
    required this.getMessages,
    required this.getCurrentSummary,
    required this.onNotify,
    required this.onSaveChat,
    required this.getIsSummaryGenerating,
    required this.setIsSummaryGenerating,
    required this.updateSummary,
    required this.updateSummaryLastIndex,
    required this.isMemoryOperational,
    required this.getMemorySourceIds,
    required this.getAllContentForCharacters,
  });

  /// Generate a summary of the chat history using the active LLM (full impl
  /// here per step 12; thin delegation + cadence/paused/enabled/flag coord in god).
  Future<void> generateSummaryInBackground() async {
    final llmService = getLlmService();
    if (!llmService.isReady) return;

    setIsSummaryGenerating(true);
    onNotify();

    try {
      final userName = getUserName();
      final charName =
          getActiveCharacter()?.name ?? getActiveGroup()?.name ?? 'Character';

      // Build the summary prompt with macro replacement
      final summaryPromptTemplate = getSummaryPrompt()
          .replaceAll('{{words}}', getSummaryMaxWords().toString())
          .replaceAll('{{user}}', userName)
          .replaceAll('{{char}}', charName);

      // Build a condensed chat history for the summary request
      final historyLines = <String>[];
      for (final m in getMessages()) {
        if (m.characterId == '__director__') continue;
        // (v30: no more sentinel messages to skip)
        // Strip thinking blocks from display text for summarization
        historyLines.add('${m.sender}: ${m.displayText}');
      }
      final chatHistoryForSummary = historyLines.join('\n');

      // Build the full prompt for the summary LLM call
      String previousSummaryBlock = '';
      final curr = getCurrentSummary();
      if (curr.isNotEmpty) {
        previousSummaryBlock = 'Previous summary:\n$curr\n\n';
      }

      // Retrieve ALL RAG content chunks to ground the summary in real content
      String ragGroundingBlock = '';
      if (isMemoryOperational()) {
        try {
          final sourceIds = await getMemorySourceIds();
          final allChunks = await getAllContentForCharacters(sourceIds);
          if (allChunks.isNotEmpty) {
            ragGroundingBlock =
                'Archived conversation content (use this as the primary source of truth):\n'
                '${allChunks.join('\n---\n')}\n\n';
            debugPrint(
              '[Summary] Including ${allChunks.length} RAG chunks as grounding',
            );
          }
        } catch (e) {
          debugPrint('[Summary] RAG grounding retrieval failed: $e');
        }
      }

      final summaryRequestPrompt =
          'The following is a conversation between $userName and $charName.\n\n'
          '$previousSummaryBlock'
          '$ragGroundingBlock'
          'Chat history:\n$chatHistoryForSummary\n\n'
          '$summaryPromptTemplate\n\n'
          'Here is the summary of the conversation so far:\n';

      final genParams = GenerationParams(
        prompt: summaryRequestPrompt,
        maxLength: (getSummaryMaxWords() * 3).clamp(200, 4000),
        temperature: 0.3, // Low temperature for factual summarization
        repeatPenalty: 1.0,
        reasoningEnabled: false,
        stopSequences: ['\n\n\n', '<END>', '</END>'],
      );

      String accumulated = '';
      await for (final token in llmService.generateStream(genParams)) {
        accumulated += token;
      }

      var result = accumulated
          .replaceAll(
            RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
          .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
          .trim();

      // Strip numbered-list analysis blocks that thinking models prepend.
      // Walk through lines, skip analysis preamble, keep only prose.
      final lines = result.split('\n');
      int startIdx = 0;
      for (int i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.isEmpty) continue;
        // Skip numbered list items like "1. **Analyze..."
        if (RegExp(r'^\d+\.').hasMatch(trimmed)) {
          startIdx = i + 1;
          continue;
        }
        // Skip bullet points like "* **Goal:**" or "- **Setting:**"
        if (trimmed.startsWith('*') || trimmed.startsWith('-')) {
          startIdx = i + 1;
          continue;
        }
        // Found prose — stop here
        break;
      }
      if (startIdx > 0 && startIdx < lines.length) {
        result = lines.sublist(startIdx).join('\n').trim();
      }

      // Trim trailing incomplete sentence — cut back to last . ! or ?
      final lastSentenceEnd = result.lastIndexOf(RegExp(r'[.!?]'));
      if (lastSentenceEnd > 0 && lastSentenceEnd < result.length - 1) {
        result = result.substring(0, lastSentenceEnd + 1).trim();
      }

      if (result.isNotEmpty) {
        updateSummary(result);
        updateSummaryLastIndex(getMessages().length);
        await onSaveChat();
      }
    } catch (e) {
      debugPrint('Summary generation failed: $e');
    } finally {
      setIsSummaryGenerating(false);
      onNotify();
    }
  }
}
