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
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/models/needs_impact.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/realism_verification.dart';

/// Plain leaf for needs impact.
///
/// Model provides net signed deltas for the scene (open prompt, like bond/emotion evals).
/// Optional Director/Verifier corrects when authority is enabled on the card.
/// Simple clamps only. Decay is handled separately in NeedsSimulation.
class NeedsImpactEvaluator {
  final Future<String?> Function(
    String responseText, {
    void Function(String)? onChunk,
    int strength,
    String? userCritique,
    Map<String, int>? previousDeltas,
  })
  evaluateNeedsImpactCall;
  final Future<VerificationResult> Function({
    required String evalKind,
    required String rawOutput,
    required String sceneResponse,
    Map<String, dynamic>? preState,
    CharacterCard? activeChar,
    GroupChat? activeGroup,
    List<ChatMessage>? recentMessages,
    String? promptText,
    Map<String, String>? injections,
    int? strictnessOverride,
    int? maxPassesOverride,
  })?
  verifyRealismOutput;

  final Future<String?> Function(
    String prompt, {
    void Function(String)? onChunk,
  })?
  fireLLMEval;

  final Map<String, dynamic> Function()? getPendingRealismMetadata;
  final void Function(Map<String, dynamic>)? setPendingRealismMetadata;

  final void Function(int crashTurns)? onClimax;

  final CharacterCard? Function() getActiveCharacter;
  final GroupChat? Function() getActiveGroup;
  final bool Function() getIsObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final bool Function() getIsGroupNonObserverMode;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final void Function(String charId, Map<String, int> needs) setGroupNeeds;
  final List<CharacterCard> Function() getGroupCharacters;
  final String Function(CharacterCard) getCharacterIdFromCard;
  final List<ChatMessage> Function() getMessages;

  final NeedsSimulation needsSimulation;

  final bool Function() getNeedsSimEnabled;
  final bool Function() getRealismEnabled;
  final bool Function() getNeedsModelAuthorityEnabled;
  final int Function() getNeedsSimStrength;

  NeedsImpactEvaluator({
    required this.evaluateNeedsImpactCall,
    this.verifyRealismOutput,
    this.fireLLMEval,
    this.getPendingRealismMetadata,
    this.setPendingRealismMetadata,
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
    required this.getNeedsSimEnabled,
    required this.getRealismEnabled,
    required this.getNeedsModelAuthorityEnabled,
    this.getNeedsSimStrength = _defaultStrength,
    this.onClimax,
  });

  static int _defaultStrength() => 1;

