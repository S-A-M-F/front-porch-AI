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
import 'package:provider/provider.dart';
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/services/world_chain.dart';
import 'package:front_porch_ai/ui/pages/worlds/worlds.dart';
import 'package:front_porch_ai/ui/theme/theme.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';
import 'world_management/world_management.dart';

class WorldManagementPage extends StatefulWidget {
  const WorldManagementPage({super.key});

  @override
  State<WorldManagementPage> createState() => _WorldManagementPageState();
}

class _WorldManagementPageState extends State<WorldManagementPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _headerAnimController;
  late Animation<double> _headerGlowAnimation;

  // Locations slice 3: library view state. Roots start expanded (the
  // mockup shows children beneath them immediately); collapse is per
  // section, multi-select lives only as long as the page does.
  WorldLibraryFilter _filter = WorldLibraryFilter.all;
  final Set<String> _collapsed = {};
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _headerAnimController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    _headerGlowAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _headerAnimController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _headerAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<WorldRepository>(
      builder: (context, repo, child) {
        final plan = planWorldLibrary(
          worlds: repo.placeWorlds,
          filter: _filter,
        );
        final modelMadeCount = repo.placeWorlds
            .where((w) => w.isModelMade)
            .length;
        return Scaffold(
          backgroundColor: AppColors.backgroundOf(context),
          body: CustomScrollView(
            slivers: [
              // Hero header
              SliverToBoxAdapter(
                child: WorldManagementHeroHeader(
                  glow: _headerGlowAnimation,
                  repo: repo,
                  onNewWorld: (ctx) => _showWorldDialog(ctx, repo),
                ),
              ),

              // Stats section
              SliverToBoxAdapter(
                child: WorldManagementStatsSection(repo: repo),
              ),

              // Filter pills + bulk actions (locations slice 3).
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 20, 28, 4),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final (label, f) in const [
                        ('All places', WorldLibraryFilter.all),
                        ('Roots only', WorldLibraryFilter.rootsOnly),
                        ('Model-made', WorldLibraryFilter.modelMade),
                      ])
                        _pill(context, label, f == _filter, () {
                          setState(() {
                            _filter = f;
                            _selected.clear();
                          });
                        }),
                      const SizedBox(width: 12),
                      if (_filter == WorldLibraryFilter.modelMade &&
                          modelMadeCount > 0)
                        _pill(
                          context,
                          'Delete $modelMadeCount model-made',
                          true,
                          () => _confirmDeleteModelMade(context, repo),
                        ),
                      if (_selected.length >= 2)
                        _pill(
                          context,
                          'Move ${_selected.length} into…',
                          true,
                          () => _moveSelectedInto(context, repo),
                        ),
                    ],
                  ),
                ),
              ),

              // Section label
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(28, 12, 28, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 3,
                        height: 18,
                        decoration: BoxDecoration(
                          color: AppColors.formAccentOf(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Places (${repo.placeWorlds.length})',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary(context),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Root sections: header card + children indented beneath.
              for (final section in plan.sections) ...[
                SliverToBoxAdapter(
                  child: WorldLibraryRootCard(
                    section: section,
                    collapsed: _collapsed.contains(section.root.id),
                    onToggleCollapsed: () => setState(() {
                      if (!_collapsed.remove(section.root.id)) {
                        _collapsed.add(section.root.id);
                      }
                    }),
                    onNewInside: () => _showWorldDialog(
                      context,
                      repo,
                      presetParentId: section.root.id,
                    ),
                    onEdit: () =>
                        _showWorldDialog(context, repo, world: section.root),
                    onExport: () =>
                        exportFpWorldFlow(context, repo, section.root),
                    onDelete: () => _confirmDelete(context, repo, section.root),
                  ),
                ),
                if (!_collapsed.contains(section.root.id))
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(52, 4, 24, 0),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 340,
                            childAspectRatio: 1.2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final w = section.places[index];
                        return WorldPlaceCard(
                          world: w,
                          parent: repo.worldById(w.parentWorldId ?? ''),
                          placeCount: placesUnder(w.id, repo.placeWorlds),
                          selected: _selected.contains(w.id),
                          onSelected: (on) => setState(() {
                            if (on) {
                              _selected.add(w.id);
                            } else {
                              _selected.remove(w.id);
                            }
                          }),
                          onEdit: () =>
                              _showWorldDialog(context, repo, world: w),
                          onExport: () => exportFpWorldFlow(context, repo, w),
                          onDelete: () => _confirmDelete(context, repo, w),
                        );
                      }, childCount: section.places.length),
                    ),
                  ),
              ],

              // Flat grid: childless roots (and model-made search results).
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 380,
                    childAspectRatio: 1.2,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final w = plan.flat[index];
                    return WorldPlaceCard(
                      world: w,
                      placeCount: placesUnder(w.id, repo.placeWorlds),
                      // Any root can take a place — the mockup shows the
                      // action on childless roots too; that is how you
                      // make the first one.
                      onNewInside: _filter == WorldLibraryFilter.modelMade
                          ? null
                          : () => _showWorldDialog(
                              context,
                              repo,
                              presetParentId: w.id,
                            ),
                      onEdit: () => _showWorldDialog(context, repo, world: w),
                      onExport: () => exportFpWorldFlow(context, repo, w),
                      onDelete: () => _confirmDelete(context, repo, w),
                    );
                  }, childCount: plan.flat.length),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return ActionChip(
      onPressed: onTap,
      backgroundColor: active
          ? AppColors.formAccentOf(context).withValues(alpha: 0.16)
          : Colors.transparent,
      side: BorderSide(
        color: active
            ? AppColors.formAccentOf(context)
            : AppColors.borderOf(context),
      ),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: active
              ? AppColors.formAccentOf(context)
              : AppColors.textSecondary(context),
        ),
      ),
    );
  }

  /// Bulk "Move into…": pick a target among roots/depth-1 places valid for
  /// EVERY selected world, then re-parent them all. The repository check
  /// still runs per save — a refusal stops the batch and names the world.
  Future<void> _moveSelectedInto(
    BuildContext context,
    WorldRepository repo,
  ) async {
    final selectedWorlds = [for (final id in _selected) ?repo.worldById(id)];
    if (selectedWorlds.isEmpty) return;
    final all = repo.placeWorlds;
    // A target qualifies only if it is a candidate for every selection.
    final common = all.where((t) {
      if (_selected.contains(t.id)) return false;
      return selectedWorlds.every(
        (s) => parentPickCandidates(
          s,
          all,
          repo.worldById,
        ).any((c) => c.id == t.id),
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
    for (final w in selectedWorlds) {
      try {
        w.parentWorldId = targetId;
        await repo.saveWorld(w);
      } on StateError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('${w.name}: ${e.message}')));
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
    setState(_selected.clear);
  }

  Future<void> _confirmDeleteModelMade(
    BuildContext context,
    WorldRepository repo,
  ) async {
    final doomed = repo.placeWorlds.where((w) => w.isModelMade).toList();
    if (doomed.isEmpty) return;
    final go = await showWarmDialog<bool>(
      context,
      title: 'Delete model-made places?',
      destructive: true,
      content: Text(
        'Delete ${doomed.length} model-made place${doomed.length == 1 ? '' : 's'}? '
        'Places inside them become their own worlds; lore stays.',
        style: TextStyle(color: AppColors.textSecondary(context)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: StatusColors.alertFill,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    );
    if (go != true) return;
    for (final w in doomed) {
      await repo.deleteWorld(w);
    }
  }

  void _showWorldDialog(
    BuildContext context,
    WorldRepository repo, {
    World? world,
    String? presetParentId,
  }) => showWorldEditDialog(
    context,
    repo,
    world: world,
    presetParentId: presetParentId,
    pickerContext: this.context,
  );

  void _confirmDelete(BuildContext context, WorldRepository repo, World world) {
    final inside = placesUnder(world.id, repo.placeWorlds);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete World?'),
        content: Text(
          'Are you sure you want to delete "${world.name}"?'
          '${inside > 0 ? ' Its $inside place${inside == 1 ? '' : 's'} become their own worlds — lore stays.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: StatusColors.alertFill,
            ),
            onPressed: () async {
              final moved = await repo.deleteWorld(world);
              if (context.mounted) Navigator.pop(context);
              if (context.mounted && moved > 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '$moved place${moved == 1 ? '' : 's'} became their own worlds.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
