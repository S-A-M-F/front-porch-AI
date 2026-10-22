// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

import 'section_header.dart';

/// Settings → General: the base prompt every group chat uses. Blank keeps
/// the built-in group prompt; a group's own prompt (Group Settings) wins.
/// Director Mode's rules are added on top either way.
class GroupSystemPromptField extends StatefulWidget {
  const GroupSystemPromptField({super.key});

  @override
  State<GroupSystemPromptField> createState() => _GroupSystemPromptFieldState();
}

class _GroupSystemPromptFieldState extends State<GroupSystemPromptField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<StorageService>().generationSettings.groupSystemPrompt,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save(String value) async {
    try {
      await context
          .read<StorageService>()
          .generationSettings
          .setGroupSystemPrompt(value);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save the group prompt: $error')),
      );
    }
  }

  void _startFromBuiltIn() {
    _controller.text = defaultGroupSystemPrompt;
    _save(defaultGroupSystemPrompt);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Group system prompt'),
        const SizedBox(height: 8),
        Text(
          'Sets the writing style for every group chat, unless that group '
          'has its own prompt in Group Settings. Leave blank for the '
          'built-in style. Front Porch adds its own turn rules, and Director '
          'Mode\'s, on top either way.',
          style: TextStyle(color: AppColors.textSecondary(context)),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 2,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Group system prompt',
            hintText: 'Blank uses the built-in group prompt',
            border: OutlineInputBorder(),
          ),
          onChanged: _save,
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _startFromBuiltIn,
            child: const Text('Start from the built-in prompt'),
          ),
        ),
      ],
    );
  }
}