  Future<void> evaluateAndApply(String responseText) async {
    if (!getNeedsSimEnabled() ||
        !getRealismEnabled() ||
        responseText.trim().isEmpty) {
      return;
    }
    final char = getActiveCharacter();
    if (char == null && getActiveGroup() == null) return;

    final strength = getNeedsSimStrength();
    try {
      final text = await evaluateNeedsImpactCall(
        responseText,
        strength: strength,
      );
      if (text == null) return;

      String effectiveText = text;
      final authority = getNeedsModelAuthorityEnabled();
      final cardVerifEnabled =
          getActiveCharacter()
              ?.frontPorchExtensions
              ?.realismVerificationEnabled ??
          false;
      if (verifyRealismOutput != null && authority && cardVerifEnabled) {
        // Director authority + card verif on: review loop corrections have authority on deltas (simple model + director; stronger critique changes applied via effective).
        // Skip verify cb entirely if card verif flag false (even under authority) to avoid unnecessary fire + metadata attempt (leaf would early-accept anyway).
        try {
          final vres = await verifyRealismOutput!(
            evalKind: 'needs_impact',
            rawOutput: text,
            sceneResponse: responseText,
            // Pass a needs snapshot shape consistent with what _captureRealismState
            // embeds in realism_state['needs'] (and what timeline/restore paths expect).
            // At this point in evaluateAndApply the sim.vector is still the pre-impact one.
            preState: {
              'needs': {'vector': needsSimulation.vector},
            },
            activeChar: getActiveCharacter(),
            activeGroup: getActiveGroup(),
            recentMessages: getMessages(),
            promptText:
                'needs impact (straight deltas; Director authority on corrections; user-requested strength ' +
                strength.toString() +
                'x — emit/correct deltas at this magnitude)',
            injections: const {},
          );
          if (vres.correctedRaw != null && vres.correctedRaw!.isNotEmpty) {
            effectiveText = vres.correctedRaw!;
          }
          if (vres.status.isNotEmpty) {
            final current =
                (getPendingRealismMetadata?.call() ?? <String, dynamic>{});
            current[RealismVerification.kMetaKey] = vres.toMetadata();
            setPendingRealismMetadata?.call(current);
            debugPrint(
              '[Realism:Verifier] Needs impact verified (authority) status=${vres.status} passes=${vres.passes}',
            );
          }
        } catch (e) {
          debugPrint('[Realism:Verifier] Needs wrap error (passthrough): $e');
          // Passthrough on error (consistent); no metadata for failure (chips fall back to model deltas).
        }
      }
      // else: straight model deltas (authority off, or verif card flag off, or no verify cb). No redundant else if.

      // Parse deltas directly from effective (model or Director corrected).
      // Robust JSON attempt first, then regex fallback.
      final deltas = <String, int>{};
      Map<String, dynamic> parsed = {};
      try {
        final noFence = effectiveText
            .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
            .trim();
        final si = noFence.indexOf('{');
        final ei = noFence.lastIndexOf('}');
        if (si >= 0 && ei > si) {
          final obj = jsonDecode(noFence.substring(si, ei + 1));
          if (obj is Map<String, dynamic>) parsed = obj;
        }
      } catch (_) {
        parsed = {};
      }
      for (final k in NeedsSimulation.needKeys) {
        int? d;
        if (parsed.isNotEmpty) {
          final v = parsed['${k}_delta'] ?? parsed[k];
          if (v is num) d = v.toInt();
        }
        d ??=
            _extractInt(effectiveText, '${k}_delta') ??
            _extractInt(effectiveText, k);
        if (d != null) {
          deltas[k] = d;
        }
      }

      // Simple clamps only (no complex gates/rules). Prevent obviously broken output from the model.
      // The Director (when authority + verification enabled) does the scene-faithfulness check,
      // just like bond/emotion/relationship evals. Strength scaling is already instructed in the prompt.
      //
      // Positive side loosened to +100 so a strong replenishing scene (meal, long rest, thorough
      // care/bathing, deep social connection) can meaningfully restore a need in one go.
      // Negative side kept at -30 to avoid any single scene catastrophically tanking a need.
      for (final k in deltas.keys.toList()) {
        deltas[k] = deltas[k]!.clamp(-30, 100);
      }

      // Strength (1-5x) is communicated to the model on the first needs-impact call and (when
      // Director authority is enabled) to the verifier critique so both emit/correct at the
      // user-requested magnitude in a single pass. We do NOT post-multiply here — that would
      // cause the Director to take an already-scaled delta (e.g. -15 at 5x) and multiply it
      // again (→ -75). The numbers that come back from the (Director-corrected) effective text
      // are the final deltas to apply. (See user clarification 2026-06: multiplier is applied
      // at first run / in the prompt to model+Director; Director must not re-scale the scaled value.)
      // If the model ignores the scale instruction the deltas will simply be smaller than desired
      // (model compliance issue, not a post-hoc multiplication).

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(effectiveText);
      final reason = reasonMatch?.group(1)?.trim();

      bool isClimax = false;
      int crashTurns = 5;
      if (parsed.isNotEmpty) {
        final c = parsed['is_climax'];
        if (c is bool) {
          isClimax = c;
        } else if (c is String) {
          isClimax = c.toLowerCase() == 'true';
        }

        final t = parsed['crashTurns'] ?? parsed['refractory_turns'];
        if (t is num) crashTurns = t.toInt();
      } else {
        final re = RegExp(r'"is_climax"\s*:\s*(true|false)');
        final m = re.firstMatch(effectiveText);
        if (m != null) isClimax = m.group(1) == 'true';
        crashTurns =
            _extractInt(effectiveText, 'crashTurns') ??
            _extractInt(effectiveText, 'refractory_turns') ??
            5;
      }

      if (isClimax) {
        onClimax?.call(crashTurns.clamp(1, 10));
      }

      final impact = NeedsImpact(
        deltas: deltas,
        reason: (reason != null && reason.toLowerCase() != 'none')
            ? reason
            : null,
      );

      needsSimulation.applySceneImpact(impact);
    } catch (e) {
      debugPrint('[Realism:Needs] evaluateAndApply error: $e');
    }
  }

