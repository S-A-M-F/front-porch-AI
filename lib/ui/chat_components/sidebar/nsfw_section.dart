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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class NsfwEnhancementsSection extends StatefulWidget {
  final ChatService chat;
  const NsfwEnhancementsSection({super.key, required this.chat});

  @override
  State<NsfwEnhancementsSection> createState() =>
      NsfwEnhancementsSectionState();
}

class NsfwEnhancementsSectionState extends State<NsfwEnhancementsSection> {
  bool _expanded = true; // default expanded

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
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
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: Color(0xFFEA580C),
                ),
                const SizedBox(width: 5),
                const Flexible(
                  child: Text(
                    'NSFW Enhancements',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEA580C),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.chat.nsfwCooldownEnabled &&
                    widget.chat.cooldownTurnsRemaining > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.resolve(
                        context,
                        Colors.deepOrange,
                        const Color(0xFFC2410C),
                      ).withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '⏳ ${widget.chat.cooldownTurnsRemaining}t',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFFEA580C),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                SizedBox(
                  height: 20,
                  child: Switch(
                    value: widget.chat.nsfwCooldownEnabled,
                    activeThumbColor: AppColors.resolve(
                      context,
                      const Color(0xFFEA580C),
                      const Color(0xFFF97316),
                    ),
                    onChanged: widget.chat.isGenerating
                        ? null
                        : (val) {
                            widget.chat.setNsfwCooldownEnabled(val);
                            if (val) setState(() => _expanded = true);
                          },
                  ),
                ),
              ],
            ),
          ),
        ),

        // Expanded content
        if (_expanded) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.resolve(
                context,
                Colors.deepOrange,
                const Color(0xFFC2410C),
              ).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: AppColors.resolve(
                  context,
                  Colors.deepOrange,
                  const Color(0xFFC2410C),
                ).withValues(alpha: 0.2),
              ),
            ),
            child: Column(
              children: [
                // ── Lust ──
                if (widget.chat.nsfwCooldownEnabled) ...[
                  Row(
                    children: [
                      Icon(
                        widget.chat.arousalTier >= 6
                            ? Icons.local_fire_department
                            : widget.chat.arousalTier <= -1
                            ? Icons.ac_unit
                            : Icons.favorite_border,
                        size: 13,
                        color: widget.chat.arousalTier >= 6
                            ? AppColors.resolve(
                                context,
                                const Color(0xFFC2410C),
                                const Color(0xFF9A3412),
                              )
                            : widget.chat.arousalTier <= -1
                            ? AppColors.resolve(
                                context,
                                const Color(0xFF38BDF8),
                                const Color(0xFF1D4ED8),
                              )
                            : AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          'Lust: ${widget.chat.arousalTierName}',
                          style: TextStyle(
                            fontSize: 12,
                            color: widget.chat.arousalTier >= 6
                                ? AppColors.resolve(
                                    context,
                                    const Color(0xFFC2410C),
                                    const Color(0xFF9A3412),
                                  )
                                : widget.chat.arousalTier <= -1
                                ? AppColors.resolve(
                                    context,
                                    const Color(0xFF38BDF8),
                                    const Color(0xFF1D4ED8),
                                  )
                                : AppColors.textSecondary(context),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.chat.arousalLevel.clamp(-100, 100)}/100',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (widget.chat.arousalLevel.abs() / 100).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 4,
                      backgroundColor: AppColors.borderOf(
                        context,
                      ).withValues(alpha: 0.25),
                      valueColor: AlwaysStoppedAnimation<Color>(
                        widget.chat.arousalTier >= 6
                            ? AppColors.resolve(
                                context,
                                const Color(0xFFC2410C),
                                const Color(0xFF9A3412),
                              )
                            : AppColors.resolve(
                                context,
                                const Color(0xFF38BDF8),
                                const Color(0xFF1D4ED8),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (widget.chat.nsfwCooldownEnabled &&
                    widget.chat.cooldownTurnsRemaining > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.hourglass_bottom,
                        size: 12,
                        color: Color(0xFFEA580C),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Refractory: ${widget.chat.cooldownTurnsRemaining} turn${widget.chat.cooldownTurnsRemaining == 1 ? '' : 's'} remaining',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFFEA580C),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
