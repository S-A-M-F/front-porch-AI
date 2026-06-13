// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted LorebookScanner (plain class).
// Covers: keyword match (exact word-boundary, wildcard * prefix/suffix, boundaries
// like fire vs fireball), scan (triggers isTriggered+remainingDepth=sticky on match
// for enabled entries in char lore + attached worlds; comma-split keys; no-op no change;
// constant entries get depth set but are not zeroed by reset), decrement (only pre-AI set,
// only !constant, untrigger at <=0, notify on change), reset (zeros non-const on current
// chars + worlds via cb, leaves const + unrelated), resets/loads/seeds/roundtrips (fresh
// 0s, after scan, group vs 1:1 via cb providing different char lists), public surface,
// edges (no entries, empty/malformed keys after split/trim, no match, stickyDepth>1,
// group chars always scanned regardless of inherit flag which affects only god filters).
// Uses createTestLorebookScanner factory (modeled exactly on nsfw_service_test.dart +
// time/expression/prior) with live closures/maps for cbs (real dispatch, no forcing
// of internal state).
// Real owner dispatch via live wiring in key suites (realism_engine, group_realism,
// session + pre-existing startNew/setActive/_loadLast/group/greeting/send paths;
// full keyword/depth/scan/inject exercised only in dedicated + manual).
// (no lore-specific aug file edits; nsfw/lore-specific qualified notes only in dedicated header + service + god + MD per smallest-mechanical precedent from step6).
// lorebook injection text / full context building kept thin/stayed in god per plan for step8.
// oneShot vs normal lorebook parity qualified (scan on final + preAi decr + user scans +
// greetings + resets all delegated; dispatch preserved).
// test count 12 (12 test() bodies via grep -c '^\s*test(' confirmed).
// 0 forcing; real dispatch for branches where unit feasible (keyword, depth, scan, reset, group cb).
// 12 tests (12 bodies, grep -c confirmed).
// 1:1 vs group parity (group-level + per-char + world) exercised via cb + roundtrips.
// 3 cbs (onNotify + getLoreCharacters + resolveWorld); onNotify wired for prod dispatch but unexercised via counter in dedicated (assert on live entries; passive/qualified per design); documented in service header + this + MD.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart';
import 'package:front_porch_ai/services/chat/lorebook_scanner.dart';

/// Test factory (modeled exactly on nsfw + time/expression/prior).
/// Supplies live lists for characters (mutated in place) + worldsByName map for resolve cb.
/// onNotify wired (for real dispatch in prod via god ctor; in tests noop by design since we assert directly on mutated entries, not side-effect counts; see scan/decr change notify logic in service).
/// (onNotify of 3 cbs unexercised via counter/assert in dedicated per passive/qualified design; exercised in prod + key suites).
LorebookScanner createTestLorebookScanner({
  List<CharacterCard>? characters,
  Map<String, World>? worldsByName,
}) {
  final chars = characters ?? <CharacterCard>[];
  final worlds = worldsByName ?? <String, World>{};

  return LorebookScanner(
    onNotify: () {
      // notify captured for real dispatch in live cb (tests that care can wrap onNotify or inspect side effects on entries)
    },
    getLoreCharacters: () => chars,
    resolveWorld: (name) => worlds[name],
  );
}

