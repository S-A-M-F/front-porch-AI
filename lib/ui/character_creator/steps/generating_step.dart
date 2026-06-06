// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Generating step with progress + streaming preview.
class GeneratingStep extends StatelessWidget {
  final CreatorState state;

  const GeneratingStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('generating'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Generating your character...',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: AppColors.surfaceContainerOf(context),
              ),
              const SizedBox(height: 8),
              Text(
                state.generationStatus,
                style: TextStyle(color: AppColors.textSecondary(context)),
              ),
              const SizedBox(height: 16),
              if (state.generationPreview.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    state.generationPreview,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: state.abortGeneration,
                icon: const Icon(Icons.cancel),
                label: const Text('Cancel Generation'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary(context),
                  side: BorderSide(color: AppColors.borderOf(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
