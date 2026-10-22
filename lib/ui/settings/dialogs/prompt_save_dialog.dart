// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// Front Porch AI is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// Front Porch AI is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Asks for a name and saves [content] as a NEW saved prompt. A name already
/// in the user's pool is refused, so Save as new never overwrites; updating a
/// prompt is the slot's own Save. Calls [onSaved] with the name.
void showSavePromptDialog(
  BuildContext context,
  StorageService storageService, {
  required String content,
  void Function(String name)? onSaved,
}) {
  final controller = TextEditingController();
  final error = ValueNotifier<String?>(null);
  var done = false;
  void submit(BuildContext ctx) {
    final name = controller.text.trim();
    if (done || name.isEmpty) return;
    // Only names the user can see count: the hidden, untouched seed may be
    // replaced.
    final taken = userSavedPrompts(
      storageService.presetSettings.savedPrompts,
    ).any((p) => p['name'] == name);
    if (taken) {
      error.value =
          'You already have a prompt called "$name". Pick another name.';
      return;
    }
    done = true;
    storageService.presetSettings.savePrompt(name, content);
    onSaved?.call(name);
    Navigator.pop(ctx);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Prompt "$name" saved!')));
  }

  showWarmDialog<void>(
    context,
    title: 'Save as new prompt',
    icon: Icons.save_outlined,
    content: ValueListenableBuilder<String?>(
      valueListenable: error,
      builder: (ctx, message, _) => TextField(
        controller: controller,
        autofocus: true,
        style: TextStyle(color: AppColors.textPrimary(ctx)),
        decoration: InputDecoration(
          hintText: 'Prompt name...',
          hintStyle: TextStyle(color: AppColors.textTertiary(ctx)),
          errorText: message,
          errorMaxLines: 3,
        ),
        onChanged: (_) => error.value = null,
        onSubmitted: (_) => submit(ctx),
      ),
    ),
    actions: [
      Builder(
        builder: (ctx) => TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(
            'Cancel',
            style: TextStyle(color: AppColors.textSecondary(ctx)),
          ),
        ),
      ),
      Builder(
        builder: (ctx) => ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.formAccentOf(ctx),
            foregroundColor: AppColors.onAccentOf(ctx),
          ),
          onPressed: () => submit(ctx),
          child: const Text('Save'),
        ),
      ),
    ],
  );
}
