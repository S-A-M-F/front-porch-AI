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
import 'package:front_porch_ai/services/story_repository.dart';
import 'package:front_porch_ai/services/story_pipeline_service.dart';
import 'package:front_porch_ai/models/story_project.dart';
import 'package:front_porch_ai/ui/pages/story_writer_page.dart';
import 'package:front_porch_ai/ui/pages/story_reader_page.dart';

/// Structure page — act/scene tree with valence indicators and generation controls.
class StoryStructurePage extends StatefulWidget {
  final String projectId;
  const StoryStructurePage({super.key, required this.projectId});

  @override
  State<StoryStructurePage> createState() => _StoryStructurePageState();
}

class _StoryStructurePageState extends State<StoryStructurePage> {
  int _expandedActIndex = -1;

  @override
  Widget build(BuildContext context) {
    return Consumer2<StoryRepository, StoryPipelineService>(
      builder: (context, repo, pipeline, child) {
        final project = repo.getById(widget.projectId);
        if (project == null) {
          return const Scaffold(body: Center(child: Text('Project not found')));
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: AppBar(
            title: Text('Structure — ${project.title}'),
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            elevation: 0,
            actions: [
              // Show Read button when any act has prose
              if (project.prose.isNotEmpty)
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => StoryReaderPage(projectId: widget.projectId),
                    ),
                  ),
                  icon: const Icon(Icons.auto_stories, size: 18, color: Colors.amber),
                  label: const Text('Read Story', style: TextStyle(color: Colors.amber)),
                ),
            ],
          ),
          body: pipeline.isRunning
              ? _buildRunningOverlay(pipeline)
              : _buildStructureTree(project, pipeline),
        );
      },
    );
  }

  Widget _buildRunningOverlay(StoryPipelineService pipeline) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 56, height: 56,
              child: CircularProgressIndicator(strokeWidth: 3, color: Colors.indigo),
            ),
            const SizedBox(height: 32),
            Text(
              pipeline.currentStep,
              style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              pipeline.statusMessage,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 14),
              textAlign: TextAlign.center,
            ),
            if (pipeline.tokenCount > 0) ...[
              const SizedBox(height: 16),
              Text(
                '${pipeline.tokenCount} tokens generated',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.25), fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStructureTree(StoryProject project, StoryPipelineService pipeline) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: project.acts.length,
      itemBuilder: (context, actIdx) {
        final act = project.acts[actIdx];
        final scenes = project.scenes[actIdx] ?? [];
        final isExpanded = _expandedActIndex == actIdx;

        return Column(
          children: [
            // Act header
            InkWell(
              onTap: () => setState(() => _expandedActIndex = isExpanded ? -1 : actIdx),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isExpanded ? Colors.indigo.shade400 : Colors.white10,
                    width: isExpanded ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade900.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text('${act.number}', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(act.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 4),
                          Text(
                            scenes.isEmpty ? 'No scenes yet' : '${scenes.length} scenes',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Valence sparkline
                    if (scenes.isNotEmpty)
                      SizedBox(
                        width: 100, height: 30,
                        child: CustomPaint(
                          painter: _ValenceSparklinePainter(scenes.map((s) => s.valence).toList()),
                        ),
                      ),
                    const SizedBox(width: 8),
                    if (scenes.isEmpty)
                      ElevatedButton.icon(
                        onPressed: pipeline.isRunning ? null : () => _generateFullAct(project, actIdx, pipeline),
                        icon: const Icon(Icons.auto_fix_high, size: 16),
                        label: const Text('Generate Act', style: TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    if (scenes.isNotEmpty) ...[
                      // Show completion status
                      _actCompletionBadge(project, actIdx),
                      const SizedBox(width: 8),
                    ],
                    Icon(isExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.white38),
                  ],
                ),
              ),
            ),

            // Scenes (when expanded)
            if (isExpanded && scenes.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 8),
                child: Column(
                  children: scenes.asMap().entries.map((entry) {
                    final sceneIdx = entry.key;
                    final scene = entry.value;
                    final sId = '$actIdx-$sceneIdx';
                    final beats = project.beats[sId] ?? [];
                    final proseCount = beats.where((b) {
                      final bId = '$sId-${b.number - 1}';
                      return project.prose[bId]?.final_ != null;
                    }).length;

                    return Card(
                      color: const Color(0xFF162032),
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: ListTile(
                        dense: true,
                        leading: _valenceIndicator(scene.valence),
                        title: Text(
                          scene.title,
                          style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                        subtitle: Text(
                          '${scene.location} • ${scene.castNames.join(", ")}',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (beats.isNotEmpty)
                              Text(
                                '$proseCount/${beats.length}',
                                style: TextStyle(
                                  color: proseCount == beats.length ? Colors.greenAccent : Colors.white38,
                                  fontSize: 12,
                                ),
                              ),
                            if (proseCount > 0)
                              IconButton(
                                icon: Icon(Icons.refresh, size: 16, color: Colors.orange.withValues(alpha: 0.7)),
                                tooltip: 'Rewrite scene prose',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                onPressed: pipeline.isRunning ? null : () => _regenerateScene(project, actIdx, sceneIdx, pipeline),
                              ),
                            const SizedBox(width: 4),
                            Icon(Icons.chevron_right, size: 18, color: Colors.white.withValues(alpha: 0.3)),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StoryWriterPage(
                              projectId: widget.projectId,
                              actIndex: actIdx,
                              sceneIndex: sceneIdx,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),

            if (isExpanded && scenes.isEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 32, top: 8),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: const Color(0xFF162032),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                  ),
                  child: const Center(
                    child: Text('Generate scenes to fill this act', style: TextStyle(color: Colors.white24)),
                  ),
                ),
              ),

            const SizedBox(height: 12),
          ],
        );
      },
    );
  }

  Widget _valenceIndicator(int valence) {
    final color = valence > 3 ? Colors.greenAccent
        : valence > 0 ? Colors.lightGreenAccent
        : valence == 0 ? Colors.blueGrey
        : valence > -3 ? Colors.orangeAccent
        : Colors.redAccent;
    return Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Center(
        child: Text(
          valence > 0 ? '+$valence' : '$valence',
          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Future<void> _generateFullAct(StoryProject project, int actIdx, StoryPipelineService pipeline) async {
    try {
      await pipeline.generateFullAct(project, actIdx);
      if (mounted) {
        setState(() => _expandedActIndex = actIdx);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Act ${actIdx + 1} complete! Review the scenes below.'),
            backgroundColor: const Color(0xFF2A2A2A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  Future<void> _regenerateScene(StoryProject project, int actIdx, int sceneIdx, StoryPipelineService pipeline) async {
    final scene = project.scenes[actIdx]?[sceneIdx];
    if (scene == null) return;

    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Rewrite Scene?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will regenerate all prose for "${scene.title}" using the new per-beat system. The old text will be replaced.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Rewrite', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Clear prose for this scene only
    final sId = '$actIdx-$sceneIdx';
    final beats = project.beats[sId] ?? [];
    for (int b = 0; b < beats.length; b++) {
      project.prose.remove('$sId-$b');
    }

    // Save the cleared state
    final repo = Provider.of<StoryRepository>(context, listen: false);
    await repo.saveProject(project);

    // Re-run prose generation for this scene
    try {
      await pipeline.regenerateSceneProse(project, actIdx, sceneIdx);
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ "${scene.title}" rewritten!'),
            backgroundColor: const Color(0xFF2A2A2A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red.shade800),
        );
      }
    }
  }

  Widget _actCompletionBadge(StoryProject project, int actIdx) {
    final scenes = project.scenes[actIdx] ?? [];
    // Check if any scene has prose
    int scenesWithProse = 0;
    for (int s = 0; s < scenes.length; s++) {
      final sId = '$actIdx-$s';
      final beats = project.beats[sId] ?? [];
      if (beats.isNotEmpty) {
        final hasAllProse = beats.asMap().entries.every((e) {
          final bId = '$sId-${e.key}';
          return project.prose[bId]?.final_ != null;
        });
        if (hasAllProse) scenesWithProse++;
      }
    }

    final isComplete = scenesWithProse == scenes.length && scenes.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isComplete
            ? Colors.greenAccent.withValues(alpha: 0.12)
            : Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isComplete ? '✓ Complete' : '$scenesWithProse/${scenes.length}',
        style: TextStyle(
          color: isComplete ? Colors.greenAccent : Colors.amber,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Auto-scrolling live text view for streaming generation output.
class _LiveTextView extends StatefulWidget {
  final String text;
  const _LiveTextView({required this.text});

  @override
  State<_LiveTextView> createState() => _LiveTextViewState();
}

class _LiveTextViewState extends State<_LiveTextView> {
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant _LiveTextView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != oldWidget.text) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 100),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _scrollController,
      child: SelectableText(
        widget.text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.7),
          fontSize: 12,
          fontFamily: 'monospace',
          height: 1.5,
        ),
      ),
    );
  }
}

/// Draws a tiny sparkline of scene valence values.
class _ValenceSparklinePainter extends CustomPainter {
  final List<int> values;
  _ValenceSparklinePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;

    final paint = Paint()
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final zeroPaint = Paint()
      ..color = Colors.white10
      ..strokeWidth = 0.5;

    final yCenter = size.height / 2;
    canvas.drawLine(Offset(0, yCenter), Offset(size.width, yCenter), zeroPaint);

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = yCenter - (values[i] / 10.0) * (size.height / 2);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Gradient effect: positive = green, negative = red
    paint.color = Colors.blueAccent.withValues(alpha: 0.6);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
