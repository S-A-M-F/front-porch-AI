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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/app_version.dart';
import 'package:front_porch_ai/services/web_server/helpers/route_utils.dart';
import 'package:front_porch_ai/services/web_server_service.dart';

/// Auth + health + disconnect routes.
/// Login issues token (validated by AuthMiddleware).
/// Extracted Stage 6 (exact paths + behavior preserved).
class AuthRoutes {
  final WebServerService _service;

  AuthRoutes(this._service, Router router) {
    router.post('/api/auth/login', _handleLogin);
    router.post('/api/auth/logout', _handleLogout);
    router.get('/api/health', _handleHealth);
    router.post('/api/disconnect', _handleDisconnect);
  }

  /// POST /api/auth/login — validate PIN, return session token.
  Future<shelf.Response> _handleLogin(shelf.Request request) async {
    try {
      final body = jsonDecode(await request.readAsString());
      final pin = body['pin']?.toString() ?? '';

      if (pin.isEmpty || pin != _service.storageService.webServerPin) {
        return shelf.Response(
          401,
          body: jsonEncode({'error': 'Invalid PIN'}),
          headers: {'Content-Type': 'application/json'},
        );
      }

      // Generate session token
      final token = RouteUtils.generateSessionToken();
      _service.activeSessions[token] = DateTime.now();

      debugPrint('[WebServer] Client authenticated, token issued');
      return shelf.Response.ok(
        jsonEncode({'token': token, 'version': appVersion}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return shelf.Response(
        400,
        body: jsonEncode({'error': 'Invalid request body'}),
        headers: {'Content-Type': 'application/json'},
      );
    }
  }

  /// POST /api/auth/logout — invalidate session token.
  Future<shelf.Response> _handleLogout(shelf.Request request) async {
    final authHeader = request.headers['authorization'];
    if (authHeader != null && authHeader.startsWith('Bearer ')) {
      _service.activeSessions.remove(authHeader.substring(7));
    }
    return shelf.Response.ok(
      jsonEncode({'status': 'logged_out'}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  shelf.Response _handleHealth(shelf.Request request) {
    return shelf.Response.ok(
      jsonEncode({
        'status': 'ok',
        'version': appVersion,
        'hasActiveClient': _service.hasActiveClient,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  shelf.Response _handleDisconnect(shelf.Request request) {
    _service.disconnectClient();
    return shelf.Response.ok(
      jsonEncode({'status': 'disconnected'}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
