// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:front_porch_ai/services/download_manager.dart';
import 'package:front_porch_ai/models/download_task.dart';

void main() {
  group('DownloadManager', () {
    late Directory tempDir;
    late DownloadManager manager;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fpai_download_test_');
      manager = DownloadManager(targetDir: tempDir.path);
    });

    tearDown(() async {
      manager.dispose();
      await tempDir.delete(recursive: true);
    });

    test('creates with default max concurrent of 3', () {
      expect(manager.maxConcurrent, equals(3));
    });

    test('adds download to queue', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      expect(manager.queue.length, equals(1));
      expect(manager.queue.first, equals(task));
      expect(task.state, equals(DownloadTaskState.pending));
    });

    test('returns existing task if same filename already queued', () {
      final task1 = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      final task2 = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      expect(manager.queue.length, equals(1));
      expect(task1, equals(task2));
    });

    test('pauses active download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      // Simulate download in progress
      task.state = DownloadTaskState.downloading;
      task.progress = 0.5;

      final result = manager.pauseDownload(task.id);
      expect(result, isTrue);
      expect(task.state, equals(DownloadTaskState.paused));
    });

    test('cannot pause non-active download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      final result = manager.pauseDownload(task.id);
      expect(result, isFalse);
      expect(task.state, equals(DownloadTaskState.pending));
    });

    test('resumes paused download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      task.state = DownloadTaskState.paused;

      final result = manager.resumeDownload(task.id);
      expect(result, isTrue);
    });

    test('cannot resume completed download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      task.state = DownloadTaskState.completed;

      final result = manager.resumeDownload(task.id);
      expect(result, isFalse);
    });

    test('cancels download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      final result = manager.cancelDownload(task.id);
      expect(result, isTrue);
      expect(task.state, equals(DownloadTaskState.cancelled));
    });

    test('removes completed download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      task.state = DownloadTaskState.completed;

      final result = manager.removeDownload(task.id);
      expect(result, isTrue);
      expect(manager.queue.length, equals(0));
    });

    test('cannot remove active download', () {
      final task = manager.addDownload(
        url: 'https://example.com/model.gguf',
        filename: 'test-model.gguf',
      );

      task.state = DownloadTaskState.downloading;

      final result = manager.removeDownload(task.id);
      expect(result, isFalse);
      expect(manager.queue.length, equals(1));
    });

    test('pauseAll pauses all active downloads', () {
      manager.addDownload(
        url: 'https://example.com/model1.gguf',
        filename: 'model1.gguf',
      );
      manager.addDownload(
        url: 'https://example.com/model2.gguf',
        filename: 'model2.gguf',
      );

      // Simulate both downloading
      for (final task in manager.queue) {
        task.state = DownloadTaskState.downloading;
      }

      manager.pauseAll();

      for (final task in manager.queue) {
        expect(task.state, equals(DownloadTaskState.paused));
      }
    });

    test('clearCompleted removes only completed tasks', () {
      final task1 = manager.addDownload(
        url: 'https://example.com/model1.gguf',
        filename: 'model1.gguf',
      );
      final task2 = manager.addDownload(
        url: 'https://example.com/model2.gguf',
        filename: 'model2.gguf',
      );
      final task3 = manager.addDownload(
        url: 'https://example.com/model3.gguf',
        filename: 'model3.gguf',
      );

      task1.state = DownloadTaskState.completed;
      task2.state = DownloadTaskState.downloading;
      task3.state = DownloadTaskState.completed;

      manager.clearCompleted();

      expect(manager.queue.length, equals(1));
      expect(manager.queue.first, equals(task2));
    });

    test('overallProgress calculates average of active downloads', () {
      manager.addDownload(
        url: 'https://example.com/model1.gguf',
        filename: 'model1.gguf',
      );
      manager.addDownload(
        url: 'https://example.com/model2.gguf',
        filename: 'model2.gguf',
      );

      final tasks = manager.queue;
      tasks[0].state = DownloadTaskState.downloading;
      tasks[0].progress = 0.4;
      tasks[1].state = DownloadTaskState.downloading;
      tasks[1].progress = 0.8;

      expect(manager.overallProgress, closeTo(0.6, 0.0001));
    });

    test('overallProgress is 0 when no active downloads', () {
      expect(manager.overallProgress, equals(0.0));
    });

    test('activeDownloads returns only active tasks', () {
      final task1 = manager.addDownload(
        url: 'https://example.com/model1.gguf',
        filename: 'model1.gguf',
      );
      final task2 = manager.addDownload(
        url: 'https://example.com/model2.gguf',
        filename: 'model2.gguf',
      );

      task1.state = DownloadTaskState.downloading;
      task2.state = DownloadTaskState.pending;

      expect(manager.activeDownloads.length, equals(1));
      expect(manager.activeDownloads.first, equals(task1));
    });

    test('pendingDownloads returns only pending tasks', () {
      final task1 = manager.addDownload(
        url: 'https://example.com/model1.gguf',
        filename: 'model1.gguf',
      );
      final task2 = manager.addDownload(
        url: 'https://example.com/model2.gguf',
        filename: 'model2.gguf',
      );

      task1.state = DownloadTaskState.downloading;
      // task2 is already pending

      expect(manager.pendingDownloads.length, equals(1));
      expect(manager.pendingDownloads.first, equals(task2));
    });
  });

  group('DownloadTask', () {
    test('generates unique ID', () {
      final task1 = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );
      final task2 = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      expect(task1.id, isNot(equals(task2.id)));
    });

    test('calculates progress correctly', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.updateProgress(500, 1000);
      expect(task.progress, equals(0.5));

      task.updateProgress(750, 1000);
      expect(task.progress, equals(0.75));
    });

    test('formats speed display correctly', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.speedBytesPerSec = 500;
      expect(task.speedDisplay, contains('B/s'));

      task.speedBytesPerSec = 1500;
      expect(task.speedDisplay, contains('KB/s'));

      task.speedBytesPerSec = 5 * 1024 * 1024;
      expect(task.speedDisplay, contains('MB/s'));
    });

    test('formats ETA display correctly', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.etaSeconds = 0;
      expect(task.etaDisplay, equals('--:--'));

      task.etaSeconds = 95;
      expect(task.etaDisplay, equals('1m 35s'));

      task.etaSeconds = 3661;
      expect(task.etaDisplay, equals('1h 1m'));
    });

    test('formats size display correctly', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.totalBytes = 500;
      expect(task.totalDisplay, equals('500 B'));

      task.totalBytes = 1500;
      expect(task.totalDisplay, equals('1.5 KB'));

      task.totalBytes = 5 * 1024 * 1024;
      expect(task.totalDisplay, equals('5.0 MB'));

      task.totalBytes = 4 * 1024 * 1024 * 1024;
      expect(task.totalDisplay, equals('4.00 GB'));
    });

    test('pause and resume work correctly', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.start();
      expect(task.state, equals(DownloadTaskState.downloading));

      task.pause();
      expect(task.state, equals(DownloadTaskState.paused));
      expect(task.pausedAt, isNotNull);

      task.resume();
      expect(task.state, equals(DownloadTaskState.downloading));
      expect(task.pausedAt, isNull);
    });

    test('cancel cleans up and sets state', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.start();
      task.cancel();

      expect(task.state, equals(DownloadTaskState.cancelled));
      expect(task.speedBytesPerSec, equals(0));
      expect(task.etaSeconds, equals(0));
    });

    test('retry increments count and resets error', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
      );

      task.fail('Test error');
      expect(task.errorMessage, equals('Test error'));

      task.retry();
      expect(task.retryCount, equals(1));
      expect(task.errorMessage, isNull);
    });

    test('retry exceeds max retries marks as failed', () {
      final task = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
        maxRetries: 2,
      );

      // Simulate 2 previous retries
      task.retryCount = 2;
      task.fail('Test error');

      task.retry();

      expect(task.state, equals(DownloadTaskState.failed));
      expect(task.errorMessage, contains('Max retries'));
    });

    test('serialization and deserialization', () {
      final original = DownloadTask(
        url: 'https://example.com/model.gguf',
        filename: 'model.gguf',
        targetDir: '/tmp',
        repoId: 'test/repo',
        expectedSha256: 'abc123',
        maxRetries: 5,
      );

      original.updateProgress(5000, 10000);
      original.pause();

      final json = original.toJson();
      final restored = DownloadTask.fromJson(json);

      expect(restored.id, equals(original.id));
      expect(restored.url, equals(original.url));
      expect(restored.filename, equals(original.filename));
      expect(restored.bytesDownloaded, equals(5000));
      expect(restored.totalBytes, equals(10000));
      expect(restored.state, equals(DownloadTaskState.paused));
    });
  });

  group('DownloadManager transfers', () {
    late Directory tempDir;
    late _ByteServer server;
    late DownloadManager manager;
    final bytes = List<int>.generate(256 * 1024, (i) => (i * 31) & 0xff);
    final sha = sha256.convert(bytes).toString();

    setUpAll(() => HttpOverrides.global = null);

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('fpai_transfer_test_');
      server = await _ByteServer.start(bytes);
      manager = DownloadManager(targetDir: tempDir.path);
    });

    tearDown(() async {
      manager.dispose();
      await server.close();
      await tempDir.delete(recursive: true);
    });

    DownloadTask queue({String? expectedSha256}) => manager.addDownload(
      url: server.url,
      filename: 'model.gguf',
      expectedSha256: expectedSha256,
    );

    test('pause keeps the partial file and never marks it complete; '
        'resume finishes it byte-exact with a Range request', () async {
      server.chunkDelay = const Duration(milliseconds: 20);
      final task = queue();
      await _until(() => task.bytesDownloaded >= 64 * 1024);
      expect(manager.pauseDownload(task.id), isTrue);
      await _until(() => server.openResponses == 0);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(task.state, DownloadTaskState.paused);
      expect(File(task.targetPath).existsSync(), isFalse);
      final partial = File(task.tempPath).lengthSync();
      expect(partial, inExclusiveRange(0, bytes.length));

      server.chunkDelay = Duration.zero;
      expect(manager.resumeDownload(task.id), isTrue);
      await _until(() => task.state == DownloadTaskState.completed);

      expect(File(task.targetPath).readAsBytesSync(), bytes);
      expect(server.ranges.last, startsWith('bytes='));
      expect(server.ranges.last, isNot('bytes=0-'));
    });

    test(
      'a refused Range restarts once from zero instead of looping',
      () async {
        server.chunkDelay = const Duration(milliseconds: 20);
        final task = queue();
        await _until(() => task.bytesDownloaded >= 32 * 1024);
        manager.pauseDownload(task.id);
        await _until(() => server.openResponses == 0);

        server
          ..refuseRanges = true
          ..chunkDelay = Duration.zero;
        manager.resumeDownload(task.id);
        await _until(() => task.state == DownloadTaskState.completed);

        expect(File(task.targetPath).readAsBytesSync(), bytes);
        expect(server.requests, 3); // first, refused Range, from zero
      },
    );

    test('a matching SHA-256 completes', () async {
      final task = queue(expectedSha256: sha.toUpperCase());
      await _until(() => task.state.isTerminal);
      expect(
        task.state,
        DownloadTaskState.completed,
        reason: task.errorMessage,
      );
      expect(File(task.targetPath).readAsBytesSync(), bytes);
    });

    test('a wrong SHA-256 fails and leaves no file behind', () async {
      final task = queue(expectedSha256: '0' * 64);
      await _until(() => task.state.isTerminal);
      expect(task.state, DownloadTaskState.failed);
      expect(task.errorMessage, contains('Checksum'));
      expect(File(task.targetPath).existsSync(), isFalse);
      expect(File(task.tempPath).existsSync(), isFalse);
    });

    test('too little free space fails at once, without retrying', () async {
      manager.dispose();
      manager = DownloadManager(
        targetDir: tempDir.path,
        freeBytes: (_) async => 1024 * 1024,
      );
      final task = queue();
      await _until(() => task.state.isTerminal);
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      expect(task.state, DownloadTaskState.failed);
      expect(task.errorMessage, contains('Not enough disk space'));
      expect(task.retryCount, 0);
      expect(server.requests, 1);
      expect(File(task.tempPath).existsSync(), isFalse);
    });

    test(
      'cancel mid-transfer leaves neither file and stays cancelled',
      () async {
        server.chunkDelay = const Duration(milliseconds: 20);
        final task = queue();
        await _until(() => task.bytesDownloaded >= 32 * 1024);
        expect(manager.cancelDownload(task.id), isTrue);
        await _until(() => server.openResponses == 0);
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(task.state, DownloadTaskState.cancelled);
        expect(File(task.targetPath).existsSync(), isFalse);
        expect(File(task.tempPath).existsSync(), isFalse);
      },
    );
  });
}

