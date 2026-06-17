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
// but WITHOUT ANY WARRANTY, without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/image_prompt/image_prompt_builder.dart';
import 'package:front_porch_ai/services/image_gen_service.dart'
    show ImageGenService;
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Rich style + paradigm selector with *live* exact suffix preview (per spec).
/// Richer than old simple chips: shows what will be enforced.
class StylePreview extends StatelessWidget {
  final String selectedStyle;
  final String paradigm;
  final ImagePromptBuilder builder;
  final ValueChanged<String>? onStyleChanged;
  final ValueChanged<String>? onParadigmChanged;

  const StylePreview({
    super.key,
    required this.selectedStyle,
    required this.paradigm,
    required this.builder,
    this.onStyleChanged,
    this.onParadigmChanged,
  });

  @override
  Widget build(BuildContext context) {
    final suffix = builder.getStyleSuffix(selectedStyle, paradigm);
    final note = builder.getStylePreviewNote(selectedStyle, paradigm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Style',
              style: TextStyle(
                color: AppColors.textSecondary(context),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            // Simple paradigm indicator (global, shown for transparency)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerOf(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                paradigm == 'tags' ? 'Tags (danbooru)' : 'Natural language',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textTertiary(context),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: ImageGenService.styleLabels.entries.map((entry) {
            final isSel = selectedStyle == entry.key;
            return ChoiceChip(
              label: Text(
                entry.value,
                style: TextStyle(
                  fontSize: 12,
                  color: isSel
                      ? AppColors.textPrimary(context)
                      : AppColors.textSecondary(context),
                ),
              ),
              selected: isSel,
              onSelected: onStyleChanged == null
                  ? null
                  : (s) {
                      if (s) onStyleChanged!(entry.key);
                    },
              selectedColor: AppColors.resolve(
                context,
                AppColors.creatorSelectedCard,
                AppColors.creatorSelectedCardLight,
              ),
              backgroundColor: AppColors.surfaceContainerOf(context),
              side: BorderSide(
                color: isSel
                    ? AppColors.resolve(
                        context,
                        AppColors.formMasterAccent,
                        AppColors.formMasterAccent,
                      )
                    : AppColors.borderOf(context),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        // Live enforced suffix preview (the heart of pre-gen transparency)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enforced style suffix (live)',
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                suffix.isEmpty ? '(no suffix for this style)' : suffix,
                style: TextStyle(
                  color: AppColors.textPrimary(context),
                  fontSize: 12,
                  fontStyle: suffix.isEmpty
                      ? FontStyle.italic
                      : FontStyle.normal,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                note,
                style: TextStyle(
                  color: AppColors.textTertiary(context),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
