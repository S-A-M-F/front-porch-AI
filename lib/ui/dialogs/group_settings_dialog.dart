// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';

/// Main settings dialog for a Group Chat.
/// This is the central place for all per-group and per-character configuration.
class GroupSettingsDialog extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;

  const GroupSettingsDialog({
    super.key,
    required this.chatService,
    this.groupRepo,
  });

  @override
  State<GroupSettingsDialog> createState() => _GroupSettingsDialogState();
}

class _GroupSettingsDialogState extends State<GroupSettingsDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        width: 720,
        height: 620,
        decoration: BoxDecoration(
          color: const Color(0xFF1F2937),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Group Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // Tabs
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: const [
                Tab(text: 'Prompt Engineering'),
                Tab(text: 'Memory & RAG'),
                Tab(text: 'Realism & Needs'),
                Tab(text: 'General'),
              ],
            ),

            const Divider(height: 1, color: Colors.white12),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _PromptEngineeringTab(chatService: widget.chatService, groupRepo: widget.groupRepo),
                  _MemoryRAGTab(chatService: widget.chatService, groupRepo: widget.groupRepo),
                  _RealismNeedsTab(chatService: widget.chatService, groupRepo: widget.groupRepo),
                  _GeneralTab(chatService: widget.chatService, groupRepo: widget.groupRepo),
                ],
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFF111827),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                  const SizedBox(width: 8),
                  if (widget.groupRepo != null)
                    OutlinedButton(
                      onPressed: () {
                        final g = widget.chatService.activeGroup;
                        if (g != null) {
                          widget.groupRepo!.save(g);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('All group changes saved.')),
                          );
                        }
                      },
                      child: const Text('Save All Changes'),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Placeholder tabs — will be implemented by sub-agents / follow-up work

class _PromptEngineeringTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _PromptEngineeringTab({required this.chatService, this.groupRepo});

  @override
  State<_PromptEngineeringTab> createState() => _PromptEngineeringTabState();
}

class _PromptEngineeringTabState extends State<_PromptEngineeringTab> {
  // Group-level controllers / state (edited locally, applied on Save)
  late final TextEditingController _groupSystemController;
  late final TextEditingController _groupAuthorNoteController;
  int _groupAuthorNoteStrength = 4;

  // Per-character editing state. Keys are live CharacterCard instances
  // (stable references from chatService.groupCharacters).
  final Map<CharacterCard, TextEditingController> _perCharNoteControllers = {};
  final Map<CharacterCard, int> _perCharStrengths = {};

  bool _changesSaved = false;

