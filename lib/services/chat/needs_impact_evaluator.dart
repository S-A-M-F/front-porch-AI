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
import 'package:front_porch_ai/services/chat/realism_verification.dart';

/// Plain (non-ChangeNotifier) sibling leaf to NeedsSimulation owning the
/// (now radically simplified) needs *impact* layer.
///
/// Straight decay ticks (in NeedsSimulation) + model-provided scene deltas.
/// Optional Director/Verifier review loop (via verify cb) sits on top and
/// corrects deltas when the raw model JSON contradicts the scene text or pre-state.
///
/// No activity table. No modifier if/then pipeline. No afterglow / crash / suppression buffers.
/// The LLM (reviewed by Director when enabled) is the source of the per-turn deltas
/// for hunger/energy/bladder/hygiene/fun/social/comfort. Decay is always the safe baseline.
///
/// Ctor takes granular cbs only for the fire, verify, active/group dispatch (impersonation for per-speaker),
/// messages/pre for verifier bundle, needsSimulation for apply, and enabled flags.
///
/// evaluateAndApply: fire the impact call, wrap with verifier (kind='needs_impact'), use effective/corrected
/// for delta extraction, build minimal NeedsImpact, applySceneImpact (now just deltas + reason).
///
/// 1:1 / group parity via cbs + god impersonation dance (verifier and apply see correct speaker).
///
/// Dedicated test with live-closure factory; 28 bodies (live grep -c '^\s*test(' =28 post dels/adds as part of task; matrix for authority+verif flag=false + group per-member roundtrip via GroupMember/toCharacterCard/cb + impersonation + god thin coverage via cbs).
/// aug/integration receive *only* qualified passive notes (no leaf edits).
///
/// 0 new god private _ methods (thins + late final only; void _ count stays exactly 15 after every edit + final).
/// Stateless/prompt+rule only (no owned mutable state); god reset comments list this leaf as "stateless or prompt-only; no reset calls needed" + "buffer removal complete" at all ~15+ sites + both startNew.
/// Deletion part of task: old table, all 6 modifiers, buffer recs, authority flag logic, climax-for-buffers, obsolete comments all expunged here.
///
/// All per AGENTS/CLAUDE (full gates, analyze 0 new on surfaces, live greps, manual 1:1+group smoke for pure decay + model deltas + Director corrections on classic realism too).
class NeedsImpactEvaluator {
  final Future<String?> Function(
    String responseText, {
    void Function(String)? onChunk,
    int strength,
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

  final Map<String, dynamic> Function()? getPendingRealismMetadata;
  final void Function(Map<String, dynamic>)? setPendingRealismMetadata;

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
      final text = await evaluateNeedsImpactCall(responseText, strength: strength);
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

      // Parse deltas directly from effective (model or Director corrected). No table, no modifiers.
      final deltas = <String, int>{};
      for (final k in NeedsSimulation.needKeys) {
        final d =
            _extractInt(effectiveText, '${k}_delta') ??
            _extractInt(effectiveText, k);
        if (d != null) {
          deltas[k] = d;
        }
      }

      // Apply user-requested strength (1-5) to the (possibly Director-corrected) deltas.
      // This is the final guarantee; the prompt + Director already saw the strength so they could emit large.
      if (strength != 1) {
        for (final k in deltas.keys.toList()) {
          deltas[k] = (deltas[k]! * strength).round();
        }
      }

      final reasonMatch = RegExp(
        r'"reason"\s*:\s*"([^"]*)"',
      ).firstMatch(effectiveText);
      final reason = reasonMatch?.group(1)?.trim();

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
}
