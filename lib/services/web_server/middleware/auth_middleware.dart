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

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web_server_service.dart';

/// Auth middleware for Bearer token (and ?token fallback for SSE/img) validation.
/// PIN login is handled in auth_routes (issues the token).
/// Extracted during Stage 6.
class AuthMiddleware {
  final WebServerService _service;

  AuthMiddleware(this._service);

  shelf.Middleware get middleware => _build();

  shelf.Middleware _build() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        final path = request.url.path;

        // Allow static assets, health, and login without auth
        if (!path.startsWith('api/') ||
            path == 'api/health' ||
            path == 'api/auth/login') {
          return innerHandler(request);
        }

        // Check Authorization header
        final authHeader = request.headers['authorization'];
        String? tokenValue;

        if (authHeader != null && authHeader.startsWith('Bearer ')) {
          tokenValue = authHeader.substring(7);
        } else {
          // Fallback: check query parameter (for <img> tags, SSE, etc.)
          tokenValue = request.url.queryParameters['token'];
        }

        if (tokenValue == null ||
            !_service.activeSessions.containsKey(tokenValue)) {
          return shelf.Response(
            401,
            body: jsonEncode({'error': 'Authentication required'}),
            headers: {'Content-Type': 'application/json'},
          );
        }

        // Update last-activity timestamp (via exposed surface)
        _service.activeSessions[tokenValue] = DateTime.now();
        return innerHandler(request);
      };
    };
  }
}
