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

// The soft gate has no length (docs/design/afterglow-recovery-overhaul.md,
// decision 4): its tenderness window is fixed at ~15 story minutes. But the
// block's "always shown" slider parked at a neutral 90 MINUTES under
// "None / multiorgasmic" — a number the mode never uses — and dragging it
// called withMinutes(), which silently flips recoveryMode to a hard lock,
// yanking the card out of multiorgasmic by accident. Maintainer ruling
// 2026-10-18: the slider hides for that preset; a plain-English line takes
// its place. Auto and the locked presets keep it — there a length genuinely
// exists (the judge's) and the slider is the honest Custom shortcut.
// Mirrored in web_ui (RealismFormSection.tsx RecoveryBlock).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section/recovery_block.dart';

void main() {
  testWidgets('None / multiorgasmic hides the minutes slider and the '
      'judge-length hint, and says why instead', (tester) async {
    await tester.pumpWidget(
      _wrap(const RecoveryProfile(recoveryMode: kRecoveryModeSoft)),
    );

    expect(
      find.byKey(const Key('recovery-minutes-slider')),
      findsNothing,
      reason:
          'a slider parked at 90 min under a mode that has no length '
          'is a lie the author can drag into a hard lock',
    );
    expect(find.text('Recovery minutes'), findsNothing);
    expect(
      find.textContaining("judge's length"),
      findsNothing,
      reason: 'the judge decides no length on the soft gate',
    );
    final hint = tester.widget<Text>(
      find.byKey(const Key('recovery-clock-off-hint')),
    );
    expect(hint.data, contains('no length to set'));
    expect(hint.data, contains('~15 min tenderness window is fixed'));
  });

  testWidgets('hard presets keep the slider where it always was', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        const RecoveryProfile(
          recoveryMode: kRecoveryModeHard,
          recoveryMinutes: 90,
        ),
      ),
    );

    expect(find.byKey(const Key('recovery-minutes-slider')), findsOneWidget);
    expect(find.text('Recovery minutes'), findsOneWidget);
    expect(find.byKey(const Key('recovery-clock-off-hint')), findsOneWidget);
  });

  testWidgets('auto keeps the slider and the judge-length hint', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(RecoveryProfile.auto));

    expect(find.byKey(const Key('recovery-minutes-slider')), findsOneWidget);
    expect(
      find.textContaining('judge\'s length becomes'),
      findsOneWidget,
      reason: 'the old null-minutes hint still belongs to the judge presets',
    );
  });
}

Widget _wrap(RecoveryProfile recovery) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: RecoveryBlock(
        recovery: recovery,
        sex: 'female',
        intimateInto: const [],
        intimateNotInto: const [],
        onChanged: (_) {},
      ),
    ),
  ),
);
