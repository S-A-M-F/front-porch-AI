// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/world_injection.dart';

void main() {
  test('skips worlds with injectDescription false or empty desc', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Dust.',
        lorebook: Lorebook(entries: []),
        injectDescription: false,
      ),
      World(
        name: 'Empty',
        description: '  ',
        lorebook: Lorebook(entries: []),
      ),
    ]);
    expect(text, isEmpty);
  });

  test('includes place prose when enabled', () {
    final text = buildWorldInjection([
      World(
        name: 'Mars',
        description: 'Red horizons and thin air.',
        lorebook: Lorebook(entries: []),
        injectDescription: true,
      ),
    ]);
    expect(text, contains('Mars'));
    expect(text, contains('Red horizons'));
    expect(text, startsWith('Setting'));
  });

  group('Location chain (slice 2)', () {
    World world(String name, {String? parent, required String description}) =>
        World(
          name: name,
          description: description,
          lorebook: Lorebook(entries: []),
          parentWorldId: parent,
          climateEnabled: false,
        );

    const header = 'Setting — where you are:\n';

    test(
      'leaf prose comes first; the parent fills what is left of the cap',
      () {
        final town = world('Bletchfield', description: 'Damp springs. ' * 60);
        final room = world(
          'Tea Rooms',
          parent: town.name,
          description: 'Steam on the windows, gossip on the saucers.',
        );
        // Order is chainFor's: leaf first. The caller builds it, not this
        // function — same contract the Primary-only rule already has.
        final text = buildWorldInjection([room, town]);
        final roomAt = text.indexOf('Steam on the windows');
        final townAt = text.indexOf('Bletchfield:');
        expect(roomAt, greaterThanOrEqualTo(0));
        expect(townAt, greaterThan(roomAt));
        expect(text.length, lessThanOrEqualTo(header.length + 600 + 1));
      },
    );

    test('a three-tier chain costs no more than the single-world cap', () {
      final town = world('Bletchfield', description: 'T' * 400);
      final house = world('Academy', parent: town.name, description: 'H' * 400);
      final room = world('Library', parent: house.name, description: 'R' * 400);
      final text = buildWorldInjection([room, house, town]);
      expect(text.length, lessThanOrEqualTo(header.length + 600 + 1));
      // The leaf is never cut: its full prose survives.
      expect(text.contains('R' * 400), isTrue);
      // The ancestor is truncated: all 400 chars of it do not fit.
      expect(text.contains('H' * 400), isFalse);
    });
  });
}
