// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// ... standard ...
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

class ChaosModeSection extends StatelessWidget {
  final ChatService chat;
  final VoidCallback onSpinRequested;
  const ChaosModeSection({
    super.key,
    required this.chat,
    required this.onSpinRequested,
  });

  Color get _pressureColor => Color.lerp(
    const Color(0xFF2EC4B6),
    const Color(0xFFE63946),
    (chat.chaosPressure / 100).clamp(0.0, 1.0),
  )!;

  @override
  Widget build(BuildContext context) {
    final borderColor = chat.chaosModeEnabled
        ? _pressureColor.withValues(alpha: 0.5)
        : AppColors.borderOf(context).withValues(alpha: 0.3);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.cardOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: chat.chaosModeEnabled,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          leading: Text(
            '🎰',
            style: TextStyle(
              fontSize: 16,
              shadows: chat.chaosModeEnabled
                  ? [Shadow(color: _pressureColor, blurRadius: 10)]
                  : null,
            ),
          ),
          title: Row(
            children: [
              Text(
                'Chaos Mode',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const Spacer(),
              Switch(
                value: chat.chaosModeEnabled,
                onChanged: (v) => chat.setChaosModeEnabled(v),
                activeThumbColor: AppColors.resolve(
                  context,
                  const Color(0xFFFFD166),
                  Colors.amber.shade700,
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pressure bar
                  Row(
                    children: [
                      Icon(
                        Icons.casino_rounded,
                        size: 12,
                        color: _pressureColor,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pressure: ${chat.chaosPressure}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: _pressureColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: (chat.chaosPressure / 100).clamp(0.0, 1.0),
                      minHeight: 5,
                      backgroundColor: AppColors.borderOf(
                        context,
                      ).withValues(alpha: 0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(_pressureColor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  // NSFW spicy events toggle
                  Row(
                    children: [
                      const Text('🌶️', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Include spicy events',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: chat.chaosNsfwEnabled,
                          onChanged: (v) => chat.setChaosNsfwEnabled(v),
                          activeThumbColor: AppColors.resolve(
                            context,
                            const Color(0xFFFF6B9D),
                            Colors.pink.shade600,
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: chat.hasPendingChaosEvent ? null : onSpinRequested,
                    child: Opacity(
                      opacity: chat.hasPendingChaosEvent ? 0.4 : 1.0,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: chat.hasPendingChaosEvent
                                ? [
                                    AppColors.surfaceContainerOf(context),
                                    AppColors.cardOf(context),
                                  ]
                                : [
                                    const Color(0xFFFFD166),
                                    const Color(0xFFFFC233),
                                  ],
                          ),
                          borderRadius: BorderRadius.circular(8),
                          border: chat.hasPendingChaosEvent
                              ? Border.all(
                                  color: AppColors.borderOf(
                                    context,
                                  ).withValues(alpha: 0.3),
                                )
                              : null,
                          boxShadow: chat.hasPendingChaosEvent
                              ? []
                              : [
                                  BoxShadow(
                                    color: const Color(
                                      0xFFFFD166,
                                    ).withValues(alpha: 0.3),
                                    blurRadius: 10,
                                  ),
                                ],
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              chat.hasPendingChaosEvent ? '⏳' : '🎰',
                              style: const TextStyle(fontSize: 14),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              chat.hasPendingChaosEvent
                                  ? 'EVENT PENDING'
                                  : 'SPIN NOW',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: chat.hasPendingChaosEvent
                                    ? AppColors.textTertiary(context)
                                    : const Color(0xFF1A1200),
                                letterSpacing: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Auto-triggers grow more likely each turn.\nBase: 5% · +5% per turn · cap: 100%',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textTertiary(context),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
