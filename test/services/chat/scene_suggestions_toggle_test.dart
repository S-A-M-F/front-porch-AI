// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Slice 6 introduces the GLOBAL "Scene suggestions" Porch Life switch: one
// row covering suggested scene moves (and, later, minted places). Unlike the
// Scene-Guest switch it defaults OFF — design §7 "One global switch for scene
// suggestions", and CLAUDE.md: a brand-new model-touching behavior ships off
// until the author turns it on. These guards fail until RealismSettings
// grows the field, the pref key, and the snapshot plumbing.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/services/storage/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<RealismSettings> settings() async {
    final s = RealismSettings();
    s.initializeBase(await SharedPreferences.getInstance(), () {});
    s.load();
    return s;
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('scene suggestions are OFF by default', () async {
    final s = await settings();
    expect(
      s.sceneSuggestionsEnabled,
      isFalse,
      reason:
          'a new, model-driven suggestion feature ships off; the author '
          'opts in from Porch Life, matching design §7',
    );
  });

  test('turning it on persists across a reload', () async {
    final s = await settings();
    await s.setSceneSuggestionsEnabled(true);
    expect(s.sceneSuggestionsEnabled, isTrue);

    final reloaded = await settings();
    expect(reloaded.sceneSuggestionsEnabled, isTrue);
  });

  test('a stored value survives; a missing key means off', () async {
    SharedPreferences.setMockInitialValues({'scene_suggestions_enabled': true});
    expect((await settings()).sceneSuggestionsEnabled, isTrue);

    SharedPreferences.setMockInitialValues({});
    expect((await settings()).sceneSuggestionsEnabled, isFalse);
  });
}
