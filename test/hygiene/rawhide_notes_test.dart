// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// docs/Rawhide.md is the in-app "What's New" for nightlies. The nightly
// workflow pastes every line under its first `## ` heading into the release
// body, and tools/rotate-rawhide-notes.sh removes the bullets a nightly
// shipped. These checks keep the file in the shape both of those rely on,
// and stop it turning back into a diary: one heading, one line per bullet,
// no bullet said twice, and a cap that trips when rotation has stalled.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const String kNotesPath = 'docs/Rawhide.md';
const String kHeading = '## Unreleased';

/// A nightly ships most days, so more than this many unshipped bullets means
/// the rotation step is not running, not that a lot landed.
const int kMaxUnreleasedBullets = 40;

final RegExp _lastShipped = RegExp(
  r'^Last shipped nightly: `nightly-rawhide\.\d{8}\.[0-9a-f]{7,40}`$',
);
final RegExp _boldTitle = RegExp(r'\*\*(.+?)\*\*');

String _normalize(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// The start of a bullet, for a failure message that stays readable.
String _clip(String s) => s.length > 80 ? '${s.substring(0, 80)}…' : s;

void main() {
  late List<String> lines;
  late int headingIndex;
  late List<String> bullets;

  setUpAll(() {
    final file = File(kNotesPath);
    expect(file.existsSync(), isTrue, reason: '$kNotesPath is missing');
    lines = file.readAsLinesSync();
    headingIndex = lines.indexWhere((l) => l.startsWith('## '));
    bullets = headingIndex < 0
        ? const []
        : lines.skip(headingIndex + 1).where((l) => l.trim().isNotEmpty).toList();
  });

  test('one heading, and it is "$kHeading"', () {
    final headings = lines.where((l) => l.startsWith('## ')).toList();
    expect(
      headings,
      [kHeading],
      reason:
          'The nightly takes the first "## " section as the release body, '
          'and rotation clears it. Keep exactly one heading, "$kHeading"; '
          'shipped notes live in the GitHub release, not here.',
    );
  });

  test('records the last shipped nightly tag above the heading', () {
    final marker = lines.take(headingIndex < 0 ? lines.length : headingIndex);
    expect(
      marker.where(_lastShipped.hasMatch).length,
      1,
      reason:
          'Expected one line like "Last shipped nightly: '
          '`nightly-rawhide.20261020.601968c`" before $kHeading. '
          'tools/rotate-rawhide-notes.sh writes it.',
    );
  });

  test('every line under the heading is one bullet with a bold title', () {
    for (final l in bullets) {
      expect(
        l.startsWith('- '),
        isTrue,
        reason:
            'Only single-line bullets go under $kHeading (the release body '
            'is pasted line by line, and rotation removes whole lines). '
            'Offending line: "${_clip(l)}"',
      );
      expect(
        _boldTitle.hasMatch(l),
        isTrue,
        reason:
            'A bullet needs a **bold title** so it can be told apart: '
            '"${_clip(l)}"',
      );
    }
  });

  test('no note is said twice', () {
    final seenTitles = <String, String>{};
    final seenBodies = <String>{};
    for (final l in bullets) {
      final title = _normalize(_boldTitle.firstMatch(l)?.group(1) ?? '');
      final earlier = seenTitles[title];
      expect(
        earlier,
        isNull,
        reason:
            'Two bullets share the title "$title". Merge them into one; a '
            'note is mentioned once and only once.',
      );
      seenTitles[title] = l;
      expect(
        seenBodies.add(_normalize(l)),
        isTrue,
        reason: 'Duplicate bullet: "${_clip(l)}"',
      );
    }
  });

  test('rotation has not stalled', () {
    expect(
      bullets.length,
      lessThanOrEqualTo(kMaxUnreleasedBullets),
      reason:
          '${bullets.length} unshipped bullets. A nightly ships most days, so '
          'this means the notes were not cleared after it. Run '
          'tools/rotate-rawhide-notes.sh <last nightly tag> and check the '
          'rotate-notes job in nightly.yml.',
    );
  });

  test('no placeholders or raw macro names reach users', () {
    for (final l in bullets) {
      expect(
        l.contains('{{') || l.contains('TODO') || l.contains('TBD'),
        isFalse,
        reason: 'User-facing note still has a placeholder: "${_clip(l)}"',
      );
    }
  });
}
