// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

/// Turn order strategies for group chats.
enum TurnOrder {
  /// Characters respond in fixed order after each user message.
  roundRobin,

  /// A random character is picked to respond after each user message.
  random,
}

/// A lightweight wrapper representing a multi-character conversation.
class GroupChat {
  final String id;
  String name;
  List<String> characterIds; // references into CharacterRepository
  TurnOrder turnOrder;
  bool autoAdvance; // auto-trigger next character after one responds
  bool directorMode; // start in director mode when entering this group
  String firstMessage; // custom group greeting (empty = use first character's)
  String
  scenario; // group-level scenario override (empty = use first character's)
  String
  systemPrompt; // group-level system prompt override (empty = use global)

  GroupChat({
    required this.id,
    required this.name,
    required this.characterIds,
    this.turnOrder = TurnOrder.roundRobin,
    this.autoAdvance = false,
    this.directorMode = false,
    this.firstMessage = '',
    this.scenario = '',
    this.systemPrompt = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'character_ids': characterIds,
      'turn_order': turnOrder.name,
      'auto_advance': autoAdvance,
      'director_mode': directorMode,
      'first_message': firstMessage,
      'scenario': scenario,
      'system_prompt': systemPrompt,
    };
  }

  factory GroupChat.fromJson(Map<String, dynamic> json) {
    return GroupChat(
      id: json['id'] ?? '',
      name: json['name'] ?? 'Group Chat',
      characterIds:
          (json['character_ids'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      turnOrder: TurnOrder.values.firstWhere(
        (e) => e.name == json['turn_order'],
        orElse: () => TurnOrder.roundRobin,
      ),
      autoAdvance: json['auto_advance'] ?? false,
      directorMode: json['director_mode'] ?? false,
      firstMessage: json['first_message'] ?? '',
      scenario: json['scenario'] ?? '',
      systemPrompt: json['system_prompt'] ?? '',
    );
  }
}
