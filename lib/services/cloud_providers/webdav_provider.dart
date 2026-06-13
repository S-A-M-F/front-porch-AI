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
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:front_porch_ai/services/cloud_sync_service.dart';

/// WebDAV-based cloud storage provider (Nextcloud, ownCloud, etc.)
class WebDavProvider extends CloudStorageProvider {
  webdav.Client? _client;
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  String get displayName => 'Nextcloud (WebDAV)';

  @override
  Future<void> connect(Map<String, String> credentials) async {
    final url = credentials['url'] ?? '';
    final username = credentials['username'] ?? '';
    final password = credentials['password'] ?? '';

    if (url.isEmpty || username.isEmpty) {
      throw Exception('WebDAV URL and username are required');
    }

    _client = webdav.newClient(
      url,
      user: username,
      password: password,
      debug: false,
    );

    // Set common headers
    _client!.setHeaders({'accept-charset': 'utf-8'});

    // Test connectivity by reading the root
    try {
      await _client!.readDir('/');
      _connected = true;
    } catch (e) {
      _connected = false;
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _client = null;
    _connected = false;
  }

  @override
  Future<List<RemoteFileInfo>> listFiles(String remotePath) async {
    if (_client == null) throw Exception('Not connected');

    final result = <RemoteFileInfo>[];
    try {
      final files = await _client!.readDir(remotePath);
      for (final file in files) {
        if (file.isDir == true) {
          // Recurse into subdirectories
          try {
            final subFiles = await listFiles('$remotePath/${file.name}');
            result.addAll(subFiles);
          } catch (_) {}
        } else {
          result.add(
            RemoteFileInfo(
              remotePath: file.path ?? '$remotePath/${file.name}',
              lastModified: file.mTime,
              size: file.size,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('WebDAV listFiles error: $e');
      rethrow;
    }
    return result;
  }

  @override
  Future<void> uploadFile(String localPath, String remotePath) async {
    if (_client == null) throw Exception('Not connected');

    try {
      await _client!.writeFromFile(localPath, remotePath);
    } catch (e) {
      debugPrint('WebDAV upload error: $e');
      rethrow;
    }
  }

  @override
  Future<void> downloadFile(String remotePath, String localPath) async {
    if (_client == null) throw Exception('Not connected');

    try {
      // Ensure local directory exists
      final dir = Directory(File(localPath).parent.path);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      await _client!.read2File(remotePath, localPath);
    } catch (e) {
      debugPrint('WebDAV download error: $e');
      rethrow;
    }
  }

  @override
  Future<void> ensureDir(String remotePath) async {
    if (_client == null) throw Exception('Not connected');

    try {
      await _client!.mkdir(remotePath);
    } catch (e) {
      // Directory may already exist — that's fine
      debugPrint('WebDAV mkdir (may already exist): $e');
    }
  }

  @override
  Future<void> deleteFile(String remotePath) async {
    if (_client == null) throw Exception('Not connected');
    try {
      await _client!.remove(remotePath);
    } catch (e) {
      debugPrint('WebDAV deleteFile error: $e');
    }
  }

  @override
  Future<void> deleteDirectory(String remotePath) async {
    if (_client == null) throw Exception('Not connected');
    try {
      await _client!.remove(remotePath);
    } catch (e) {
      debugPrint('WebDAV deleteDirectory error: $e');
    }
  }
}
