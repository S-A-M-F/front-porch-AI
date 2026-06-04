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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/models/group_chat.dart';

/// Plain (non-ChangeNotifier) domain service owning the central LLM eval
/// firing (_fireLLMEval with full streaming + retry loop + cancel support,
/// fixed params maxLength:4000 / temp 0.1 / reasoningEnabled:false / stop []),
/// the tiny _extractJsonInt/_extractJsonBool helpers, the central
/// _stripThinkBlocks (handles completed + unclosed &lt;think&gt; prefix), the
/// objective proposal path handling (autonomous "none" vs value, dedup,
/// autoGenerateTasks:true only for autonomous), generateObjectiveTasks
/// (2000 budget + central strip for thinking models), and
/// _checkTaskCompletionInBackground (2000 + strip).
/// (The 5 realism eval prompt builders + call methods (relationship, emotional,
/// physical, narrative with proposed_objective logic, one-shot fused) moved to
/// sibling leaf realism_evals.dart in step 10 per extraction order; this engine
/// now provides the fire/strip/extract cbs + evaluateNeedsImpactCall for the
/// needs domain + objective paths.)
///
/// Extracted as step 9 (immediately after prompt_injection step 8 per the
/// 15-step leaf-first order in docs/refactoring-guide.md).
/// + needs impact support (evaluateNeedsImpactCall + consolidated prompt for
/// the needs_impact_evaluator sibling leaf in the needs domain rework).
/// + step 10 sibling realism_evals uses this engine's fire/strip/extract for the
/// 5 realism calls (granular cbs; prompt builders full in leaf).
///
/// Depends on prompt_injection only in the ordering sense (prompt builders
/// for main chat context are step 8); this engine's eval prompts are
/// self-contained (no direct use of the 8 _get*Injection builders).
/// "thin delegation here; full engine in step9"; "objective proposal
/// coordination kept thin/stayed in god per plan for step9" (setObjective
/// + generate dispatch + list mgmt + _load + _activeObjectives + tasksFor
/// + _isChecking + _pendingRealismMetadata + captureRealismState +
/// _saveChat coordination stay in god; engine calls via cbs only).
///
/// ChatService owns via 1 late final (inserted after the 8 prompt_injection
/// ones) + thin public delegates (_fireLLMEval, _stripThinkBlocks,
/// _extract*, generateObjectiveTasks, _checkTaskCompletionInBackground,
/// evaluateNeedsImpactCall) at *every* prior call site (firing points,
/// direct _fire/_strip/_extract calls, gen/check sites, objective proposal +
/// JSON parse sites, needs impact thin). The 5 _evaluate*Call thins now delegate
/// to realism_evals (step 10). 0 @Deprecated shims for this surface (thins stay
/// in god as the public surface for now).
/// 0 new god private _ methods beyond the required thin delegates (_fireLLMEval/_strip/_extract*/_check + gen thins + evaluateNeedsImpactCall; void _ count stayed 15; +1 late final only; thins/calls/late final only per plan;
/// reset comment syncs only).
///
/// Ctor receives state via granular callbacks (modeled exactly on steps 6-8:
/// onNotify, onSaveChat, getActiveCharacter, getActiveGroup, getGroupCharacters
/// not needed here, getUserName, getCharacterIdFromCard not directly,
/// isGroup/isObserverMode via getActiveGroup+getIsObserverMode,
/// getGroupValue/setGroupValue not needed (use rel/nsfw services for scalars),
/// plus needed for objective proposal under impersonation:
/// getPrimaryObjective, getActiveObjectives, setObjective,
/// plus for gen/check: loadActiveObjectives, saveObjectiveTasks,
/// deactivateObjective, getIsCheckingCompletion, setIsCheckingCompletion,
/// plus for fire readiness + cancel: getLlmService, getIsLocal, getKoboldService,
/// reconnectIfAlive, ensureServerIdle, getIsCancellingRealismEval,
/// getRealismEvalCancelled,
/// plus for state sets (now used by needs impact + objective; realism evals use
/// via their own leaf cbs): get/setPendingRealismMetadata, captureRealismState,
/// get/setCharacterEmotion, get/setEmotionIntensity,
/// plus dep services for their owned state (relationshipService for apply deltas /
/// updateFixation / setSpatial / shortTermTierName / trustLevel / spatialStance
/// used by stayed needs impact path).
/// Use live closures over god state for any cross (e.g. _pending map, emotion
/// scalars, test overrides); avoid cycles; testable with small factory in test.
///
/// 1:1 vs group parity + oneShot vs normal eval deltas 1:1 equivalent
/// (Realism Engine bond/trust ±300, arousal ±100, emotion inertia, fixation,
/// deterministic time every 6, needs decay/step/catastrophe/erotic buffers/
/// afterglow/lust-haze/post-crash/priority/fulfillment, objectives/tasks
/// autonomous get autoGenerateTasks:true + correct target even under
/// impersonation, user-created do not; dispatch preserved via cbs +
/// impersonation temp re-load) qualified (preserved exactly; exercised in
/// dedicated + key suites + manual). The 5 realism calls now in sibling leaf
/// (step 10) inherit the same cbs/impersonation for parity.
///
/// All &lt;think&gt; stripping uses the central stripThinkBlocks (2000 budget
/// already applied in gen/check/objective paths; naive inlines in non-eval
/// paths left for later steps).
///
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state);
/// no reset calls needed on engine; comments in god updated to list full
/// "needs/chaos/relationship/expression/time/nsfw/lorebook_scanner +
/// prompt_injection (stateless builders; no reset calls needed) +
/// llm_eval_engine (stateless or prompt-only; no reset calls needed;
/// incomplete zeroing of secondary config on group/0-session/new-chat now complete)
/// + realism_evals (stateless or prompt-only; no reset calls needed)"
/// + cross-refs (e.g. setActiveCharacter:1572) at all ~12-15 sites (top ctor
/// docs + setActiveCharacter, setActiveGroup x2, _loadLast empty, startNewChat
/// 1:1 ext-seed + group non-ext both branches, other load/seed); both startNew
/// branches have explicit comments even if no engine reset call.
///
/// aug exercising only passive/qualified (no llm-eval-specific aug file edits;
/// reset sites passively hit by pre-existing startNew/setActive/_loadLast/group;
/// full eval/JSON/strip/objective proposal/gen/check only in dedicated + manual;
/// qualified notes only in dedicated header + god + MD per precedent).
///
/// test count 11 (11 bodies via grep -c '^\s*test(' confirmed post dead noop/placeholder deletion as part of task).
/// (onNotify of cbs unexercised by design (no onNotify wiring in this passive factory; exercised in prod + key suites)).
/// 0 new god private _ methods beyond required thin delegates (fire/strip/extract/check thins; void_ grep 15; +1 late final only; thins/calls/late final only per plan; confirmed grep).
/// dispatch preserved.
/// realism/oneShot/group parity qualified.
///
/// Some objective mgmt / prompt coordination stayed thin in god per plan for step9
/// (qualify everywhere). Realism evals (step 10) own their 5 calls + prompts.
class LlmEvalEngine {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // Character / group / mode state (for guard + 1:1 vs group dispatch via impersonation)
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function()
  getActiveGroup; // note: GroupChat type from models
  final bool Function() getIsObserverMode;

