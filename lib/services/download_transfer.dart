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

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// How a transfer ended without throwing.
enum TransferOutcome {
  /// Every byte arrived and the `.part` file is closed.
  finished,

  /// The task left `downloading` (pause or cancel) and the sink is closed.
  stopped,
}

/// The models drive cannot hold what is left of the file. Not retried.
class DownloadSpaceException implements Exception {
  DownloadSpaceException(this.neededBytes, this.freeBytes, this.dir);

  final int neededBytes;
  final int freeBytes;
  final String dir;

  String get message =>
      'Not enough disk space in $dir: needs ${formatBytes(neededBytes)}, '
      '${formatBytes(freeBytes)} free';

  @override
  String toString() => message;
}

/// Moves one task's bytes from its URL into its `.part` file: Range resume,
/// a single from-zero retry when the server refuses the Range, a free-space
/// check against what the server says is left, and progress callbacks no
/// more often than [progressEvery].
class DownloadTransfer {
  DownloadTransfer({
    this.headersFor,
    FreeDiskBytes? freeBytes,
    this.progressEvery = const Duration(milliseconds: 250),
  }) : freeBytes = freeBytes ?? freeDiskBytes;

  /// Extra request headers for a URL (the HuggingFace token, say).
  Map<String, String> Function(Uri url)? headersFor;

  final FreeDiskBytes freeBytes;
  final Duration progressEvery;

  /// Space kept free on top of the file itself.
  static const int spareBytes = 512 * 1024 * 1024;

  Future<TransferOutcome> run(
    DownloadTask task, {
    required void Function() onProgress,
  }) async {
    final client = http.Client();
    try {
      var response = await _send(client, task);
      if (response.statusCode == 416 && task.rangeHeader != null) {
        await response.stream.drain<void>();
        task.restartFromZero();
        response = await _send(client, task);
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw HttpException('HTTP ${response.statusCode} for ${task.url}');
      }
      return await _write(task, response, onProgress);
    } finally {
      client.close();
    }
  }

  Future<http.StreamedResponse> _send(http.Client client, DownloadTask task) {
    final url = Uri.parse(task.url);
    final request = http.Request('GET', url);
    request.headers.addAll(headersFor?.call(url) ?? const {});
    final range = task.rangeHeader;
    if (range != null) request.headers['Range'] = range;
    return client.send(request);
  }

  Future<TransferOutcome> _write(
    DownloadTask task,
    http.StreamedResponse response,
    void Function() onProgress,
  ) async {
    final length = int.tryParse(response.headers['content-length'] ?? '');
    var startOffset = 0;
    var totalSize = length ?? 0;
    if (response.statusCode == 206) {
      final match = RegExp(
        r'bytes (\d+)-(\d+)/(\d+)',
      ).firstMatch(response.headers['content-range'] ?? '');
      if (match != null) {
        startOffset = int.parse(match.group(1)!);
        totalSize = int.parse(match.group(3)!);
      } else {
        startOffset = task.bytesDownloaded;
        totalSize = startOffset + (length ?? 0);
      }
    }
    if (totalSize > 0) task.totalBytes = totalSize;

    final remaining = totalSize - startOffset;
    if (remaining > 0) {
      final free = await freeBytes(task.targetDir);
      if (free != null && free < remaining + spareBytes) {
        await response.stream.drain<void>();
        throw DownloadSpaceException(remaining, free, task.targetDir);
      }
    }

    final sink = File(
      task.tempPath,
    ).openWrite(mode: startOffset > 0 ? FileMode.append : FileMode.write);
    var received = startOffset;
    var lastTick = DateTime.now();
    try {
      await for (final chunk in response.stream) {
        if (task.state != DownloadTaskState.downloading) {
          return TransferOutcome.stopped;
        }
        sink.add(chunk);
        received += chunk.length;
        task.updateProgress(received, totalSize);
        final now = DateTime.now();
        if (now.difference(lastTick) >= progressEvery) {
          lastTick = now;
          onProgress();
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    task.updateProgress(received, totalSize);
    if (totalSize > 0 && received < totalSize) {
      throw HttpException(
        'Connection closed at ${formatBytes(received)} of '
        '${formatBytes(totalSize)}',
      );
    }
    return TransferOutcome.finished;
  }
}
