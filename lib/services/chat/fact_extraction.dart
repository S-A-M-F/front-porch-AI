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

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/embedding_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';

/// Plain (non-ChangeNotifier) leaf sibling to LlmEvalEngine / realism_evals /
/// objective_proposal / summary_service owning the "auto persona" / learned facts
/// feature (fact extraction + consolidation + quality gate).
/// Per extraction order (step 13 after summary_service step 12 per
/// docs/refactoring-guide.md table and CLAUDE.md Critical Services / Path Map).
/// Fact extraction is user-global (learnedFacts live in _userPersonaService.persona),
/// but rejection context (current + group char names) and trigger timing are
/// chat-specific. Extraction trigger (dedicated god-owned _userMessagesSinceLastPeriodicEval
/// counter vs autoPersonaInterval + enabled guard in _maybeRunPeriodicEvals) + call site in
/// _runPeriodicEvalsInSequence stay thin/coordinated in god ("thin delegation here;
/// full fact extraction in step 13"). The _isExtractingFacts flag (transient guard)
/// is god-owned (like _isSummaryGenerating); leaf clears it via cb in finally +
/// !ready/error paths. LLM stream for extract (custom 1024/0.2/1.15, early break on
/// ']' after strip, isThinking from local+storage drives the stop set) +
/// consolidate via fireLLMEval (2000? no, uses engine fire path) + strip + ```json
/// codeblock + RegExp \[.*\] dotAll + jsonDecode + _isValidFact quality gate (length
/// 8-200 + 13+ garbage RP/meta/JSON/third-person/rel/scene/emotion patterns + reject
/// if contains current _active or any _group char name case-insens) + addLearnedFacts
/// (with embed pass-through if avail) + cap check + consolidate (merge related dense
/// preserving ALL details, drop vague first, target <=50, truncate fallbacks on LLM/
/// parse fail) fully owned here.
/// ChatService (god) owns via late final (after _summaryService) +
/// thins/delegates at *every* prior call site (the one in _runPeriodicEvalsInSequence
/// and the guard/flag use in _maybe) with *full excision* of the moved bodies from god.
/// 0 @Deprecated shims.
///
/// Granular callbacks for cross-state (~14: getLlmService for isReady + generateStream
/// (extract path with early ] break); fireLLMEval + stripThinkBlocks (consolidate path
/// + extract stream strip); getIsLocal/getKoboldThinkingModel/getReasoningEnabled (for
/// isThinkingModel + banEos/trim in extract params); getUserName (for prompt); getLearnedFacts
/// (existing block + post-add count + consolidate copy); addLearnedFacts (success path
/// with embedService pass-through); updateLearnedFacts (consolidate success/fallbacks);
/// getActiveCharacter/getGroupCharacters (for _isValidFact rejection + charNamesStr in
/// prompt; must work under any god impersonation for group); getMessages (for last 10
/// user filter skipping __director__); getIsExtractingFacts/setIsExtractingFacts (flag
/// guard + clear in finally/!ready); isMemoryOperational/getEmbeddingService (embed
/// arg for add)). Live closures in god for test overrides + group chat context (char
/// list for rejection/prompt always current + group).
///
/// 0 *new* god private _ methods (live `grep -c '^\s*void _[a-zA-Z]'
/// lib/services/chat_service.dart` *must stay exactly 15* after every edit + final;
/// thins + late final + reset comment syncs only).
/// Dedicated test `test/services/chat/fact_extraction_test.dart` using factory
/// (`createTestFactExtraction`) with *live* closures over group maps + cbs (real
/// dispatch exercised without forcing god internals); 15 `test()` bodies via
/// live `grep -c '^\s*test('` *post mandatory dead noop/placeholder/vestigial/
/// factory-setup deletion as part of task*.
///
/// aug/integration tests (chat_service_session_test etc.) receive *only* qualified
/// passive notes in headers/comments (exact precedent: "aug exercising only
/// passive/qualified (no fact-extraction-specific aug file edits; full in dedicated +
/// manual; exercised via god thins _maybeRunPeriodicEvals/_runPeriodicEvalsInSequence/_extractFactsInBackground ;
/// qualified notes only in dedicated header + god + MD per precedent)");
/// no leaf-specific logic edits.
/// Strict 1:1 vs group parity for fact extraction (rejection of current+group char
/// names must work identically in _isValidFact + prompt charNamesStr; dispatch
/// preserved via cbs; facts are user-global but context for extraction/rejection
/// is chat-specific; timing of trigger in post-gen sequence qualified per group
/// impersonation dance precedent).
/// Stateless/prompt-only leaf where possible (no owned reset/seed/load state for
/// the counter/flag — kept thin in god; no reset calls needed on leaf); god
/// reset "keep blocks in sync" comments expanded at *all* ~15+ documented sites
/// (full prior+current list + fact_extraction (stateless or prompt-only; no reset
/// calls needed) + "incomplete zeroing of secondary config on group/0-session/
/// new-chat now complete" + *both* startNewChat branches explicit + cross-refs
/// (e.g. setActiveCharacter:1572)).
/// Anti-accumulation/dead-code audit: explicit greps/audit of affected methods
/// in god (no new `_Fact/*Fact/ExtractFact` privates in god); deletion of
/// moved code + any dead/vestigial as part of task.
/// Barrel not added (internal to ChatService only; per "unless 3+ locations").
/// Some coordination / cadence / state / flag / periodic orchestration / enabled /
/// sequence / call sites / load/save of transients thin in god per plan (qualify
/// explicitly in leaf header + god thins + test + MD:
/// "thin delegation here; full fact extraction in step 13").
/// Update any other headers/comments attributing fact extraction to god (now in step
/// 13 sibling leaf; god provides cbs + thin delegation for extract + the _maybe/_run
/// guards/sequence).
class FactExtraction {
  final LLMService Function() getLlmService;
  final Future<String?> Function(String prompt) fireLLMEval;
  final String Function(String) stripThinkBlocks;

