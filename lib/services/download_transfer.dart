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
import 'package:front_porch_ai/services/segmented_transfer.dart';
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
    this.progressEvery = const Duration(milliseconds: 100),
    this.segmentCount = 8,
    this.segmentMinBytes = 32 * 1024 * 1024,
  }) : freeBytes = freeBytes ?? freeDiskBytes;

  /// Extra request headers for a URL (the HuggingFace token, say).
  Map<String, String> Function(Uri url)? headersFor;

  final FreeDiskBytes freeBytes;
  final Duration progressEvery;

  /// Most parallel connections for one file. HuggingFace's CDN caps each
  /// connection well below a fast downlink, so one stream rarely fills it.
  final int segmentCount;

  /// Smallest range one connection is given; a file under twice this is
  /// fetched over a single connection.
  final int segmentMinBytes;

  /// Space kept free on top of the file itself.
  static const int spareBytes = 512 * 1024 * 1024;

  Future<TransferOutcome> run(
    DownloadTask task, {
    required void Function() onProgress,
  }) async {
    final client = http.Client();
    try {
      SegmentPlan? saved;
      try {
        saved = await SegmentPlan.load(task.segmentsPath);
      } on FormatException {
        task.restartFromZero(); // the plan placed the bytes; without it, start over
      }
      if (saved != null) {
        task.totalBytes = saved.total;
        await _ensureSpace(task, saved.total - saved.done, null);
        return await _segmented(task, saved, client, onProgress, null);
      }

      var response = await _send(client, task, task.rangeHeader);
      if (response.statusCode == 416 && task.rangeHeader != null) {
        await response.stream.drain<void>();
        task.restartFromZero();
        response = await _send(client, task, null);
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        await response.stream.drain<void>();
        throw HttpException('HTTP ${response.statusCode} for ${task.url}');
      }

      final total = int.tryParse(response.headers['content-length'] ?? '');
      final ranged = (response.headers['accept-ranges'] ?? '').contains(
        'bytes',
      );
      if (response.statusCode == 200 &&
          ranged &&
          segmentCount > 1 &&
          total != null &&
          total >= 2 * segmentMinBytes) {
        task.totalBytes = total;
        await _ensureSpace(task, total, response);
        await File(task.tempPath).writeAsBytes(const [], flush: true);
        final count = (total ~/ segmentMinBytes).clamp(2, segmentCount);
        return await _segmented(
          task,
          SegmentPlan.split(total, count),
          client,
          onProgress,
          response,
        );
      }
      return await _write(task, response, onProgress);
    } finally {
      client.close();
    }
  }

  /// GETs the task URL with any [headersFor] credentials. HuggingFace
  /// answers with a redirect to its CDN; dart:io drops `Authorization` when
  /// a redirect changes host, so the token stays with HuggingFace (pinned
  /// in download_manager_test).
  Future<http.StreamedResponse> _send(
    http.Client client,
    DownloadTask task,
    String? range,
  ) {
    final url = Uri.parse(task.url);
    final request = http.Request('GET', url)
      ..headers.addAll(headersFor?.call(url) ?? const {});
    if (range != null) request.headers['Range'] = range;
    return client.send(request);
  }

  Future<TransferOutcome> _segmented(
    DownloadTask task,
    SegmentPlan plan,
    http.Client client,
    void Function() onProgress,
    http.StreamedResponse? first,
  ) async {
    final finished = await SegmentedTransfer(
      task: task,
      plan: plan,
      send: (range) => _send(client, task, range),
      onProgress: onProgress,
      progressEvery: progressEvery,
    ).run(first: first);
    return finished ? TransferOutcome.finished : TransferOutcome.stopped;
  }

  /// Fails before writing when the models drive cannot hold [remaining].
  Future<void> _ensureSpace(
    DownloadTask task,
    int remaining,
    http.StreamedResponse? open,
  ) async {
    if (remaining <= 0) return;
    final free = await freeBytes(task.targetDir);
    if (free != null && free < remaining + spareBytes) {
      await open?.stream.drain<void>();
      throw DownloadSpaceException(remaining, free, task.targetDir);
    }
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

    await _ensureSpace(task, totalSize - startOffset, response);

    final sink = File(
      task.tempPath,
    ).openWrite(mode: startOffset > 0 ? FileMode.append : FileMode.write);
    final int received;
    try {
      final pumped = await pumpBytes(
        task,
        response.stream,
        sink,
        startOffset: startOffset,
        totalSize: totalSize,
        onProgress: onProgress,
        every: progressEvery,
      );
      if (pumped == null) return TransferOutcome.stopped;
      received = pumped;
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (totalSize > 0 && received < totalSize) {
      throw HttpException(
        'Connection closed at ${formatBytes(received)} of '
        '${formatBytes(totalSize)}',
      );
    }
    return TransferOutcome.finished;
  }
}

/// A connection that sends nothing for this long is treated as dead: the
/// attempt fails and the download's retry resumes it. Without it a stalled
/// socket hung a download forever.
const Duration stallTimeout = Duration(seconds: 60);

/// Writes [body] into [sink] for [task], updating its progress on every
/// chunk but calling [onProgress] at most once per [every]: HuggingFace and
/// Windows sockets hand back thousands of small chunks a second, and a
/// notify per chunk rebuilt the Model Manager until the window crawled.
/// Returns the byte count reached, or null when the task left `downloading`
/// (pause or cancel) mid-stream. The caller owns the sink.
Future<int?> pumpBytes(
  DownloadTask task,
  Stream<List<int>> body,
  IOSink sink, {
  required int startOffset,
  required int totalSize,
  required void Function() onProgress,
  required Duration every,
  Duration stall = stallTimeout,
}) async {
  var received = startOffset;
  final sinceTick = Stopwatch()..start();
  await for (final chunk in body.timeout(stall)) {
    if (task.state != DownloadTaskState.downloading) return null;
    sink.add(chunk);
    received += chunk.length;
    task.updateProgress(received, totalSize);
    if (sinceTick.elapsed >= every) {
      sinceTick.reset();
      onProgress();
    }
  }
  task.updateProgress(received, totalSize);
  return received;
}
