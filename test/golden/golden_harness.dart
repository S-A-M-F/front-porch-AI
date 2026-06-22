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

import 'package:flutter_test/flutter_test.dart';

/// Text/JSON golden (snapshot) harness for deterministic, non-widget outputs.
///
/// Stores committed snapshots under `test/golden/_goldens/<group>/<name>.golden`
/// (text) and `<name>.golden.json` (JSON). Each run compares the live output to
/// the committed snapshot; on drift the test fails with a readable line diff.
///
/// To (re)generate snapshots after an intentional behavior change:
///   `UPDATE_GOLDENS=1 flutter test test/golden`
/// then review `git diff` before committing — a golden diff is a behavior change
/// that must be justified in the PR.
///
/// This is intentionally separate from Flutter's built-in `matchesGoldenFile`
/// (used for widget pixel goldens, refreshed via `--update-goldens`) so a
/// text/JSON refresh never silently rewrites PNGs and vice-versa.

/// Root of committed text/JSON goldens. `flutter test` runs with cwd = package
/// root, so this relative path is stable.
const String _goldensRoot = 'test/golden/_goldens';

bool get _updateRequested =>
    Platform.environment['UPDATE_GOLDENS'] == '1' ||
    Platform.environment['UPDATE_GOLDENS'] == 'true';

String _normalize(String raw) {
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final trimmed = lines.map((l) => l.replaceAll(RegExp(r'[ \t]+$'), '')).toList();
  // Drop trailing blank lines, then guarantee exactly one trailing newline.
  while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
    trimmed.removeLast();
  }
  return '${trimmed.join('\n')}\n';
}

/// Compare [actual] against the committed text golden at
/// `_goldens/<group>/<name>.golden`. Writes/overwrites the golden instead of
/// asserting when `UPDATE_GOLDENS=1`.
void expectGolden(String actual, {required String group, required String name}) {
  _compare(actual, group: group, name: name, extension: 'golden');
}

/// JSON variant: canonicalizes [actual] (recursively sorted keys, 2-space
/// indent) so field-order churn never produces a false diff, then compares to
/// `_goldens/<group>/<name>.golden.json`.
void expectGoldenJson(Object? actual,
    {required String group, required String name}) {
  const encoder = JsonEncoder.withIndent('  ');
  final canonical = encoder.convert(_canonicalize(actual));
  _compare(canonical, group: group, name: name, extension: 'golden.json');
}

Object? _canonicalize(Object? value) {
  if (value is Map) {
    final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
    return {for (final k in sortedKeys) k: _canonicalize(value[k])};
  }
  if (value is Iterable) {
    return value.map(_canonicalize).toList();
  }
  return value;
}

void _compare(String actual,
    {required String group, required String name, required String extension}) {
  final normalized = _normalize(actual);
  final file = File('$_goldensRoot/$group/$name.$extension');

  if (_updateRequested) {
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(normalized);
    // Surface that an update happened so it can't pass silently unnoticed.
    printOnFailure('Updated golden: ${file.path}');
    return;
  }

  if (!file.existsSync()) {
    fail(
      'Missing golden ${file.path}.\n'
      'Run `UPDATE_GOLDENS=1 flutter test` to create it, then review the diff.',
    );
  }

  final expected = _normalize(file.readAsStringSync());
  if (expected != normalized) {
    fail(
      'Golden mismatch for ${file.path}:\n${_diff(expected, normalized)}\n'
      'If this change is intentional, run '
      '`UPDATE_GOLDENS=1 flutter test` and review the diff.',
    );
  }
}

/// Minimal, readable line diff capped so failures stay legible under the
/// `expanded` reporter.
String _diff(String expected, String actual) {
  final e = expected.split('\n');
  final a = actual.split('\n');
  final max = e.length > a.length ? e.length : a.length;
  final out = <String>[];
  var shown = 0;
  for (var i = 0; i < max && shown < 40; i++) {
    final el = i < e.length ? e[i] : null;
    final al = i < a.length ? a[i] : null;
    if (el != al) {
      if (el != null) out.add('- [${i + 1}] $el');
      if (al != null) out.add('+ [${i + 1}] $al');
      shown++;
    }
  }
  if (shown == 0) out.add('(whitespace-only difference)');
  return out.join('\n');
}
