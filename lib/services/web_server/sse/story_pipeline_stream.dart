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

/// Story pipeline SSE stream + status (extracted last per plan).
/// The god _storyBroadcast and _onStoryPipelineUpdate remain (existing void _ ).
class StoryPipelineStream {
  final WebServerService _service;

  StoryPipelineStream(this._service, Router router) {
    router.get('/api/stories/<id>/pipeline/stream', _handlePipelineStream);
    router.get('/api/stories/<id>/pipeline/status', _handlePipelineStatus);
  }

  Future<shelf.Response> _handlePipelineStream(
    shelf.Request request,
    String id,
  ) async {
    final controller = StreamController<List<int>>();
    _service.storySseClients.add(controller);
    debugPrint(
      '[WebServer] Story SSE client connected (${_service.storySseClients.length} total)',
    );

    controller.onCancel = () {
      _service.storySseClients.remove(controller);
      debugPrint('[WebServer] Story SSE client disconnected');
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

  /// GET `/api/stories/<id>/pipeline/status` — Polling fallback for pipeline state.
  Future<shelf.Response> _handlePipelineStatus(
    shelf.Request request,
    String id,
  ) async {
    return shelf.Response.ok(
      jsonEncode({
        'running': _service.storyPipelineRunning,
        'status': _service.storyStatus,
        'streamingText': _service.storyStreamingText,
        'currentId': _service.storyCurrentId,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
