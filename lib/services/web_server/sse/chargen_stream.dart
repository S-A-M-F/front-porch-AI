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

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/services/web_server_service.dart';

/// Chargen SSE stream + status (extracted last per plan because coupled to mutable _chargen* state).
/// Non-stream chargen handlers (generate/describe etc) are in character_routes.
/// The god _chargenBroadcast remains (existing void _ , no new priv count).
class ChargenStream {
  final WebServerService _service;

  ChargenStream(this._service, Router router) {
    router.get('/api/chargen/status', _handleChargenStatus);
    router.get('/api/chargen/stream', _handleChargenStream);
  }

  Future<shelf.Response> _handleChargenStatus(shelf.Request request) async {
    final result = <String, dynamic>{
      'isGenerating': _service.isChargenRunning,
      'status': _service.chargenStatus,
      'preview': _service.chargenPreview,
    };
    if (_service.chargenCompletedCard != null) {
      result['complete'] = true;
      result['card'] = _service.chargenCompletedCard;
    }
    if (_service.chargenError != null) {
      result['error'] = _service.chargenError;
    }
    return shelf.Response.ok(
      jsonEncode(result),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// GET /api/chargen/stream — SSE endpoint for generation progress.
  Future<shelf.Response> _handleChargenStream(shelf.Request request) async {
    final controller = StreamController<List<int>>();
    _service.chargenSseClients.add(controller);
    debugPrint(
      '[WebServer] Chargen SSE client connected (${_service.chargenSseClients.length} total)',
    );

    // Send initial state
    try {
      final jsonStr = jsonEncode({
        'event': 'connected',
        'isGenerating': _service.isChargenRunning,
      });
      controller.add(utf8.encode('data: $jsonStr\n\n'));
    } catch (_) {}

    controller.onCancel = () {
      _service.chargenSseClients.remove(controller);
      debugPrint(
        '[WebServer] Chargen SSE client disconnected (${_service.chargenSseClients.length} remaining)',
      );
    };

    return shelf.Response.ok(
      controller.stream,
      headers: {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache',
        'Connection': 'keep-alive',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }
}
