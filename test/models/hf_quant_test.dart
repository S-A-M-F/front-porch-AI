// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The Model Manager lists what a user can actually download: big quants
// live in subfolders split into parts (bartowski's Llama-3.3-70B showed 24
// of its 38 GGUFs before), the parts are one row and one download, a vision
// projector is an add-on rather than a quant, and the local list shows a
// split model once. Fixture names and sizes are copied from the real repos;
// the live group asks HuggingFace and skips unless FPAI_HF_LIVE is set.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/services/hf_repo_files.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/projector_pairing.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/widgets/hf_model_card.dart';
import 'package:path/path.dart' as p;

const _repo = 'bartowski/Llama-3.3-70B-Instruct-GGUF';
const _gb = 1024 * 1024 * 1024;

HFModelFile _f(String path, int bytes, {String? oid, String repo = _repo}) =>
    HFModelFile.fromApiMap({
      'type': 'file',
      'path': path,
      'size': bytes,
      'lfs': ?(oid == null ? null : {'oid': oid, 'size': bytes}),
    }, repo);

final _tree = [
  _f('Llama-3.3-70B-Instruct-IQ2_M.gguf', (24.1 * _gb).round()),
  _f('Llama-3.3-70B-Instruct-Q4_K_M.gguf', (42.5 * _gb).round(), oid: 'a' * 64),
  _f(
    'Llama-3.3-70B-Instruct-Q8_0/Llama-3.3-70B-Instruct-Q8_0-00002-of-00002.gguf',
    (35.0 * _gb).round(),
  ),
  _f(
    'Llama-3.3-70B-Instruct-Q8_0/Llama-3.3-70B-Instruct-Q8_0-00001-of-00002.gguf',
    (39.9 * _gb).round(),
  ),
];

