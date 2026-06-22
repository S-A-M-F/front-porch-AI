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

// Golden snapshots for the brittle JSON scalar extraction that turns raw LLM
// eval responses into bond/trust/emotion/needs deltas. The LLM call itself is
// nondeterministic, but the PARSE step is pure — these lock its behavior across
// valid, malformed, negative, missing, and whitespace-padded inputs so a regex
// change can't silently misread a character's realism deltas. Reuses
// createTestLlmEvalEngine from the existing llm_eval_engine_test.

import 'package:flutter_test/flutter_test.dart';

import '../golden_harness.dart';
import '../../services/chat/llm_eval_engine_test.dart'
    show createTestLlmEvalEngine;

void main() {
  test('extractJsonInt across representative inputs', () {
    final e = createTestLlmEvalEngine();
    const cases = <String, String>{
      'positive': '{"bond_delta": 15}',
      'negative': '{"bond_delta": -20}',
      'padded': '{ "bond_delta" :   7 }',
      'amongOthers': '{"trust_delta": 3, "bond_delta": 9}',
      'missing': '{"trust_delta": 3}',
      'thinkPrefixed': '<think>reasoning</think>{"bond_delta": 4}',
      'malformedNoValue': '{"bond_delta": }',
      'substringKeyNotMatched': '{"long_bond_delta": 99}',
    };
    final out = {
      for (final c in cases.entries)
        c.key: e.extractJsonInt(c.value, 'bond_delta'),
    };
    expectGoldenJson(out, group: 'realism', name: 'extract_json_int');
  });

  test('extractJsonBool across representative inputs', () {
    final e = createTestLlmEvalEngine();
    const cases = <String, String>{
      'true': '{"is_climax": true}',
      'false': '{"is_climax": false}',
      'padded': '{ "is_climax" :  true }',
      'missing': '{"other": true}',
      'nonBoolValue': '{"is_climax": 1}',
    };
    final out = {
      for (final c in cases.entries)
        c.key: e.extractJsonBool(c.value, 'is_climax'),
    };
    expectGoldenJson(out, group: 'realism', name: 'extract_json_bool');
  });
}
