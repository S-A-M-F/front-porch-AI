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

import 'package:front_porch_ai/models/character_card.dart';

/// Portable interchange format for a group of characters exported as a single PNG.
///
/// This is the data model that gets serialized into the `fpa_group` PNG text chunk.
/// It is deliberately self-contained (full member CharacterCard objects, not ID references)
/// so that a single file can be shared and imported anywhere without requiring the
/// original character files.
///
/// This is a Front Porch innovation. SillyTavern has no equivalent single-file group
/// card format as of 2026 (see open issue #1757).
class GroupCard {
  final String name;
  final List<CharacterCard> members;

  /// Raw portable member data maps (full V2 shape as serialized by CharacterCard.toJson).
  /// This is what we use for high-fidelity import so that lorebooks, extensions,
  /// and all fields survive the roundtrip perfectly.
  final List<Map<String, dynamic>> rawMemberData;

  final String turnOrder; // 'roundRobin' or 'random'
  final bool autoAdvance;
  final bool directorMode;
  final String firstMessage;
  final String scenario;
  final String systemPrompt;

  /// Future extension point for group-level Front Porch features
  /// (e.g. shared realism defaults, group-wide needs simulation, etc.).
  final Map<String, dynamic>? extensions;

  GroupCard({
    required this.name,
    required this.members,
    List<Map<String, dynamic>>? rawMemberData,
    required this.turnOrder,
    this.autoAdvance = false,
    this.directorMode = false,
    this.firstMessage = '',
    this.scenario = '',
    this.systemPrompt = '',
    this.extensions,
  }) : rawMemberData = rawMemberData ?? members.map((c) => c.toJson()).toList();

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'members': members.map((c) => c.toJson()).toList(),
      'turn_order': turnOrder,
      'auto_advance': autoAdvance,
      'director_mode': directorMode,
      'first_message': firstMessage,
      'scenario': scenario,
      'system_prompt': systemPrompt,
      if (extensions != null && extensions!.isNotEmpty) 'extensions': extensions,
    };
  }

  factory GroupCard.fromJson(Map<String, dynamic> json) {
    final rawMembers = (json['members'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    // Reconstruct lightweight CharacterCard objects for any in-app display needs.
    // The rawMemberData is what we use for perfect-fidelity import.
    final members = rawMembers.map((m) {
      final data = m['data'] is Map ? Map<String, dynamic>.from(m['data']) : m;
      return CharacterCard(
        name: data['name'] ?? m['name'] ?? 'Unnamed',
        description: data['description'] ?? m['description'] ?? '',
        personality: data['personality'] ?? m['personality'] ?? '',
        scenario: data['scenario'] ?? m['scenario'] ?? '',
        firstMessage: data['first_mes'] ?? m['first_mes'] ?? '',
        mesExample: data['mes_example'] ?? m['mes_example'] ?? '',
        systemPrompt: data['system_prompt'] ?? m['system_prompt'] ?? '',
        postHistoryInstructions:
            data['post_history_instructions'] ?? m['post_history_instructions'] ?? '',
        alternateGreetings: (data['alternate_greetings'] ?? m['alternate_greetings'] ?? const <String>[]).cast<String>(),
        tags: (data['tags'] ?? m['tags'] ?? const <String>[]).cast<String>(),
        ttsVoice: data['tts_voice'] ?? m['tts_voice'],
        worldNames: (data['world_names'] ?? m['world_names'] ?? const <String>[]).cast<String>(),
      );
    }).toList();

    return GroupCard(
      name: json['name'] ?? 'Group',
      members: members,
      rawMemberData: rawMembers,
      turnOrder: json['turn_order'] ?? 'roundRobin',
      autoAdvance: json['auto_advance'] ?? false,
      directorMode: json['director_mode'] ?? false,
      firstMessage: json['first_message'] ?? '',
      scenario: json['scenario'] ?? '',
      systemPrompt: json['system_prompt'] ?? '',
      extensions: json['extensions'] is Map
          ? Map<String, dynamic>.from(json['extensions'])
          : null,
    );
  }
}
