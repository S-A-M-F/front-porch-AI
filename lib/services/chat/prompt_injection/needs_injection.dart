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
/// Step 8. Now uses NeedsSimulation.getLowNeedsForInjection (shared selection of up to 2 lowest
/// at step <=4 / mild-or-worse) so early subtle hints are visible again and slow needs
/// (Comfort, Hygiene) are not completely silenced by faster decayers. Progressive stepped
/// text (mild → catastrophic) reaches the model earlier. Special bladder case preserved.
/// Delegates step/urgency calc to sim helpers.
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

      // Use shared selection (up to 2 lowest that are mild or worse). This lets slow
      // decayers like Comfort/Hygiene surface when they are #2, and revives step-4
      // subtle early hints for progressive awareness.
      final low = needsSimulation.getLowNeedsForInjection(needs);
      if (low.isEmpty) return '';

      final buf = StringBuffer();
      for (final item in low) {
        final step = item.effectiveStep; // for group we still use raw-ish via the helper
        final label = NeedsSimulation.needSteppedText[item.key]?[step.clamp(0, 4)] ?? item.key;
        buf.write(
            '[Background State for $name: $label (level ${item.value}) — this is a subtle physical or emotional condition that may gently influence her mood, thoughts, small behaviors, and focus this turn. Do not force her to directly comment on it unless it naturally fits the scene.]\n');
      }
      return buf.toString();
    }

    // 1:1 path
    final charName = getActiveCharacter()?.name ?? 'the character';

    if (needsSimulation.vector.isEmpty) return '';

    final sorted = needsSimulation.vector.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    final rawStepTop = needsSimulation.getNeedStep(sorted.first.key, sorted.first.value);

    // Preserve (and keep strong) the special erotic bladder + high-arousal tension case.
    // This one deliberately uses the *original* step so desperate holding while
    // extremely turned on can still create charged, kinky flavor even when other
    // needs are being softened by lust. (Kept as data here per plan.)
    if (sorted.first.key == 'bladder' &&
        nsfwService.nsfwCooldownEnabled &&
        nsfwService.arousalLevel >= 40 &&
        rawStepTop <= 2) {
      final tension = rawStepTop <= 1
          ? 'She is *desperately* holding on while extremely aroused — the combination is overwhelming and humiliating.'
          : 'The combination of bladder desperation and current arousal (level: ${nsfwService.arousalLevel}/10) creates a charged, uncomfortable tension.';
      return '[CRITICAL NEED — she cannot ignore this. $charName urgently needs to use the restroom. $tension]\n';
    }

    // Shared selection: up to the two lowest needs at mild (step 4) or worse.
    // This replaces the old "only the single worst + optional parenthetical" rule.
    // Mild step-4 descriptions are now emitted (progressive early hints the character
    // can act on before things become critical). Comfort and Hygiene can appear as #2.
    final lowNeeds = needsSimulation.getLowNeedsForInjection(needsSimulation.vector);
    if (lowNeeds.isEmpty) return '';

    final buf = StringBuffer();
    for (final item in lowNeeds) {
      // Delegate effective step + helpers (enjoys, urgency text, etc.)
      final eff = item.effectiveStep;
      if (eff >= 5) continue; // defensive

      final list = NeedsSimulation.needSteppedText[item.key] ?? const <String>[];
      final baseText = list.isNotEmpty ? list[eff.clamp(0, 4)] : item.key;

      final urgencyPrefix = needsSimulation.getUrgencyPrefixForStep(eff);
      // Secondary note kept for the (rare) case of 3+ low needs; it will mention one extra.
      final secondaryNote = needsSimulation.getSecondaryLowNeedNote(
        sorted,
        item.key,
        eff,
      );
      final postCrashSuffix = needsSimulation.getPostCrashSuffixIfRelevant(item.key);

      buf.write('[$urgencyPrefix $baseText$secondaryNote$postCrashSuffix]\n');
    }
    return buf.toString();
  }
}
