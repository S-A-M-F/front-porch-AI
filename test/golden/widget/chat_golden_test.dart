// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

@Tags(['golden'])
@TestOn('linux')
library;

// Widget pixel goldens for chat bubble surfaces.
//
// MessageBubble is the highest-value chat component — it embeds realism chips,
// TTS controls, alternate-greeting swipes, and the action-suggestion row. These
// goldens freeze the bubble layout in light + dark for both the user and AI sides,
// and specifically assert the realism-chip row (bond/trust/emotion/needs deltas)
// so a regression that silently drops chips fails loudly here.
//
// Provider tree required by MessageBubble:
//   StorageService (bubbleOpacity, textScale, colors)
//   TtsService     (isSpeaking/isGenerating/currentMessageId/generationProgress)
//   ChatService    (isGroupMode, messages, isGenerating, suggestedActions, …)
//   UserPersonaService (personas — empty list → no-op persona row)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/chat_message.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/tts_service.dart';
import 'package:front_porch_ai/services/user_persona_service.dart';
import 'package:front_porch_ai/ui/chat_components/bubbles/message_bubble.dart';

import '../support/creator_test_support.dart';
import '../support/fakes.dart';
import '../support/golden_app.dart';

/// Sync StorageService — defaults only (bubbleOpacity 1.0, textScale 1.0).
/// The async init is irrelevant for a static golden.
StorageService _storage() {
  SharedPreferences.setMockInitialValues({});
  return StorageService();
}

/// Wrap a MessageBubble in the full provider tree it requires.
Widget _bubbleTree({
  required ChatMessage message,
  required FakeChatService chat,
  required FakeTtsService tts,
  required StorageService storage,
  CharacterCard? character,
  int index = 1,
}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<StorageService>.value(value: storage),
      ChangeNotifierProvider<TtsService>.value(value: tts),
      ChangeNotifierProvider<ChatService>.value(value: chat),
      ChangeNotifierProvider<UserPersonaService>.value(
        value: FakeUserPersonaService(),
      ),
    ],
    child: SizedBox(
      width: 680,
      child: MessageBubble(
        message: message,
        index: index,
        character: character,
        chatService: chat,
      ),
    ),
  );
}

void main() {
  setupPathProviderMock();

  testWidgets('MessageBubble — user message', (tester) async {
    final msg = ChatMessage(
      text: 'What do you know about the lighthouse?',
      sender: 'User',
      isUser: true,
    );
    final chat = FakeChatService(messages: [msg]);
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: _bubbleTree(
        message: msg,
        chat: chat,
        tts: tts,
        storage: storage,
      ),
      group: 'chat',
      name: 'bubble_user',
      surface: const Size(720, 160),
    );
  });

  testWidgets('MessageBubble — AI character message (plain)', (tester) async {
    final character = CharacterCard(name: 'Aria Vale');
    final msg = ChatMessage(
      text: '"The lamp at the cape never goes dark," she said quietly.',
      sender: 'Aria Vale',
      isUser: false,
    );
    final chat = FakeChatService(
      activeCharacter: character,
      messages: [msg],
    );
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: _bubbleTree(
        message: msg,
        chat: chat,
        tts: tts,
        storage: storage,
        character: character,
      ),
      group: 'chat',
      name: 'bubble_ai_plain',
      surface: const Size(720, 200),
    );
  });

  testWidgets('MessageBubble — AI message with realism chips', (tester) async {
    final character = CharacterCard(name: 'Aria Vale');
    final msg = ChatMessage(
      text:
          '"You came," she said, turning from the lamp. "I wasn\'t sure you would."',
      sender: 'Aria Vale',
      isUser: false,
      metadata: {
        'bond_delta': 15,
        'bond_reason': 'showed concern for her safety',
        'emotion_label': 'affection',
        'arousal_delta': 0,
        'trust_delta': 8,
        'trust_reason': 'kept their promise',
        'needs_deltas': {'social': 12, 'fun': 6},
      },
    );
    final chat = FakeChatService(
      activeCharacter: character,
      characterEmotion: 'affection',
      emotionIntensity: 'moderate',
      messages: [msg],
    );
    addTearDown(chat.dispose);
    final tts = FakeTtsService();
    addTearDown(tts.dispose);
    final storage = _storage();
    addTearDown(storage.dispose);

    await expectThemedGoldens(
      tester,
      child: _bubbleTree(
        message: msg,
        chat: chat,
        tts: tts,
        storage: storage,
        character: character,
      ),
      group: 'chat',
      name: 'bubble_ai_realism',
      surface: const Size(720, 380),
    );
  });
}
