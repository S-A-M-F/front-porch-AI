// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This file is part of Front Porch AI.
//
// ... standard ...
//
// You should have received a copy of the GNU Affero General Public License
// along with Front Porch AI. If not, see <https://www.gnu.org/licenses/>.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

class ObjectiveSection extends StatefulWidget {
  final ChatService chatService;
  const ObjectiveSection({super.key, required this.chatService});

  @override
  State<ObjectiveSection> createState() => ObjectiveSectionState();
}

class ObjectiveSectionState extends State<ObjectiveSection> {
  bool _expanded = true; // default expanded
  bool _generatingTasks = false;
  bool _nsfw = false;
  int _taskCount = 5;
  final _goalController = TextEditingController();
  final _manualTaskController = TextEditingController();

  @override
  void dispose() {
    _goalController.dispose();
    _manualTaskController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ChatService>(
      builder: (context, chatService, _) {
        final pObj = chatService.primaryObjective;
        final secondaries = chatService.secondaryObjectives;

        final primaryTasks = pObj != null
            ? chatService.tasksForObjective(pObj)
            : [];
        final completedCount = primaryTasks
            .where((t) => t['completed'] == true)
            .length;
        final currentTask = primaryTasks
            .where((t) => t['completed'] != true)
            .firstOrNull;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.cardOf(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.borderOf(context).withValues(alpha: 0.15),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 16,
                      color: AppColors.iconSecondary(context),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.flag, size: 14, color: Colors.orangeAccent),
                    const SizedBox(width: 6),
                    Text(
                      'Objectives',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    if (pObj != null)
                      Text(
                        '$completedCount/${primaryTasks.length}',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppColors.textTertiary(context),
                        ),
                      ),
                  ],
                ),
              ),