Future<void> _until(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final end = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(end)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Serves one byte array over loopback HTTP with real Range support, in
/// 8 KB chunks spaced by [chunkDelay] so a test can pause mid-file.
class _ByteServer {
  _ByteServer._(this._server, this._bytes);

  final HttpServer _server;
  final List<int> _bytes;
  Duration chunkDelay = Duration.zero;
  bool refuseRanges = false;
  int requests = 0;
  int openResponses = 0;
  final List<String> ranges = [];

  String get url => 'http://127.0.0.1:${_server.port}/model.gguf';

  static Future<_ByteServer> start(List<int> bytes) async {
    final http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final server = _ByteServer._(http, bytes);
    http.listen(server._handle);
    return server;
  }

  Future<void> _handle(HttpRequest req) async {
    requests++;
    openResponses++;
    final res = req.response;
    try {
      final range = req.headers.value('range');
      var start = 0;
      if (range != null) {
        ranges.add(range);
        if (refuseRanges) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          return;
        }
        start = int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          'content-range',
          'bytes $start-${_bytes.length - 1}/${_bytes.length}',
        );
      }
      res.contentLength = _bytes.length - start;
      for (var i = start; i < _bytes.length; i += 8192) {
        res.add(_bytes.sublist(i, (i + 8192).clamp(0, _bytes.length)));
        await res.flush();
        if (chunkDelay > Duration.zero) await Future<void>.delayed(chunkDelay);
      }
    } catch (_) {
      // The client hung up (pause or cancel); that is the point.
    } finally {
      try {
        await res.close();
      } catch (_) {}
      openResponses--;
    }
  }

  Future<void> close() => _server.close(force: true);
}
