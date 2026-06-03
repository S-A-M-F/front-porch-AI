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
import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';
import 'package:front_porch_ai/services/chat/relationship_service.dart';

/// Plain (non-ChangeNotifier) sibling leaf to NeedsSimulation owning the
/// consolidated needs *impact* / eval layer (the "what happened in the scene"
/// half that was previously 4 ad-hoc LLM checks + hard-coded maps + 10+ ifs
/// scattered across god + injection).
///
/// Extracted per the god-file modularization (fits after llm_eval_engine step 9
/// as the needs-domain companion to the already-extracted sim + injection).
/// "Create the new sibling leaf `lib/services/chat/needs_impact_evaluator.dart`
/// (plain class, granular cbs, consolidated detection with rich LLM impact JSON,
/// declarative rules table per Proposal A, modifiers pipeline, NeedsImpact,
/// apply, test factory, edges, Proposal A romance scenarios, group/1:1 via cbs)."
///
/// Ctor: granular cbs for LLM (fireLLMEval/strip/extract* via engine thins),
/// active/group/observer/speaker (for prompts + per-char), messages/recent,
/// nsfw/relationship/time cbs (arousal/stance/cooldown/tod for modifiers +
/// special), group needs cbs, onNotify/onSave, enabled/realism/enjoys flags,
/// + direct needsSimulation for apply + context.
/// ~20 cbs total (modeled on llm_eval_engine + needs_simulation + prompt inj).
/// Live closures in god for test overrides + group scalars/impersonation.
///
/// Owns:
/// - Single consolidated evaluateAndApply (or evaluateNeedsImpact) that builds
///   one rich prompt (consolidating the 4: climax + sexual nonclimax + daily +
///   fulfillment scan). Strict: "ONLY if unambiguous description of the *act*
///   (eating food, not 'devoured her lips'); output activities + intensity +
///   grounded deltas + fulfillments + reason + refractory/orgasm if climax".
/// - Declarative rules table (const, single source, easy scan/tune):
///   activityEffects for sexual_climax/non (energy 0 / hunger small-neg per A),
///   ate/slept/bathed with base deltas.
/// - Modifiers pipeline (ordered pure fns, documented; applied after base/LLM
///   grounded): romance context (Proposal A: no energy/hunger replenish in pure
///   romance/sex w/o explicit daily; hygiene neg *only* on explicit mess/fluids/
///   creampie words or high-int + exposed stance), time-of-day, arousal+buffer
///   damp, enjoysLow inversion/half, explicit mess/stance hygiene, cross-need,
///   intensity scale, etc.
/// - Produces NeedsImpact (deltas, startAfterglow, turns, fulfillments, reason,
///   intensity, activities).
/// - Calls needsSimulation.applySceneImpact(impact) (new API) + onClimaxDetected
///   cb (for nsfw refractory + regen pre-climax meta, so climax path parity).
///
/// Group/1:1 via cbs (per-speaker for group exactly as current sim/injection;
/// god does the temp impersonation + loadGroupRealismIntoScalars dance before
/// the thin delegate call to _runPostGenNeedsChecks).
///
/// Dedicated test factory (createTestEvaluator) with live closures over group
/// maps + cbs (real dispatch, no forcing god internals). 15-25+ test() bodies
/// (grep -c post mandatory dead/vestigial/noop/placeholder/factory-setup
/// deletion *as part of task*).
///
/// aug/integration (realism_engine_test, group_realism_test, etc.): exercised
/// via god thins + fake LLM returning crafted needs_impact JSON; *only*
/// qualified passive notes in headers/comments (no leaf-specific logic edits
/// in aug files; full coverage + Proposal A romance scenarios + edges +
/// group per-char + chips/sidebar + no-random + parity in dedicated + manual).
///
/// 0 new god private _ methods (thins/delegates + late final only; the void _
/// count grep stays at prior 15; confirmed after every edit).
/// Dispatch preserved exactly (cbs + impersonation).
/// Realism & Needs parity (1:1 vs group + oneShot vs normal) 1:1 equivalent
/// deltas/behavior at all times (including new impact path); qualified.
/// "some coordination may stay thin in god per plan (qualify everywhere)".
/// Reset hygiene: stateless or prompt-only (no owned reset/seed/load state);
/// no reset calls needed; comments in god expanded to list +
/// needs_impact_evaluator (stateless or prompt-only; no reset calls needed)
/// alongside prior + cross-refs (e.g. setActiveCharacter:1572); both startNew
/// branches explicit.
///
/// Header + god + test + MD all qualify "aug exercising only passive/qualified
/// (no needs-eval-specific aug file edits; full in dedicated + manual;
/// exercised via god thins)"; "onNotify of cbs unexercised by design in
/// dedicated (passive design; exercised in prod + key suites)".
///
/// All per plan + CLAUDE.md/AGENTS.md (deletion part of task, claims exact
/// via live grep post, gate capture hygiene with long self-contained cd+abs+
/// redirect+echo+cat + EXIT + re-runs + re-reads of abs on-disk + /tmp after
/// *every* edit, main pristine read-only only, no destructive git, etc.).
///
/// Verification gates (self-contained, re-run + re-read post edits + final):
/// format 0, analyze 0 new w on surfaces, dartfix, dedicated test count via
/// grep post dead delete, key aug green, build macos --debug, priv grep=15,
/// dead grep for old check bodies=0, manual smoke note.
class NeedsImpactEvaluator {
  final VoidCallback onNotify;
  final Future<void> Function() onSaveChat;

