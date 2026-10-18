// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/storage/settings/generation_settings.dart';
import 'package:front_porch_ai/ui/chat_components/prompt_source_picker.dart';
import '../../../integration_test/support/fake_backend.dart';
import '../../helpers/chat_db_teardown.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fpai_prompt_picker_');
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

  CharacterCard wrenCard() => CharacterCard(
    name: 'Wren',
    firstMessage: 'Welcome.',
    systemPrompt: 'CARD_SYSTEM for {{char}}',
    postHistoryInstructions: 'CARD_PHI',
    frontPorchExtensions: FrontPorchExtensions(
      realismEnabled: false,
      needsSimEnabled: false,
      chaosModeEnabled: false,
    ),
  )..dbId = 'picker-test';

  Map<String, String> lastSent(
    FakeBackendServer backend, {
    bool impersonating = false,
  }) {
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
    return {'system': system, 'user': user};
  }

  Future<(ChatService, AppDatabase, FakeBackendServer)> openChat(
    StorageService storage,
  ) async {
    HttpOverrides.global = null;
    final backend = await FakeBackendServer.start(
      replyPieces: ['The garden is peaceful.'],
    );
    final db = AppDatabase.forTesting();
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
    return (chat, db, backend);
  }

  Future<StorageService> seededStorage() async {
    final storage = StorageService();
    await storage.initialized;
    await storage.generationSettings.setSystemPrompt(
      'FALLBACK_BASE for {{char}}',
    );
    await storage.generationSettings.setAdditionalSystemPrompt(
      'GLOBAL_SYSTEM for {{char}}',
    );
    await storage.generationSettings.setAdditionalPostHistoryInstructions(
      'GLOBAL_PHI for {{char}}',
    );
    return storage;
  }

  test(
    "source 'user' swaps the base to the fallback on send and impersonate",
    () async {
      final storage = await seededStorage();
      final (chat, db, backend) = await openChat(storage);
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await chat.setActiveCharacter(wrenCard());
      chat.sessionGenSettings = ChatGenerationSettings(
        systemPromptSource: 'user',
      );
      await chat.sendMessage('Look at the garden.');
      var sent = lastSent(backend);
      expect(sent['system'], contains('FALLBACK_BASE for Wren'));
      expect(sent['system'], isNot(contains('CARD_SYSTEM')));
      expect(sent['system'], contains('GLOBAL_SYSTEM for Wren'));
      expect('FALLBACK_BASE'.allMatches(sent['system']!).length, 1);
      expect(sent['user'], contains('GLOBAL_PHI for Wren'));
      expect(sent['user'], contains('CARD_PHI'));

      await chat.impersonateUser(prefix: 'I look', onToken: (_) {});
      sent = lastSent(backend, impersonating: true);
      expect(sent['system'], contains('FALLBACK_BASE for Wren'));
      expect(sent['system'], isNot(contains('CARD_SYSTEM')));
      expect(sent['system'], contains('IMPERSONATE'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'amendments off removes both global additions from the sent prompt',
    () async {
      final storage = await seededStorage();
      final (chat, db, backend) = await openChat(storage);
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await chat.setActiveCharacter(wrenCard());
      chat.sessionGenSettings = ChatGenerationSettings(
        systemPromptSource: 'card',
        promptAmendmentsEnabled: false,
      );
      await chat.sendMessage('Look at the garden.');
      final sent = lastSent(backend);
      expect(sent['system'], contains('CARD_SYSTEM for Wren'));
      expect(sent['system'], isNot(contains('GLOBAL_SYSTEM')));
      expect(sent['user'], contains('CARD_PHI'));
      expect(sent['user'], isNot(contains('GLOBAL_PHI')));

      await chat.impersonateUser(prefix: 'I look', onToken: (_) {});
      final impersonated = lastSent(backend, impersonating: true);
      expect(impersonated['system'], isNot(contains('GLOBAL_SYSTEM')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the explicit card+amendments preset is byte-identical to the null state',
    () async {
      final storage = await seededStorage();
      final (chat, db, backend) = await openChat(storage);
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await chat.setActiveCharacter(wrenCard());
      chat.sessionGenSettings = ChatGenerationSettings();
      await chat.sendMessage('Same line.');
      final inherited = lastSent(backend);
      expect(inherited['system'], contains('CARD_SYSTEM for Wren'));
      expect(
        'GLOBAL_SYSTEM for Wren'.allMatches(inherited['system']!).length,
        1,
      );

      chat.sessionGenSettings = ChatGenerationSettings(
        systemPromptSource: 'card',
        promptAmendmentsEnabled: true,
      );
      await chat.sendMessage('Same line.');
      final explicit = lastSent(backend);
      expect(explicit['system'], inherited['system']);
      expect(
        'GLOBAL_SYSTEM for Wren'.allMatches(explicit['system']!).length,
        1,
      );
      expect(
        explicit['user']!.endsWith(
          inherited['user']!.substring(inherited['user']!.indexOf('CARD_PHI')),
        ),
        isTrue,
        reason: 'the post-history tail changed between the two sends',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'the live budget estimate carries the same base and amendment as the sent prompt',
    () async {
      final storage = await seededStorage();
      final (chat, db, backend) = await openChat(storage);
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });
      await chat.setActiveCharacter(wrenCard());

      Future<Map<String, String>> estimateFor(
        ChatGenerationSettings settings,
      ) async {
        chat.sessionGenSettings = settings;
        await chat.sendMessage('Look at the garden.');
        await chat.estimateContextBudgetNow();
        final sent = lastSent(backend);
        final estimate = chat.lastPromptSections['System Prompt'] ?? '';
        return {'sent': sent['system']!, 'estimate': estimate};
      }

      var pair = await estimateFor(ChatGenerationSettings());
      expect(pair['estimate'], contains('CARD_SYSTEM'));
      expect(pair['estimate'], contains('GLOBAL_SYSTEM'));
      expect(pair['sent'], contains('CARD_SYSTEM for Wren'));

      pair = await estimateFor(
        ChatGenerationSettings(systemPromptSource: 'user'),
      );
      expect(pair['estimate'], contains('FALLBACK_BASE'));
      expect(pair['estimate'], isNot(contains('CARD_SYSTEM')));
      expect(pair['estimate'], contains('GLOBAL_SYSTEM'));
      expect(pair['sent'], contains('FALLBACK_BASE for Wren'));
      expect(pair['sent'], isNot(contains('CARD_SYSTEM')));

      pair = await estimateFor(
        ChatGenerationSettings(promptAmendmentsEnabled: false),
      );
      expect(pair['estimate'], contains('CARD_SYSTEM'));
      expect(pair['estimate'], isNot(contains('GLOBAL_SYSTEM')));
      expect(pair['sent'], isNot(contains('GLOBAL_SYSTEM')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'new 1:1 chats arm the picker; remembered choices apply without asking',
    () async {
      final storage = await seededStorage();
      final (chat, db, backend) = await openChat(storage);
      addTearDown(() async {
        await disposeChatThenCloseDb(chat, db);
        await backend.close();
      });

      await chat.setActiveCharacter(wrenCard());
      expect(chat.promptPickerPendingFor, isNotNull);

      await chat.applyPromptSourceChoice(preset: 'user', remember: true);
      expect(chat.promptPickerPendingFor, isNull);
      expect(chat.sessionGenSettings.systemPromptSource, 'user');
      expect(chat.sessionGenSettings.promptAmendmentsEnabled, isTrue);
      expect(
        storage.generationSettings.promptPickerChoices.values,
        contains('user'),
      );

      await chat.startNewChat();
      expect(chat.promptPickerPendingFor, isNull);
      expect(chat.sessionGenSettings.systemPromptSource, 'user');

      await chat.sendMessage('Look at the garden.');
      await chat.forkFromMessage(chat.messages.length - 1);
      expect(chat.sessionGenSettings.systemPromptSource, 'user');
      expect(chat.sessionGenSettings.promptAmendmentsEnabled, isTrue);
      expect(chat.promptPickerPendingFor, isNull);

      await chat.applyPromptSourceChoice(preset: 'card', askEveryChat: true);
      expect(
        storage.generationSettings.promptPickerChoices.values,
        isNot(contains('user')),
      );
      expect(chat.sessionGenSettings.systemPromptSource, 'card');

      await chat.setActiveCharacter(
        CharacterCard(name: 'Plain', firstMessage: 'Hi')..dbId = 'picker-plain',
      );
      expect(chat.promptPickerPendingFor, isNull);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'the picker renders a 5k card prompt without overflow and both panes scroll',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final longPrompt =
          'Wren tends the failing greenhouse at the edge of town, '
              'noticing plants the way other people notice faces. '
              'Salt air, peat, rust, the particular green of old glass. '
              'She never lies about facts, only about feelings. ' *
          45;
      expect(longPrompt.length, greaterThan(5000));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: PromptSourcePickerDialog(
                characterName: 'Wren',
                cardPrompt: longPrompt,
                userPrompt: GenerationSettings.defaultSystemPrompt,
                amendment: 'Never speak or act for {{user}}.',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final dialog = find.byKey(const ValueKey('prompt-source-dialog'));
      expect(dialog, findsOneWidget);
      // The Dialog widget's own box fills the route; the visible surface is
      // its Material — that is the box the 85% cap must hold.
      final surface = find
          .descendant(of: dialog, matching: find.byType(Material))
          .first;
      final viewportHeight = MediaQuery.sizeOf(tester.element(dialog)).height;
      expect(
        tester.getSize(surface).height,
        lessThanOrEqualTo(viewportHeight * 0.85 + 1),
        reason: 'the dialog surface escaped the 85% viewport cap',
      );
      expect(tester.getTopLeft(surface).dy, greaterThanOrEqualTo(0));
      expect(
        tester.getBottomRight(surface).dy,
        lessThanOrEqualTo(700),
        reason: 'the dialog surface left the screen',
      );

      for (final paneId in ['card', 'user']) {
        final pane = find.byKey(ValueKey('prompt-pane-$paneId'));
        expect(pane, findsOneWidget);
        final scrollable = find
            .descendant(of: pane, matching: find.byType(Scrollable))
            .first;
        final position = tester.state<ScrollableState>(scrollable).position;
        expect(
          position.maxScrollExtent,
          greaterThan(0),
          reason: 'the $paneId pane does not scroll',
        );
        final before = position.pixels;
        await tester.drag(pane, const Offset(0, -80));
        await tester.pump();
        expect(
          tester.state<ScrollableState>(scrollable).position.pixels,
          greaterThan(before),
          reason: 'the $paneId pane did not scroll on drag',
        );
      }
    },
  );

  test('an unanswered picker never lands on the next chat opened', () async {
    final storage = await seededStorage();
    final (chat, db, backend) = await openChat(storage);
    addTearDown(() async {
      await disposeChatThenCloseDb(chat, db);
      await backend.close();
    });
    final rook = CharacterCard(
      name: 'Rook',
      firstMessage: 'Evening.',
      systemPrompt: 'ROOK_SYSTEM',
      frontPorchExtensions: FrontPorchExtensions(
        realismEnabled: false,
        needsSimEnabled: false,
        chaosModeEnabled: false,
      ),
    )..dbId = 'picker-rook';

    // Rook gets a saved chat of its own.
    await chat.setActiveCharacter(rook);
    await chat.applyPromptSourceChoice(preset: 'card+amend');
    await chat.sendMessage('Hello there.');
    expect(chat.currentSessionId, isNotNull);

    // A new Wren chat is armed, then left unanswered (started from the
    // phone, or the desktop was on another page) while Rook's saved
    // chat is opened.
    await chat.setActiveCharacter(wrenCard());
    expect(chat.promptPickerPendingFor, 'Wren');
    await chat.setActiveCharacter(rook);
    expect(chat.promptPickerPendingFor, isNull);

    // A late answer describes the chat on screen, never Wren's.
    await chat.applyPromptSourceChoice(preset: 'user', remember: true);
    final choices = storage.generationSettings.promptPickerChoices;
    expect(choices.containsKey('Wren'), isFalse);
    expect(choices['Rook'], 'user');
  }, timeout: const Timeout(Duration(minutes: 2)));
}
