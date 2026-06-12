// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/widgets/needs_form_section.dart';

/// Realism initial state step (lifted).
class RealismStep extends StatelessWidget {
  final CreatorState state;

  const RealismStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('realism'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Initial Realism State (optional)',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set starting bond, trust, emotion, needs sim etc for the character. Full form lifted from original _buildRealismStep using RealismFormSection + toggles bound to state.',
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 16),
              // Threaded verif controls (3: toggle + 2 sliders) per approved plan "wire in all current form users" + realism_step.
              // Other realism seeds (bond etc) are stub in creator_state; dummies here for required form props.
              RealismFormSection(
                enabled: false,
                onEnabledChanged: (_) {},
                timeOfDay: 'morning',
                onTimeOfDayChanged: (_) {},
                dayCount: 1,
                onDayCountChanged: (_) {},
                shortTermBond: 0,
                onShortTermBondChanged: (_) {},
                longTermBond: 0,
                onLongTermBondChanged: (_) {},
                trustLevel: 0,
                onTrustLevelChanged: (_) {},
                emotion: 'neutral',
                onEmotionChanged: (_) {},
                emotionIntensity: 'mild',
                onEmotionIntensityChanged: (_) {},
                nsfwCooldownEnabled: false,
                onNsfwCooldownChanged: (_) {},
                chaosModeEnabled: false,
                onChaosModeChanged: (_) {},
                currentTask: '',
                onCurrentTaskChanged: (_) {},
                realismVerificationEnabled: state.realismVerificationEnabled,
                onRealismVerificationChanged: (v) {
                  state.realismVerificationEnabled = v;
                  state.notify();
                },
                realismVerificationMaxReprocesses:
                    state.realismVerificationMaxReprocesses,
                onRealismVerificationMaxReprocessesChanged: (v) {
                  state.realismVerificationMaxReprocesses = v;
                  state.notify();
                },
                realismVerificationStrictness:
                    state.realismVerificationStrictness,
                onRealismVerificationStrictnessChanged: (v) {
                  state.realismVerificationStrictness = v;
                  state.notify();
                },
                needsFormSection: NeedsFormSection(
                  enabled: false,
                  onEnabledChanged: (_) {},
                  enjoysLowHygiene: false,
                  onEnjoysLowHygieneChanged: (_) {},
                  needsSimStrength: 1,
                  baselineHunger: 80,
                  onBaselineHungerChanged: (_) {},
                  baselineBladder: 80,
                  onBaselineBladderChanged: (_) {},
                  baselineEnergy: 80,
                  onBaselineEnergyChanged: (_) {},
                  baselineSocial: 80,
                  onBaselineSocialChanged: (_) {},
                  baselineFun: 80,
                  onBaselineFunChanged: (_) {},
                  baselineHygiene: 80,
                  onBaselineHygieneChanged: (_) {},
                  baselineComfort: 80,
                  onBaselineComfortChanged: (_) {},
                  decayHunger: 5,
                  onDecayHungerChanged: (_) {},
                  decayBladder: 5,
                  onDecayBladderChanged: (_) {},
                  decayEnergy: 5,
                  onDecayEnergyChanged: (_) {},
                  decaySocial: 5,
                  onDecaySocialChanged: (_) {},
                  decayFun: 5,
                  onDecayFunChanged: (_) {},
                  decayHygiene: 5,
                  onDecayHygieneChanged: (_) {},
                  decayComfort: 5,
                  onDecayComfortChanged: (_) {},
                ),
                showVerificationToggle: true,
                showNsfwCooldownToggle: false,
                showChaosToggle: false,
                showTimeAndDay: false,
                showMasterEnabledToggle: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
