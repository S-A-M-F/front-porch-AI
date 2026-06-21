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

  void _select(CreatorMode mode) {
    state.creatorMode = mode;
    state.saveState();
    state.notify();
  }

  @override
  Widget build(BuildContext context) {
    final amber = AppColors.resolve(
      context,
      Colors.amberAccent,
      const Color(0xFFB45309),
    );
    final teal = AppColors.resolve(
      context,
      Colors.tealAccent,
      const Color(0xFF0D7377),
    );
    final green = AppColors.resolve(
      context,
      Colors.greenAccent,
      const Color(0xFF15803D),
    );

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
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              ModeCard(
                title: 'Automated Creator',
                subtitle: 'Pick traits from bubbles, let AI fill the gaps',
                description:
                    'Best when you want to explore and discover. '
                    'Select from archetypes, appearance options, backstory presets, '
                    'and personality keywords. The AI handles the rest.',
                features: const [
                  'Archetype presets',
                  'Bubble selectors for every trait',
                  'AI generates description from selections',
                ],
                icon: Icons.auto_awesome,
                accentColor: amber,
                isSelected: state.creatorMode == CreatorMode.automated,
                onTap: () => _select(CreatorMode.automated),
              ),
              const SizedBox(height: 16),

              ModeCard(
                title: 'Guided Creator',
                subtitle: 'Write your vision, AI helps you flesh it out',
                description:
                    'Best when you already have a character in mind but need help '
                    'getting it on paper. Describe your idea in your own words — '
                    'guided prompts and suggestions help you express your vision.',
                features: const [
                  'Free-form text with guided prompts',
                  'Suggestion chips for inspiration',
                  '"Help me expand this" AI assist',
                ],
                icon: Icons.edit_note,
                accentColor: teal,
                isSelected: state.creatorMode == CreatorMode.guided,
                onTap: () => _select(CreatorMode.guided),
              ),
              const SizedBox(height: 16),

              ModeCard(
                title: 'Quick Create',
                subtitle: 'Name it, describe it, done — AI does the rest',
                description:
                    'Fastest path to a finished character. '
                    'Just give a name and a one-liner. The full AI pipeline '
                    '(interview, lorebook, greetings) runs automatically.',
                features: const [
                  'Name + concept only',
                  'NSFW toggle',
                  'Full pipeline in ~2 min',
                ],
                icon: Icons.bolt,
                accentColor: green,
                isSelected: state.creatorMode == CreatorMode.quick,
                onTap: () => _select(CreatorMode.quick),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
