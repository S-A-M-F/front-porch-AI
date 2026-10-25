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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import '../sidebar_tokens.dart';

/// The Character State gear flyout — an inline inset panel (not a popup menu,
/// which would dismiss on every toggle tap) collecting the simulation
/// switches that used to be scattered through realism_section: Needs
/// Simulation and One-Shot Eval. Manual time nudging lives ONLY on the
/// TimeStrip's chevrons (a duplicate row here was removed — user feedback
/// 2026-07-03).
///
/// No arousal switch: the old per-chat "NSFW Enhancements" row overrode
/// Porch Life, so turning Afterglow on there did nothing for an existing
/// chat. Porch Life Afterglow (with 18+ on) is now the one gate.
class CharacterStateSettings extends StatelessWidget {
  final ChatService chat;
  final bool isGroup;

  const CharacterStateSettings({
    super.key,
    required this.chat,
    required this.isGroup,
  });

  @override
  Widget build(BuildContext context) {
    // Listening on purpose: one-shot eval lives on StorageService.
    final storage = Provider.of<StorageService>(context);

    return Container(
      padding: SidebarTokens.wellPadding,
      decoration: BoxDecoration(
        color: AppColors.sunkenSurfaceOf(context),
        borderRadius: BorderRadius.circular(SidebarTokens.wellRadius),
        border: Border.all(
          color: AppColors.borderOf(context).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _toggleRow(
            context,
            icon: Icons.battery_std,
            label: 'Needs Simulation',
            caption:
                'Tracks satisfaction levels (hunger, bladder, energy, social, '
                'fun, hygiene, comfort). Higher = more sated / less urgent '
                '(100 = full, 0 = critical). Affects prompts & behavior when '
                'low.',
            value: chat.needsSimEnabled,
            accent: AppColors.porchTerracottaOf(context),
            onChanged: chat.isGenerating
                ? null
                : (val) => chat.setNeedsSimEnabled(val),
          ),
          NeedsClockOffNote(
            clockOn: storage.realismSettings.passageOfTimeDefault,
          ),
          const SizedBox(height: 10),
          _modeRow(
            context,
            icon: Icons.speed,
            label: 'One-Shot Eval',
            caption:
                'Fuses the realism evals into a single LLM call for roughly '
                'double the processing speed. Auto uses it on remote AI '
                'services that support tool calls, and keeps the safer '
                'multi-call path on local models, where small models can '
                'struggle with the combined prompt.',
            value: storage.realismSettings.oneShotMode,
            accent: AppColors.journalAccentOf(context),
            onChanged: chat.isGenerating
                ? null
                : (val) => storage.realismSettings.setOneShotMode(val),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String caption,
    required bool value,
    required Color accent,
    required ValueChanged<bool>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              height: 24,
              child: FittedBox(
                child: Switch(
                  value: value,
                  activeThumbColor: accent,
                  onChanged: onChanged,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10,
          ),
        ),
      ],
    );
  }

  /// [_toggleRow]'s shape for the one tri-state setting: same icon + label +
  /// caption layout, with three compact choice pills where the switch sits.
  /// Auto is listed first because it is the default and the recommendation.
  Widget _modeRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String caption,
    required OneShotMode value,
    required Color accent,
    required ValueChanged<OneShotMode>? onChanged,
  }) {
    Widget pill(OneShotMode mode, String name) {
      final selected = value == mode;
      return GestureDetector(
        onTap: onChanged == null ? null : () => onChanged(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.22)
                : AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? accent : AppColors.borderOf(context),
            ),
          ),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppColors.textPrimary(context)
                  : AppColors.textSecondary(context),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: AppColors.iconSecondary(context)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            pill(OneShotMode.auto, 'Auto'),
            const SizedBox(width: 4),
            pill(OneShotMode.on, 'On'),
            const SizedBox(width: 4),
            pill(OneShotMode.off, 'Off'),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          caption,
          style: TextStyle(
            color: AppColors.textTertiary(context),
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}