              if (!_expanded && pObj != null && currentTask != null) ...[
                const SizedBox(height: 6),
                Text(
                  '▸ ${currentTask['description']}',
                  style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              if (_expanded) ...[
                const SizedBox(height: 10),

                // Primary Objective Display
                if (pObj != null) ...[
                  Text(
                    'PRIMARY QUEST',
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: Colors.orangeAccent.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.star, size: 14, color: Colors.orangeAccent),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            pObj.objective,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textPrimary(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => chatService.clearObjective(pObj),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // NSFW toggle
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 14,
                        color: AppColors.iconSecondary(context),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'NSFW Tasks',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        height: 24,
                        child: Switch(
                          value: _nsfw,
                          activeThumbColor: Colors.redAccent,
                          onChanged: (v) => setState(() => _nsfw = v),
                        ),
                      ),
                    ],
                  ),

                  if (primaryTasks.isEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _generatingTasks
                                ? null
                                : () async {
                                    setState(() => _generatingTasks = true);
                                    await chatService.generateObjectiveTasks(
                                      pObj,
                                      taskCount: _taskCount,
                                      nsfw: _nsfw,
                                    );
                                    if (mounted) {
                                      setState(() => _generatingTasks = false);
                                    }
                                  },
                            icon: _generatingTasks
                                ? SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textPrimary(context),
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome, size: 14),
                            label: Text(
                              _generatingTasks
                                  ? 'Generating...'
                                  : 'Generate Tasks',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.surfaceContainerOf(
                                context,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              textStyle: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceContainerOf(context),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: DropdownButton<int>(
                            value: _taskCount,
                            underline: const SizedBox.shrink(),
                            dropdownColor: AppColors.surfaceContainerOf(
                              context,
                            ),
                            style: TextStyle(
                              color: AppColors.textPrimary(context),
                              fontSize: 12,
                            ),
                            isDense: true,
                            items: [3, 4, 5, 6, 7, 8, 10]
                                .map(
                                  (n) => DropdownMenuItem(
                                    value: n,
                                    child: Text('$n'),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _taskCount = v ?? 5),
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: _manualTaskController,
                          style: TextStyle(
                            color: AppColors.textPrimary(context),
                            fontSize: 11,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Add a task manually...',
                            hintStyle: TextStyle(
                              color: AppColors.textTertiary(context),
                              fontSize: 11,
                            ),
                            filled: true,
                            fillColor: AppColors.surfaceContainerOf(context),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                            ),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onSubmitted: (text) async {
                            if (text.trim().isEmpty) return;
                            await chatService.addManualTask(pObj, text);
                            _manualTaskController.clear();
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      InkWell(
                        onTap: () async {
                          final text = _manualTaskController.text.trim();
                          if (text.isEmpty) return;
                          await chatService.addManualTask(pObj, text);
                          _manualTaskController.clear();
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.add_circle_outline,
                            size: 18,
                            color: Colors.orangeAccent,
                          ),
                        ),
                      ),
                    ],
                  ),

                  if (primaryTasks.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...primaryTasks.asMap().entries.map((entry) {
                      final i = entry.key;
                      final task = entry.value;
                      final completed = task['completed'] == true;
                      final isCurrent =
                          !completed &&
                          primaryTasks
                              .take(i)
                              .every((t) => t['completed'] == true);

                      return EditableTaskRow(
                        key: ValueKey('task_$i'),
                        description: task['description'] as String,
                        completed: completed,
                        isCurrent: isCurrent,
                        onToggle: () => chatService.toggleTask(pObj, i),
                        onDelete: () => chatService.removeTask(pObj, i),
                        onEdit: (newText) =>
                            chatService.updateTask(pObj, i, newText),
                      );
                    }),

                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text(
                          'Check every ',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        SizedBox(
                          width: 80,
                          child: SliderTheme(
                            data: SliderThemeData(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 5,
                              ),
                              activeTrackColor: AppColors.resolve(
                                context,
                                Colors.white30,
                                Colors.black26,
                              ),
                              inactiveTrackColor: AppColors.borderOf(
                                context,
                              ).withValues(alpha: 0.2),
                              thumbColor: AppColors.textSecondary(context),
                            ),
                            child: Slider(
                              value: pObj.checkFrequency.toDouble(),
                              min: 1,
                              max: 10,
                              divisions: 9,
                              onChanged: (v) => chatService
                                  .updateCheckFrequency(pObj, v.round()),
                            ),
                          ),
                        ),
                        Text(
                          '${pObj.checkFrequency} msgs',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                        const SizedBox(width: 8),
                        chatService.isCheckingCompletion
                            ? SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: Colors.greenAccent,
                                ),
                              )
                            : InkWell(
                                onTap: () => chatService.forceCheckCompletion(),
                                child: Padding(
                                  padding: const EdgeInsets.all(2),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        size: 12,
                                        color: Colors.greenAccent,
                                      ),
                                      SizedBox(width: 2),
                                      Text(
                                        'Check now',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.greenAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ],
                ],

                // Secondary Objectives
                if (secondaries.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'SIDE QUESTS',
                    style: TextStyle(
                      fontSize: 9,
                      color: AppColors.textSecondary(context),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  for (final sObj in secondaries)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceContainerOf(context),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.circle_outlined,
                            size: 10,
                            color: AppColors.iconSecondary(context),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              sObj.objective,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textPrimary(context),
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => chatService.setObjective(
                              sObj.objective,
                              isPrimary: true,
                            ),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.keyboard_double_arrow_up,
                                size: 14,
                                color: Colors.orangeAccent,
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: () => chatService.clearObjective(sObj),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4),
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],

                const SizedBox(height: 12),

                // Add new objective box
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _goalController,
                        style: TextStyle(
                          color: AppColors.textPrimary(context),
                          fontSize: 11,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Add new goal...',
                          hintStyle: TextStyle(
                            color: AppColors.textTertiary(context),
                            fontSize: 11,
                          ),
                          filled: true,
                          fillColor: AppColors.surfaceContainerOf(context),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                        onSubmitted: (text) async {
                          if (text.trim().isEmpty) return;
                          await chatService.setObjective(
                            text,
                            isPrimary: chatService.primaryObjective == null,
                          );
                          _goalController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () async {
                        final text = _goalController.text.trim();
                        if (text.isEmpty) return;
                        await chatService.setObjective(text, isPrimary: true);
                        _goalController.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orangeAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      child: const Text('As Primary'),
                    ),
                    const SizedBox(width: 4),
                    ElevatedButton(
                      onPressed: () async {
                        final text = _goalController.text.trim();
                        if (text.isEmpty) return;
                        await chatService.setObjective(text, isPrimary: false);
                        _goalController.clear();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.surfaceContainerOf(context),
                        foregroundColor: AppColors.textPrimary(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        textStyle: const TextStyle(fontSize: 10),
                      ),
                      child: const Text('As Side'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

// ── Editable Task Row ──────────────────────────────────────────────────

class EditableTaskRow extends StatefulWidget {
  final String description;
  final bool completed;
  final bool isCurrent;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final ValueChanged<String> onEdit;

  const EditableTaskRow({
    super.key,
    required this.description,
    required this.completed,
    required this.isCurrent,
    required this.onToggle,
    required this.onDelete,
    required this.onEdit,
  });

  @override
  State<EditableTaskRow> createState() => EditableTaskRowState();
}

class EditableTaskRowState extends State<EditableTaskRow> {
  bool _editing = false;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.description);
  }

  @override
  void didUpdateWidget(EditableTaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && oldWidget.description != widget.description) {
      _controller.text = widget.description;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onEdit(_controller.text.trim());
    }
    setState(() => _editing = false);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Checkbox
          GestureDetector(
            onTap: widget.onToggle,
            child: Icon(
              widget.completed
                  ? Icons.check_box
                  : Icons.check_box_outline_blank,
              size: 16,
              color: widget.completed
                  ? Colors.greenAccent
                  : widget.isCurrent
                  ? Colors.orangeAccent
                  : AppColors.iconSecondary(context),
            ),
          ),
          const SizedBox(width: 6),

          // Description or edit field
          Expanded(
            child: _editing
                ? TextField(
                    controller: _controller,
                    autofocus: true,
                    style: TextStyle(
                      color: AppColors.textPrimary(context),
                      fontSize: 11,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      filled: true,
                      fillColor: AppColors.surfaceContainerOf(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Colors.orangeAccent,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: const BorderSide(
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                    onSubmitted: (_) => _save(),
                  )
                : GestureDetector(
                    onTap: widget.onToggle,
                    child: Text(
                      widget.description,
                      style: TextStyle(
                        fontSize: 11,
                        color: widget.completed
                            ? AppColors.textTertiary(context)
                            : widget.isCurrent
                            ? AppColors.textPrimary(context)
                            : AppColors.textSecondary(context),
                        decoration: widget.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ),
          ),

          // Current task indicator
          if (widget.isCurrent && !_editing)
            const Padding(
              padding: EdgeInsets.only(left: 2),
              child: Text(
                '◂',
                style: TextStyle(fontSize: 10, color: Colors.orangeAccent),
              ),
            ),

          const SizedBox(width: 4),

          // Edit / Save button
          if (_editing)
            GestureDetector(
              onTap: _save,
              child: const Icon(
                Icons.check,
                size: 14,
                color: Colors.greenAccent,
              ),
            )
          else
            GestureDetector(
              onTap: () => setState(() => _editing = true),
              child: Icon(
                Icons.edit,
                size: 12,
                color: AppColors.iconSecondary(context),
              ),
            ),

          const SizedBox(width: 4),

          // Delete button
          GestureDetector(
            onTap: widget.onDelete,
            child: Icon(
              Icons.close,
              size: 12,
              color: AppColors.iconSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}
