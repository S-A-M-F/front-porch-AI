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

import 'dart:io';

import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web_server/helpers/route_utils.dart';
import 'package:front_porch_ai/services/web_server_service.dart';

/// Client tracking middleware (sets hasActiveClient + connected info on first
/// authenticated API hit after login; drives the desktop lock overlay).
/// Extracted Stage 6. Uses public surface on service for mutations.
class ClientTracker {
  final WebServerService _service;

  ClientTracker(this._service);

  shelf.Middleware get middleware => _build();

  shelf.Middleware _build() {
    return (shelf.Handler innerHandler) {
      return (shelf.Request request) async {
        if (request.url.path.startsWith('api/') &&
            request.url.path != 'api/health' &&
            request.url.path != 'api/auth/login' &&
            request.url.path != 'api/disconnect') {
          if (!_service.hasActiveClient) {
            final forwardedFor = request.headers['x-forwarded-for'];
            final ip =
                forwardedFor ??
                request.headers['x-real-ip'] ??
                (request.context['shelf.io.connection_info'] != null
                    ? (request.context['shelf.io.connection_info']
                              as HttpConnectionInfo?)
                          ?.remoteAddress
                          .address
                    : null);
            final ua = request.headers['user-agent'] ?? '';
            final info = RouteUtils.parseUserAgent(ua, ip);
            _service.markClientActive(
              ip: ip,
              info: info,
            ); // god thin accepts optional named for tracker notify + state
          }
        }
        return innerHandler(request);
      };
    };
  }
}