  final bool Function() getIsLocal;
  final bool Function() getKoboldThinkingModel;
  final bool Function() getReasoningEnabled;

  final String Function() getUserName;
  final List<String> Function() getLearnedFacts;
  final Future<void> Function(
    List<String> facts, {
    EmbeddingService? embedService,
  })
  addLearnedFacts;
  final Future<void> Function(List<String> facts) updateLearnedFacts;
  final CharacterCard? Function() getActiveCharacter;
  final List<CharacterCard> Function() getGroupCharacters;
  final List<ChatMessage> Function() getMessages;
  final bool Function() getIsExtractingFacts;
  final void Function(bool) setIsExtractingFacts;
  final bool Function() isMemoryOperational;
  final EmbeddingService? Function() getEmbeddingService;

  // Regex patterns for the post-extraction quality gate.
  // Facts matching any of these are rejected as garbage or character-specific events.
  static final List<RegExp> _factGarbagePatterns = [
    // RP action text (contains asterisks or action-style phrasing)
    RegExp(r'\*'),
    // Starts with action verbs that indicate RP narration (present or past tense)
    RegExp(
      r'^(walks|walked|runs|ran|looks|looked|says|said|goes|went|came|sat|stood|turned|moved|grabbed|took|pulled|pushed|kissed|hugged|touched|smiled|laughed|nodded|sighed|whispered|moaned|gasped|fought|visited|traveled|explored|entered|left|arrived|met|told|asked|agreed|decided|confessed|promised|attacked|defended|defeated|escaped|rescued|seduced|flirted|dated|married|proposed)\b',
      caseSensitive: false,
    ),
    // LLM meta-commentary / non-facts
    RegExp(
      r'^(no new facts|none|n/a|nothing|unknown|unclear|not sure|i don.?t know)',
      caseSensitive: false,
    ),
    // Too generic / vague to be useful
    RegExp(
      r'^(is nice|is good|is bad|likes things|does stuff|is a person|is human|exists)',
      caseSensitive: false,
    ),
    // JSON artifacts or structural garbage
    RegExp(r'[\[\]{}]'),
    // Repeated punctuation or encoding garbage
    RegExp(r'[.!?]{3,}|\\[nrt]|&#|%[0-9a-f]{2}', caseSensitive: false),
    // Third-person narrator voice ("The user did X", "They went Y")
    RegExp(
      r'^(the user|the player|they|he|she)\s+(is|was|had|has|did|does|went|walked|said|looked|seemed|appeared)\b',
      caseSensitive: false,
    ),
    // Character-specific relationship events ("kissed X", "went on a date with X", "told X")
    RegExp(
      r'(kissed|hugged|dated|married|proposed to|confessed to|fell in love with|slept with|fought with|traveled with|met with|went .+ with|had .+ with|told .+ about|asked .+ to|promised .+ to)\s+[A-Z]',
      caseSensitive: false,
    ),
    // References to specific RP interactions ("during the", "at the", "in the [location]")
    RegExp(
      r'(during the|at the|in the|after the|before the)\s+(quest|battle|fight|mission|date|party|ritual|ceremony|adventure|journey|dungeon|castle|tavern|camp)',
      caseSensitive: false,
    ),
    // Emotional events tied to scenes ("felt X when", "was X during")
    RegExp(
      r'(felt|was|became|got)\s+\w+\s+(when|during|after|while|because)\b',
      caseSensitive: false,
    ),
    // Relationship status with fictional characters ("is dating X", "is friends with X", "loves X")
    RegExp(
      r'(is|are|was|were)\s+(dating|married to|in love with|friends with|enemies with|attracted to|bonded with|loyal to|allied with)\b',
      caseSensitive: false,
    ),
  ];

