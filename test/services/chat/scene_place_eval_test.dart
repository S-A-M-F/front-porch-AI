// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6 guards (design §6 row 6, evaluator half): the clock judge may
// FLAG an arrival — it never moves the scene, never touches the slots,
// and a plan or a stranger-name is not a move. Plus the decline memory:
// Stay sticks for the current Setting and dies with it.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/scene_move_state.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

TimeService makeService({
  List<({String id, String label})>? Function()? getScenePlaceOffer,
  void Function(String id)? onScenePlace,
}) => TimeService(
  onNotify: () {},
  onSaveChat: () async {},
  onSetPendingRealismMetadata: (_, _) {},
  onPatchLastMessageRealismState: (_, _, _) {},
  getScenePlaceOffer: getScenePlaceOffer,
  onScenePlace: onScenePlace,
);

Future<String> runTurn(
  TimeService t,
  String reply, {
  bool sceneMovesAllowed = true,
}) async {
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
    sceneMovesAllowed: sceneMovesAllowed,
  );
  return prompt ?? '';
}

void main() {
  const offer = [
    (id: 'p-tea', label: 'Tea Rooms'),
    (id: 'p-gate', label: 'Harbour Gate · inside Bletchport'),
  ];

  group('scene_place on the clock judge', () {
    test('an arrival answer fires the callback and leaves the clock a '
        'clock', () async {
      String? flagged;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onScenePlace: (id) => flagged = id,
      );
      t.seedFromV2OrExt(
        dayCount: 3,
        timeOfDay: 'evening',
        storyStartDate: '2026-06-30',
      );
      await runTurn(
        t,
        '{"minutes_elapsed": 20, "new_day": false, "scene_place": "p-tea"}',
      );
      expect(flagged, 'p-tea', reason: 'arrival sets the flag');
      // The move itself is NOT applied here: the clock moved 20 minutes
      // and nothing else was touched — the evaluator has no slots at all.
      expect(t.clock, DateTime.utc(2026, 7, 2, 18, 50));
    });

    test('a plan (no scene_place) never flags', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onScenePlace: (_) => fired = true,
      );
      await runTurn(t, '{"minutes_elapsed": 5, "new_day": false}');
      expect(fired, isFalse, reason: 'the field is omitted on plans');
    });

    test('"same" never flags', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onScenePlace: (_) => fired = true,
      );
      await runTurn(
        t,
        '{"minutes_elapsed": 5, "new_day": false, "scene_place": "same"}',
      );
      expect(fired, isFalse);
    });

    test('an id nobody offered is a hallucination, not a move', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => offer,
        onScenePlace: (_) => fired = true,
      );
      await runTurn(
        t,
        '{"minutes_elapsed": 5, "scene_place": "p-the-moon"}',
      );
      expect(fired, isFalse);
    });

    test('with the switch off the prompt is untouched', () async {
      var fired = false;
      final t = makeService(
        getScenePlaceOffer: () => null,
        onScenePlace: (_) => fired = true,
      );
      final prompt = await runTurn(
        t,
        '{"minutes_elapsed": 5, "scene_place": "p-tea"}',
      );
      expect(prompt, isNot(contains('scene_place')));
      expect(fired, isFalse, reason: 'nothing was offered, so nothing is valid');
    });

    test('Director and Lite turns are not offered a move', () async {
      var offered = 0;
      final t = makeService(
        getScenePlaceOffer: () {
          offered++;
          return offer;
        },
        onScenePlace: (_) {},
      );
      final prompt = await runTurn(
        t,
        '{"minutes_elapsed": 5}',
        sceneMovesAllowed: false,
      );
      expect(offered, 0, reason: 'the supplier is not even consulted');
      expect(prompt, isNot(contains('scene_place')));
    });

    test('the offered ids appear in the prompt when on', () async {
      final t = makeService(getScenePlaceOffer: () => offer, onScenePlace: (_) {});
      final prompt = await runTurn(t, '{"minutes_elapsed": 5}');
      expect(prompt, contains('"p-tea" (Tea Rooms)'));
      expect(prompt, contains('"p-gate" (Harbour Gate · inside Bletchport)'));
      // Review #605: rules stay sequentially numbered. The planner is
      // off in this harness, so scene_place is rule 5.
      expect(prompt, contains('5. "scene_place"'));
      expect(prompt, isNot(contains('4. "days"')));
    });
  });

  group('the decline memory', () {
    test('Stay sticks while the Setting holds', () {
      final m = SceneMoveState();
      m.pending = const PendingPlaceMove(id: 'p-tea', name: 'Tea Rooms');
      m.decline('p-tea', 'world-earth');
      expect(m.isDeclined('p-tea'), isTrue);
      expect(m.pending, isNull);
    });

    test('a different Setting revives the offer', () {
      final m = SceneMoveState();
      m.decline('p-tea', 'world-earth');
      m.decline('p-gate', 'world-mars');  // scope moved: old decline dies
      expect(m.isDeclined('p-tea'), isFalse);
      expect(m.isDeclined('p-gate'), isTrue);
    });

    test('a move landing clears declines AND any open offer', () {
      final m = SceneMoveState();
      m.decline('p-tea', 'world-earth');
      m.pending = const PendingPlaceMove(id: 'p-gate', name: 'Gate');
      m.settingChanged();
      expect(m.isDeclined('p-tea'), isFalse);
      expect(m.pending, isNull);
    });
  });
}
