// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Model Manager's HuggingFace search finds roleplay tunes. Community
// quant repos carry no pipeline tag, so the old `filter=gguf,text-generation`
// returned zero hits for every one of them. The fixtures below are trimmed
// copies of real search results (2026-10); the live group at the bottom asks
// the real API and skips unless FPAI_HF_LIVE is set:
//
//   FPAI_HF_LIVE=1 flutter test test/services/hf_search_test.dart

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/services/hf_search.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:http/http.dart' as http;

HFModel _hit(String id, List<String> tags, {String? pipeline}) =>
    HFModel.fromSearchResult({
      'id': id,
      'downloads': 100,
      'tags': tags,
      'pipeline_tag': ?pipeline,
    });

final _scarlett = _hit('ReadyArt/Dark-Scarlett-27B-v3.0-GGUF', [
  'gguf',
  'roleplay',
  'conversational',
  'nsfw',
  'erp',
  'not-for-all-audiences',
]);
final _instruct = _hit('bartowski/gemma-3-27b-it-GGUF', [
  'gguf',
  'text-generation',
], pipeline: 'text-generation');
final _flux = _hit('city96/FLUX.1-dev-gguf', [
  'gguf',
  'text-to-image',
  'image-generation',
], pipeline: 'text-to-image');
final _ltxBare = _hit('darksidewalker/DaSiWa-LTX2.3', [
  'gguf',
  'base_model:Lightricks/LTX-2.3',
]);
final _wanDiffusion = _hit('DeepBeepMeep/Wan2.1', [
  'diffusion-single-file',
  'gguf',
]);
final _sdxlBare = _hit('nuupy/WAI-illustrious-SDXL-GGUF', ['gguf']);
final _plainQuant = _hit('mradermacher/SomeTune-12B-GGUF', ['gguf']);

void main() {
  group('HfSearch.searchUri', () {
    test('filters on gguf only, so untagged quant repos are not dropped', () {
      final uri = HfSearch.searchUri('https://huggingface.co', 'Scarlett 27B');
      expect(uri.path, '/api/models');
      expect(uri.queryParameters['filter'], 'gguf');
      expect(uri.queryParameters['search'], 'Scarlett 27B');
      expect(uri.queryParameters['sort'], 'downloads');
      expect(uri.queryParameters['direction'], '-1');
      expect(int.parse(uri.queryParameters['limit']!), HfSearch.fetched);
    });
  });

  group('HfSearch.rank', () {
    test('keeps chat repos with no pipeline tag, drops self-described '
        'image / video repos', () {
      final ranked = HfSearch.rank([
        _flux,
        _plainQuant,
        _ltxBare,
        _wanDiffusion,
        _sdxlBare,
        _scarlett,
        _instruct,
      ]);
      expect(ranked.map((m) => m.id), [
        _scarlett.id,
        _plainQuant.id,
        _instruct.id,
      ]);
    });

    test('roleplay tunes rise above the downloads order, which is kept '
        'within each group', () {
      final rpA = _hit('a/RpA-GGUF', ['gguf', 'roleplay']);
      final rpB = _hit('b/RpB-GGUF', ['gguf', 'ERP']);
      final ranked = HfSearch.rank([_instruct, rpA, _plainQuant, rpB]);
      expect(ranked.map((m) => m.id), [
        rpA.id,
        rpB.id,
        _instruct.id,
        _plainQuant.id,
      ]);
    });

    test('caps the list at the shown count after boosting', () {
      final plain = List.generate(30, (i) => _hit('p/Plain$i-GGUF', ['gguf']));
      final ranked = HfSearch.rank([...plain, _scarlett]);
      expect(ranked, hasLength(HfSearch.shown));
      expect(ranked.first.id, _scarlett.id);
    });
  });

  group('HFModelCard roleplay badge', () {
    Future<void> pump(WidgetTester tester, HFModel model) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HFModelCard(
            model: model,
            availableVramMb: 24000,
            onDownload: (_) {},
          ),
        ),
      ),
    );

    testWidgets('shows on a roleplay-tagged repo', (tester) async {
      await pump(tester, _scarlett);
      expect(find.text('Roleplay'), findsOneWidget);
    });

    testWidgets('stays off a plain instruct repo', (tester) async {
      await pump(tester, _instruct);
      expect(find.text('Roleplay'), findsNothing);
    });
  });

  group('live HuggingFace search', () {
    final live = Platform.environment['FPAI_HF_LIVE'] != null;
    // flutter_test answers every HttpClient call with a 400.
    setUpAll(() => HttpOverrides.global = null);

    for (final query in ['Scarlett 27B', 'For-Her-Darkside', 'Dominatrix']) {
      test('"$query" finds roleplay tunes', () async {
        // The same request and ranking ModelManager.searchHFModels makes.
        final res = await http.get(
          HfSearch.searchUri('https://huggingface.co', query),
        );
        expect(res.statusCode, 200);
        final hits = HfSearch.rank([
          for (final m in jsonDecode(res.body) as List)
            HFModel.fromSearchResult(m as Map<String, dynamic>),
        ]);
        expect(hits, isNotEmpty);
        expect(hits.first.isRoleplay, isTrue, reason: hits.first.id);
      }, skip: live ? false : 'set FPAI_HF_LIVE to ask huggingface.co');
    }
  });
}
