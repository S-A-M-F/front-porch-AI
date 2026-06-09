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

import 'package:front_porch_ai/database/database.dart' hide AvatarImage;
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';
import 'package:front_porch_ai/utils/emotion_labels.dart';

/// Per-eval delta limits for the realism LLM calls (relationship, emotional state,
/// one-shot). These are the authoritative ranges for what each eval is allowed to
/// contribute in a single turn. They are used both for .clamp() enforcement and
/// interpolated into the prompt guidance text so the model instructions and the
/// runtime guard cannot drift from each other (or between the multi-call paths and
/// the fused one-shot path).
const kMinRelationshipDelta = -15;
const kMaxRelationshipDelta = 15;
const kMinTrustDelta = -200;
const kMaxTrustDelta = 50;
const kMinArousalDelta = -25;
const kMaxArousalDelta = 25;

/// Plain (non-ChangeNotifier) leaf sibling to LlmEvalEngine owning the 5
/// realism evaluation calls (relationship, emotional state, physical state,
/// narrative, one-shot) + their prompt builders, orchestration, parse for
/// realism results (bond/trust deltas ± , emotion/inertia, arousal, fixation,
/// spatial stance, time, pending metadata for chips/reasons), and side effects
/// (apply on rel/nsfw, set scalars, updateFixation, setObjective thin cb for
/// autonomous, snapshot for oneShot).
///
/// Per extraction order table in docs/refactoring-guide.md (order 10 after
/// 9/9b llm_eval + needs_impact; depends on llm_eval_engine for fire/strip/extract
/// cbs; prompt builders for the 5 evals full in leaf or coordinated per precedent).
///
/// Extracted as step 10 of Stage 3 god-file modularization.
/// "the 5 realism evaluation calls: relationship, emotional state, physical state,
/// narrative, one-shot" as plain leaf sibling to llm_eval_engine.
///
/// ChatService owns via late final (after _llmEvalEngine) + thins/delegations at
/// *every* prior call site for the 5 _evaluate*Call (full excision of moved code
/// from engine + old thin bodies). Some coordination (setObjective thin for auto
/// proposal in narr/oneShot, physical posture delegate to timeService which
/// receives fire cbs) may stay thin/coordinated in god per precedent (qualify).
///
/// Ctor receives state via granular callbacks (modeled on steps 6-9b + needs_impact:
/// fireLLMEval/strip/extract* (via god thins over engine),
/// getActiveCharacter/getActiveGroup/getIsObserverMode (for guards + 1:1 vs group
/// dispatch via god's impersonation), getUserName, getRealismEnabled, getMessages,
/// get/setPendingRealismMetadata, captureRealismState, get/setCharacterEmotion,
/// get/setEmotionIntensity, relationshipService, nsfwService, timeService (for
/// physical + ctx in oneShot), getExpressionEnabled (for prompt label list),
/// getPrimaryObjective/getActiveObjectives/setObjective (for narr/oneShot proposed
/// objective under impersonation), getMessages for recent etc).
/// ~23+ granular cbs total (onSave/onNotify removed in fix round 1: god owns
/// post-eval save/notify after pre-turn evals to avoid double in oneShot paths
/// and races; leaf populates pending snapshot for god to persist). Live closures
/// in god for test overrides + group per-speaker impersonation/load scalars
/// without cycles; testable with small factory in dedicated test.
///
/// 1:1 vs group + oneShot vs normal parity 1:1 equivalent deltas/behavior at all
/// times (Realism Engine bond/trust ±300/±100 clamps, emotion, fixation, spatial,
/// time every-6, arousal; oneShot must match normal multi-call for the fields it
/// covers; Needs/Objectives parity via other paths but qualified here for any
/// overlap; dispatch preserved exactly via cbs + god impersonation dance +
/// loadGroupRealismIntoScalars before speaker evals). Qualified (preserved
/// exactly; exercised in dedicated + key suites + manual).
///
/// Dedicated test: test/services/chat/realism_evals_test.dart with factory
/// (createTestRealismEvals) using live closures over group maps + cbs (real
/// dispatch, no forcing god internals). 15-25+ test() bodies via live
/// `grep -c '^\s*test('` confirmed post mandatory dead noop/placeholder/vestigial/
/// factory-setup deletion *as part of task*. Coverage: public surface + roundtrips
/// + group vs 1:1 via cbs + edges (guards, !ready/cancel, empty, error, "none",
/// strip, impersonation/proposal parity, oneShot vs normal, Realism/Needs/Objectives
/// parity 1:1 equiv deltas, chips/sidebar/group per-char, no random, etc.).
///
/// aug/integration tests (realism_engine_test, group_realism_test, etc.): receive
/// *only* qualified passive notes in headers/comments (no realism-evals-specific
/// aug file logic edits; full coverage + edges + oneShot/normal + group per-char +
/// chips/sidebar + parity in dedicated + manual; "aug exercising only passive/qualified
/// (no realism-evals-specific aug file edits; full in dedicated realism_evals_test +
/// manual; exercised via god thins _evaluate*Call ; qualified notes only in dedicated
/// header + god + MD per precedent)".
///
/// 0 new god private _ methods (thins/delegates + late final only; the void _ count
/// grep stays at prior 15 confirmed after every edit + final; thins/calls/late final
/// + reset comment syncs only per plan).
/// Anti-accumulation: explicit dead code audit of affected in god (no new _Eval/
/// _Realism methods; old bodies excised).
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state; no
/// reset calls needed on this leaf); god comments expanded to list + realism_evals
/// (stateless or prompt-only; no reset calls needed) alongside prior + cross-refs
/// (e.g. setActiveCharacter:1572); both startNew branches explicit; "incomplete
/// zeroing of secondary config on group/0-session/new-chat now complete" language
/// includes this leaf.
///
/// Header + god + test + MD all qualify the aug note (onSave/onNotify cbs removed
/// in fix round 1 for oneShot double-save hygiene; unexercised by design from leaf
/// in dedicated — god owns post-eval save/notify; exercised in prod + key suites).
///
/// Barrel: not added (internal to ChatService only; per checklist "unless 3+
/// locations"; opportunistic when touching for other reason).
class RealismEvals {
  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireLLMEval;
  final String Function(String) stripThinkBlocks;
  final int? Function(String, String) extractJsonInt;
  final bool? Function(String, String) extractJsonBool;

