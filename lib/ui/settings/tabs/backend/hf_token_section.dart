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
import 'package:front_porch_ai/services/storage/storage.dart';
import 'package:front_porch_ai/ui/settings/widgets/section_header.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Settings → Backend: the optional HuggingFace token the model downloader
/// sends to HuggingFace, so gated repos list and download. The saved token
/// is never shown again; the field only replaces or clears it.
class HfTokenSection extends StatefulWidget {
  const HfTokenSection({super.key});

  @override
  State<HfTokenSection> createState() => _HfTokenSectionState();
}

class _HfTokenSectionState extends State<HfTokenSection> {
  final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  /// Set before the first await, so a double click writes once.
  bool _saving = false;

  Future<void> _save(HfSettings settings, String value) async {
    if (_saving) return;
    _saving = true;
    try {
      await settings.setToken(value);
    } finally {
      _saving = false;
    }
    if (!mounted) return;
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<StorageService>().backendSettings.hf;
    final theme = Theme.of(context);
    return Column(
      key: const Key('hf-token-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        const SectionHeader('HuggingFace token'),
        const SizedBox(height: 8),
        Text(
          'Optional. Gated repos (official Llama and Gemma, some tunes) only '
          'list and download with a token. Create a read-only one under '
          'Settings → Access Tokens on huggingface.co, and accept the '
          "repo's licence there first.",
          style: TextStyle(
            fontSize: 13,
            height: 1.35,
            color: AppColors.textSecondary(context),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: TextField(
                controller: _field,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: settings.hasToken
                      ? '•••••• saved (paste to replace)'
                      : 'hf_…',
                  filled: true,
                  fillColor: theme.scaffoldBackgroundColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  isDense: true,
                  suffixIcon: const Icon(Icons.key, size: 18),
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) _save(settings, v);
                },
              ),
            ),
            ElevatedButton(
              onPressed: () {
                if (_field.text.trim().isNotEmpty) {
                  _save(settings, _field.text);
                }
              },
              child: const Text('Save token'),
            ),
            if (settings.hasToken)
              TextButton(
                onPressed: () => _save(settings, ''),
                child: const Text('Clear token'),
              ),
          ],
        ),
      ],
    );
  }
}
