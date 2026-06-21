// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_options.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Amber-bordered "Quick Start" card of archetype preset chips. Tapping a chip
/// auto-fills the concept + personality keywords (and name if empty) from the
/// selected preset. Restored from the pre-refactor automated config step.
class ArchetypePresetCard extends StatelessWidget {
  final CreatorState state;

  const ArchetypePresetCard({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final amberSel = AppColors.resolve(
      context,
      Colors.amberAccent,
      const Color(0xFFB45309),
    );
    final selectedFg = AppColors.resolve(context, Colors.white, Colors.black87);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.resolve(
            context,
            Colors.amber.withValues(alpha: 0.3),
            Colors.amber.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: Colors.amberAccent, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Quick Start — Archetype Presets',
                style: TextStyle(
                  color: Colors.amberAccent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap to auto-fill concept & personality',
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: CreatorOptions.archetypePresets.entries.map((entry) {
              final isSelected = state.selectedArchetype == entry.key;
              return ChoiceChip(
                label: Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected
                        ? selectedFg
                        : AppColors.textSecondary(context),
                  ),
                ),
                avatar: Icon(
                  isSelected ? Icons.check : Icons.auto_awesome,
                  size: 14,
                  color: isSelected ? selectedFg : Colors.amberAccent,
                ),
                selected: isSelected,
                selectedColor: AppColors.resolve(
                  context,
                  Colors.amberAccent.withValues(alpha: 0.2),
                  Colors.amber.withValues(alpha: 0.12),
                ),
                backgroundColor: AppColors.surfaceContainerOf(context),
                side: BorderSide(
                  color: isSelected ? amberSel : AppColors.borderOf(context),
                ),
                checkmarkColor: Colors.amberAccent,
                showCheckmark: false,
                onSelected: (_) {
                  if (isSelected) {
                    state.selectedArchetype = '';
                  } else {
                    state.selectedArchetype = entry.key;
                    state.conceptController.text = entry.value['concept'] ?? '';
                    state.keywordsController.text =
                        entry.value['keywords'] ?? '';
                    if (state.nameController.text.isEmpty) {
                      state.nameController.text = entry.key;
                    }
                  }
                  state.saveState();
                  state.notify();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
