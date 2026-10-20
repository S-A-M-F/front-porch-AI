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

// SETTINGS PARITY — DESKTOP SIDE. docs/design/settings-parity-manifest.json
// maps every web Settings control to its desktop home. This guard proves the
// Dart half: each control's `dartMarker` string still lives in the pinned
// `dart` file. If a desktop control moves tabs or gets renamed, the manifest
// and this test fail together — the web half is guarded by
// web_ui/src/pages/SettingsPage.parity.test.tsx.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings parity manifest', () {
    final file = File('docs/design/settings-parity-manifest.json');
    final manifest =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final sections = (manifest['sections'] as List).cast<String>();
    final controls = manifest['controls'] as Map<String, dynamic>;

    test('every control pins a known web section', () {
      for (final entry in controls.entries) {
        final control = entry.value as Map<String, dynamic>;
        expect(
          sections,
          contains(control['section']),
          reason: '${entry.key} pins unknown section ${control['section']}',
        );
      }
    });

    test('every desktop marker still lives in its pinned file', () {
      for (final entry in controls.entries) {
        final control = entry.value as Map<String, dynamic>;
        final source = File(control['dart'] as String);
        expect(
          source.existsSync(),
          isTrue,
          reason: '${entry.key} pins missing file ${control['dart']}',
        );
        expect(
          source.readAsStringSync(),
          contains(control['dartMarker'] as String),
          reason:
              '${entry.key}: "${control['dartMarker']}" no longer in '
              '${control['dart']} — the desktop control moved or was renamed; '
              'update the manifest in the same change',
        );
      }
    });
  });
}
