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

import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/download_transfer.dart';
import 'package:front_porch_ai/utils/utils.dart';

/// Manages a queue of model downloads with support for:
/// - Multiple concurrent downloads (configurable, default: 3)
/// - Pause and resume via HTTP Range requests
/// - Progress tracking with speed and ETA
/// - Automatic retry on failure
/// - File integrity verification
class DownloadManager extends ChangeNotifier {
  /// Maximum number of concurrent downloads.
  final int maxConcurrent;

  /// The directory where downloaded models are stored. NOT final: the provider
  /// re-points it to the live `StorageService.modelsDir` once storage finishes
  /// its async init. Without this it can be captured as a relative `models/`
  /// (rootPath still null at create time), so downloads land beside the running
  /// binary instead of the configured models folder and never appear as
  /// installed. New tasks read this when queued; in-flight tasks keep their own.
  String _targetDir;
  String get targetDir => _targetDir;

  /// Assigning a new dir re-ensures it exists. This is how the real absolute
  /// models dir actually gets created: at construction [targetDir] is briefly
  /// the relative fallback `models/` (which [_ensureTargetDir] skips), then the
  /// provider re-points us here once StorageService init resolves the absolute
  /// path.
  set targetDir(String value) {
    if (value == _targetDir) return;
    _targetDir = value;
    _ensureTargetDir();
  }

  /// Queue of download tasks.
  final List<DownloadTask> _queue = [];

  /// Controller for the download processing loop.
  final StreamController<DownloadAction> _actionController =
      StreamController<DownloadAction>.broadcast();

  /// Whether the processing loop is running.
  bool _isProcessing = false;

  /// Unmodifiable view of the download queue.
  List<DownloadTask> get queue => List.unmodifiable(_queue);

  /// Currently active (downloading or verifying) tasks.
  List<DownloadTask> get activeDownloads =>
      _queue.where((t) => t.state.isActive).toList();

