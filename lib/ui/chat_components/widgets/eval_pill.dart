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

/// Data holder for eval pill (extracted).
class EvalPill {
  final String label;
  final IconData icon;
  final Color color;
  const EvalPill({
    required this.label,
    required this.icon,
    required this.color,
  });
}

/// Animated eval pill used in realism / objective overlays (extracted).
class AnimatedEvalPill extends StatelessWidget {
  final EvalPill pill;
  final Animation<double> pulseAnimation;

  const AnimatedEvalPill({required this.pill, required this.pulseAnimation});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (_, _) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: pill.color.withValues(
            alpha: 0.07 + 0.04 * pulseAnimation.value,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: pill.color.withValues(
              alpha: 0.2 + 0.1 * pulseAnimation.value,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pill.icon,
              size: 12,
              color: pill.color.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 5),
            Text(
              pill.label,
              style: TextStyle(
                fontSize: 11,
                color: pill.color.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
