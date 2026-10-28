// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 7 guards (design §3 "Minted places"): the clock judge's
// scene_place field gains one more legal value, "new", carried with a
// NAME and a one-line DESCRIPTOR (the same pair cast detection uses).
// It fires only when the reply narrates arriving at a NAMED place that
// is not in the reachable list; an unnamed side street never
// qualifies; nothing mints until a human taps. The evaluator only
// flags — same law as slice 6's moves.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/scene_mint_state.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService makeService({
  List<({String id, String label})>? Function()? getScenePlaceOffer,
  void Function(String id)? onScenePlace,
  void Function(String name, String descriptor)? onNewPlace,
}) => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
  getScenePlaceOffer: getScenePlaceOffer,
  onScenePlace: onScenePlace,
  onNewPlace: onNewPlace,
);

Future<String> runTurn(TimeService t, String reply) async {
  String? prompt;
  await t.evaluateTimeProgressAndPostureIfNeeded(
    charName: 'Nia',
    recent: 'User: hi\nNia: hello',
    shortTermTierName: 'Warm',
    onChunk: null,
    fireLLMEval: (p, {onChunk}) async {
      prompt = p;
      return reply;
    },
    stripThinkBlocks: (s) => s,
    extractJsonBool: (text, key) {
      final m = RegExp('"$key"\\s*:\\s*(true|false)').firstMatch(text);
      return m == null ? null : m.group(1) == 'true';
    },
    setSpatialStance: (_) {},
    getCurrentSpatialStance: () => 'on the porch',
    getCharacterEmotion: () => 'content',
    getEmotionIntensity: () => 'mild',
    timeOnly: true,
  );
  return prompt ?? '';
}

void main() {
  const offer = [(id: 'p-tea', label: 'Tea Rooms')];

  group('the new value mints nothing but a flag', () {
    test('scene_place:"new" with a name+descriptor flags the pair', () async {
      String? name, desc;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onNewPlace: (n, d) {
          name = n;
          desc = d;
        },
      );
      await runTurn(
        t,
        '{"minutes_elapsed": 10, "scene_place": "new", '
        '"new_place_name": "The Salt Garden", '
        '"new_place_descriptor": "hedged beds beside the tideline"}',
      );
      expect(name, 'The Salt Garden');
      expect(desc, 'hedged beds beside the tideline');
    });

    test('a NAMED new place is demanded: no name, no flag', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onNewPlace: (_, _) => fired = true,
      );
      await runTurn(
        t,
        '{"minutes_elapsed": 10, "scene_place": "new"}',
      );
      expect(fired, isFalse, reason: 'unnamed side streets never qualify');
    });

    test('a blank name is the same as none', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onNewPlace: (_, _) => fired = true,
      );
      await runTurn(
        t,
        '{"scene_place": "new", "new_place_name": "  ", '
        '"new_place_descriptor": "x"}',
      );
      expect(fired, isFalse);
    });

    test('the prompt names "new" among the legal answers', () async {
      final t = makeService(getScenePlaceOffer: () => offer, onNewPlace: (_, _) {});
      final prompt = await runTurn(t, '{"minutes_elapsed": 5}');
      expect(prompt, contains('"new"'));
      expect(prompt, contains('named'));
    });

    test('switch-off prompt stays byte-quiet about new places', () async {
      final t = makeService(
        getScenePlaceOffer: () => null,
        onNewPlace: (_, _) => throw StateError('must not fire'),
      );
      final prompt = await runTurn(t, '{"minutes_elapsed": 5}');
      expect(prompt, isNot(contains('new_place_name')));
      expect(prompt, isNot(contains('"new"')));
    });
  });

  group('ignored mint names', () {
    test('an ignored name is never re-flagged for this chat', () {
      final m = SceneMintState();
      m.ignore('The Salt Garden');
      expect(m.isIgnored('the salt garden'), isTrue, reason: 'case-insensitive');
      expect(m.isIgnored('Gate House'), isFalse);
    });

    test('session reset forgets the ignore list', () {
      final m = SceneMintState();
      m.ignore('X');
      m.reset();
      expect(m.isIgnored('X'), isFalse);
      expect(m.pending, isNull);
    });
  });
}
