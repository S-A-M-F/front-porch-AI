// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The wizard's five steps as dots joined by a line: done ones filled
/// amber with a tick, the current one ringed, the rest outlined. Its own
/// widget so the creator's indicator keeps its look.
class WorldStepIndicator extends StatelessWidget {
  const WorldStepIndicator({
    super.key,
    required this.labels,
    required this.current,
  });

  final List<String> labels;
  final int current;

  @override
  Widget build(BuildContext context) {
    final amber = StudioColors.amberOf(context);
    final line = StudioColors.lineOf(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(top: 13),
              child: Container(
                width: 24,
                height: 2,
                color: i <= current ? amber : line,
              ),
            ),
          SizedBox(
            width: 64,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(context, i),
                const SizedBox(height: 4),
                Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: i == current
                        ? FontWeight.w700
                        : FontWeight.w400,
                    color: i == current
                        ? StudioColors.inkOf(context)
                        : StudioColors.mutedOf(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _dot(BuildContext context, int i) {
    final amber = StudioColors.amberOf(context);
    final done = i < current;
    final now = i == current;
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: done || now ? amber : StudioColors.raiseOf(context),
        border: done || now
            ? null
            : Border.all(color: StudioColors.lineOf(context), width: 2),
        boxShadow: now
            ? [BoxShadow(color: amber.withValues(alpha: 0.22), spreadRadius: 4)]
            : null,
      ),
      child: Center(
        child: done
            ? Icon(Icons.check, size: 16, color: StudioColors.bgOf(context))
            : Text(
                '${i + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: now
                      ? StudioColors.bgOf(context)
                      : StudioColors.mutedOf(context),
                ),
              ),
      ),
    );
  }
}
