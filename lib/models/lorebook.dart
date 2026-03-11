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

class LorebookEntry {
  String name; // Display name for the entry
  String key; // Keywords to trigger this entry (comma-separated)
  String content; // The actual lore content
  bool enabled;
  bool isTriggered; // Runtime state for UI indication
  bool constant; // Always active if true
  int stickyDepth; // How many messages it stays active
  int remainingDepth; // Runtime counter

  LorebookEntry({
    this.name = '',
    required this.key,
    required this.content,
    this.enabled = true,
    this.isTriggered = false,
    this.constant = false,
    this.stickyDepth = 1,
    this.remainingDepth = 0,
  });

  /// Display label: name if available, otherwise key, otherwise 'Unnamed Entry'
  String get displayName {
    if (name.isNotEmpty) return name;
    if (key.isNotEmpty) return key;
    return 'Unnamed Entry';
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'key': key,
      'keys': key.split(',').map((k) => k.trim()).where((k) => k.isNotEmpty).toList(),
      'content': content,
      'enabled': enabled,
      'constant': constant,
      'sticky_depth': stickyDepth,
    };
  }

  factory LorebookEntry.fromJson(Map<String, dynamic> json) {
    // Handle V2 'keys' (array) or V1 'key' (string)
    String keyStr = '';
    if (json['keys'] != null && json['keys'] is List && (json['keys'] as List).isNotEmpty) {
      keyStr = (json['keys'] as List).map((k) => k.toString()).join(', ');
    } else {
      keyStr = json['key']?.toString() ?? '';
    }

    return LorebookEntry(
      name: json['name']?.toString() ?? '',
      key: keyStr,
      content: json['content']?.toString() ?? '',
      enabled: json['enabled'] ?? true,
      constant: json['constant'] ?? false,
      stickyDepth: json['sticky_depth'] ?? json['insertion_order'] ?? 1,
    );
  }
}

class Lorebook {
  List<LorebookEntry> entries;

  Lorebook({required this.entries});

  Map<String, dynamic> toJson() {
    return {
      'entries': entries.map((e) => e.toJson()).toList(),
    };
  }

  factory Lorebook.fromJson(Map<String, dynamic> json) {
    var entriesList = json['entries'] as List?;
    List<LorebookEntry> entries = [];
    if (entriesList != null) {
      entries = entriesList.map((e) => LorebookEntry.fromJson(e)).toList();
    }
    return Lorebook(entries: entries);
  }
}
