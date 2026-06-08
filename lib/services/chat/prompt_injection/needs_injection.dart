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

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/needs_simulation.dart';
import 'package:front_porch_ai/services/chat/nsfw_service.dart';

/// Plain needs injection builder (_getNeedsInjection).
/// Per-char in group via cbs, 1:1 scalar, suppression, erotic special case, secondary note, post-crash.
/// Step 8. Simplified post needs impact rework: hard calc (effective step after enjoys/damp,
/// urgency prefix, secondary note, post-crash suffix, romantic context) delegated to
/// NeedsSimulation context helpers (getInjectionEffectiveStep etc); keeps only dispatch,
/// the erotic bladder tension text as data, and formatting. Exact prior behavior +
/// Proposal A milder notes via romantic context if used.
class NeedsInjection {
  final NeedsSimulation needsSimulation;
  final NsfwService nsfwService;
  final bool Function() getNeedsSimEnabled;
  final bool Function() getRealismEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final CharacterCard? Function() getActiveCharacter;
  final bool Function() getEnjoysLowHygiene;
  final Map<String, int> Function(String charId) getGroupNeeds;
  final String Function(CharacterCard) getCharacterIdFromCard;

  NeedsInjection({
    required this.needsSimulation,
    required this.nsfwService,
    required this.getNeedsSimEnabled,
    required this.getRealismEnabled,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getActiveCharacter,
    required this.getEnjoysLowHygiene,
    required this.getGroupNeeds,
    required this.getCharacterIdFromCard,
  });

  String buildNeedsInjection() {
    if (!getNeedsSimEnabled() || !getRealismEnabled()) return '';

    // Group mode (non-director) — per-character needs
    if (getIsGroupNonObserverMode()) {
      final id = getCurrentSpeakerIdForRealism();
      final needs = getGroupNeeds(id);
      if (needs.isEmpty) return '';

      final name = getGroupCharacters()
          .firstWhere(
            (c) => getCharacterIdFromCard(c) == id,
            orElse: () => getGroupCharacters().isNotEmpty
                ? getGroupCharacters().first
                : CharacterCard(name: 'the character'),
          )
          .name;

      final sorted = needs.entries.toList()
        ..sort((a, b) => a.value.compareTo(b.value));
      final top = sorted.first;
      final step = needsSimulation.getNeedStep(top.key, top.value);

      // Only inject when the need is noticeable or worse (step 3 or lower).
      // This prevents mild needs (e.g. 62% hunger) from constantly interrupting roleplay.
      if (step >= 4) return '';

      final label = NeedsSimulation.needSteppedText[top.key]?[step] ?? top.key;

      return '[Background State for $name: $label (level ${top.value}) — this is a subtle physical or emotional condition that may gently influence her mood, thoughts, small behaviors, and focus this turn. Do not force her to directly comment on it unless it naturally fits the scene.]\n';
    }

    // 1:1 path
    final charName = getActiveCharacter()?.name ?? 'the character';

    if (needsSimulation.vector.isEmpty) return '';

    final sorted = needsSimulation.vector.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final top = sorted.first;
    final rawStep = needsSimulation.getNeedStep(top.key, top.value);

    // Only inject when the need is noticeable or worse.
    // Mild needs (step 4) no longer force injection — reduces wack-a-mole behavior.
    if (rawStep >= 4) return '';

    // Preserve (and keep strong) the special erotic bladder + high-arousal tension case.
    // This one deliberately uses the *original* step so desperate holding while
    // extremely turned on can still create charged, kinky flavor even when other
    // needs are being softened by lust. (Kept as data here per plan.)
    if (top.key == 'bladder' &&
        nsfwService.nsfwCooldownEnabled &&
        nsfwService.arousalLevel >= 40 &&
        rawStep <= 2) {
      final tension = rawStep <= 1
          ? 'She is *desperately* holding on while extremely aroused — the combination is overwhelming and humiliating.'
          : 'The combination of bladder desperation and current arousal (level: ${nsfwService.arousalLevel}/10) creates a charged, uncomfortable tension.';
      return '[CRITICAL NEED — she cannot ignore this. $charName urgently needs to use the restroom. $tension]\n';
    }

    // Delegate effective step (enjoys inversion + suppression damp) + prefix/secondary/postcrash
    // to sim helpers (kills prior 10+ ifs for calc in this file).
    final effectiveStep = needsSimulation.getInjectionEffectiveStep(
      top.key,
      top.value,
    );

    if (effectiveStep >= 5) return '';

    final baseText =
        (NeedsSimulation.needSteppedText[top.key] ??
        const <String>[])[effectiveStep.clamp(0, 4)];

    final urgencyPrefix = needsSimulation.getUrgencyPrefixForStep(
      effectiveStep,
    );
    final secondaryNote = needsSimulation.getSecondaryLowNeedNote(
      sorted,
      top.key,
      effectiveStep,
    );
    final postCrashSuffix = needsSimulation.getPostCrashSuffixIfRelevant(
      top.key,
    );

    return '[$urgencyPrefix $baseText$secondaryNote$postCrashSuffix]\n';
  }
}
