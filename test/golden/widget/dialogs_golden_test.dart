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

// Widget pixel goldens for dialog widgets pumped directly (not via
// showDialog) so they render inside pumpGolden's Scaffold body.
//
// Skipped dialogs:
//   _RocmGuidanceDialog     — private class, not directly pumpable
//   _LorebookEntryDialog    — private class, not directly pumpable
//
// Cases:
//   ByafImportDialog    — seeded preview (name + persona + first message)
//   StableDbImportDialog — const glassmorphic import prompt
//   TagDialog           — character with two existing tags; CharacterRepository
//                         is only read in _updateSuggestions (onChanged handler,
//                         never invoked during static golden) so no provider needed
//   UpdateDialog        — prompt stage (downloadComplete=false, downloading=false);
//                         FakeUpdateService supplied via ChangeNotifierProvider

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/byaf_service.dart';
import 'package:front_porch_ai/services/update_service.dart';
import 'package:front_porch_ai/ui/dialogs/byaf_import_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/stable_db_import_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

void main() {
  setupPathProviderMock();

  testWidgets('ByafImportDialog — seeded preview', (tester) async {
    final preview = ByafImportPreview(
      name: 'Aria Vale',
      persona:
          'A lighthouse keeper on a wind-scoured cape. She keeps her own '
          'counsel and speaks only when words carry weight.',
      firstMessage:
          'The lantern room is cold tonight. You climb the last spiral '
          'step and find her waiting, charts spread across the iron floor.',
      loreItems: const [],
      messages: const [],
    );

    await expectThemedGoldens(
      tester,
      child: ByafImportDialog(preview: preview),
      group: 'dialogs',
      name: 'byaf_import',
      surface: const Size(580, 680),
    );
  });

  testWidgets('StableDbImportDialog — glassmorphic prompt', (tester) async {
    await expectThemedGoldens(
      tester,
      child: const StableDbImportDialog(),
      group: 'dialogs',
      name: 'stable_db_import',
      surface: const Size(620, 800),
    );
  });

  testWidgets('TagDialog — character with existing tags', (tester) async {
    final character = CharacterCard(
      name: 'Dex Marlowe',
      description: 'A retired detective with sharp eyes and old debts.',
      tags: ['detective', 'noir', 'mystery'],
    );

    await expectThemedGoldens(
      tester,
      child: TagDialog(character: character),
      group: 'dialogs',
      name: 'tag_dialog',
      surface: const Size(520, 500),
    );
  });

  testWidgets('UpdateDialog — prompt stage', (tester) async {
    final updateService = FakeUpdateService(
      updateAvailable: true,
      latestVersion: '0.9.1',
      releaseNotes:
          '## What\'s New\n- Realism Engine improvements\n- Bug fixes',
    );
    addTearDown(updateService.dispose);

    await expectThemedGoldens(
      tester,
      child: ChangeNotifierProvider<UpdateService>.value(
        value: updateService,
        child: const UpdateDialog(),
      ),
      group: 'dialogs',
      name: 'update_dialog_prompt',
      surface: const Size(620, 720),
    );
  });
}
