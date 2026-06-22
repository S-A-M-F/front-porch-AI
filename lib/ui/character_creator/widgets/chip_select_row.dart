// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/character_creator/widgets/creator_pill.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// NSFW sections are always pink, regardless of the mode accent.
Color _nsfwPink(BuildContext context) =>
    AppColors.resolve(context, Colors.pinkAccent, const Color(0xFF9D174D));

Widget _chipRowLabel(BuildContext context, String label, Color accent, bool isNsfw) =>
    Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (isNsfw) ...[
            Icon(Icons.local_fire_department, size: 12, color: accent),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              color: isNsfw ? accent : AppColors.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );

/// A labelled row of single-select pills. Tapping the selected pill clears it
/// (passes '' to [onChanged]). Themed by [accent] (mode colour); NSFW → pink.
class SingleSelectChipRow extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final Color accent;
  final bool isNsfw;

  const SingleSelectChipRow({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    required this.accent,
    this.isNsfw = false,
  });

  @override
  Widget build(BuildContext context) {
    final pillAccent = isNsfw ? _nsfwPink(context) : accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRowLabel(context, label, pillAccent, isNsfw),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options
                .map(
                  (opt) => CreatorPill(
                    label: opt,
                    selected: value == opt,
                    accent: pillAccent,
                    icon: isNsfw ? Icons.local_fire_department : null,
                    onTap: () => onChanged(value == opt ? '' : opt),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

/// A labelled row of multi-select pills. Themed by [accent]; NSFW → pink.
class MultiSelectChipRow extends StatelessWidget {
  final String label;
  final Set<String> selected;
  final List<String> options;
  final ValueChanged<Set<String>> onChanged;
  final Color accent;
  final bool isNsfw;

  const MultiSelectChipRow({
    super.key,
    required this.label,
    required this.selected,
    required this.options,
    required this.onChanged,
    required this.accent,
    this.isNsfw = false,
  });

  @override
  Widget build(BuildContext context) {
    final pillAccent = isNsfw ? _nsfwPink(context) : accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRowLabel(context, label, pillAccent, isNsfw),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: options.map((opt) {
              final isSelected = selected.contains(opt);
              return CreatorPill(
                label: opt,
                selected: isSelected,
                accent: pillAccent,
                icon: isNsfw ? Icons.local_fire_department : null,
                onTap: () {
                  final next = Set<String>.from(selected);
                  if (isSelected) {
                    next.remove(opt);
                  } else {
                    next.add(opt);
                  }
                  onChanged(next);
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
