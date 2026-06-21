// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';

/// Step 4: seed the Realism Engine's initial state for the generated character.
/// Restored from the god file's `_buildRealismStep` — the full form is now wired
/// to CreatorState instead of the dummy hardcoded values the refactor shipped.
class RealismStep extends StatelessWidget {
  final CreatorState state;

  const RealismStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    // Generation-error fallback: if the LLM produced nothing, offer a retry
    // back to the config step (the wizard advanced here regardless).
    if (state.generatedCard == null) {
      return Center(
        key: const ValueKey('realism-error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Generation failed. The LLM did not produce valid output.',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                state.generationPreview = '';
                state.currentStep = 2;
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('Try Again'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.resolve(
                  context,
                  Colors.blueAccent,
                  Colors.blue.shade700,
                ),
              ),
            ),
          ],
        ),
      );
    }

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
                'Realism Engine',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set the initial state for the Realism Engine when a new conversation starts. '
                'These values will seed the relationship, emotion, and time-of-day systems.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              RealismFormSection(
                enabled: state.realismStepEnabled,
                onEnabledChanged: (v) {
                  state.realismStepEnabled = v;
                  state.notify();
                },
                timeOfDay: state.realismTimeOfDay,
                onTimeOfDayChanged: (v) {
                  state.realismTimeOfDay = v;
                  state.notify();
                },
                dayCount: state.realismDayCount,
                onDayCountChanged: (v) {
                  state.realismDayCount = v;
                  state.notify();
                },
                shortTermBond: state.realismShortTermBond,
                onShortTermBondChanged: (v) {
                  state.realismShortTermBond = v;
                  state.notify();
                },
                longTermBond: state.realismLongTermBond,
                onLongTermBondChanged: (v) {
                  state.realismLongTermBond = v;
                  state.notify();
                },
                trustLevel: state.realismTrustLevel,
                onTrustLevelChanged: (v) {
                  state.realismTrustLevel = v;
                  state.notify();
                },
                emotion: state.realismEmotion,
                onEmotionChanged: (v) {
                  state.realismEmotion = v;
                  state.notify();
                },
                emotionIntensity: state.realismEmotionIntensity,
                onEmotionIntensityChanged: (v) {
                  state.realismEmotionIntensity = v;
                  state.notify();
                },
                nsfwCooldownEnabled: state.realismNsfwCooldown,
                onNsfwCooldownChanged: (v) {
                  state.realismNsfwCooldown = v;
                  state.notify();
                },
                chaosModeEnabled: state.realismChaosMode,
                onChaosModeChanged: (v) {
                  state.realismChaosMode = v;
                  state.notify();
                },
                currentTask: state.realismCurrentTask,
                onCurrentTaskChanged: (v) {
                  state.realismCurrentTask = v;
                  state.notify();
                },
                realismVerificationEnabled: state.realismVerificationEnabled,
                onRealismVerificationChanged: (v) {
                  state.realismVerificationEnabled = v;
                  state.saveState();
                  state.notify();
                },
                realismVerificationMaxReprocesses:
                    state.realismVerificationMaxReprocesses,
                onRealismVerificationMaxReprocessesChanged: (v) {
                  state.realismVerificationMaxReprocesses = v;
                  state.saveState();
                  state.notify();
                },
                realismVerificationStrictness:
                    state.realismVerificationStrictness,
                onRealismVerificationStrictnessChanged: (v) {
                  state.realismVerificationStrictness = v;
                  state.saveState();
                  state.notify();
                },
                needsFormSection: _needsToggles(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Needs-simulation seed toggles. The refactored RealismFormSection exposes a
  /// slot for these instead of the god file's inline booleans, so we provide a
  /// compact pair wired to the same seed fields the save step consumes.
  Widget _needsToggles(BuildContext context) {
    final accent = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeThumbColor: accent,
            value: state.realismNeedsSim,
            onChanged: (v) {
              state.realismNeedsSim = v;
              state.notify();
            },
            title: Text(
              'Needs Simulation',
              style: TextStyle(
                color: AppColors.textPrimary(context),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              'Sims-style hunger, energy, social, hygiene and more.',
              style: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 11,
              ),
            ),
          ),
          if (state.realismNeedsSim)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeThumbColor: accent,
              value: state.realismEnjoysLowHygiene,
              onChanged: (v) {
                state.realismEnjoysLowHygiene = v;
                state.notify();
              },
              title: Text(
                'Enjoys Low Hygiene',
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Inverts the hygiene need — this character likes being filthy.',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
