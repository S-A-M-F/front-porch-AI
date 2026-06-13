// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Mode selection card (lifted for quick/guided/automated per plan).
/// Honors AppColors, const where possible, composition.
class ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const ModeCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isSelected
        ? AppColors.resolve(
            context,
            AppColors.creatorSelectedCard,
            AppColors.creatorSelectedCardLight,
          )
        : AppColors.cardOf(context);
    final borderColor = isSelected
        ? AppColors.resolve(context, Colors.blueAccent, Colors.blue.shade700)
        : AppColors.borderOf(context);
    final titleColor = isSelected
        ? AppColors.textPrimary(context)
        : AppColors.textPrimary(context);
    final subColor = isSelected
        ? AppColors.textSecondary(context)
        : AppColors.textSecondary(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: isSelected ? 2 : 1),
        ),
        child: Row(
          children: [
            Icon(icon, size: 28, color: titleColor),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: titleColor,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: subColor),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check_circle,
                color: AppColors.resolve(
                  context,
                  Colors.white,
                  Colors.blue.shade700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
