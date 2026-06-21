// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/lore_input_section.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/reasoning_toggle.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/alternate_greetings_slider.dart';
import 'package:front_porch_ai/ui/widgets/avatar_art_style_selector.dart';
import 'package:front_porch_ai/ui/widgets/greeting_tone_selector.dart';
import 'package:front_porch_ai/ui/widgets/nsfw_toggle.dart';

/// Quick Create config step — faithful restoration of the pre-refactor UI.
/// Name it, describe it, generate. Navigation/generation is owned by the
/// wizard shell (`character_creator_page.dart`); this step is pure form.
class QuickConfigStep extends StatelessWidget {
  final CreatorState state;

  const QuickConfigStep({super.key, required this.state});

  /// A field label, optionally with a helper sub-line beneath it.
  Widget _inputLabel(BuildContext context, String text, {String? helper}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          text,
          style: TextStyle(
            color: AppColors.textSecondary(context),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        if (helper != null) ...[
          const SizedBox(height: 4),
          Text(
            helper,
            style: TextStyle(
              color: AppColors.textTertiary(context),
              fontSize: 11,
            ),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  /// A decorated multi-line text field matching the original quick-form styling.
  Widget _textField(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required Color accent,
    int maxLines = 1,
    int? minLines,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(color: AppColors.textPrimary(context), fontSize: 14),
      maxLines: maxLines,
      minLines: minLines,
      onChanged: (_) => state.saveState(),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.textTertiary(context),
          fontSize: 12,
        ),
        filled: true,
        fillColor: AppColors.surfaceContainerOf(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.borderOf(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: accent, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quickAccent = AppColors.resolve(
      context,
      Colors.greenAccent,
      const Color(0xFF15803D),
    );
    final nsfwAccent = AppColors.resolve(
      context,
      Colors.pinkAccent,
      const Color(0xFF9D174D),
    );

    return Center(
      key: const ValueKey('quick-config'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: quickAccent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.bolt, color: quickAccent, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quick Create',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary(context),
                          ),
                        ),
                        Text(
                          'Name it, describe it, generate.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textTertiary(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),

              // Name field
              _inputLabel(context, 'Character Name'),
              _textField(
                context,
                controller: state.nameController,
                hint: 'Morgana, Kaito, Vex...',
                accent: quickAccent,
              ),
              const SizedBox(height: 24),

              // Concept field
              _inputLabel(
                context,
                'Describe them (optional)',
                helper:
                    'A sentence or two is plenty. Leave it blank and the AI will invent someone.',
              ),
              _textField(
                context,
                controller: state.conceptController,
                hint:
                    'A gruff dwarven blacksmith who secretly writes poetry...',
                accent: quickAccent,
                maxLines: 4,
                minLines: 3,
              ),
              const SizedBox(height: 24),

              // Scenario field
              _inputLabel(
                context,
                'Scenario / Setting (optional)',
                helper:
                    'Where does the story take place? What\'s the situation? The AI will build on this.',
              ),
              _textField(
                context,
                controller: state.quickScenarioController,
                hint:
                    'A modern coffee shop where they work as a barista, a fantasy guild hall, a space station...',
                accent: quickAccent,
                maxLines: 3,
                minLines: 2,
              ),
              const SizedBox(height: 24),

              // Art style
              _inputLabel(context, 'Avatar Art Style'),
              AvatarArtStyleSelector(
                selectedStyle: state.artStyle,
                accentColor: quickAccent,
                onChanged: (style) {
                  state.artStyle = style;
                  state.saveState();
                  state.notify();
                },
              ),
              const SizedBox(height: 24),

              // Greeting tones
              _inputLabel(context, 'Greeting Tone'),
              GreetingToneSelector(
                selectedTones: state.quickSelectedTones,
                greetingCount: state.quickGreetingCount,
                nsfwEnabled: state.quickNsfwEnabled,
                accentColor: quickAccent,
                onChanged: (tones) {
                  state.quickSelectedTones = tones;
                  state.saveState();
                  state.notify();
                },
              ),
              const SizedBox(height: 24),

              // Number of greetings
              _inputLabel(
                context,
                'Number of Greetings',
                helper:
                    'How many first messages to generate (1 main + alternates).',
              ),
              AlternateGreetingsSlider(
                value: state.quickGreetingCount,
                accentColor: quickAccent,
                formatLabel: (v) =>
                    v == 0 ? '1 greeting' : '1 + $v alt${v == 1 ? '' : 's'}',
                onChanged: (val) {
                  state.quickGreetingCount = val;
                  final maxTones = state.quickGreetingCount + 1;
                  while (state.quickSelectedTones.length > maxTones) {
                    state.quickSelectedTones.removeLast();
                  }
                  state.saveState();
                  state.notify();
                },
              ),
              const SizedBox(height: 24),

              // Lore input
              LoreInputSection(state: state, accentColor: quickAccent),
              const SizedBox(height: 28),

              // NSFW toggle
              NsfwToggle(
                value: state.quickNsfwEnabled,
                accentColor: nsfwAccent,
                title: 'NSFW Content',
                subtitle:
                    'Enables adult themes in personality, lorebook, and greetings',
                animated: true,
                onChanged: (v) {
                  state.quickNsfwEnabled = v;
                  state.saveState();
                  state.notify();
                },
              ),
              const SizedBox(height: 28),

              // Reasoning toggle
              ReasoningToggle(
                enabled: state.reasoningEnabled,
                accentColor: quickAccent,
                onChanged: (v) {
                  state.reasoningEnabled = v;
                  state.saveState();
                  state.notify();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