  // Per-character accent colors (matches chat sidebar palette)
  static const List<Color> _charColors = [
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFEF4444), // Red
    Color(0xFF3B82F6), // Blue
    Color(0xFFEC4899), // Pink
    Color(0xFF14B8A6), // Teal
    Color(0xFFF97316), // Orange
  ];

  Color _charColor(int index) => _charColors[index % _charColors.length];

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initEditingState();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initEditingState() {
    final cs = widget.chatService;
    final group = cs.activeGroup;

    _groupSystemController = TextEditingController(
      text: group?.systemPrompt ?? '',
    );
    _groupAuthorNoteController = TextEditingController(
      text: cs.authorNote,
    );
    _groupAuthorNoteStrength = cs.authorNoteStrength;

    // Pre-create controllers for current characters using live getters
    // (so first render has correct starting values).
    for (final c in cs.groupCharacters) {
      _getOrCreateNoteController(c); // creates + populates from service
      _perCharStrengths[c] ??= cs.getAuthorNoteStrengthForGroupCharacter(c);
    }

    _changesSaved = false;
  }

  TextEditingController _getOrCreateNoteController(CharacterCard c) {
    return _perCharNoteControllers.putIfAbsent(c, () {
      final initial = widget.chatService.getAuthorNoteForGroupCharacter(c);
      return TextEditingController(text: initial);
    });
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);

    _groupSystemController.dispose();
    _groupAuthorNoteController.dispose();

    for (final ctrl in _perCharNoteControllers.values) {
      ctrl.dispose();
    }
    _perCharNoteControllers.clear();
    _perCharStrengths.clear();

    super.dispose();
  }

  void _saveChanges() {
    final cs = widget.chatService;
    final group = cs.activeGroup;

    // 1. Group system prompt (in-memory update for immediate effect on prompts;
    //    full persistence to DB requires GroupChatRepository which is not
    //    passed to this dialog. The value affects the current session.
    //    Consumers of ChatService will see the live value on next rebuild.)
    if (group != null) {
      group.systemPrompt = _groupSystemController.text.trim();
    }

    // 2. Group-level Author's Note + strength (persists via public API + checkpoint)
    cs.setAuthorNote(
      _groupAuthorNoteController.text,
      strength: _groupAuthorNoteStrength,
    );

    // 3. Per-character Author's Notes + strengths (persist via public APIs)
    for (final c in cs.groupCharacters) {
      final noteCtrl = _perCharNoteControllers[c];
      final note = noteCtrl?.text.trim() ?? '';
      final strength = _perCharStrengths[c] ?? cs.getAuthorNoteStrengthForGroupCharacter(c);
      cs.setAuthorNoteForGroupCharacter(c, note, strength: strength);
    }

    // 4. Persist the GroupChat model (name, scenario, systemPrompt, directorMode, etc.)
    if (widget.groupRepo != null && group != null) {
      widget.groupRepo!.save(group); // fire-and-forget is acceptable here
    }

    if (mounted) {
      setState(() {
        _changesSaved = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Prompt engineering changes saved.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final chars = cs.groupCharacters;
    final hasGroup = cs.activeGroup != null && chars.isNotEmpty;

    if (!hasGroup) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.group_off_outlined, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'No active group chat',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              'Author\'s notes and group prompts are only available in group mode.',
              style: TextStyle(color: Colors.white24, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Group System Prompt ─────────────────────────────────────
                const Row(
                  children: [
                    Icon(Icons.code, size: 16, color: Colors.blueAccent),
                    SizedBox(width: 6),
                    Text(
                      'Group System Prompt',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blueAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Overrides the default group system prompt when non-empty.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: _groupSystemController,
                  maxLines: 5,
                  minLines: 3,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Custom system prompt for the entire group...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.blueAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) {
                    if (_changesSaved) setState(() => _changesSaved = false);
                  },
                ),

                const SizedBox(height: 20),

                // ── Per-Character Author's Notes ────────────────────────────
                const Row(
                  children: [
                    Icon(Icons.person_outline, size: 16, color: Colors.purpleAccent),
                    SizedBox(width: 6),
                    Text(
                      "Per-Character Author's Notes",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.purpleAccent,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Specific notes injected only when that character is the current speaker (after any group note). Strength is independent per character.',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
                const SizedBox(height: 12),

                // Character editors (reactive to current groupCharacters)
                for (int i = 0; i < chars.length; i++)
                  _buildCharacterNoteEditor(chars[i], i),

                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // ── Save bar at bottom of tab ─────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12)),
            color: Color(0xFF111827),
          ),
          child: Row(
            children: [
              if (_changesSaved)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 16, color: Color(0xFF10B981)),
                      SizedBox(width: 4),
                      Text(
                        'Saved',
                        style: TextStyle(color: Color(0xFF10B981), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _saveChanges,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blueAccent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterNoteEditor(CharacterCard c, int index) {
    final noteCtrl = _getOrCreateNoteController(c);
    final strength = _perCharStrengths.putIfAbsent(
      c,
      () => widget.chatService.getAuthorNoteStrengthForGroupCharacter(c),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: _charColor(index),
                backgroundImage: c.imagePath != null
                    ? FileImage(File(c.imagePath!))
                    : null,
                child: c.imagePath == null
                    ? Text(
                        c.name.isNotEmpty ? c.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  c.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Note field
          AppTextField(
            controller: noteCtrl,
            maxLines: 3,
            minLines: 1,
            style: const TextStyle(color: Colors.white, fontSize: 12),
            decoration: InputDecoration(
              hintText: "Author's note for ${c.name} (when they speak)...",
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 11),
              filled: true,
              fillColor: const Color(0xFF1F2937),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.white10),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: Colors.purpleAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (_) {
              if (_changesSaved) setState(() => _changesSaved = false);
            },
          ),
          const SizedBox(height: 8),

          // Compact strength slider (1-10)
          Row(
            children: [
              const Text(
                'Strength',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2.5,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: _charColor(index),
                    inactiveTrackColor: Colors.white12,
                    thumbColor: _charColor(index),
                  ),
                  child: Slider(
                    value: strength.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    onChanged: (val) {
                      setState(() {
                        _perCharStrengths[c] = val.round();
                        if (_changesSaved) _changesSaved = false;
                      });
                    },
                  ),
                ),
              ),
              SizedBox(
                width: 22,
                child: Text(
                  '$strength',
                  style: TextStyle(
                    color: _charColor(index),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Builds the group-level strength control with tier labels (matches sidebar styling).
  Widget _buildStrengthSlider({
    required int strength,
    required ValueChanged<int> onChanged,
  }) {
    Color sliderColor;
    String tierLabel;
    if (strength <= 3) {
      sliderColor = Colors.blueAccent;
      tierLabel = 'Subtle';
    } else if (strength <= 7) {
      sliderColor = Colors.amberAccent;
      tierLabel = 'Moderate';
    } else {
      sliderColor = Colors.redAccent;
      tierLabel = 'Strong';
    }

    return Column(
      children: [
        Row(
          children: [
            const Tooltip(
              message:
                  'Controls how forcefully the author\'s note is applied.\n'
                  'Subtle: a gentle suggestion the AI may follow.\n'
                  'Moderate: standard injection into context.\n'
                  'Strong: an urgent directive the AI should apply immediately.',
              child: Text(
                'Strength: ',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ),
            Expanded(
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 12,
                  ),
                  activeTrackColor: sliderColor,
                  inactiveTrackColor: Colors.white12,
                  thumbColor: sliderColor,
                ),
                child: Slider(
                  value: strength.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  label: '$strength — $tierLabel',
                  onChanged: (val) => onChanged(val.round()),
                ),
              ),
            ),
            Text(
              '$strength',
              style: TextStyle(
                color: sliderColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: sliderColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: sliderColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  tierLabel,
                  style: TextStyle(
                    color: sliderColor,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

class _MemoryRAGTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _MemoryRAGTab({required this.chatService, this.groupRepo});

  @override
  State<_MemoryRAGTab> createState() => _MemoryRAGTabState();
}

class _MemoryRAGTabState extends State<_MemoryRAGTab> {
  bool _groupRagEnabled = true;
  int _retrievalCount = 8;
  double _memoryBudgetPercent = 10.0;
  Map<String, double> _charPriorities = {};
  List<CharacterCard> _chars = [];
  bool _hasUnsavedChanges = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _initializeFromActiveGroup();
  }

  void _initializeFromActiveGroup() {
    final group = widget.chatService.activeGroup;
    if (group == null) {
      _chars = [];
      _charPriorities = {};
      return;
    }

    _chars = widget.chatService.groupCharacters;

    // Load live values from the checkpoint-backed ChatService state.
    // These persist across sessions via the hidden __group_state__ message.
    _groupRagEnabled = widget.chatService.groupRagEnabled;
    _retrievalCount = widget.chatService.groupRetrievalCount;
    _memoryBudgetPercent = widget.chatService.groupMemoryBudgetPercent;

    final savedPriorities = widget.chatService.currentGroupRAGPriorities;
    _charPriorities = {
      for (final c in _chars)
        c.name: savedPriorities[c.name] ?? 1.0,
    };

    _hasUnsavedChanges = false;
    _statusMessage = '';
  }

  void _updateCharPriority(String charName, double value) {
    setState(() {
      _charPriorities[charName] = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _updateRetrievalCount(int value) {
    setState(() {
      _retrievalCount = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _updateMemoryBudget(double value) {
    setState(() {
      _memoryBudgetPercent = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _toggleGroupRag(bool value) {
    setState(() {
      _groupRagEnabled = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _resetToDefaults() {
    setState(() {
      _groupRagEnabled = true;
      _retrievalCount = 8;
      _memoryBudgetPercent = 10.0;
      _charPriorities = {
        for (final c in _chars) c.name: 1.0,
      };
      _hasUnsavedChanges = true;
      _statusMessage = 'Reset to defaults (unsaved)';
    });
  }

  void _saveSettings() {
    final group = widget.chatService.activeGroup;
    if (group == null) return;

    // Apply via ChatService (which now persists via the hidden checkpoint)
    widget.chatService.setGroupRAGEnabled(_groupRagEnabled);
    widget.chatService.setGroupRetrievalCount(_retrievalCount);
    widget.chatService.setGroupMemoryBudgetPercent(_memoryBudgetPercent);

    // Per-character priorities
    for (final entry in _charPriorities.entries) {
      // We need stable IDs here — the tab currently uses names.
      // For now we keep the old behavior (names as keys) until we standardize on IDs.
      widget.chatService.setCharacterRAGPriority(entry.key, entry.value);
    }

    debugPrint('[GroupSettings:MemoryRAG] Saved RAG config for group ${group.name}');

    setState(() {
      _hasUnsavedChanges = false;
      _statusMessage = 'RAG settings saved for this group.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.psychology, color: Colors.purpleAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Memory & RAG — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_hasUnsavedChanges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'UNSAVED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Per-group RAG controls. Memories are embedded from this group\'s conversation history and retrieved when context is dropped.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 16),

            // Group-level RAG section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.toggle_on, size: 18, color: Colors.purpleAccent),
                      const SizedBox(width: 8),
                      const Text(
                        'Enable RAG for this group',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const Spacer(),
                      Switch(
                        value: _groupRagEnabled,
                        activeTrackColor: Colors.purpleAccent,
                        onChanged: _toggleGroupRag,
                      ),
                    ],
                  ),
                  if (!_groupRagEnabled)
                    const Padding(
                      padding: EdgeInsets.only(left: 26, top: 2, bottom: 8),
                      child: Text(
                        'Retrieval skipped for this group even if global RAG is on.',
                        style: TextStyle(fontSize: 11, color: Colors.white38),
                      ),
                    ),
                  const SizedBox(height: 8),

                  // Retrieval count
                  Row(
                    children: [
                      const Text(
                        'Memories per turn (retrieval limit)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        _retrievalCount == 0 ? 'All' : '$_retrievalCount',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _retrievalCount.toDouble(),
                      min: 0,
                      max: 30,
                      divisions: 30,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: Colors.white12,
                      onChanged: (v) => _updateRetrievalCount(v.round()),
                    ),
                  ),

                  const SizedBox(height: 6),

                  // Memory budget (context length feel)
                  Row(
                    children: [
                      const Text(
                        'RAG memory budget (% of context)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '${_memoryBudgetPercent.round()}%',
                        style: const TextStyle(
                          color: Colors.purpleAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _memoryBudgetPercent,
                      min: 5,
                      max: 25,
                      divisions: 20,
                      activeColor: Colors.purpleAccent,
                      inactiveColor: Colors.white12,
                      onChanged: _updateMemoryBudget,
                    ),
                  ),

                  const SizedBox(height: 4),
                  const Text(
                    'Note: Global embedding window size (messages per chunk) lives in main Settings → Memory (RAG). Per-group override would be a future extension.',
                    style: TextStyle(fontSize: 10, color: Colors.white30, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character priorities
            Row(
              children: [
                const Icon(Icons.people_alt, size: 18, color: Colors.purpleAccent),
                const SizedBox(width: 8),
                const Text(
                  'Per-Character Memory Importance',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _resetToDefaults,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Reset all to 1.0',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Boost or suppress how heavily each character\'s past messages influence RAG results (0.0–2.0). 1.0 = normal relevance scoring.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 8),

            if (_chars.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            else
              ..._chars.map((char) {
                final priority = _charPriorities[char.name] ?? 1.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 11,
                        backgroundColor: Colors.purpleAccent.withValues(alpha: 0.25),
                        child: Text(
                          char.name.isNotEmpty ? char.name[0].toUpperCase() : '?',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 3,
                        child: Text(
                          char.name,
                          style: const TextStyle(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2.5,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                          ),
                          child: Slider(
                            value: priority,
                            min: 0.0,
                            max: 2.0,
                            divisions: 20,
                            activeColor: Colors.purpleAccent,
                            inactiveColor: Colors.white12,
                            onChanged: (v) => _updateCharPriority(char.name, v),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 32,
                        child: Text(
                          priority.toStringAsFixed(1),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            color: Colors.purpleAccent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 16),

            // Save controls
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Save RAG Settings for Group'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purpleAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                const SizedBox(width: 12),
                if (_statusMessage.isNotEmpty)
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RealismNeedsTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _RealismNeedsTab({required this.chatService, this.groupRepo});

  @override
  State<_RealismNeedsTab> createState() => _RealismNeedsTabState();
}

class _RealismNeedsTabState extends State<_RealismNeedsTab> {
  bool _realismEnabled = false;
  bool _needsSimEnabled = false;
  bool _passageOfTimeEnabled = true;
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;

  bool _hasUnsavedChanges = false;
  String _statusMessage = '';

  List<CharacterCard> _chars = [];

  @override
  void initState() {
    super.initState();
    widget.chatService.addListener(_onServiceChanged);
    _initializeFromService();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  void _initializeFromService() {
    final cs = widget.chatService;
    _chars = cs.groupCharacters;

    _realismEnabled = cs.realismEnabled;
    _needsSimEnabled = cs.needsSimEnabled;
    _passageOfTimeEnabled = cs.passageOfTimeEnabled;
    _chaosModeEnabled = cs.chaosModeEnabled;
    _chaosNsfwEnabled = cs.chaosNsfwEnabled;

    _hasUnsavedChanges = false;
    _statusMessage = '';
  }

  @override
  void dispose() {
    widget.chatService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _markDirty() {
    setState(() {
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _updateRealism(bool value) {
    _realismEnabled = value;
    _markDirty();
  }

  void _updateNeedsSim(bool value) {
    _needsSimEnabled = value;
    _markDirty();
  }

  void _updatePassageOfTime(bool value) {
    _passageOfTimeEnabled = value;
    _markDirty();
  }

  void _updateChaosMode(bool value) {
    _chaosModeEnabled = value;
    _markDirty();
  }

  void _updateChaosNsfw(bool value) {
    _chaosNsfwEnabled = value;
    _markDirty();
  }

  Future<void> _saveSettings() async {
    final cs = widget.chatService;

    await cs.setRealismEnabled(_realismEnabled);
    await cs.setNeedsSimEnabled(_needsSimEnabled);
    await cs.setPassageOfTimeEnabled(_passageOfTimeEnabled);
    await cs.setChaosModeEnabled(_chaosModeEnabled);
    await cs.setChaosNsfwEnabled(_chaosNsfwEnabled);

    if (mounted) {
      _initializeFromService();
      setState(() {
        _statusMessage =
            'Realism & Needs settings applied live to the current session.';
      });
    }

    // Defensive persist of the GroupChat (in case any flags were moved to the model later)
    final g = widget.chatService.activeGroup;
    if (widget.groupRepo != null && g != null) {
      widget.groupRepo!.save(g);
    }
  }

  void _resetToDefaults() {
    setState(() {
      _realismEnabled = false;
      _needsSimEnabled = false;
      _passageOfTimeEnabled = true;
      _chaosModeEnabled = false;
      _chaosNsfwEnabled = false;
      _hasUnsavedChanges = true;
      _statusMessage = 'Reset to defaults (unsaved)';
    });
  }

  void _resetAllRealismStates() {
    final cs = widget.chatService;
    if (cs.activeGroup == null) return;

    for (final c in cs.groupCharacters) {
      cs.resetRealismForGroupCharacter(c);
    }

    if (mounted) {
      setState(() {
        _statusMessage =
            'All character realism states cleared for this group. They will re-initialize on the next turn/eval.';
      });
    }
  }

  void _resetCharacterRealism(CharacterCard character) {
    widget.chatService.resetRealismForGroupCharacter(character);
    if (mounted) {
      setState(() {
        _statusMessage = 'Reset realism state for ${character.name}.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.chatService;
    final group = cs.activeGroup;
    final isDirectorMode = cs.observerMode;
    final isRealismActive = cs.isGroupRealismActive;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.theater_comedy, color: Colors.tealAccent, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Realism & Needs — ${group.name}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_hasUnsavedChanges)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'UNSAVED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Master toggles and per-character baseline management for the Realism Engine, Needs simulation, Chaos Mode, and Passage of Time in this group.',
              style: TextStyle(fontSize: 12, color: Colors.white70),
            ),
            const SizedBox(height: 12),

            // Director Mode notice (visual indication per requirements)
            if (isDirectorMode)
              Container(
                padding: const EdgeInsets.all(10),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1F2937),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Director Mode is active. Realism Engine, Needs Simulation, and related tracking are suspended for this group (narrative control only). Exit Director Mode to re-enable.',
                        style: const TextStyle(fontSize: 12, color: Colors.amber, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),

            // Master Realism Engine
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 18, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Realism Engine for this group',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _realismEnabled,
                        activeColor: Colors.tealAccent,
                        onChanged: _updateRealism,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tracks emotions, short/long-term bond, trust, arousal, and fixation per character. Only takes effect when not in Director Mode.',
                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                  if (!_realismEnabled)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Sub-features (Needs, etc.) have no effect while the master toggle is off.',
                        style: TextStyle(fontSize: 10, color: Colors.white38, fontStyle: FontStyle.italic),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Needs Simulation
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.battery_std, size: 18, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Needs Simulation',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _needsSimEnabled,
                        activeColor: Colors.tealAccent,
                        onChanged: _updateNeedsSim,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Simulates hunger, bladder, energy, social, fun, hygiene, and comfort. Low needs influence AI behavior and prompt injections. Only relevant when Realism Engine is enabled.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Passage of Time + Chaos (two-column-ish or stacked)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Passage of Time
                  Row(
                    children: [
                      const Icon(Icons.access_time, size: 18, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Passage of Time',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _passageOfTimeEnabled,
                        activeColor: Colors.tealAccent,
                        onChanged: _updatePassageOfTime,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Automatically advances narrative time between turns. Manual nudge controls remain available in the sidebar.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),

                  const SizedBox(height: 14),
                  const Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),

                  // Chaos Mode
                  Row(
                    children: [
                      const Text('🎰', style: TextStyle(fontSize: 16)),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Chaos Mode (Chance Time)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      Switch(
                        value: _chaosModeEnabled,
                        activeColor: const Color(0xFFFFD166),
                        onChanged: _updateChaosMode,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Injects random narrative events based on accumulating pressure. Great for surprising group dynamics.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),

                  if (_chaosModeEnabled) ...[
                    const SizedBox(height: 10),

                    // Pressure readout (live from service)
                    Row(
                      children: [
                        Icon(
                          Icons.casino_rounded,
                          size: 14,
                          color: _pressureColorFor(cs.chaosPressure),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pressure: ${cs.chaosPressure}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: _pressureColorFor(cs.chaosPressure),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // NSFW spicy toggle
                    Row(
                      children: [
                        const Text('🌶️', style: TextStyle(fontSize: 13)),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            'Include spicy/NSFW events',
                            style: TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Switch(
                            value: _chaosNsfwEnabled,
                            activeColor: const Color(0xFFFF6B9D),
                            onChanged: _updateChaosNsfw,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Per-character baselines / reset section
            Row(
              children: [
                const Icon(Icons.people_alt, size: 18, color: Colors.tealAccent),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Per-Character Realism Baselines',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
                TextButton(
                  onPressed: _resetAllRealismStates,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Reset ALL',
                    style: TextStyle(fontSize: 11, color: Colors.tealAccent),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Clear tracked emotion, bond, trust, needs, and fixation for characters in the current group. Use to restart relationship arcs or after major story changes. States re-seed automatically on the next Realism evaluation.',
              style: TextStyle(fontSize: 11, color: Colors.white54),
            ),
            const SizedBox(height: 10),

            if (_chars.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'No characters loaded for this group.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              )
            else
              ..._chars.asMap().entries.map((entry) {
                final index = entry.key;
                final char = entry.value;
                final liveState = isRealismActive
                    ? cs.getRealismStateForGroupCharacter(char)
                    : null;
                final emo = liveState?['emotion'] as String?;
                final bond = isRealismActive
                    ? cs.getAffectionForGroupCharacter(char)
                    : 0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      // Avatar (matches Prompt tab style)
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: _charAccentColor(index),
                        backgroundImage: char.imagePath != null
                            ? FileImage(File(char.imagePath!))
                            : null,
                        child: char.imagePath == null
                            ? Text(
                                char.name.isNotEmpty ? char.name[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              char.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isRealismActive
                                  ? (emo != null
                                      ? 'Emotion: $emo • Bond: $bond'
                                      : 'No realism data yet (will seed on next turn)')
                                  : 'Realism inactive (Director Mode or master off)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => _resetCharacterRealism(char),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'Reset',
                          style: TextStyle(fontSize: 12, color: Colors.tealAccent),
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 16),

            // Save controls
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _saveSettings,
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('Apply Changes to Session'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.tealAccent,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                ),
                const SizedBox(width: 10),
                TextButton(
                  onPressed: _resetToDefaults,
                  child: const Text(
                    'Reset toggles',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 12),
                if (_statusMessage.isNotEmpty)
                  Expanded(
                    child: Text(
                      _statusMessage,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.greenAccent,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // Helper for chaos pressure color (matches _ChaosModeSection in chat_page)
  Color _pressureColorFor(int pressure) {
    final t = (pressure / 100).clamp(0.0, 1.0);
    return Color.lerp(
      const Color(0xFF2EC4B6),
      const Color(0xFFE63946),
      t,
    )!;
  }

  // Simple accent palette for per-char avatars (subset of Prompt tab palette)
  static const List<Color> _charColors = [
    Color(0xFF14B8A6), // Teal (realism accent)
    Color(0xFF8B5CF6), // Purple
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFF3B82F6), // Blue
  ];

  Color _charAccentColor(int index) => _charColors[index % _charColors.length];
}
class _GeneralTab extends StatefulWidget {
  final ChatService chatService;
  final GroupChatRepository? groupRepo;
  const _GeneralTab({required this.chatService, this.groupRepo});

  @override
  State<_GeneralTab> createState() => _GeneralTabState();
}

class _GeneralTabState extends State<_GeneralTab> {
  // Local editing controllers and state (applied on Save)
  late final TextEditingController _nameController;
  late final TextEditingController _scenarioController;
  late final TextEditingController _firstMessageController;

  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorModeDefault = false;

  bool _hasUnsavedChanges = false;
  String _statusMessage = '';

  // Snapshot of the group at load time (for reset)
  GroupChat? _loadedGroup;

  @override
  void initState() {
    super.initState();
    _loadFromActiveGroup();
  }

  void _loadFromActiveGroup() {
    final g = widget.chatService.activeGroup;
    _loadedGroup = g;

    if (g != null) {
      _nameController = TextEditingController(text: g.name);
      _scenarioController = TextEditingController(text: g.scenario);
      _firstMessageController = TextEditingController(text: g.firstMessage);
      _turnOrder = g.turnOrder;
      _autoAdvance = g.autoAdvance;
      _directorModeDefault = g.directorMode;
    } else {
      _nameController = TextEditingController(text: '');
      _scenarioController = TextEditingController(text: '');
      _firstMessageController = TextEditingController(text: '');
      _turnOrder = TurnOrder.roundRobin;
      _autoAdvance = false;
      _directorModeDefault = false;
    }

    _hasUnsavedChanges = false;
    _statusMessage = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = true;
        _statusMessage = '';
      });
    }
  }

  void _setTurnOrder(TurnOrder order) {
    if (_turnOrder == order) return;
    setState(() {
      _turnOrder = order;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _setAutoAdvance(bool value) {
    if (_autoAdvance == value) return;
    setState(() {
      _autoAdvance = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _setDirectorModeDefault(bool value) {
    if (_directorModeDefault == value) return;
    setState(() {
      _directorModeDefault = value;
      _hasUnsavedChanges = true;
      _statusMessage = '';
    });
  }

  void _resetToLoaded() {
    if (_loadedGroup == null) return;
    _nameController.text = _loadedGroup!.name;
    _scenarioController.text = _loadedGroup!.scenario;
    _firstMessageController.text = _loadedGroup!.firstMessage;
    setState(() {
      _turnOrder = _loadedGroup!.turnOrder;
      _autoAdvance = _loadedGroup!.autoAdvance;
      _directorModeDefault = _loadedGroup!.directorMode;
      _hasUnsavedChanges = false;
      _statusMessage = 'Reset to last saved values';
    });
  }

  void _saveSettings() {
    final g = widget.chatService.activeGroup;
    if (g == null) return;

    // Apply all edits to the live GroupChat instance (in-memory, immediate effect)
    g.name = _nameController.text.trim().isNotEmpty
        ? _nameController.text.trim()
        : 'Group Chat';
    g.scenario = _scenarioController.text.trim();
    g.firstMessage = _firstMessageController.text.trim();
    g.turnOrder = _turnOrder;
    g.autoAdvance = _autoAdvance;
    g.directorMode = _directorModeDefault;

    // Note: We mutate the live GroupChat object held by the turn manager.
    // Core reads (turnOrder, scenario, firstMessage, flags) pick it up immediately.
    // UI labels (e.g. sidebar header) will reflect on next rebuild of those widgets.
    // (No notifyListeners here to avoid protected-member analyzer diagnostics.)

    setState(() {
      _hasUnsavedChanges = false;
      _statusMessage = 'Settings applied for this session.';
      _loadedGroup = g; // keep snapshot in sync
    });

    // Persist the GroupChat model
    if (widget.groupRepo != null) {
      widget.groupRepo!.save(g);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('General settings saved.'),
          duration: Duration(seconds: 2),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.chatService.activeGroup;

    if (group == null) {
      return const Center(
        child: Text(
          'No active group chat selected.',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  children: [
                    const Icon(Icons.tune, color: Colors.tealAccent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'General — ${group.name}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_hasUnsavedChanges)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'UNSAVED',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amber,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Basic group identity, opening message, and conversation flow rules. All changes apply live after Save.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                ),
                const SizedBox(height: 16),

                // ── Identity ───────────────────────────────────────────────
                _buildSectionHeader('Identity', Icons.label_outline, Colors.tealAccent),
                const SizedBox(height: 8),

                // Group Name
                const Text(
                  'Group Name',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _nameController,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'e.g. The Fellowship',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),

                // Scenario
                const Text(
                  'Scenario',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Group-level scenario override (blank = use first character\'s scenario).',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _scenarioController,
                  maxLines: 4,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'The scene, time period, and situation for this group conversation...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 14),

                // First Message
                const Text(
                  'First Message / Greeting',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Custom opening message shown when the group starts or is reset (blank = use first character\'s greeting).',
                  style: TextStyle(fontSize: 11, color: Colors.white38),
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _firstMessageController,
                  maxLines: 3,
                  minLines: 2,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'The group\'s initial greeting or narration...',
                    hintStyle: const TextStyle(color: Colors.white24, fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF111827),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.white12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Colors.tealAccent),
                    ),
                    contentPadding: const EdgeInsets.all(10),
                  ),
                  onChanged: (_) => _markDirty(),
                ),
                const SizedBox(height: 20),

                // ── Turn Management ────────────────────────────────────────
                _buildSectionHeader('Turn Management', Icons.swap_horiz, Colors.purpleAccent),
                const SizedBox(height: 8),

                const Text(
                  'Turn Order Strategy',
                  style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),

                Row(
                  children: [
                    Expanded(
                      child: _buildTurnStrategyCard(
                        TurnOrder.roundRobin,
                        'Round Robin',
                        'Characters respond in a fixed repeating order. Predictable and fair.',
                        Icons.repeat,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildTurnStrategyCard(
                        TurnOrder.random,
                        'Random',
                        'Any eligible character may speak next. More spontaneous and lively.',
                        Icons.shuffle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Auto-advance
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.play_circle_outline, size: 18, color: Colors.white54),
                          const SizedBox(width: 8),
                          const Text(
                            'Auto-advance',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          const Spacer(),
                          Switch(
                            value: _autoAdvance,
                            activeTrackColor: Colors.greenAccent,
                            onChanged: _setAutoAdvance,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 26),
                        child: Text(
                          'After a character finishes responding, automatically prompt the next speaker. Works with both turn orders and Director Mode.',
                          style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── Director Mode ──────────────────────────────────────────
                _buildSectionHeader('Director Mode Defaults', Icons.movie_creation_outlined, Colors.amberAccent),
                const SizedBox(height: 8),

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF111827),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.visibility, size: 18, color: Colors.white54),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Start this group in Director Mode',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                          Switch(
                            value: _directorModeDefault,
                            activeTrackColor: Colors.amberAccent,
                            onChanged: _setDirectorModeDefault,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Padding(
                        padding: EdgeInsets.only(left: 26),
                        child: Text(
                          'When enabled, entering the group begins in observer/director mode. You steer via the input box while characters respond autonomously. The live toggle is also available in the group sidebar.',
                          style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Persistence note
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.white38),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'These settings are stored with the group definition. Saving here updates the live session immediately. The values are persisted to the database automatically on membership changes (add/remove character) and on session checkpoints.',
                          style: TextStyle(fontSize: 10, color: Colors.white38, height: 1.25),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Save bar ───────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Colors.white12)),
            color: Color(0xFF111827),
          ),
          child: Row(
            children: [
              if (_hasUnsavedChanges)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'UNSAVED',
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.amber,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else if (_statusMessage.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(
                      _statusMessage,
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 12),
                    ),
                  ],
                ),
              const Spacer(),
              if (_hasUnsavedChanges)
                TextButton(
                  onPressed: _resetToLoaded,
                  child: const Text('Reset'),
                ),
              if (_hasUnsavedChanges) const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _hasUnsavedChanges ? _saveSettings : null,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: const Text('Save Changes'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.tealAccent,
                  foregroundColor: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildTurnStrategyCard(
    TurnOrder order,
    String label,
    String description,
    IconData icon,
  ) {
    final isSelected = _turnOrder == order;
    final borderColor = isSelected ? Colors.purpleAccent : Colors.white12;
    final bgColor = isSelected ? const Color(0xFF1F2937) : const Color(0xFF111827);
    final iconColor = isSelected ? Colors.purpleAccent : Colors.white54;
    final textColor = isSelected ? Colors.purpleAccent : Colors.white;

    return GestureDetector(
      onTap: () => _setTurnOrder(order),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: isSelected ? 1.5 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(fontSize: 11, color: Colors.white54, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }
}
