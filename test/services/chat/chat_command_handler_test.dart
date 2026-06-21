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
    late List<(String, String)> mintCalls;
    late List<CharacterCard> entered;
    late List<CharacterCard> exited;
    late String? pendingDeparture;
    late int primaryTurns;
    GuestMintResult Function(String, String) mintBehavior = (n, c) =>
        GuestMintResult.success(_guest(n));

    ChatCommandHandler build({bool activeSet = true}) {
      return ChatCommandHandler(
        setExpression: expressionCalls.add,
        activeCharacterIsSet: () => activeSet,
        getSceneGuestCards: () => guests,
        setPendingGuestDeparture: (n) => pendingDeparture = n,
        onSystemMessage: systemMessages.add,
        generatePrimaryTurn: () async => primaryTurns++,
        mintGuest: (name, concept) async {
          mintCalls.add((name, concept));
          return mintBehavior(name, concept);
        },
        enterGuest: (g) async => entered.add(g),
        exitGuest: (g) async => exited.add(g),
      );
    }

    setUp(() {
      guests = [];
      systemMessages = [];
      expressionCalls = [];
      mintCalls = [];
      entered = [];
      exited = [];
      pendingDeparture = null;
      primaryTurns = 0;
      mintBehavior = (n, c) => GuestMintResult.success(_guest(n));
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

    test('/create outside a 1:1 chat is rejected before minting', () async {
      final h = build(activeSet: false);
      expect(await h.handle('/create Bob: a baker'), true);
      expect(systemMessages.single, contains('1:1'));
      expect(mintCalls, isEmpty);
    });

    test('/create with empty args shows usage', () async {
      final h = build();
      expect(await h.handle('/create'), true);
      expect(systemMessages.last, contains('Usage'));
      expect(mintCalls, isEmpty);
    });

    test('/create splits name/concept on ":" and enters on success', () async {
      final h = build();
      expect(await h.handle('/create Bob: a cheerful baker'), true);
      expect(mintCalls.single, ('Bob', 'a cheerful baker'));
      expect(entered.single.name, 'Bob');
    });

    test('/create splits name/concept on "|"', () async {
      final h = build();
      await h.handle('/create Mara | a stoic guard');
      expect(mintCalls.single, ('Mara', 'a stoic guard'));
    });

    test('/create with name only yields empty concept', () async {
      final h = build();
      await h.handle('/create Solo');
      expect(mintCalls.single, ('Solo', ''));
    });

    test('/create surfaces mint failure and does not enter', () async {
      mintBehavior = (n, c) => const GuestMintResult.failure('backend down');
      final h = build();
      await h.handle('/create Bob: baker');
      expect(systemMessages.last, contains('backend down'));
      expect(entered, isEmpty);
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
  });
}
