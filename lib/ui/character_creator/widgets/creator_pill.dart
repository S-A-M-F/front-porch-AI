// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// The single, shared "bubble" used across every character-creation mode
/// (Quick / Guided / Automated). One look, themed per mode by [accent] — so
/// the modes feel like one polished family but are visually distinguishable.
///
/// Light/dark safe: unselected uses surfaceContainer + a real border; selected
/// uses an accent tint + accent border + accent label (which resolve to deep
/// colours in light mode), so it never blinds and always reads.
class CreatorPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;
  final IconData? icon;

  const CreatorPill({
    super.key,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? accent : AppColors.textSecondary(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.16)
                : AppColors.surfaceContainerOf(context),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected
                  ? accent
                  : AppColors.borderOf(context).withValues(alpha: 0.9),
              width: selected ? 1.5 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.25),
                      blurRadius: 8,
                      spreadRadius: -2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
