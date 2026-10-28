// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// THE SYSTEM HEAD DOES NOT CHANGE BETWEEN A SEND AND A CONTINUE.
//
// The after-lookup line ("react to it as yourself") is advertised on a
// direct user send only, never on Continue or an autonomous turn. While it
// rode the system prompt, byte one of the head flipped between those turn
// kinds and a local prefix cache re-read the whole transcript on every
// Continue — the same class of move the state zone, the lore buckets and
// the speaker card already made. It rides the tail after the transcript
// now, under the same gate, so the head stays byte-identical.
//
// Guard proven red before passing: with the line appended to
// `t.systemPrompt`, the send's and the Continue's system messages differed
// and the line was missing from the send's user message.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chat.dart';
import 'package:front_porch_ai/services/chat/prompt_injection/prompt_injection.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../helpers/chat_db_teardown.dart';

/// Search is offered on eligible turns; the model never looks anything up.
class _SearchOfferedLlm extends LLMService {
  final List<GenerationParams> streams = [];

  @override
  Future<LlmToolResponse?> generateWithTools(
    GenerationParams params,
    List<Map<String, dynamic>> tools,
  ) async {
    final names = [
      for (final tool in tools) (tool['function'] as Map?)?['name'] as String?,
    ];
    if (!names.contains(kWebSearchToolName)) return null;
    return const LlmToolResponse(calls: [], text: '');
  }

  @override
  Stream<String> generateStream(GenerationParams params) async* {
    streams.add(params);
    yield 'Reply ${streams.length}.';
  }

  @override
  bool get isReady => true;

  @override
  String get backendName => 'system-head-stability-test';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(pathProvider, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_system_head_').path;
        }
        return null;
      });

  late AppDatabase db;
  late StorageService storage;
  late ChatService chat;
  late _SearchOfferedLlm llm;
  late int httpCalls;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      'pockets_enabled': false,
      'journal_enabled': false,
      'passage_of_time_default': false,
    });
    db = AppDatabase.forTesting();
    storage = StorageService();
    llm = _SearchOfferedLlm();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..setCharacterRepository(CharacterRepository(db, storage))
          ..testLlmServiceOverride = llm;
    await storage.initialized;
    await storage.webSearchSettings.setSearchApiKey('head-stability-key');
    await storage.webSearchSettings.setWebSearchDefault(true);
    httpCalls = 0;
    chat.webSearchService.fetch = (uri, key) async {
      httpCalls++;
      return jsonEncode({'results': <Object>[]});
    };
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    storage.dispose();
  });

  /// The reply stream of the latest turn: the one that carries a system
  /// message (clock-only streams carry none).
  GenerationParams replyAfter(int from) =>
      llm.streams.skip(from).where((s) => s.systemPrompt != null).single;

  test(
    'send, Continue and regenerate share one system message; the '
    'after-lookup line rides the tail only on turns that offer search',
    () async {
      await chat.setActiveCharacter(
        CharacterCard(
          name: 'Mara',
          description: 'Exists only inside the system-head test.',
          firstMessage: 'Mara waits on the porch.',
          frontPorchExtensions: FrontPorchExtensions(
            realismEnabled: false,
            needsSimEnabled: false,
            chaosModeEnabled: false,
          ),
        )..dbId = 'system-head-mara',
      );

      await chat.sendMessage('What is the weather doing tonight?');
      final send = replyAfter(0);
      expect(
        send.prompt,
        contains(kWebSearchCharacterLine),
        reason: 'a direct user send still carries the line, after the chat',
      );
      expect(
        send.systemPrompt,
        isNot(contains(kWebSearchCharacterLine)),
        reason: 'the line is off the cached head',
      );

      var seen = llm.streams.length;
      await chat.continueGeneration();
      final cont = replyAfter(seen);
      expect(
        cont.systemPrompt,
        send.systemPrompt,
        reason:
            'byte-identical head, or a local prefix cache re-reads the '
            'whole transcript on every Continue',
      );
      expect(
        cont.prompt,
        isNot(contains(kWebSearchCharacterLine)),
        reason: 'Continue does not offer a lookup, so no line',
      );

      seen = llm.streams.length;
      await chat.regenerateLastMessage();
      final regen = replyAfter(seen);
      expect(regen.systemPrompt, send.systemPrompt);
      expect(
        regen.prompt,
        contains(kWebSearchCharacterLine),
        reason: 'a regenerate is a new try and offers the lookup again',
      );
      expect(httpCalls, 0, reason: 'the model declined every lookup');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
