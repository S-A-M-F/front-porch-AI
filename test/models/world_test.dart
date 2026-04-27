// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('World', () {
    test('requires name and lorebook', () {
      final world = World(
        name: 'Test World',
        lorebook: Lorebook(entries: []),
      );
      expect(world.name, 'Test World');
      expect(world.lorebook, isNotNull);
    });

    test('toJson includes all fields', () {
      final world = World(
        name: 'Fantasy Realm',
        description: 'A magical world',
        lorebook: Lorebook(entries: [
          LorebookEntry(key: 'magic', content: 'Magic exists here'),
        ]),
        linkedCharacterName: 'Wizard',
        avatarPath: '/path/to/avatar.png',
      );
      final json = world.toJson();
      expect(json['name'], 'Fantasy Realm');
      expect(json['description'], 'A magical world');
      expect(json['lorebook'], isNotNull);
      expect(json['linked_character_name'], 'Wizard');
      expect(json['avatar_path'], '/path/to/avatar.png');
    });

    test('toJson omits null fields', () {
      final world = World(
        name: 'Test World',
        lorebook: Lorebook(entries: []),
      );
      final json = world.toJson();
      expect(json.containsKey('linked_character_name'), false);
      expect(json.containsKey('avatar_path'), false);
    });

    test('fromJson with full data', () {
      final json = {
        'name': 'Dragon Lands',
        'description': 'Land of dragons',
        'lorebook': {
          'entries': [
            {'key': 'dragon', 'content': 'Dragons breathe fire'},
          ],
        },
        'linked_character_name': 'Dragon Master',
        'avatar_path': '/avatars/dragon.png',
      };
      final world = World.fromJson(json);
      expect(world.name, 'Dragon Lands');
      expect(world.description, 'Land of dragons');
      expect(world.lorebook.entries.length, 1);
      expect(world.linkedCharacterName, 'Dragon Master');
      expect(world.avatarPath, '/avatars/dragon.png');
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {
        'name': 'Minimal World',
        'lorebook': {'entries': []},
      };
      final world = World.fromJson(json);
      expect(world.name, 'Minimal World');
      expect(world.description, '');
      expect(world.linkedCharacterName, isNull);
      expect(world.avatarPath, isNull);
    });

    test('fromJson with missing lorebook creates empty lorebook', () {
      final json = {'name': 'No Lorebook World'};
      final world = World.fromJson(json);
      expect(world.name, 'No Lorebook World');
      expect(world.lorebook.entries, isEmpty);
    });

    test('fromJson with null lorebook creates empty lorebook', () {
      final json = {
        'name': 'Null Lorebook World',
        'lorebook': null,
      };
      final world = World.fromJson(json);
      expect(world.name, 'Null Lorebook World');
      expect(world.lorebook.entries, isEmpty);
    });

    test('round-trip preserves all data', () {
      final original = World(
        name: 'Round Trip World',
        description: 'A world that survives serialization',
        lorebook: Lorebook(entries: [
          LorebookEntry(name: 'Entry 1', key: 'a', content: 'Content A'),
          LorebookEntry(name: 'Entry 2', key: 'b', content: 'Content B', constant: true),
        ]),
        linkedCharacterName: 'Hero',
        avatarPath: '/avatars/hero.png',
      );
      final json = original.toJson();
      final restored = World.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.description, original.description);
      expect(restored.lorebook.entries.length, 2);
      expect(restored.linkedCharacterName, original.linkedCharacterName);
      expect(restored.avatarPath, original.avatarPath);
    });
  });
}
