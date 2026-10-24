// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// World from Wiki against a REAL wiki and a REAL model: the engine the
// desktop and the phone run, end to end, writing what it made to a JSON
// file for a human (or an agent) to judge as a roleplay world. Never a
// stub, never a fake model (CLAUDE.md ## Tests). Skips unless the
// provider is named in the environment, so the default run and CI are
// unaffected.
//
//   FPAI_LIVE_API_URL=http://localhost:8000/v1 FPAI_LIVE_MODEL=<id> \
//   FPAI_LIVE_WIKI=https://bleach.fandom.com FPAI_LIVE_NAME='Bleach (TYBW)' \
//   FPAI_LIVE_PREMISE='…' FPAI_LIVE_MOMENT='…' FPAI_LIVE_DEPTH=1 \
//   FPAI_LIVE_CONTEXT=65536 FPAI_LIVE_WRITE=1 \
//   FPAI_LIVE_OUT=/path/world.json \
//     flutter test --tags wiki_live test/live/world_from_wiki_live_test.dart
//
// FPAI_LIVE_API_KEY names the provider key; without it, on macOS, the key
// the app itself saved for that provider URL is used and never printed.

@Tags(['live', 'wiki_live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

/// flutter_test stubs HttpClient to 400. An un-overridden HttpOverrides
/// restores the real client so this suite can reach the wiki and the model.
class _RealHttpOverrides extends HttpOverrides {}

String? _env(String key) {
  final v = Platform.environment[key]?.trim();
  return (v == null || v.isEmpty) ? null : v;
}

/// The key the app saved for [apiUrl] (its per-URL store, macOS prefs).
/// Read by the app's own bundle id; the value is used, never logged.
Future<String> _savedKeyFor(String apiUrl) async {
  if (!Platform.isMacOS) return '';
  try {
    final r = await Process.run('defaults', [
      'read',
      'com.linux4life1.frontPorchAi',
      'flutter.remote_api_keys',
    ]);
    if (r.exitCode != 0) return '';
    final decoded = jsonDecode((r.stdout as String).trim());
    if (decoded is! Map) return '';
    final bare = apiUrl.endsWith('/')
        ? apiUrl.substring(0, apiUrl.length - 1)
        : apiUrl;
    final key = decoded[apiUrl] ?? decoded[bare] ?? decoded['$bare/'];
    return key is String ? key : '';
  } catch (_) {
    return '';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final apiUrl = _env('FPAI_LIVE_API_URL');
  final model = _env('FPAI_LIVE_MODEL');
  final wiki = _env('FPAI_LIVE_WIKI');
  final out =
      _env('FPAI_LIVE_OUT') ??
      '${Directory.systemTemp.path}/fpai-wiki-live.json';
  final context = int.tryParse(_env('FPAI_LIVE_CONTEXT') ?? '') ?? 65536;
  final name = _env('FPAI_LIVE_NAME') ?? 'Live world';
  final premise = _env('FPAI_LIVE_PREMISE') ?? '';
  final moment = _env('FPAI_LIVE_MOMENT') ?? '';
  final depth = WorldWikiDepthX.fromIndex(
    int.tryParse(_env('FPAI_LIVE_DEPTH') ?? ''),
  );
  final write = _env('FPAI_LIVE_WRITE') == '1';

  final savedOverrides = HttpOverrides.current;
  setUp(() => HttpOverrides.global = _RealHttpOverrides());
  tearDown(() => HttpOverrides.global = savedOverrides);

  test(
    'World from Wiki builds a world from a real wiki with a real model',
    () async {
      if (apiUrl == null || model == null || wiki == null) {
        markTestSkipped(
          'set FPAI_LIVE_API_URL, FPAI_LIVE_MODEL and FPAI_LIVE_WIKI',
        );
        return;
      }
      final key = _env('FPAI_LIVE_API_KEY') ?? await _savedKeyFor(apiUrl);
      final llm = OpenRouterService(
        apiUrl: apiUrl,
        apiKey: key,
        modelName: model,
      );
      final engine = WorldFromWikiEngine(
        wiki: WikiSearchService(getBaseUrl: () => wiki),
        llm: llm,
        contextTokens: context,
        depth: depth,
        moment: moment,
        onProgress: (m) => stdout.writeln('[live] $m'),
      );
      final report = <String, dynamic>{
        'provider': apiUrl,
        'model': model,
        'wiki': wiki,
        'context': context,
        'name': name,
        'premise': premise,
        'moment': moment,
        'depth': depth.name,
      };
      void save() => File(
        out,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(report));

      final sw = Stopwatch()..start();
      final scout = await engine.scout(worldName: name, premise: premise);
      report['catalog'] = {
        'titles': scout.catalog.titles.length,
        'articles': scout.catalog.articleCount,
        'ranked': scout.catalog.ranked,
        'tagged': scout.catalog.tagsByTitle.length,
        'first': scout.catalog.titles.take(40).toList(),
      };
      report['scout'] = {
        'seconds': sw.elapsed.inSeconds,
        'cards': [for (final c in scout.proposed) c.toJson()],
        'places': [for (final p in scout.places) p.toJson()],
        'parts': scout.parts,
        'partsCut': scout.partsCut,
        'revised': scout.revised,
        'auditNotes': scout.auditNotes,
        'notes': scout.notes,
        'failure': scout.failure,
      };
      save();
      stdout.writeln(
        '[live] scout ${sw.elapsed.inSeconds}s titles=${scout.catalog.titles.length} '
        'ranked=${scout.catalog.ranked} cards=${scout.proposed.length} '
        'places=${scout.places.length} parts=${scout.parts} '
        'cut=${scout.partsCut} revised=${scout.revised} '
        'notes=${scout.auditNotes} failure=${scout.failure}',
      );
      expect(scout.failure, isNull);
      expect(scout.proposed, isNotEmpty);

      if (!write) return;
      sw.reset();
      final tree = await engine.writeTree(
        scout.proposed,
        places: scout.places,
        worldName: name,
        premise: premise,
        climateEnabled: true,
        climatePlaces: {
          for (final p in scout.places)
            if (p.climateHint.isNotEmpty) p.key,
        },
      );
      report['tree'] = {
        'seconds': sw.elapsed.inSeconds,
        'writeLog': engine.writeLog,
        'root': tree.root.toJson(),
        'places': [for (final p in tree.places) p.toJson()],
      };
      save();
      stdout.writeln(
        '[live] wrote ${sw.elapsed.inSeconds}s root=${tree.root.entries.length} '
        'entries, places=${tree.places.length} → $out',
      );
      expect(tree.root.entries, isNotEmpty);
    },
    timeout: const Timeout(Duration(minutes: 240)),
  );
}
