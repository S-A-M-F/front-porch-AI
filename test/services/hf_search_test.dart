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

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/hf_model.dart';
import 'package:front_porch_ai/services/hf_search.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/ui/pages/model_manager/model_manager.dart';
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

  group('HfSearch filters', () {
    test('each sort asks HuggingFace for its own order', () {
      String sortOf(HfSort s) => HfSearch.searchUri(
        'https://huggingface.co',
        'x',
        sort: s,
      ).queryParameters['sort']!;
      expect(sortOf(HfSort.downloads), 'downloads');
      expect(sortOf(HfSort.likes), 'likes');
      expect(sortOf(HfSort.newest), 'lastModified');
      expect(sortOf(HfSort.trending), 'trendingScore');
    });

    test('the size comes from the repo name, MoE counted in full', () {
      expect(HfSearch.paramsBillions('Qwen3.8-27B-Dominatrix-GGUF'), 27);
      expect(HfSearch.paramsBillions('Dark-Scarlett-v0.3-26B-A4B-GGUF'), 26);
      expect(HfSearch.paramsBillions('Mixtral-8x7B-Instruct-GGUF'), 56);
      expect(HfSearch.paramsBillions('Llama-3.2-1B-NSFW-Dominatrix'), 1);
      expect(HfSearch.paramsBillions('SmolLM2-1.7B-Instruct'), 1.7);
      expect(HfSearch.paramsBillions('Llama-3.3-70B-Instruct-GGUF'), 70);
      expect(HfSearch.paramsBillions('Phi-3-mini-4k-instruct'), isNull);
    });

    test('roleplay only and a size bucket narrow the ranked list', () {
      final rp12 = _hit('r/For-Her-Darkside-12B-GGUF', ['gguf', 'roleplay']);
      final rp32 = _hit('r/For-Her-Darkside-32B-GGUF', ['gguf', 'roleplay']);
      final plain12 = _hit('p/Mistral-Nemo-12B-GGUF', ['gguf']);
      final unsized = _hit('p/Phi-mini-GGUF', ['gguf', 'roleplay']);
      final all = [rp12, rp32, plain12, unsized];

      List<String> ids(HfSearchOptions o) =>
          HfSearch.rank(all, options: o).map((m) => m.id).toList();

      expect(ids(const HfSearchOptions(roleplayOnly: true)), [
        rp12.id,
        rp32.id,
        unsized.id,
      ]);
      expect(ids(const HfSearchOptions(size: HfSizeBucket.small)), [
        rp12.id,
        plain12.id,
      ]);
      expect(
        ids(
          const HfSearchOptions(roleplayOnly: true, size: HfSizeBucket.medium),
        ),
        [rp32.id],
      );
    });

    test('the web relay reads its filters, and none means the default', () {
      final none = HfSearchOptions.fromQuery(const {'q': 'x'});
      expect(none.sort, HfSort.downloads);
      expect(none.roleplayOnly, isFalse);
      expect(none.size, HfSizeBucket.any);

      final some = HfSearchOptions.fromQuery(const {
        'sort': 'newest',
        'rp': '1',
        'size': 'large',
      });
      expect(some.sort, HfSort.newest);
      expect(some.roleplayOnly, isTrue);
      expect(some.size, HfSizeBucket.large);

      expect(
        HfSearchOptions.fromQuery(const {'sort': 'bogus'}).sort,
        HfSort.downloads,
      );
    });
  });

  group('ModelSearchController', () {
    test('a slow older search never overwrites a newer one', () async {
      final models = _ScriptedModels();
      final controller = ModelSearchController();
      addTearDown(controller.dispose);

      controller.textController.text = 'old';
      final first = controller.search(models);
      controller.textController.text = 'new';
      final second = controller.search(models);

      models.answer('new', [_instruct]);
      await second;
      models.answer('old', [_scarlett]);
      await first;

      expect(controller.results.map((m) => m.id), [_instruct.id]);
      expect(controller.isSearching, isFalse);
    });

    test('changing a filter searches again with it', () async {
      final models = _ScriptedModels();
      final controller = ModelSearchController();
      addTearDown(controller.dispose);
      controller.textController.text = 'darkside';

      controller.setOptions(const HfSearchOptions(roleplayOnly: true), models);
      expect(models.asked.single.$1, 'darkside');
      expect(models.asked.single.$2.roleplayOnly, isTrue);
    });
  });
}

/// A ModelManager whose searches answer when the test says so. No network:
/// this pins the controller's ordering, not HuggingFace.
class _ScriptedModels implements ModelManager {
  final List<(String, HfSearchOptions)> asked = [];
  final Map<String, Completer<List<HFModel>>> _pending = {};

  void answer(String query, List<HFModel> results) =>
      _pending[query]!.complete(results);

  @override
  Future<List<HFModel>> searchHFModels(
    String query, {
    int limit = HfSearch.shown,
  }) => searchHFModelsFiltered(query);

  @override
  Future<List<HFModel>> searchHFModelsFiltered(
    String query, {
    int limit = HfSearch.shown,
    HfSearchOptions options = const HfSearchOptions(),
  }) {
    asked.add((query, options));
    return (_pending[query] = Completer<List<HFModel>>()).future;
  }

  @override
  Future<Map<String, HFModel>> fetchFilesForModels(
    List<HFModel> models,
  ) async => {for (final m in models) m.id: m};

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