  /// Minimum/maximum character length for a valid fact.
  static const int _minFactLength = 8;
  static const int _maxFactLength = 200;

  /// Maximum number of learned facts to keep per persona.
  static const int _maxLearnedFacts = 50;

  FactExtraction({
    required this.getLlmService,
    required this.fireLLMEval,
    required this.stripThinkBlocks,
    required this.getIsLocal,
    required this.getKoboldThinkingModel,
    required this.getReasoningEnabled,
    required this.getUserName,
    required this.getLearnedFacts,
    required this.addLearnedFacts,
    required this.updateLearnedFacts,
    required this.getActiveCharacter,
    required this.getGroupCharacters,
    required this.getMessages,
    required this.getIsExtractingFacts,
    required this.setIsExtractingFacts,
    required this.isMemoryOperational,
    required this.getEmbeddingService,
  });

  String _safe(String s) => s.replaceAll(RegExp(r'[\n\r"]'), ' ').trim();

  /// Returns true if a fact passes the quality gate.
  /// Rejects RP actions, character-specific events, and scene-bound facts.
  bool _isValidFact(String fact) {
    if (fact.length < _minFactLength || fact.length > _maxFactLength) {
      return false;
    }
    for (final pattern in _factGarbagePatterns) {
      if (pattern.hasMatch(fact)) {
        debugPrint('[RAG:Persona] ✗ Rejected by quality gate: "$fact"');
        return false;
      }
    }
    // Reject facts that reference the current character by name (chat-specific)
    final active = getActiveCharacter();
    if (active != null) {
      final charName = active.name.toLowerCase();
      if (fact.toLowerCase().contains(charName)) {
        debugPrint(
          '[RAG:Persona] ✗ Rejected (references character "${active.name}"): "$fact"',
        );
        return false;
      }
    }
    // Reject facts referencing any group chat character
    for (final gc in getGroupCharacters()) {
      if (fact.toLowerCase().contains(gc.name.toLowerCase())) {
        debugPrint(
          '[RAG:Persona] ✗ Rejected (references group character "${gc.name}"): "$fact"',
        );
        return false;
      }
    }
    return true;
  }

