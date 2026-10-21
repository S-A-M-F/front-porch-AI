// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Locations slice 2 (docs/design/locations-within-worlds.md §3 Transitions):
// a Setting swap that changes the climate author must not rewrite history.
// The old author is pinned from day 1 and the new one takes over from the
// current story day, on the same ChatBiomeSpans machinery the climate
// dropdown uses. Moving between places under one author writes no span.
// Real ChatService + in-memory Drift; no model is contacted.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/models/world.dart' as model;
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
          return Directory.systemTemp.createTempSync('fpai_move_span_').path;
        }
        return null;
      });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _setupPathProviderMock();

  late AppDatabase db;
  late ChatService chat;
  late WorldRepository worlds;
  late CharacterCard marta;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'update_auto_check': false});
    db = AppDatabase.forTesting();
    final storage = StorageService();
    await storage.initialized;
    worlds = WorldRepository(storage, db);
    chat = ChatService(
      KoboldService(storage),
      UserPersonaService(db),
      storage,
      worlds,
    )..setDatabase(db);
    await db.insertCharacter(
      CharactersCompanion.insert(
        id: 'c-move',
        name: 'Marta',
        imagePath: const Value('/tmp/marta.png'),
      ),
    );
    await db.insertSession(
      SessionsCompanion.insert(
        id: 'sess-move',
        characterId: const Value('c-move'),
        name: const Value('Move chat'),
      ),
    );
    await chat.loadSession('sess-move');
    // _openSession no-ops without an active character (chat_service_session_
    // load.dart:291) — enter Marta, then reopen her session the way the UI
    // does, and assert the door actually opened.
    marta = CharacterCard(name: 'Marta', imagePath: '/tmp/marta.png')
      ..dbId = 'c-move';
    await chat.setActiveCharacter(marta);
    await chat.loadSession('sess-move');
    expect(chat.currentSessionId, 'sess-move');
    // Pin the story clock four days in, so a changeover can prove that
    // days 1..N-1 keep the previous author's weather.
    final now = DateTime.now();
    chat.timeService.setStartDate(DateTime(now.year, now.month, now.day - 4, 6));
    await chat.timeService.setClockDirect(DateTime(now.year, now.month, now.day, 9));
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => disposeChatThenCloseDb(chat, db));

  Future<List<({int effectiveFromDay, String biomeJson})>> spans() =>
      worlds.getChatBiomeSpanRows('sess-move');

  test('first climate Setting records the switch from the current day', () async {
    final town = model.World(
      id: 'town',
      name: 'Bletchfield',
      lorebook: Lorebook(entries: []),
      biomeId: 'temperate',
    );
    await worlds.saveWorld(town);
    final day = chat.timeService.dayCount;
    expect(day, greaterThan(1), reason: 'the clock was pinned days in');

    await chat.setChatPlaceSlots(primaryId: town.id);

    final rows = await spans();
    expect(rows.map((r) => r.effectiveFromDay), [day]);
    expect(rows.single.biomeJson, contains('temperate'));
    expect(chat.activeChatBiome.id, 'temperate');
    expect(chat.currentWeather, isNotNull);
  });

  test('a swap to a new author pins the old one from day 1', () async {
    final town = model.World(
      id: 'town',
      name: 'Bletchfield',
      lorebook: Lorebook(entries: []),
      biomeId: 'temperate',
    );
    final cavern = model.World(
      id: 'cavern',
      name: 'Cavern',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'town',
      biomeId: 'desert',
    );
    await worlds.saveWorld(town);
    await worlds.saveWorld(cavern);
    final day = chat.timeService.dayCount;

    await chat.setChatPlaceSlots(primaryId: town.id);
    await chat.setChatPlaceSlots(primaryId: cavern.id);

    final rows = await spans();
    expect(rows.map((r) => r.effectiveFromDay).toList(), [1, day]);
    expect(rows.first.biomeJson, contains('temperate'));
    expect(rows.last.biomeJson, contains('desert'));
    // Today reads the new author; the earlier days are pinned, not gone.
    expect(chat.activeChatBiome.id, 'desert');
  });

  test('moving under the same climate author writes no span', () async {
    final town = model.World(
      id: 'town',
      name: 'Bletchfield',
      lorebook: Lorebook(entries: []),
      biomeId: 'temperate',
    );
    final cafe = model.World(
      id: 'cafe',
      name: 'Tea Rooms',
      lorebook: Lorebook(entries: []),
      parentWorldId: 'town',
      climateEnabled: false,
    );
    await worlds.saveWorld(town);
    await worlds.saveWorld(cafe);

    await chat.setChatPlaceSlots(primaryId: town.id);
    final afterFirst = await spans();

    await chat.setChatPlaceSlots(primaryId: cafe.id, loreIds: ['town']);
    final afterMove = await spans();

    // The Tea Rooms inherit Bletchfield's weather: same author, same
    // schedule, and the chat still has live weather.
    expect(afterMove.map((r) => r.effectiveFromDay),
        afterFirst.map((r) => r.effectiveFromDay));
    expect(chat.chatPrimaryWorldId, cafe.id);
    expect(chat.currentWeather, isNotNull);
  });

  test('dropping to no Setting silences weather but keeps the spans', () async {
    final town = model.World(
      id: 'town',
      name: 'Bletchfield',
      lorebook: Lorebook(entries: []),
      biomeId: 'temperate',
    );
    await worlds.saveWorld(town);
    await chat.setChatPlaceSlots(primaryId: town.id);
    final rows = await spans();
    expect(rows, isNotEmpty);

    await chat.setChatPlaceSlots(primaryId: null, loreIds: ['town']);
    expect(chat.currentWeather, isNull, reason: 'no Setting ⇒ gate off');
    final kept = await spans();
    expect(kept.map((r) => r.effectiveFromDay),
        rows.map((r) => r.effectiveFromDay));
  });
}