  // Character / group / mode state (for guard + 1:1 vs group dispatch via impersonation)
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;

  // User / persona for eval prompts
  final String Function() getUserName;

  // Realism flag
  final bool Function() getRealismEnabled;

  // Messages for recent context in evals
  final List<ChatMessage> Function() getMessages;

  // Pending metadata + capture for realism state snapshot (oneShot + rel/emotion)
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

  // Expression enabled for the "MUST choose label from list" instruction in emotion prompts
  final bool Function() getExpressionEnabled;

  // Objective proposal (for narr/oneShot; thin cb to god per plan for coordination)
  final Objective? Function() getPrimaryObjective;
  final List<Objective> Function() getActiveObjectives;
  final Future<void> Function(
    String objectiveText, {
    bool isPrimary,
    bool autoGenerateTasks,
  })
  setObjective;

  RealismEvals({
    required this.fireLLMEval,
    required this.stripThinkBlocks,
    required this.extractJsonInt,
    required this.extractJsonBool,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getUserName,
    required this.getRealismEnabled,
    required this.getMessages,
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
    required this.getExpressionEnabled,
    required this.getPrimaryObjective,
    required this.getActiveObjectives,
    required this.setObjective,
  });

  /// Parses relationship/trust (+ best-effort or requested arousal) fields from
  /// an eval JSON text, applies the side effects (score/trust deltas to services,
  /// arousal to nsfwService), populates pending metadata for chips/reasons using
  /// only nonzero deltas (reasons are populated when present even if deltas are 0),
  /// and returns the resolved values for caller debug logging.
  ///
  /// This single implementation is used by both the separate relationship eval
  /// (multi-call) and the fused one-shot eval, guaranteeing identical clamp
  /// behavior and pending population for bond/trust/arousal.
  ({
    int bondDelta,
    int trustDelta,
    int arousalDelta,
    String bondReason,
    String trustReason,
  }) _parseAndApplyRelationshipDeltas(String text) {
    // Bond / relationship delta (per prompt range)
    final relDelta = extractJsonInt(text, 'relationship_delta');
    int bondDelta = 0;
    if (relDelta != null) {
      bondDelta = relDelta.clamp(kMinRelationshipDelta, kMaxRelationshipDelta);
      relationshipService.applyScoreDelta(bondDelta);
    }

    // Trust delta (user behavior only; per prompt range)
    int trustDelta = 0;
    final trDelta = extractJsonInt(text, 'trust_delta');
    if (trDelta != null) {
      trustDelta = trDelta.clamp(kMinTrustDelta, kMaxTrustDelta);
      if (trustDelta != 0) {
        relationshipService.applyTrustDelta(trustDelta);
      }
    }

    // Arousal (only when NSFW cooldowns are enabled; relationship path treats
    // as best-effort since its prompt does not request the field; emotional and
    // one-shot paths request it when enabled).
    int arousalDelta = 0;
    if (nsfwService.nsfwCooldownEnabled) {
      final arDelta = extractJsonInt(text, 'arousal_delta');
      if (arDelta != null) {
        arousalDelta = arDelta.clamp(kMinArousalDelta, kMaxArousalDelta);
        nsfwService.setArousalLevel(
          (nsfwService.arousalLevel + arousalDelta).clamp(-100, 100),
        );
      }
    }

    // Nonzero deltas → pending (for chips + message metadata). Only record
    // nonzero so UI and revert logic stay uncluttered (0s are the default).
    if (bondDelta != 0 || arousalDelta != 0 || trustDelta != 0) {
      var pending = getPendingRealismMetadata() ?? {};
      if (bondDelta != 0) pending['bond_delta'] = bondDelta;
      if (arousalDelta != 0) pending['arousal_delta'] = arousalDelta;
      if (trustDelta != 0) pending['trust_delta'] = trustDelta;
      setPendingRealismMetadata(pending);
    }

    // Reasons (for hover tooltips on chips). Always extract; set if present
    // and not the sentinel "none".
    final bondReasonMatch = RegExp(
      r'"bond_reason"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final rawBondReason = bondReasonMatch?.group(1)?.trim() ?? '';
    final bondReason =
        rawBondReason.toLowerCase() == 'none' ? '' : rawBondReason;
    if (bondReason.isNotEmpty) {
      var pending = getPendingRealismMetadata() ?? {};
      pending['bond_reason'] = bondReason;
      setPendingRealismMetadata(pending);
    }

    final trustReasonMatch = RegExp(
      r'"trust_reason"\s*:\s*"([^"]*)"',
    ).firstMatch(text);
    final rawTrustReason = trustReasonMatch?.group(1)?.trim() ?? '';
    final trustReason =
        rawTrustReason.toLowerCase() == 'none' ? '' : rawTrustReason;
    if (trustReason.isNotEmpty) {
      var pending = getPendingRealismMetadata() ?? {};
      pending['trust_reason'] = trustReason;
      setPendingRealismMetadata(pending);
    }

    return (
      bondDelta: bondDelta,
      trustDelta: trustDelta,
      arousalDelta: arousalDelta,
      bondReason: bondReason,
      trustReason: trustReason,
    );
  }

  // ── The 5 Realism Eval Calls (full bodies moved here from engine in step 10) ──

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
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (' "$kMinRelationshipDelta to +$kMaxRelationshipDelta" ')\n'
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
        '3. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (' "$kMinTrustDelta to +$kMaxTrustDelta" ')\n'
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

      // Unified parse/apply (also used by one-shot). The relationship path passes
      // arousal parsing through even though its prompt does not request the field
      // (best-effort extraction preserved exactly).
      final res = _parseAndApplyRelationshipDeltas(text);

      debugPrint(
        '[Realism:Relationship] Bond: ${res.bondDelta} (${res.bondReason.isNotEmpty ? res.bondReason : 'no reason'}) | Trust: ${res.trustDelta} (${res.trustReason.isNotEmpty ? res.trustReason : 'no reason'})',
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
        ? ", \"arousal_delta\": <number $kMinArousalDelta to +$kMaxArousalDelta>"
        : '';
    final arousalInstr = nsfwService.nsfwCooldownEnabled
        ? '3. "arousal_delta": Physical arousal shift this turn. (' "$kMinArousalDelta to +$kMaxArousalDelta" ')\n'
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

    final prompt =
        'You are a nuanced evaluator of $charName\'s emotional state in a roleplay.\n\n'
        '$personalityInjection'
        '$relationshipCtx'
        'Reactions are subjective! Evaluate emotion THROUGH $charName\'s specific personality.\n\n'
        '1. "emotion": $charName\'s overarching emotional state (one nuanced word).\n'
        '   NOT generic ("happy"/"sad") — find the specific texture: wistful not sad, flustered not happy, prickly not angry.\n'
        '   Filter through $charName\'s personality — a stoic character in deep pain shows "guarded", not "devastated".\n'
        '${getExpressionEnabled() ? '   ⚠ YOU MUST choose EXACTLY ONE of these labels: ${EmotionLabels.all.join(", ")}. No other words allowed.\n' : ''}'
        '2. "emotion_intensity": mild, moderate, or strong\n'
        '$arousalInstr'
        'Recent conversation:\n$recent\n\n'
        'Respond with ONLY a flat JSON object containing "emotion", "emotion_intensity"$arousalField.';

    try {
      debugPrint('[Realism] Evaluating emotional state...');
      final raw = await fireLLMEval(prompt, onChunk: onChunk);
      if (raw == null) return;

      final searchText = stripThinkBlocks(raw);
      final text = searchText.isNotEmpty ? searchText : raw;

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
          final arousalDelta = arDelta.clamp(kMinArousalDelta, kMaxArousalDelta);
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
        ? ", \"arousal_delta\": <number $kMinArousalDelta to +$kMaxArousalDelta>"
        : '';
    // Arousal is field 8 (after posture), objective is 9, fixation 10, reason 11
    final arousalInstr = nsfwService.nsfwCooldownEnabled
        ? '8. "arousal_delta": Physical arousal shift this turn. (' "$kMinArousalDelta to +$kMaxArousalDelta" ')\n'
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
        '1. "relationship_delta": How did this exchange shift $charName\'s warmth toward $userName? (' "$kMinRelationshipDelta to +$kMaxRelationshipDelta" ')\n'
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
        '2. "trust_delta": Did $userName — NOT $charName — do something that builds or destroys $charName\'s trust in $userName? (' "$kMinTrustDelta to +$kMaxTrustDelta" ')\n'
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

      // ── Relationship / trust / arousal (unified with multi-call path) ──
      _parseAndApplyRelationshipDeltas(text);

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

      // Bundle full state snapshot for time-travel forking (god will persist via
      // post-eval _saveChat + synthesize in the calling pre-gen / baseline paths;
      // removing the cb calls here eliminates double save/notify for oneShot vs
      // multi-call paths and the save-race window).
      var pending = getPendingRealismMetadata() ?? {};
      pending['emotion_label'] = getCharacterEmotion();
      pending['realism_state'] = captureRealismState();
      setPendingRealismMetadata(pending);
    } catch (e) {
      debugPrint(
        '[Realism:OneShot] Failed: $e — falling back to dual-call on next turn',
      );
    }
  }
}
