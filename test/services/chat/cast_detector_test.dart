// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Tests for CastDetector (Scene Guests Phase 2 — recurring named side-character
// detection leaf). The detector is pure orchestration over injected closures,
// so the whole surface is unit-coverable: strict-JSON parse (incl. fenced /
// prose-wrapped / {"name": null}), the host/user/existing-guest/already-offered
// filters, the proper-name plausibility check, and null-on-empty (the KoboldCPP
// empty-eval gotcha). It must NEVER fire a second LLM-firing path — it only uses
// the injected fireLLMEval/stripThinkBlocks delegates.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/cast_detector.dart';

void main() {
  group('CastDetector', () {
    late List<String> primaryTexts;
    late List<String> guestNames;
    late Set<String> offeredOrIgnored;
    String? eval; // canned LLM reply (null = empty/backend down)
    int fireCount = 0;

    CastDetector build({String host = 'Aria', String user = 'You'}) {
      return CastDetector(
        getRecentPrimaryTexts: () => primaryTexts,
        fireLLMEval: (prompt) async {
          fireCount++;
          return eval;
        },
        stripThinkBlocks: (t) => t
            .replaceAll(RegExp(r'<think>.*?</think>', dotAll: true), '')
            .trim(),
        getHostName: () => host,
        getUserName: () => user,
        getSceneGuestNames: () => guestNames,
        getOfferedOrIgnoredNames: () => offeredOrIgnored,
      );
    }

    setUp(() {
      primaryTexts = ['Aria waved as her sister Mara stepped onto the porch.'];
      guestNames = [];
      offeredOrIgnored = {};
      eval = '{"name": "Mara", "descriptor": "Aria\'s younger sister"}';
      fireCount = 0;
    });

    test('parses a valid candidate', () async {
      final r = await build().detect();
      expect(r, isNotNull);
      expect(r!.name, 'Mara');
      expect(r.descriptor, "Aria's younger sister");
      expect(fireCount, 1);
    });

    test('returns null when there is no narration (no LLM call)', () async {
      primaryTexts = ['   ', ''];
      final r = await build().detect();
      expect(r, isNull);
      expect(fireCount, 0, reason: 'must not fire the eval with no input');
    });

    test('null on empty / backend-down eval (KoboldCPP gotcha)', () async {
      eval = null;
      expect(await build().detect(), isNull);
      eval = '';
      expect(await build().detect(), isNull);
      eval = '   ';
      expect(await build().detect(), isNull);
    });

    test('null on {"name": null}', () async {
      eval = '{"name": null}';
      expect(await build().detect(), isNull);
    });

    test('null on unparseable / non-JSON output', () async {
      eval = 'There is no recurring character here.';
      expect(await build().detect(), isNull);
    });

    test('tolerates code fences and surrounding prose', () async {
      eval =
          'Sure!\n```json\n{"name": "Mara", "descriptor": "the sister"}\n```\nDone.';
      final r = await build().detect();
      expect(r?.name, 'Mara');
      expect(r?.descriptor, 'the sister');
    });

    test('strips think blocks before parsing', () async {
      eval =
          '<think>let me look</think>{"name": "Mara", "descriptor": "sister"}';
      expect((await build().detect())?.name, 'Mara');
    });

    test('rejects the host (collision either direction)', () async {
      eval = '{"name": "Aria", "descriptor": "the host"}';
      expect(await build().detect(), isNull);
      // First-name collision with a fuller host name.
      eval = '{"name": "Aria Vance", "descriptor": "x"}';
      expect(await build(host: 'Aria').detect(), isNull);
    });

    test('rejects the user', () async {
      eval = '{"name": "Sam", "descriptor": "the user"}';
      expect(await build(user: 'Sam').detect(), isNull);
    });

    test('rejects an existing scene guest (case-insensitive)', () async {
      guestNames = ['mara'];
      expect(await build().detect(), isNull);
    });

    test('dedup: rejects an already offered/ignored name', () async {
      offeredOrIgnored = {'mara'};
      expect(await build().detect(), isNull);
    });

    test('rejects an implausible (letterless) name', () async {
      eval = '{"name": "123", "descriptor": "x"}';
      expect(await build().detect(), isNull);
      eval = '{"name": "   ", "descriptor": "x"}';
      expect(await build().detect(), isNull);
    });

    test('accepts with an empty descriptor', () async {
      eval = '{"name": "Greaves"}';
      final r = await build().detect();
      expect(r?.name, 'Greaves');
      expect(r?.descriptor, '');
    });
  });
}
