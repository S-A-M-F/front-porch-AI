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
/// Step 8.
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
    final step = needsSimulation.getNeedStep(top.key, top.value);

    // Hygiene inversion support ("Enjoys low hygiene")
    int effectiveStep = step;
    if (getEnjoysLowHygiene() && top.key == 'hygiene') {
      // Invert the perceived urgency: low hygiene = "comfortable/good" for these characters
      effectiveStep = (5 - step).clamp(0, 5);
    }

    // Only inject when the need is noticeable or worse.
    // Mild needs (step 4) no longer force injection — reduces wack-a-mole behavior.
    if (step >= 4) return '';

    // Catastrophe (step 0) is never suppressed — the disaster must be narrated.
    final bool suppressionActive =
        needsSimulation.arousalSuppressionTurnsRemaining > 0 ||
        (nsfwService.arousalLevel >=
                NeedsSimulation.arousalSuppressionThreshold &&
            (needsSimulation.afterglowTurnsRemaining > 0 ||
                nsfwService.cooldownTurnsRemaining > 0));

    // Preserve (and keep strong) the special erotic bladder + high-arousal tension case.
    // This one deliberately uses the *original* step so desperate holding while
    // extremely turned on can still create charged, kinky flavor even when other
    // needs are being softened by lust.
    if (top.key == 'bladder' &&
        nsfwService.nsfwCooldownEnabled &&
        nsfwService.arousalLevel >= 40 &&
        step <= 2) {
      final tension = step <= 1
          ? 'She is *desperately* holding on while extremely aroused — the combination is overwhelming and humiliating.'
          : 'The combination of bladder desperation and current arousal (level: ${nsfwService.arousalLevel}/10) creates a charged, uncomfortable tension.';
      return '[CRITICAL NEED — she cannot ignore this. $charName urgently needs to use the restroom. $tension]\n';
    }

    // Apply arousal suppression (lust haze) on top of any hygiene inversion
    if (suppressionActive && step >= 1 && step <= 3) {
      // Dampen urgency by 1-2 steps when the character is deep in a lust haze.
      // Stronger effect at very high arousal (tier 6+ or raw >= 60).
      final int dampen = (nsfwService.arousalLevel >= 60) ? 2 : 1;
      effectiveStep = (effectiveStep + dampen).clamp(0, 5);
    }

    // If suppression pushed this need into "comfortable" territory for the LLM,
    // skip injecting it this turn (it will still decay normally in the background).
    if (effectiveStep >= 5) return '';

    // Get the graduated text for this *effective* step (so suppressed needs read milder)
    final texts = NeedsSimulation.needSteppedText[top.key] ?? const <String>[];
    final baseText = effectiveStep < texts.length
        ? texts[effectiveStep]
        : texts.last;

    // Build a more immersive prefix that escalates with severity
    final urgencyPrefix = switch (effectiveStep) {
      0 =>
        'CATASTROPHIC — this has already happened and must be roleplayed immediately.',
      1 => 'CRITICAL — she is in real, urgent distress from this need.',
      2 =>
        'Strong need — this is heavily weighing on her and affecting her focus.',
      3 =>
        'Noticeable need — this is a clear background pressure on her mood and attention.',
      _ => 'Mild background sensation — this is subtly coloring her state.',
    };

    // Secondary low need note (only for effective steps 1-3 to avoid noise at catastrophe)
    String secondaryNote = '';
    if (effectiveStep >= 1 && effectiveStep <= 3) {
      final secondary = sorted
          .where(
            (e) =>
                e.key != top.key &&
                needsSimulation.getNeedStep(e.key, e.value) <= 3,
          )
          .firstOrNull;
      if (secondary != null) {
        secondaryNote = ' (She is also feeling the ${secondary.key} need.)';
      }
    }

    // Optional explicit "post-sex crash" flavor when energy surfaces during the active crash phase
    // (afterglow + haze have expired). Keeps the erotic "sated exhaustion" feeling.
    final String postCrashSuffix =
        (needsSimulation.postClimaxCrashTurnsRemaining > 0 &&
            needsSimulation.afterglowTurnsRemaining == 0 &&
            needsSimulation.arousalSuppressionTurnsRemaining == 0 &&
            (top.key == 'energy' || top.key == 'fun'))
        ? ' (This heavy, sated exhaustion has the warm, post-orgasm quality — limbs like lead, deep drowsiness after intense release.)'
        : '';

    return '[$urgencyPrefix $baseText$secondaryNote$postCrashSuffix]\n';
  }
}