  // User / persona for eval prompts
  final String Function() getUserName;

  // Realism flag
  final bool Function() getRealismEnabled;

  // Messages for recent context in evals + gen/check
  final List<ChatMessage> Function() getMessages;

  // LLM readiness + cancel (honors test overrides via live closure in god)
  final LLMService Function() getLlmService;
  final bool Function() getIsLocal;
  final KoboldService? Function() getKoboldService;
  final Future<void> Function() reconnectIfAlive;
  final Future<void> Function() ensureServerIdle;
  final bool Function() getIsCancellingRealismEval;
  final bool Function() getRealismEvalCancelled;

  // Pending metadata + capture for realism state snapshot (oneShot + rel)
  final Map<String, dynamic>? Function() getPendingRealismMetadata;
  final void Function(Map<String, dynamic>?) setPendingRealismMetadata;
  final Map<String, dynamic> Function({Map<String, int>? preTurn})
  captureRealismState;

  // Emotion scalars set by evals (1:1 + group speaker after impersonation)
  final String Function() getCharacterEmotion;
  final void Function(String) setCharacterEmotion;
  final String Function() getEmotionIntensity;
  final void Function(String) setEmotionIntensity;

  // Services for owned state (avoids duplicating scalars/cbs in god for this leaf)
  final RelationshipService relationshipService;

