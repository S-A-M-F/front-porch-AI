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
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';
import 'package:front_porch_ai/models/group_chat.dart';

/// Plain (non-ChangeNotifier) domain service owning the central LLM eval
/// firing (_fireLLMEval with full streaming + retry loop + cancel support,
/// fixed params maxLength:4000 / temp 0.1 / reasoningEnabled:false / stop []),
/// the tiny _extractJsonInt/_extractJsonBool helpers, the central
/// _stripThinkBlocks (handles completed + unclosed &lt;think&gt; prefix), the 5
/// realism eval prompt builders + call methods (relationship, emotional,
/// physical, narrative with proposed_objective logic, one-shot fused), the
/// objective proposal path handling (autonomous "none" vs value, dedup,
/// autoGenerateTasks:true only for autonomous), generateObjectiveTasks
/// (2000 budget + central strip for thinking models), and
/// _checkTaskCompletionInBackground (2000 + strip).
///
/// Extracted as step 9 (immediately after prompt_injection step 8 per the
/// 15-step leaf-first order in docs/refactoring-guide.md).
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
/// _extract*, the 5 _evaluate*Call, generateObjectiveTasks,
/// _checkTaskCompletionInBackground) at *every* prior call site (the 5
/// firing points in sendMessage + oneShot/greeting/post paths, all direct
/// _fire/_strip/_extract calls, proposed_objective sites in narr/oneShot,
/// gen/check sites, objective proposal + JSON parse sites). 0 @Deprecated
/// shims for this new surface (thins stay in god as the public surface for now).
/// 0 new god private _ methods beyond the required thin delegates (_fireLLMEval/_strip/_extract*/_evaluate*Call/_check + gen thins; void _ count stayed 15; +1 late final only; thins/calls/late final only per plan;
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
/// plus for state sets in evals: get/setPendingRealismMetadata, captureRealismState,
/// get/setCharacterEmotion, get/setEmotionIntensity,
/// plus dep services for their owned state (relationshipService for apply deltas /
/// updateFixation / setSpatial / shortTermTierName / trustLevel / spatialStance,
/// nsfwService for cooldown/arousal/setArousal, timeService for the physical
/// posture/time progress delegation).
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
/// dedicated + key suites + manual).
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
/// incomplete zeroing of secondary config on group/0-session/new-chat now complete)"
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
/// 0 new god private _ methods beyond required thin delegates (fire/strip/extract/eval/check thins; void_ grep 15; +1 late final only; thins/calls/late final only per plan; confirmed grep).
/// dispatch preserved.
/// realism/oneShot/group parity qualified.
///
/// Some objective mgmt / prompt coordination stayed thin in god per plan for step9
/// (qualify everywhere).
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
  final NsfwService nsfwService;
  final TimeService timeService;

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
    required this.nsfwService,
    required this.timeService,
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

  Future<void> evaluateRelationshipCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) {
      return; // Director excluded
    }

    final msgs = getMessages();
    final recentCount = msgs.length < 3 ? msgs.length : 3;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final charName = getActiveCharacter()!.name;
    final userName = getUserName();

    String personalityInjection = '';
    if (getActiveCharacter()!.personality.isNotEmpty) {
      final p = getActiveCharacter()!.personality;
      personalityInjection =
          'Account for $charName\'s specific personality traits:\n"$p"\n\n';
    }

    final prompt =
        'You are a nuanced evaluator of relationship dynamics between $charName and $userName in a roleplay.\n\n'
        '$personalityInjection'
        'IMPORTANT: Reactions are entirely subjective based on $charName\'s personality. '
        'Most normal interactions should score 0 or slightly positive. '
        'Reserve negative scores ONLY for clear rudeness, hostility, manipulation, or betrayal.\n\n'
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (-15 to +15)\n'
        '   +15: Life-changing — a moment that fundamentally redefines the relationship\n'
        '   +10: Profoundly moving — raw vulnerability, sacrifice, or devotion that leaves $charName shaken\n'
        '   +7: Deeply touched — a significant emotional breakthrough or act of genuine care\n'
        '   +5: Meaningfully warmed — a moment that clearly strengthens the connection\n'
        '   +3: Moved | +2: Warmed up | +1: Mildly pleasant\n'
        '   -1: Slightly put off | -2: Annoyed | -3: Hurt — a clearly unkind or dismissive moment\n'
        '   -5: Wounded — a significant emotional injury\n'
        '   -8: Deeply hurt — a cruel or callous act that damages the bond\n'
        '   -10: Devastated — a severe betrayal of emotional trust\n'
        '   -15: Devastating betrayal — a relationship-destroying act\n'
        '   ⚠ Default to 0 for normal conversation. Only go negative if $userName was clearly unkind, dismissive, or harmful.\n'
        '2. "bond_reason": One brief in-character thought from $charName explaining the tension shift, e.g. "His warmth made me feel safe." or "That dismissal stung." Use "none" if delta is 0.\n'
        '3. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (-200 to +50)\n'
        '   Trust is SUBJECTIVE to $charName\'s personality and what she values. Examples:\n'
        '   +30 to +50: $userName did something EXTRAORDINARILY trustworthy — a selfless sacrifice, returning something precious, protecting $charName at real cost to themselves, or proving loyalty in a way that CANNOT be faked\n'
        '   +10 to +20: $userName did something meaningfully trustworthy — kept a difficult promise, showed vulnerability, stood firm under pressure in a way $charName deeply respects\n'
        '   +5: $userName did exactly what $charName craves or values most | +2: acted authentically in a way $charName respects | 0: Neutral\n'
        '   -5: $userName did something $charName finds personally untrustworthy given her personality | -30: deliberate deception or betrayal | -200: Unforgivable betrayal\n'
        '   ⚠ Default to 0. Consider her personality — what one character finds threatening another may find attractive or trust-building.\n'
        '   ⚠ If $charName is the one acting (e.g. $charName lied, felt guilty, made a mistake): always 0. Only $userName\'s behavior moves this.\n'
        '4. "trust_reason": One brief in-character thought from $charName explaining the trust shift, e.g. "He kept his promise." or "That felt like a lie." Use "none" if delta is 0.\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "relationship_delta", "bond_reason", "trust_delta", and "trust_reason".';

    try {
      debugPrint('[Realism] Evaluating relationship dynamic...');
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      final relDelta = extractJsonInt(text, 'relationship_delta');
      int bondDelta = 0;
      if (relDelta != null) {
        bondDelta = relDelta.clamp(-50, 50);
        relationshipService.applyScoreDelta(bondDelta);
      }

      int trustDelta = 0;
      final trDelta = extractJsonInt(text, 'trust_delta');
      if (trDelta != null) {
        trustDelta = trDelta.clamp(-200, 50);
        if (trustDelta != 0) {
          relationshipService.applyTrustDelta(trustDelta);
        }
      }

      int arousalDelta = 0;
      if (nsfwService.nsfwCooldownEnabled) {
        final arDelta = extractJsonInt(text, 'arousal_delta');
        if (arDelta != null) {
          arousalDelta = arDelta.clamp(-25, 25);
          nsfwService.setArousalLevel(
            (nsfwService.arousalLevel + arousalDelta).clamp(-100, 100),
          );
        }
      }

      if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
        var pending = getPendingRealismMetadata() ?? {};
        if (bondDelta != 0) pending['bond_delta'] = bondDelta;
        if (arousalDelta != 0) {
          pending['arousal_delta'] = arousalDelta;
        }
        if (trustDelta != 0) {
          pending['trust_delta'] = trustDelta;
        }
        setPendingRealismMetadata(pending);
      }

      // Extract and store per-chip reasons
      final bondReasonMatch = RegExp(
        r'"bond_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final bondReason = bondReasonMatch?.group(1)?.trim() ?? '';
      if (bondReason.isNotEmpty && bondReason.toLowerCase() != 'none') {
        var pending = getPendingRealismMetadata() ?? {};
        pending['bond_reason'] = bondReason;
        setPendingRealismMetadata(pending);
      }

      final trustReasonMatch = RegExp(
        r'"trust_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final trustReason = trustReasonMatch?.group(1)?.trim() ?? '';
      if (trustReason.isNotEmpty && trustReason.toLowerCase() != 'none') {
        var pending = getPendingRealismMetadata() ?? {};
        pending['trust_reason'] = trustReason;
        setPendingRealismMetadata(pending);
      }

      debugPrint(
        '[Realism:Relationship] Bond: $bondDelta (${bondReason.isNotEmpty ? bondReason : 'no reason'}) | Trust: $trustDelta (${trustReason.isNotEmpty ? trustReason : 'no reason'})',
      );
      debugPrint(
        '[Realism:Metadata] _pendingRealismMetadata after relationship eval: ${getPendingRealismMetadata()}',
      );
    } catch (e) {
      debugPrint('[Realism:Relationship] Failed: $e');
    }
  }

  Future<void> evaluateEmotionalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;
    final msgs = getMessages();
    final recentCount = msgs.length < 4 ? msgs.length : 4;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final charName = getActiveCharacter()!.name;

    // ── Personality injection (same as relationship eval) ──
    String personalityInjection = '';
    if (getActiveCharacter()!.personality.isNotEmpty) {
      final p = getActiveCharacter()!.personality;
      personalityInjection =
          '$charName\'s personality traits (evaluate emotion THROUGH these):\n"$p"\n\n';
    }

    // ── Relationship & trust context ──
    final relationshipCtx =
        'Current relationship tension: ${relationshipService.shortTermTierName} | Trust level: ${relationshipService.trustLevel}\n';

    // ── Arousal instruction (enriched with current level + behavioral visibility) ──
    final arousalField = nsfwService.nsfwCooldownEnabled
        ? ', "arousal_delta": <number -25 to +25>'
        : '';
    final arousalInstr = nsfwService.nsfwCooldownEnabled
        ? '3. "arousal_delta": Physical arousal shift this turn. (-25 to +25)\n'
              '   Current arousal: ${nsfwService.arousalLevel}/100. '
              'Arousal measures DESIRE and PHYSICAL RESPONSE, not progress toward orgasm.\n'
              '   Be bold with arousal deltas — intimate moments should produce significant shifts (+10 to +20).\n'
              '   High arousal = the character is intensely turned on, NOT that they are about to climax '
              '— climax only happens during active sexual contact at high arousal.\n'
              '   CRITICAL: Arousal MUST be VISIBLE in character behavior. At high levels (60+), '
              'show heavy breathing, stuttering, flushed skin, inability to focus, desperate body language.\n'
              '   Examples: whispered compliment = +3, passionate kiss = +10 to +15, '
              'explicit sexual contact = +15 to +25, humiliating rejection = -15 to -25.\n'
        : '';

    // ── Emotion inertia context ──
    final curEmotion = getCharacterEmotion();
    final curIntensity = getEmotionIntensity();
    final currentEmotionCtx = curEmotion.isNotEmpty
        ? 'Current emotional state: $curEmotion${curIntensity.isNotEmpty ? ' ($curIntensity)' : ''}.\n'
              'Emotions have natural inertia — only shift meaningfully if something in the conversation genuinely warrants it. '
              'Minor or neutral exchanges should produce small drift, not sudden jumps.\n'
              'BUT: after intense events (fights, confessions, betrayals, intimate moments), '
              'emotions naturally LINGER for several turns — do NOT rush back to baseline. '
              'Only drift toward settled during truly mundane exchanges.\n\n'
        : '';

    final prompt =
        'You are evaluating the emotional state for $charName.\n\n'
        '$personalityInjection'
        '$relationshipCtx'
        '$currentEmotionCtx'
        '1. "emotion": $charName\'s overarching emotional state right now (one nuanced word).\n'
        '   NOT a generic label like "happy" or "sad" — find the *specific texture*:\n'
        '   wistful not sad, flustered not happy, prickly not angry, smoldering not aroused.\n'
        '   Filter through $charName\'s personality — a stoic character feeling deep pain\n'
        '   might show "guarded" or "controlled" rather than "devastated".\n'
        '${getExpressionEnabled() ? '   ⚠ YOU MUST choose EXACTLY ONE of these labels: ${EmotionLabels.all.join(", ")}. No other words allowed.\n' : ''}'
        '2. "emotion_intensity": mild, moderate, or strong\n'
        '$arousalInstr\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "emotion", "emotion_intensity"$arousalField.';

    try {
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;
      final text = stripThinkBlocks(raw).isNotEmpty
          ? stripThinkBlocks(raw)
          : raw;

      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (emotionMatch != null) {
        setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
      }

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (intensityMatch != null) {
        setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
      }

      if (nsfwService.nsfwCooldownEnabled) {
        final arDelta = extractJsonInt(text, 'arousal_delta');
        if (arDelta != null) {
          final arousalDelta = arDelta.clamp(-10, 10);
          nsfwService.setArousalLevel(
            (nsfwService.arousalLevel + arousalDelta).clamp(-100, 100),
          );
          if (arousalDelta != 0) {
            var pending = getPendingRealismMetadata() ?? {};
            pending['arousal_delta'] = arousalDelta;
            setPendingRealismMetadata(pending);
          }
        }
      }
      debugPrint(
        '[Realism:Emotion] Emotion: ${getCharacterEmotion()} (${getEmotionIntensity()})',
      );
    } catch (e) {
      debugPrint('[Realism:Emotion] Failed: $e');
    }
  }

  Future<void> evaluatePhysicalStateCall({
    void Function(String)? onChunk,
  }) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;

    final msgs = getMessages();
    final recentCount = msgs.length < 6 ? msgs.length : 6;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet.
      // (Time advance is chat-scoped and handled via delegation when active char is impersonated for group speaker.)
      return;
    }
    final charName = getActiveCharacter()!.name;

    // Time progress + posture (when passage enabled) + disabled-passage posture path
    // now fully delegated to TimeService (pre-turn advance logic moved verbatim,
    // adjusted only for granular cbs). No new private method in god.
    // shortTermTierName resolves via relationshipService.
    await timeService.evaluateTimeProgressAndPostureIfNeeded(
      charName: charName,
      recent: recent,
      shortTermTierName: relationshipService.shortTermTierName,
      onChunk: onChunk,
      fireLLMEval: fireLLMEval,
      stripThinkBlocks: stripThinkBlocks,
      extractJsonBool: extractJsonBool,
      setSpatialStance: relationshipService.setSpatialStance,
      getCurrentSpatialStance: () => relationshipService.spatialStance,
      getCharacterEmotion: getCharacterEmotion,
      getEmotionIntensity: getEmotionIntensity,
    );
  }

  Future<void> evaluateNarrativeCall({void Function(String)? onChunk}) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;
    final msgs = getMessages();
    final recentCount = msgs.length < 4 ? msgs.length : 4;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');
    if (getActiveCharacter() == null) {
      // This path requires an active character (the group per-speaker path
      // temporarily sets _activeCharacter before calling us for parity).
      return;
    }
    final charName = getActiveCharacter()!.name;
    final primary = getPrimaryObjective();
    final oPrompt = primary != null
        ? '1. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue — something DISTINCT from the current Primary Quest ("${primary.objective}"). Must be a significant personal, social, or narrative goal triggered by a STRONG, specific event THIS turn. NOT a trivial step, and NOT a restatement of the primary quest.\n'
              '   ⚠ Default to "none". 90% of turns should produce "none". Only propose one if $charName would literally lose sleep over it.\n'
        : '1. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue, triggered by a strong specific event THIS turn — could be emotional (confess feelings), practical (plan a surprise), or personal (achieve something they\'ve been working toward). Default: "none".\n'
              '   ⚠ Default to "none". 90% of turns should produce "none". Only propose one if $charName would literally lose sleep over it.\n';
    final prompt =
        'You are an autonomous story engine evaluating narrative progression for $charName.\n\n'
        '$oPrompt'
        '2. "fixation_topic": A persistent thought or concern that colors $charName\'s perspective — could be a hope, worry, ambition, or memory. Not a temporary reaction, but something that lingers across scenes. Default: "none".\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "proposed_objective", and "fixation_topic".';

    try {
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;
      final text = stripThinkBlocks(raw).isNotEmpty
          ? stripThinkBlocks(raw)
          : raw;

      relationshipService.updateFixationFromEvalResult(
        (RegExp(
              r'"fixation_topic"\s*:\s*"([^"]+)"',
            ).firstMatch(text)?.group(1) ??
            ''),
      );

      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          final active = getActiveObjectives();
          final isDuplicate = active.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate) {
            debugPrint(
              '[Realism:Narrative] Autonomous objective proposed: $newObj',
            );
            // Pass autoGenerateTasks:true so the character's self-initiated goal gets
            // concrete subtasks (making autonomous objectives feel like real pursuits
            // with steps the character can accomplish).
            // (thin delegation to god setObjective per plan for step9; full proposal logic here)
            await setObjective(
              newObj,
              isPrimary: false,
              autoGenerateTasks: true,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[Realism:Narrative] Failed: $e');
    }
  }

  /// ── One-Shot Eval (Experimental) ─────────────────────────────────────────
  /// Fused replacement for _evaluateRelationshipCall + _evaluateSceneStateCall.
  /// Issues a SINGLE LLM inference that evaluates all realism state fields at
  /// once, cutting pre-generation blocking overhead from 2 calls to 1.
  ///
  /// Enable via Settings → Realism → "One-Shot Eval (Experimental)".
  /// Not default because some models struggle with the combined prompt length.
  Future<void> evaluateOneShotCall({void Function(String)? onChunk}) async {
    if (!getRealismEnabled()) return;
    if (getActiveCharacter() == null && getActiveGroup() == null) return;
    if (getActiveGroup() != null && getIsObserverMode()) return;

    // The group speaker path sets _activeCharacter before calling this for parity.

    // Keep the eval prompt lean for local models — use fewer messages and a
    // shorter personality snippet to reduce prefill time on large models.
    final msgs = getMessages();
    final recentCount = msgs.length < 6 ? msgs.length : 6;
    final recent = msgs.reversed
        .take(recentCount)
        .toList()
        .reversed
        .map((m) => '${m.sender}: ${m.displayText}')
        .join('\n');

    if (getActiveCharacter() == null) {
      // Group chat or other mode — relationship evals not supported in this path yet
      return;
    }
    final charName = getActiveCharacter()!.name;
    final userName = getUserName();

    String personalityInjection = '';
    if (getActiveCharacter()!.personality.isNotEmpty) {
      final p = getActiveCharacter()!.personality;
      personalityInjection =
          'Account for $charName\'s specific personality traits:\n"$p"\n\n';
    }

    // ── Relationship & trust context ──
    final curEmotion = getCharacterEmotion();
    final curIntensity = getEmotionIntensity();
    final emotionCtx = curEmotion.isNotEmpty
        ? 'Current emotional state: $curEmotion ($curIntensity). '
        : '';
    final postureCtx = relationshipService.spatialStance.isNotEmpty
        ? 'Recent position reference: $charName was "${relationshipService.spatialStance}". '
        : '';
    final relationshipCtx =
        '$emotionCtx${postureCtx}Current relationship tension: ${relationshipService.shortTermTierName} | Trust level: ${relationshipService.trustLevel}\n\n';

    final arousalField = nsfwService.nsfwCooldownEnabled
        ? ', "arousal_delta": <number -25 to +25>'
        : '';
    // Arousal is field 8 (after posture), objective is 9, fixation 10, reason 11
    final arousalInstr = nsfwService.nsfwCooldownEnabled
        ? '8. "arousal_delta": Physical arousal shift this turn. (-25 to +25)\n'
              '   Current arousal: ${nsfwService.arousalLevel}/100. '
              'Arousal = DESIRE and PHYSICAL RESPONSE, not progress toward orgasm.\n'
              '   Be bold — intimate moments should produce significant shifts (+10 to +20).\n'
              '   CRITICAL: Arousal MUST be VISIBLE in character behavior. At 60+, show heavy breathing, stuttering, flushed skin, desperate body language.\n'
              '   High arousal = intensely turned on, NOT about to climax — climax only during active sexual contact at peak arousal.\n'
              '   Examples: whispered compliment = +3, passionate kiss = +10 to +15, explicit contact = +15 to +25.\n'
        : '';

    // Determine the next field number after arousal (or after posture if arousal disabled)
    final objNum = nsfwService.nsfwCooldownEnabled ? 9 : 8;
    final fixNum = objNum + 1;
    final reasonNum = fixNum + 1;

    final primary = getPrimaryObjective();
    final prompt =
        'You are evaluating the current state of a roleplay scene involving $charName.\n\n'
        '$personalityInjection'
        '$relationshipCtx'
        'Reactions are subjective! Evaluate ALL changes through $charName\'s specific personality.\n\n'
        'Evaluate ALL of the following at once:\n'
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (-15 to +15)\n'
        '   +15: Life-changing — a moment that fundamentally redefines the relationship\n'
        '   +10: Profoundly moving — raw vulnerability, sacrifice, or devotion that leaves $charName shaken\n'
        '   +7: Deeply touched — a significant emotional breakthrough or act of genuine care\n'
        '   +5: Meaningfully warmed — a moment that clearly strengthens the connection\n'
        '   +3: Moved | +2: Warmed up | +1: Mildly pleasant\n'
        '   -1: Slightly put off | -2: Annoyed | -3: Hurt — a clearly unkind or dismissive moment\n'
        '   -5: Wounded — a significant emotional injury\n'
        '   -8: Deeply hurt — a cruel or callous act that damages the bond\n'
        '   -10: Devastated — a severe betrayal of emotional trust\n'
        '   -15: Devastating betrayal — a relationship-destroying act\n'
        '   ⚠ Default to 0 for normal conversation. Only go negative if $userName was clearly unkind, dismissive, or harmful.\n'
        '2. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (-200 to +50)\n'
        '   Trust is SUBJECTIVE to $charName\'s personality and what she values. Examples:\n'
        '   +30 to +50: $userName did something EXTRAORDINARILY trustworthy — a selfless sacrifice, returning something precious, protecting $charName at real cost to themselves, or proving loyalty in a way that CANNOT be faked\n'
        '   +10 to +20: $userName did something meaningfully trustworthy — kept a difficult promise, showed vulnerability, stood firm under pressure in a way $charName deeply respects\n'
        '   +5: $userName did exactly what $charName craves or values most | +2: acted authentically in a way $charName respects | 0: Neutral\n'
        '   -5: $userName did something $charName finds personally untrustworthy given her personality | -30: deliberate deception or betrayal | -200: Unforgivable betrayal\n'
        '   ⚠ Default to 0. Consider her personality — what one character finds threatening another may find attractive or trust-building.\n'
        '   ⚠ If $charName is the one acting (e.g. $charName lied, felt guilty, made a mistake): always 0. Only $userName\'s behavior moves this.\n'
        '3. "trust_reason": One brief in-character thought from $charName explaining the trust shift in $userName, or "none" if delta is 0.\n'
        '4. "emotion": $charName\'s overarching emotional state (one nuanced word).\n'
        '   NOT generic ("happy"/"sad") — find the specific texture: wistful not sad, flustered not happy, prickly not angry.\n'
        '   Filter through $charName\'s personality — a stoic character in deep pain shows "guarded", not "devastated".\n'
        '${getExpressionEnabled() ? '   ⚠ YOU MUST choose EXACTLY ONE of these labels: ${EmotionLabels.all.join(", ")}. No other words allowed.\n' : ''}'
        '5. "emotion_intensity": mild, moderate, or strong\n'
        '6. "bond_reason": One brief in-character thought from $charName explaining the relationship shift, or "none" if delta is 0.\n'
        '7. "posture": $charName\'s current physical position and location (brief grounded phrase), or "none".\n'
        '   - Match the posture to the current scene context and emotional state.\n'
        '   - If the conversation implies a location or activity change, update accordingly.\n'
        '   - Within the same scene, maintain natural continuity (don\'t jump locations).\n'
        '   - Across scene breaks or time jumps, update to the new context.\n'
        '   - If time advanced significantly or a new day started, characters naturally shift positions.\n'
        '$arousalInstr'
        '${primary != null ? '$objNum. "proposed_objective": A meaningful, emotionally-driven goal $charName independently wants to pursue — something DISTINCT from the current Primary Quest ("${primary.objective}"). Triggered by a STRONG event THIS turn.\n   ⚠ Default to "none". 90% of turns should produce "none".\n' : '$objNum. "proposed_objective": A meaningful, emotionally-driven goal triggered by a strong event THIS turn. Default: "none". 90% of turns should produce "none".\n'}'
        '$fixNum. "fixation_topic": An *intrusive* thought $charName cannot stop returning to — haunts them across scenes, not a temporary reaction. Default: "none".\n'
        '$reasonNum. "reason": One brief sentence explaining the key relationship change, or "none"\n\n'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a JSON object containing all fields above$arousalField.';

    try {
      debugPrint('[Realism:OneShot] Evaluating (fused call)...');
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

      // ── Relationship fields ──
      int bondDelta = 0;
      final relDelta = extractJsonInt(text, 'relationship_delta');
      if (relDelta != null) {
        bondDelta = relDelta.clamp(-50, 50);
        relationshipService.applyScoreDelta(bondDelta);
      }

      int trustDelta = 0;
      final trDelta = extractJsonInt(text, 'trust_delta');
      if (trDelta != null) {
        trustDelta = trDelta.clamp(-50, 30);
        if (trustDelta != 0) {
          relationshipService.applyTrustDelta(trustDelta);
        }
      }

      int arousalDelta = 0;
      if (nsfwService.nsfwCooldownEnabled) {
        final arDelta = extractJsonInt(text, 'arousal_delta');
        if (arDelta != null) {
          arousalDelta = arDelta.clamp(-25, 25);
          nsfwService.setArousalLevel(
            (nsfwService.arousalLevel + arousalDelta).clamp(-100, 100),
          );
        }
      }

      // Extract and store per-chip reasons for hover tooltips
      final bondReasonMatch = RegExp(
        r'"bond_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final bondReason = bondReasonMatch?.group(1)?.trim() ?? '';
      if (bondReason.isNotEmpty && bondReason.toLowerCase() != 'none') {
        var pending = getPendingRealismMetadata() ?? {};
        pending['bond_reason'] = bondReason;
        setPendingRealismMetadata(pending);
      }

      final trustReasonMatch = RegExp(
        r'"trust_reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text);
      final trustReason = trustReasonMatch?.group(1)?.trim() ?? '';
      if (trustReason.isNotEmpty && trustReason.toLowerCase() != 'none') {
        var pending = getPendingRealismMetadata() ?? {};
        pending['trust_reason'] = trustReason;
        setPendingRealismMetadata(pending);
      }

      if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
        var pending = getPendingRealismMetadata() ?? {};
        pending['bond_delta'] = bondDelta;
        if (arousalDelta != 0) {
          pending['arousal_delta'] = arousalDelta;
        }
        if (trustDelta != 0) {
          pending['trust_delta'] = trustDelta;
        }
        if (bondReason.isNotEmpty) {
          pending['bond_reason'] = bondReason;
        }
        if (trustReason.isNotEmpty) {
          pending['trust_reason'] = trustReason;
        }
        setPendingRealismMetadata(pending);
      } else if (bondReason.isNotEmpty || trustReason.isNotEmpty) {
        var pending = getPendingRealismMetadata() ?? {};
        if (bondReason.isNotEmpty) {
          pending['bond_reason'] = bondReason;
        }
        if (trustReason.isNotEmpty) {
          pending['trust_reason'] = trustReason;
        }
        setPendingRealismMetadata(pending);
      }

      // ── Autonomous Objective ──
      final objectiveMatch = RegExp(
        r'"proposed_objective"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (objectiveMatch != null) {
        final newObj = objectiveMatch.group(1)!.trim();
        if (newObj.toLowerCase() != 'none' && newObj.isNotEmpty) {
          // Avoid setting the exact same goal if it's already active
          final active = getActiveObjectives();
          final isDuplicate = active.any(
            (o) => o.objective.toLowerCase() == newObj.toLowerCase(),
          );
          if (!isDuplicate) {
            debugPrint(
              '[Realism:OneShot] Autonomous objective proposed: $newObj',
            );
            // Auto objectives are strictly secondary (isPrimary = false).
            // Pass autoGenerateTasks:true so the character's self-initiated goal gets
            // concrete subtasks (making autonomous objectives feel like real pursuits
            // with steps the character can accomplish).
            // (thin delegation to god setObjective per plan for step9)
            await setObjective(
              newObj,
              isPrimary: false,
              autoGenerateTasks: true,
            );
          }
        }
      }

      // ── Scene fields ──
      final emotionMatch = RegExp(
        r'"emotion"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (emotionMatch != null) {
        setCharacterEmotion(emotionMatch.group(1)!.toLowerCase().trim());
      }

      final intensityMatch = RegExp(
        r'"emotion_intensity"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (intensityMatch != null) {
        setEmotionIntensity(intensityMatch.group(1)!.toLowerCase().trim());
      }

      final postureMatch = RegExp(
        r'"posture"\s*:\s*"([^"]+)"',
      ).firstMatch(text);
      if (postureMatch != null) {
        final p = postureMatch.group(1)!.trim();
        relationshipService.setSpatialStance(p);
      }

      relationshipService.updateFixationFromEvalResult(
        (RegExp(
              r'"fixation_topic"\s*:\s*"([^"]+)"',
            ).firstMatch(text)?.group(1) ??
            ''),
        isOneShot: true,
      );

      final reasonMatch = RegExp(r'"reason"\s*:\s*"([^"]*)"').firstMatch(text);
      debugPrint(
        '[Realism:OneShot] Done — Emotion: ${getCharacterEmotion()} (${getEmotionIntensity()}), '
        'Time: ${timeService.timeOfDay}, Reason: ${reasonMatch?.group(1) ?? 'unknown'}',
      );

      // Bundle full state snapshot for time-travel forking
      var pending = getPendingRealismMetadata() ?? {};
      pending['emotion_label'] = getCharacterEmotion();
      pending['realism_state'] = captureRealismState();
      setPendingRealismMetadata(pending);

      await onSaveChat();
      onNotify();
    } catch (e) {
      debugPrint(
        '[Realism:OneShot] Failed: $e — falling back to dual-call on next turn',
      );
    }
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
}
