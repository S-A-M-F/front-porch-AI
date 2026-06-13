// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/styled_text_field.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Guided config step (free-text / question based).
class GuidedConfigStep extends StatelessWidget {
  final CreatorState state;

  const GuidedConfigStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('guided-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Guided Configuration',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Fill in the details the AI will use as strong guidance.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),

              StyledTextField(
                controller: state.guidedVisionController,
                label: 'Overall Vision / Concept',
                maxLines: 3,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 12),
              StyledTextField(
                controller: state.guidedAppearanceController,
                label: 'Appearance',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 12),
              StyledTextField(
                controller: state.guidedPersonalityController,
                label: 'Personality',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 12),
              StyledTextField(
                controller: state.guidedHairController,
                label: 'Hair',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedFeaturesController,
                label: 'Features',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedRaceController,
                label: 'Race',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedSpeechController,
                label: 'Speech Style',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedSecretController,
                label: 'Secret',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedOriginController,
                label: 'Origin',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedSettingController,
                label: 'Setting',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedToneController,
                label: 'Tone',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedRelDynamicController,
                label: 'Rel Dynamic',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedRelScenarioController,
                label: 'Rel Scenario',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwBodyController,
                label: 'NSFW Body',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwExpController,
                label: 'NSFW Exp',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwDomController,
                label: 'NSFW Dom',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwKinksController,
                label: 'NSFW Kinks',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwClothingController,
                label: 'NSFW Clothing',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.guidedNsfwPersonalityController,
                label: 'NSFW Personality',
                maxLines: 1,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 8),
              StyledTextField(
                controller: state.loreUrlsController,
                label: 'Lore URLs',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
              StyledTextField(
                controller: state.backstoryNotesController,
                label: 'Backstory Notes',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
