// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// A labelled multiline text field with tap-to-append suggestion chips, used by
/// the Guided creator. Restored from the god file's `_guidedField`. Pure
/// presentation: [onChanged] fires on edits and chip taps so the caller can
/// rebuild + persist.
class SuggestionChipField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final List<String> suggestions;
  final int maxLines;
  final int minLines;
  final bool isNsfw;
  final Widget? trailing;
  final VoidCallback onChanged;

  const SuggestionChipField({
    super.key,
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.suggestions = const [],
    this.maxLines = 2,
    this.minLines = 1,
    this.isNsfw = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isNsfw ? Colors.pinkAccent : Colors.tealAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isNsfw) ...[
                const Icon(
                  Icons.local_fire_department,
                  size: 12,
                  color: Colors.pinkAccent,
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isNsfw
                        ? Colors.pinkAccent
                        : AppColors.textSecondary(context),
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
                borderSide: BorderSide(color: accent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: suggestions.map((sug) {
                final isInField = controller.text.toLowerCase().contains(
                  sug.toLowerCase(),
                );
                return InkWell(
                  onTap: () {
                    if (!isInField) {
                      final current = controller.text.trim();
                      controller.text = current.isEmpty
                          ? sug
                          : '$current, $sug';
                      controller.selection = TextSelection.fromPosition(
                        TextPosition(offset: controller.text.length),
                      );
                      onChanged();
                    }
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isInField
                          ? accent.withValues(alpha: 0.2)
                          : AppColors.surfaceContainerOf(context),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isInField
                            ? accent.withValues(alpha: 0.5)
                            : AppColors.borderOf(context),
                      ),
                    ),
                    child: Text(
                      sug,
                      style: TextStyle(
                        color: isInField
                            ? accent
                            : AppColors.textTertiary(context),
                        fontSize: 11,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
