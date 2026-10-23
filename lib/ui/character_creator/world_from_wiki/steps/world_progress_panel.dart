// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The wizard's progress while it scouts or writes: a spinner, the line
/// for what it is doing now, the time the run has taken, and the lines
/// before it. The maintainer's ask: "it needs to give more details on what
/// it's doing" than a spinner that says "scouting".
class WorldProgressPanel extends StatelessWidget {
  const WorldProgressPanel({
    super.key,
    required this.state,
    required this.fallback,
  });

  final WorldFromWikiState state;

  /// The line shown before the engine has said anything.
  final String fallback;

  /// How many earlier lines the panel shows under the current one.
  static const int shown = 6;

  @override
  Widget build(BuildContext context) {
    final log = state.progress;
    final now = state.status.isEmpty ? fallback : state.status;
    final earlier = log.earlier.take(shown).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: StudioColors.amberOf(context),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                now,
                key: const Key('world-from-wiki-progress'),
                style: TextStyle(
                  color: StudioColors.inkOf(context),
                  height: 1.35,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              log.elapsedLabel,
              key: const Key('world-from-wiki-elapsed'),
              style: TextStyle(
                color: StudioColors.mutedOf(context),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        if (earlier.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(left: 30, top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in earlier)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      '${line.at}  ${line.text}',
                      style: TextStyle(
                        color: StudioColors.mutedOf(context),
                        fontSize: 12,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
