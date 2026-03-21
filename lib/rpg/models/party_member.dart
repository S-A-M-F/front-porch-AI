// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// RPG Engine — Party Member Model

class PartyMember {
  String name;
  String role;        // e.g. "Warrior", "Healer", "Guide"
  String description; // Short AI-generated blurb
  int? currentHp;
  int? maxHp;

  PartyMember({
    required this.name,
    required this.role,
    this.description = '',
    this.currentHp,
    this.maxHp,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'role': role,
    'description': description,
    'currentHp': currentHp,
    'maxHp': maxHp,
  };

  factory PartyMember.fromJson(Map<String, dynamic> json) => PartyMember(
    name: json['name'] as String? ?? 'Unknown',
    role: json['role'] as String? ?? 'Companion',
    description: json['description'] as String? ?? '',
    currentHp: json['currentHp'] as int?,
    maxHp: json['maxHp'] as int?,
  );
}
