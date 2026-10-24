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

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story_chat_memory.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// One message as the Skim and the writer read it. [text] already carries
/// `{{user}}` where the persona's name was, so no prompt ever sees it.
typedef WorldChatLine = ({int index, int position, String sender, String text});

/// The Skim reads this many messages a pass, cut exactly as the Chat
/// Distiller cuts them.
const int kWorldSkimChunk = 50;

/// The persona's name as every prompt and every written entry carries it
/// (docs/design/world-from-character.md §3.3): the macro the lore
/// injector fills, never the name.
const String kWorldUserMacro = '{{user}}';

/// The record a world is built from: one character's card is read
/// elsewhere; this is their chat, with what the chat itself wrote down —
/// the Journal cards, the Growth rings and the Objectives (design §3.2).
/// Pure data: the loader below fills it from the database, tests fill it
/// by hand.
class WorldChatRecord {
  WorldChatRecord({
    required this.characterName,
    required this.characterId,
    this.sessionId = '',
    this.lines = const [],
    this.cards = const [],
    this.rings = const [],
    this.objectives = const [],
    this.summary = '',
    this.userName = '',
  });

  final String characterName;

  /// The persona's name as the chat had it. The lines no longer carry it
  /// (they carry the macro); the Skim keeps it only to refuse a name the
  /// model might still volunteer.
  final String userName;

  /// The card's `stableGroupId`, which Journal, Growth and Objectives key
  /// by (never `characters.id`).
  final String characterId;
  final String sessionId;
  final List<WorldChatLine> lines;
  final List<JournalMemoryData> cards;
  final List<GrowthRingData> rings;
  final List<Objective> objectives;

  /// The chat's own summary: Where the story stands, prefilled.
  final String summary;

  int get messageCount => lines.length;
  bool get hasChat => lines.isNotEmpty;

  /// The chat in parts of [kWorldSkimChunk] messages, in order.
  List<List<WorldChatLine>> get chunks => [
    for (var i = 0; i < lines.length; i += kWorldSkimChunk)
      lines.sublist(i, (i + kWorldSkimChunk).clamp(0, lines.length)),
  ];

  /// The Journal cards and rings placed at their messages, the way the
  /// Distiller places them, so a part's prompt carries what that stretch
  /// recorded.
  StoryChatMemory memory() => StoryChatMemory.place(
    lines: [
      for (final l in lines)
        (sessionId: sessionId, position: l.position, text: l.text),
    ],
    cards: cards,
    rings: rings,
    names: {characterId: characterName},
    userName: kWorldUserMacro,
  );

  /// The Objectives as closing notes: they have no message receipt, so
  /// they join the unplaced cards as "what the character was working
  /// toward".
  String objectiveNotes() {
    if (objectives.isEmpty) return '';
    final b = StringBuffer(
      'WHAT $characterName WAS WORKING TOWARD (the chat\'s objectives; '
      'each is true of this chat):\n',
    );
    for (final o in objectives) {
      b.writeln('- ${objectiveLine(o)}');
    }
    return b.toString().trimRight();
  }

  /// "(active) Reopen the Salt Garden — tasks: find the key (done), …".
  static String objectiveLine(Objective o) {
    final tasks = <String>[];
    try {
      final raw = jsonDecode(o.tasks);
      if (raw is List) {
        for (final t in raw) {
          if (t is! Map) continue;
          final desc = t['description']?.toString().trim() ?? '';
          if (desc.isEmpty) continue;
          tasks.add(t['completed'] == true ? '$desc (done)' : desc);
        }
      }
    } catch (_) {}
    return '(${o.active ? 'active' : 'done'}) ${o.objective.trim()}'
        '${tasks.isEmpty ? '' : ' — tasks: ${tasks.join(', ')}'}';
  }

