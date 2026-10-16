// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/app_colors.dart';

/// Re-reads a Change sheet's list from the connected app. Shows a small
/// spinner while it reads and ignores taps until it is done.
class StudioRefreshButton extends StatelessWidget {
  const StudioRefreshButton({
    super.key,
    required this.refreshing,
    required this.onPressed,
  });

  final bool refreshing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Refresh list',
      onPressed: refreshing ? null : onPressed,
      icon: refreshing
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.refresh, color: AppColors.iconSecondary(context)),
    );
  }
}