  /// Queued (pending) tasks waiting for a slot.
  List<DownloadTask> get pendingDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.pending).toList();

  /// Completed tasks.
  List<DownloadTask> get completedDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.completed).toList();

  /// Failed tasks.
  List<DownloadTask> get failedDownloads =>
      _queue.where((t) => t.state == DownloadTaskState.failed).toList();

  /// Total progress across all active downloads (0.0 to 1.0).
  double get overallProgress {
    final active = activeDownloads;
    if (active.isEmpty) return 0.0;
    final sum = active.fold<double>(0, (s, t) => s + t.progress);
    return sum / active.length;
  }

  /// Combined download speed of all active downloads.
  double get overallSpeed =>
      activeDownloads.fold<double>(0, (s, t) => s + t.speedBytesPerSec);

  /// Moves the bytes; owns Range resume, the free-space check and the
  /// progress throttle.
  final DownloadTransfer _transfer;

  /// Extra request headers per URL (the HuggingFace token).
  set headersFor(Map<String, String> Function(Uri url)? value) =>
      _transfer.headersFor = value;

  DownloadManager({
    required String targetDir,
    this.maxConcurrent = 3,
    FreeDiskBytes? freeBytes,
    int segmentMinBytes = 32 * 1024 * 1024,
  }) : _targetDir = targetDir,
       _transfer = DownloadTransfer(
         freeBytes: freeBytes,
         segmentMinBytes: segmentMinBytes,
       ) {
    _ensureTargetDir();
    _startProcessing();
  }

  /// Ensures the target directory exists — best-effort, and never throws.
  ///
  /// Skips relative paths: during early startup [targetDir] is briefly the
  /// relative fallback `models/` (StorageService.rootPath still null), and on
  /// desktop GUI launches the working directory is `/`, so creating a relative
  /// dir throws `Read-only file system`. The provider re-points us at the real
  /// absolute dir moments later (see the [targetDir] setter).
  Future<void> _ensureTargetDir() async {
    final dir = Directory(targetDir);
    if (!dir.isAbsolute) return;
    try {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    } catch (e) {
      debugPrint(
        '[DownloadManager] Could not create models dir "$targetDir": $e',
      );
    }
  }

  /// Starts the download processing loop.
  void _startProcessing() {
    if (_isProcessing) return;
    _isProcessing = true;
    _actionController.stream.listen(_processQueue);
  }

  /// Stops the download processing loop.
  void _stopProcessing() {
    _isProcessing = false;
    _actionController.close();
  }

  /// Adds a new download task to the queue.
  /// Returns the created task.
  DownloadTask addDownload({
    required String url,
    required String filename,
    String? repoId,
    String? expectedSha256,
  }) {
    // Check if this file is already being downloaded or exists
    final existingIndex = _queue.indexWhere((t) => t.filename == filename);
    DownloadTask? existing;
    if (existingIndex != -1) {
      existing = _queue[existingIndex];
    }

    if (existing != null) {
      // Task already exists
      if (existing.state == DownloadTaskState.pending ||
          existing.state == DownloadTaskState.downloading) {
        return existing; // Already in queue
      } else if (existing.state == DownloadTaskState.paused ||
          existing.state == DownloadTaskState.failed) {
        _requeue(existing);
        _actionController.add(const DownloadAction.resume());
        notifyListeners();
        return existing;
      } else if (existing.state == DownloadTaskState.completed) {
        return existing; // Already done
      }
    }

    final task = DownloadTask(
      url: url,
      filename: filename,
      targetDir: targetDir,
      repoId: repoId,
      expectedSha256: expectedSha256,
    );

    _queue.add(task);
    _actionController.add(const DownloadAction.start());
    notifyListeners();
    return task;
  }

  /// Pauses a specific download by task ID.
  bool pauseDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;
    if (task.state != DownloadTaskState.downloading &&
        task.state != DownloadTaskState.verifying) {
      return false;
    }

    task.pause();
    _actionController.add(const DownloadAction.start()); // Process next
    notifyListeners();
    return true;
  }

  /// Resumes a specific download by task ID.
  bool resumeDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;
    if (!task.state.canResume) return false;

    _requeue(task);
    _actionController.add(const DownloadAction.start());
    notifyListeners();
    return true;
  }

  /// Cancels a specific download by task ID.
  bool cancelDownload(String taskId) {
    final task = _queue.where((t) => t.id == taskId).firstOrNull;
    if (task == null) return false;

    task.cancel();
    _actionController.add(const DownloadAction.start()); // Process next
    notifyListeners();
    return true;
  }

  /// Removes a completed/failed/cancelled task from the queue.
  bool removeDownload(String taskId) {
    final index = _queue.indexWhere((t) => t.id == taskId);
    if (index == -1) return false;

    final task = _queue[index];
    if (task.state.isActive) return false; // Can't remove active downloads

    _queue.removeAt(index);
    notifyListeners();
    return true;
  }

  /// Pauses all active downloads.
  void pauseAll() {
    for (final task in _queue) {
      if (task.state == DownloadTaskState.downloading ||
          task.state == DownloadTaskState.verifying) {
        task.pause();
      }
    }
    notifyListeners();
  }

  /// Resumes all paused downloads.
  void resumeAll() {
    for (final task in _queue) {
      if (task.state.canResume) {
        _requeue(task);
      }
    }
    _actionController.add(const DownloadAction.start());
    notifyListeners();
  }

  /// Clears all completed downloads from the queue.
  void clearCompleted() {
    _queue.removeWhere((t) => t.state == DownloadTaskState.completed);
    notifyListeners();
  }

  /// Puts a paused or failed task back in line, keeping its `.part` file
  /// so the next transfer resumes with a Range request.
  void _requeue(DownloadTask task) {
    task.resume();
    task.state = DownloadTaskState.pending;
  }

  /// Starts pending tasks while slots are free. Each runs on its own; a
  /// task leaves `pending` synchronously in [_executeDownload], so two
  /// passes never start the same one.
  void _processQueue(DownloadAction action) {
    for (final task in _queue.toList()) {
      if (activeDownloads.length >= maxConcurrent) return;
      if (task.state != DownloadTaskState.pending) continue;
      unawaited(_executeDownload(task));
    }
  }

  /// Executes a single download with retry logic.
  Future<void> _executeDownload(DownloadTask task) async {
    task.start();
    notifyListeners();

    try {
      final outcome = await _transfer.run(task, onProgress: notifyListeners);
      if (outcome == TransferOutcome.stopped) {
        // Paused keeps its .part for resume; cancelled drops it now that
        // the sink is closed (Windows cannot delete an open file).
        if (task.state == DownloadTaskState.cancelled) task.restartFromZero();
        return;
      }

      if (task.expectedSha256 != null) {
        task.state = DownloadTaskState.verifying;
        notifyListeners();
        final actual = await fileSha256(task.tempPath);
        if (task.state != DownloadTaskState.verifying) return;
        if (actual != task.expectedSha256!.toLowerCase()) {
          task.restartFromZero();
          task.fail('Checksum mismatch: the file arrived damaged');
          return;
        }
      }

      task.complete();
    } on DownloadSpaceException catch (e) {
      task.fail(e.message);
    } catch (e) {
      task.fail('Download failed: $e');

      if (task.retryCount < task.maxRetries) {
        await Future.delayed(const Duration(seconds: 2));
        // The user may have paused, cancelled or removed it meanwhile.
        if (task.state != DownloadTaskState.failed || !_queue.contains(task)) {
          return;
        }
        task.retry();
        await _executeDownload(task);
        return;
      }
    } finally {
      notifyListeners();
      if (!_actionController.isClosed) {
        _actionController.add(const DownloadAction.start());
      }
    }
  }

  bool _disposed = false;

  /// A transfer can outlive the manager (app shutdown, a test tearDown);
  /// its late progress ticks must not reach a disposed notifier.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopProcessing();
    super.dispose();
  }
}

/// Actions that can trigger queue processing.
sealed class DownloadAction {
  const DownloadAction();

  /// Start processing pending downloads.
  const factory DownloadAction.start() = _StartAction;

  /// Resume a specific download.
  const factory DownloadAction.resume() = _ResumeAction;
}

final class _StartAction extends DownloadAction {
  const _StartAction();
}

final class _ResumeAction extends DownloadAction {
  const _ResumeAction();
}
