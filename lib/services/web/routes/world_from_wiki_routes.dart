// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web/facade/world_from_wiki_facade.dart';
import 'package:front_porch_ai/services/web/facade/world_from_wiki_review_facade.dart';
import 'package:front_porch_ai/services/web/util/util.dart';

class WebWorldFromWikiRoutes {
  WebWorldFromWikiRoutes(this._facade, Router router) {
    router.get('/api/worlds/from-wiki/status', _status);
    router.post('/api/worlds/from-wiki/scout', _scout);
    router.post('/api/worlds/from-wiki/write', _write);
    router.post('/api/worlds/from-wiki/abort', _abort);
    router.post('/api/worlds/from-wiki/tool-test', _toolTest);
    router.post('/api/worlds/from-wiki/context', _context);
    router.post('/api/worlds/from-wiki/review/rewrite', _reviewRewrite);
    router.post('/api/worlds/from-wiki/review/direction', _reviewDirection);
    router.post('/api/worlds/from-wiki/review/add', _reviewAdd);
  }

  final WorldFromWikiFacade _facade;

  Future<shelf.Response> _status(shelf.Request r) async =>
      JsonResponse.ok(await _facade.status());

  Future<shelf.Response> _toolTest(shelf.Request r) async =>
      JsonResponse.ok(await _facade.testTools());

  Future<shelf.Response> _context(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = await _facade.setContext(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _scout(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = await _facade.scout(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok(result);
  }

  Future<shelf.Response> _write(shelf.Request r) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = _facade.startWrite(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  Future<shelf.Response> _reviewRewrite(shelf.Request r) =>
      _review(r, _facade.startRewrite);

  Future<shelf.Response> _reviewDirection(shelf.Request r) =>
      _review(r, _facade.startDirection);

  Future<shelf.Response> _reviewAdd(shelf.Request r) =>
      _review(r, _facade.startAdd);

  /// A Review action starts in the background like a write; its result
  /// arrives as a `world_wiki_review_done` event.
  Future<shelf.Response> _review(
    shelf.Request r,
    Map<String, dynamic> Function(Map<String, dynamic> body) start,
  ) async {
    Map<String, dynamic> body;
    try {
      body = await RequestBody.readJsonMap(r);
    } catch (_) {
      return JsonResponse.badRequest('Invalid JSON body');
    }
    final result = start(body);
    if (result['ok'] != true) {
      return JsonResponse.error(
        400,
        result['error']?.toString() ?? 'Bad request',
      );
    }
    return JsonResponse.ok({'status': 'started'});
  }

  shelf.Response _abort(shelf.Request r) {
    _facade.abort();
    return JsonResponse.ok({'status': 'aborted'});
  }
}
