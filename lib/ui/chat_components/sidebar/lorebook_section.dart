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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Lorebook section for 1:1 (extracted).
class LorebookSection extends StatefulWidget {
  final CharacterCard character;
  const LorebookSection({required this.character});

  @override
  State<LorebookSection> createState() => _LorebookSectionState();
}

class _LorebookSectionState extends State<LorebookSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Lorebook Triggers',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child:
                widget.character.lorebook != null &&
                    widget.character.lorebook!.entries.isNotEmpty
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.character.lorebook!.entries
                          .where((e) => e.enabled)
                          .isEmpty)
                        Text(
                          'No enabled entries.',
                          style: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 12,
                          ),
                        ),

                      ...widget.character.lorebook!.entries
                          .where((e) => e.enabled)
                          .map((entry) {
                            Color dotColor = AppColors.resolve(
                              context,
                              Colors.redAccent,
                              Colors.red.shade700,
                            );
                            if (entry.constant) {
                              dotColor = AppColors.resolve(
                                context,
                                Colors.blueAccent,
                                Colors.blue.shade700,
                              );
                            } else if (entry.isTriggered) {
                              dotColor = AppColors.resolve(
                                context,
                                Colors.greenAccent,
                                Colors.green.shade700,
                              );
                            }

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 4.0,
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: AppColors.resolve(
                                        context,
                                        dotColor,
                                        dotColor.withValues(alpha: 0.85),
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key.isEmpty && entry.constant
                                          ? 'Always Active'
                                          : entry.displayName,
                                      style: TextStyle(
                                        color:
                                            (entry.isTriggered ||
                                                entry.constant)
                                            ? AppColors.textPrimary(context)
                                            : AppColors.textSecondary(context),
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                    ],
                  )
                : Text(
                    'No lorebook entries.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  ),
          ),
        ],
      ],
    );
  }
}

/// Group-aware lorebook triggers section for the group chat sidebar.
class GroupLorebookSection extends StatefulWidget {
  final ChatService chatService;
  const GroupLorebookSection({required this.chatService});

  @override
  State<GroupLorebookSection> createState() => _GroupLorebookSectionState();
}

class _GroupLorebookSectionState extends State<GroupLorebookSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final activeEntries = widget.chatService.getActiveGroupLoreEntries();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4.0),
            child: Row(
              children: [
                Icon(
                  _expanded ? Icons.expand_more : Icons.chevron_right,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(
                  'Lorebook Triggers',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                if (activeEntries.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${activeEntries.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.greenAccent,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 20.0),
            child: activeEntries.isEmpty
                ? Text(
                    'No active lorebook entries.',
                    style: TextStyle(
                      color: AppColors.textTertiary(context),
                      fontSize: 12,
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: activeEntries.map((entry) {
                      Color dotColor = AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      );
                      if (entry.constant) {
                        dotColor = AppColors.resolve(
                          context,
                          Colors.blueAccent,
                          Colors.blue.shade700,
                        );
                      } else if (entry.isTriggered) {
                        dotColor = AppColors.resolve(
                          context,
                          Colors.greenAccent,
                          Colors.green.shade700,
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3.0),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: AppColors.resolve(
                                  context,
                                  dotColor,
                                  dotColor.withValues(alpha: 0.85),
                                ),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.displayName,
                                style: TextStyle(
                                  color: (entry.isTriggered || entry.constant)
                                      ? AppColors.textPrimary(context)
                                      : AppColors.textSecondary(context),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ],
    );
  }
}