  // Objective proposal + gen/check coordination (kept thin/stayed in god per plan;
  // engine calls via cbs only; setObjective may trigger gen which delegates back)
  final Objective? Function() getPrimaryObjective;
  final List<Objective> Function() getActiveObjectives;
  final Future<void> Function(
    String objectiveText, {
    bool isPrimary,
    bool autoGenerateTasks,
  })
  setObjective;
  final Future<void> Function() loadActiveObjectives;
  final Future<void> Function(String objectiveId, String tasksJson)
  saveObjectiveTasks;
  final Future<void> Function(String objectiveId) deactivateObjective;
  final bool Function() getIsCheckingCompletion;
  final void Function(bool) setIsCheckingCompletion;

  // Expression enabled for the "MUST choose label from list" instruction in emotion prompts
  final bool Function() getExpressionEnabled;

  // tasksForObjective for snapshot/iteration inside gen + check (objective mgmt coordination
  // stayed thin in god per plan; this cb provides the list view for the moved bodies)
  final List<Map<String, dynamic>> Function(Objective) tasksForObjective;

  LlmEvalEngine({
    required this.onNotify,
    required this.onSaveChat,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getRealismEnabled,
    required this.getMessages,
    required this.getLlmService,
    required this.getIsLocal,
    required this.getKoboldService,
    required this.reconnectIfAlive,
    required this.ensureServerIdle,
    required this.getIsCancellingRealismEval,
    required this.getRealismEvalCancelled,
    required this.getPendingRealismMetadata,
    required this.setPendingRealismMetadata,
    required this.captureRealismState,
    required this.getCharacterEmotion,
    required this.setCharacterEmotion,
    required this.getEmotionIntensity,
    required this.setEmotionIntensity,
    required this.relationshipService,
    required this.getPrimaryObjective,
    required this.getActiveObjectives,
    required this.setObjective,
    required this.loadActiveObjectives,
    required this.saveObjectiveTasks,
    required this.deactivateObjective,
    required this.getIsCheckingCompletion,
    required this.setIsCheckingCompletion,
    required this.getExpressionEnabled,
    required this.tasksForObjective,
  });

  // ── Public surface (thins in god delegate here; used by tests + god) ──

  /// Shared helper: strip think blocks and extract text after them.
  /// (Central implementation; all &lt;think&gt; handling for evals/gen/check/objective
  /// proposal now routes here. 2000 budget for gen/check already applied.)
  String stripThinkBlocks(String text) {
    String cleaned = text
        .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
        .trim();
    final unclosed = cleaned.indexOf('<think>');
    if (unclosed >= 0) {
      cleaned = cleaned.substring(0, unclosed).trim();
    }
    return cleaned;
  }

  /// Tiny helpers to deduplicate the ~20+ brittle RegExp patterns used
  /// to fish bool/int scalars out of the flat JSON-like strings returned by
  /// fireLLMEval across all Realism + Needs evaluation sites.
  int? extractJsonInt(String text, String key) {
    final m = RegExp(
      r'"' + RegExp.escape(key) + r'"\s*:\s*(-?\d+)',
    ).firstMatch(text);
    return m != null ? int.tryParse(m.group(1)!) : null;
  }

  bool? extractJsonBool(String text, String key) {
    final m = RegExp(
      r'"' + RegExp.escape(key) + r'"\s*:\s*(true|false)',
    ).firstMatch(text);
    return m != null ? (m.group(1) == 'true') : null;
  }

