// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/open_router_service.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/backend_chip.dart';
import 'package:front_porch_ai/ui/settings/dialogs/model_search_dialog.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Step 0: Backend & Model setup (lifted pure from _buildSetupStep).
class SetupStep extends StatelessWidget {
  final CreatorState state;

  const SetupStep({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final llmProvider = Provider.of<LLMProvider>(context, listen: false);
    final activeBackend = llmProvider.activeBackend;
    final isKobold = activeBackend == BackendType.kobold;
    final isAppleSiliconMac = _isAppleSiliconMac();

    return Center(
      key: const ValueKey('setup'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Backend & Model Setup',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose your AI backend and model before configuring your character.',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.textSecondary(context),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),

              // Backend toggle (uses extracted BackendChip)
              _inputLabel(context, 'Backend', required: false),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: BackendChip(
                      label: 'KoboldCpp (Local)',
                      icon: Icons.computer,
                      isSelected: isKobold,
                      onTap: () async {
                        if (!isKobold) {
                          await llmProvider.setActiveBackend(
                            BackendType.kobold,
                          );
                          // Trigger scan (was never wired) + notify so Kobold model list appears
                          // and the conditional picker UI switches. This was the root of the
                          // "KoboldCpp model picker completely broken" bug.
                          final storage = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          state.scanLocalModels(storage);
                          state.notify();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BackendChip(
                      label: 'Pseudo-Remote',
                      icon: Icons.laptop,
                      isSelected: activeBackend == BackendType.pseudoRemote,
                      onTap: () async {
                        if (activeBackend != BackendType.pseudoRemote) {
                          await llmProvider.setActiveBackend(
                            BackendType.pseudoRemote,
                          );
                          state.notify(); // ensure section switches in wizard UI
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: BackendChip(
                      label: 'API (Remote)',
                      icon: Icons.cloud,
                      isSelected: activeBackend == BackendType.openRouter,
                      onTap: () async {
                        if (activeBackend != BackendType.openRouter) {
                          await llmProvider.setActiveBackend(
                            BackendType.openRouter,
                          );
                          state.loadAvailableModels(llmProvider);
                        }
                      },
                    ),
                  ),
                  if (isAppleSiliconMac) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: BackendChip(
                        label: 'oMLX',
                        icon: Icons.apple,
                        isSelected: activeBackend == BackendType.omlx,
                        onTap: () async {
                          if (activeBackend != BackendType.omlx) {
                            await llmProvider.setActiveBackend(
                              BackendType.omlx,
                            );
                            // Ensure oMLX URL is configured before loading models
                            llmProvider.openRouterService.configure(
                              apiUrl: 'http://localhost:8000/v1',
                              apiKey: llmProvider.openRouterService.apiKey,
                              modelName: llmProvider.openRouterService.modelName,
                            );
                            // Small delay to ensure configuration is applied
                            await Future.delayed(const Duration(milliseconds: 100));
                            state.loadAvailableModels(llmProvider);
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 24),

              // Model selection — both Kobold (local) and remote/oMLX now use the *exact same*
              // tappable selector field + searchable dialog (the one the user liked for API/oMLX).
              // This reuses the existing model picker UX for local .gguf files too.
              if (isKobold) ...[
                _inputLabel(context, 'Local Model (.gguf)', required: false),
                const SizedBox(height: 8),
                // Identical styled picker field as remote/oMLX
                InkWell(
                  onTap: () async {
                    final storage = Provider.of<StorageService>(context, listen: false);
                    state.scanLocalModels(storage);
                    final modelManager = Provider.of<ModelManager>(context, listen: false);
                    await modelManager.refreshModels();

                    final models = modelManager.models.isNotEmpty
                        ? modelManager.models
                        : state.localModels;

                    if (context.mounted) {
                      // Always open the searchable picker (even if currently empty) so the user
                      // sees the familiar search UI and can understand the state.
                      showGenericModelSearchDialog<FileSystemEntity>(
                        context,
                        models,
                        title: 'Select Local Model',
                        getTitle: (f) => p.basename(f.path),
                        getSubtitle: (f) => f.path,
                        onSelected: (f) {
                          state.selectedLocalModelPath = f.path;
                          storage.setLastUsedModelPath(f.path);
                          state.notify();
                        },
                      );
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Model',
                                style: TextStyle(
                                  color: AppColors.textTertiary(context),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.selectedLocalModelPath.isEmpty
                                    ? 'Tap to select a model...'
                                    : p.basename(state.selectedLocalModelPath),
                                style: TextStyle(
                                  color: state.selectedLocalModelPath.isEmpty
                                      ? AppColors.textTertiary(context)
                                      : AppColors.textPrimary(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.iconSecondary(context),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: state.selectedLocalModelPath.isEmpty
                      ? null
                      : () {
                          final llm = Provider.of<LLMProvider>(
                            context,
                            listen: false,
                          );
                          final storage = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          state.reloadKoboldWithModel(
                            state.selectedLocalModelPath,
                            llm,
                            storage,
                          );
                        },
                  child: const Text('Reload Kobold with selected model'),
                ),
                if (state.koboldStatus.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    state.koboldStatus,
                    style: TextStyle(
                      fontSize: 12,
                      color: state.koboldStatus.toLowerCase().contains('error')
                          ? Colors.redAccent
                          : AppColors.textSecondary(context),
                    ),
                  ),
                ],
              ] else ...[
                // Restored the original nice searchable model picker for API (remote) and oMLX.
                _inputLabel(
                  context,
                  activeBackend == BackendType.omlx ? 'oMLX Model' : 'Remote Model',
                  required: false,
                ),
                const SizedBox(height: 8),
                // Tappable chip/field that opens the searchable model picker dialog (same as before)
                InkWell(
                  onTap: () async {
                    final llm = Provider.of<LLMProvider>(context, listen: false);
                    final storage = Provider.of<StorageService>(context, listen: false);

                    // Fetch models first if none loaded
                    if (state.availableModels.isEmpty) {
                      await state.loadAvailableModels(llm);
                    }

                    // Show the (searchable) model picker dialog
                    if (context.mounted && state.availableModels.isNotEmpty) {
                      showModelSearchDialog(
                        context,
                        storage,
                        state.availableModels.cast<RemoteModelInfo>(),
                      );
                      // Sync creator display state after user picks (dialog writes storage directly).
                      Future.delayed(const Duration(milliseconds: 350), () {
                        if (context.mounted) {
                          final s = Provider.of<StorageService>(
                            context,
                            listen: false,
                          );
                          if (s.remoteModelName.isNotEmpty) {
                            state.selectedModelId = s.remoteModelName;
                            state.notify();
                          }
                        }
                      });
                    }
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: AppColors.borderOf(context),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Model',
                                style: TextStyle(
                                  color: AppColors.textTertiary(context),
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                state.selectedModelId.isEmpty
                                    ? 'Tap to select a model...'
                                    : state.selectedModelId,
                                style: TextStyle(
                                  color: state.selectedModelId.isEmpty
                                      ? AppColors.textTertiary(context)
                                      : AppColors.textPrimary(context),
                                  fontSize: 14,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_drop_down,
                          color: AppColors.iconSecondary(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              Text(
                'The selected backend and model will be used for all AI generation in this wizard.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputLabel(
    BuildContext context,
    String text, {
    bool required = false,
  }) {
    return Row(
      children: [
        Text(
          text,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary(context),
            fontWeight: FontWeight.w500,
          ),
        ),
        if (required)
          Text(
            ' *',
            style: TextStyle(
              color: AppColors.resolve(
                context,
                Colors.redAccent,
                Colors.red.shade700,
              ),
            ),
          ),
      ],
    );
  }

  /// Check if running on Apple Silicon Mac (arm64 architecture).
  bool _isAppleSiliconMac() {
    if (!Platform.isMacOS) return false;
    // Try to detect arm64 architecture
    try {
      final result = Process.runSync('uname', ['-m']);
      if (result.exitCode == 0) {
        return result.stdout.toString().trim() == 'arm64';
      }
    } catch (_) {}
    // Fallback: if uname fails, assume it's not Apple Silicon
    return false;
  }

}
