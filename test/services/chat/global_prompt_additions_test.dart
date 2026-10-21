// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';
import 'package:front_porch_ai/ui/settings/tabs/tabs.dart';

import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fpai_global_additions_');
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
      'passage_of_time_default': false,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => sandbox.path,
        );
  });
  tearDown(() async {
    await AppDatabase.closeAndReset();
    if (await sandbox.exists()) await sandbox.delete(recursive: true);
  });

  test(
    'blank additions preserve prompt bytes and saved additions reload',
    () async {
      final prefs = await SharedPreferences.getInstance();
      final settings = GenerationSettings()
        ..initializeBase(prefs, () {})
        ..load();
      expect(settings.withSystemPromptAddition('base\n'), 'base\n');
      expect(settings.withPostHistoryAddition('card phi\n'), 'card phi\n');
      await settings.setAdditionalSystemPrompt('  global system  ');
      await settings.setAdditionalPostHistoryInstructions('global phi');
      final reloaded = GenerationSettings()
        ..initializeBase(prefs, () {})
        ..load();
      expect(
        reloaded.withSystemPromptAddition('card system\n'),
        'card system\n\nglobal system',
      );
      expect(
        reloaded.withPostHistoryAddition('card phi\n'),
        'card phi\n\nglobal phi\n',
      );
      await reloaded.setAdditionalSystemPrompt('');
      await reloaded.setAdditionalPostHistoryInstructions('   ');
      expect(reloaded.withSystemPromptAddition('base'), 'base');
      expect(reloaded.withPostHistoryAddition('card phi\n'), 'card phi\n');
    },
  );

  test(
    'real chat assembly adds instructions once for send, regen, Continue and impersonation',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: ['The garden is peaceful.'],
      );
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      await storage.initialized;
      final chat =
          ChatService(
              KoboldService(storage)..setBaseUrl(backend.baseUrl),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await storage.generationSettings.setAdditionalSystemPrompt(
        'GLOBAL_SYSTEM for {{char}}',
      );
      await storage.generationSettings.setAdditionalPostHistoryInstructions(
        'GLOBAL_PHI for {{char}}',
      );
      final card = CharacterCard(
        name: 'Wren',
        firstMessage: 'Welcome.',
        systemPrompt: 'CARD_SYSTEM',
        postHistoryInstructions: 'CARD_PHI',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: false,
        ),
      )..dbId = 'global-test';
      await chat.setActiveCharacter(card);
      void assertRequest({bool impersonating = false, bool cleared = false}) {
        final body = jsonDecode(backend.lastChatBody) as Map;
        final messages = body['messages'] as List;
        final system = messages
            .where((m) => m['role'] == 'system')
            .map((m) => m['content'])
            .join('\n');
        final user = messages
            .where((m) => m['role'] == 'user')
            .map((m) => m['content'])
            .join('\n');
        expect(system, contains('CARD_SYSTEM'));
        expect(system.contains('GLOBAL_SYSTEM for Wren'), !cleared);
        expect(user.contains('GLOBAL_PHI for Wren'), !cleared);
        if (!cleared) {
          expect('GLOBAL_SYSTEM'.allMatches(system).length, 1);
          expect('GLOBAL_PHI'.allMatches(user).length, 1);
        }
        if (!impersonating) {
          expect(user, contains('CARD_PHI'));
          if (!cleared) {
            expect(
              user.indexOf('GLOBAL_PHI'),
              greaterThan(user.indexOf('CARD_PHI')),
            );
          }
        } else {
          expect(system, contains('IMPERSONATE'));
        }
        expect(card.systemPrompt, 'CARD_SYSTEM');
        expect(card.postHistoryInstructions, 'CARD_PHI');
      }

      await chat.sendMessage('Look at the garden.');
      assertRequest();
      await chat.regenerateLastMessage();
      assertRequest();
      await chat.continueGeneration();
      assertRequest();
      await chat.impersonateUser(prefix: 'I look', onToken: (_) {});
      assertRequest(impersonating: true);
      await storage.generationSettings.setAdditionalSystemPrompt('');
      await storage.generationSettings.setAdditionalPostHistoryInstructions('');
      await chat.sendMessage('Another look.');
      assertRequest(cleared: true);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'group speakers resolve global macros without changing group overrides',
    () async {
      HttpOverrides.global = null;
      final backend = await FakeBackendServer.start(
        replyPieces: ['The garden is peaceful.'],
      );
      final db = AppDatabase.forTesting();
      final storage = StorageService();
      await storage.initialized;
      final chat =
          ChatService(
              KoboldService(storage)..setBaseUrl(backend.baseUrl),
              UserPersonaService(db),
              storage,
              WorldRepository(storage, db),
            )
            ..setDatabase(db)
            ..setCharacterRepository(CharacterRepository(db, storage))
            ..testLlmServiceOverride = OpenRouterService(
              apiUrl: '${backend.baseUrl}/v1',
              modelName: 'smoke-model',
            );
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await storage.generationSettings.setAdditionalSystemPrompt(
        'GLOBAL_SYSTEM for {{char}}',
      );
      await storage.generationSettings.setAdditionalPostHistoryInstructions(
        'GLOBAL_PHI for {{char}}',
      );
      await db.insertGroup(
        GroupsCompanion.insert(id: 'global-group', name: 'Garden'),
      );
      for (final name in ['Wren', 'Robin']) {
        await db.insertGroupMember(
          GroupMembersCompanion.insert(
            id: name,
            groupId: 'global-group',
            name: name,
            firstMessage: const Value('Welcome.'),
            avatarFilename: Value('$name.png'),
            systemPrompt: Value('SPEAKER_$name'),
            frontPorchExtensions: Value(
              jsonEncode(
                FrontPorchExtensions(
                  realismEnabled: false,
                  needsSimEnabled: false,
                  chaosModeEnabled: false,
                ).toJson(),
              ),
            ),
          ),
        );
      }
      final group = GroupChat(
        id: 'global-group',
        name: 'Garden',
        systemPrompt: 'GROUP_SYSTEM',
        autoAdvance: false,
      );
      await chat.setActiveGroup(
        group,
        groupRepo: GroupChatRepository(storage, db),
      );
      expect(chat.groupCharacters, hasLength(2));
      for (var i = 0; i < 2; i++) {
        chat.setNextCharacter(chat.groupCharacters[i]);
        await chat.sendMessage('Look at the garden.');
        final body = jsonDecode(backend.lastChatBody) as Map;
        final messages = body['messages'] as List;
        final system = messages
            .where((m) => m['role'] == 'system')
            .map((m) => m['content'])
            .join('\n');
        final user = messages
            .where((m) => m['role'] == 'user')
            .map((m) => m['content'])
            .join('\n');
        final speaker = chat.messages.last.sender;
        expect(system, contains('GROUP_SYSTEM'));
        expect(system, contains('GLOBAL_SYSTEM for $speaker'));
        expect(user, contains('GLOBAL_PHI for $speaker'));
        expect(user, contains('SPEAKER_$speaker'));
        expect(group.systemPrompt, 'GROUP_SYSTEM');
        await chat.continueGeneration();
        final continued = jsonDecode(backend.lastChatBody) as Map;
        expect(
          jsonEncode(continued['messages']),
          contains('GLOBAL_PHI for $speaker'),
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'global prompt additions widget saves both fields without replacing the base',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = (await tester.runAsync(() async {
        final value = StorageService();
        await value.initialized;
        return value;
      }))!;
      addTearDown(storage.dispose);
      final systemPrompt = TextEditingController(
        text: storage.generationSettings.systemPrompt,
      );
      addTearDown(systemPrompt.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: GeneralTab(systemPromptController: systemPrompt),
            ),
          ),
        ),
      );
      // NOT pumpAndSettle: the spell-check row's spinner never settles.
      await tester.pump(const Duration(milliseconds: 100));
      final base = storage.generationSettings.systemPrompt;
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Additional system instructions'),
        'System addition',
      );
      await tester.enterText(
        find.widgetWithText(
          TextFormField,
          'Additional post-history instructions',
        ),
        'Post history addition',
      );
      await tester.pump();
      await tester.pump();
      expect(
        storage.generationSettings.additionalSystemPrompt,
        'System addition',
      );
      expect(
        storage.generationSettings.additionalPostHistoryInstructions,
        'Post history addition',
      );
      expect(storage.generationSettings.systemPrompt, base);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'the Group system prompt in General saves, starts from the built-in '
    'prompt, and reloads',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final storage = (await tester.runAsync(() async {
        final value = StorageService();
        await value.initialized;
        return value;
      }))!;
      addTearDown(storage.dispose);
      final systemPrompt = TextEditingController(
        text: storage.generationSettings.systemPrompt,
      );
      addTearDown(systemPrompt.dispose);
      await tester.pumpWidget(
        ChangeNotifierProvider<StorageService>.value(
          value: storage,
          child: MaterialApp(
            home: Scaffold(
              body: GeneralTab(systemPromptController: systemPrompt),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(storage.generationSettings.groupSystemPrompt, isEmpty);
      final base = storage.generationSettings.systemPrompt;
      expect(
        find.widgetWithText(ActionChip, '👥 Group Chat'),
        findsNothing,
        reason:
            'the group preset lives with the Group system prompt, not '
            'in the one-to-one fallback',
      );

      final field = find.widgetWithText(TextField, 'Group system prompt');
      await tester.ensureVisible(field);
      await tester.enterText(field, 'Novel style for every group.');
      await tester.pump();
      await tester.pump();
      expect(
        storage.generationSettings.groupSystemPrompt,
        'Novel style for every group.',
      );
      expect(storage.generationSettings.systemPrompt, base);

      final builtIn = find.text('Start from the built-in prompt');
      await tester.ensureVisible(builtIn);
      await tester.tap(builtIn);
      await tester.pump();
      await tester.pump();
      expect(
        storage.generationSettings.groupSystemPrompt,
        defaultGroupSystemPrompt,
      );

      final prefs = await SharedPreferences.getInstance();
      final reloaded = GenerationSettings()
        ..initializeBase(prefs, () {})
        ..load();
      expect(reloaded.groupSystemPrompt, defaultGroupSystemPrompt);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
