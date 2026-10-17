// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'section_header.dart';

/// Settings → General → the block under the Fallback system prompt.
///
/// Flat on purpose (prompt-picker SOW Phase 0): it would be the only
/// accordion in Settings, and the additions belong beside the base prompt
/// they extend, not behind a tap.
class GlobalPromptAdditions extends StatelessWidget {
  const GlobalPromptAdditions({super.key});

  Future<void> _save(BuildContext context, Future<void> action) async {
    try {
      await action;
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save prompt addition: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().generationSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Global prompt additions'),
        const SizedBox(height: 8),
        Text(
          'Saved automatically. Leave blank to disable. Both fields support {{char}} and {{user}}.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: settings.additionalSystemPrompt,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Additional system instructions',
            helperText: 'Appended to the selected system prompt, including character and group prompts.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) =>
              _save(context, settings.setAdditionalSystemPrompt(value)),
        ),
        const SizedBox(height: 16),
        TextFormField(
          initialValue: settings.additionalPostHistoryInstructions,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Additional post-history instructions',
            helperText: 'Appended after existing post-history instructions.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _save(
            context,
            settings.setAdditionalPostHistoryInstructions(value),
          ),
        ),
      ],
    );
  }
}
