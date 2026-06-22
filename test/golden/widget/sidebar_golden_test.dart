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

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for the chat sidebar sections — the first surface driven
// by the shared timer-free `FakeChatService`. Each section is a focused,
// character-behavior-facing panel; freezing them in light + dark locks the chat
// sidebar against UI regressions. Sections are added here as the fake grows to
// cover their `ChatService` read surface (see COVERAGE.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/chat_components/sidebar/scene_time_section.dart';

import '../support/fakes.dart';
import '../support/golden_app.dart';

void main() {
  testWidgets('SceneTimeSection — evening, day 3', (tester) async {
    final chat = FakeChatService(timeOfDay: 'evening', dayCount: 3);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 300, child: SceneTimeSection(chat: chat)),
      group: 'sidebar',
      name: 'scene_time_evening',
      surface: const Size(340, 120),
    );
  });

  testWidgets('SceneTimeSection — dawn, day 1', (tester) async {
    final chat = FakeChatService(timeOfDay: 'dawn', dayCount: 1);
    addTearDown(chat.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(width: 300, child: SceneTimeSection(chat: chat)),
      group: 'sidebar',
      name: 'scene_time_dawn',
      surface: const Size(340, 120),
    );
  });
}
