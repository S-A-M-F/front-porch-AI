// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';

/// One line of what the wizard was doing, stamped with the time since the
/// run started.
typedef WorldProgressLine = ({String at, String text});

/// What the wizard has been doing this run, line by line, for the panel
/// under the spinner: the current line, the ones before it, and how long
/// the run has taken. Plain Dart; the state owns one and ticks it.
class WorldProgressLog {
  WorldProgressLog({DateTime Function()? now, this.keep = 12})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// How many lines are kept; older ones fall off the top.
  final int keep;

  DateTime? _since;
  final List<WorldProgressLine> _lines = [];

  /// Every kept line, oldest first; the last is the current one.
  List<WorldProgressLine> get lines => List.unmodifiable(_lines);

  /// The lines before the current one, newest first, for the panel.
  List<WorldProgressLine> get earlier => _lines.length < 2
      ? const []
      : _lines.sublist(0, _lines.length - 1).reversed.toList();

  String get current => _lines.isEmpty ? '' : _lines.last.text;

  bool get running => _since != null;

  Duration get elapsed =>
      _since == null ? Duration.zero : _now().difference(_since!);

  /// Clock-face elapsed: 0:42, 12:05, 1:03:09.
  String get elapsedLabel => worldElapsedLabel(elapsed);

  /// A run begins: the clock starts and the old lines go.
  void start() {
    _since = _now();
    _lines.clear();
  }

  /// The run is over; the lines stay for reading until the next start.
  void stop() => _since = null;

  /// One more line. The same line twice in a row is kept once.
  void note(String text) {
    final line = text.trim();
    if (line.isEmpty || line == current) return;
    _lines.add((at: elapsedLabel, text: line));
    while (_lines.length > keep) {
      _lines.removeAt(0);
    }
  }
}
