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

// Regression goldens for commit 8a0844f — the "AI character" bug:
//   1) AI-generated cards baked the literal character NAME into description/
//      personality/scenario instead of the portable {{char}} macro, confusing
//      the chat model mid-conversation.
//   2) Thinking models returned think-only streams; the greeting was silently
//      dropped to an empty first message.
// These tests lock the deterministic normalization (applyCharMacro /
// applyCharMacroToCard) and the think-only detection (stripThinkBlocks) that
// fixed both, so the failure can never silently return.

import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chargen/char_macro.dart';

import '../golden_harness.dart';

void main() {
  group('applyCharMacro — literal name -> {{char}} (row 1)', () {
    test('single-word name replaced, case-insensitive', () {
      const name = 'Rachel';
      final input = [
        'Rachel is brave and clever.',
        'rachel laughed; RACHEL frowned.',
        'Everyone trusts Rachel.',
      ].join('\n');
      expectGolden(applyCharMacro(input, name),
          group: 'chargen', name: 'macro_single_word');
    });

    test('multi-word name caught whole and by 3+char parts', () {
      const name = 'Mary Jane Watson';
      final input = [
        'Mary Jane Watson smiled.',
        'Mary waved while Jane spoke.',
        'Watson is the surname; Mary alone also matches.',
      ].join('\n');
      expectGolden(applyCharMacro(input, name),
          group: 'chargen', name: 'macro_multi_word');
    });

    test('word boundary — substrings and short parts are NOT clobbered', () {
      // Name "Ann" must not touch "Anna"/"announce"; a <3 char part like "Jo"
      // from "Jo Li" must not replace "Joe"/"John".
      expect(applyCharMacro('Anna announced to Ann.', 'Ann'),
          'Anna announced to {{char}}.');
      final input = [
        'Jo Li arrived. Joe and John waved at Jo.',
        'Li is two letters too — left intact inside "police".',
      ].join('\n');
      expectGolden(applyCharMacro(input, 'Jo Li'),
          group: 'chargen', name: 'macro_word_boundary');
    });

    test('empty/whitespace name is a no-op', () {
      const input = 'Some text mentioning nobody in particular.';
      expect(applyCharMacro(input, ''), input);
      expect(applyCharMacro(input, '   '), input);
    });

    test('text already using {{char}} is left unchanged', () {
      const input = '{{char}} greets {{user}} warmly.';
      expect(applyCharMacro(input, 'Rachel'), input);
    });
  });

  group('applyCharMacroToCard — all six fields normalized (row 4)', () {
    test('every generated text field is macro-normalized', () {
      final card = CharacterCard(
        name: 'Elena Voss',
        description: 'Elena Voss is a tactician. Elena plans everything.',
        personality: 'Voss is cold but loyal.',
        scenario: 'You meet Elena at the docks.',
        firstMessage: '"You\'re late," Elena says, eyeing {{user}}.',
        mesExample: '{{user}}: Hi\n{{char}}: Elena nods at you.',
        alternateGreetings: [
          'Elena leans against the wall.',
          'Voss does not look up.',
        ],
      );
      applyCharMacroToCard(card, card.name);
      expectGoldenJson({
        'description': card.description,
        'personality': card.personality,
        'scenario': card.scenario,
        'firstMessage': card.firstMessage,
        'mesExample': card.mesExample,
        'alternateGreetings': card.alternateGreetings,
      }, group: 'chargen', name: 'macro_card_fields');
    });
  });

  group('stripThinkBlocks — think-only detection (rows 2 & 3)', () {
    test('well-formed and fuzzy/unterminated blocks stripped to content', () {
      final cases = <String, String>{
        'wellFormed': '<think>plan the greeting</think>Hello there, traveller.',
        'fuzzyTag': '<thnk>oops</thnk>The fire crackles.',
        'unterminated': '<think>still reasoning with no close tag ever',
        'mixed': 'Before.<think>mid</think> After.',
        'noThink': 'Plain content, untouched.',
      };
      final out = {
        for (final e in cases.entries) e.key: stripThinkBlocks(e.value),
      };
      expectGoldenJson(out, group: 'chargen', name: 'strip_think_blocks');
    });

    test('think-only output is empty -> greeting guard treats it as failure', () {
      // This is the exact condition guarding the blank-first-message bug at
      // chargen/character_gen_llm.dart: `if (stripThinkBlocks(x).isNotEmpty)`.
      // Think-only must be empty so the retry loop fires instead of saving a
      // blank greeting.
      expect(stripThinkBlocks('<think>only reasoning, no answer</think>'), '');
      expect(stripThinkBlocks('<thinking>   </thinking>'), '');
      // A real greeting survives and is therefore accepted (non-empty).
      expect(stripThinkBlocks('<think>x</think>Welcome home.').isNotEmpty, isTrue);
    });
  });
}
