// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Bulk "Move into…" for multi-selected place cards (locations slice 3).
// Lives apart from the page so the page keeps its headroom under the
// 500-line size law; the flow itself is unchanged from the mockup p1
// multi-select action.

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

/// Pick a target among roots/depth-1 places valid for EVERY world in
/// [selected], then re-parent them all. The repository check still runs
/// per save — a refusal stops the batch and names the world. [repaint]
/// rebuilds the library after a mid-batch restore (the moved card may
/// have been painted under the target before the refusal arrived).
Future<void> movePlacesInto(
  BuildContext context,
  WorldRepository repo,
  Set<String> selected,
  VoidCallback repaint,
) async {
  final selectedWorlds = [for (final id in selected) ?repo.worldById(id)];
  if (selectedWorlds.isEmpty) return;
  final all = repo.placeWorlds;
  // A target qualifies only if it is a candidate for every selection.
  final common = all.where((t) {
    if (selected.contains(t.id)) return false;
    return selectedWorlds.every(
      (s) =>
          parentPickCandidates(s, all, repo.worldById).any((c) => c.id == t.id),
    );
  }).toList();
  if (common.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No place can take all of these (depth cap).'),
        ),
      );
    }
    return;
  }
  final targetId = await showWarmDialog<String>(
    context,
    title:
        'Move ${selectedWorlds.length} place${selectedWorlds.length == 1 ? '' : 's'} into…',
    width: 380,
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final t in common)
            ListTile(
              dense: true,
              title: Text(
                t.name,
                style: TextStyle(color: AppColors.textPrimary(context)),
              ),
              onTap: () => Navigator.pop(context, t.id),
            ),
        ],
      ),
    ),
  );
  if (targetId == null) return;
  var committed = 0;
  for (final w in selectedWorlds) {
    final priorParent = w.parentWorldId;
    try {
      w.parentWorldId = targetId;
      await repo.saveWorld(w);
      committed++;
    } catch (e) {
      // saveWorld re-seats the cache only on success. Anything it throws
      // — the StateError of the depth/cycle law, or a DB failure — must
      // put the parent back AND repaint, so no card keeps sitting under
      // the target while the DB says otherwise (hostile review #592).
      w.parentWorldId = priorParent;
      if (context.mounted) {
        repaint();
        final why = e is StateError ? e.message : '$e';
        final head = committed == 0
            ? ''
            : 'Moved $committed of ${selectedWorlds.length} — ';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$head${w.name}: $why')));
      }
      return;
    }
  }
  if (context.mounted) {
    final target = repo.worldById(targetId);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Moved ${selectedWorlds.length} places into ${target?.name ?? 'the parent'}.',
        ),
      ),
    );
  }
  selected.clear();
  repaint();
}
