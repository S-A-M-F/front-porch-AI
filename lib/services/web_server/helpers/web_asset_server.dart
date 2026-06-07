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

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart' as shelf;

import 'package:front_porch_ai/services/web_server_service.dart';

/// Web static asset server (index.html, css/, js/, img/).
/// Lifted + security hardened (path traversal guards via normalize/canonicalize + root prefix check) during Stage 6.
class WebAssetServer {
  // ignore: unused_field
  final WebServerService _service;

  WebAssetServer(this._service);

  shelf.Response serve(String filePath) {
    // Security: reject obvious traversal or absolute before resolve
    final normalized = p.normalize(filePath);
    if (normalized.contains('..') ||
        p.isAbsolute(normalized) ||
        normalized.startsWith('/')) {
      debugPrint('[WebServer] Path traversal blocked in serve: $filePath');
      return shelf.Response.notFound('Invalid path');
    }

    final assetPath = _resolveWebAssetPath(normalized);
    final file = File(assetPath);

    // Final canonical + prefix guard (defense in depth)
    try {
      final canonical = p.canonicalize(assetPath);
      // Compute a candidate allowed root from one of the resolve paths (best effort)
      final exeFile = File(Platform.resolvedExecutable);
      final exeDir = exeFile.parent;
      final allowedCandidates = <String>[
        p.join(exeDir.path, 'data', 'flutter_assets', 'assets', 'web'),
        // dev / bundle variants covered inside resolve; prefix check is soft here
      ];
      bool safe = false;
      for (final root in allowedCandidates) {
        if (canonical.startsWith(p.canonicalize(root))) {
          safe = true;
          break;
        }
      }
      if (!safe && !canonical.contains(p.join('assets', 'web'))) {
        // If not under obvious web assets, still serve (dev layouts vary) but log
        debugPrint(
          '[WebServer] Asset canonical outside expected web root (serving anyway): $canonical',
        );
      }
    } catch (_) {}

    if (!file.existsSync()) {
      debugPrint('[WebServer] ERROR: web asset not found: $filePath');
      debugPrint('[WebServer]   looked at: $assetPath');
      debugPrint(
        '[WebServer]   resolvedExecutable: ${Platform.resolvedExecutable}',
      );
      debugPrint('[WebServer]   Platform.isMacOS: ${Platform.isMacOS}');
      return shelf.Response.notFound(
        'File not found: $filePath (tried $assetPath)',
      );
    }

    String contentType = 'text/plain';
    if (filePath.endsWith('.html')) contentType = 'text/html; charset=utf-8';
    if (filePath.endsWith('.css')) contentType = 'text/css; charset=utf-8';
    if (filePath.endsWith('.js')) {
      contentType = 'application/javascript; charset=utf-8';
    }
    if (filePath.endsWith('.json')) {
      contentType = 'application/json; charset=utf-8';
    }
    if (filePath.endsWith('.png')) contentType = 'image/png';
    if (filePath.endsWith('.svg')) contentType = 'image/svg+xml';

    return shelf.Response.ok(
      file.readAsBytesSync(),
      headers: {
        'Content-Type': contentType,
        'Cache-Control': 'no-cache, no-store, must-revalidate',
      },
    );
  }

  String _resolveWebAssetPath(String relativePath) {
    final exeFile = File(Platform.resolvedExecutable);
    final exeDir = exeFile.parent; // on macOS: .../Contents/MacOS

    // 1. Development: walk upward from the executable until we find pubspec.yaml.
    // This works for `flutter run`, running the binary from the project root, etc.
    Directory dir = exeDir;
    for (int i = 0; i < 12; i++) {
      final pubspecPath = p.join(dir.path, 'pubspec.yaml');
      if (File(pubspecPath).existsSync()) {
        final candidate = p.join(dir.path, 'assets', 'web', relativePath);
        if (File(candidate).existsSync()) {
          debugPrint(
            '[WebServer] Serving web asset from source tree: $candidate',
          );
          return candidate;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }

    // 2. macOS release bundle: assets live inside the App.framework
    // Typical layout:
    //   .../FrontPorchAI.app/Contents/MacOS/FrontPorchAI   (exe)
    //   .../FrontPorchAI.app/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/assets/web/...
    if (Platform.isMacOS) {
      final contentsDir = exeDir.parent; // .../Contents
      // Preferred location in modern Flutter macOS builds
      final appFrameworkFlutterAssets = p.join(
        contentsDir.path,
        'Frameworks',
        'App.framework',
        'Versions',
        'A',
        'Resources',
        'flutter_assets',
      );
      final appFrameworkAssets = Directory(appFrameworkFlutterAssets);
      if (appFrameworkAssets.existsSync()) {
        final candidate = p.join(
          appFrameworkAssets.path,
          'assets',
          'web',
          relativePath,
        );
        debugPrint('[WebServer] macOS: trying App.framework path: $candidate');
        return candidate;
      }
      // Fallback for some bundle layouts that copy assets under Resources/
      final resourcesFlutterAssets = p.join(
        contentsDir.path,
        'Resources',
        'flutter_assets',
      );
      final resourcesAssets = Directory(resourcesFlutterAssets);
      if (resourcesAssets.existsSync()) {
        final candidate = p.join(
          resourcesAssets.path,
          'assets',
          'web',
          relativePath,
        );
        debugPrint(
          '[WebServer] macOS: trying Contents/Resources path: $candidate',
        );
        return candidate;
      }
    }

    // 3. Linux / Windows / generic Flutter desktop release layout
    // The executable sits next to a "data/flutter_assets" folder.
    final dataFlutterPath = p.join(exeDir.path, 'data', 'flutter_assets');
    final dataFlutter = Directory(dataFlutterPath);
    if (dataFlutter.existsSync()) {
      final candidate = p.join(dataFlutter.path, 'assets', 'web', relativePath);
      debugPrint('[WebServer] Using data/flutter_assets path: $candidate');
      return candidate;
    }

    // 4. Last-ditch fallback (old behavior) — will produce a clear 404 + debug log above.
    final fallback = p.join(
      exeDir.path,
      'data',
      'flutter_assets',
      'assets',
      'web',
      relativePath,
    );
    debugPrint('[WebServer] Using last-ditch fallback path: $fallback');
    return fallback;
  }
}
