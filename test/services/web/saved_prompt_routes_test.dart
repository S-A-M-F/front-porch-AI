// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// The web relay for the shared pool of saved prompts behind Settings' two
// prompt slots: a taken name is refused unless the slot asked to update it,
// a delete lets go of every slot that named the prompt, and a Save settings
// from a page that still names a deleted prompt does not bring the pick
// back.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf_router/shelf_router.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/web/auth/auth_service.dart';
import 'package:front_porch_ai/services/web/facade/facades.dart';
import 'package:front_porch_ai/services/web/routes/routes.dart';
import 'package:front_porch_ai/services/web/web_server_deps.dart';

import '../../golden/support/fakes.dart';

class _Llm extends FakeLLMProvider {
  final OpenRouterService remote = OpenRouterService();
  @override
  OpenRouterService get openRouterService => remote;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late AppDatabase db;
  late StorageService storage;
  late Router router;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('fpai saved prompts');
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          return call.method == 'getApplicationDocumentsDirectory'
              ? root.path
              : null;
        });
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    db = AppDatabase.forTesting();
    storage = StorageService();
    await storage.initialized;
    router = Router();
    WebSettingsRoutes(
      WebServerDeps(
        storage: storage,
        db: db,
        auth: AuthService(db),
        settingsFacade: SettingsFacade(storage, _Llm()),
      ),
      router,
    );
    WebSavedPromptRoutes(storage, router);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  Future<(int, Map<String, dynamic>)> call(
    String method,
    String path, [
    Object? body,
  ]) async {
    final res = await router.call(
      shelf.Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {'content-type': 'application/json'},
        body: body == null ? null : jsonEncode(body),
      ),
    );
    return (
      res.statusCode,
      jsonDecode(await res.readAsString()) as Map<String, dynamic>,
    );
  }

  test('a taken name is refused unless the slot updates it', () async {
    final (ok, pool) = await call('POST', '/api/saved-prompts', {
      'name': 'Novel',
      'content': 'Write like a novel.',
    });
    expect(ok, 200);
    expect(pool['savedPrompts'], [
      {'name': 'Novel', 'content': 'Write like a novel.'},
    ]);

    final (taken, _) = await call('POST', '/api/saved-prompts', {
      'name': 'Novel',
      'content': 'Something else.',
    });
    expect(taken, 409);

    final (updated, _) = await call('POST', '/api/saved-prompts', {
      'name': 'Novel',
      'content': 'Write like a long novel.',
      'overwrite': true,
    });
    expect(updated, 200);
    expect(
      userSavedPrompts(storage.presetSettings.savedPrompts).single['content'],
      'Write like a long novel.',
    );
  });

  test('a delete from one slot lets go of both, and a stale Save settings '
      'does not bring the pick back', () async {
    await call('POST', '/api/saved-prompts', {
      'name': 'Novel',
      'content': 'Write like a novel.',
    });
    await call('POST', '/api/settings', {
      'systemPromptName': 'Novel',
      'groupSystemPromptName': 'Novel',
    });
    expect(PromptSlot.oneToOne.savedName(storage), 'Novel');
    expect(PromptSlot.group.savedName(storage), 'Novel');

    final (deleted, pool) = await call('POST', '/api/saved-prompts/delete', {
      'name': 'Novel',
    });
    expect(deleted, 200);
    expect(pool['savedPrompts'], isEmpty);
    expect(PromptSlot.oneToOne.savedName(storage), isNull);
    expect(PromptSlot.group.savedName(storage), isNull);

    // A page that loaded before the delete still sends the old pick.
    await call('POST', '/api/settings', {
      'systemPromptName': 'Novel',
      'groupSystemPromptName': 'Novel',
    });
    expect(PromptSlot.oneToOne.savedName(storage), isNull);
    expect(PromptSlot.group.savedName(storage), isNull);
    final (_, settings) = await call('GET', '/api/settings');
    expect(settings['systemPromptName'], isNull);
    expect(settings['groupSystemPromptName'], isNull);
  });
}
