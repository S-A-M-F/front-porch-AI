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

// Likes & Dislikes must SURVIVE both wires, and neither is hypothetical:
//
//   1. The card wire (CharacterCard.toJson / fromJson) — what ships in the PNG
//      and to The Stoop.
//   2. The web bridge (realism_extensions_json.dart) — what the web editor
//      reads and writes.
//
// The second is the one that has actually failed. When Ambitions became a chip
// editor, the bridge did not round-trip `ambitions` at all, so the web could
// neither read nor write them and the field silently vanished on any web save.
// Adding four more phrase lists to the same bridge without a guard would be
// asking for the same bug four more times.
//
// Cards also arrive from ANYWHERE — a PNG someone mailed you, a Stoop download,
// hand-edited JSON — so the malformed cases here are the real point, not
// padding. A wrong-typed field must yield an empty list, never throw and fail
// the whole import.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/web/util/realism_extensions_json.dart';

FrontPorchExtensions seeded() => FrontPorchExtensions(
  likes: ['being read to', 'thunderstorms'],
  dislikes: ['being interrupted'],
  intimateInto: ['slow mornings'],
  intimateNotInto: ['an audience'],
  ambitions: ['open her own bakery'],
  planLines: ['finish the log before the tide'],
  occupation: 'lighthouse keeper',
  hours: 'dawn–dusk',
  occupationBrief: 'Keeps the lamp and logs the ships',
);

