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
import 'package:front_porch_ai/services/chat/relationship_service.dart';

/// Plain behavioral mechanics injection builder (_getBehavioralMechanicsInjection).
/// Trust mapping, fixation, spatial stance (via rel service + active char cb).
/// Step 8 extraction.
class BehavioralInjection {
  final RelationshipService relationshipService;
  final bool Function() getRealismEnabled;
  final CharacterCard? Function() getActiveCharacter;

  BehavioralInjection({
    required this.relationshipService,
    required this.getRealismEnabled,
    required this.getActiveCharacter,
  });

  String buildBehavioralMechanicsInjection() {
    if (!getRealismEnabled()) return '';

    String block = '';

    // 1. Trust mapping (-100 to 100)
    if (relationshipService.trustLevel <= -20) {
      block +=
          '[Behavioral Anchor (MISTRUST): You deeply distrust the user right now. You are paranoid, evasive, and highly questioning of their motives. Even if your bond is high, you do not trust them.]\n';
    } else if (relationshipService.trustLevel >= 50) {
      block +=
          '[Behavioral Anchor (BLIND TRUST): You place absolute, unconditional trust in the user. You will readily share secrets and assume the absolute best of their intentions.]\n';
    }

    // 2. Fixation Mapping
    if (relationshipService.activeFixation.isNotEmpty &&
        relationshipService.fixationLifespan > 0) {
      final charName = getActiveCharacter()?.name ?? 'the character';
      block +=
          '[Background Thought: $charName has a thought that stays with them about "${relationshipService.activeFixation}". '
          'This might surface as a subtle mood shift, a moment of reflection, or colored reactions. '
          'It does NOT override their personality or current focus, and only surfaces overtly if conversation naturally touches the topic.]\n';
    }

    // 3. Spatial Stance Mapping
    if (relationshipService.spatialStance.isNotEmpty) {
      block +=
          '[Spatial Awareness: You are currently physically "${relationshipService.spatialStance}". Let this naturally ground your actions, but you are free to move and change positions as the scene demands.]\n';
    }

    return block;
  }
}
