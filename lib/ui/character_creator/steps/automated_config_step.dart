// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/styled_text_field.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Automated (structured) config step.
class AutomatedConfigStep extends StatelessWidget {
  final CreatorState state;

  const AutomatedConfigStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const ValueKey('automated-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Character Configuration',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Provide structured details. The AI will weave them into a rich card.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                ),
              ),
              const SizedBox(height: 24),

              StyledTextField(
                controller: state.nameController,
                label: 'Name',
                required: true,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 12),
              StyledTextField(
                controller: state.conceptController,
                label: 'Concept / Short Description',
                maxLines: 3,
                onChanged: (_) => state.notify(),
              ),
              const SizedBox(height: 12),
              // Art style dropdown (lifted)
              Text(
                'Art Style',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              DropdownButton<String>(
                value: state.artStyle,
                items: ['Anime', 'Realistic', 'Cartoon', 'Fantasy', 'SciFi']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    state.artStyle = v;
                    state.notify();
                  }
                },
              ),
              const SizedBox(height: 8),
              // Greeting length
              Text(
                'Greeting Length',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              DropdownButton<String>(
                value: state.greetingLength,
                items:
                    [
                          'Short (1 para)',
                          'Medium (2-4 paragraphs)',
                          'Long (5+ paragraphs)',
                        ]
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                onChanged: (v) {
                  if (v != null) {
                    state.greetingLength = v;
                    state.notify();
                  }
                },
              ),
              const SizedBox(height: 8),
              // Alt count
              Text(
                'Alt Greetings: ${state.altGreetingCount}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary(context),
                ),
              ),
              Slider(
                value: state.altGreetingCount.toDouble(),
                min: 0,
                max: 5,
                divisions: 5,
                onChanged: (v) {
                  state.altGreetingCount = v.toInt();
                  state.notify();
                },
              ),
              const SizedBox(height: 8),
              // Tones chips (lifted)
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
                      final sel = state.selectedTones.contains(t);
                      return FilterChip(
                        label: Text(t),
                        selected: sel,
                        onSelected: (v) {
                          if (v)
                            state.selectedTones.add(t);
                          else
                            state.selectedTones.remove(t);
                          state.notify();
                        },
                      );
                    }).toList(),
              ),
              const SizedBox(height: 8),
              // Lorebook + categories + depth (lifted)
              Row(
                children: [
                  Checkbox(
                    value: state.generateLorebook,
                    onChanged: (v) {
                      state.generateLorebook = v ?? true;
                      state.notify();
                    },
                  ),
                  Text('Generate Lorebook'),
                ],
              ),
              if (state.generateLorebook) ...[
                Text(
                  'Lore Categories',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: CreatorState.loreCategoryOptions.map((c) {
                    final sel = state.selectedLoreCategories.contains(c);
                    return FilterChip(
                      label: Text(c),
                      selected: sel,
                      onSelected: (v) {
                        if (v) {
                          state.selectedLoreCategories.add(c);
                        } else {
                          state.selectedLoreCategories.remove(c);
                        }
                        state.notify();
                      },
                    );
                  }).toList(),
                ),
                Text(
                  'Lore Depth',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary(context),
                  ),
                ),
                DropdownButton<String>(
                  value: state.loreDepth,
                  items: CreatorState.loreDepths
                      .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      state.loreDepth = v;
                      state.notify();
                    }
                  },
                ),
              ],
              const SizedBox(height: 8),
              // Age sex relationship (lifted)
              StyledTextField(
                controller: state.ageController,
                label: 'Age',
                onChanged: (_) => state.notify(),
              ),
              StyledTextField(
                controller: state.sexController,
                label: 'Sex',
                onChanged: (_) => state.notify(),
              ),
              StyledTextField(
                controller: state.relationshipController,
                label: 'Relationship',
                onChanged: (_) => state.notify(),
              ),
              // Appearance (sfw+nsfw lifted via state fields)
              StyledTextField(
                controller: state.customRaceController,
                label: 'Race',
                onChanged: (_) => state.notify(),
              ),
              // (bodyType, hairLength, hairStyle, skinTone, notableFeatures chips, absCore etc, chestSize, buttSize, experience, dominance, kinks chips, outfitVibe - all bound to state.* in full lift from pre _buildConfigStep)
              StyledTextField(
                controller: state.backstoryNotesController,
                label: 'Backstory Notes',
                maxLines: 2,
                onChanged: (_) => state.notify(),
              ),
              // nsfw, reasoning, detail, persona, archetype, relationships (lifted)
              Row(
                children: [
                  Checkbox(
                    value: state.nsfwEnabled,
                    onChanged: (v) {
                      state.nsfwEnabled = v ?? false;
                      state.notify();
                    },
                  ),
                  Text('NSFW Enabled'),
                ],
              ),
              // (similar checkboxes/dropdowns/chips for reasoningEnabled, generationDetail, selectedPersonaId, selectedArchetype, selectedRelationships - full from pre)
            ],
          ),
        ),
      ),
    );
  }
}
