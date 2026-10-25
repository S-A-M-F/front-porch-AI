// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The model downloader's "Model card": a repo's README, cleaned so desktop
// and the PWA can render it safely (no front matter, no HTML, prompt-format
// code kept verbatim), its facts, and the jump to the original model a quant
// was made from. The live group asks HuggingFace and skips unless
// FPAI_HF_LIVE is set.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/hf_readme.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:front_porch_ai/ui/widgets/hf_readme_dialog.dart';

void main() {
  group('HfReadme.clean', () {
    test('drops front matter, scripts, styles and comments', () {
      final out = HfReadme.clean(
        '---\nlicense: apache-2.0\ntags:\n- roleplay\n---\n'
        '<style>.x{color:red}</style><!-- hidden -->'
        '# Dark Scarlett\n<script>alert(1)</script>Passion ignited.',
      );
      expect(out, '# Dark Scarlett\nPassion ignited.');
    });

    test('turns HTML pictures and links into markdown links, and strips '
        'the rest of the markup', () {
      final out = HfReadme.clean(
        '<div align="center"><img src="https://cdn.example/banner.png" '
        'alt="Banner"></div>\n'
        '<p>See <a href="https://huggingface.co/x/y">the <b>original</b></a>'
        '&nbsp;&amp; more</p>\n![shot](https://cdn.example/s.png)',
      );
      expect(out, contains('[image: Banner](https://cdn.example/banner.png)'));
      expect(
        out,
        contains('See [the original](https://huggingface.co/x/y) & more'),
      );
      expect(out, contains('[image: shot](https://cdn.example/s.png)'));
      expect(out, isNot(contains('<')));
    });

    test('code keeps its angle brackets: prompt formats live there', () {
      const prompt =
          '```\n<start_of_turn>user\n{prompt}<end_of_turn>\n'
          '<start_of_turn>model\n```';
      final out = HfReadme.clean(
        '## Prompt format\n$prompt\nUse `<|im_start|>` too.',
      );
      expect(out, contains(prompt));
      expect(out, contains('`<|im_start|>`'));
    });

    test('indentation left by removed HTML is not read as a code block, '
        'nested list items keep theirs', () {
      final out = HfReadme.clean(
        '<div>\n        NSFW\n        ERP\n</div>\n- top\n    - nested',
      );
      expect(out, startsWith('NSFW\nERP\n'));
      expect(out, contains('    - nested'));
    });
  });

  group('Model card dialog', () {
    const quant = HfReadme(
      repoId: 'mradermacher/Qwen3.8-27B-Dominatrix-GGUF',
      markdown: '## About\n\nstatic quants of the original',
      license: 'apache-2.0',
      baseModels: ['allura-org/Qwen3.8-27B-Dominatrix'],
    );
    const original = HfReadme(
      repoId: 'allura-org/Qwen3.8-27B-Dominatrix',
      markdown: '# Dominatrix\n\nA roleplay tune.',
    );

    Future<List<String>> open(WidgetTester tester) async {
      final asked = <String>[];
      Future<HfReadme> load(String id) async {
        asked.add(id);
        return id == quant.repoId ? quant : original;
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showHfReadme(context, repoId: quant.repoId, load: load),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return asked;
    }

    testWidgets('shows the card, its facts, and goes through to the '
        'original and back', (tester) async {
      final asked = await open(tester);
      expect(
        find.textContaining('static quants of the original'),
        findsOneWidget,
      );
      expect(find.text('Licence: apache-2.0'), findsOneWidget);

      await tester.tap(
        find.text('Original: allura-org/Qwen3.8-27B-Dominatrix'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('A roleplay tune.'), findsOneWidget);
      expect(asked, [quant.repoId, original.repoId]);

      await tester.tap(find.byIcon(Icons.arrow_back_rounded));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('static quants of the original'),
        findsOneWidget,
      );
    });

    testWidgets('a gated card says how to read it', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HfReadmeView(
              repoId: 'google/gemma-3-27b-it',
              load: (id) async =>
                  HfReadme(repoId: id, problem: HfFilesProblem.gated),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Gated repo'), findsOneWidget);
    });

    testWidgets('the result card\'s Model card button names its repo', (
      tester,
    ) async {
      String? shown;
      final model = HFModel(id: quant.repoId, author: 'mradermacher');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HFModelCard(
                model: model,
                availableVramMb: 0,
                onDownload: (_) {},
                onShowModelCard: (id) => shown = id,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(model.name));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Model card'));
      expect(shown, quant.repoId);
    });
  });

  group('live model cards', () {
    final live = Platform.environment['FPAI_HF_LIVE'] != null;
    final skip = live ? false : 'set FPAI_HF_LIVE to ask huggingface.co';
    // flutter_test answers every HttpClient call with a 400.
    setUpAll(() => HttpOverrides.global = null);

    test('an HTML-heavy roleplay card comes back as clean markdown', () async {
      final card = await HfReadme.fetch(
        'https://huggingface.co',
        'ReadyArt/Dark-Scarlett-27B-v3.0-GGUF',
      );
      expect(card.problem, isNull);
      expect(card.markdown, contains('Dark Scarlett'));
      expect(card.markdown, isNot(matches(RegExp(r'</?(div|img|span|p)\b'))));
      expect(card.license, isNotNull);
      expect(card.baseModels, isNotEmpty);
    }, skip: skip);

    test('a gated repo reports gated rather than an empty card', () async {
      final card = await HfReadme.fetch(
        'https://huggingface.co',
        'google/gemma-3-27b-it',
      );
      expect(card.problem, HfFilesProblem.gated);
    }, skip: skip);
  });
}