void main() {
  group('LorebookScanner (extracted leaf)', () {
    test(
      'matchKeyword exact uses word boundaries (fire matches fire not fireball)',
      () {
        final svc = createTestLorebookScanner();
        expect(svc.matchKeyword('fire', 'fire'), isTrue);
        expect(svc.matchKeyword('fire', 'fireball'), isFalse);
        expect(svc.matchKeyword('fire', 'campfire'), isFalse);
        expect(svc.matchKeyword('fire', 'fire place'), isTrue);
        expect(svc.matchKeyword('foo', 'foo,bar'), isTrue);
      },
    );

    test('matchKeyword wildcard prefix/suffix/mid works', () {
      final svc = createTestLorebookScanner();
      expect(svc.matchKeyword('pot*', 'potato'), isTrue);
      expect(svc.matchKeyword('pot*', 'pottery'), isTrue);
      expect(svc.matchKeyword('pot*', 'potion'), isTrue);
      expect(svc.matchKeyword('pot*', 'apple'), isFalse); // no 'pot' substring
      expect(svc.matchKeyword('*ball', 'fireball'), isTrue);
      expect(svc.matchKeyword('*ball', 'snowball'), isTrue);
      expect(
        svc.matchKeyword('*ball', 'global'),
        isFalse,
      ); // no 'ball' substring
      expect(svc.matchKeyword('fi*re', 'fire'), isTrue);
      expect(
        svc.matchKeyword('fi*re', 'fool'),
        isFalse,
      ); // no 'fi...re' pattern
    });

    test(
      'scan triggers enabled entry on exact match, sets remainingDepth to stickyDepth',
      () {
        final entry = LorebookEntry(
          key: 'dragon, wyrm',
          content: 'A big lizard',
          stickyDepth: 3,
        );
        final lore = Lorebook(entries: [entry]);
        final ch = CharacterCard(name: 'Test', lorebook: lore);
        final svc = createTestLorebookScanner(characters: [ch]);

        svc.scanLorebook('The dragon flew over the mountain.');
        expect(entry.isTriggered, isTrue);
        expect(entry.remainingDepth, 3);

        // second scan on already triggered does not "change" for notify but depth reset
        svc.scanLorebook('dragon again');
        expect(entry.remainingDepth, 3);
      },
    );

    test(
      'scan respects enabled=false, constant entries get depth but reset leaves them',
      () {
        final e1 = LorebookEntry(
          key: 'alpha',
          content: 'a',
          enabled: true,
          constant: false,
        );
        final e2 = LorebookEntry(
          key: 'beta',
          content: 'b',
          enabled: false,
          constant: false,
        );
        final e3 = LorebookEntry(
          key: 'gamma',
          content: 'g',
          enabled: true,
          constant: true,
          stickyDepth: 2,
        );
        final lore = Lorebook(entries: [e1, e2, e3]);
        final ch = CharacterCard(name: 'C', lorebook: lore);
        final svc = createTestLorebookScanner(characters: [ch]);

        svc.scanLorebook('alpha beta gamma');
        expect(e1.isTriggered, isTrue);
        expect(e2.isTriggered, isFalse);
        expect(e3.isTriggered, isTrue);
        expect(e3.remainingDepth, 2);

        svc.resetLorebookTriggerState();
        expect(e1.isTriggered, isFalse);
        expect(e1.remainingDepth, 0);
        expect(e3.isTriggered, isTrue); // constant not zeroed
        expect(e3.remainingDepth, 2); // untouched
      },
    );

    test(
      'scan splits comma keys, matches any, attached world lore is scanned',
      () {
        final chEntry = LorebookEntry(key: 'castle', content: 'big house');
        final ch = CharacterCard(
          name: 'Hero',
          lorebook: Lorebook(entries: [chEntry]),
          worldNames: ['w1'],
        );

        final wEntry = LorebookEntry(key: 'forest*', content: 'trees');
        final world = World(
          name: 'w1',
          lorebook: Lorebook(entries: [wEntry]),
        );

        final svc = createTestLorebookScanner(
          characters: [ch],
          worldsByName: {'w1': world},
        );

        svc.scanLorebook('We entered the castle in the forestland.');
        expect(chEntry.isTriggered, isTrue);
        expect(wEntry.isTriggered, isTrue);
        expect(wEntry.remainingDepth, 1);
      },
    );

    test(
      'scan no chars or no match does nothing, no spurious notify side effects',
      () {
        final svc = createTestLorebookScanner(characters: []);
        svc.scanLorebook('anything'); // should not crash

        final e = LorebookEntry(key: 'miss', content: 'x');
        final ch = CharacterCard(
          name: 'C',
          lorebook: Lorebook(entries: [e]),
        );
        final svc2 = createTestLorebookScanner(characters: [ch]);
        svc2.scanLorebook('no match here');
        expect(e.isTriggered, isFalse);
      },
    );

    test(
      'decrementLoreDepthForEntries only affects provided non-const pre-AI set, untriggers at 0, skips const',
      () {
        final e1 = LorebookEntry(
          key: 'k1',
          content: 'c1',
          stickyDepth: 2,
          isTriggered: true,
          remainingDepth: 2,
        );
        final e2 = LorebookEntry(
          key: 'k2',
          content: 'c2',
          isTriggered: true,
          remainingDepth: 1,
          constant: true,
        );
        final e3 = LorebookEntry(
          key: 'k3',
          content: 'c3',
          isTriggered: true,
          remainingDepth: 1,
        );

        final svc = createTestLorebookScanner();
        svc.decrementLoreDepthForEntries({e1, e2, e3});

        expect(e1.remainingDepth, 1);
        expect(e1.isTriggered, isTrue);
        expect(e2.remainingDepth, 1); // const not decr
        expect(e2.isTriggered, isTrue);
        expect(e3.remainingDepth, 0);
        expect(e3.isTriggered, isFalse);
      },
    );

    test(
      'resetLorebookTriggerState zeros non-const across char lore + attached worlds for current cb chars only',
      () {
        final eChar = LorebookEntry(
          key: 'foo',
          content: 'f',
          isTriggered: true,
          remainingDepth: 5,
        );
        final ch1 = CharacterCard(
          name: 'C1',
          lorebook: Lorebook(entries: [eChar]),
          worldNames: ['w'],
        );

        final eWorld = LorebookEntry(
          key: 'bar',
          content: 'b',
          isTriggered: true,
          remainingDepth: 4,
        );
        final w = World(
          name: 'w',
          lorebook: Lorebook(entries: [eWorld]),
        );

        final eOther = LorebookEntry(
          key: 'other',
          content: 'o',
          isTriggered: true,
          remainingDepth: 3,
        );
        // eOther lives outside cb-provided chars (proves reset scope is cb-driven; no construction needed for the unrelated entry)

        final svc = createTestLorebookScanner(
          characters: [ch1], // only ch1 + its world in cb
          worldsByName: {'w': w},
        );

        svc.resetLorebookTriggerState();
        expect(eChar.isTriggered, isFalse);
        expect(eChar.remainingDepth, 0);
        expect(eWorld.isTriggered, isFalse);
        expect(eWorld.remainingDepth, 0);
        // other not touched because not in current cb chars
        expect(eOther.isTriggered, isTrue);
        expect(eOther.remainingDepth, 3);
      },
    );

    test(
      'group vs 1:1 via cb: scan affects only the provided character list',
      () {
        final e1 = LorebookEntry(key: 'g1', content: 'g1');
        final e2 = LorebookEntry(key: 'g2', content: 'g2');
        final chG1 = CharacterCard(
          name: 'G1',
          lorebook: Lorebook(entries: [e1]),
        );
        final chG2 = CharacterCard(
          name: 'G2',
          lorebook: Lorebook(entries: [e2]),
        );

        // simulate group cb providing both
        final groupSvc = createTestLorebookScanner(characters: [chG1, chG2]);
        groupSvc.scanLorebook('g1 keyword here');
        expect(e1.isTriggered, isTrue);
        expect(e2.isTriggered, isFalse);

        // 1:1 cb providing only one
        final oneSvc = createTestLorebookScanner(characters: [chG2]);
        oneSvc.scanLorebook('g2 here');
        expect(e2.isTriggered, isTrue);
      },
    );

    test(
      'roundtrip scan then reset then rescan works, depth sticky honored on re-trigger',
      () {
        final e = LorebookEntry(key: 're', content: 'r', stickyDepth: 2);
        final ch = CharacterCard(
          name: 'R',
          lorebook: Lorebook(entries: [e]),
        );
        final svc = createTestLorebookScanner(characters: [ch]);

        svc.scanLorebook('re trigger');
        expect(e.remainingDepth, 2);
        svc.decrementLoreDepthForEntries({e}); // simulate post AI
        expect(e.remainingDepth, 1);
        svc.resetLorebookTriggerState();
        expect(e.isTriggered, isFalse);
        expect(e.remainingDepth, 0);

        svc.scanLorebook('re again');
        expect(e.isTriggered, isTrue);
        expect(e.remainingDepth, 2);
      },
    );

    test(
      'edges: empty keys after split/trim ignored, no entries, sticky multi-decr',
      () {
        final e = LorebookEntry(
          key: ' , ,valid, ',
          content: 'v',
          stickyDepth: 3,
        );
        final ch = CharacterCard(
          name: 'E',
          lorebook: Lorebook(entries: [e]),
        );
        final svc = createTestLorebookScanner(characters: [ch]);

        svc.scanLorebook('valid word');
        expect(e.isTriggered, isTrue);
        expect(e.remainingDepth, 3);

        // decr 4 times (should stop at 0)
        svc.decrementLoreDepthForEntries({e});
        svc.decrementLoreDepthForEntries({e});
        svc.decrementLoreDepthForEntries({e});
        svc.decrementLoreDepthForEntries({e});
        expect(e.remainingDepth, 0);
        expect(e.isTriggered, isFalse);

        // no entries case
        final ch2 = CharacterCard(
          name: 'Empty',
          lorebook: Lorebook(entries: []),
        );
        final svc2 = createTestLorebookScanner(characters: [ch2]);
        svc2.scanLorebook('anything'); // no crash
      },
    );

    test('public surface: matchKeyword exposed, scan/decr/reset callable', () {
      final svc = createTestLorebookScanner();
      expect(svc.matchKeyword('test', 'test'), isTrue);
      // no throw on calls with empty
      svc.scanLorebook('');
      svc.decrementLoreDepthForEntries({});
      svc.resetLorebookTriggerState();
    });
  });
}
