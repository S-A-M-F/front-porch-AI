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

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/story/story_chat_sources.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';
import 'package:intl/intl.dart';

/// The Book step's second card when the source is a character: the
/// library as tiles, then that character's 1:1 chats as rows with Card
/// only first, and the one warning line for the picked chat (design §5).
class BookSourceSection extends StatelessWidget {
  const BookSourceSection({
    super.key,
    required this.state,
    required this.wide,
    required this.depth,
  });

  final WorldFromWikiState state;
  final bool wide;
  final WorldWikiDepth depth;

  @override
  Widget build(BuildContext context) {
    final pick = state.characterPick;
    final muted = StudioColors.mutedOf(context);
    final ink = StudioColors.inkOf(context);
    final shown = pick.shownCharacters;
    return WorldSectionCard(
      icon: Icons.person_outline,
      title: 'The source',
      step: 2,
      of: 4,
      highlighted: !pick.hasCharacter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('world-from-character-search'),
            enabled: !state.busy,
            style: TextStyle(color: ink),
            decoration: InputDecoration(
              labelText: 'Character',
              hintText: 'Search your characters',
              hintStyle: TextStyle(color: muted),
              prefixIcon: const Icon(Icons.search, size: 18),
              filled: true,
              fillColor: StudioColors.bgOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onChanged: (v) {
              pick.query = v;
              state.notify();
            },
          ),
          const SizedBox(height: 12),
          if (pick.loading)
            Text('Loading your characters…', style: TextStyle(color: muted))
          else if (pick.characters.isEmpty)
            Text(
              'No characters yet. Make or import one first, then come back.',
              style: TextStyle(color: muted),
            )
          else if (shown.isEmpty)
            Text(
              'No character matches that search.',
              style: TextStyle(color: muted),
            )
          else
            LayoutBuilder(
              builder: (context, box) {
                final cols = wide ? 4 : 1;
                final w = cols == 1
                    ? box.maxWidth
                    : (box.maxWidth - 10 * (cols - 1)) / cols;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in shown.take(24))
                      SizedBox(width: w, child: _characterTile(context, c)),
                  ],
                );
              },
            ),
          if (shown.length > 24) ...[
            const SizedBox(height: 6),
            Text(
              'Showing 24 of ${shown.length} characters. Search to narrow '
              'them down.',
              style: TextStyle(fontSize: 12, color: muted),
            ),
          ],
          if (pick.hasCharacter) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Text(
                  'Chats with ${pick.character!.name}',
                  style: TextStyle(fontWeight: FontWeight.w700, color: ink),
                ),
                const SizedBox(width: 8),
                const WorldChip('optional'),
                const Spacer(),
                Flexible(
                  child: Text(
                    '1:1 chats only for now; group chats come later.',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _chatRow(
              context,
              key: const Key('world-from-character-chat-card-only'),
              selected: !pick.hasChat,
              icon: Icons.badge_outlined,
              title: 'Card only',
              subtitle: pick.chats.isEmpty
                  ? 'No chats with ${pick.character!.name} yet. The card '
                        'alone makes a short world, mostly the places and '
                        'people it names.'
                  : 'A short world from the card alone: mostly the places '
                        'and people it names.',
              onTap: () {
                pick.pickSession('');
                state.notify();
              },
            ),
            for (final r in pick.chats.take(8)) ...[
              const SizedBox(height: 8),
              _chatRow(
                context,
                key: Key('world-from-character-chat-${r.sessionId}'),
                selected: pick.sessionId == r.sessionId,
                icon: Icons.chat_bubble_outline,
                title: r.sessionName.trim().isEmpty
                    ? 'Untitled chat'
                    : r.sessionName,
                subtitle:
                    '${DateFormat.yMMMd().format(r.createdAt)} · '
                    '${r.messageCount} message${r.messageCount == 1 ? '' : 's'}',
                chip: worldChatLengthChip(r.messageCount),
                onTap: () {
                  pick.pickSession(r.sessionId);
                  state.notify();
                },
              ),
            ],
            if (pick.chats.length > 8) ...[
              const SizedBox(height: 6),
              Text(
                'Showing the newest 8 of ${pick.chats.length} chats.',
                style: TextStyle(fontSize: 12, color: muted),
              ),
            ],
            ..._warning(context, pick.warning(depth)),
          ],
        ],
      ),
    );
  }

  List<Widget> _warning(BuildContext context, String? line) => line == null
      ? const []
      : [
          const SizedBox(height: 10),
          Text(
            line,
            key: const Key('world-from-character-length-warning'),
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              color: StudioColors.honeyOf(context),
            ),
          ),
        ];

  Widget _characterTile(BuildContext context, CharacterCard c) {
    final pick = state.characterPick;
    final selected = pick.character?.dbId == c.dbId;
    final chats = pick.chatsOf(c).length;
    final lore = c.lorebook?.entries.where((e) => e.enabled).length ?? 0;
    final muted = StudioColors.mutedOf(context);
    return WorldPickTile(
      key: Key('world-from-character-pick-${c.dbId ?? c.name}'),
      selected: selected,
      onTap: state.busy
          ? null
          : () {
              pick.pick(c);
              state.notify();
            },
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          _avatar(context, c),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.name,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                Text(
                  [
                    chats == 0
                        ? 'no chats yet'
                        : '$chats chat${chats == 1 ? '' : 's'}',
                    if (lore > 0)
                      '$lore lore ${lore == 1 ? 'entry' : 'entries'}',
                    if (c.isLite) 'model-made',
                  ].join(' · '),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(BuildContext context, CharacterCard c) {
    final path = c.imagePath;
    final initials = c.name.trim().isEmpty
        ? '?'
        : c.name
              .trim()
              .split(RegExp(r'\s+'))
              .take(2)
              .map((w) => w[0].toUpperCase())
              .join();
    final fallback = CircleAvatar(
      radius: 17,
      backgroundColor: StudioColors.raiseOf(context),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: StudioColors.inkOf(context),
        ),
      ),
    );
    if (path == null || path.isEmpty) return fallback;
    return ClipOval(
      child: Image.file(
        File(path),
        width: 34,
        height: 34,
        fit: BoxFit.cover,
        cacheWidth: 68,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }

  Widget _chatRow(
    BuildContext context, {
    required Key key,
    required bool selected,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String chip = '',
  }) {
    final muted = StudioColors.mutedOf(context);
    return WorldPickTile(
      key: key,
      selected: selected,
      onTap: state.busy ? null : onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: selected ? StudioColors.amberOf(context) : muted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: StudioColors.inkOf(context),
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: muted, height: 1.35),
                ),
              ],
            ),
          ),
          if (chip.isNotEmpty) ...[
            const SizedBox(width: 8),
            Tooltip(
              message: chip == 'short chat'
                  ? 'Fewer than $kWorldChatMessagesShort messages. Facts '
                        'only will give a thin shelf.'
                  : 'Fewer than $kWorldChatMessagesFloor messages. There '
                        'is almost nothing to skim.',
              child: WorldChip(chip, accent: chip == 'short chat'),
            ),
          ],
        ],
      ),
    );
  }
}

/// A chat row's words, shared with tests: "12 Oct 2026 · 212 messages".
String worldChatRowSubtitle(StoryChatSourceRow r) =>
    '${DateFormat.yMMMd().format(r.createdAt)} · '
    '${r.messageCount} message${r.messageCount == 1 ? '' : 's'}';