  Future<void> extractFactsInBackground() async {
    if (getIsExtractingFacts()) return;
    setIsExtractingFacts(true);

    try {
      final llmService = getLlmService();
      if (!llmService.isReady) {
        debugPrint('[RAG:Persona] ✗ LLM not ready, skipping extraction');
        return;
      }

      // Get recent user messages (last N messages, user only)
      final userMessages = getMessages()
          .where((m) => m.isUser && m.characterId != '__director__')
          .toList();

      if (userMessages.isEmpty) {
        debugPrint('[RAG:Persona] No user messages to extract from');
        return;
      }

      // Take last 10 user messages
      final recentUserMsgs = userMessages.length > 10
          ? userMessages.sublist(userMessages.length - 10)
          : userMessages;

      final existingFacts = getLearnedFacts();
      final userName = getUserName();
      final safeUserName = _safe(userName);

      // Build user message text (strip RP asterisk actions for cleaner context)
      final userMsgText = recentUserMsgs
          .map((m) => '$safeUserName: ${_safe(m.displayText)}')
          .join('\n');

      final existingFactsText = existingFacts.isNotEmpty
          ? 'Already known (do NOT repeat or rephrase these):\n${existingFacts.map((f) => '- ${_safe(f)}').join('\n')}\n\n'
          : '';

      // ── Strict RP-Aware Extraction Prompt ──
      // Build character name list to explicitly exclude from facts
      final charNames = <String>[];
      final active = getActiveCharacter();
      if (active != null) charNames.add(_safe(active.name));
      for (final gc in getGroupCharacters()) {
        if (!charNames.contains(_safe(gc.name))) charNames.add(_safe(gc.name));
      }
      final charNamesStr = charNames.isNotEmpty
          ? 'Characters in this chat (NEVER reference these): ${charNames.join(", ")}\n'
          : '';

      final extractionPrompt =
          'You are extracting REAL, PERMANENT personal facts about a user named "$safeUserName" from their chat messages.\n'
          'These facts will be used ACROSS ALL conversations, not just this one.\n\n'
          'CRITICAL RULES:\n'
          '- ONLY extract facts that are UNIVERSALLY TRUE about $safeUserName as a real person\n'
          '- Facts must be TIMELESS and CONTEXT-FREE — true regardless of which character they are talking to\n'
          '- IGNORE all roleplay actions (text between *asterisks*), character dialogue, and narrative descriptions\n'
          '- IGNORE anything said IN CHARACTER or about fictional scenarios, quests, or fantasy settings\n'
          '- NEVER extract events, actions, or interactions that happened with a specific character\n'
          '- NEVER extract relationship status or feelings toward any fictional character\n'
          '- NEVER mention any character name in a fact\n'
          '- Each fact must be something you would put on a real person\'s About Me page\n'
          '- Extract ONLY concrete, specific, permanent details — not momentary states or scene-specific observations\n\n'
          '$charNamesStr\n'
          'GOOD facts (universal truths): "Has a dog named Max", "Works as a nurse", "Favorite color is blue", "Lives in Texas", "Is 25 years old", "Enjoys cooking"\n'
          'BAD (do NOT extract): "Walked to the door", "Kissed [character]", "Went on a date", "Told [character] a secret", "Felt nervous", "Is dating [character]", "Explored the dungeon", "Agreed to help", "Seems happy today"\n\n'
          '$existingFactsText'
          'Recent messages from $safeUserName:\n$userMsgText\n\n'
          'Return ONLY a valid JSON array of short, universal factual sentences. If no qualifying facts exist, return [].\n'
          'Response:';

      debugPrint(
        '[RAG:Persona] Sending extraction prompt (${extractionPrompt.length} chars, ${recentUserMsgs.length} user messages)',
      );

      final isThinkingModel = getIsLocal()
          ? getKoboldThinkingModel()
          : getReasoningEnabled();

      final params = GenerationParams(
        prompt: extractionPrompt,
        maxLength: 1024,
        temperature: 0.2,
        repeatPenalty: 1.15,
        stopSequences: isThinkingModel ? [] : [']\n', ']'],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
        // Early termination: if we see the closing bracket, stop
        final stripped = stripThinkBlocks(responseText);
        if (stripped.isNotEmpty && stripped.trimRight().endsWith(']')) {
          responseText = stripped;
          break;
        }
      }

      // Strip think blocks (for thinking models)
      if (responseText.isEmpty || !responseText.trimRight().endsWith(']')) {
        responseText = stripThinkBlocks(responseText).isNotEmpty
            ? stripThinkBlocks(responseText)
            : responseText;
      }
      responseText = responseText.trim();

      debugPrint('[RAG:Persona] Raw response: $responseText');

      // Parse JSON array from response
      // Handle cases where the model wraps in markdown code blocks
      var jsonStr = responseText;
      if (jsonStr.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(jsonStr);
        if (match != null) jsonStr = match.group(1)!.trim();
      }

      // Extract the JSON array — no fallback line parser (fail silently if not JSON)
      List<String> facts = [];
      final arrayMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(jsonStr);
      if (arrayMatch != null) {
        try {
          facts = List<String>.from(jsonDecode(arrayMatch.group(0)!) as List);
        } catch (_) {
          debugPrint('[RAG:Persona] ✗ JSON parse failed — aborting extraction');
          return;
        }
      }

      if (facts.isEmpty) {
        debugPrint('[RAG:Persona] ✗ No facts extracted from response');
        return;
      }

      // ── Quality Gate: filter garbage facts ──
      final cleanFacts = facts.where(_isValidFact).toList();
      final rejected = facts.length - cleanFacts.length;
      if (rejected > 0) {
        debugPrint(
          '[RAG:Persona] Quality gate: rejected $rejected/${facts.length} facts',
        );
      }

      if (cleanFacts.isEmpty) {
        debugPrint(
          '[RAG:Persona] ✗ All extracted facts rejected by quality gate',
        );
        return;
      }

      debugPrint(
        '[RAG:Persona] ✅ Accepted ${cleanFacts.length} fact(s) (details redacted for PII; see persona for full)',
      );
      // Do not log full facts to avoid PII in logs/captures (redaction for security)

      await addLearnedFacts(cleanFacts, embedService: getEmbeddingService());

      // ── Fact Cap: consolidate if over limit ──
      final currentCount = getLearnedFacts().length;
      if (currentCount > _maxLearnedFacts) {
        debugPrint(
          '[RAG:Persona] Fact count ($currentCount) exceeds cap ($_maxLearnedFacts), consolidating...',
        );
        await _consolidateLearnedFacts();
      }

      debugPrint('[RAG:Persona] Facts saved to persona');
    } catch (e) {
      debugPrint('[RAG:Persona] ✗ Extraction failed: $e');
    } finally {
      setIsExtractingFacts(false);
    }
  }

