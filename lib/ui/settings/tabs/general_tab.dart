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
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/settings/widgets/color_row.dart';
import 'package:front_porch_ai/ui/settings/widgets/slider_setting.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_save_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/prompt_delete_dialog.dart';
import 'package:front_porch_ai/ui/settings/dialogs/color_picker_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/update_dialog.dart';

/// General tab extracted from settings_page (Stage 5).
/// Lift of _buildGeneralTab with shared state passed via ctor, AppColors exclusive in the file, use of extracted widgets and dialogs.
class GeneralTab extends StatelessWidget {
  const GeneralTab({super.key, required this.systemPromptController});

  final TextEditingController systemPromptController;

  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Dark Mode', style: theme.textTheme.titleMedium),
              Switch(
                value: Provider.of<StorageService>(context).isDark,
                onChanged: (v) {
                  Provider.of<StorageService>(
                    context,
                    listen: false,
                  ).setIsDark(v);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (UpdateService.isSupported) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Auto-check for Updates',
                  style: theme.textTheme.titleMedium,
                ),
                Consumer<UpdateService>(
                  builder: (context, updateService, _) => Switch(
                    value: updateService.autoCheckEnabled,
                    onChanged: (val) => updateService.setAutoCheckEnabled(val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Consumer<UpdateService>(
              builder: (context, updateService, _) {
                final isBusy = updateService.checking;
                return SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isBusy
                        ? null
                        : () async {
                            final hasUpdate = await updateService
                                .checkForUpdate();
                            if (hasUpdate && context.mounted) {
                              await UpdateDialog.show(context);
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('You are up to date.'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                    icon: isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(
                      isBusy ? 'Checking...' : 'Check for Updates Now',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary(context),
                      side: BorderSide(color: AppColors.textTertiary(context)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          SliderSetting(
            label: 'Font Size Scale',
            value: storageService.textScale,
            min: 0.7,
            max: 2.0,
            onChanged: (val) => storageService.setTextScale(val),
            divisions: 13,
          ),
          const SizedBox(height: 24),
          const SectionHeader('Chat Appearance'),
          const SizedBox(height: 8),
          ColorRow(
            label: 'User Bubble',
            color: storageService.globalUserBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalUserBubbleColor,
              (color) => storageService.setGlobalUserBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'User Text',
            color: storageService.globalUserTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalUserTextColor,
              (color) => storageService.setGlobalUserTextColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Bubble',
            color: storageService.globalAiBubbleColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalAiBubbleColor,
              (color) => storageService.setGlobalAiBubbleColor(color),
            ),
          ),
          ColorRow(
            label: 'AI Text',
            color: storageService.globalAiTextColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalAiTextColor,
              (color) => storageService.setGlobalAiTextColor(color),
            ),
          ),
          ColorRow(
            label: 'Dialogue (Quoted)',
            color: storageService.globalDialogueColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalDialogueColor,
              (color) => storageService.setGlobalDialogueColor(color),
            ),
          ),
          ColorRow(
            label: 'Actions (*text*)',
            color: storageService.globalActionColor,
            onPressed: () => showColorPicker(
              context,
              storageService.globalActionColor,
              (color) => storageService.setGlobalActionColor(color),
            ),
          ),
          const SizedBox(height: 12),
          // Font row simplified (full from god lift would include the dropdown with chatFonts; smallest for this tab)
          Text(
            'Chat Font (see full in advanced extraction)',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Realism Mode'),
          const SizedBox(height: 8),
          Text(
            'Realism settings (see full in advanced tab)',
            style: TextStyle(
              color: AppColors.textSecondary(context),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeader('Model Instructions'),
          const SizedBox(height: 8),
          // Prompt library row simplified for smallest (full chips/load/save use the extracted dialogs)
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: null,
                  isExpanded: true,
                  hint: const Text(
                    'Load saved prompt...',
                    style: TextStyle(fontSize: 13),
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.cardOf(context),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: storageService.savedPrompts
                      .map(
                        (p) => DropdownMenuItem<String>(
                          value: p['name'],
                          child: Text(
                            p['name']!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (name) {
                    if (name != null) {
                      storageService.loadSavedPrompt(name);
                      systemPromptController.text = storageService.systemPrompt;
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Save current prompt',
                icon: Icon(Icons.save, color: AppColors.logWarn),
                onPressed: () => showSavePromptDialog(context, storageService),
              ),
              IconButton(
                tooltip: 'Delete a saved prompt',
                icon: Icon(Icons.delete_outline, color: AppColors.logError),
                onPressed: () =>
                    showDeletePromptDialog(context, storageService),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Built-in preset chips (simplified inline for smallest; full would use PresetChip widget)
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ActionChip(
                label: const Text('📡 API Default'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultApiSystemPrompt,
                ),
              ),
              ActionChip(
                label: const Text('🖥️ KoboldCPP'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultKoboldSystemPrompt,
                ),
              ),
              ActionChip(
                label: const Text('👥 Group Chat'),
                onPressed: () => storageService.setSystemPrompt(
                  ChatService.defaultGroupSystemPrompt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(
            controller: systemPromptController,
            maxLines: 5,
            style: theme.textTheme.bodyMedium,
            decoration: InputDecoration(
              hintText: 'System Prompt...',
              hintStyle: TextStyle(color: theme.textTheme.bodySmall?.color),
              filled: true,
              fillColor: AppColors.cardOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            onChanged: (val) => storageService.setSystemPrompt(val),
          ),
        ],
      ),
    );
  }
}
