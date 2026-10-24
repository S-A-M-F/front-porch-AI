// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/material.dart';

import 'package:front_porch_ai/ui/character_creator/world_from_wiki/world_from_wiki_state.dart';
import 'package:front_porch_ai/ui/theme/studio_colors.dart';

/// The wizard's progress while it scouts, writes or reviews: one amber
/// card with the spinner, the line for what it is doing now, the run's
/// total time and, once a step has been waited on a while, that step's
/// own timer; a slow sweep bar; the stages as chips with the current one
/// lit; and Stop. No history under it (the maintainer's ask).
class WorldProgressPanel extends StatelessWidget {
  const WorldProgressPanel({
    super.key,
    required this.state,
    required this.fallback,
    this.subtitle = '',
    this.stages = const [],
    this.stage = 0,
    this.onStop,
  });

  final WorldFromWikiState state;

  /// The line shown before the engine has said anything.
  final String fallback;

  /// A muted line under the current one: what kind of work this is.
  final String subtitle;

  /// The run's stages, as chips; empty hides the row.
  final List<String> stages;

  /// Which of [stages] is lit (0-based).
  final int stage;

  /// Stop, when the run can be stopped from here.
  final VoidCallback? onStop;

  /// A step waited on this long shows its own timer beside the total.
  static const Duration stepTimerAfter = Duration(seconds: 15);

  @override
  Widget build(BuildContext context) {
    final log = state.progress;
    final now = state.status.isEmpty ? fallback : state.status;
    final onStep = log.onStep >= stepTimerAfter ? log.onStepLabel : '';
    final amber = StudioColors.amberOf(context);
    final ink = StudioColors.inkOf(context);
    final muted = StudioColors.mutedOf(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      decoration: BoxDecoration(
        color: StudioColors.cardOf(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: amber, width: 1.5),
        boxShadow: [
          BoxShadow(color: amber.withValues(alpha: 0.08), spreadRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: amber,
                  backgroundColor: StudioColors.lineOf(context),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      now,
                      key: const Key('world-from-wiki-progress'),
                      style: TextStyle(
                        color: ink,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: muted, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    log.elapsedLabel,
                    key: const Key('world-from-wiki-elapsed'),
                    style: TextStyle(
                      color: ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (onStep.isNotEmpty)
                    Text(
                      '$onStep on this step',
                      key: const Key('world-from-wiki-step-elapsed'),
                      style: TextStyle(
                        color: muted,
                        fontSize: 12,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 4,
              color: amber,
              backgroundColor: StudioColors.raiseOf(context),
            ),
          ),
          if (stages.isNotEmpty || onStop != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (var i = 0; i < stages.length; i++)
                  _stageChip(context, i, stages[i], lit: i == stage),
                if (onStop != null)
                  OutlinedButton(
                    key: const Key('world-from-wiki-stop'),
                    onPressed: onStop,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: StudioColors.badOf(context),
                      side: BorderSide(
                        color: StudioColors.badOf(context),
                        width: 1.5,
                      ),
                      visualDensity: VisualDensity.compact,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Stop',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stageChip(
    BuildContext context,
    int i,
    String label, {
    required bool lit,
  }) {
    final amber = StudioColors.amberOf(context);
    return Container(
      key: Key('world-from-wiki-stage-$i'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: lit
            ? amber.withValues(alpha: 0.14)
            : StudioColors.raiseOf(context),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: lit ? Colors.transparent : StudioColors.lineOf(context),
        ),
      ),
      child: Text(
        '${i + 1} · $label',
        style: TextStyle(
          fontSize: 12,
          fontWeight: lit ? FontWeight.w700 : FontWeight.w400,
          color: lit ? amber : StudioColors.mutedOf(context),
        ),
      ),
    );
  }
}
