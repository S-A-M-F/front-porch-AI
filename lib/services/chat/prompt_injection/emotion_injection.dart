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

/// Plain (non-ChangeNotifier) prompt injection builder for the current
/// emotional state text (_getEmotionInjection).
///
/// Extracted step 8. Verbatim group (per-speaker from _groupRealism via god cbs)
/// + 1:1 (scalar _characterEmotion) branches.
///
/// ChatService owns late final + thin. 0 shims. 0 new god _ privates.
///
/// aug passive only (no prompt aug edits); full in dedicated.
class EmotionInjection {
  final bool Function() getRealismEnabled;
  final bool Function() getIsGroupNonObserverMode;
  final String Function() getCurrentSpeakerIdForRealism;
  final List<CharacterCard> Function() getGroupCharacters;
  final CharacterCard? Function() getActiveCharacter;
  final String Function() getCharacterEmotion;
  final String Function() getEmotionIntensity;
  final String Function(CharacterCard) getCharacterIdFromCard;

  EmotionInjection({
    required this.getRealismEnabled,
    required this.getIsGroupNonObserverMode,
    required this.getCurrentSpeakerIdForRealism,
    required this.getGroupCharacters,
    required this.getActiveCharacter,
    required this.getCharacterEmotion,
    required this.getEmotionIntensity,
    required this.getCharacterIdFromCard,
  });

  String buildEmotionInjection() {
    if (!getRealismEnabled()) return '';

    // In group mode (non-director), use the per-char state for the current speaker
    if (getIsGroupNonObserverMode()) {
      final speakerId = getCurrentSpeakerIdForRealism();
      // Note: in real god the per-char emotion is in _groupRealism[speakerId]['emotion']
      // For builder we use the god's load-into-scalars path; the cb getCharacterEmotion
      // will reflect the impersonated scalar after load (see god _loadGroupRealismIntoScalars).
      // For dedicated tests we simulate by providing a map-backed cb if needed.
      final emo = getCharacterEmotion();
      if (emo.isEmpty) return '';
      final intensity = getEmotionIntensity();
      final cap = emo.substring(0, 1).toUpperCase() + emo.substring(1);
      final name = getGroupCharacters()
          .firstWhere(
            (c) => getCharacterIdFromCard(c) == speakerId,
            orElse: () => getGroupCharacters().isNotEmpty
                ? getGroupCharacters().first
                : CharacterCard(name: 'the character'),
          )
          .name;
      return '[$name\'s Current Emotional State: $cap ($intensity)\n'
          ' This should subtly influence $name\'s tone, body language, and word choice.]\n';
    }

    // 1:1 path (or director groups)
    final emo = getCharacterEmotion();
    if (emo.isEmpty) return '';
    final charName = getActiveCharacter()?.name ?? 'the character';
    final cap = emo.substring(0, 1).toUpperCase() + emo.substring(1);
    final intensity = getEmotionIntensity();
    return '[$charName\'s Current Emotional State: $cap ($intensity)\n'
        ' This should subtly influence $charName\'s tone, body language, and word choice.]\n';
  }
}
