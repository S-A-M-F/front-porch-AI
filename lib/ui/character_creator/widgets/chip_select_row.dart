// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Shared accent resolver for creator chip rows: blue for SFW, pink for NSFW.
Color _chipAccent(BuildContext context, bool isNsfw) => isNsfw
    ? AppColors.resolve(context, Colors.pinkAccent, const Color(0xFF9D174D))
    : AppColors.resolve(context, Colors.blueAccent, const Color(0xFF1E40AF));

Color _chipLabelAccent(BuildContext context, bool isNsfw) => isNsfw
    ? AppColors.resolve(context, Colors.pinkAccent, const Color(0xFF9D174D))
    : AppColors.resolve(context, Colors.blueAccent, const Color(0xFF1E40AF));

Widget _chipRowLabel(BuildContext context, String label, bool isNsfw) => Row(
  children: [
    if (isNsfw) ...[
      Icon(
        Icons.local_fire_department,
        size: 12,
        color: _chipAccent(context, isNsfw),
      ),
      const SizedBox(width: 4),
    ],
    Text(
      label,
      style: TextStyle(
        color: isNsfw
            ? _chipLabelAccent(context, isNsfw)
            : AppColors.textSecondary(context),
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  ],
);

/// A labelled row of single-select choice chips. Tapping the selected chip
/// clears it (passes '' to [onChanged]). Restored from the god file's
/// `_singleSelectChipRow`.
class SingleSelectChipRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final bool isNsfw;

  const SingleSelectChipRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.isNsfw = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _chipAccent(context, isNsfw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRowLabel(context, label, isNsfw),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = value == opt;
              return ChoiceChip(
                label: Text(opt, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (_) => onChanged(isSelected ? '' : opt),
                selectedColor: AppColors.resolve(
                  context,
                  accent.withValues(alpha: 0.25),
                  accent.withValues(alpha: 0.12),
                ),
                backgroundColor: AppColors.surfaceContainerOf(context),
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppColors.resolve(context, Colors.white, Colors.black87)
                      : AppColors.textSecondary(context),
                ),
                side: BorderSide(
                  color: isSelected ? accent : AppColors.borderOf(context),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

/// A labelled row of multi-select filter chips. Restored from the god file's
/// `_multiSelectChipRow`.
class MultiSelectChipRow extends StatelessWidget {
  final String label;
  final Set<String> selected;
  final List<String> options;
  final ValueChanged<Set<String>> onChanged;
  final bool isNsfw;

  const MultiSelectChipRow({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    this.isNsfw = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = _chipAccent(context, isNsfw);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRowLabel(context, label, isNsfw),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return FilterChip(
                label: Text(opt, style: const TextStyle(fontSize: 11)),
                selected: isSelected,
                onSelected: (val) {
                  final next = Set<String>.from(selected);
                  if (val) {
                    next.add(opt);
                  } else {
                    next.remove(opt);
                  }
                  onChanged(next);
                },
                selectedColor: AppColors.resolve(
                  context,
                  accent.withValues(alpha: 0.25),
                  accent.withValues(alpha: 0.12),
                ),
                backgroundColor: AppColors.surfaceContainerOf(context),
                checkmarkColor: accent,
                labelStyle: TextStyle(
                  color: isSelected
                      ? AppColors.resolve(context, Colors.white, Colors.black87)
                      : AppColors.textTertiary(context),
                ),
                side: BorderSide(
                  color: isSelected ? accent : AppColors.borderOf(context),
                ),
                visualDensity: VisualDensity.compact,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