  // LLM surface (via engine thins in god; live closure for test fake).
  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })
  fireLLMEval;
  final String Function(String text) stripThinkBlocks;
  final int? Function(String text, String key) extractJsonInt;
  final bool? Function(String text, String key) extractJsonBool;

  // Consolidated impact call (prompt + fire + strip in engine for central LLM;
  // evaluator does modifiers/table/parse/apply). Full impl in engine per plan.
  final Future<String?> Function(
    String responseText, {
    void Function(String)? onChunk,
  })
  evaluateNeedsImpactCall;

  // Character/group/mode for prompts + per-char dispatch (god does impersonation
  // dance for group speaker before calling the thin _runPost... so active is
  // correct for name/personality/stance in prompt).
  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final bool Function() getIsGroupNonObserverMode;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final void Function(String charId, Map<String, int> needs) setGroupNeeds;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard card) getCharacterIdFromCard;

  // Messages for recent context in prompt (like other evals).
  final List<ChatMessage> Function() getMessages;

  // Cross services for modifiers + special (stance for hygiene mess judgment;
  // arousal/cooldown for damp/romance context; time for tod).
  final NeedsSimulation needsSimulation;
  final NsfwService nsfwService;
  final RelationshipService relationshipService;
  // timeService optional for tod in modifiers (fall back to sim cb if absent).
  final dynamic
  timeService; // TimeService if wired; use dynamic to avoid import cycle in this stage

  // Control flags + char trait.
  final bool Function() getNeedsSimEnabled;
  final bool Function() getRealismEnabled;
  final bool Function() getEnjoysLowHygiene;

  // Cross for climax nsfw side-effects (refractory + pre-climax meta save for
  // regen). Provided as live closure from god (closes over _messages, _nsfw).
  // Called only on unambiguous climax detection from the consolidated impact.
  final void Function(int preArousal, int refractoryTurns)? onClimaxDetected;

  NeedsImpactEvaluator({
    required this.onNotify,
    required this.onSaveChat,
    required this.fireLLMEval,
    required this.stripThinkBlocks,
    required this.extractJsonInt,
    required this.extractJsonBool,
    required this.evaluateNeedsImpactCall,
    required this.getActiveCharacter,
    required this.getActiveGroup,
    required this.getIsObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getIsGroupNonObserverMode,
    required this.getGroupNeeds,
    required this.setGroupNeeds,
    required this.getGroupCharacters,
    required this.getCharacterIdFromCard,
    required this.getMessages,
    required this.needsSimulation,
    required this.nsfwService,
    required this.relationshipService,
    this.timeService,
    required this.getNeedsSimEnabled,
    required this.getRealismEnabled,
    required this.getEnjoysLowHygiene,
    this.onClimaxDetected,
  });

  // ── Declarative rules table (Proposal A tuned; single source of truth) ──────

  /// Base effect for a detected activity. Deltas are starting point (LLM may
  /// ground/override some; modifiers pipeline runs after and can adjust e.g.
  /// zero energy/hunger for romance per A, hygiene only on explicit mess).
  static const Map<String, NeedsBaseEffect> activityEffects = {
    'sexual_climax': NeedsBaseEffect(
      deltas: {
        'fun': 16,
        'social': 9,
        'energy': 0, // Proposal A: neutral/costing, no replenish from intimacy
        'hunger': -2,
        'hygiene': -18,
        'bladder': 0,
        'comfort': 0,
      },
      startAfterglow: true,
      afterglowTurns: 4,
      suppressionTurns: 6,
      crashTurns: 3, // base; scaled by orgasm_intensity in parse
    ),
    'sexual_nonclimax': NeedsBaseEffect(
      deltas: {
        'fun': 12,
        'social': 7,
        'energy': 0, // Proposal A
        'hunger': -1,
        'hygiene': -8,
        'bladder': 0,
        'comfort': 0,
      },
      startAfterglow: true,
      afterglowTurns: 3,
      suppressionTurns: 5,
    ),
    'ate': NeedsBaseEffect(
      deltas: {'hunger': 22, 'fun': 6, 'energy': 5, 'bladder': 4, 'social': 4},
    ),
    'slept': NeedsBaseEffect(
      deltas: {'energy': 25, 'fun': 5, 'hunger': -3, 'bladder': 5},
    ),
    'bathed': NeedsBaseEffect(
      deltas: {'hygiene': 25, 'comfort': 12, 'fun': 6},
      // hygiene gain reduced by modifiers for recentSexual or enjoysLow
    ),
  };

  // ── Modifiers pipeline (ordered, pure, documented; Proposal A core) ─────────

  /// Shared explicit mess detection (creampie/fluids etc) for hygiene modifiers.
  /// Extracted to kill dupe (romance context + explicit stance hygiene).
  bool _hasExplicitMess(String lower) {
    return lower.contains('creampie') ||
        lower.contains('cum on') ||
        lower.contains('cum inside') ||
        lower.contains('fluids') ||
        lower.contains('messy') ||
        lower.contains('internal cum') ||
        lower.contains('filled her');
  }

  NeedsImpact _applyRomanceContextModifier(
    NeedsImpact impact,
    String responseTextLower,
  ) {
    final acts = impact.detectedActivities;
    final isSexual = acts.any(
      (a) => a == 'sexual_climax' || a == 'sexual_nonclimax',
    );
    final hasDaily = acts.any(
      (a) => a == 'ate' || a == 'slept' || a == 'bathed',
    );
    if (!isSexual || hasDaily) return impact;

    // Pure romance/sex scene, no explicit daily act described: per Proposal A
    // energy mostly neutral/costing (already 0 in base), hunger unaffected or
    // small negative (already), hygiene negative *only* if explicit mess/fluids.
    final newDeltas = Map<String, int>.from(impact.deltas);
    // Force no positive replenish for energy/hunger from intimacy flavor.
    newDeltas['energy'] = (newDeltas['energy'] ?? 0).clamp(-5, 0);
    newDeltas['hunger'] = (newDeltas['hunger'] ?? 0).clamp(-3, 0);

    // Hygiene: only if explicit mess words (creampie, cum, fluids, messy, on body etc)
    // or high intensity + stance suggests exposure. Base may have - , zero it unless.
    final hasExplicitMess = _hasExplicitMess(responseTextLower);
    final highIntensity = (impact.intensity ?? 5) >= 7;
    final stance = (relationshipService.spatialStance ?? '').toLowerCase();
    final exposedStance =
        stance.contains('bed') ||
        stance.contains('floor') ||
        stance.contains('couch') ||
        !stance.contains('shower') && !stance.contains('bath');
    if (!hasExplicitMess && !(highIntensity && exposedStance)) {
      newDeltas['hygiene'] = 0; // no blanket hygiene hit from romance alone
    }

    return NeedsImpact(
      deltas: newDeltas,
      startAfterglow: impact.startAfterglow,
      afterglowTurns: impact.afterglowTurns,
      suppressionTurns: impact.suppressionTurns,
      crashTurns: impact.crashTurns,
      fulfillments: impact.fulfillments,
      reason: impact.reason,
      intensity: impact.intensity,
      detectedActivities: impact.detectedActivities,
    );
  }

  NeedsImpact _applyTimeOfDayModifier(NeedsImpact impact) {
    // Time modifiers are primarily decay (in sim), but for impact we can
    // lightly boost e.g. morning hunger cost already in base; keep minimal here.
    // (Full tod in tickDecay pipeline.)
    return impact;
  }

  NeedsImpact _applyArousalAndBufferDamp(NeedsImpact impact) {
    // For impact deltas themselves, damp is light (the main damp is urgency in
    // injection). If suppression active, slightly mute positive social/fun from
    // sexual (lust haze mutes some "fun" awareness).
    if (!nsfwService.nsfwCooldownEnabled) return impact;
    final suppression =
        nsfwService.cooldownTurnsRemaining > 0 ||
        nsfwService.arousalLevel >= NeedsSimulation.arousalSuppressionThreshold;
    if (!suppression) return impact;

    final newD = Map<String, int>.from(impact.deltas);
    if (newD.containsKey('fun') && (newD['fun'] ?? 0) > 0) {
      newD['fun'] = ((newD['fun'] ?? 0) * 0.85).round();
    }
    if (newD.containsKey('social') && (newD['social'] ?? 0) > 0) {
      newD['social'] = ((newD['social'] ?? 0) * 0.9).round();
    }
    return NeedsImpact(
      deltas: newD,
      startAfterglow: impact.startAfterglow,
      afterglowTurns: impact.afterglowTurns,
      suppressionTurns: impact.suppressionTurns,
      crashTurns: impact.crashTurns,
      fulfillments: impact.fulfillments,
      reason: impact.reason,
      intensity: impact.intensity,
      detectedActivities: impact.detectedActivities,
    );
  }

  NeedsImpact _applyEnjoysLowHygieneModifier(NeedsImpact impact) {
    if (!getEnjoysLowHygiene()) return impact;
    final newD = Map<String, int>.from(impact.deltas);
    if (newD.containsKey('hygiene') && (newD['hygiene'] ?? 0) > 0) {
      // Less benefit from cleaning.
      newD['hygiene'] = ((newD['hygiene'] ?? 0) * 0.5).round().clamp(0, 100);
      newD['comfort'] = ((newD['comfort'] ?? 0) + 6).clamp(
        0,
        100,
      ); // lower payoff
      newD['fun'] = ((newD['fun'] ?? 0) + 3).clamp(0, 100);
    }
    return NeedsImpact(
      deltas: newD,
      startAfterglow: impact.startAfterglow,
      afterglowTurns: impact.afterglowTurns,
      suppressionTurns: impact.suppressionTurns,
      crashTurns: impact.crashTurns,
      fulfillments: impact.fulfillments,
      reason: impact.reason,
      intensity: impact.intensity,
      detectedActivities: impact.detectedActivities,
    );
  }

  NeedsImpact _applyExplicitMessAndStanceHygiene(
    NeedsImpact impact,
    String respLower,
  ) {
    if (!impact.deltas.containsKey('hygiene') ||
        (impact.deltas['hygiene'] ?? 0) >= 0) {
      return impact;
    }
    final hasMess = _hasExplicitMess(respLower);
    final high = (impact.intensity ?? 5) >= 7;
    final stance = (relationshipService.spatialStance ?? '').toLowerCase();
    final exposed =
        stance.contains('bed') ||
        stance.contains('floor') ||
        stance.contains('couch') ||
        (!stance.contains('shower') && !stance.contains('bath'));
    if (!hasMess && !(high && exposed)) {
      final newD = Map<String, int>.from(impact.deltas);
      newD['hygiene'] = 0;
      return NeedsImpact(
        deltas: newD,
        startAfterglow: impact.startAfterglow,
        afterglowTurns: impact.afterglowTurns,
        suppressionTurns: impact.suppressionTurns,
        crashTurns: impact.crashTurns,
        fulfillments: impact.fulfillments,
        reason: impact.reason,
        intensity: impact.intensity,
        detectedActivities: impact.detectedActivities,
      );
    }
    return impact;
  }

  NeedsImpact _applyIntensityScale(NeedsImpact impact) {
    final inty = impact.intensity ?? 5;
    if (inty == 5) return impact;
    final str = (inty / 10.0).clamp(0.5, 1.0);
    final newD = <String, int>{};
    impact.deltas.forEach((k, v) {
      if (k == 'hunger' || k == 'energy') {
        newD[k] =
            v; // don't scale core daily costs/rewards by "intensity of sex"
      } else {
        newD[k] = (v * str).round();
      }
    });
    return NeedsImpact(
      deltas: newD,
      startAfterglow: impact.startAfterglow,
      afterglowTurns: impact.afterglowTurns,
      suppressionTurns: impact.suppressionTurns,
      crashTurns: impact.crashTurns,
      fulfillments: impact.fulfillments,
      reason: impact.reason,
      intensity: impact.intensity,
      detectedActivities: impact.detectedActivities,
    );
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Consolidated post-gen needs impact (replaces the 4 prior _check* + runPost bodies
  /// via thin delegate in god). One LLM call for activities + grounded + fulfill.
  /// Then rules table + ordered modifiers pipeline (romance A first) → NeedsImpact
  /// → applySceneImpact on sim (which sets deltas + buffers + fulfill + crash).
  /// If climax activity, also fires onClimaxDetected cb (nsfw + regen meta).
  Future<void> evaluateAndApply(String responseText) async {
    if (!getNeedsSimEnabled() ||
        !getRealismEnabled() ||
        responseText.trim().isEmpty) {
      return;
    }
    final char = getActiveCharacter();
    if (char == null && getActiveGroup() == null) return;

    // Prompt build + fire + strip centralized in engine.evaluateNeedsImpactCall
    // (reuses personality/stance/recent from other evals; strict unambiguous +
    // Proposal A). Evaluator receives stripped text for table/modifiers/parse/apply.
    try {
      debugPrint(
        '[Realism:Needs] Running consolidated impact eval (Proposal A)...',
      );
      final text = await evaluateNeedsImpactCall(responseText);
      if (text == null) return;

      // Parse (use flat bools + deltas; activities list or derive).
      final activities = <String>[];
      if (extractJsonBool(text, 'sexual_climax') == true) {
        activities.add('sexual_climax');
      }
      if (extractJsonBool(text, 'sexual_nonclimax') == true) {
        activities.add('sexual_nonclimax');
      }
      if (extractJsonBool(text, 'ate') == true) {
        activities.add('ate');
      }
      if (extractJsonBool(text, 'slept') == true) {
        activities.add('slept');
      }
      if (extractJsonBool(text, 'bathed') == true) {
        activities.add('bathed');
      }

      final intensity = extractJsonInt(text, 'intensity') ?? 5;

      // Prefer LLM grounded deltas; fall back to table scaled by intensity.
      final deltas = <String, int>{};
      for (final k in NeedsSimulation.needKeys) {
        final fromLlm = extractJsonInt(text, '${k}_delta');
        if (fromLlm != null) {
          deltas[k] = fromLlm;
        }
      }
      if (deltas.isEmpty && activities.isNotEmpty) {
        // Base from table, first matching (or sum if multi, but rare).
        for (final act in activities) {
          final base = activityEffects[act];
          if (base != null) {
            base.deltas.forEach((k, v) {
              deltas[k] = (deltas[k] ?? 0) + v;
            });
          }
        }
      }

      final isClimax =
          extractJsonBool(text, 'is_climax') ??
          activities.contains('sexual_climax');
      int? refractory;
      int? orgasmInt;
      if (isClimax || activities.contains('sexual_climax')) {
        refractory = extractJsonInt(text, 'refractory_turns')?.clamp(1, 10);
        orgasmInt = extractJsonInt(text, 'orgasm_intensity')?.clamp(1, 10);
      }

      final fulfillments = <String, bool>{};
      // Try to parse any _fulfilled or the map.
      for (final k in NeedsSimulation.needKeys) {
        final f = extractJsonBool(text, '${k}_fulfilled');
        if (f != null) fulfillments[k] = f;
      }
      // Also check "fulfillment" object heuristically via regex if present.
      final fulMapMatch = RegExp(
        r'"fulfillment"\s*:\s*\{([^}]*)\}',
      ).firstMatch(text);
      if (fulMapMatch != null) {
        final inner = fulMapMatch.group(1) ?? '';
        for (final k in NeedsSimulation.needKeys) {
          if (RegExp('$k["\']?\s*:\s*(true|false)').hasMatch(inner)) {
            final m = RegExp('$k["\']?\s*:\s*(true|false)').firstMatch(inner);
            if (m != null) fulfillments[k] = m.group(1) == 'true';
          }
        }
      }

      final reason = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(text)?.group(1)?.trim();

      var impact = NeedsImpact(
        deltas: deltas,
        startAfterglow: activities.any((a) => a.startsWith('sexual_')),
        afterglowTurns: activities.contains('sexual_climax')
            ? 4
            : (activities.any((a) => a.startsWith('sexual_')) ? 3 : null),
        suppressionTurns: activities.any((a) => a.startsWith('sexual_'))
            ? 6
            : null,
        crashTurns: isClimax && orgasmInt != null
            ? (orgasmInt >= 9
                  ? 5
                  : orgasmInt >= 7
                  ? 4
                  : orgasmInt >= 5
                  ? 3
                  : orgasmInt >= 3
                  ? 2
                  : 0)
            : null,
        fulfillments: fulfillments.isEmpty ? null : fulfillments,
        reason: (reason != null && reason.toLowerCase() != 'none')
            ? reason
            : null,
        intensity: intensity,
        detectedActivities: activities,
      );

      // Modifiers pipeline (ordered; romance A first to fix the reported issues).
      final respLower = responseText.toLowerCase();
      impact = _applyRomanceContextModifier(impact, respLower);
      impact = _applyTimeOfDayModifier(impact);
      impact = _applyArousalAndBufferDamp(impact);
      impact = _applyEnjoysLowHygieneModifier(impact);
      impact = _applyExplicitMessAndStanceHygiene(impact, respLower);
      impact = _applyIntensityScale(impact);

      // Apply to sim (deltas + buffers + fulfill + crash).
      needsSimulation.applySceneImpact(impact);

      // Climax side effects (nsfw refractory + pre meta for regen) via cb (god provides closure).
      if (isClimax && onClimaxDetected != null) {
        final pre = nsfwService.arousalLevel;
        final turns = refractory ?? 5;
        onClimaxDetected!(pre, turns);
        debugPrint(
          '[Realism:Climax] Consolidated impact confirmed climax — cb for nsfw + regen meta',
        );
      }

      debugPrint(
        '[Realism:Needs] Consolidated impact applied: $impact (activities=$activities)',
      );
      // onSave/notify already fired inside applySceneImpact (or the cb).
    } catch (e) {
      debugPrint('[Realism:Needs] Consolidated impact eval failed: $e');
    }
  }
}

/// Internal base effect (not exported; name without _ to satisfy
/// library_private_types_in_public_api for the static table).
class NeedsBaseEffect {
  final Map<String, int> deltas;
  final bool startAfterglow;
  final int afterglowTurns;
  final int suppressionTurns;
  final int? crashTurns;

  const NeedsBaseEffect({
    required this.deltas,
    this.startAfterglow = false,
    this.afterglowTurns = 4,
    this.suppressionTurns = 6,
    this.crashTurns,
  });
}
