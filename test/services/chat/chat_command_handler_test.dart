// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for ChatCommandHandler (Scene Guests / Lite NPC slash-command leaf).
// The handler is pure dispatch/parsing over injected closures, so the whole
// surface is unit-coverable: non-commands fall through, expression set/clear
// dispatch, unknown commands fall through, /create parsing + mint wiring
// (success + failure + guards), and /exit selection (named, partial, omitted,
// missing, no-guests) with departure arming + primary-turn trigger.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/chat_command_handler.dart';

CharacterCard _guest(String name) => CharacterCard(
  name: name,
  frontPorchExtensions: FrontPorchExtensions(tier: 'lite'),
);

void main() {
  group('ChatCommandHandler', () {
    late List<CharacterCard> guests;
    late List<String> systemMessages;
    late List<String?> expressionCalls;
    late List<(String, String)> createCalls;
    late List<CharacterCard> exited;
    late List<CharacterCard> joinable;
    late List<CharacterCard> joined;
    late List<CharacterCard> spoke;
    late List<String> pickerRequests;
    late String? pendingDeparture;
    late int primaryTurns;
    late int castScans;
    bool castScanFound = false;

    ChatCommandHandler build({bool activeSet = true}) {
      return ChatCommandHandler(
        setExpression: expressionCalls.add,
        activeCharacterIsSet: () => activeSet,
        getSceneGuestCards: () => guests,
        setPendingGuestDeparture: (n) => pendingDeparture = n,
        onSystemMessage: systemMessages.add,
        generatePrimaryTurn: () async => primaryTurns++,
        createGuest: (name, concept) async => createCalls.add((name, concept)),
        exitGuest: (g) async => exited.add(g),
        getJoinableCharacters: () => joinable,
        joinGuest: (g) async => joined.add(g),
        requestGuestPicker: pickerRequests.add,
        runCastScan: () async {
          castScans++;
          return castScanFound;
        },
        speakGuest: (g) async => spoke.add(g),
      );
    }

    setUp(() {
      guests = [];
      systemMessages = [];
      expressionCalls = [];
      createCalls = [];
      exited = [];
      joinable = [];
      joined = [];
      spoke = [];
      pickerRequests = [];
      pendingDeparture = null;
      primaryTurns = 0;
      castScans = 0;
      castScanFound = false;
    });

    test('non-command input is not handled', () async {
      expect(await build().handle('hello there'), false);
    });

    test('unknown command falls through (not handled)', () async {
      expect(await build().handle('/wobble foo'), false);
    });

    test(
      '/expression sets a manual label, /expression-clear clears it',
      () async {
        final h = build();
        expect(await h.handle('/expression happy'), true);
        expect(await h.handle('/expression'), true); // empty args -> clear
        expect(await h.handle('/expression-clear'), true);
        expect(expressionCalls, ['happy', null, null]);
      },
    );

    test('/create outside a 1:1 chat is rejected before creating', () async {
      final h = build(activeSet: false);
      expect(await h.handle('/create Bob: a baker'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(createCalls, isEmpty);
    });

    test('/create with empty args shows usage', () async {
      final h = build();
      expect(await h.handle('/create'), true);
      expect(systemMessages.last, contains('Usage'));
      expect(createCalls, isEmpty);
    });

    test('/create splits name/concept on ":" and delegates', () async {
      final h = build();
      expect(await h.handle('/create Bob: a cheerful baker'), true);
      expect(createCalls.single, ('Bob', 'a cheerful baker'));
    });

    test('/create splits name/concept on "|"', () async {
      final h = build();
      await h.handle('/create Mara | a stoic guard');
      expect(createCalls.single, ('Mara', 'a stoic guard'));
    });

    test('/create with name only yields empty concept', () async {
      final h = build();
      await h.handle('/create Solo');
      expect(createCalls.single, ('Solo', ''));
    });

    test('/exit with no guests surfaces a message and is handled', () async {
      final h = build();
      expect(await h.handle('/exit'), true);
      expect(systemMessages.single, contains('no scene guests'));
      expect(exited, isEmpty);
      expect(primaryTurns, 0);
    });

    test('/exit (no name) removes the last guest and arms departure', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/exit'), true);
      expect(exited.single.name, 'Bram'); // most-recent guest
      expect(pendingDeparture, 'Bram');
      expect(primaryTurns, 1);
    });

    test('/exit <name> selects the named guest (case-insensitive)', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/exit aria'), true);
      expect(exited.single.name, 'Aria');
      expect(pendingDeparture, 'Aria');
    });

    test('/exit partial-name match falls back to contains()', () async {
      guests = [_guest('Aria the Brave')];
      final h = build();
      expect(await h.handle('/exit brave'), true);
      expect(pendingDeparture, 'Aria the Brave');
    });

    test(
      '/exit with an unknown name surfaces an error, no departure',
      () async {
        guests = [_guest('Aria')];
        final h = build();
        expect(await h.handle('/exit zzz'), true);
        expect(systemMessages.single, contains('zzz'));
        expect(pendingDeparture, isNull);
        expect(exited, isEmpty);
        expect(primaryTurns, 0);
      },
    );

    test('/join outside a 1:1 chat is rejected', () async {
      joinable = [_guest('Nora')];
      final h = build(activeSet: false);
      expect(await h.handle('/join Nora'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(joined, isEmpty);
      expect(pickerRequests, isEmpty);
    });

    test('/join with no joinable characters surfaces a message', () async {
      final h = build();
      expect(await h.handle('/join'), true);
      expect(systemMessages.single, contains('No other characters'));
      expect(pickerRequests, isEmpty);
    });

    test('/join (no name) opens the picker with an empty filter', () async {
      joinable = [_guest('Nora'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/join'), true);
      expect(pickerRequests.single, '');
      expect(joined, isEmpty);
    });

    test('/join <exact name> joins outright (case-insensitive)', () async {
      joinable = [_guest('Nora'), _guest('Pax')];
      final h = build();
      expect(await h.handle('/join nora'), true);
      expect(joined.single.name, 'Nora');
      expect(pickerRequests, isEmpty);
    });

    test('/join <unique substring> joins the single match', () async {
      joinable = [_guest('Nora Vance'), _guest('Pax')];
      final h = build();
      await h.handle('/join vance');
      expect(joined.single.name, 'Nora Vance');
      expect(pickerRequests, isEmpty);
    });

    test('/join <ambiguous substring> opens the picker pre-filtered', () async {
      joinable = [_guest('Nora'), _guest('Norbert')];
      final h = build();
      await h.handle('/join nor');
      expect(joined, isEmpty);
      expect(pickerRequests.single, 'nor');
    });

    test('/join <no match> opens the picker pre-filtered', () async {
      joinable = [_guest('Nora')];
      final h = build();
      await h.handle('/join zzz');
      expect(joined, isEmpty);
      expect(pickerRequests.single, 'zzz');
    });

    test('/scan outside a 1:1 chat is rejected before scanning', () async {
      final h = build(activeSet: false);
      expect(await h.handle('/scan'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(castScans, 0);
    });

    test('/scan with no hit reports nothing found', () async {
      castScanFound = false;
      final h = build();
      expect(await h.handle('/scan'), true);
      expect(castScans, 1);
      expect(systemMessages.last, contains('No new recurring character'));
    });

    test('/scan with a hit stays silent (popup handles it)', () async {
      castScanFound = true;
      final h = build();
      expect(await h.handle('/scan'), true);
      expect(castScans, 1);
      // Only the "scanning…" status line; no "nothing found" follow-up.
      expect(systemMessages.length, 1);
      expect(systemMessages.single, contains('Scanning'));
    });

    test('/detect is an alias for /scan', () async {
      final h = build();
      expect(await h.handle('/detect'), true);
      expect(castScans, 1);
    });

    test('/speak with no guests surfaces a message, speaks nobody', () async {
      final h = build();
      expect(await h.handle('/speak Aria'), true);
      expect(systemMessages.single, contains('No scene guests'));
      expect(spoke, isEmpty);
    });

    test('/speak <exact name> forces that guest (case-insensitive)', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/speak bram'), true);
      expect(spoke.single.name, 'Bram');
    });

    test('/speak (no name) targets the most-recent guest', () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      await h.handle('/speak');
      expect(spoke.single.name, 'Bram');
    });

    test('/speak <unique substring> forces the single match', () async {
      guests = [_guest('Aria the Brave'), _guest('Bram')];
      final h = build();
      await h.handle('/speak brave');
      expect(spoke.single.name, 'Aria the Brave');
    });

    test('/speak <wrong name> lists the valid guests and speaks nobody',
        () async {
      guests = [_guest('Aria'), _guest('Bram')];
      final h = build();
      expect(await h.handle('/speak Zelda'), true);
      expect(spoke, isEmpty);
      expect(systemMessages.single, contains('Zelda'));
      expect(systemMessages.single, contains('Aria'));
      expect(systemMessages.single, contains('Bram'));
    });

    test('/speak <ambiguous substring> lists guests, speaks nobody', () async {
      guests = [_guest('Mara'), _guest('Marcus')];
      final h = build();
      await h.handle('/speak mar');
      expect(spoke, isEmpty);
      expect(systemMessages.single, contains('more than one'));
    });

    test('/turn is an alias for /speak', () async {
      guests = [_guest('Aria')];
      final h = build();
      await h.handle('/turn Aria');
      expect(spoke.single.name, 'Aria');
    });

    // Drift guard: the "type /" helper panel advertises ChatCommandHandler
    // .commands — every one must actually be a recognized command.
    test('every advertised command in the registry is recognized', () async {
      guests = [_guest('Aria')];
      for (final c in ChatCommandHandler.commands) {
        expect(await build().handle('/${c.command}'), true,
            reason: '/${c.command} is advertised but not handled');
      }
    });
  });
}
