// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Review #599 (Stoop disclosure): the upload wizard must say in one line
// what the card actually carries once locations ride the envelope.

import 'package:flutter_test/flutter_test.dart';

import 'package:front_porch_ai/ui/pages/repository/stoop_upload/stoop_upload_review_step.dart';

void main() {
  Map<String, dynamic> envelope({required String name, List<dynamic>? locs}) =>
      {'name': name, 'locations': ?locs};

  test('a leaf place names the root it rides and counts the branch', () {
    final note = stoopWorldShareNote(
      envelope(
        name: 'Earth',
        locs: [
          {
            'name': 'Asia',
            'locations': [
              {'name': 'Tea House'},
            ],
          },
        ],
      ),
      ridesUpstream: true,
    );
    expect(note, contains('"Earth"'));
    expect(note, contains('2 place(s)'));
  });

  test('a tree root counts its whole subtree', () {
    final note = stoopWorldShareNote(
      envelope(
        name: 'Bletchport',
        locs: [
          {
            'name': 'Quarter',
            'locations': [
              {'name': 'Room'},
            ],
          },
          {'name': 'Docks'},
        ],
      ),
      ridesUpstream: false,
    );
    expect(note, contains('3 place(s)'));
  });

  test('a plain world with no tree says nothing extra', () {
    expect(
      stoopWorldShareNote(envelope(name: 'Lonely'), ridesUpstream: false),
      isNull,
    );
  });
}
