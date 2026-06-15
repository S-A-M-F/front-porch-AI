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
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

/// Standalone Needs Simulation configuration form.
///
/// Extracted from RealismFormSection to keep that widget under the 500 LOC cap.
/// Used by the character creator/editor to configure per-need baselines.
class NeedsFormSection extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onEnabledChanged;
  final bool enjoysLowHygiene;
  final ValueChanged<bool> onEnjoysLowHygieneChanged;
  final int needsSimStrength;
  final ValueChanged<int>? onNeedsSimStrengthChanged;

  // Per-need baselines (0-100).
  final int baselineHunger;
  final ValueChanged<int> onBaselineHungerChanged;
  final int baselineBladder;
  final ValueChanged<int> onBaselineBladderChanged;
  final int baselineEnergy;
  final ValueChanged<int> onBaselineEnergyChanged;
  final int baselineSocial;
  final ValueChanged<int> onBaselineSocialChanged;
  final int baselineFun;
  final ValueChanged<int> onBaselineFunChanged;
  final int baselineHygiene;
  final ValueChanged<int> onBaselineHygieneChanged;
  final int baselineComfort;
  final ValueChanged<int> onBaselineComfortChanged;

  // Decay rates (per turn)
  final int? decayHunger;
  final ValueChanged<int>? onDecayHungerChanged;
  final int? decayBladder;
  final ValueChanged<int>? onDecayBladderChanged;
  final int? decayEnergy;
  final ValueChanged<int>? onDecayEnergyChanged;
  final int? decaySocial;
  final ValueChanged<int>? onDecaySocialChanged;
  final int? decayFun;
  final ValueChanged<int>? onDecayFunChanged;
  final int? decayHygiene;
  final ValueChanged<int>? onDecayHygieneChanged;
  final int? decayComfort;
  final ValueChanged<int>? onDecayComfortChanged;

  const NeedsFormSection({
    super.key,
    required this.enabled,
    required this.onEnabledChanged,
    required this.enjoysLowHygiene,
    required this.onEnjoysLowHygieneChanged,
    required this.needsSimStrength,
    this.onNeedsSimStrengthChanged,
    required this.baselineHunger,
    required this.onBaselineHungerChanged,
    required this.baselineBladder,
    required this.onBaselineBladderChanged,
    required this.baselineEnergy,
    required this.onBaselineEnergyChanged,
    required this.baselineSocial,
    required this.onBaselineSocialChanged,
    required this.baselineFun,
    required this.onBaselineFunChanged,
    required this.baselineHygiene,
    required this.onBaselineHygieneChanged,
    required this.baselineComfort,
    required this.onBaselineComfortChanged,
    this.decayHunger,
    this.onDecayHungerChanged,
    this.decayBladder,
    this.onDecayBladderChanged,
    this.decayEnergy,
    this.onDecayEnergyChanged,
    this.decaySocial,
    this.onDecaySocialChanged,
    this.decayFun,
    this.onDecayFunChanged,
    this.decayHygiene,
    this.onDecayHygieneChanged,
    this.decayComfort,
    this.onDecayComfortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──
        const SizedBox(height: 24),
        Text(
          'Needs Simulation',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 8),

        // ── Card ──
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Master toggle
              RealismFormSection.buildToggleRow(
                icon: Icons.battery_std,
                label: 'Needs Simulation',
                subtitle:
                    'Hunger etc. (higher = more sated/less urgent; 100=full, 0=critical) — influences prompts & behavior when low',
                value: enabled,
                onChanged: onEnabledChanged,
                context: context,
              ),

              // ── Gated content (only when Needs Simulation is ON) ──
              if (enabled) ...[
                const SizedBox(height: 16),

                // Per-need baseline sliders
                _needsSlider(
                  label: 'Hunger',
                  value: baselineHunger,
                  onChanged: onBaselineHungerChanged,
                  decayValue: decayHunger,
                  onDecayChanged: onDecayHungerChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Bladder',
                  value: baselineBladder,
                  onChanged: onBaselineBladderChanged,
                  decayValue: decayBladder,
                  onDecayChanged: onDecayBladderChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Energy',
                  value: baselineEnergy,
                  onChanged: onBaselineEnergyChanged,
                  decayValue: decayEnergy,
                  onDecayChanged: onDecayEnergyChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Social',
                  value: baselineSocial,
                  onChanged: onBaselineSocialChanged,
                  decayValue: decaySocial,
                  onDecayChanged: onDecaySocialChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Fun',
                  value: baselineFun,
                  onChanged: onBaselineFunChanged,
                  decayValue: decayFun,
                  onDecayChanged: onDecayFunChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Hygiene',
                  value: baselineHygiene,
                  onChanged: onBaselineHygieneChanged,
                  decayValue: decayHygiene,
                  onDecayChanged: onDecayHygieneChanged,
                  context: context,
                ),
                const SizedBox(height: 12),
                _needsSlider(
                  label: 'Comfort',
                  value: baselineComfort,
                  onChanged: onBaselineComfortChanged,
                  decayValue: decayComfort,
                  onDecayChanged: onDecayComfortChanged,
                  context: context,
                ),

                const SizedBox(height: 16),
                Divider(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                const SizedBox(height: 12),

                // Enjoys low hygiene
                RealismFormSection.buildToggleRow(
                  icon: Icons.water_drop_outlined,
                  label: 'Enjoys low hygiene',
                  subtitle:
                      'Character prefers being sweaty, musky, or filthy (inverts hygiene behavior)',
                  value: enjoysLowHygiene,
                  onChanged: onEnjoysLowHygieneChanged,
                  context: context,
                ),

                const SizedBox(height: 16),
                Divider(color: AppColors.borderOf(context).withValues(alpha: 0.4)),
                const SizedBox(height: 12),

                // Needs delta strength
                if (onNeedsSimStrengthChanged != null) ...[
                  Text(
                    'Needs delta strength: $needsSimStrength x (1x baseline; 5x = 5× larger swings)',
                    style: TextStyle(
                      color: AppColors.textSecondary(context),
                      fontSize: 12,
                    ),
                  ),
                  Slider(
                    value: needsSimStrength.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    label: '$needsSimStrength x',
                    onChanged: (d) {
                      onNeedsSimStrengthChanged?.call(d.round());
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _needsSlider({
    required String label,
    required int value,
    required ValueChanged<int> onChanged,
    int? decayValue,
    ValueChanged<int>? onDecayChanged,
    required BuildContext context,
  }) {
    final mainSlider = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const Spacer(),
            Text(
              '$value / 100',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.emotionAccent,
            inactiveTrackColor: AppColors.borderOf(context).withValues(alpha: 0.3),
            thumbColor: AppColors.emotionAccent,
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: value.toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            onChanged: (d) => onChanged(d.round()),
          ),
        ),
      ],
    );

    if (decayValue == null || onDecayChanged == null) {
      return mainSlider;
    }

    String decayDescription;
    if (decayValue == 0) {
      decayDescription = 'Static (0)';
    } else if (decayValue <= 2) {
      decayDescription = 'Very Slow ($decayValue)';
    } else if (decayValue <= 4) {
      decayDescription = 'Slow ($decayValue)';
    } else if (decayValue <= 7) {
      decayDescription = 'Normal ($decayValue)';
    } else if (decayValue <= 12) {
      decayDescription = 'Fast ($decayValue)';
    } else {
      decayDescription = 'Very Fast ($decayValue)';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mainSlider,
        Padding(
          padding: const EdgeInsets.only(left: 12.0, right: 8.0, top: 2.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Decay Rate / Turn',
                    style: TextStyle(
                      color: AppColors.textSecondary(context).withValues(alpha: 0.7),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    decayDescription,
                    style: TextStyle(
                      color: AppColors.textSecondary(context).withValues(alpha: 0.7),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
              SliderTheme(
                data: SliderThemeData(
                  activeTrackColor: AppColors.emotionAccent.withValues(alpha: 0.5),
                  inactiveTrackColor: AppColors.borderOf(context).withValues(alpha: 0.15),
                  thumbColor: AppColors.emotionAccent.withValues(alpha: 0.7),
                  trackHeight: 2,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                ),
                child: Slider(
                  value: decayValue.toDouble(),
                  min: 0,
                  max: 20,
                  divisions: 20,
                  onChanged: (d) => onDecayChanged(d.round()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
