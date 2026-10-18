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

// Orgasm detection must not be switchable-off by a model's choice of which
// fields to bother filling in.
//
// `is_climax` is the only signal that starts the post-orgasm refractory: nothing
// else in the app looks at the text. It was an OPTIONAL field in the needs-impact
// tool schema, and a model answering a tool call fills in what the schema demands
// and skips what it does not. So on every tools-capable backend the field simply
// never arrived, the verdict defaulted to false, and the Lust bar stayed pinned
// at 100/100 through an unmistakable climax — with no error, nothing in the log,
// and no way for a user to tell the feature had stopped working.
//
// Caught in real use. The model returned EXACTLY the eight required fields:
//
//   {"hunger_delta":80,"energy_delta":-40,"hygiene_delta":-15,"fun_delta":60,
//    "social_delta":55,"bladder_delta":0,"comfort_delta":45,
//    "reason":"Violet experiences her first orgasm ever ... an overwhelming
//              first climax that leaves her emotionally shattered ..."}
//
// It had understood the scene completely and said so in the reason. It just
// never emitted the key it was not obliged to emit.
//
// This is the same lesson the TEXT path already learned — see the climaxGuidance
// comment in llm_eval_engine.dart, "won't guess at an undefined field". The tools
// transport re-created the hole by a different route: defined, but optional.
//
// Two guards, because either alone can be undone:
//   1. the schema must REQUIRE the field, so the model has to answer;
//   2. the parse must still read the raw text when a parsed result lacks it, so
//      one backend ignoring `required` cannot switch the feature off again.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/climax_eval.dart';
import 'package:front_porch_ai/services/chat/reply_facts_eval.dart';
import 'package:front_porch_ai/services/chat/realism_tools.dart';
import 'package:front_porch_ai/services/llm_service.dart' show LlmToolCall;

List<String> _requiredOf(List<Map<String, dynamic>> tools) =>
    ((tools.single['function'] as Map)['parameters'] as Map)['required']
        as List<String>;

Map<String, dynamic> _propsOf(List<Map<String, dynamic>> tools) =>
    ((tools.single['function'] as Map)['parameters'] as Map)['properties']
        as Map<String, dynamic>;

