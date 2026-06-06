// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/styled_text_field.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Quick config step (minimal).
class QuickConfigStep extends StatelessWidget {
  final CreatorState state;

  const QuickConfigStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final nameEmpty = state.nameController.text.trim().isEmpty;

    return Center(
      key: const ValueKey('quick-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Quick Character Config',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Minimal details for fast generation.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),

              StyledTextField(
                controller: state.nameController,
                label: 'Character Name',
                hint: 'e.g. Elara the Fox',
                required: true,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 16),

              StyledTextField(
                controller: state.quickScenarioController,
                label: 'Scenario / Concept (optional)',
                maxLines: 3,
                onChanged: (_) => state.notify(),
              ),

              const SizedBox(height: 16),
              // Tone chips, greeting count (lifted from quick form, bound to state.quick*)
              Text(
                'Tones',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              Wrap(
                spacing: 8,
                children:
                    [
                      'Neutral',
                      'Friendly',
                      'Mysterious',
                      'Aggressive',
                      'Playful',
                      'Serious',
                    ].map((t) {
                      final sel = state.quickSelectedTones.contains(t);
                      return FilterChip(
                        label: Text(t),
                        selected: sel,
                        onSelected: (v) {
                          if (v) {
                            state.quickSelectedTones.add(t);
                          } else {
                            state.quickSelectedTones.remove(t);
                          }
                          state.notify();
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                'Alt Greetings: ${state.quickGreetingCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              Slider(
                value: state.quickGreetingCount.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                onChanged: (v) {
                  state.quickGreetingCount = v.toInt();
                  state.notify();
                },
              ),

              if (nameEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Name is required to continue.',
                    style: TextStyle(
                      color: AppColors.resolve(
                        context,
                        Colors.redAccent,
                        Colors.red.shade700,
                      ),
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
