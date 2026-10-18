// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Recovery overhaul PR 6, end to end through the real wiring: the wheel
// ChatService builds for a Chance Time spin pulls the desire-asserting
// adult events while the attributed body is mid a HARD refractory lock,
// and serves them again the moment the lock (or a soft body) says desire
// is honest. The pool-level contract lives in chaos_wheel_test.dart; this
// file pins the CHAIN — 18+ themes, the chat's spicy switch, the closure,
// and the live refractory — because a silently missing closure param is
// exactly the hole that made climax detection optional once.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/chat/chaos/chaos.dart';
import 'package:front_porch_ai/services/chat/refractory.dart';
import 'package:front_porch_ai/services/services.dart';

import '../../../../integration_test/support/fake_backend.dart';
import '../../../helpers/chat_db_teardown.dart';

const _locked = {
  '{{char}} is visibly aroused at the most inconvenient moment imaginable '
      'and is scrambling',
  '{{char}} is trying extremely hard to hide a visible physical reaction to '
      'someone attractive nearby',
  '{{char}} is suddenly, intensely in the mood and it is very hard to hide',
  'A long dry spell has caught up with {{char}} and they are restless, '
      'flustered, and thinking about little else',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return Directory.systemTemp.createTempSync('fpai_chaoslock_').path;
        }
        return null;
      });

  late FakeBackendServer backend;
  late AppDatabase db;
  late ChatService chat;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({
      'update_auto_check': false,
      'realism_default': false,
      // Seeds the app-wide 18+ themes switch (adultThemesEnabled reads it
      // live when no explicit choice was stored).
      'nsfw_cooldown_default': true,
    });
    backend = await FakeBackendServer.start(replyPieces: ['She nods.']);
    db = AppDatabase.forTesting();
    final storage = StorageService();
    chat =
        ChatService(
            KoboldService(storage),
            UserPersonaService(db),
            storage,
            WorldRepository(storage, db),
          )
          ..setDatabase(db)
          ..testLlmServiceOverride = OpenRouterService(
            apiUrl: '${backend.baseUrl}/v1',
            modelName: 'smoke-model',
          );
    await storage.initialized;
    await chat.setActiveCharacter(
      CharacterCard(
        name: 'Mara',
        description: 'Exists only inside the chaos hard-lock test.',
        firstMessage: 'The porch light hums.',
        frontPorchExtensions: FrontPorchExtensions(
          realismEnabled: false,
          needsSimEnabled: false,
          chaosModeEnabled: true,
        ),
      )..dbId = 'char-chaos-lock',
    );
    await chat.setChaosNsfwEnabled(true);
  });

  tearDown(() async {
    await disposeChatThenCloseDb(chat, db);
    await backend.close();
  });

  Set<String> seenLockedOver(int spins) {
    final seen = <String>{};
    for (var i = 0; i < spins; i++) {
      seen.addAll(chat.spinWheelEvents().where(_locked.contains));
    }
    return seen;
  }

  test('unlocked and spicy: the wheel serves the desire events', () {
    expect(chat.nsfwService.refractory.running, isFalse);
    expect(
      seenLockedOver(200),
      isNotEmpty,
      reason:
          'baseline must be able to land them, or the gate proves '
          'nothing',
    );
  });

  test('a hard lock pulls them from every wheel, wheel stays full', () {
    chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
    for (var i = 0; i < 100; i++) {
      final wheel = chat.spinWheelEvents();
      expect(wheel.length, 8);
      expect(wheel.where(_locked.contains), isEmpty, reason: '$wheel');
    }
  });

  test('a soft body keeps them — the gate is hard lock only', () {
    // Multiorgasmic characters hold their arousal through the window, so
    // "visibly aroused" is the TRUTH for them mid-window, not a lie.
    chat.nsfwService.setRefractory(Refractory.tenderness([0]));
    expect(chat.nsfwService.refractory.running, isTrue);
    expect(chat.nsfwService.refractory.soft, isTrue);
    expect(seenLockedOver(300), isNotEmpty);
  });

  test('the gate is live: releasing the lock serves them again', () {
    chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(4));
    expect(seenLockedOver(100), isEmpty);
    chat.nsfwService.setRefractory(Refractory.none);
    expect(seenLockedOver(300), isNotEmpty);
  });

  // Review M1: a manual SPIN NOW parks WITHOUT halting generation. The
  // beat between spin and accept can carry a climax (1:1) or rotate a
  // group pointer onto a body locked the whole window. Accept must re-gate
  // against the body the event actually attributes to.
  test('a parked tagged event cannot land on a now-locked body', () async {
    final tagged = kAllChaosEvents.firstWhere((e) => e.desireAsserting).text;
    // Spin happened unlocked; the climax lands before Accept.
    chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
    await chat.applyChanceTimeResult(tagged, 'Mara');
    final injection = chat.chaosModeService.pendingChaosInjection;
    expect(injection, isNotNull, reason: 'the spin still pays out');
    expect(
      injection,
      isNot(chat.resolveChanceTimeEvent(tagged, 'Mara')),
      reason: 'the parked "visibly aroused" must not print under Lust: 0',
    );
    // What lands is a legal event: untagged or from the gated wheel.
    final applied = kAllChaosEvents.where(
      (e) => chat.resolveChanceTimeEvent(e.text, 'Mara') == injection,
    );
    expect(
      applied.every((e) => !e.desireAsserting),
      isTrue,
      reason: 'a desire-asserting event survived the re-gate: $injection',
    );
  });

  test('unlocked, the parked tagged event lands verbatim', () async {
    final tagged = kAllChaosEvents.firstWhere((e) => e.desireAsserting).text;
    await chat.applyChanceTimeResult(tagged, 'Mara');
    expect(
      chat.chaosModeService.pendingChaosInjection,
      chat.resolveChanceTimeEvent(tagged, 'Mara'),
    );
  });

  test('a locked body still receives untagged events untouched', () async {
    final plain = kAllChaosEvents
        .firstWhere((e) => !e.desireAsserting && e.text.contains('{{char}}'))
        .text;
    chat.nsfwService.setRefractory(Refractory.fromJudgeTurns(6));
    await chat.applyChanceTimeResult(plain, 'Mara');
    expect(
      chat.chaosModeService.pendingChaosInjection,
      chat.resolveChanceTimeEvent(plain, 'Mara'),
    );
  });
}
