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

class World {
  String name;
  String description;
  Lorebook lorebook;
  String? linkedCharacterName; // If set, this world was auto-created from a character import

  World({
    required this.name,
    this.description = '',
    required this.lorebook,
    this.linkedCharacterName,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'description': description,
      'lorebook': lorebook.toJson(),
      if (linkedCharacterName != null) 'linked_character_name': linkedCharacterName,
    };
  }

  factory World.fromJson(Map<String, dynamic> json) {
    return World(
      name: json['name'] ?? 'New World',
      description: json['description'] ?? '',
      lorebook: json['lorebook'] != null 
          ? Lorebook.fromJson(json['lorebook'])
          : Lorebook(entries: []),
      linkedCharacterName: json['linked_character_name'],
    );
  }
}
