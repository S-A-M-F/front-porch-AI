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

import 'package:front_porch_ai/models/lorebook.dart';

class CharacterCard {
  String name;
  String description;
  String personality;
  String scenario;
  String firstMessage;
  String mesExample;
  String systemPrompt;
  String postHistoryInstructions;
  List<String> alternateGreetings;
  List<String> tags;
  String? imagePath;
  String? folderId;
  Lorebook? lorebook;
  List<String> worldNames;
  String? ttsVoice; // Piper voice key for per-character TTS
  String? dbId; // UUID primary key (runtime only, not serialized)

  CharacterCard({
    required this.name,
    this.description = '',
    this.personality = '',
    this.scenario = '',
    this.firstMessage = '',
    this.mesExample = '',
    this.systemPrompt = '',
    this.postHistoryInstructions = '',
    this.alternateGreetings = const [],
    this.tags = const [],
    this.imagePath,
    this.folderId,
    this.lorebook,
    this.worldNames = const [],
    this.ttsVoice,
  });

  /// All greetings: primary first message + alternates
  List<String> get allGreetings {
    final greetings = <String>[firstMessage];
    greetings.addAll(alternateGreetings);
    return greetings.where((g) => g.isNotEmpty).toList();
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'personality': personality,
      'scenario': scenario,
      'first_mes': firstMessage,
      'mes_example': mesExample,
      'system_prompt': systemPrompt,
      'post_history_instructions': postHistoryInstructions,
      'alternate_greetings': alternateGreetings,
      'tags': tags,
      'character_book': lorebook?.toJson(),
      'world_names': worldNames,
      if (ttsVoice != null) 'tts_voice': ttsVoice,
    };
  }

  String replacePlaceholders(String text, {String userName = 'You'}) {
    return text
        .replaceAll(RegExp(r'\{\{char\}\}', caseSensitive: false), name)
        .replaceAll(RegExp(r'<char>', caseSensitive: false), name)
        .replaceAll(RegExp(r'\{\{user\}\}', caseSensitive: false), userName)
        .replaceAll(RegExp(r'<user>', caseSensitive: false), userName);
  }

  String get formattedDescription => replacePlaceholders(description);

  // V2 spec fields can be added here later (e.g., character_book, etc.)
}
