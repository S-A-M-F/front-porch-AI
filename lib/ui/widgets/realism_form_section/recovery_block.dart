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
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/theme/creator_palette.dart';

/// "Recovery after intimacy" — the card author's one control over how their
/// character comes down after climax (recovery overhaul PR 2; the mockup's
/// editor frame). A preset dropdown over the decision-3 table, a minutes
/// slider that is always shown (moving it selects Custom), the clock-off
/// reply hint, and a plain-English "resolves to" line naming the kind and
/// the length. Its copy helpers are pure functions in `recovery_profile.dart`
/// so both this and the web mirror can be pinned against one source.
class RecoveryBlock extends StatelessWidget {
  const RecoveryBlock({
    super.key,
    required this.recovery,
    required this.sex,
    required this.intimateInto,
    required this.intimateNotInto,
    required this.onChanged,
    this.showChargenSuggestion = false,
  });

  final RecoveryProfile recovery;
  final String sex;
  final List<String> intimateInto;
  final List<String> intimateNotInto;
  final ValueChanged<RecoveryProfile> onChanged;

  /// Only the creation flows surface the interview-derived suggestion;
  /// the edit page shows the stored truth with no nagging.
  final bool showChargenSuggestion;

  /// Slider position when the card fixes no length: the middle named value,
  /// so the slider reads as "where Custom would start", not as a 0 that
  /// contradicts the judge-decides label. Moving it always sets Custom.
  static const double neutralSliderMinutes = 90;

  @override
  Widget build(BuildContext context) {
    final palette = context.creatorPalette;
    final textColor = palette?.prose ?? AppColors.textSecondary(context);
    final mutedColor = palette?.muted ?? AppColors.textTertiary(context);
    final accent = palette?.amber ?? AppColors.porchAmberOf(context);
    final presetKey = recovery.presetKey;
    final suggestion = showChargenSuggestion && presetKey == 'auto'
        ? recoverySuggestionLine(
            suggestRecoveryPreset(
              intimateInto: intimateInto,
              intimateNotInto: intimateNotInto,
            ),
          )
        : null;
    final sliderValue = (recovery.recoveryMinutes ?? neutralSliderMinutes)
        .toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recovery after intimacy',
          style: TextStyle(
            color: palette?.ink ?? AppColors.textPrimary(context),
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'How this character comes down after climax.',
          style: TextStyle(color: mutedColor, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette?.raise ?? AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: palette?.line ?? AppColors.borderOf(context),
            ),
          ),
          child: DropdownButton<String>(
            key: const Key('recovery-preset-dropdown'),
            value: presetKey,
            isExpanded: true,
            dropdownColor:
                palette?.raise ?? AppColors.surfaceContainerOf(context),
            underline: const SizedBox(),
            style: TextStyle(
              color: palette?.ink ?? AppColors.textPrimary(context),
              fontSize: 14,
            ),
            items: [
              for (final p in kRecoveryPresets)
                DropdownMenuItem(value: p.key, child: Text(p.label)),
            ],
            onChanged: (key) {
              if (key == null) return;
              onChanged(
                key == 'custom'
                    ? recovery.withMinutes(sliderValue.round())
                    : RecoveryProfile.fromPreset(
                        key,
                        pcdMood: recovery.pcdMood,
                      ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Recovery minutes',
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: accent,
                  inactiveTrackColor:
                      (palette?.line ?? AppColors.borderOf(context)).withValues(
                        alpha: 0.3,
                      ),
                  thumbColor: accent,
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 7,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 14,
                  ),
                ),
                child: Slider(
                  key: const Key('recovery-minutes-slider'),
                  value: sliderValue,
                  min: kRecoveryMinutesMin.toDouble(),
                  max: kRecoveryMinutesMax.toDouble(),
                  label: '${sliderValue.round()} min',
                  onChanged: (v) => onChanged(recovery.withMinutes(v.round())),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${sliderValue.round()} min',
              style: TextStyle(color: accent, fontSize: 12),
            ),
          ],
        ),
        Text(
          recoveryClockOffHint(recovery.recoveryMinutes),
          key: const Key('recovery-clock-off-hint'),
          style: TextStyle(color: mutedColor, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 10),
        // PR 8: the grey-drift dial. Opt-in by law — Off ships and Off is
        // what every pre-PR-8 card reads, so no existing character gains
        // a tone-shift it never asked for.
        Text(
          'Grey drift after',
          style: TextStyle(
            color: textColor,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'A hollow, misty mood some people feel minutes to an hour after '
          'intimacy — real, brief, and not about their partner. How often '
          'it visits after a climax.',
          style: TextStyle(color: mutedColor, fontSize: 11, height: 1.35),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette?.raise ?? AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: palette?.line ?? AppColors.borderOf(context),
            ),
          ),
          child: DropdownButton<String>(
            key: const Key('recovery-pcd-dropdown'),
            value: recovery.pcdMood,
            isExpanded: true,
            dropdownColor:
                palette?.raise ?? AppColors.surfaceContainerOf(context),
            underline: const SizedBox(),
            style: TextStyle(
              color: palette?.ink ?? AppColors.textPrimary(context),
              fontSize: 14,
            ),
            items: [
              for (final o in kPcdOptions)
                DropdownMenuItem(value: o.key, child: Text(o.label)),
            ],
            onChanged: (mood) {
              if (mood == null) return;
              onChanged(recovery.withPcdMood(mood));
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          recoveryResolvesLine(recovery, sex),
          key: const Key('recovery-resolves-line'),
          style: TextStyle(color: mutedColor, fontSize: 11, height: 1.35),
        ),
        if (suggestion != null) ...[
          const SizedBox(height: 6),
          Text(
            suggestion,
            key: const Key('recovery-suggestion'),
            style: TextStyle(
              color: accent.withValues(alpha: 0.9),
              fontSize: 11,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}
