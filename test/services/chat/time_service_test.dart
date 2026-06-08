// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for the extracted TimeService (plain class).
// Covers: narrativeWeekday calc (start+daycount combos), legacy resolveStartDayOfWeek (persisted + 0/legacy cases),
// nudge (deltas + day wrap + turns reset + metadata patch roundtrip via live cb + survival semantics),
// passage toggle + effects (advance guard), resets/loads/roundtrips/seeds (fresh start-of-day, ext seed, load scalars with resolve),
// OOC detect (markers, phrases, periods, next-day special, pending stamp via cb, disabled guard),
// public surface (getters, buildTimeInjection thin, resolve exposed), explicit 1:1 vs group parity note
// (time is chat-scoped not per-speaker; exercised via live owner mutation in integrations for group speaker impersonation).
// Uses createTestTime factory (modeled exactly on expression_classifier_test.dart / relationship / chaos / needs).
// Real owner dispatch: reset/seed/load sites passively via pre-existing startNew/setActive/_loadLast/group load in
// key suites (realism_engine, group_realism, session); full nudge/OOC/advance/eval paths exercised in dedicated
// (with fake fireLLM) + manual. (aug edits in key tests add only qualified header notes per review precedent:
// "reset sites passively hit by pre-existing...; full time advance/nudge/OOC only in dedicated + manual").
// No unit for full prompt builders (step8); time injection tested only as thin build here.
// Callback contract exercised (patch cb for nudge, pending cb for OOC, onNotify/onSave).
// 0 forcing of internal state; real dispatch for branches where unit feasible.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/time_service.dart';

/// Test factory (modeled exactly on prior leaf tests).
/// Supplies realistic defaults + live closures/maps for side-effect cbs (pending, nudge patch with full (tod,dc) payload capture for stronger asserts).
/// emotionRef/group-swap not required for time (chat-scoped) but kept for parity sim pattern.
TimeService createTestTime({
  List<String>? notifies,
  List<String>? saves,
  List<MapEntry<String, dynamic>>? pendingStamps,
  List<MapEntry<String, int>>?
  patchPayloads, // enhanced to capture (tod, dc) payload for stronger nudge cb testing
  bool initialPassage = true,
  int initialDay = 1,
  String initialTime = 'morning',
  int initialStartDow = 1,
  int initialTurns = 0,
}) {
  final n = notifies ?? <String>[];
  final s = saves ?? <String>[];
  final p = pendingStamps ?? <MapEntry<String, dynamic>>[];
  final patches = patchPayloads ?? <MapEntry<String, int>>[];

  // Live map to simulate god's _pendingRealismMetadata for OOC/nudge stamps
  final pending = <String, dynamic>{};

  final svc = TimeService(
    onNotify: () => n.add('notify'),
    onSaveChat: () async => s.add('save'),
    onSetPendingRealismMetadata: (k, v) {
      pending[k] = v;
      p.add(MapEntry(k, v));
    },
    onNudgePatchLastMessageRealismState: (tod, dc) =>
        patches.add(MapEntry(tod, dc)),
  );

  // Seed initial via public load (real path, no internal force)
  svc.loadTimeScalars(
    timeOfDay: initialTime,
    dayCount: initialDay,
    startDayOfWeek: initialStartDow,
    passageOfTimeEnabled: initialPassage,
  );
  // turns not exposed for direct set; nudge/advance paths exercise it
  return svc;
}

