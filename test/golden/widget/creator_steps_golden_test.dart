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

// Widget pixel goldens for the AI Character Creator WIZARD SCREENS.
//
// Companion to creator_engine_golden_test.dart (which locks the engine
// behavior). The June-6 "Stage 4" refactor didn't only stub the engine — it
// also gutted these config/realism screens to bare placeholders (see
// .claude/changelog.md "rebuilt all 5 gutted step screens [Phase 2 of 3]"): the
// concept field, mode cards, and realism form all vanished or went no-op. A
// pixel golden of each screen freezes the restored layout so a regression back
// to placeholders fails loudly here.
//
// These render statically from a seeded CreatorState — the steps only reach for
// Provider inside button callbacks, which never fire during a static pump. The
// Review screen is covered separately (its avatar panel needs a live LLMProvider
// whose readiness probe is incompatible with a static golden — see COVERAGE.md).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/steps/mode_select_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/quick_config_step.dart';
import 'package:front_porch_ai/ui/character_creator/steps/realism_step.dart';

import '../support/golden_app.dart';

/// A deterministically seeded CreatorState with a generated card, so the realism
/// screen renders its real form (not the empty/error fallback).
CreatorState _seedState() {
  final state = CreatorState();
  state.creatorMode = CreatorMode.quick;
  state.nameController.text = 'Aria Vale';
  state.conceptController.text =
      'A lighthouse keeper who collects shipwreck tales.';
  state.realismStepEnabled = true;
  state.realismNeedsSim = true;

  final card = CharacterCard(
    name: 'Aria Vale',
    description: '{{char}} is a lighthouse keeper on a wind-scoured cape.',
    personality: 'Patient, observant, dry-humored.',
    scenario: '{{user}} climbs the tower stairs at dusk.',
    firstMessage: 'The lamp turns. "You came, {{user}}."',
    lorebook: Lorebook(entries: [
      LorebookEntry(key: 'lighthouse', content: 'The lamp never goes dark.'),
      LorebookEntry(key: 'storm', content: 'A wreck washed in last winter.'),
    ]),
  );
  state.generatedCard = card;
  state.descController.text = card.description;
  state.personalityController.text = card.personality;
  state.scenarioController.text = card.scenario;
  state.firstMessageController.text = card.firstMessage;
  state.lorebookEntryEnabled = {0: true, 1: true};
  return state;
}

void main() {
  testWidgets('ModeSelectStep — three mode cards', (tester) async {
    final state = _seedState();
    addTearDown(state.dispose);
    await expectThemedGoldens(
      tester,
      child:
          SizedBox(width: 900, height: 760, child: ModeSelectStep(state: state)),
      group: 'creator_steps',
      name: 'mode_select',
      surface: const Size(940, 800),
    );
  });

  testWidgets('QuickConfigStep — concept + options form', (tester) async {
    final state = _seedState();
    addTearDown(state.dispose);
    await expectThemedGoldens(
      tester,
      child: SizedBox(
        width: 760,
        height: 1100,
        child: SingleChildScrollView(child: QuickConfigStep(state: state)),
      ),
      group: 'creator_steps',
      name: 'quick_config',
      surface: const Size(800, 1140),
    );
  });

  testWidgets('RealismStep — realism/needs form (not a no-op stub)',
      (tester) async {
    final state = _seedState();
    addTearDown(state.dispose);
    await expectThemedGoldens(
      tester,
      child:
          SizedBox(width: 820, height: 1100, child: RealismStep(state: state)),
      group: 'creator_steps',
      name: 'realism',
      surface: const Size(860, 1140),
    );
  });
}
