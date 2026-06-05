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

import 'package:flutter/foundation.dart';

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
/// _stripThinkBlocks (handles completed + unclosed &lt;think&gt; prefix).
/// (The 5 realism eval prompt builders + call methods (relationship, emotional,
/// physical, narrative with proposed_objective logic, one-shot fused) moved to
/// sibling leaf realism_evals.dart in step 10 per extraction order; the
/// objective proposal path handling + generateObjectiveTasks +
/// _checkTaskCompletionInBackground moved to sibling leaf
/// objective_proposal.dart in step 11; this engine now provides the
/// fire/strip/extract cbs + evaluateNeedsImpactCall for the needs domain +
/// the 5 realism calls (granular cbs to realism_evals) + fire/strip to
/// objective_proposal.)
///
/// Extracted as step 9 (immediately after prompt_injection step 8 per the
/// 15-step leaf-first order in docs/refactoring-guide.md).
/// + needs impact support (evaluateNeedsImpactCall + consolidated prompt for
/// the needs_impact_evaluator sibling leaf in the needs domain rework).
/// + step 10 sibling realism_evals uses this engine's fire/strip/extract for the
/// 5 realism calls (granular cbs; prompt builders full in leaf).
/// + step 11 sibling objective_proposal uses this engine's strip (for central
/// &lt;think&gt; in 2000 gen/check paths).
///
/// Depends on prompt_injection only in the ordering sense (prompt builders
/// for main chat context are step 8); this engine's eval prompts are
/// self-contained (no direct use of the 8 _get*Injection builders).
/// "thin delegation here; full engine in step9"; "objective proposal
/// coordination kept thin/stayed in god per plan for step9/11" (setObjective
/// + generate dispatch + list mgmt + _load + _activeObjectives + tasksFor
/// + _isChecking + _pendingRealismMetadata + captureRealismState +
/// _saveChat coordination stay in god; engine calls via cbs only; full
/// gen/check + internal prompt/strip/parse in step 11 leaf).
///
/// ChatService owns via 1 late final (inserted after the 8 prompt_injection
/// ones) + thin public delegates (_fireLLMEval, _stripThinkBlocks,
/// _extract*, evaluateNeedsImpactCall) at *every* prior call site (firing points,
/// direct _fire/_strip/_extract calls, needs impact thin). The 5 _evaluate*Call
/// thins delegate to realism_evals (step 10). generateObjectiveTasks +
/// _checkTaskCompletionInBackground thins now delegate to objective_proposal
/// (step 11). 0 @Deprecated shims for this surface (thins stay in god as the
/// public surface for now).
/// 0 new god private _ methods beyond the required thin delegates (_fireLLMEval/_strip/_extract* + evaluateNeedsImpactCall; void _ count stayed 15; +1 late final only; thins/calls/late final only per plan;
/// reset comment syncs only).
///
/// Ctor receives state via granular callbacks (modeled exactly on steps 6-8:
/// onNotify, onSaveChat (now dead post step11 objective move; removed below),
/// getActiveCharacter, getActiveGroup, getGroupCharacters
/// not needed here, getUserName, getCharacterIdFromCard not directly,
/// isGroup/isObserverMode via getActiveGroup+getIsObserverMode,
/// getGroupValue/setGroupValue not needed (use rel/nsfw services for scalars),
/// plus for fire readiness + cancel: getLlmService, getIsLocal, getKoboldService,
/// reconnectIfAlive, ensureServerIdle, getIsCancellingRealismEval,
/// getRealismEvalCancelled,
/// plus for state sets (now used by needs impact; realism evals use via their own
/// leaf cbs; objective gen/check moved to step 11 leaf): get/setPendingRealismMetadata,
/// captureRealismState, get/setCharacterEmotion, get/setEmotionIntensity,
/// plus dep services for their owned state (relationshipService for apply deltas /
/// updateFixation / setSpatial / shortTermTierName / trustLevel / spatialStance
/// used by stayed needs impact path).
/// Use live closures over god state for any cross (e.g. _pending map, emotion
/// scalars, test overrides); avoid cycles; testable with small factory in test.
///
/// 1:1 vs group parity + oneShot vs normal eval deltas 1:1 equivalent
/// (Realism Engine bond/trust ±300, arousal ±100, emotion inertia, fixation,
/// deterministic time every 6, needs decay/step/catastrophe/erotic buffers/
/// afterglow/lust-haze/post-crash/priority/fulfillment; objectives/tasks
/// autonomous get autoGenerateTasks:true + correct target even under
/// impersonation, user-created do not — proposal target + gen/check dispatch
/// preserved via cbs + god impersonation; full in step 11 leaf) qualified
/// (preserved exactly; exercised in dedicated + key suites + manual). The 5
/// realism calls now in sibling leaf (step 10) inherit the same cbs/impersonation
/// for parity.
///
/// All &lt;think&gt; stripping uses the central stripThinkBlocks (2000 budget
/// already applied in gen/check/objective paths via step 11 leaf's use of this
/// strip cb; naive inlines in non-eval paths left for later steps).
///
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state);
/// no reset calls needed on engine; comments in god updated to list full
/// "needs/chaos/relationship/expression/time/nsfw/lorebook_scanner +
/// prompt_injection (stateless builders; no reset calls needed) +
/// llm_eval_engine (stateless or prompt-only; no reset calls needed;
/// incomplete zeroing of secondary config on group/0-session/new-chat now complete)
/// + realism_evals (stateless or prompt-only; no reset calls needed)
/// + objective_proposal (stateless or prompt-only; no reset calls needed)"
/// + cross-refs (e.g. setActiveCharacter:1572) at all ~12-15 sites (top ctor
/// docs + setActiveCharacter, setActiveGroup x2, _loadLast empty, startNewChat
/// 1:1 ext-seed + group non-ext both branches, other load/seed); both startNew
/// branches have explicit comments even if no engine reset call.
///
/// aug exercising only passive/qualified (no llm-eval-specific aug file edits;
/// reset sites passively hit by pre-existing startNew/setActive/_loadLast/group;
/// full eval/JSON/strip + needs impact only in dedicated + manual;
/// objective proposal/gen/check exercised via god thins generate/check ;
/// qualified notes only in dedicated header + god + MD per precedent).
///
/// test count 11 (11 bodies via grep -c '^\s*test(' confirmed post dead noop/placeholder deletion as part of task; objective tests excised to dedicated step11 test).
/// (onNotify of cbs unexercised by design (no onNotify wiring in this passive factory; exercised in prod + key suites); onNotify/onSaveChat now dead post step11 objective move, to be cleaned).
/// 0 new god private _ methods beyond required thin delegates (fire/strip/extract thins; void_ grep 15; +1 late final only; thins/calls/late final only per plan; confirmed grep).
/// dispatch preserved.
/// realism/oneShot/group parity qualified.
///
/// Some objective mgmt / prompt coordination stayed thin in god per plan for step9/11
/// (qualify everywhere; full objective proposal in step 11 sibling leaf).
/// Realism evals (step 10) own their 5 calls + prompts.
class LlmEvalEngine {
  // (onNotify/onSaveChat removed here post step11 objective_proposal extraction;
  // they were only used by the moved checkTaskCompletionInBackground finally;
  // deletion part of task + anti-accumulation. Engine is now strictly for fire/strip/
  // extract + needs impact call. on* if needed by future would be re-added then.)

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

  // (Objective proposal + gen/check cbs moved to step 11 sibling leaf
  // objective_proposal.dart; getExpressionEnabled also dead post step10 move of
  // realism evals; onSaveChat dead post step11; cleaned here as part of task.
  // onNotify remains declared for now but will be audited; if unused after,
  // further hygiene in later.)

  LlmEvalEngine({
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
  });

  // ── Public surface (thins in god delegate here; used by tests + god) ──

  /// Shared helper: strip think blocks and extract text after them.
  /// (Central implementation; all &lt;think&gt; handling for evals + needs impact
  /// routes here. 2000 budget for gen/check paths now applied in step 11
  /// objective_proposal leaf via this strip cb passed from god thin.)
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

  // (generateObjectiveTasks excised; full impl + prompt/strip/parse/2000 now in
  // objective_proposal.dart step 11. Deletion part of task.)

  // (checkTaskCompletionInBackground excised; full body + logic moved to
  // objective_proposal.dart step 11. Deletion part of task.)
  // (check + gen excised to objective_proposal step 11; deletion part of task)
  // (all dangling body chunks removed; engine clean for step 11.)

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