  /// The lines that name [title] or one of [aliases] as a whole word,
  /// oldest first, at most [max].
  List<WorldChatLine> linesNaming(
    String title,
    Iterable<String> aliases, {
    int max = 40,
  }) {
    final words = {title.trim(), for (final a in aliases) a.trim()}
      ..removeWhere((w) => w.length < 2);
    if (words.isEmpty) return const [];
    final re = RegExp(
      '(?<![\\w])(?:${words.map(RegExp.escape).join('|')})(?![\\w])',
      caseSensitive: false,
    );
    final out = <WorldChatLine>[];
    for (final l in lines) {
      if (re.hasMatch(l.text)) {
        out.add(l);
        if (out.length >= max) break;
      }
    }
    return out;
  }

  /// The Journal cards, rings and objectives that name [title] or an alias.
  List<String> notesNaming(String title, Iterable<String> aliases) {
    final words = {title.trim(), for (final a in aliases) a.trim()}
      ..removeWhere((w) => w.length < 2);
    if (words.isEmpty) return const [];
    final re = RegExp(
      '(?<![\\w])(?:${words.map(RegExp.escape).join('|')})(?![\\w])',
      caseSensitive: false,
    );
    return [
      for (final c in cards)
        if (re.hasMatch(c.content)) "$characterName's journal: ${c.content}",
      for (final r in rings)
        if (re.hasMatch(r.content))
          '$characterName changed: ${r.content.replaceAll('{{char}}', characterName)}',
      for (final o in objectives)
        if (re.hasMatch('${o.objective} ${o.tasks}'))
          'objective ${objectiveLine(o)}',
    ];
  }
}

/// [text] with every whole-word [userName] replaced by the user macro, so
/// the persona's name never reaches a prompt or an entry.
String worldPersonaToMacro(String text, String userName) {
  final name = userName.trim();
  if (name.isEmpty || text.isEmpty) return text;
  final re = RegExp(
    '(?<![\\w])${RegExp.escape(name)}(?![\\w])',
    caseSensitive: false,
  );
  return text.replaceAll(re, kWorldUserMacro);
}

/// The record for [card] and [sessionId] from the database: the session's
/// messages (the shown swipe of each), its Journal cards and rings, the
/// card's objectives in that chat, and the chat's summary. An empty
/// [sessionId] is Card only: no lines, nothing to skim.
Future<WorldChatRecord> loadWorldChatRecord(
  AppDatabase db, {
  required CharacterCard card,
  required String sessionId,
}) async {
  final stableId = stableGroupIdFrom(card.imagePath, card.name);
  if (sessionId.trim().isEmpty) {
    return WorldChatRecord(characterName: card.name, characterId: stableId);
  }
  final msgs = await db.getMessagesForSession(sessionId);
  var userName = '';
  final raw = <({int position, String sender, String text, bool isUser})>[];
  for (final m in msgs) {
    try {
      final swipes = jsonDecode(m.swipes) as List;
      final text = swipes.isEmpty
          ? ''
          : swipes[m.swipeIndex.clamp(0, swipes.length - 1)].toString();
      if (text.trim().isEmpty) continue;
      if (m.isUser && userName.isEmpty) userName = m.sender;
      raw.add((
        position: m.position,
        sender: m.sender,
        text: text.trim(),
        isUser: m.isUser,
      ));
    } catch (e) {
      debugPrint('[World] skipped a message that would not parse: $e');
    }
  }
  final lines = <WorldChatLine>[
    for (var i = 0; i < raw.length; i++)
      (
        index: i,
        position: raw[i].position,
        sender: raw[i].isUser
            ? kWorldUserMacro
            : worldPersonaToMacro(raw[i].sender, userName),
        text: worldPersonaToMacro(raw[i].text, userName),
      ),
  ];
  final session = await db.getSessionById(sessionId);
  return WorldChatRecord(
    characterName: card.name,
    characterId: stableId,
    sessionId: sessionId,
    lines: lines,
    cards: await db.getJournalCardsForSession(sessionId),
    rings: await db.getGrowthRingsForSession(sessionId),
    objectives: await db.getObjectivesForCharacter(stableId, chatId: sessionId),
    summary: worldPersonaToMacro(session?.summary ?? '', userName),
    userName: userName,
  );
}
