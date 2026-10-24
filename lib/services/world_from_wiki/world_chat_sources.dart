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

import 'package:front_porch_ai/services/story/story_chat_sources.dart';

import 'world_build_mode.dart';
import 'world_from_wiki_depth.dart';

/// Under this many messages there is almost nothing to skim: Card only, or
/// Creative, does better (docs/design/world-from-character.md §3.5).
const int kWorldChatMessagesFloor = 40;

/// Under this many messages (about fifty turns) Facts only gives a thin
/// shelf, likely under ten cards.
const int kWorldChatMessagesShort = 100;

/// Below this Full is mostly review passes over the same cards.
const int kWorldChatMessagesForFull = 200;

/// The chip a chat row wears: 'too short to skim', 'short chat', or ''.
String worldChatLengthChip(int messages) {
  if (messages <= 0) return '';
  if (messages < kWorldChatMessagesFloor) return 'too short to skim';
  if (messages < kWorldChatMessagesShort) return 'short chat';
  return '';
}

/// The one warning line under the chat rows for the picked chat, or null
/// when its length needs no word. Both surfaces say exactly this; it
/// warns, never blocks. [messages] 0 means no chat is picked.
String? worldChatLengthWarning(
  int messages, {
  required WorldBuildMode mode,
  required WorldWikiDepth depth,
}) {
  if (messages <= 0) return null;
  final turns = (messages / 2).round();
  final count =
      '$messages message${messages == 1 ? '' : 's'} (about $turns '
      'turn${turns == 1 ? '' : 's'})';
  if (messages < kWorldChatMessagesFloor) {
    return 'This chat has $count. Under $kWorldChatMessagesFloor messages '
        'there is almost nothing to skim: Card only, or Creative, does '
        'better.';
  }
  if (messages < kWorldChatMessagesShort) {
    return mode == WorldBuildMode.creative
        ? 'This chat has $count. The shelf will lean on what the model '
              'invents around it.'
        : 'This chat has $count. ${mode.label} will give a thin shelf, '
              'likely under ten cards.';
  }
  if (messages < kWorldChatMessagesForFull && depth != WorldWikiDepth.quick) {
    return 'This chat has $count. Below $kWorldChatMessagesForFull messages '
        '${depth.label} is mostly review passes over the same cards; Quick '
        'is the better fit.';
  }
  return null;
}

/// The 1:1 chats of one character, newest first, as the story picker lists
/// them. Group chats are not offered yet (design §6, slice 4).
List<StoryChatSourceRow> worldChatRowsFor(
  List<StoryChatSourceRow> rows,
  String characterId,
) => [
  for (final r in rows)
    if (r.characterId == characterId) r,
];

/// The most cards a chat yields at [depth]: fewer than a wiki, because a
/// chat has no roster to walk (design §3.3). Deep is not offered and
/// behaves as Full.
int worldCharacterCardTarget(WorldWikiDepth depth) => switch (depth) {
  WorldWikiDepth.quick => 15,
  WorldWikiDepth.full => 30,
  WorldWikiDepth.deep => 30,
};

/// What the first scout call asks for at [depth], for a chat.
(int, int) worldCharacterScoutRange(WorldWikiDepth depth) => switch (depth) {
  WorldWikiDepth.quick => (8, 15),
  WorldWikiDepth.full => (12, 30),
  WorldWikiDepth.deep => (12, 30),
};

/// Deep has no roster to walk here; a stored Deep runs as Full.
WorldWikiDepth worldCharacterDepth(WorldWikiDepth depth) =>
    depth == WorldWikiDepth.deep ? WorldWikiDepth.full : depth;

/// The Book step's depth tile copy for a chat source.
String worldCharacterDepthBlurb(WorldWikiDepth depth) => switch (depth) {
  WorldWikiDepth.quick =>
    'The places, the people around them, the events the chat turned on. '
        'No review passes; the shelf may be thin.',
  _ =>
    'Places and factions name their people in their own card. Reviewers '
        'check the shelf and every entry against the chat.',
};

String worldCharacterDepthTime(WorldWikiDepth depth) => switch (depth) {
  WorldWikiDepth.quick => 'About 5 min on a remote model',
  _ => 'About 15 min on a remote model',
};

/// Why Deep is missing from the tiles, in one line.
const String kWorldCharacterNoDeepCopy =
    'Deep is not offered here: a chat has no roster to walk the way a '
    "wiki's categories do.";