  /// Consolidate learned facts when they exceed the cap.
  /// Uses the LLM to merge related facts into denser statements,
  /// reducing the total count while preserving all meaningful details.
  Future<void> _consolidateLearnedFacts() async {
    try {
      final facts = List<String>.from(getLearnedFacts());
      if (facts.length <= _maxLearnedFacts) return;

      final userName = getUserName();
      final safeUserName = _safe(userName);

      // Ask the LLM to consolidate the facts
      final consolidationPrompt =
          'You are a fact consolidation assistant. The following is a list of facts about a person named "$safeUserName".\n'
          'There are ${facts.length} facts but the maximum allowed is $_maxLearnedFacts.\n\n'
          'TASK: Merge related facts together into single, dense sentences that preserve ALL specific details.\n'
          'For example: "Has a cat" + "Cat\'s name is Luna" + "Luna is a calico" → "Has a calico cat named Luna"\n'
          'Remove any truly redundant entries. Prioritize keeping specific, unique details (names, numbers, locations).\n'
          'Drop vague or low-value entries first (e.g. "Seems nice" or "Likes things").\n\n'
          'Current facts:\n${facts.asMap().entries.map((e) => '${e.key + 1}. ${_safe(e.value)}').join('\n')}\n\n'
          'Return ONLY a JSON array of consolidated facts. Target: around $_maxLearnedFacts entries or fewer.\n'
          'Response:';

      final raw = await fireLLMEval(consolidationPrompt);
      if (raw == null) {
        // LLM failed — fall back to simple truncation (keep first N facts)
        debugPrint(
          '[RAG:Persona] Consolidation LLM call failed, truncating to $_maxLearnedFacts',
        );
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await updateLearnedFacts(trimmed);
        return;
      }

      final text = stripThinkBlocks(raw).isNotEmpty
          ? stripThinkBlocks(raw)
          : raw;
      var jsonStr = text.trim();
      if (jsonStr.contains('```')) {
        final match = RegExp(
          r'```(?:json)?\s*\n?(.*?)\n?```',
          dotAll: true,
        ).firstMatch(jsonStr);
        if (match != null) jsonStr = match.group(1)!.trim();
      }
      final arrayMatch = RegExp(r'\[.*\]', dotAll: true).firstMatch(jsonStr);
      if (arrayMatch == null) {
        debugPrint(
          '[RAG:Persona] Consolidation response not parseable, truncating',
        );
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await updateLearnedFacts(trimmed);
        return;
      }

      try {
        final consolidated = List<String>.from(
          jsonDecode(arrayMatch.group(0)!) as List,
        );
        final cleaned = consolidated.where(_isValidFact).toList();
        debugPrint(
          '[RAG:Persona] Consolidated ${facts.length} → ${cleaned.length} facts (details redacted for PII)',
        );
        await updateLearnedFacts(cleaned);
      } catch (_) {
        debugPrint('[RAG:Persona] Consolidation JSON parse failed, truncating');
        final trimmed = facts.sublist(0, _maxLearnedFacts);
        await updateLearnedFacts(trimmed);
      }
    } catch (e) {
      debugPrint('[RAG:Persona] Consolidation error: $e');
    }
  }
}