void main() {
  group('the climax check must force a verdict', () {
    // REPOINTED 2026-08-07 from the needs-impact tool. Not because these
    // assertions became inconvenient — because they became FALSE. Climax moved
    // off the needs eval, which early-returns unless Needs is on, and Needs is
    // off on most cards (CharacterCard.needsSimEnabled defaults false), so
    // Afterglow silently did nothing for most users who switched it on. It now
    // has its own POST-GENERATION pass, gated on the Realism Engine and the
    // Afterglow switch alone.
    //
    // Every assertion below keeps its exact original meaning — that the verdict
    // is REQUIRED rather than optional (an optional field is never emitted, the
    // whole reason this file exists), that a loose string "true" still reads as
    // a climax, and that a tool call survives the trip to flat JSON. Only the
    // tool they are asked about changed.
    test('is_climax is required, not optional', () {
      expect(
        _requiredOf(ClimaxEval.tools),
        contains('is_climax'),
        reason:
            'optional means the model may skip it, and skipping reads as '
            '"no climax" — the refractory then never starts and Lust stays '
            'pinned at 100 forever',
      );
    });

    test('refractory_turns is required alongside it', () {
      // Answering "yes a climax happened" without saying for how long leaves
      // the cooldown length to a default, which is the same guess-the-undefined
      // problem one field along.
      expect(_requiredOf(ClimaxEval.tools), contains('refractory_turns'));
    });

    test('every required field actually exists in the schema', () {
      // A typo in the required list is worse than a missing entry: some
      // backends reject the whole tool, which would take the eval down rather
      // than just the climax verdict.
      final props = _propsOf(ClimaxEval.tools);
      for (final key in _requiredOf(ClimaxEval.tools)) {
        expect(
          props.containsKey(key),
          isTrue,
          reason: '"$key" is demanded but not defined',
        );
      }
    });

    test('a tool call carrying the verdict survives the trip to flat JSON', () {
      // The bridge only copies keys it recognises, so a boolean that the model
      // DID supply must not be dropped on the way through.
      final json = realismToolCallToJson(ClimaxEval.kClimaxTool, [
        LlmToolCall(
          name: ClimaxEval.kClimaxTool,
          arguments: const {
            'hunger_delta': 80,
            'energy_delta': -40,
            'hygiene_delta': -15,
            'fun_delta': 60,
            'social_delta': 55,
            'bladder_delta': 0,
            'comfort_delta': 45,
            'reason': 'first orgasm ever',
            'is_climax': true,
            'refractory_turns': 6,
          },
        ),
      ]);

      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as Map<String, dynamic>;
      expect(decoded['is_climax'], isTrue);
      expect(decoded['refractory_turns'], 6);
    });

    test('a string "true" from a loose backend still reads as a climax', () {
      // Some backends stringify every tool argument.
      final json = realismToolCallToJson(ClimaxEval.kClimaxTool, [
        LlmToolCall(
          name: ClimaxEval.kClimaxTool,
          arguments: const {'reason': 'came hard', 'is_climax': 'true'},
        ),
      ]);
      expect((jsonDecode(json!) as Map)['is_climax'], isTrue);
    });
  });

  // Recovery overhaul PR 5: `user_climaxed` rides the SAME verdict for
  // free. Same law as is_climax — defined, required, whitelisted, and
  // leniently parsed — or the mutual beat silently never exists.
  group('the mutual field rides the same verdict (PR 5)', () {
    test('user_climaxed is defined and required on the climax tool', () {
      final props =
          ((ClimaxEval.tools.single['function'] as Map)['parameters']
                  as Map)['properties']
              as Map;
      expect(props, contains('user_climaxed'));
      expect((props['user_climaxed'] as Map)['type'], 'boolean');
      expect(
        _requiredOf(ClimaxEval.tools),
        containsAll(['is_climax', 'refractory_turns', 'user_climaxed']),
        reason:
            'optional means never emitted — the exact hole that turned '
            'climax detection off on every tools-capable backend once',
      );
    });

    test(
      'the fused tool demands it only when the climax question is asked',
      () {
        final asked = kReplyFactsToolsFor(
          askClimax: true,
          askPockets: false,
          askPosture: false,
        );
        expect(_requiredOf(asked), contains('user_climaxed'));
        final silent = kReplyFactsToolsFor(
          askClimax: false,
          askPockets: true,
          askPosture: false,
        );
        expect(
          _requiredOf(silent),
          isNot(contains('user_climaxed')),
          reason: 'a disabled feature must not be demanded of the model',
        );
        expect(_requiredOf(silent), contains('inventory_ops'));
      },
    );

    test('the registry whitelist carries it — transport drops the rest', () {
      expect(
        realismToolFieldsByTool[ClimaxEval.kClimaxTool],
        contains('user_climaxed'),
      );
      expect(
        realismToolFieldsByTool[kReplyFactsToolName],
        contains('user_climaxed'),
        reason:
            'an unregistered tool or key is dropped and the feature falls '
            'back to text (or to nothing) on every tools backend, silently',
      );
    });

    test('the rubric and the text floor both ask for the flag', () {
      expect(ClimaxEval.rubric('Nia'), contains('user_climaxed'));
      expect(
        ClimaxEval.buildPrompt(
          charName: 'Nia',
          reply: 'x',
          recentExchange: '',
          toolsMode: false,
        ),
        contains('"user_climaxed"'),
        reason: 'the no-tools floor names every key or loose models skip it',
      );
      // Judge lanes are NOT macro-resolved (only generation blocks are):
      // a {{user}} token here would reach the model literally.
      expect(ClimaxEval.rubric('Nia'), isNot(contains('{{user}}')));
      expect(
        kClimaxFields['user_climaxed']!['description']!,
        isNot(contains('{{user}}')),
      );
    });

    test('parseUserClimaxed is lenient in, strict by absence', () {
      expect(ClimaxEval.parseUserClimaxed('{"user_climaxed":true}'), isTrue);
      expect(ClimaxEval.parseUserClimaxed('{"user_climaxed":"true"}'), isTrue);
      expect(ClimaxEval.parseUserClimaxed('{"user_climaxed":"yes"}'), isTrue);
      expect(ClimaxEval.parseUserClimaxed('{"user_climaxed":"Yes"}'), isTrue);
      expect(ClimaxEval.parseUserClimaxed('{"user_climaxed":false}'), isFalse);
      expect(
        ClimaxEval.parseUserClimaxed('{"is_climax":true,"refractory_turns":6}'),
        isFalse,
        reason: 'a missing key is never assumed — the mutual beat is opt-in',
      );
      expect(ClimaxEval.parseUserClimaxed('nonsense'), isFalse);
      expect(ClimaxEval.parseUserClimaxed(null), isFalse);
    });

    test('a real false field cannot be flipped by a later quote, '
        'nor a word match by half', () {
      // Hostile review M2: the sibling parseRefractory wins the FIRST
      // match so chatty codicils cannot flip a real verdict; a bare
      // hasMatch("true|yes") also let "yesterday" and "truest" read true.
      expect(
        ClimaxEval.parseUserClimaxed(
          '{"user_climaxed":false,"posture":"lying still — she wrote '
          '\\"user_climaxed\\": true would be wrong here"}',
        ),
        isFalse,
        reason: 'the real field is first; the quote is prose',
      );
      expect(
        ClimaxEval.parseUserClimaxed('{"user_climaxed":"yesterday"}'),
        isFalse,
      );
      expect(
        ClimaxEval.parseUserClimaxed('{"user_climaxed":"truest"}'),
        isFalse,
      );
    });

    test('the fused TEXT floor names the key too', () {
      // The tools lane is pinned by the required-list guards above; a
      // text-mode fused backend must be ASKED or the mutual beat silently
      // never exists there (hostile review M4).
      final asked = ReplyFactsEval.buildPrompt(
        charName: 'Nia',
        reply: 'x',
        recentExchange: '',
        toolsMode: false,
        askClimax: true,
      );
      // Target the flat-JSON keys list itself — the rubric already names
      // the key, so a bare contains() would pass without the floor.
      expect(asked, contains('"refractory_turns", "user_climaxed". '));
      final silent = ReplyFactsEval.buildPrompt(
        charName: 'Nia',
        reply: 'x',
        recentExchange: '',
        toolsMode: false,
        askClimax: false,
      );
      expect(
        silent,
        isNot(contains('"user_climaxed"')),
        reason: 'a disabled feature must not be asked of the model',
      );
    });
  });
}
