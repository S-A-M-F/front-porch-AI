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
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web_server_service.dart';

/// Image cache proxy (check + serve with on-demand download).
/// Lifted from web_server_service during Stage 6.
class ImageCacheHelper {
  final WebServerService _service;

  ImageCacheHelper(this._service);

  /// Returns the image_cache directory path.
  Future<Directory> getImageCacheDir() async {
    final root =
        _service.storageService.rootPath ??
        (await getApplicationDocumentsDirectory()).path;
    final dir = Directory(p.join(root, 'system', 'image_cache'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Compute cache filename for a URL — same scheme as Flutter app.
  String imageCacheFilename(String url) {
    final hash = url.hashCode.toRadixString(16);
    final uri = Uri.tryParse(url);
    String ext = '.png';
    if (uri != null && uri.pathSegments.isNotEmpty) {
      final seg = uri.pathSegments.last.split('.').last.split('?').first;
      if ([
        'png',
        'jpg',
        'jpeg',
        'gif',
        'webp',
        'svg',
      ].contains(seg.toLowerCase())) {
        ext = '.$seg';
      }
    }
    return '$hash$ext';
  }

  /// GET /api/image-cache/check?url=<encoded_url>
  /// Returns `{ cached: bool }` — checks if URL is already in local image cache.
  Future<shelf.Response> check(shelf.Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return _errorResponse(400, 'url parameter required');
    }
    try {
      final dir = await getImageCacheDir();
      final filename = imageCacheFilename(url);
      final file = File('${dir.path}/$filename');
      return shelf.Response.ok(
        jsonEncode({'cached': await file.exists()}),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (e) {
      return _errorResponse(500, 'Cache check failed: $e');
    }
  }

  /// GET `/api/image-cache/serve?url=<encoded_url>`
  /// Serves image from cache, downloading and caching first if needed.
  Future<shelf.Response> serve(shelf.Request request) async {
    final url = request.url.queryParameters['url'];
    if (url == null || url.isEmpty) {
      return _errorResponse(400, 'url parameter required');
    }
    try {
      final dir = await getImageCacheDir();
      final filename = imageCacheFilename(url);
      final file = File('${dir.path}/$filename');

      // Serve from cache if available
      if (await file.exists()) {
        final ext = filename.split('.').last.toLowerCase();
        final mime =
            {
              'png': 'image/png',
              'jpg': 'image/jpeg',
              'jpeg': 'image/jpeg',
              'gif': 'image/gif',
              'webp': 'image/webp',
              'svg': 'image/svg+xml',
            }[ext] ??
            'image/png';
        return shelf.Response.ok(
          await file.readAsBytes(),
          headers: {
            'Content-Type': mime,
            'Cache-Control': 'public, max-age=86400',
          },
        );
      }

      // Download and cache
      final httpClient = HttpClient();
      try {
        final req = await httpClient.getUrl(Uri.parse(url));
        final response = await req.close();
        if (response.statusCode != 200) {
          return _errorResponse(
            502,
            'Upstream returned ${response.statusCode}',
          );
        }
        // Manual consolidate (equivalent to consolidateHttpClientResponseBytes; avoids import friction post-extraction)
        final bytes = <int>[];
        await for (final chunk in response) {
          bytes.addAll(chunk);
        }
        await file.writeAsBytes(bytes);

        final contentType = response.headers.contentType;
        final mime = contentType != null
            ? '${contentType.primaryType}/${contentType.subType}'
            : 'image/png';
        return shelf.Response.ok(
          bytes,
          headers: {
            'Content-Type': mime,
            'Cache-Control': 'public, max-age=86400',
          },
        );
      } finally {
        httpClient.close();
      }
    } catch (e) {
      return _errorResponse(500, 'Cache serve failed: $e');
    }
  }

  shelf.Response _errorResponse(int status, String message) {
    return shelf.Response(
      status,
      body: jsonEncode({'error': message}),
      headers: {'Content-Type': 'application/json'},
    );
  }
}