  int? _extractInt(String text, String key) {
    final re = RegExp('"$key"\\s*:\\s*(-?\\d+)');
    final m = re.firstMatch(text);
    if (m != null) return int.tryParse(m.group(1)!);
    return null;
  }

  Future<bool> reprocessWithUserCritique(
    String responseText,
    Map<String, int> oldDeltas,
    String critique,
  ) async {
    // Use the injected evaluateNeedsImpactCall (now supports critique/oldDeltas for unified rich prompt + personality/stance/recent/full guidance + MUST + examples).
    final strength = getNeedsSimStrength();

    try {
      debugPrint(
        '[Realism:Needs] Running manual reprocess impact eval (via engine)...',
      );
      String? text = await evaluateNeedsImpactCall(
        responseText,
        strength: strength,
        userCritique: critique,
        previousDeltas: oldDeltas,
      );

      // C: bounded retry on empty/fragile (one extra attempt with emphasis)
      if (text == null || text.trim().isEmpty) {
        debugPrint(
          '[Realism:Needs] reprocess empty response, retrying once...',
        );
        text = await evaluateNeedsImpactCall(
          responseText,
          strength: strength,
          userCritique:
              '$critique Output ONLY the flat JSON now with all seven _delta keys.',
          previousDeltas: oldDeltas,
        );
      }

      if (text == null || text.trim().isEmpty) return false;

      String effectiveText = text; // already stripped by evaluate path

      final deltas = <String, int>{};
      Map<String, dynamic> parsed = {};
      try {
        final noFence = effectiveText
            .replaceAll(RegExp(r'```(?:json)?\s*|\s*```', dotAll: true), ' ')
            .trim();
        final si = noFence.indexOf('{');
        final ei = noFence.lastIndexOf('}');
        if (si >= 0 && ei > si) {
          final obj = jsonDecode(noFence.substring(si, ei + 1));
          if (obj is Map<String, dynamic>) parsed = obj;
        }
      } catch (_) {
        parsed = {};
      }
      for (final k in NeedsSimulation.needKeys) {
        int? d;
        if (parsed.isNotEmpty) {
          final v = parsed['${k}_delta'] ?? parsed[k];
          if (v is num) d = v.toInt();
        }
        d ??=
            _extractInt(effectiveText, '${k}_delta') ??
            _extractInt(effectiveText, k);
        if (d != null) {
          deltas[k] = d;
        }
      }

      // C: if after strip/parse we got literally no delta keys at all, treat as failure (do not apply empty "correction")
      if (deltas.isEmpty) {
        debugPrint(
          '[Realism:Needs] reprocess parsed no deltas; treating as failure',
        );
        return false;
      }

      for (final k in deltas.keys.toList()) {
        deltas[k] = deltas[k]!.clamp(-30, 100);
      }

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(effectiveText);
      final reason = reasonMatch?.group(1)?.trim();

      bool isClimax = false;
      int crashTurns = 5;
      if (parsed.isNotEmpty) {
        final c = parsed['is_climax'];
        if (c is bool) {
          isClimax = c;
        } else if (c is String) {
          isClimax = c.toLowerCase() == 'true';
        }
        final t = parsed['crashTurns'] ?? parsed['refractory_turns'];
        if (t is num) crashTurns = t.toInt();
      } else {
        final re = RegExp(r'"is_climax"\s*:\s*(true|false)');
        final m = re.firstMatch(effectiveText);
        if (m != null) isClimax = m.group(1) == 'true';
        crashTurns =
            _extractInt(effectiveText, 'crashTurns') ??
            _extractInt(effectiveText, 'refractory_turns') ??
            5;
      }

      if (isClimax) {
        onClimax?.call(crashTurns.clamp(1, 10));
      }

      final impact = NeedsImpact(
        deltas: deltas,
        reason: (reason != null && reason.toLowerCase() != 'none')
            ? reason
            : null,
      );

      needsSimulation.applySceneImpact(impact);

      // Store the metadata for the update
      final currentMeta =
          (getPendingRealismMetadata?.call() ?? <String, dynamic>{});
      // We manually construct a fake VerificationResult metadata to display the Director Corrected pill.
      currentMeta[RealismVerification.kMetaKey] = {
        'status': 'Director corrected (manual)',
        'passes': 1,
      };
      setPendingRealismMetadata?.call(currentMeta);

      return true;
    } catch (e) {
      debugPrint('[Realism:Needs] reprocessWithUserCritique error: $e');
      return false;
    }
  }
}
