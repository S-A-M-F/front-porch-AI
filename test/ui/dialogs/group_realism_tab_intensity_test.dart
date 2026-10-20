// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Group Settings → Realism drew a red error box instead of the tab. Its
// mood-strength dropdown offered calm / moderate / intense while a group is
// created with the engine's mild / moderate / strong (default mild), and a
// dropdown handed a value that is not one of its items fails its assertion.
// So every group made with the default broke the tab. A real group, so the
// seed comes through the real ChatService door the tab reads.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/group_settings.dart';
import 'package:front_porch_ai/ui/dialogs/group_settings/member_baseline_seed.dart';
import 'package:front_porch_ai/utils/group_realism_blobs.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_grp_mood_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late GroupChatRepository repo;

  Future<void> boot() async {
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': true,
    });
    db = AppDatabase.forTesting(sameIsolate: true);
    storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage));
    await storage.initialized;
    repo = GroupChatRepository(storage, db);

    // Ada as a new group seeds her (mild); Bex as the old tab saved her.
    final blobs = buildGroupRealismBlobs(
      seeds: {
        'mem-ada': defaultGroupMemberRealismSeed(),
        'mem-bex': {
          ...defaultGroupMemberRealismSeed(),
          'emotionIntensity': 'intense',
        },
      },
      needsEnabled: true,
      timeOfDay: 'morning',
      dayCount: 1,
    );
    await db.insertGroup(
      GroupsCompanion.insert(
        id: 'grp-mood',
        name: 'The Porch',
        defaultMemberRealismState: Value(blobs.defaultMemberJson),
        baselineRealismState: Value(blobs.baselineJson),
      ),
    );
    for (final m in [('mem-ada', 'Ada'), ('mem-bex', 'Bex')]) {
      await db.insertGroupMember(
        GroupMembersCompanion.insert(
          id: m.$1,
          groupId: 'grp-mood',
          name: m.$2,
          firstMessage: const Value('Evening.'),
        ),
      );
    }
    await chat.setActiveGroup(
      GroupChat(
        id: 'grp-mood',
        name: 'The Porch',
        defaultMemberRealismState: blobs.defaultMemberJson,
        baselineRealismState: blobs.baselineJson,
      ),
      groupRepo: repo,
    );
    await chat.setRealismEnabled(true);
  }

  testWidgets('the Realism tab draws with the strengths groups are made with', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(boot);
    addTearDown(() => tester.runAsync(() => disposeChatThenCloseDb(chat, db)));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GroupRealismNeedsTab(chatService: chat, groupRepo: repo),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    final shown = tester
        .widgetList<DropdownButtonFormField<String>>(
          find.byType(DropdownButtonFormField<String>),
        )
        .map((d) => d.initialValue)
        .where(emotionIntensities.contains)
        .toList();
    expect(shown, [
      'mild',
      'strong',
    ], reason: 'Ada as made; Bex read from intense');
  });
}
