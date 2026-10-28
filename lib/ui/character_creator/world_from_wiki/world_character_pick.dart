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

import 'package:flutter/foundation.dart';
import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/story/story_chat_sources.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// The Book step's second card when the source is a character: who, which
/// chat, how far the writer may go, and whether the card's own lorebook
/// rides along. Held by the wizard state; the source it builds is kept
/// between scout and write so the chat is skimmed once.
class WorldCharacterPick {
  WorldCharacterPick({Future<AppDatabase> Function()? database})
    : _database = database ?? AppDatabase.instance;

  final Future<AppDatabase> Function() _database;

  List<CharacterCard> characters = const [];
  List<StoryChatSourceRow> rows = const [];
  bool loading = false;
  String query = '';

  CharacterCard? character;

  /// '' is Card only.
  String sessionId = '';

  WorldBuildMode mode = WorldBuildMode.creative;
  bool copyCardLore = false;

  CharacterChatWorldSource? _source;
  String _sourceKey = '';

  bool get hasCharacter => character != null;
  bool get hasChat => sessionId.isNotEmpty;

  /// Plain words when the pick is not enough to scout from, else null.
  String? get pickError => character == null ? 'Pick a character first.' : null;

  /// The picked chat's row, when a chat is picked.
  StoryChatSourceRow? get pickedRow {
    for (final r in rows) {
      if (r.sessionId == sessionId) return r;
    }
    return null;
  }

  int get messageCount => pickedRow?.messageCount ?? 0;

  /// The library and the 1:1 chats, once; the picker filters them.
  Future<void> load({
    required CharacterRepository repo,
    required StoryPipelineService? stories,
  }) async {
    loading = true;
    try {
      await repo.whenLoaded;
      characters = [...repo.characters]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      rows = stories == null ? const [] : await stories.chatSources();
    } catch (e) {
      debugPrint('[World] character pick load miss: $e');
    } finally {
      loading = false;
    }
  }

  /// Characters whose name contains every word of [query].
  List<CharacterCard> get shownCharacters {
    final words = query.toLowerCase().split(RegExp(r'\s+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return characters;
    return [
      for (final c in characters)
        if (words.every(c.name.toLowerCase().contains)) c,
    ];
  }

  List<StoryChatSourceRow> chatsOf(CharacterCard c) =>
      worldChatRowsFor(rows, c.dbId ?? '');

  /// The picked character's chats, newest first.
  List<StoryChatSourceRow> get chats =>
      character == null ? const [] : chatsOf(character!);

  void pick(CharacterCard c) {
    if (character?.dbId == c.dbId) return;
    character = c;
    sessionId = '';
    mode = WorldBuildMode.creative;
  }

  void pickSession(String id) {
    sessionId = id;
    // Facts only with a chat, Creative for Card only (design §7).
    mode = id.isEmpty ? WorldBuildMode.creative : WorldBuildMode.factsOnly;
  }

  /// The one warning line under the chat rows, or null.
  String? warning(WorldWikiDepth depth) => worldChatLengthWarning(
    messageCount,
    mode: mode,
    depth: worldCharacterDepth(depth),
  );

  /// What the title bar and the shelf call the source.
  String get label {
    final c = character;
    if (c == null) return '';
    final row = pickedRow;
    return row == null ? "${c.name}'s card" : '${c.name} · ${row.sessionName}';
  }

  /// The source for the current pick, skimmed once per pick: a second
  /// scout or the write after it reuses the index.
  Future<CharacterChatWorldSource> buildSource() async {
    final c = character;
    if (c == null) throw StateError('no character picked');
    final key = '${c.dbId}/$sessionId';
    if (_source != null && _sourceKey == key) return _source!;
    final record = await loadWorldChatRecord(
      await _database(),
      card: c,
      sessionId: sessionId,
    );
    _sourceKey = key;
    return _source = CharacterChatWorldSource(card: c, record: record);
  }

  /// The chat's own summary, for Where the story stands (prefilled once).
  Future<String> summary() async {
    if (sessionId.isEmpty) return '';
    final s = await buildSource();
    return s.record.summary;
  }

  /// The minted world's provenance and, when asked, the card's own lore.
  /// Nothing is linked: renaming or deleting the character leaves the
  /// world alone (design §3.3).
  World stamp(World world, {required bool active}) {
    final c = character;
    if (!active || c == null) return world;
    final stableId = stableGroupIdFrom(c.imagePath, c.name);
    world.sourceId =
        'character:$stableId${sessionId.isEmpty ? '' : '/$sessionId'}';
    world.placeTraits['source'] = {
      'kind': 'character',
      'name': c.name,
      'characterId': stableId,
      if (sessionId.isNotEmpty) 'sessionId': sessionId,
      'mode': mode.name,
    };
    if (copyCardLore) {
      final have = {
        for (final e in world.lorebook.entries) e.name.trim().toLowerCase(),
      };
      for (final e in c.lorebook?.entries ?? const <LorebookEntry>[]) {
        if (!e.enabled || !have.add(e.name.trim().toLowerCase())) continue;
        world.lorebook.entries.add(e);
      }
    }
    return world;
  }
}
