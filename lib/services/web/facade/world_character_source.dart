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

import 'package:front_porch_ai/database/database.dart' show AppDatabase;
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/utils/character_id.dart';

/// The relay's `source` field on a scout or write body: a character and,
/// optionally, one of their chats. Absent means the wiki, as before
/// (docs/design/world-from-character.md §5). Additive: an older PWA
/// never sends it.
class WorldSourcePick {
  const WorldSourcePick({
    required this.characterId,
    this.sessionId = '',
    this.mode = WorldBuildMode.factsOnly,
    this.copyCardLore = false,
  });

  final String characterId;
  final String sessionId;
  final WorldBuildMode mode;
  final bool copyCardLore;

  String get key => '$characterId/$sessionId';

  /// Null when [body] names no character source.
  static WorldSourcePick? fromBody(Map<String, dynamic> body) {
    final raw = body['source'];
    if (raw is! Map) return null;
    if (raw['kind']?.toString() != 'character') return null;
    final characterId = raw['characterId']?.toString().trim() ?? '';
    if (characterId.isEmpty) return null;
    final sessionId = raw['sessionId']?.toString().trim() ?? '';
    return WorldSourcePick(
      characterId: characterId,
      sessionId: sessionId,
      mode: WorldBuildModeX.fromName(
        raw['mode']?.toString(),
        fallback: sessionId.isEmpty
            ? WorldBuildMode.creative
            : WorldBuildMode.factsOnly,
      ),
      copyCardLore: raw['copyCardLore'] == true,
    );
  }
}

/// Builds and keeps the character sources the relay's wizard reads, one
/// per pick, so the chat is skimmed once between scout and write.
class WorldCharacterSources {
  WorldCharacterSources({required this.db, required this.characters});

  final AppDatabase db;
  final CharacterRepository characters;

  CharacterChatWorldSource? _source;
  String _key = '';

  /// Plain words when the pick cannot be read, else null.
  Future<String?> pickError(WorldSourcePick pick) async {
    final card = await characters.getCharacterCardById(pick.characterId);
    if (card == null) return 'that character is not in the library';
    return null;
  }

  Future<CharacterChatWorldSource> sourceFor(WorldSourcePick pick) async {
    if (_source != null && _key == pick.key) return _source!;
    final card = await characters.getCharacterCardById(pick.characterId);
    if (card == null) {
      throw StateError('that character is not in the library');
    }
    final record = await loadWorldChatRecord(
      db,
      card: card,
      sessionId: pick.sessionId,
    );
    _key = pick.key;
    return _source = CharacterChatWorldSource(card: card, record: record);
  }

  /// The minted world's provenance for the PWA's save: `sourceId` and the
  /// `source` place trait the desktop stamps (design §3.3).
  Map<String, dynamic> provenance(
    CharacterChatWorldSource source,
    WorldSourcePick pick,
  ) {
    final stableId = stableGroupIdFrom(source.card.imagePath, source.card.name);
    return {
      'sourceId':
          'character:$stableId${pick.sessionId.isEmpty ? '' : '/${pick.sessionId}'}',
      'placeTraits': {
        'source': {
          'kind': 'character',
          'name': source.card.name,
          'characterId': stableId,
          if (pick.sessionId.isNotEmpty) 'sessionId': pick.sessionId,
          'mode': pick.mode.name,
        },
      },
    };
  }
}
