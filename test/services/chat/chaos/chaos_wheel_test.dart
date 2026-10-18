// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Chance Time wheel: the 18+ gate on adult events, the category spread, pair
// and user events, repeat skipping, and the frequency / cooldown math.

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/chat/chat.dart';

ChaosModeService _chaos({
  bool adult = false,
  bool spicy = false,
  ChaosFrequency frequency = ChaosFrequency.normal,
}) {
  return ChaosModeService(
    onNotify: () {},
    onSaveChat: () async {},
    onSetPendingRealismMetadata: (_, _) {},
    isAdultAllowed: () => adult,
    getFrequency: () => frequency,
  )..seedFromGroupOrExt(true, spicy);
}

bool _isAdult(String text) => chaosEventFor(text)!.adult;

void main() {
  group('18+ gate', () {
    test(
      'spicy on but 18+ themes off: no adult event ever reaches a wheel',
      () {
        final chaos = _chaos(adult: false, spicy: true);
        expect(chaos.spicyActive, isFalse);
        for (var i = 0; i < 200; i++) {
          expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
        }
      },
    );

    test('a service built without the 18+ callback never allows adult', () {
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
      )..seedFromGroupOrExt(true, true);
      expect(chaos.adultAllowed, isFalse);
      expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
    });

    test('18+ themes on but spicy off: no adult events', () {
      final chaos = _chaos(adult: true, spicy: false);
      for (var i = 0; i < 100; i++) {
        expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
      }
    });

    test('both on: the wheel carries exactly the adult slots', () {
      final chaos = _chaos(adult: true, spicy: true);
      for (var i = 0; i < 50; i++) {
        final wheel = chaos.spinWheelEvents();
        expect(wheel.length, 8);
        expect(wheel.toSet().length, 8);
        expect(wheel.where(_isAdult).length, kAdultWheelSlots);
      }
    });

    test('turning 18+ themes off takes effect on the next wheel', () {
      var adult = true;
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        isAdultAllowed: () => adult,
      )..seedFromGroupOrExt(true, true);
      expect(chaos.spinWheelEvents().where(_isAdult), isNotEmpty);
      adult = false;
      expect(chaos.spinWheelEvents().where(_isAdult), isEmpty);
    });
  });

  group('wheel contents', () {
    test('SFW slots come from eight different categories', () {
      for (var seed = 0; seed < 50; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: false,
          allowPair: true,
          allowUser: true,
          random: Random(seed),
        );
        final cats = wheel.map((t) => chaosEventFor(t)!.category).toSet();
        expect(cats.length, 8, reason: 'seed $seed: $wheel');
      }
    });

    test('pair events need a partner; user events need the user', () {
      for (var seed = 0; seed < 200; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: false,
          allowUser: false,
          random: Random(seed),
        );
        expect(wheel.where((t) => t.contains('{{other}}')), isEmpty);
        expect(wheel.where((t) => t.contains('{{user}}')), isEmpty);
      }
    });

    test('recently used events are skipped', () {
      final chaos = _chaos(adult: true, spicy: true);
      final seen = <String>{};
      for (var i = 0; i < 3; i++) {
        final wheel = chaos.spinWheelEvents();
        expect(wheel.where(seen.contains), isEmpty);
        for (final e in wheel) {
          chaos.rememberEvent(e);
          seen.add(e);
        }
      }
    });

    test('every event is unique and uses only known placeholders', () {
      final texts = kAllChaosEvents.map((e) => e.text).toList();
      expect(texts.toSet().length, texts.length);
      for (final t in texts) {
        final names = RegExp(r'\{\{(\w+)\}\}').allMatches(t).map((m) => m[1]);
        expect(
          names.every(const {'char', 'user', 'other'}.contains),
          isTrue,
          reason: t,
        );
      }
    });
  });

  group('frequency and cooldown', () {
    test('Wild grows 10 a turn, Rare 2', () {
      final wild = _chaos(frequency: ChaosFrequency.wild);
      wild.checkAndTickChaosPressure();
      expect(wild.chaosPressure, 10);
      final rare = _chaos(frequency: ChaosFrequency.rare);
      rare.checkAndTickChaosPressure();
      expect(rare.chaosPressure, 2);
    });

    test('after an event lands, the cooldown turns pass with no growth '
        'and no roll', () async {
      final chaos = _chaos(frequency: ChaosFrequency.rare);
      await chaos.applyPreparedEvent('A bird lands.');
      expect(chaos.cooldownTurns, ChaosFrequency.rare.cooldown);
      for (var i = 0; i < ChaosFrequency.rare.cooldown; i++) {
        expect(chaos.checkAndTickChaosPressure(), isFalse);
        expect(chaos.chaosPressure, 0);
      }
      expect(chaos.cooldownTurns, 0);
      chaos.checkAndTickChaosPressure();
      expect(chaos.chaosPressure, ChaosFrequency.rare.growth);
    });

    test('an unknown stored frequency reads as Normal', () {
      expect(ChaosFrequency.fromName('bogus'), ChaosFrequency.normal);
      expect(ChaosFrequency.fromName(null), ChaosFrequency.normal);
      expect(ChaosFrequency.fromName('wild'), ChaosFrequency.wild);
    });
  });

  // Recovery overhaul PR 6: the wheel respects the hard lock. Exactly the
  // events that ASSERT the speaker's own desire leave the pool while that
  // body is locked — every other event (and the whole SFW wheel) spins as
  // before, and a soft-gate body never loses one.
  group('the hard lock respects the wheel (PR 6)', () {
    const locked = {
      '{{char}} is visibly aroused at the most inconvenient moment '
          'imaginable and is scrambling',
      '{{char}} is trying extremely hard to hide a visible physical '
          'reaction to someone attractive nearby',
      '{{char}} is suddenly, intensely in the mood and it is very hard '
          'to hide',
      'A long dry spell has caught up with {{char}} and they are '
          'restless, flustered, and thinking about little else',
    };

    test('exactly the four desire-asserting events carry the tag', () {
      final tagged = kAllChaosEvents
          .where((e) => e.desireAsserting)
          .map((e) => e.text)
          .toSet();
      expect(tagged, locked);
      expect(
        kAllChaosEvents.where((e) => e.desireAsserting).every((e) => e.adult),
        isTrue,
        reason: 'a desire event that is not adult would gate into SFW wheels',
      );
    });

    test('the locked wheel never speaks a tagged event, and stays full', () {
      for (var seed = 0; seed < 200; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: true,
          allowUser: true,
          hardLockActive: true,
          random: Random(seed),
        );
        expect(wheel.length, 8);
        expect(wheel.toSet().length, 8);
        expect(
          wheel.where(locked.contains),
          isEmpty,
          reason: 'seed $seed narrates arousal under a hard lock: $wheel',
        );
        expect(
          wheel.where(_isAdult).length,
          kAdultWheelSlots,
          reason: 'the remaining adult pool backfills — no dead slots',
        );
      }
    });

    test('the unlocked wheel still serves them', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        seen.addAll(
          buildChaosWheel(
            includeAdult: true,
            allowPair: true,
            allowUser: true,
            random: Random(seed),
          ).where(locked.contains),
        );
      }
      expect(
        seen,
        locked,
        reason: 'a baseline wheel must still be able to land each one',
      );
    });

    test('the recent-skip fallback cannot sneak one back under lock', () {
      // Saturate recency with every OTHER adult text: the "not enough
      // fresh" fallback hands back the whole pool, and the tagged four
      // were already pulled BEFORE that branch — never after.
      final others = [
        for (final e in kAllChaosEvents)
          if (e.adult && !locked.contains(e.text)) e.text,
      ];
      for (var seed = 0; seed < 50; seed++) {
        final wheel = buildChaosWheel(
          includeAdult: true,
          allowPair: true,
          allowUser: true,
          hardLockActive: true,
          recent: others,
          random: Random(seed),
        );
        expect(wheel.where(locked.contains), isEmpty, reason: 'seed $seed');
        expect(wheel.length, 8);
      }
    });

    test('the service gate is live per spin, and absent means never gated', () {
      var lockedNow = true;
      final chaos = ChaosModeService(
        onNotify: () {},
        onSaveChat: () async {},
        onSetPendingRealismMetadata: (_, _) {},
        isAdultAllowed: () => true,
        isHardLockActive: () => lockedNow,
      )..seedFromGroupOrExt(true, true);
      for (var i = 0; i < 100; i++) {
        expect(chaos.spinWheelEvents().where(locked.contains), isEmpty);
      }
      lockedNow = false; // the window passes mid-session
      final seen = <String>{};
      for (var i = 0; i < 300; i++) {
        seen.addAll(chaos.spinWheelEvents().where(locked.contains));
      }
      expect(seen, isNotEmpty);
      // A service built without the closure (every other host) never gates.
      final ungated = _chaos(adult: true, spicy: true);
      final seen2 = <String>{};
      for (var i = 0; i < 300; i++) {
        seen2.addAll(ungated.spinWheelEvents().where(locked.contains));
      }
      expect(seen2, isNotEmpty);
    });
  });
}