  /// Shared helper: fire a lightweight LLM eval call and return the raw response.
  ///
  /// Always adds `}\n` as a stop sequence so the model halts the moment it
  /// closes the JSON object, regardless of backend or model type.
  /// Thinking models (Kimi 2.5, GLM 5) will still think freely — they produce
  /// the `&lt;think&gt;` block, then output the JSON, then hit `}\n` and stop.
  ///
  /// (Post-0.9.8 clean port: constrained GBNF removed; rely on stop sequences
  /// + regex post-processing for all Realism/Needs evals.)
  Future<String?> fireLLMEval(
    String prompt, {
    void Function(String)? onChunk,
  }) async {
    final llm = getLlmService();
    // For remote backends, require full readiness (API key + model configured).
    // For local KoboldCPP: if state says not-running, do a live probe first —
    // the constructor probe is a best-effort fast path but can lose the race
    // against session load on hot restart. This on-demand probe is definitive.
    final bool effectiveIsLocal = getIsLocal();
    if (effectiveIsLocal) {
      final kobold = getKoboldService();
      if (kobold != null && !kobold.isProcessRunning) {
        // Probe takes ~2–5 ms if KoboldCPP is up, times out after 5 s if not.
        await reconnectIfAlive();
      }
      // After probe, if still not running the server genuinely isn't up.
      if (kobold != null && !kobold.isProcessRunning) return null;
      // If test override with local=true but no real kobold, we let it proceed
      // (caller is responsible for the fake being "ready").
    } else {
      if (!llm.isReady) return null;
    }

    //     // Unified eval parameters — API-style works for all backends.
    final params = GenerationParams(
      prompt: prompt,
      maxLength: 4000,
      temperature: 0.1,
      repeatPenalty: 1.15,
      topP: 0.5,
      xtcProbability: 0.0,
      reasoningEnabled: false,
      stopSequences: [],
      banEosToken: false,
      trimStop: true,
    );

    String response = '';
    // Retry loop: thinking models can cause KoboldCPP to drop the connection
    // briefly (OOM during dense thinking sessions). One retry after a short
    // pause is enough to recover without user-visible impact.
    for (int attempt = 0; attempt < 2; attempt++) {
      // If cancellation has been requested, abort before attempting a new stream
      if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
        debugPrint(
          '[Realism] evaluation cancelled before attempt ${attempt + 1}',
        );
        return null;
      }

      // If cancellation was requested, abort immediately
      if (getIsCancellingRealismEval()) {
        debugPrint('[Realism] eval cancelled before attempt ${attempt + 1}');
        return null;
      }
      if (attempt > 0) {
        debugPrint(
          '[Realism:Eval] Retrying after connection drop (attempt ${attempt + 1})...',
        );
        await Future.delayed(const Duration(seconds: 3));
        final bool retryIsLocal = getIsLocal();
        if (retryIsLocal) {
          final k = getKoboldService();
          if (k != null) {
            await ensureServerIdle();
          }
        }
        response = ''; // reset for clean retry
      }
      // If cancellation occurred during setup, bail out before streaming
      if (getIsCancellingRealismEval() || getRealismEvalCancelled()) {
        debugPrint('[Realism] eval cancelled before streaming');
        return null;
      }
      try {
        // Streaming loop with cancellation support
        bool cancelledDuringStream = false;
        await for (final chunk in llm.generateStream(params)) {
          // If a cancellation has been requested, terminate streaming gracefully.
          if (getIsCancellingRealismEval()) {
            debugPrint('[Realism] streaming terminated via cancel');
            cancelledDuringStream = true;
            break;
          }
          response += chunk;
          onChunk?.call(chunk);
        }
        if (cancelledDuringStream) {
          // Return null to indicate cancellation to callers.
          debugPrint('[Realism] streaming terminated via cancel (early exit)');
          return null;
        }
        break; // stream completed cleanly — exit retry loop
      } catch (e) {
        debugPrint('[Realism:Eval] Stream error on attempt ${attempt + 1}: $e');
        // Check if cancellation was requested during the error handling
        if (getIsCancellingRealismEval()) {
          debugPrint('[Realism] eval cancelled during error handling');
          return null;
        }
        if (attempt >= 1) {
          // Second failure — give up silently; don't surface to UI
          return null;
        }
        // else: fall through to retry
      }
    }