void main() {
  group('the card wire', () {
    test('all four lists survive toJson -> fromJson', () {
      final back = FrontPorchExtensions.fromJson(seeded().toJson());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.dislikes, ['being interrupted']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.intimateNotInto, ['an audience']);
      expect(back.ambitions, ['open her own bakery'], reason: 'not regressed');
      expect(back.planLines, ['finish the log before the tide']);
      expect(back.occupation, 'lighthouse keeper');
      expect(back.hours, 'dawn–dusk');
      expect(back.occupationBrief, 'Keeps the lamp and logs the ships');
    });

    test('occupation and hours omitted JSON reads as empty, not null', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.occupation, '');
      expect(back.hours, '');
      expect(back.occupationBrief, '');
      expect(back.workDays, isNull);
    });

    test('blank occupation and hours are omitted from card JSON', () {
      final realism =
          FrontPorchExtensions().toJson()['realism_engine']
              as Map<String, dynamic>;
      expect(realism.containsKey('occupation'), isFalse);
      expect(realism.containsKey('hours'), isFalse);
      expect(realism.containsKey('occupationBrief'), isFalse);
    });

    test('occupation and hours survive the card wire', () {
      final ext = FrontPorchExtensions(
        occupation: 'lighthouse keeper',
        hours: 'dawn–dusk',
        occupationBrief: 'Keeps the lamp and logs the ships',
      );
      final json = ext.toJson();
      final realism = json['realism_engine'] as Map<String, dynamic>;
      expect(realism['occupation'], 'lighthouse keeper');
      expect(realism['hours'], 'dawn–dusk');
      expect(realism['occupationBrief'], 'Keeps the lamp and logs the ships');
      expect(realism.containsKey('occupation_brief'), isFalse);
      expect(realism.containsKey('workDays'), isFalse);
      final back = FrontPorchExtensions.fromJson(json);
      expect(back.occupation, 'lighthouse keeper');
      expect(back.hours, 'dawn–dusk');
      expect(back.occupationBrief, 'Keeps the lamp and logs the ships');
      expect(back.workDays, isNull);
    });

    test('workDays survive the card wire and [] is not collapsed', () {
      final weekdays = FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
        workDays: const [1, 2, 3, 4, 5],
      );
      final realism =
          weekdays.toJson()['realism_engine'] as Map<String, dynamic>;
      expect(realism['workDays'], [1, 2, 3, 4, 5]);
      expect(FrontPorchExtensions.fromJson(weekdays.toJson()).workDays, [
        1,
        2,
        3,
        4,
        5,
      ]);

      final off = FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
        workDays: const [],
      );
      expect(
        (off.toJson()['realism_engine'] as Map<String, dynamic>)['workDays'],
        isEmpty,
      );
      expect(FrontPorchExtensions.fromJson(off.toJson()).workDays, isEmpty);

      final noHours = FrontPorchExtensions(
        occupation: 'clerk',
        workDays: const [1, 2, 3, 4, 5],
      );
      expect(
        (noHours.toJson()['realism_engine'] as Map<String, dynamic>)
            .containsKey('workDays'),
        isFalse,
      );
    });

    test('plan_lines omitted JSON reads as empty, not null', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.planLines, isEmpty);
    });

    test('plan_lines survive the card wire', () {
      final ext = FrontPorchExtensions(
        planLines: ['finish the log before the tide'],
      );
      final json = ext.toJson();
      final realism = json['realism_engine'] as Map<String, dynamic>;
      expect(realism['plan_lines'], ['finish the log before the tide']);
      expect(FrontPorchExtensions.fromJson(json).planLines, [
        'finish the log before the tide',
      ]);
    });

    test(
      'the 18+ pair travels nested, so a share can strip it as one object',
      () {
        final realism =
            seeded().toJson()['realism_engine'] as Map<String, dynamic>;
        expect(realism['intimate_preferences'], {
          'into': ['slow mornings'],
          'not_into': ['an audience'],
        });
        // ...and is NOT smuggled into the everyday lists.
        expect(realism['likes'], isNot(contains('slow mornings')));
      },
    );

    test('a card with no preferences at all reads as empty, not null', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.likes, isEmpty);
      expect(back.dislikes, isEmpty);
      expect(back.intimateInto, isEmpty);
      expect(back.intimateNotInto, isEmpty);
    });

    test('blank and non-string entries are dropped, not carried', () {
      final back = FrontPorchExtensions.fromJson(const {
        'realism_engine': {
          'likes': ['  thunderstorms  ', '', '   ', 42, null, true],
        },
      });
      expect(back.likes, ['thunderstorms']);
    });

    test('a malformed list never throws — the whole import must not fail', () {
      for (final junk in <Object>[
        'being read to', // a bare string where a list belongs
        7,
        {'a': 1},
      ]) {
        expect(
          () => FrontPorchExtensions.fromJson({
            'realism_engine': {'likes': junk, 'dislikes': junk},
          }),
          returnsNormally,
          reason: 'junk: $junk',
        );
      }
    });

    test('a malformed intimate_preferences object never throws', () {
      for (final junk in <Object>['nope', 3, <String>[]]) {
        final back = FrontPorchExtensions.fromJson({
          'realism_engine': {'intimate_preferences': junk},
        });
        expect(back.intimateInto, isEmpty, reason: 'junk: $junk');
        expect(back.intimateNotInto, isEmpty);
      }
    });

    // Recovery overhaul PR 2 (docs/design/afterglow-recovery-overhaul.md):
    // structured sex + the recovery profile are additive card keys — a Stoop
    // card must not lose its profile through a PNG, and a card that never had
    // them must read as today's behavior (auto / no sex), not garbage.
    test('sex and the recovery profile survive the card wire', () {
      final ext = FrontPorchExtensions(
        sex: 'female',
        recovery: const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 45,
        ),
      );
      final realism = ext.toJson()['realism_engine'] as Map<String, dynamic>;
      expect(realism['sex'], 'female');
      expect(realism['recovery'], {'mode': 'hard', 'minutes': 45});
      final back = FrontPorchExtensions.fromJson(ext.toJson());
      expect(back.sex, 'female');
      expect(back.recovery.recoveryMode, 'hard');
      expect(back.recovery.recoveryMinutes, 45);
    });

    test('a default profile and blank sex are omitted — old cards stay byte-stable', () {
      final realism =
          FrontPorchExtensions().toJson()['realism_engine']
              as Map<String, dynamic>;
      expect(realism.containsKey('sex'), isFalse);
      expect(realism.containsKey('recovery'), isFalse);
    });

    test('a card without the new keys reads as auto — exactly today', () {
      final back = FrontPorchExtensions.fromJson(const {'realism_engine': {}});
      expect(back.sex, '');
      expect(back.recovery.recoveryMode, kRecoveryModeAuto);
      expect(back.recovery.recoveryMinutes, isNull);
      expect(back.recovery.isDefault, isTrue);
    });

    test('sex is read leniently and stored normalized', () {
      final back = FrontPorchExtensions.fromJson(const {
        'realism_engine': {'sex': ' Woman '},
      });
      expect(back.sex, 'female');
      final junk = FrontPorchExtensions.fromJson(const {
        'realism_engine': {'sex': 42},
      });
      expect(junk.sex, kSexOther);
    });

    test('a malformed recovery object never fails the import', () {
      for (final junk in <Object>['nope', 3, ['hard']]) {
        final back = FrontPorchExtensions.fromJson({
          'realism_engine': {'recovery': junk},
        });
        expect(back.recovery.isDefault, isTrue, reason: 'junk: $junk');
      }
      // A length on a mode that carries none is dropped, not kept-as-a-lie.
      final softFixed = FrontPorchExtensions.fromJson(const {
        'realism_engine': {
          'recovery': {'mode': 'soft', 'minutes': 30},
        },
      });
      expect(softFixed.recovery.recoveryMode, kRecoveryModeSoft);
      expect(softFixed.recovery.recoveryMinutes, isNull);
    });
  });

  group('the web bridge', () {
    test('all four lists survive extensions -> json -> extensions', () {
      final back = frontPorchFromFields(frontPorchToJson(seeded()));
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.dislikes, ['being interrupted']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.intimateNotInto, ['an audience']);
      expect(back.planLines, ['finish the log before the tide']);
      expect(back.occupation, 'lighthouse keeper');
      expect(back.hours, 'dawn–dusk');
      expect(back.occupationBrief, 'Keeps the lamp and logs the ships');
    });

    test('workDays survive the web bridge, including empty', () {
      final seededDays = FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
        workDays: const [1, 2, 3, 4, 5, 6],
      );
      expect(frontPorchFromFields(frontPorchToJson(seededDays)).workDays, [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
      final off = FrontPorchExtensions(
        occupation: 'clerk',
        hours: '9am–5pm',
        workDays: const [],
      );
      expect(frontPorchFromFields(frontPorchToJson(off)).workDays, isEmpty);
      expect(frontPorchFromFields(const {}, base: seededDays).workDays, [
        1,
        2,
        3,
        4,
        5,
        6,
      ]);
    });

    test('an older web client that omits the keys keeps the base values', () {
      // The exact shape of the ambitions bug: a payload without the key must
      // fall back to what the card already had, NOT wipe it.
      final back = frontPorchFromFields(const {}, base: seeded());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.intimateInto, ['slow mornings']);
      expect(back.planLines, ['finish the log before the tide']);
      expect(back.occupation, 'lighthouse keeper');
      expect(back.hours, 'dawn–dusk');
      expect(back.occupationBrief, 'Keeps the lamp and logs the ships');
    });

    test('a client sending junk falls back rather than throwing', () {
      final back = frontPorchFromFields(const {
        'likes': 'being read to',
        'intimateInto': 5,
      }, base: seeded());
      expect(back.likes, ['being read to', 'thunderstorms']);
      expect(back.intimateInto, ['slow mornings']);
    });

    // Recovery overhaul PR 2 — the data-loss trap that ate `inventory`:
    // any field missing from the bridge constructor silently takes its
    // default on every phone save. `sex` + `recovery` nest/read with the
    // base as fallback, and a save that touches neither keeps both.
    test('sex and recovery survive extensions -> json -> extensions', () {
      final ext = FrontPorchExtensions(
        sex: 'male',
        recovery: const RecoveryProfile(recoveryMode: kRecoveryModeHard, recoveryMinutes: 30),
      );
      final back = frontPorchFromFields(frontPorchToJson(ext));
      expect(back.sex, 'male');
      expect(back.recovery.recoveryMode, kRecoveryModeHard);
      expect(back.recovery.recoveryMinutes, 30);
    });

    test('a web edit that does not touch them keeps them', () {
      final base = FrontPorchExtensions(
        sex: 'female',
        recovery: const RecoveryProfile(recoveryMode: kRecoveryModeSoft),
      );
      // A phone changing the description posts a realism block without
      // either key — the exact shape that wiped starting inventory.
      final back = frontPorchFromFields(const {'currentTask': 'fixed'}, base: base);
      expect(back.sex, 'female');
      expect(back.recovery.recoveryMode, kRecoveryModeSoft);
      expect(back.currentTask, 'fixed');
    });

    test('a web sex edit is normalized on the way in, junk keeps nothing false', () {
      final back = frontPorchFromFields(const {'sex': 'FEMALE ELF'}, base: seeded());
      expect(back.sex, 'female');
      final junk = frontPorchFromFields(const {'recovery': 'multi'}, base: FrontPorchExtensions(
        recovery: const RecoveryProfile(recoveryMode: kRecoveryModeHard, recoveryMinutes: 90),
      ));
      expect(junk.recovery.recoveryMinutes, 90,
          reason: 'an unusable payload falls back to the base, like inventory');
    });
  });
}
