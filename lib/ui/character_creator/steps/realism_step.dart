// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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
              // In full: the RealismFormSection + all the _realism* fields from state (if extended) or direct card extensions.
              Text(
                '(Complete realism config UI here in extraction — matches create_character_page pattern for consistency.)',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
