// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

// The recovery profile value class (docs/design/afterglow-recovery-overhaul.md,
// decisions 1–3): the preset table, the sex prior, the lenient readers, and
// the copy lines. The Dart side is the source of truth;
// `web_ui/src/components/realism/realismTypes.ts` mirrors it and its vitest
// pins the same values — edit one, edit both, run both suites.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character/recovery_profile.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';

void main() {
  group('the preset table is one decision, spelled once', () {
    test('keys, modes, and fixed minutes match decision 3', () {
      expect(kRecoveryPresets.map((p) => p.key).toList(), [
        'auto',
        'none',
        'personality',
        'short',
        'typical',
        'long',
        'custom',
      ]);
      final byKey = {for (final p in kRecoveryPresets) p.key: p};
      expect(byKey['auto']!.recoveryMode, kRecoveryModeAuto);
      expect(byKey['auto']!.recoveryMinutes, isNull);
      expect(
        byKey['none']!.recoveryMode,
        kRecoveryModeSoft,
        reason: 'multiorgasmic is a gate choice, not a zero-length lock',
      );
      expect(byKey['none']!.recoveryMinutes, isNull);
      expect(byKey['personality']!.recoveryMode, kRecoveryModeHard);
      expect(
        byKey['personality']!.recoveryMinutes,
        isNull,
        reason: 'this is the only fixed preset that keeps the judge',
      );
      expect(byKey['short']!.recoveryMinutes, 30);
      expect(byKey['typical']!.recoveryMinutes, 90);
      expect(
        byKey['long']!.recoveryMinutes,
        180,
        reason: 'the judge ceiling (12 × 15) is the slider ceiling',
      );
    });

    test('fromPreset and presetKey round-trip every non-custom row', () {
      for (final key in [
        'auto',
        'none',
        'personality',
        'short',
        'typical',
        'long',
      ]) {
        expect(RecoveryProfile.fromPreset(key).presetKey, key);
      }
    });

    test('presetKey reads the stored pair the way the menu shows it', () {
      expect(const RecoveryProfile().presetKey, 'auto');
      expect(
        const RecoveryProfile(recoveryMode: kRecoveryModeSoft).presetKey,
        'none',
      );
      expect(
        const RecoveryProfile(recoveryMode: kRecoveryModeHard).presetKey,
        'personality',
      );
      expect(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 45,
        ).presetKey,
        'custom',
      );
      expect(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 45,
        ).presetLabel,
        'Custom',
      );
    });

    test('moving the slider selects Custom — a hard lock of exactly that', () {
      final p = const RecoveryProfile().withMinutes(50);
      expect(p.recoveryMode, kRecoveryModeHard);
      expect(p.recoveryMinutes, 50);
      expect(p.presetKey, 'custom');
      expect(const RecoveryProfile().withMinutes(-5).recoveryMinutes, 0);
      expect(const RecoveryProfile().withMinutes(500).recoveryMinutes, 180);
    });
  });

  group('auto resolves by physiology, nothing else is surprised', () {
    test('the sex prior maps only female to the gate', () {
      expect(const RecoveryProfile().resolvedMode('female'), kRecoveryModeSoft);
      expect(const RecoveryProfile().resolvedMode('male'), kRecoveryModeHard);
      expect(const RecoveryProfile().resolvedMode('other'), kRecoveryModeHard);
      expect(
        const RecoveryProfile().resolvedMode(''),
        kRecoveryModeHard,
        reason: 'no structured sex is today\'s behavior, exactly',
      );
    });

    test('an explicit mode is never re-decided by sex', () {
      expect(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
        ).resolvedMode('female'),
        kRecoveryModeHard,
      );
      expect(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeSoft,
        ).resolvedMode('male'),
        kRecoveryModeSoft,
      );
    });
  });

  group('the readers are lenient like every card reader', () {
    test('absent or malformed reads auto, never throws', () {
      for (final junk in [null, 'insatiable', 42, [], {}]) {
        expect(
          RecoveryProfile.fromJson(junk).isDefault,
          isTrue,
          reason: 'junk: $junk',
        );
        expect(
          RecoveryProfile.fromFields(junk).isDefault,
          isTrue,
          reason: 'junk: $junk',
        );
      }
    });

    test('a junk mode string falls to auto, a length on it is dropped', () {
      final p = RecoveryProfile.fromJson({'mode': 'sometimes', 'minutes': 90});
      expect(p.recoveryMode, kRecoveryModeAuto);
      expect(p.recoveryMinutes, isNull);
    });

    test('only a hard lock keeps a length — soft drops it, like the menu', () {
      final soft = RecoveryProfile.fromJson({'mode': 'soft', 'minutes': 30});
      expect(soft.recoveryMode, kRecoveryModeSoft);
      expect(
        soft.recoveryMinutes,
        isNull,
        reason: 'keeping it would make the preset menu lie about itself',
      );
    });

    test('a hard length parses loosely and clamps to the slider span', () {
      expect(
        RecoveryProfile.fromJson({
          'mode': 'hard',
          'minutes': '90',
        }).recoveryMinutes,
        90,
      );
      expect(
        RecoveryProfile.fromJson({
          'mode': 'hard',
          'minutes': 900,
        }).recoveryMinutes,
        180,
      );
      expect(
        RecoveryProfile.fromJson({
          'mode': 'hard',
          'minutes': -5,
        }).recoveryMinutes,
        isNull,
        reason: 'below the span means the judge decides again, not a lie',
      );
      expect(
        RecoveryProfile.fromJson({
          'mode': 'hard',
          'minutes': 'soon',
        }).recoveryMinutes,
        isNull,
      );
    });

    test('the bridge shape carries the same pair under its own key names', () {
      final p = RecoveryProfile.fromFields({
        'recoveryMode': 'hard',
        'recoveryMinutes': 45,
      });
      expect(p.recoveryMode, kRecoveryModeHard);
      expect(p.recoveryMinutes, 45);
      expect(
        RecoveryProfile.fromFields({'recoveryMode': 'soft'}).recoveryMinutes,
        isNull,
      );
    });

    test('toJson / fromJson and toFields / fromFields are exact inverses', () {
      for (final p in [
        const RecoveryProfile(),
        const RecoveryProfile(recoveryMode: kRecoveryModeSoft),
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 45,
        ),
        const RecoveryProfile(recoveryMode: kRecoveryModeHard),
      ]) {
        expect(RecoveryProfile.fromJson(p.toJson()).toJson(), p.toJson());
        expect(
          RecoveryProfile.fromFields(p.toFields()).toFields(),
          p.toFields(),
        );
      }
    });
  });

  group('normalizeCharacterSex reads what authors actually write', () {
    test('they-family answers read other FIRST — before any girl-word', () {
      expect(normalizeCharacterSex('nonbinary female'), kSexOther);
      expect(normalizeCharacterSex('they'), kSexOther);
      expect(normalizeCharacterSex('Futanari'), kSexOther);
      expect(normalizeCharacterSex('shapeshifter'), kSexOther);
      expect(normalizeCharacterSex('x'), kSexOther);
    });

    test(
      'female is found before male — "female" is not swallowed by "male"',
      () {
        expect(normalizeCharacterSex('female'), kSexFemale);
        expect(normalizeCharacterSex('FEMALE'), kSexFemale);
        expect(normalizeCharacterSex('a female elf woman'), kSexFemale);
        expect(
          normalizeCharacterSex('male, she/her'),
          kSexFemale,
          reason: 'pronouns follow the stated sex, not the first word',
        );
        expect(normalizeCharacterSex('f'), kSexFemale);
      },
    );

    test('male reads male, bare letters read as words', () {
      expect(normalizeCharacterSex('male'), kSexMale);
      expect(normalizeCharacterSex('he/him'), kSexMale);
      expect(normalizeCharacterSex('m'), kSexMale);
      expect(normalizeCharacterSex('  '), '', reason: 'blank is silence');
      expect(normalizeCharacterSex(''), '');
      expect(normalizeCharacterSex(null), '');
    });

    test('anything else non-blank is other, never a throw', () {
      expect(normalizeCharacterSex('22'), kSexOther);
      expect(normalizeCharacterSex('glitch ♥'), kSexOther);
    });
  });

  group('chargen suggests, the author decides', () {
    test('multi-capacity signals suggest the gate, reserved the long lock', () {
      expect(
        suggestRecoveryPreset(intimateInto: ['insatiable, always ready']),
        'none',
      );
      expect(suggestRecoveryPreset(intimateInto: ['slow to warm up']), 'long');
      expect(
        suggestRecoveryPreset(
          intimateInto: ['cuddling'],
          intimateNotInto: ['low sex drive things'],
        ),
        'long',
        reason: 'the not-into list carries signals too',
      );
    });

    test('mixed or silent signal nothing', () {
      expect(
        suggestRecoveryPreset(intimateInto: ['insatiable', 'but slow to warm']),
        isNull,
        reason: 'both signals is no signal — stay silent, do not guess',
      );
      expect(suggestRecoveryPreset(intimateInto: ['reading']), isNull);
      expect(suggestRecoveryPreset(intimateInto: []), isNull);
    });

    test('the suggestion line names the preset and says what it overrides', () {
      expect(recoverySuggestionLine(null), isNull);
      final line = recoverySuggestionLine('none')!;
      expect(line, contains('"None / multiorgasmic"'));
      expect(line, contains('overrides the personality judge'));
    });
  });

  group('the copy lines tell the truth about the engine', () {
    test('auto with no sex says it is today\'s behavior', () {
      final line = recoveryResolvesLine(const RecoveryProfile(), '');
      expect(line, contains('Auto → hard lock (no structured sex'));
      expect(line, contains('length by the personality judge'));
    });

    test('auto by sex names the physiology it read', () {
      expect(
        recoveryResolvesLine(const RecoveryProfile(), 'female'),
        contains('Auto → soft gate (card says female)'),
      );
      expect(
        recoveryResolvesLine(const RecoveryProfile(), 'male'),
        contains('Auto → hard lock (card says male)'),
      );
    });

    test('a fixed length says it replaces the judge', () {
      final line = recoveryResolvesLine(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 90,
        ),
        'male',
      );
      expect(line, contains('Hard lock'));
      expect(line, contains('90 min fixed (replaces the judge\'s number)'));
    });

    test('the soft gate admits it behaves as hard until PR 3', () {
      final line = recoveryResolvesLine(
        const RecoveryProfile(recoveryMode: kRecoveryModeSoft),
        'female',
      );
      expect(line, contains('Soft gate'));
      expect(
        line,
        contains('until soft-gate mechanics'),
        reason: 'no promised physics the engine does not have yet',
      );
    });

    test('the clock-off hint quantizes at the reply floor', () {
      expect(recoveryClockOffHint(90), contains('90 min ≈ 6 replies'));
      expect(recoveryClockOffHint(30), contains('2 replies'));
      expect(
        recoveryClockOffHint(null),
        contains('each reply of theirs is 15'),
      );
    });

    test('the duplicated per-turn constant cannot drift', () {
      expect(kRefractoryMinutesPerTurnHint, kRefractoryMinutesPerTurn);
    });
  });
}
