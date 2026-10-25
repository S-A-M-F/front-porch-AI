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

import 'package:front_porch_ai/services/kobold/kobold.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';

/// The warning box beside a flash attention switch for a pairing that
/// crashed KoboldCpp in testing (see `koboldFlashAttentionRisky`): it may be
/// turned on, but the user is told first.
class FlashAttentionCrashWarning extends StatelessWidget {
  const FlashAttentionCrashWarning({super.key});

  @override
  Widget build(BuildContext context) {
    final warn = StatusColors.warningOf(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: StatusColors.warningWashOf(context, 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: warn.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: warn, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              kKoboldFlashAttentionCrashWarning,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: warn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
