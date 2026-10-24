// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Depth and Moment: the knobs the loops read, and the Dart gate on entry
// keys. New feature, so a file of its own.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

void main() {
  group('depth', () {
    test('full is the default and quick runs no review loops', () {
      expect(kWorldWikiDepthDefault, WorldWikiDepth.full);
      expect(WorldWikiDepthX.fromIndex(null), WorldWikiDepth.full);
      expect(WorldWikiDepthX.fromIndex(0), WorldWikiDepth.quick);
      expect(WorldWikiDepthX.fromIndex(2), WorldWikiDepth.deep);
      expect(WorldWikiDepthX.fromIndex(7), WorldWikiDepth.full);
      expect(WorldWikiDepth.quick.reviews, isFalse);
      expect(WorldWikiDepth.quick.fillRounds, 0);
      expect(WorldWikiDepth.quick.tries, 1);
      expect(WorldWikiDepth.full.reviews, isTrue);
      // Changed 2026-10-23: Full gets one rewrite per entry, not two. The
      // first Kimi loops run sent nearly every batch round three times and
      // ran past four hours without finishing; Deep keeps three tries.
      expect(WorldWikiDepth.full.tries, 2);
      expect(WorldWikiDepth.full.cardTarget, 60);
      expect(WorldWikiDepth.full.memberCards, isFalse);
      expect(WorldWikiDepth.quick.memberCards, isFalse);
      expect(WorldWikiDepth.deep.memberCards, isTrue);
    });

    test(
      'budgets grow with depth and the card target bounds the scout range',
      () {
        for (final d in WorldWikiDepth.values) {
          final (lo, hi) = d.scoutRange;
          expect(lo, lessThan(hi));
          expect(hi, lessThanOrEqualTo(d.cardTarget));
          expect(d.cardTarget, greaterThanOrEqualTo(kWorldScoutCardMax));
        }
        expect(
          WorldWikiDepth.quick.cardTarget,
          lessThan(WorldWikiDepth.full.cardTarget),
        );
        expect(
          WorldWikiDepth.full.cardTarget,
          lessThan(WorldWikiDepth.deep.cardTarget),
        );
        expect(
          WorldWikiDepth.deep.perPlaceMin,
          greaterThan(WorldWikiDepth.quick.perPlaceMin),
        );
        expect(
          WorldWikiDepth.deep.topPeople,
          greaterThan(WorldWikiDepth.full.topPeople),
        );
      },
    );
  });

  group('moment', () {
    test('no moment keeps the premise rule; a moment pins the tense', () {
      expect(worldMomentLine(''), '');
      expect(worldMomentLine(' the night after '), 'Moment: the night after\n');
      expect(worldMomentRule(''), contains("premise's time"));
      final rule = worldMomentRule('the night after the first invasion');
      expect(rule, contains('the night after the first invasion'));
      expect(rule, contains('unknown to everyone'));
    });
  });

  group('entry keys', () {
    test(
      "keys that are other entries' names and common words are dropped; the name leads",
      () {
        final keys = polishWorldKeys(
          'Soul Society',
          [
            'afterlife',
            'Seireitei',
            'Gotei 13',
            'Spirit World',
            'soul society',
            'East Branch',
          ],
          otherNamesLower: {'seireitei', 'gotei 13'},
        );
        expect(keys, ['Soul Society', 'Spirit World', 'East Branch']);
      },
    );

    test('a term of art survives: capitalized, hyphenated or multiword', () {
      final keys = polishWorldKeys('Auswählen', [
        'selection',
        'Still Silver',
        'Bankai',
        'Quincy-King',
        'linchpin',
        "Ichibe'e",
      ], otherNamesLower: {});
      expect(keys, [
        'Auswählen',
        'Still Silver',
        'Bankai',
        'Quincy-King',
        "Ichibe'e",
      ]);
    });

    test('at most eight keys, never none', () {
      final many = polishWorldKeys('Gotei 13', [
        for (var i = 0; i < 12; i++) 'Alias $i',
      ], otherNamesLower: {});
      expect(many, hasLength(kWorldLoreKeysMax));
      expect(many.first, 'Gotei 13');
      expect(polishWorldKeys('Lone', ['lone', 'word'], otherNamesLower: {}), [
        'Lone',
      ]);
    });

    test('the gate names a short entry', () {
      const draft = WorldCraftDraft(
        name: 'Rukongai',
        keys: ['Rukongai'],
        content: 'Too short.',
        role: WorldCraftRole.hub,
      );
      expect(worldEntryGate(draft).single, contains('two full sentences'));
      final fine = WorldCraftDraft(
        name: 'Rukongai',
        keys: const ['Rukongai'],
        content:
            'The districts ring the Seireitei in widening rings of want. ' * 4,
        role: WorldCraftRole.hub,
      );
      expect(worldEntryGate(fine), isEmpty);
    });

    test('drafts are polished against every name on the shelf', () {
      final out = polishWorldDrafts(
        const [
          WorldCraftDraft(
            name: 'Soul Society',
            keys: ['Soul Society', 'Seireitei'],
            content: 'x',
            role: WorldCraftRole.hub,
          ),
          WorldCraftDraft(
            name: 'Seireitei',
            keys: ['Court of Pure Souls', 'Soul Society'],
            content: 'y',
            role: WorldCraftRole.hub,
          ),
        ],
        allNames: ['Soul Society', 'Seireitei', 'Rukongai'],
      );
      expect(out[0].keys, ['Soul Society']);
      expect(out[1].keys, ['Seireitei', 'Court of Pure Souls']);
    });
  });

  group('scout parts', () {
    test('a scout is asked in parts of about forty cards', () {
      expect(WorldWikiDepth.quick.scoutParts, 1);
      expect(WorldWikiDepth.full.scoutParts, 2);
      expect(WorldWikiDepth.deep.scoutParts, 2);
    });
  });
}