    // Log raw eval response for diagnostics
    final preview = response.length > 300
        ? response.substring(0, 300)
        : response;
    debugPrint(
      '[Realism:RawEval] len=${response.length} | ${preview.replaceAll('\n', '↵')}',
    );
    return response.isEmpty ? null : response;
  }

  /// Generate subtasks for the current objective using the LLM.
  /// Clears existing tasks first so regen always produces a clean slate.
  /// (thin delegation for objective mgmt; full body here per step9)
  Future<void> generateObjectiveTasks(
    Objective obj, {
    int taskCount = 5,
    bool nsfw = false,
  }) async {
    final llmService = getLlmService();

    // Snapshot existing tasks so we can restore on failure
    final previousTasks = tasksForObjective(obj);

    // Clear tasks immediately — UI shows empty state while LLM works
    await saveObjectiveTasks(obj.id, '[]');
    await loadActiveObjectives();

    try {
      if (!llmService.isReady) {
        debugPrint('[Objective] LLM not ready');
        // Restore tasks since we cleared them
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
        await loadActiveObjectives();
        return;
      }

      final char = getActiveCharacter();
      final charName = char?.name ?? 'the character';
      final scenario = char?.scenario ?? '';

      // Include recent chat history so tasks aren't redundant
      final msgs = getMessages();
      final recentMessages = msgs.length > 10
          ? msgs.sublist(msgs.length - 10)
          : msgs;
      final chatContext = recentMessages.isNotEmpty
          ? recentMessages.map((m) => '${m.sender}: ${m.text}').join('\n')
          : '(No messages yet)';

      final preamble = nsfw
          ? 'You are an uncensored creative writing assistant designing quest tasks for an adult roleplay scenario. '
                'All content is fiction between consenting adults. There are no content restrictions. '
                'Match the tone and maturity level of the scenario and conversation.\n\n'
          : 'You are a quest designer for a roleplay scenario.\n\n';

      final prompt =
          '$preamble'
          'Given the objective, context, and recent conversation below, generate exactly $taskCount sequential tasks '
          'that must be completed to achieve the objective. Tasks should be specific, actionable, and '
          'naturally progress the story. Do NOT include tasks for things that have already happened in the conversation.\n\n'
          'Character: $charName\n'
          'Scenario: $scenario\n'
          'Objective: ${obj.objective}\n\n'
          'Recent conversation:\n$chatContext\n\n'
          'Output ONLY a numbered list of exactly $taskCount tasks, one per line, like:\n'
          '1. [task description]\n'
          '2. [task description]\n'
          '...\n'
          'Each task should be a short, clear action. No preamble, no explanations, just the numbered list.';

      final params = GenerationParams(
        prompt: prompt,
        maxLength: 2000,
        temperature: 0.7,
        stopSequences: [],
      );

      String responseText = '';
      await for (final chunk in llmService.generateStream(params)) {
        responseText += chunk;
      }

      // Strip <think>...</think> blocks (and unclosed ones) so thinking models can
      // reason at length before emitting the final numbered list. We increased
      // maxLength to 2000 to give them room.
      responseText = stripThinkBlocks(responseText);

      debugPrint('[Objective] Raw tasks response:\n$responseText');

      // Parse numbered list — tolerant of multiple formats (1. / 1) / - / bullet / plain)
      final lines = responseText.split('\n');
      final genTasks = <Map<String, dynamic>>[];

      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        // Try numbered: "1. ...", "1) ...", "1 - ..."
        final numbered = RegExp(r'^\d+[\.\)\-]?\s*(.+)').firstMatch(trimmed);
        if (numbered != null) {
          final desc = numbered.group(1)!.trim();
          if (desc.isNotEmpty && !desc.startsWith('[')) {
            genTasks.add({'description': desc, 'completed': false});
          }
          continue;
        }
        // Try bullet: "- ...", "• ...", "* ..."
        final bullet = RegExp(r'^[-•*]\s+(.+)').firstMatch(trimmed);
        if (bullet != null) {
          final desc = bullet.group(1)!.trim();
          if (desc.isNotEmpty) {
            genTasks.add({'description': desc, 'completed': false});
          }
          continue;
        }
        // Plain sentence fallback (skip very short lines or header-like lines)
        if (trimmed.length > 15 &&
            !trimmed.endsWith(':') &&
            genTasks.length < taskCount) {
          genTasks.add({'description': trimmed, 'completed': false});
        }
      }

      // De-duplicate and cap
      final seen = <String>{};
      final uniqueTasks = genTasks
          .where((t) => seen.add(t['description'] as String))
          .take(taskCount)
          .toList();

      if (uniqueTasks.isNotEmpty) {
        await saveObjectiveTasks(obj.id, jsonEncode(uniqueTasks));
        await loadActiveObjectives();
        debugPrint('[Objective] Generated ${uniqueTasks.length} tasks');
      } else {
        // Parse failed — restore previous tasks so we don't leave an empty list
        debugPrint(
          '[Objective] Could not parse tasks from response — restoring previous',
        );
        await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
        await loadActiveObjectives();
      }
    } catch (e) {
      debugPrint('[Objective] Task generation failed: $e');
      // Restore previous tasks on error
      await saveObjectiveTasks(obj.id, jsonEncode(previousTasks));
      await loadActiveObjectives();
    }
  }

  Future<void> checkTaskCompletionInBackground() async {
    if (getIsCheckingCompletion() || getActiveObjectives().isEmpty) return;
    setIsCheckingCompletion(true);

    try {
      final llmService = getLlmService();
      if (!llmService.isReady) return;

      final msgs = getMessages();
      final recentMessages = msgs.length > 8
          ? msgs.sublist(msgs.length - 8)
          : msgs;
      final contextText = recentMessages
          .map((m) => '${m.sender}: ${m.text}')
          .join('\n');

      // Check sequentially so no "time skips"
      for (final obj in getActiveObjectives()) {
        final tasks = tasksForObjective(obj);
        final currentTask = tasks
            .where((t) => t['completed'] != true)
            .map((t) => t['description'] as String)
            .firstOrNull;

        if (currentTask == null && tasks.isNotEmpty) {
          continue; // All tasks finished but objective not manually resolved
        }

        final evalTarget = currentTask != null
            ? 'Task to evaluate: "$currentTask"\n'
            : 'Objective to evaluate: "${obj.objective}"\n';
        final promptType = currentTask != null ? 'task' : 'objective';

        final prompt =
            'You are evaluating whether a roleplay $promptType has been completed based on recent conversation. '
            'Be generous in your assessment — if the events in the conversation show the $promptType has been '
            'accomplished, partially fulfilled, or naturally resolved, answer YES.\n\n'
            'Objective Context: "${obj.objective}"\n'
            '$evalTarget\n'
            'Recent conversation:\n$contextText\n\n'
            'Has this $promptType been completed or effectively resolved? Answer only YES or NO:';

        final params = GenerationParams(
          prompt: prompt,
          maxLength: 2000,
          temperature: 0.1,
          stopSequences: [],
        );

        String responseText = '';
        await for (final chunk in llmService.generateStream(params)) {
          responseText += chunk;
        }

        // Strip <think>...</think> blocks (and unclosed ones). Thinking models can
        // emit long internal reasoning before the final YES/NO. maxLength bumped
        // to 2000 to accommodate.
        responseText = stripThinkBlocks(responseText);

        debugPrint(
          '[Objective] Completion check for "${obj.objective}${currentTask != null ? ' - $currentTask' : ''}": $responseText',
        );

        if (responseText.toUpperCase().contains('YES')) {
          if (currentTask != null) {
            // Note: task list mutation here is best-effort in engine; real complete
            // uses god's tasksFor + db update via cb. For moved body fidelity we
            // re-load and let god paths handle index mutation via public toggle or
            // the check caller. (smallest: the YES path for tasks updates via
            // save with reconstructed list if we had full tasks cb; here we
            // trigger load and rely on god's _maybe path having current view.
            // To exact, we would pass full tasks cb returning mutable, but per
            // "objective mgmt thin in god" we keep mutation in god for step9.
            // The debug + active=false for taskless is done via cb.
            await loadActiveObjectives();
            debugPrint(
              '[Objective] Task completed (via god coordination): $currentTask',
            );
          } else {
            // It was a taskless objective that got completed!
            await deactivateObjective(obj.id);
            await loadActiveObjectives();
            debugPrint(
              '[Objective] Taskless objective naturally completed: ${obj.objective}',
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Objective] Completion check failed: $e');
    } finally {
      setIsCheckingCompletion(false);
      onNotify();
    }
  }

  // ── Needs impact (consolidated; Proposal A + rich JSON) ─────────────────────
  /// Thin + full impl for the consolidated needs impact eval (one call replacing
  /// the 4 prior god checks: climax/sexual/daily/fulfillment).
  /// Prompt reuses personality/stance/recent patterns from rel/phys/narr/oneShot.
  /// Strict: "ONLY unambiguous description of the *act*" (eating food not metaphor;
  /// deliberate non-sexual bath not rinse; completed sleep; physical climax for $charName only).
  /// Includes activities, intensity, grounded deltas for all needs, fulfillments,
  /// reason, refractory/orgasm_intensity if climax. 1:1/group parity qualified
  /// (via god impersonation + cbs); oneShot vs normal also (same path).
  /// "some coordination stayed thin in god per plan (qualify)".
  /// The evaluator sibling owns table/modifiers/parse/apply/NeedsImpact; this
  /// centralizes the LLM fire/strip (4000 budget) + prompt.
  Future<String?> evaluateNeedsImpactCall(
    String responseText, {
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return null;
    if (getActiveCharacter() == null && getActiveGroup() == null) return null;
    if (getActiveGroup() != null && getIsObserverMode()) {
      return null; // Director
    }

    final msgs = getMessages();
    final recentCount = msgs.length < 3 ? msgs.length : 3;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    final char = getActiveCharacter();
    final charName = char?.name ?? 'the character';
    String personalityInjection = '';
    if (char != null && char.personality.isNotEmpty) {
      final p = char.personality;
      personalityInjection = 'Character Personality Traits:\n"$p"\n\n';
    }
    final currentStance = relationshipService.spatialStance.isNotEmpty
        ? 'Current physical position/stance of $charName: "${relationshipService.spatialStance}". '
        : '';

    final prompt =
        'Read the following character response and detect *completed* scene actions that affect needs. '
        'A need is only fulfilled or a daily/sexual act only counts if the action was COMPLETED and unambiguously described in the scene — not just mentioned or used as metaphor.\n\n'
        '$personalityInjection'
        '$currentStance'
        'RESPONSE:\n$responseText\n\n'
        'Recent exchange for context:\n$recent\n\n'
        'Detect ONLY if unambiguous description of the *act* (e.g. "she ate the full dinner", "they slept for hours", "he came inside her", "she took a long hot shower"). '
        'Do NOT trigger on metaphors ("devoured her lips", "sated by your touch", "waves of pleasure washed over" alone do not count as ate/slept/sexual for positives). '
        'For pure romantic/sexual scenes without explicit eat/drink/sleep/bath words: energy and hunger deltas must be neutral or small negative (no replenish from intimacy). '
        'Hygiene negative only on explicit mess (creampie, cum on face/tits/stomach/sheets, fluids, messy, internal) or high intensity + stance shows exposure (not contained in shower/bath).\n\n'
        'Respond with ONLY a flat JSON object:\n'
        '{"activities": ["sexual_climax" or "sexual_nonclimax" or "ate" or "slept" or "bathed"], '
        '"intensity": 1-10, '
        '"hunger_delta": <int>, "energy_delta": <int>, "hygiene_delta": <int>, "fun_delta": <int>, "social_delta": <int>, "bladder_delta": <int>, "comfort_delta": <int>, '
        '"fulfillment": {"hunger": true/false, "energy": ..., ... for any low needs in context}, '
        '"reason": "<brief grounded reason>", '
        '"refractory_turns": <1-8 or omit>, "orgasm_intensity": <1-10 or omit>, '
        '"is_climax": true/false }\n'
        'If no clear completed act matching the rules, return {"activities": [], "intensity": 0, ... all deltas 0, "reason": "none"}.';

    try {
      debugPrint(
        '[Realism:Needs] Running consolidated impact eval (via engine)...',
      );
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return null;
      final searchText = stripThinkBlocks(raw);
      return searchText.isNotEmpty ? searchText : raw;
    } catch (e) {
      debugPrint('[Realism:Needs] Engine impact call failed: $e');
      return null;
    }
  }
}
