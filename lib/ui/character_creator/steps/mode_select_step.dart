// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/mode_card.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 1: Mode selection (Automated / Guided / Quick).
class ModeSelectStep extends StatelessWidget {
  final CreatorState state;

  const ModeSelectStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('mode-select'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'How do you want to create?',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the creation mode that fits your workflow.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),

              ModeCard(
                title: 'Automated',
                subtitle:
                    'Describe your character in a few sentences. The AI does the rest.',
                icon: Icons.auto_awesome,
                isSelected: state.creatorMode == CreatorMode.automated,
                onTap: () {
                  state.creatorMode = CreatorMode.automated;
                  // In thin shell, next would advance step; here for direct
                },
              ),
              const SizedBox(height: 12),
              ModeCard(
                title: 'Guided',
                subtitle:
                    'Answer a series of questions for more control over the result.',
                icon: Icons.list_alt,
                isSelected: state.creatorMode == CreatorMode.guided,
                onTap: () => state.creatorMode = CreatorMode.guided,
              ),
              const SizedBox(height: 12),
              ModeCard(
                title: 'Quick',
                subtitle: 'Minimal inputs. Fastest path to a usable character.',
                icon: Icons.bolt,
                isSelected: state.creatorMode == CreatorMode.quick,
                onTap: () => state.creatorMode = CreatorMode.quick,
              ),

              const SizedBox(height: 32),
              Text(
                'You can always edit the generated card in the Review step.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
