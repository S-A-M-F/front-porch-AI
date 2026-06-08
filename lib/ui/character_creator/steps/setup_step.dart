// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/ui/character_creator/creator_state.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/backend_chip.dart';
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
                          // scan would be called via state if wired
                          // state.scanLocalModels(...); but service passed from caller in full
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
                          // state.loadAvailableModels(llmProvider);
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Model selection (full lift from pre-extraction _buildSetupStep, bound to state, using passed services in onTap via Provider for fidelity)
              if (isKobold) ...[
                _inputLabel(context, 'Local Model (.gguf)', required: false),
                const SizedBox(height: 8),
                // List of local .gguf (lifted)
                if (state.localModels.isNotEmpty)
                  ...state.localModels.map((f) {
                    final path = f.path;
                    final isSel = state.selectedLocalModelPath == path;
                    return ListTile(
                      title: Text(
                        p.basename(path),
                        style: TextStyle(color: AppColors.textPrimary(context)),
                      ),
                      selected: isSel,
                      onTap: () {
                        state.selectedLocalModelPath = path;
                        state.notify();
                      },
                    );
                  })
                else
                  Text(
                    'No local models found. Scan or place .gguf in models dir.',
                    style: TextStyle(color: AppColors.textTertiary(context)),
                  ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: () {
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
              ] else ...[
                _inputLabel(context, 'Remote Model', required: false),
                const SizedBox(height: 8),
                if (state.availableModels.isNotEmpty)
                  ...state.availableModels.map((m) {
                    final isSel = state.selectedModelId == m;
                    return ListTile(
                      title: Text(
                        m.toString(),
                        style: TextStyle(color: AppColors.textPrimary(context)),
                      ),
                      selected: isSel,
                      onTap: () {
                        state.selectedModelId = m.toString();
                        state.notify();
                      },
                    );
                  })
                else
                  Text(
                    'No remote models loaded. Select API backend and load.',
                    style: TextStyle(color: AppColors.textTertiary(context)),
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
}
