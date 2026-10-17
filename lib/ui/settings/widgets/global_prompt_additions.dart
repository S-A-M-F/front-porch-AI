// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

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
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      title: const Text('Global prompt additions'),
      subtitle: const Text(
        'Extra instructions for every character and chat model.',
      ),
      children: [
        Text(
          'Saved automatically. Applied to future chat generations, including Continue and impersonation. Existing card instructions stay intact. Auxiliary evaluators and tools are unchanged. Clear a field to disable it.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 12),
        TextFormField(
          initialValue: settings.additionalSystemPrompt,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Additional system prompt',
            helperText:
                'Appended even when a character or group supplies its own system prompt.',
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
            helperText:
                'Appended in the post-history section. Supports {{char}} and {{user}}.',
            helperMaxLines: 3,
            border: OutlineInputBorder(),
          ),
          onChanged: (value) => _save(
            context,
            settings.setAdditionalPostHistoryInstructions(value),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
