// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';

void main() {
  group('LorebookEntry', () {
    test('displayName returns name when available', () {
      final entry = LorebookEntry(name: 'My Entry', key: 'test', content: 'some content');
      expect(entry.displayName, 'My Entry');
    });

    test('displayName returns key when name is empty', () {
      final entry = LorebookEntry(name: '', key: 'test-key', content: 'some content');
      expect(entry.displayName, 'test-key');
    });

    test('displayName returns "Unnamed Entry" when both empty', () {
      final entry = LorebookEntry(name: '', key: '', content: 'some content');
      expect(entry.displayName, 'Unnamed Entry');
    });

    test('toJson includes all fields with proper keys', () {
      final entry = LorebookEntry(
        name: 'Test Entry',
        key: 'hello,hi',
        content: 'A greeting rule',
        enabled: true,
        constant: true,
        stickyDepth: 3,
      );
      final json = entry.toJson();
      expect(json['name'], 'Test Entry');
      expect(json['key'], 'hello,hi');
      expect(json['keys'], ['hello', 'hi']);
      expect(json['content'], 'A greeting rule');
      expect(json['enabled'], true);
      expect(json['constant'], true);
      expect(json['sticky_depth'], 3);
    });

    test('toJson trims and filters empty keys', () {
      final entry = LorebookEntry(key: 'hello, , world , ', content: 'some content');
      final json = entry.toJson();
      expect(json['keys'], ['hello', 'world']);
    });

    test('fromJson handles V2 keys array', () {
      final json = {
        'name': 'Greeting',
        'keys': ['hello', 'hi', 'hey'],
        'content': 'Say hello back',
        'enabled': true,
        'constant': false,
        'sticky_depth': 2,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, 'Greeting');
      expect(entry.key, 'hello, hi, hey');
      expect(entry.content, 'Say hello back');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 2);
    });

    test('fromJson handles V1 key string', () {
      final json = {
        'name': 'Old Entry',
        'key': 'trigger-word',
        'content': 'Content here',
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.key, 'trigger-word');
      expect(entry.name, 'Old Entry');
      expect(entry.content, 'Content here');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 1);
    });

    test('fromJson uses defaults for missing fields', () {
      final json = {'key': 'test', 'content': 'some content'};
      final entry = LorebookEntry.fromJson(json);
      expect(entry.name, '');
      expect(entry.enabled, true);
      expect(entry.constant, false);
      expect(entry.stickyDepth, 1);
    });

    test('fromJson handles insertion_order fallback for stickyDepth', () {
      final json = {
        'key': 'test',
        'content': 'content',
        'insertion_order': 5,
      };
      final entry = LorebookEntry.fromJson(json);
      expect(entry.stickyDepth, 5);
    });

    test('round-trip preserves data', () {
      final original = LorebookEntry(
        name: 'Round Trip Test',
        key: 'trigger1, trigger2',
        content: 'This content must survive round-trip',
        enabled: true,
        constant: true,
        stickyDepth: 4,
      );
      final json = original.toJson();
      final restored = LorebookEntry.fromJson(json);
      expect(restored.name, original.name);
      expect(restored.key, original.key);
      expect(restored.content, original.content);
      expect(restored.enabled, original.enabled);
      expect(restored.constant, original.constant);
      expect(restored.stickyDepth, original.stickyDepth);
    });
  });

  group('Lorebook', () {
    test('fromJson with entries', () {
      final json = {
        'entries': [
          {'key': 'hello', 'content': 'Greeting', 'name': 'Greet Rule'},
          {'key': 'goodbye', 'content': 'Farewell', 'name': 'Farewell Rule'},
        ],
      };
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries.length, 2);
      expect(lorebook.entries[0].key, 'hello');
      expect(lorebook.entries[1].key, 'goodbye');
    });

    test('fromJson with empty entries list', () {
      final json = {'entries': []};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('fromJson with missing entries', () {
      final json = <String, dynamic>{};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('fromJson with null entries', () {
      final json = {'entries': null};
      final lorebook = Lorebook.fromJson(json);
      expect(lorebook.entries, isEmpty);
    });

    test('toJson includes all entries', () {
      final lorebook = Lorebook(entries: [
        LorebookEntry(key: 'a', content: 'Content A'),
        LorebookEntry(key: 'b', content: 'Content B'),
      ]);
      final json = lorebook.toJson();
      expect(json['entries'], isA<List>());
      expect(json['entries'].length, 2);
    });

    test('toJson with empty entries', () {
      final lorebook = Lorebook(entries: []);
      final json = lorebook.toJson();
      expect(json['entries'], isEmpty);
    });

    test('round-trip preserves all entries', () {
      final original = Lorebook(entries: [
        LorebookEntry(name: 'Entry 1', key: 'trigger1', content: 'Content 1', constant: true),
        LorebookEntry(name: 'Entry 2', key: 'trigger2, trigger3', content: 'Content 2', stickyDepth: 3),
      ]);
      final json = original.toJson();
      final restored = Lorebook.fromJson(json);
      expect(restored.entries.length, 2);
      expect(restored.entries[0].name, 'Entry 1');
      expect(restored.entries[1].name, 'Entry 2');
      expect(restored.entries[1].key, 'trigger2, trigger3');
    });
  });
}
