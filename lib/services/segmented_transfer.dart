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
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:front_porch_ai/models/models.dart';

/// One byte range of a segmented download: `[start, end)`, [done] bytes in.
class Segment {
  Segment(this.start, this.end, [this.done = 0]);

  final int start;
  final int end;
  int done;

  int get next => start + done;
  bool get finished => next >= end;
}

/// How a file is split, persisted beside the `.part` file so a pause, a
/// failure or an app restart resumes every segment where it stopped.
///
/// The plan is written before the first byte, so a `.part` without one was
/// written by the plain single-stream path and is safe to Range-resume.
class SegmentPlan {
  SegmentPlan(this.total, this.segments);

  final int total;
  final List<Segment> segments;

  int get done => segments.fold(0, (s, seg) => s + seg.done);

  /// [count] equal ranges, the last one taking the remainder.
  factory SegmentPlan.split(int total, int count) {
    final size = total ~/ count;
    return SegmentPlan(total, [
      for (var i = 0; i < count; i++)
        Segment(i * size, i == count - 1 ? total : (i + 1) * size),
    ]);
  }

  Map<String, dynamic> toJson() => {
    'total': total,
    'segments': [
      for (final s in segments) [s.start, s.end, s.done],
    ],
  };

  static Future<SegmentPlan?> load(String path) async {
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final map = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      return SegmentPlan(map['total'] as int, [
        for (final s in map['segments'] as List)
          Segment(s[0] as int, s[1] as int, s[2] as int),
      ]);
    } catch (e) {
      // A plan we cannot read cannot place the bytes already written.
      await file.delete();
      throw FormatException('Unreadable download state: $e');
    }
  }

  Future<void> save(String path) =>
      File(path).writeAsString(jsonEncode(toJson()), flush: true);
}

/// Fetches a [SegmentPlan]'s unfinished segments in parallel, each worker
/// writing its own range of the shared `.part` file through its own handle.
/// A worker whose connection drops retries its remaining range a few times
/// before the whole transfer fails (and the plan keeps what arrived).
class SegmentedTransfer {
  SegmentedTransfer({
    required this.task,
    required this.plan,
    required this.client,
    required this.request,
    required this.onProgress,
    required this.progressEvery,
  });

  final DownloadTask task;
  final SegmentPlan plan;
  final http.Client client;

  /// Builds a GET for the task URL with the given Range header.
  final http.Request Function(String range) request;
  final void Function() onProgress;
  final Duration progressEvery;

  static const int _attempts = 3;
  static const int _bufferBytes = 1024 * 1024;

  Object? _failure;
  DateTime _lastTick = DateTime.now();
  DateTime _lastSave = DateTime.now();
  Future<void>? _saving;

  bool get _halt =>
      _failure != null || task.state != DownloadTaskState.downloading;

  /// Runs every unfinished segment; [first] is an already-open response
  /// that starts at byte 0 and becomes segment 0's stream.
  /// Returns true when every byte arrived, false when paused or cancelled.
  Future<bool> run({http.StreamedResponse? first}) async {
    await plan.save(task.segmentsPath);
    final workers = <Future<void>>[];
    for (final seg in plan.segments) {
      if (seg.finished) continue;
      final opening = seg.start == 0 && seg.done == 0 ? first : null;
      if (opening != null) first = null;
      workers.add(_worker(seg, opening));
    }
    if (first != null) await first.stream.drain<void>();
    await Future.wait(workers);

    await _saving;
    await plan.save(task.segmentsPath);
    if (_failure != null) throw _failure!;
    if (task.state != DownloadTaskState.downloading) return false;

    if (plan.done < plan.total) {
      throw const HttpException('A download segment ended early');
    }
    await File(task.segmentsPath).delete();
    task.updateProgress(plan.total, plan.total);
    return true;
  }

  Future<void> _worker(Segment seg, http.StreamedResponse? opening) async {
    var failures = 0;
    while (!seg.finished && !_halt) {
      try {
        final response =
            opening ??
            await client.send(request('bytes=${seg.next}-${seg.end - 1}'));
        opening = null;
        final ok =
            response.statusCode == 206 ||
            (response.statusCode == 200 && seg.next == 0);
        if (!ok) {
          await response.stream.drain<void>();
          throw HttpException('HTTP ${response.statusCode} for a segment');
        }
        await _drain(seg, response);
      } catch (e) {
        if (_halt) return;
        if (++failures >= _attempts) {
          _failure ??= e;
          return;
        }
        await Future<void>.delayed(Duration(seconds: failures));
      }
    }
  }

  /// Writes the response into the segment's range, stopping at its end
  /// (segment 0 may be reading a whole-file 200 response).
  Future<void> _drain(Segment seg, http.StreamedResponse response) async {
    final file = await File(task.tempPath).open(mode: FileMode.append);
    final buffer = BytesBuilder(copy: false);
    Future<void> flush() async {
      if (buffer.isEmpty) return;
      await file.setPosition(seg.next);
      final bytes = buffer.takeBytes();
      await file.writeFrom(bytes);
      seg.done += bytes.length;
    }

    try {
      await for (final chunk in response.stream) {
        if (_halt) break;
        final room = seg.end - seg.next - buffer.length;
        buffer.add(chunk.length > room ? chunk.sublist(0, room) : chunk);
        if (buffer.length >= _bufferBytes || chunk.length >= room) {
          await flush();
          _tick();
        }
        if (seg.finished) break;
      }
      await flush();
    } finally {
      await file.close();
    }
    _tick();
  }

  void _tick() {
    final now = DateTime.now();
    if (now.difference(_lastTick) >= progressEvery) {
      _lastTick = now;
      task.updateProgress(plan.done, plan.total);
      onProgress();
    }
    if (_saving == null &&
        now.difference(_lastSave) >= const Duration(seconds: 1)) {
      _lastSave = now;
      _saving = plan
          .save(task.segmentsPath)
          .catchError((Object e) => _failure ??= e)
          .whenComplete(() => _saving = null);
    }
  }
}
