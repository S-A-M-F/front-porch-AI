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

import 'package:shelf/shelf.dart' as shelf;

/// CORS middleware extracted from web_server_service.dart (Stage 6).
/// Simple permissive CORS for local LAN web UI + API access.
class CorsMiddleware {
  static const headers = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  shelf.Middleware get middleware => _build();

  shelf.Middleware _build() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: headers);
        }
        final response = await innerHandler(request);
        return response.change(headers: headers);
      };
    };
  }
}
