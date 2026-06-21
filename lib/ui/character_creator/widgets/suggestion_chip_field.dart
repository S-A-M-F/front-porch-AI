// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_pill.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A labelled multiline text field with tap-to-toggle suggestion pills, used by
/// the Guided creator. Shares the [CreatorPill] look with every other mode;
/// themed by [accent] (NSFW fields override to pink). [onChanged] fires on edits
/// and pill taps so the caller can rebuild + persist.
class SuggestionChipField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final List<String> suggestions;
  final int maxLines;
  final int minLines;
  final bool isNsfw;
  final Widget? trailing;
  final Color accent;
  final VoidCallback onChanged;

  const SuggestionChipField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.accent,
    required this.onChanged,
    this.suggestions = const [],
    this.maxLines = 2,
    this.minLines = 1,
    this.isNsfw = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final pillAccent = isNsfw
        ? AppColors.resolve(context, Colors.pinkAccent, const Color(0xFF9D174D))
        : accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNsfw) ...[
                Icon(
                  Icons.local_fire_department,
                  size: 12,
                  color: pillAccent,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isNsfw ? pillAccent : AppColors.textSecondary(context),
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            maxLines: maxLines,
            minLines: minLines,
            style: TextStyle(
              color: AppColors.textPrimary(context),
              fontSize: 13,
            ),
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(
                color: AppColors.textTertiary(context),
                fontSize: 12,
              ),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.borderOf(context)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: pillAccent, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: suggestions.map((sug) {
                // Field is treated as comma-separated tokens so a pill toggles
                // both on AND off; free text the user typed is preserved.
                List<String> tokens() => controller.text
                    .split(',')
                    .map((e) => e.trim())
                    .where((e) => e.isNotEmpty)
                    .toList();
                final isInField = tokens().any(
                  (t) => t.toLowerCase() == sug.toLowerCase(),
                );
                return CreatorPill(
                  label: sug,
                  selected: isInField,
                  accent: pillAccent,
                  onTap: () {
                    final parts = tokens();
                    if (isInField) {
                      parts.removeWhere(
                        (t) => t.toLowerCase() == sug.toLowerCase(),
                      );
                    } else {
                      parts.add(sug);
                    }
                    controller.text = parts.join(', ');
                    controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: controller.text.length),
                    );
                    onChanged();
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