void main() {
  group('HfQuant.group', () {
    final quants = HfQuant.group(_tree);

    test('subfolder split parts are one quant, smallest first', () {
      expect(quants.map((q) => q.title), [
        'Llama-3.3-70B-Instruct-IQ2_M.gguf',
        'Llama-3.3-70B-Instruct-Q4_K_M.gguf',
        'Llama-3.3-70B-Instruct-Q8_0.gguf',
      ]);
      final q8 = quants.last;
      expect(q8.isSplit, isTrue);
      expect(q8.isComplete, isTrue);
      expect(q8.parts, hasLength(2));
      expect(q8.sizeBytes, (35.0 * _gb).round() + (39.9 * _gb).round());
      expect(q8.id, endsWith('-00001-of-00002.gguf'));
      expect(q8.localFilenames, [
        'Llama-3.3-70B-Instruct-Q8_0-00001-of-00002.gguf',
        'Llama-3.3-70B-Instruct-Q8_0-00002-of-00002.gguf',
      ]);
      expect(q8.primary.quantType, QuantType.q8_0);
    });

    test('a quant missing a part is not complete', () {
      final partial = HfQuant.group([
        _f('Big-Q6_K/Big-Q6_K-00001-of-00003.gguf', _gb),
        _f('Big-Q6_K/Big-Q6_K-00002-of-00003.gguf', _gb),
      ]).single;
      expect(partial.isComplete, isFalse);
      expect(partial.partsExpected, 3);
    });

    test('the LFS oid is the expected SHA-256; a split quant has none', () {
      expect(quants[1].primary.sha256, 'a' * 64);
      expect(quants[1].combined.sha256, 'a' * 64);
      expect(quants.last.combined.sha256, isNull);
    });

    test('a projector is saved under its repo name so two repos never '
        'collide', () {
      final proj = _f(
        'mmproj-F16.gguf',
        800 << 20,
        repo: 'bartowski/google_gemma-3-27b-it-GGUF',
      );
      expect(proj.isProjector, isTrue);
      expect(proj.localFilename, 'google_gemma-3-27b-it-GGUF.mmproj-F16.gguf');
      expect(_tree.first.localFilename, 'Llama-3.3-70B-Instruct-IQ2_M.gguf');
    });
  });

  group('QuantType.fromFilename', () {
    test('reads the basename and needs integer quants to stand alone', () {
      expect(QuantType.fromFilename('Phi4-mini-Q8_0.gguf'), QuantType.q8_0);
      expect(
        QuantType.fromFilename('Phi-4-Q8_0/Phi-4-Q8_0-00001-of-00002.gguf'),
        QuantType.q8_0,
      );
      expect(QuantType.fromFilename('model-I4.gguf'), QuantType.i4);
    });
  });

  group('HfQuant.bestFit', () {
    final quants = HfQuant.group(_tree);

    test('picks the largest quant that fits with headroom', () {
      final best = HfQuant.bestFit(
        quants,
        vramMb: 48 * 1024,
        contextSize: 8192,
      );
      expect(best?.title, 'Llama-3.3-70B-Instruct-Q4_K_M.gguf');
    });

    test('nothing when nothing fits, or the VRAM is unknown', () {
      expect(
        HfQuant.bestFit(quants, vramMb: 8 * 1024, contextSize: 8192),
        isNull,
      );
      expect(HfQuant.bestFit(quants, vramMb: 0, contextSize: 8192), isNull);
    });
  });

  group('local models', () {
    late Directory root;
    late StorageService storage;
    late DownloadManager downloads;
    late ModelManager models;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('fpai_split_local_');
      storage = StorageService.sandbox(root.path);
      final dir = storage.modelsDir..createSync(recursive: true);
      void write(String name, int bytes) =>
          File(p.join(dir.path, name)).writeAsBytesSync(List.filled(bytes, 1));
      write('Big-Q8_0-00001-of-00002.gguf', 10);
      write('Big-Q8_0-00002-of-00002.gguf', 20);
      write('gemma-GGUF.mmproj-F16.gguf', 5);
      write('Solo-Q4_K_M.gguf', 7);
      downloads = DownloadManager(targetDir: dir.path);
      models = ModelManager(storage, downloads);
      await models.refreshModels();
    });

    tearDown(() async {
      models.dispose();
      downloads.dispose();
      await root.delete(recursive: true);
    });

    test('a split model is listed once, at its full size, without its '
        'projector', () {
      final listed = {
        for (final m in models.localModels) m.filename: m.sizeBytes,
      };
      expect(listed, {
        'Big-Q8_0-00001-of-00002.gguf': 30,
        'Solo-Q4_K_M.gguf': 7,
      });
      expect(models.downloadedFilenames, {
        'Big-Q8_0-00001-of-00002.gguf',
        'Big-Q8_0-00002-of-00002.gguf',
        'gemma-GGUF.mmproj-F16.gguf',
        'Solo-Q4_K_M.gguf',
      });
    });
  });

  group('ProjectorPairing', () {
    DownloadTask done(String repo, String filename) => DownloadTask(
      url: 'https://huggingface.co/$repo/resolve/main/$filename',
      filename: filename,
      targetDir: '/models',
      repoId: repo,
    )..state = DownloadTaskState.completed;

    test('a model gets its own repo\'s projector, and keeps one it has', () {
      final pairs = ProjectorPairing.pairs(
        [
          done('g/gemma-GGUF', 'gemma-Q4_K_M.gguf'),
          done('g/gemma-GGUF', 'gemma-GGUF.mmproj-F16.gguf'),
          done('g/gemma-GGUF', 'gemma-Q8_0.gguf'),
          done('o/other-GGUF', 'other-Q4_K_M.gguf'),
        ],
        existing: const {'/models/gemma-Q8_0.gguf': '/models/mine.gguf'},
      );
      expect(pairs, {
        '/models/gemma-Q4_K_M.gguf': '/models/gemma-GGUF.mmproj-F16.gguf',
      });
    });
  });

  group('HFModelCard file list', () {
    Future<void> pump(
      WidgetTester tester,
      HFModel model, {
      ValueChanged<HfQuant>? onQuant,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: HFModelCard(
                model: model,
                availableVramMb: 48 * 1024,
                contextSize: 8192,
                onDownload: (_) {},
                onDownloadQuant: onQuant,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text(model.name));
      await tester.pumpAndSettle();
    }

    final model = HFModel(id: _repo, author: 'bartowski');

    testWidgets('a split quant is one row and one download of every part', (
      tester,
    ) async {
      HfQuant? queued;
      await pump(tester, model.withFiles(_tree), onQuant: (q) => queued = q);

      expect(
        find.text('Llama-3.3-70B-Instruct-Q8_0.gguf · 2 parts'),
        findsOneWidget,
      );
      expect(find.text('Best fit'), findsOneWidget);
      expect(find.textContaining('00002-of-00002'), findsNothing);

      // Rows run smallest first; the split Q8_0 is last and over 48 GB.
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Download Anyway'));
      await tester.pumpAndSettle();
      expect(queued?.parts, hasLength(2));
    });

    testWidgets('a gated repo says what to do instead of "no files"', (
      tester,
    ) async {
      await pump(
        tester,
        model.withFiles(const [], problem: HfFilesProblem.gated),
      );
      expect(find.textContaining('Gated repo'), findsOneWidget);
      expect(find.text('No GGUF files available'), findsNothing);
    });
  });

  group('live HuggingFace file list', () {
    final live = Platform.environment['FPAI_HF_LIVE'] != null;
    // flutter_test answers every HttpClient call with a 400.
    setUpAll(() => HttpOverrides.global = null);

    test(
      'the 70B repo lists its subfolder Q8_0 as one two-part quant',
      () async {
        final listed = await HfRepoFiles.list('https://huggingface.co', _repo);
        expect(listed.problem, isNull);
        final q8 = HfQuant.group(
          listed.files,
        ).firstWhere((q) => q.title == 'Llama-3.3-70B-Instruct-Q8_0.gguf');
        expect(q8.parts, hasLength(2));
        expect(q8.isComplete, isTrue);
        expect(q8.parts.every((f) => f.sha256 != null), isTrue);
      },
      skip: live ? false : 'set FPAI_HF_LIVE to ask huggingface.co',
    );
  });

  group('live gated repo', () {
    // Never printed. FPAI_HF_GATED_REPO is a repo whose licence the token's
    // account has accepted, e.g. a meta-llama or google GGUF repo.
    final token = Platform.environment['FPAI_HF_TOKEN'];
    final repo = Platform.environment['FPAI_HF_GATED_REPO'];
    final skip = token == null || repo == null
        ? 'set FPAI_HF_TOKEN and FPAI_HF_GATED_REPO to ask huggingface.co'
        : false;
    setUpAll(() => HttpOverrides.global = null);

    test('lists with the token, and says "gated" without it', () async {
      final without = await HfRepoFiles.list('https://huggingface.co', repo!);
      expect(without.problem, HfFilesProblem.gated);

      final withToken = await HfRepoFiles.list(
        'https://huggingface.co',
        repo,
        headers: {'Authorization': 'Bearer $token'},
      );
      expect(withToken.problem, isNull);
      expect(withToken.files, isNotEmpty);
    }, skip: skip);
  });
}
