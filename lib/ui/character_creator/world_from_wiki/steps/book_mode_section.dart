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

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/world_from_wiki/world_from_wiki.dart';
import 'package:front_porch_ai/ui/character_creator/world_from_wiki/steps/world_section_card.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The three mode tiles on the Book step's "What to make" card: Facts
/// only, Faithful, Creative, each with what it does and what it never
/// does, and the one line under them (design §3.3, §5).
class BookModeSection extends StatelessWidget {
  const BookModeSection({
    super.key,
    required this.mode,
    required this.onChanged,
    required this.wide,
    required this.enabled,
    this.hasChat = true,
  });

  final WorldBuildMode mode;
  final ValueChanged<WorldBuildMode> onChanged;
  final bool wide;
  final bool enabled;

  /// Whether a chat is picked: the default chip moves with it.
  final bool hasChat;

  @override
  Widget build(BuildContext context) {
    final muted = StudioColors.mutedOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, box) {
            final cols = wide ? 3 : 1;
            final w = cols == 1
                ? box.maxWidth
                : (box.maxWidth - 10 * (cols - 1)) / cols;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final m in WorldBuildMode.values)
                  SizedBox(width: w, child: _tile(context, m)),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Text(
          WorldBuildModeX.explainer,
          style: TextStyle(fontSize: 12, color: muted, height: 1.4),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, WorldBuildMode m) {
    final on = m == mode;
    final ink = StudioColors.inkOf(context);
    final prose = StudioColors.proseOf(context);
    final isDefault = hasChat
        ? m == WorldBuildMode.factsOnly
        : m == WorldBuildMode.creative;
    return WorldPickTile(
      key: Key('world-from-character-mode-${m.name}'),
      selected: on,
      onTap: enabled ? () => onChanged(m) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                switch (m) {
                  WorldBuildMode.factsOnly => Icons.check,
                  WorldBuildMode.faithful => Icons.menu_book_outlined,
                  WorldBuildMode.creative => Icons.auto_awesome_outlined,
                },
                size: 16,
                color: on
                    ? StudioColors.amberOf(context)
                    : StudioColors.mutedOf(context),
              ),
              const SizedBox(width: 8),
              Text(
                m.label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: ink,
                ),
              ),
              if (isDefault) ...[
                const SizedBox(width: 8),
                WorldChip(
                  hasChat ? 'default with a chat' : 'default for Card only',
                  accent: on,
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          _line(context, 'What it does:', m.does, prose, ink),
          const SizedBox(height: 4),
          _line(context, 'Never:', m.never, prose, ink),
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String lead,
    String body,
    Color prose,
    Color ink,
  ) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text: '$lead ',
          style: TextStyle(fontWeight: FontWeight.w700, color: ink),
        ),
        TextSpan(text: body),
      ],
    ),
    style: TextStyle(fontSize: 12, height: 1.4, color: prose),
  );
}
