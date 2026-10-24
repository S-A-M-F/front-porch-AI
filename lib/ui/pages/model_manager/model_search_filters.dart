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

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The search tab's filter row: sort order, Roleplay only, and a size
/// bucket. Wraps onto more lines in a narrow window.
class ModelSearchFilters extends StatelessWidget {
  const ModelSearchFilters({
    super.key,
    required this.options,
    required this.onChanged,
  });

  final HfSearchOptions options;
  final ValueChanged<HfSearchOptions> onChanged;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      color: AppColors.textSecondary(context),
      fontSize: 12,
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        PopupMenuButton<HfSort>(
          tooltip: 'Sort results',
          initialValue: options.sort,
          onSelected: (sort) => onChanged(options.copyWith(sort: sort)),
          itemBuilder: (_) => [
            for (final sort in HfSort.values)
              PopupMenuItem(value: sort, child: Text(sort.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.sort_rounded,
                  size: 16,
                  color: AppColors.iconSecondary(context),
                ),
                const SizedBox(width: 4),
                Text(options.sort.label, style: labelStyle),
                Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 18,
                  color: AppColors.iconSecondary(context),
                ),
              ],
            ),
          ),
        ),
        FilterChip(
          label: const Text('Roleplay only'),
          selected: options.roleplayOnly,
          onSelected: (on) => onChanged(options.copyWith(roleplayOnly: on)),
        ),
        for (final size in HfSizeBucket.values)
          ChoiceChip(
            label: Text(size.label),
            selected: options.size == size,
            onSelected: (_) => onChanged(options.copyWith(size: size)),
          ),
      ],
    );
  }
}
