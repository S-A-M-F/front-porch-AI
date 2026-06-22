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

// Golden snapshot of CharacterCard V2.5 serialization. Character Card Forge and
// other external tools read/write this shape via raw SQL/JSON; a silent change
// to the exported structure (renamed key, dropped field, changed default) would
// break interop. This freezes the on-disk shape so it can't drift unnoticed.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';

import '../golden_harness.dart';

void main() {
  test('V2.5 card with realism extensions serializes to a stable shape', () {
    final card = CharacterCard(
      name: 'Test Character',
      description: '{{char}} is a fixture used to lock serialization.',
      personality: 'Methodical, deterministic.',
      scenario: '{{user}} opens a test harness.',
      firstMessage: 'Hello, {{user}}.',
      mesExample: '{{user}}: Hi\n{{char}}: Hi back.',
      systemPrompt: 'Stay in character.',
      postHistoryInstructions: 'Be concise.',
      alternateGreetings: const ['A second greeting.'],
      tags: const ['fixture', 'golden'],
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: true,
        stableId: 'fixture-stable-id',
        dayCount: 3,
        timeOfDay: 'evening',
        characterEmotion: 'curiosity',
        emotionIntensity: 'moderate',
        needsSimEnabled: true,
      ),
    );
    expectGoldenJson(card.toJson(), group: 'card', name: 'v25_full');
  });
}
