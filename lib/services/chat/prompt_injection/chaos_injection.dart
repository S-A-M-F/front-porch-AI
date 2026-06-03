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
import 'package:front_porch_ai/services/chat/chaos_mode_service.dart';

/// Plain chaos / Chance Time injection builder (_getChanceTimeInjection).
/// Thin in god per plan; full event text + mark delivered here (step 8).
class ChaosInjection {
  final ChaosModeService chaosModeService;
  final CharacterCard? Function() getActiveCharacter;

  ChaosInjection({
    required this.chaosModeService,
    required this.getActiveCharacter,
  });

  String buildChanceTimeInjection() {
    // Delegation to extracted service for pending + delivered flag (builder here for step 8).
    if (chaosModeService.pendingChaosInjection == null ||
        chaosModeService.pendingChaosInjection!.isEmpty) {
      return '';
    }
    final charName = getActiveCharacter()?.name ?? 'the character';
    final event = chaosModeService.pendingChaosInjection!;
    // Mark as delivered via service so it can be cleared on the NEXT sendMessage.
    chaosModeService.markEventDelivered();
    return '\n[OOC — URGENT NARRATIVE INTERRUPT:\n'
        'THE FOLLOWING EVENT JUST HAPPENED RIGHT NOW, THIS VERY MOMENT, during the scene:\n'
        '>>> $event <<<\n\n'
        'MANDATORY: $charName MUST acknowledge and react to this event IN THEIR VERY FIRST PARAGRAPH.\n'
        'This is NOT optional. This is NOT background flavor. This event is happening RIGHT NOW and $charName witnesses/experiences it directly.\n'
        'Write $charName\'s immediate, visceral reaction to this event FIRST, then continue responding to the conversation naturally.\n'
        'Do NOT ignore this event. Do NOT save it for later. React NOW.\n'
        'Do NOT mention game mechanics, "Chance Time", or systems.]\n';
  }
}
