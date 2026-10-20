// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Live guard: keys written by ChatService._captureRealismState must stay
// ⊆ kFpchatRealismStateCoreKeys so a new stamp field forces package awareness.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/services/chat/fpchat_format.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/kobold_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import '../../helpers/chat_db_teardown.dart';

void _setupPathProviderMock() {
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (MethodCall call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_docs_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    final personas = UserPersonaService(db);
    final worlds = WorldRepository(storage, db);
    chat = ChatService(KoboldService(storage), personas, storage, worlds)
      ..setDatabase(db);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await chat.startFreshChatWith(
      character: CharacterCard(
        name: 'Misty',
        frontPorchExtensions: FrontPorchExtensions(realismEnabled: true),
      )..dbId = 'char-misty',
      personaId: personas.persona.id,
    );
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  // Recovery overhaul PR 3: a soft body's snapshot grows two keys, and the
  // awareness list must already cover them — the same trap the turn-count
  // keys once sprang.
  test('soft-gate keys ride the fpchat capture (PR 3)', () {
    chat.nsfwService.setNsfwCooldownEnabled(true);
    chat.nsfwService.setRefractory(
      const Refractory(minutes: 12, total: 15, soft: true, peaks: [20, 0]),
    );
    final captured = chat.debugCaptureRealismStateForFpchat();
    expect(captured[RefractoryKeys.soft], true);
    expect(captured[RefractoryKeys.peaks], [20, 0]);
    final unknown = captured.keys.toSet().difference(
      kFpchatRealismStateCoreKeys,
    );
    expect(
      unknown,
      isEmpty,
      reason: 'soft + peaks must be listed in the core-keys set',
    );
  });

  test('live capture keys are covered by kFpchatRealismStateCoreKeys', () {
    final captured = chat.debugCaptureRealismStateForFpchat();
    final keys = captured.keys.toSet();
    final unknown = keys.difference(kFpchatRealismStateCoreKeys);
    expect(
      unknown,
      isEmpty,
      reason:
          'New realism_state keys $unknown must be added to '
          'kFpchatRealismStateCoreKeys (and package docs) before shipping',
    );
    // Required always-on keys (optional: pockets, needs, interCharacterRelationships)
    const required = {
      'affectionScore',
      'trustLevel',
      'characterEmotion',
      'storyClock',
      'arousalLevel',
    };
    expect(
      keys.containsAll(required),
      isTrue,
      reason: 'missing $required from $keys',
    );
  });
}