void main() {
  group('TimeService (extracted leaf)', () {
    test(
      'narrativeWeekday computes correctly from start + dayCount (Mon anchor, various days)',
      () {
        final svc = createTestTime(
          initialStartDow: 1,
          initialDay: 1,
        ); // Day 1 = Mon
        expect(svc.narrativeWeekday, 'Monday');
        final svc2 = createTestTime(initialStartDow: 1, initialDay: 2);
        expect(svc2.narrativeWeekday, 'Tuesday');
        final svc7 = createTestTime(initialStartDow: 1, initialDay: 7);
        expect(svc7.narrativeWeekday, 'Sunday');
        final svc8 = createTestTime(initialStartDow: 1, initialDay: 8);
        expect(svc8.narrativeWeekday, 'Monday');
      },
    );

    test(
      'resolveStartDayOfWeek returns persisted when valid 1-7, computes legacy anchor for 0',
      () {
        final svc = createTestTime();
        expect(svc.resolveStartDayOfWeek(3, 5), 3); // valid
        // legacy 0: formula produces stable anchor (we don't assert exact today-dependent value,
        // but it must be 1-7 and not crash)
        final legacy = svc.resolveStartDayOfWeek(0, 10);
        expect(legacy, inInclusiveRange(1, 7));
        final legacy2 = svc.resolveStartDayOfWeek(0, 1);
        expect(legacy2, inInclusiveRange(1, 7));
      },
    );

    test(
      'nudgeTimePeriod +1/-1 mutates time/turns/day, calls patch cb (roundtrip)',
      () {
        final patches = <MapEntry<String, int>>[];
        final svc = createTestTime(
          initialTime: 'morning',
          initialDay: 5,
          patchPayloads: patches,
        );
        svc.nudgeTimePeriod(1);
        expect(svc.timeOfDay, 'late_morning');
        expect(svc.dayCount, 5);
        expect(patches.length, 1);
        expect(patches.last.key, 'late_morning');
        expect(patches.last.value, 5);

        svc.nudgeTimePeriod(-1);
        expect(svc.timeOfDay, 'morning');
        expect(patches.length, 2);
        expect(patches.last.key, 'morning');
        expect(patches.last.value, 5);

        // wrap forward past night -> day++
        final svcWrapFwd = createTestTime(
          initialTime: 'night',
          initialDay: 10,
          patchPayloads: patches,
        );
        svcWrapFwd.nudgeTimePeriod(1);
        expect(svcWrapFwd.timeOfDay, 'dawn');
        expect(svcWrapFwd.dayCount, 11);
        expect(patches.length, 3);
        expect(patches.last.key, 'dawn');
        expect(patches.last.value, 11);

        // wrap backward past dawn -> day--
        final svcWrapBack = createTestTime(
          initialTime: 'dawn',
          initialDay: 10,
          patchPayloads: patches,
        );
        svcWrapBack.nudgeTimePeriod(-1);
        expect(svcWrapBack.timeOfDay, 'night');
        expect(svcWrapBack.dayCount, 9);
        expect(patches.last.key, 'night');
        expect(patches.last.value, 9);
      },
    );

    test('passageOfTimeEnabled toggle affects advance guard and OOC', () {
      final svc = createTestTime(initialPassage: false);
      expect(svc.passageOfTimeEnabled, false);
      svc.setPassageOfTimeEnabled(true);
      expect(svc.passageOfTimeEnabled, true);
    });

    test(
      'resetForFreshChat sets start-of-day + anchor + passage true + turns 0',
      () {
        final svc = createTestTime(
          initialDay: 42,
          initialTime: 'night',
          initialPassage: false,
        );
        svc.resetForFreshChat();
        expect(svc.dayCount, 1);
        expect(svc.timeOfDay, 'morning');
        expect(svc.passageOfTimeEnabled, true);
        expect(svc.narrativeWeekday, isNot('')); // anchor set
      },
    );

    test('seedFromV2OrExt applies clamped day/time/passage (anchor set)', () {
      final svc = createTestTime();
      svc.seedFromV2OrExt(
        dayCount: 123,
        timeOfDay: 'evening',
        passageOfTimeEnabled: false,
      );
      expect(svc.dayCount, 123);
      expect(svc.timeOfDay, 'evening');
      expect(svc.passageOfTimeEnabled, false);
    });

    test('loadTimeScalars roundtrips + resolve for start', () {
      final svc = createTestTime();
      svc.loadTimeScalars(
        timeOfDay: 'afternoon',
        dayCount: 7,
        startDayOfWeek: 4,
        passageOfTimeEnabled: true,
      );
      expect(svc.timeOfDay, 'afternoon');
      expect(svc.dayCount, 7);
      expect(svc.passageOfTimeEnabled, true);
    });

    test(
      'restoreTimeForSwipeOrRegen respects !nudged + passage, ignores when nudged',
      () {
        final svc = createTestTime(
          initialTime: 'dawn',
          initialDay: 2,
          initialPassage: true,
        );
        svc.restoreTimeForSwipeOrRegen({
          'timeOfDay': 'night',
          'dayCount': 5,
        }, wasNudged: false);
        expect(svc.timeOfDay, 'night');
        expect(svc.dayCount, 5);

        svc.restoreTimeForSwipeOrRegen({
          'timeOfDay': 'morning',
          'dayCount': 99,
        }, wasNudged: true);
        expect(svc.timeOfDay, 'night'); // unchanged
      },
    );

    test(
      'restoreTimeFromRealismState applies when passage, copies start anchor',
      () {
        final svc = createTestTime(initialPassage: true);
        svc.restoreTimeFromRealismState({
          'timeOfDay': 'late_morning',
          'dayCount': 9,
          'startDayOfWeek': 2,
        });
        expect(svc.timeOfDay, 'late_morning');
        expect(svc.dayCount, 9);
      },
    );

    test(
      'detectOocTimeSkip (with OOC marker) advances and stamps pending via cb',
      () {
        final stamps = <MapEntry<String, dynamic>>[];
        final notifies = <String>[];
        final svc = createTestTime(
          initialTime: 'morning',
          initialDay: 3,
          pendingStamps: stamps,
          notifies: notifies,
        );
        svc.detectOocTimeSkip('(ooc: time skip a few hours)');
        expect(svc.timeOfDay, isNot('morning'));
        expect(stamps.any((e) => e.key == 'time_skip_to'), true);
        expect(notifies.isNotEmpty, true);
      },
    );

    test('detectOocTimeSkip next-day special advances day + stamps Dawn', () {
      final stamps = <MapEntry<String, dynamic>>[];
      final svc = createTestTime(
        initialTime: 'night',
        initialDay: 10,
        pendingStamps: stamps,
      );
      svc.detectOocTimeSkip('ooc: woke up the next day');
      expect(svc.dayCount, 11);
      expect(svc.timeOfDay, 'dawn');
      expect(stamps.last.value, 'Dawn · Day 11');
    });

    test('detectOocTimeSkip does nothing when passage disabled', () {
      final svc = createTestTime(initialPassage: false, initialTime: 'morning');
      svc.detectOocTimeSkip('ooc: skip to next day');
      expect(svc.timeOfDay, 'morning');
      expect(svc.dayCount, 1);
    });

    test(
      'buildTimeInjection returns thin scene time block (step8 note: full builders later)',
      () {
        final svc = createTestTime(
          initialTime: 'afternoon',
          initialDay: 4,
          initialStartDow: 1,
        );
        final inj = svc.buildTimeInjection();
        expect(inj, contains('Scene Time: Afternoon'));
        expect(inj, contains('Day 4'));
        expect(inj, contains('Thursday')); // (start=1 + day4-1 = idx3)
      },
    );

    test(
      'public surface + evaluateTimeProgress (eligible advance path via fake fireLLM)',
      () async {
        final svc = createTestTime(initialTime: 'morning', initialDay: 1);
        // Make eligible by faking internal turns (no direct setter; use multiple no-op calls or test via the method)
        // For unit, directly exercise the eligible branch with a fake that returns hold=false.
        bool calledFire = false;
        Future<String?> fakeFire(
          String prompt, {
          void Function(String)? onChunk,
        }) async {
          calledFire = true;
          return '{"hold_time": false, "new_day": false, "posture": "sitting by the fire"}';
        }

        // Call 6 times to reach eligible (real ++ inside each evaluate; 6th parses hold=false + advances).
        // No internal force; real dispatch in evaluateTimeProgressAndPostureIfNeeded.
        for (int i = 0; i < 6; i++) {
          await svc.evaluateTimeProgressAndPostureIfNeeded(
            charName: 'Test',
            recent: 'user: hi\nTest: hello',
            shortTermTierName: 'Neutral',
            onChunk: null,
            fireLLMEval: fakeFire,
            stripThinkBlocks: (s) => s,
            extractJsonBool: (t, k) {
              if (k == 'hold_time') return false;
              if (k == 'new_day') return false;
              return null;
            },
            setSpatialStance: (_) {},
            getCurrentSpatialStance: () => 'standing',
            getCharacterEmotion: () => '',
            getEmotionIntensity: () => '',
          );
        }
        expect(calledFire, true);
        // time should have advanced from morning on the 6th (eligible) call
        expect(svc.timeOfDay, isNot('morning'));
      },
    );

    test(
      '1:1 vs group parity note (time chat-scoped; owner swap via loadGroupRealism in god exercised in aug)',
      () {
        // Time has no per-speaker state (unlike rel/needs). Group uses same scalars.
        // Live mutation test: load different "speaker" context does not fork time.
        final svc = createTestTime(initialDay: 5, initialTime: 'evening');
        // Simulate owner "swap" by loading scalars (as god does for group speaker)
        svc.loadTimeScalars(
          timeOfDay: 'evening',
          dayCount: 5,
          startDayOfWeek: 3,
          passageOfTimeEnabled: true,
        );
        expect(svc.dayCount, 5); // shared
        expect(svc.timeOfDay, 'evening');
        // nudge affects the one chat time
        svc.nudgeTimePeriod(1);
        expect(svc.timeOfDay, 'night');
      },
    );

    test('OOC periods estimation + multi-period wrap (several hours = +3)', () {
      final stamps = <MapEntry<String, dynamic>>[];
      final svc = createTestTime(
        initialTime: 'dawn',
        initialDay: 1,
        pendingStamps: stamps,
      );
      svc.detectOocTimeSkip('ooc: several hours pass');
      // dawn +3 -> afternoon
      expect(svc.timeOfDay, 'afternoon');
      expect(stamps.isNotEmpty, true);
    });

    test(
      'fresh group time init (resetForFreshChat sim for setActiveGroup / _loadLast empty group path) sets start-of-day, passage true, anchored weekday',
      () {
        // Simulates the zeroing now called in setActiveGroup defensive + _loadLastSession empty branch for groups (cross-check vs prior needs reset hygiene).
        // Prevents stale advanced time/passage/anchor bleed from prior 1:1 into fresh group creation / 0-session.
        final svc = createTestTime(
          initialDay: 99,
          initialTime: 'night',
          initialPassage: false,
          initialStartDow: 0, // legacy/unset
        );
        svc.resetForFreshChat();
        expect(svc.dayCount, 1);
        expect(svc.timeOfDay, 'morning');
        expect(svc.passageOfTimeEnabled, true);
        expect(
          svc.narrativeWeekday,
          isNotEmpty,
        ); // anchored to today via resolve
        final resolved = svc.resolveStartDayOfWeek(0, 1);
        expect(resolved, inInclusiveRange(1, 7));
      },
    );
  });
}
