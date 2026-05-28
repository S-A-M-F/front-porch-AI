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

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:path/path.dart' as p;

import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/app_text_field.dart';
import 'package:front_porch_ai/ui/widgets/realism_form_section.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';

/// First-class, menu-driven Group Chat Creator.
///
/// Launched from the sidebar (peer to the character creators).
/// Supports the complete modern GroupChat model at creation time:
/// - Rich member roster builder (search, add, remove, reorder, voices)
/// - Group lorebooks + worlds + inherit flag
/// - Per-character system prompt overrides
/// - Full Realism/Needs + Chaos seeding (baseline + defaultMember)
/// - Director Mode, turn order, auto-advance, opening scene with AI gen
///
/// No layering on the old crusty dialog. Beautiful, first-class experience.
class CreateGroupChatPage extends StatefulWidget {
  const CreateGroupChatPage({super.key});

  @override
  State<CreateGroupChatPage> createState() => _CreateGroupChatPageState();
}



class _CreateGroupChatPageState extends State<CreateGroupChatPage> {
  int _currentStep = 0; // 0 = Members, 1 = Identity, 2 = Opening, 3 = Prompts, 4 = Lore, 5 = Realism, 6 = Review

  // ── Core State ─────────────────────────────────────────────────────
  final List<CharacterCard> _members = [];
  // (reserved for future multi-select voice bulk actions)

  // Identity
  final _nameController = TextEditingController();

  // Behavior
  TurnOrder _turnOrder = TurnOrder.roundRobin;
  bool _autoAdvance = false;
  bool _directorMode = false;

  // Opening
  final _scenarioController = TextEditingController();
  final _firstMessageController = TextEditingController();
  bool _isGeneratingScenario = false;
  bool _isGeneratingFirst = false;

  // Prompts
  final _groupSystemController = TextEditingController();
  final Map<String, String> _characterSystemPrompts = {}; // charId -> prompt

  // Voices (charId -> voiceId or '')
  final Map<String, String> _characterVoices = {};

  // Lore & Worlds
  final List<LorebookEntry> _groupLoreEntries = [];
  final List<String> _worldIds = [];
  bool _inheritCharacterLorebooks = false;
  // (reserved for future entry dialog state if we go non-modal)

  // Realism / Chaos / Needs (group level + per-member seeds)
  bool _realismEnabled = true; // Master group toggle — this is the only realism on/off control
  final Map<String, Map<String, dynamic>> _memberRealismSeeds = {};
  bool _chaosModeEnabled = false;
  bool _chaosNsfwEnabled = false;
  bool _needsSimEnabled = true;

  // Global time/day for the whole group (not per-character — prevents footgun)
  String _globalTimeOfDay = 'morning';
  int _globalDayCount = 1;

  // Search / filter for Members browser
  final _memberSearchController = TextEditingController();
  String _memberSearchQuery = '';
  // (reserved for future folder filter chips in the Members browser)

  // Token-ish estimate (lightweight)
  int _contentTokenEstimate = 0;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_updateEstimates);
    _scenarioController.addListener(_updateEstimates);
    _firstMessageController.addListener(_updateEstimates);
    _groupSystemController.addListener(_updateEstimates);
    _memberSearchController.addListener(() {
      setState(() => _memberSearchQuery = _memberSearchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scenarioController.dispose();
    _firstMessageController.dispose();
    _groupSystemController.dispose();
    _memberSearchController.dispose();
    super.dispose();
  }

  void _updateEstimates() {
    int total = 0;
    total += (_nameController.text.length / 4).ceil();
    total += (_scenarioController.text.length / 4).ceil();
    total += (_firstMessageController.text.length / 4).ceil();
    total += (_groupSystemController.text.length / 4).ceil();
    for (final p in _characterSystemPrompts.values) {
      total += (p.length / 4).ceil();
    }
    for (final e in _groupLoreEntries) {
      total += ((e.name.length + e.key.length + e.content.length) / 4).ceil();
    }
    if (mounted && total != _contentTokenEstimate) {
      setState(() => _contentTokenEstimate = total);
    }
  }

  List<CharacterCard> get _availableCharacters {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final all = repo.characters;
    final memberIds = _members.map(_stableId).toSet();
    return all.where((c) => !memberIds.contains(_stableId(c))).toList();
  }

  List<CharacterCard> get _filteredAvailable {
    final q = _memberSearchQuery;
    var list = _availableCharacters;
    if (q.isNotEmpty) {
      list = list.where((c) =>
          c.name.toLowerCase().contains(q) ||
          c.description.toLowerCase().contains(q) ||
          c.personality.toLowerCase().contains(q)).toList();
    }
    // Simple sort by name
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  String _stableId(CharacterCard c) => c.dbId ?? (c.imagePath != null ? p.basenameWithoutExtension(c.imagePath!) : c.name);

  // ── SECTION NAV ────────────────────────────────────────────────────

  bool get _canLeaveMembersStep => _members.length >= 2;

  // ── MEMBER MANAGEMENT (heart of the experience) ────────────────────

  void _addMember(CharacterCard card) {
    final id = _stableId(card);
    if (_members.any((m) => _stableId(m) == id)) return;
    setState(() {
      _members.add(card);
      // Seed a reasonable neutral realism entry if none exists
      if (!_memberRealismSeeds.containsKey(id)) {
        _memberRealismSeeds[id] = _defaultRealismSeedFor(card);
      }
      if (_nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
      _updateEstimates();
    });
  }

  void _removeMember(String id) {
    setState(() {
      _members.removeWhere((c) => _stableId(c) == id);
      _characterVoices.remove(id);
      _characterSystemPrompts.remove(id);
      _memberRealismSeeds.remove(id);
      if (_members.isNotEmpty && _nameController.text.trim().isEmpty) {
        _nameController.text = _members.map((c) => c.name).join(' & ');
      }
    });
  }

  void _reorderMembers(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final moved = _members.removeAt(oldIndex);
      _members.insert(newIndex, moved);
    });
  }

  void _setVoice(String charId, String? voiceId) {
    setState(() {
      _characterVoices[charId] = voiceId ?? '';
    });
  }

  Map<String, dynamic> _defaultRealismSeedFor(CharacterCard c) {
    // Neutral but alive starting point
    return {
      'affection': 35,
      'trust': 40,
      'emotion': 'neutral',
      'emotionIntensity': 'mild',
      'timeOfDay': 'morning',
      'dayCount': 1,
      'needs': <String, int>{
        'hunger': 70,
        'thirst': 75,
        'rest': 65,
        'social': 60,
        'hygiene': 80,
        'arousal': 20,
        'bladder': 85,
      },
      'enjoysLowHygiene': false,
    };
  }

  void _seedRealismFromCard(String charId) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final card = _members.firstWhere((c) => _stableId(c) == charId, orElse: () => _members.first);
    setState(() {
      _memberRealismSeeds[charId] = _defaultRealismSeedFor(card);
    });
  }

  void _bulkSeedRealism(String mode) {
    setState(() {
      for (final c in _members) {
        final id = _stableId(c);
        if (mode == 'neutral') {
          _memberRealismSeeds[id] = _defaultRealismSeedFor(c);
        } else if (mode == 'highBond') {
          final s = _defaultRealismSeedFor(c);
          s['affection'] = 75;
          s['trust'] = 70;
          s['emotion'] = 'affection';
          s['emotionIntensity'] = 'moderate';
          _memberRealismSeeds[id] = s;
        }
      }
    });
  }

  // ── AI GENERATION (adapted + improved from old dialog) ─────────────

  Future<void> _generateScenario() async {
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final service = llm.activeService;
    if (!service.isReady) {
      _showSnack('LLM backend is not ready. Start KoboldCPP or configure your API first.');
      return;
    }
    setState(() => _isGeneratingScenario = true);

    final names = _members.map((c) => c.name).join(', ');
    final briefs = _members.map((c) {
      final trait = c.personality.isNotEmpty ? c.personality.split('.').first : c.name;
      return '${c.name} ($trait)';
    }).join(', ');

    final prompt = '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
        'Do NOT use <think> tags.]\n\n'
        'Write a brief scenario (1-2 sentences max) for a group roleplay with: $briefs.\n'
        'The scenario should describe WHERE the characters are and WHAT is happening.\n'
        'Use {{user}} to refer to the player when appropriate. Keep it concise.\n\n'
        'SCENARIO: ';

    try {
      final buf = StringBuffer();
      final params = GenerationParams(
        prompt: prompt,
        maxLength: 420,
        temperature: 0.88,
        stopSequences: ['\n\n', 'END', '---', '<think>'],
      );
      await for (final tok in service.generateStream(params)) {
        buf.write(tok);
      }
      var result = _cleanThinkAndMarkers(buf.toString(), prefixMarkers: ['SCENARIO:']);
      if (result.isNotEmpty) {
        _scenarioController.text = result;
      }
    } catch (e) {
      _showSnack('Scenario generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingScenario = false);
    }
  }

  Future<void> _generateFirstMessage() async {
    final llm = Provider.of<LLMProvider>(context, listen: false);
    final service = llm.activeService;
    if (!service.isReady) {
      _showSnack('LLM backend is not ready. Start KoboldCPP or configure your API first.');
      return;
    }
    setState(() => _isGeneratingFirst = true);

    final descriptions = _members.map((c) {
      final persona = c.personality.isNotEmpty ? c.personality : c.description;
      final scen = c.scenario.isNotEmpty ? ' Scenario: ${c.scenario}' : '';
      return '- ${c.name}: $persona$scen';
    }).join('\n');

    final scenarioCtx = _scenarioController.text.trim().isNotEmpty
        ? '\nThe group scenario is: ${_scenarioController.text.trim()}'
        : '';

    final isDirector = _directorMode;
    final prompt = isDirector
        ? '[INSTRUCTIONS: Output ONLY the creative scene text. '
          'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
          'Write a vivid, immersive opening scene (3-5 paragraphs) for a DIRECTOR MODE group roleplay featuring:\n$descriptions$scenarioCtx\n\n'
          'CRITICAL: There is NO user/player present. Characters interact ONLY with each other.\n'
          'Each character MUST have at least 2 lines of dialogue.\n'
          'Characters address and react to EACH OTHER.\n'
          'Use *asterisks* for actions.\n'
          'When done, write "END SCENE" on its own line.\n\n'
          'BEGIN SCENE:\n'
        : '[INSTRUCTIONS: Output ONLY the creative scene text. '
          'Do NOT plan, reason, analyze, or explain. Do NOT use <think> tags. Start writing IMMEDIATELY.]\n\n'
          'Write a vivid, immersive opening message (2-4 paragraphs) for a group roleplay featuring:\n$descriptions$scenarioCtx\n\n'
          'The player ({{user}}) is present. Include natural dialogue from the characters and actions in *asterisks*.\n'
          'Keep it engaging and true to the characters.\n\n'
          'OPENING:\n';

    try {
      final buf = StringBuffer();
      final params = GenerationParams(
        prompt: prompt,
        maxLength: isDirector ? 1800 : 1200,
        temperature: 0.86,
        stopSequences: isDirector ? ['END SCENE', '---', '[END]', '<think>'] : ['\n\n\n', '---', '<think>'],
      );
      await for (final tok in service.generateStream(params)) {
        buf.write(tok);
      }
      var result = _cleanThinkAndMarkers(buf.toString(), prefixMarkers: ['BEGIN SCENE:', 'OPENING:']);
      if (isDirector) {
        result = result.split('\n').where((line) {
          final t = line.trimLeft();
          return !t.startsWith('The user wants') &&
              !t.startsWith('I need to') &&
              !t.startsWith('I will') &&
              !RegExp(r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End)').hasMatch(t);
        }).join('\n').trim();
      }
      if (result.isNotEmpty) {
        _firstMessageController.text = result;
      }
    } catch (e) {
      _showSnack('First message generation failed: $e');
    } finally {
      if (mounted) setState(() => _isGeneratingFirst = false);
    }
  }

  String _cleanThinkAndMarkers(String raw, {List<String> prefixMarkers = const []}) {
    var s = raw
        .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<think>[\s\S]*$', caseSensitive: false), '')
        .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
        .replaceAll('"', '')
        .trim();
    for (final m in prefixMarkers) {
      s = s.replaceAll(RegExp('^$m\\s*', caseSensitive: false), '');
    }
    return s.trim();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── LOREBOOK HELPERS ───────────────────────────────────────────────

  Future<void> _showLoreEntryEditor({LorebookEntry? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final keyCtrl = TextEditingController(text: existing?.key ?? '');
    final contentCtrl = TextEditingController(text: existing?.content ?? '');
    bool enabled = existing?.enabled ?? true;
    bool constant = existing?.constant ?? false;
    int sticky = existing?.stickyDepth ?? 1;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        title: Text(existing == null ? 'Add Group Lore Entry' : 'Edit Group Lore Entry'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppTextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'Entry Name (optional)')),
              const SizedBox(height: 10),
              AppTextField(controller: keyCtrl, decoration: const InputDecoration(labelText: 'Trigger Keys (comma or space separated)')),
              const SizedBox(height: 10),
              AppTextField(controller: contentCtrl, maxLines: 5, decoration: const InputDecoration(labelText: 'Content (injected when triggered)')),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: SwitchListTile(title: const Text('Enabled'), value: enabled, onChanged: (v) => setState(() => enabled = v), dense: true)),
                Expanded(child: SwitchListTile(title: const Text('Constant'), value: constant, onChanged: (v) => setState(() => constant = v), dense: true)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Text('Sticky Depth'),
                Expanded(child: Slider(value: sticky.toDouble(), min: 0, max: 12, divisions: 12, label: sticky.toString(), onChanged: (v) => setState(() => sticky = v.round()))),
                Text(sticky.toString()),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final entry = LorebookEntry(
      name: nameCtrl.text.trim(),
      key: keyCtrl.text.trim(),
      content: contentCtrl.text.trim(),
      enabled: enabled,
      constant: constant,
      stickyDepth: sticky,
    );

    setState(() {
      if (index != null && index >= 0 && index < _groupLoreEntries.length) {
        _groupLoreEntries[index] = entry;
      } else {
        _groupLoreEntries.add(entry);
      }
      _updateEstimates();
    });
  }

  void _deleteLoreEntry(int index) {
    setState(() => _groupLoreEntries.removeAt(index));
  }

  // ── WORLD HELPERS ──────────────────────────────────────────────────

  void _toggleWorld(String worldId) {
    setState(() {
      if (_worldIds.contains(worldId)) {
        _worldIds.remove(worldId);
      } else {
        _worldIds.add(worldId);
      }
    });
  }

  // ── REALISM HELPERS ────────────────────────────────────────────────

  void _updateMemberRealism(String charId, Map<String, dynamic> values) {
    setState(() {
      _memberRealismSeeds[charId] = {
        ...(_memberRealismSeeds[charId] ?? _defaultRealismSeedFor(_members.firstWhere((c) => _stableId(c) == charId))),
        ...values,
      };
    });
  }

  // ── CREATE ─────────────────────────────────────────────────────────

  Future<void> _createGroup() async {
    if (_members.length < 2) {
      _showSnack('A group needs at least 2 characters.');
      setState(() => _currentStep = 0);
      return;
    }
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showSnack('Please give the group a name.');
      setState(() => _currentStep = 1);
      return;
    }

    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final chatService = Provider.of<ChatService>(context, listen: false);
    Provider.of<TtsService>(context, listen: false); // voices already resolved earlier

    // Build per-char system prompts & voices
    final charPrompts = <String, String>{};
    for (final c in _members) {
      final id = _stableId(c);
      final p = _characterSystemPrompts[id];
      if (p != null && p.trim().isNotEmpty) charPrompts[id] = p.trim();
    }

    // Serialize group lorebook
    final lb = Lorebook(entries: List.from(_groupLoreEntries));
    final groupLoreJson = jsonEncode(lb.toJson());

    // Build realism blobs — only when the group master toggle is on.
    // This prevents the serious footgun of mixed per-character realism states.
    String baselineJson = '{}';
    String defaultMemberJson = '{}';

    if (_realismEnabled) {
      final baseline = <String, dynamic>{};
      final defaultMember = <String, dynamic>{'perChar': <String, dynamic>{}};

      for (final c in _members) {
        final id = _stableId(c);
        var seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);

        if (!_needsSimEnabled) {
          seed = Map<String, dynamic>.from(seed)..remove('needs');
        }

        baseline[id] = {
          'affection': (seed['affection'] as num?)?.toInt() ?? 35,
          'trust': (seed['trust'] as num?)?.toInt() ?? 40,
          'emotion': (seed['emotion'] as String?) ?? 'neutral',
          'emotionIntensity': (seed['emotionIntensity'] as String?) ?? 'mild',
          'timeOfDay': _globalTimeOfDay,
          'dayCount': _globalDayCount,
        };

        (defaultMember['perChar'] as Map)[id] = seed;
      }

      baselineJson = jsonEncode(baseline);
      defaultMemberJson = jsonEncode(defaultMember);
    }

    final group = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      characterIds: _members.map(_stableId).toList(),
      turnOrder: _turnOrder,
      autoAdvance: _autoAdvance,
      directorMode: _directorMode,
      firstMessage: _firstMessageController.text.trim(),
      scenario: _scenarioController.text.trim(),
      systemPrompt: _groupSystemController.text.trim(),
      characterSystemPrompts: charPrompts,
      worldIds: List.from(_worldIds),
      groupLorebook: groupLoreJson,
      inheritCharacterLorebooks: _inheritCharacterLorebooks,
      chaosModeEnabled: _chaosModeEnabled,
      chaosNsfwEnabled: _chaosNsfwEnabled,
      baselineRealismState: baselineJson,
      defaultMemberRealismState: defaultMemberJson,
    );

    await groupRepo.save(group);

    // Apply voice overrides (same pattern as the old creator)
    for (final entry in _characterVoices.entries) {
      final card = _members.firstWhere((c) => _stableId(c) == entry.key, orElse: () => _members.first);
      if (entry.value.isNotEmpty && entry.value != card.ttsVoice) {
        card.ttsVoice = entry.value;
        await repo.updateCharacter(card);
      }
    }

    // Auto-enter the beautiful new group
    await chatService.setActiveGroup(group);
    await chatService.startNewChat();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "$name" created!'),
          backgroundColor: const Color(0xFF7C3AED),
        ),
      );
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundOf(context),
      appBar: AppBar(
        backgroundColor: AppColors.surfaceOf(context),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.group_add, color: Color(0xFF7C3AED), size: 22),
            const SizedBox(width: 10),
            const Text('Create Group Chat'),
            const Spacer(),
            _buildStepIndicator(),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _tokenBadge(),
          ),
        ],
      ),
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _currentStep == 0
                ? _buildMembersStep()
                : _currentStep == 1
                ? _buildIdentityStep()
                : _currentStep == 2
                ? _buildOpeningStep()
                : _currentStep == 3
                ? _buildPromptsStep()
                : _currentStep == 4
                ? _buildLoreStep()
                : _currentStep == 5
                ? _buildRealismStep()
                : _buildReviewStep(),
          ),
        ],
      ),
    );
  }



  Widget _buildMembersStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Members', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary(context))),
          const SizedBox(height: 6),
          Text('Build your roster. At least 2 characters required.', style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 16),

          // Current Roster
          Row(
            children: [
              Text('Current Roster (${_members.length})', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
              if (_members.length < 2) ...[
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Minimum 2 required',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (_members.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: AppColors.cardOf(context), borderRadius: BorderRadius.circular(12)),
              child: const Center(child: Text('No members yet — add from the browser below')),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _members.length,
              onReorder: _reorderMembers,
              itemBuilder: (ctx, i) {
                final c = _members[i];
                final id = _stableId(c);
                final voice = _characterVoices[id] ?? c.ttsVoice ?? '';
                return Card(
                  key: ValueKey(id),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: _avatar(c, radius: 22),
                    title: Text(c.name),
                    subtitle: Text('${c.description.isNotEmpty ? c.description.substring(0, c.description.length.clamp(0, 60)) : "No description"}...'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _voiceDropdown(c, voice, (v) => _setVoice(id, v)),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => _removeMember(id)),
                      ],
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 24),
          Text('Add Characters', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary(context))),
          const SizedBox(height: 8),

          // Search
          TextField(
            controller: _memberSearchController,
            decoration: InputDecoration(
              hintText: 'Search available characters...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: AppColors.surfaceContainerOf(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),

          // Available grid (compact)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _filteredAvailable.map((c) {
              return InkWell(
                onTap: () => _addMember(c),
                child: Container(
                  width: 140,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.cardOf(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.borderOf(context)),
                  ),
                  child: Row(
                    children: [
                      _avatar(c, radius: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(c.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                      const Icon(Icons.add, size: 18, color: Color(0xFF7C3AED)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_filteredAvailable.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('No more characters available.', style: TextStyle(color: AppColors.textTertiary(context))),
            ),

          _buildNavButtons(currentStep: 0),
        ],
      ),
    );
  }

  Widget _voiceDropdown(CharacterCard c, String current, ValueChanged<String?> onChanged) {
    final tts = Provider.of<TtsService>(context, listen: false);
    final voices = tts.activeVoices;
    return DropdownButton<String>(
      value: current.isNotEmpty ? current : null,
      hint: const Text('Voice'),
      isDense: true,
      items: [
        const DropdownMenuItem(value: '', child: Text('Default')),
        ...voices.map((v) => DropdownMenuItem(value: v.id, child: Text(v.name, overflow: TextOverflow.ellipsis))),
      ],
      onChanged: onChanged,
    );
  }

  Widget _tinyAvatar(CharacterCard c) {
    return CircleAvatar(
      radius: 12,
      backgroundImage: c.imagePath != null ? FileImage(File(c.imagePath!)) : null,
      child: c.imagePath == null ? const Icon(Icons.person, size: 14) : null,
    );
  }

  Widget _avatar(CharacterCard c, {double radius = 20}) {
    return CircleAvatar(
      radius: radius,
      backgroundImage: c.imagePath != null ? FileImage(File(c.imagePath!)) : null,
      child: c.imagePath == null ? Icon(Icons.person, size: radius * 0.9) : null,
    );
  }

  Widget _buildIdentityStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Identity & Behavior', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          AppTextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Group Name', hintText: 'e.g. The Ember Circle'),
            style: TextStyle(color: AppColors.textPrimary(context), fontSize: 18),
          ),
          const SizedBox(height: 24),
          Text('Turn Order', style: TextStyle(color: AppColors.textSecondary(context))),
          const SizedBox(height: 8),
          SegmentedButton<TurnOrder>(
            segments: const [
              ButtonSegment(value: TurnOrder.roundRobin, label: Text('Round Robin'), icon: Icon(Icons.repeat)),
              ButtonSegment(value: TurnOrder.random, label: Text('Random'), icon: Icon(Icons.shuffle)),
            ],
            selected: {_turnOrder},
            onSelectionChanged: (v) => setState(() => _turnOrder = v.first),
          ),
          const SizedBox(height: 20),
          SwitchListTile(
            title: const Text('Auto-Advance'),
            subtitle: const Text('Characters respond one after another automatically'),
            value: _autoAdvance,
            onChanged: (v) => setState(() => _autoAdvance = v),
            activeThumbColor: const Color(0xFF7C3AED),
          ),
          SwitchListTile(
            title: Row(children: const [Icon(Icons.movie_creation, color: Colors.amberAccent, size: 18), SizedBox(width: 6), Text('Director Mode')]),
            subtitle: const Text('Characters chat autonomously — you direct the scene (no player present)'),
            value: _directorMode,
            onChanged: (v) => setState(() => _directorMode = v),
            activeThumbColor: Colors.amberAccent,
          ),

          _buildNavButtons(currentStep: 1),
        ],
      ),
    );
  }

  Widget _buildOpeningStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Opening Scene', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
              TextButton.icon(
                onPressed: _isGeneratingScenario ? null : _generateScenario,
                icon: _isGeneratingScenario ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, color: Colors.amberAccent),
                label: Text(_isGeneratingScenario ? 'Generating...' : 'Generate Scenario'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(controller: _scenarioController, maxLines: 3, decoration: const InputDecoration(hintText: 'The group is...')),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(child: Text('First Message (optional)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
              TextButton.icon(
                onPressed: _isGeneratingFirst ? null : _generateFirstMessage,
                icon: _isGeneratingFirst ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.auto_awesome, color: Colors.amberAccent),
                label: Text(_isGeneratingFirst ? 'Generating...' : 'Generate'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppTextField(controller: _firstMessageController, maxLines: 8, decoration: const InputDecoration(hintText: 'The scene opens with...')),
          const SizedBox(height: 12),
          if (_directorMode)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: const Text('Director Mode active: generated first message will be a self-contained group scene with no {{user}}.', style: TextStyle(color: Colors.amberAccent)),
            ),

          _buildNavButtons(currentStep: 2),
        ],
      ),
    );
  }

  Widget _buildPromptsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Group System Prompt', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          AppTextField(controller: _groupSystemController, maxLines: 6, decoration: const InputDecoration(hintText: 'Global instructions for this group...')),
          const SizedBox(height: 24),
          Text('Per-Character Overrides (optional)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ..._members.map((c) {
            final id = _stableId(c);
            final ctrl = TextEditingController(text: _characterSystemPrompts[id] ?? '');
            ctrl.addListener(() {
              _characterSystemPrompts[id] = ctrl.text;
            });
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [_avatar(c, radius: 16), const SizedBox(width: 8), Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600))]),
                    const SizedBox(height: 6),
                    AppTextField(controller: ctrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Extra instructions only for this character in this group')),
                  ],
                ),
              ),
            );
          }),
          if (_members.isEmpty) const Text('Add members first to configure per-character prompts.'),

          _buildNavButtons(currentStep: 3),
        ],
      ),
    );
  }

  Widget _buildLoreStep() {
    final worldRepo = Provider.of<WorldRepository>(context);
    final allWorlds = worldRepo.worlds;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text('Group Lorebook', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600))),
              ElevatedButton.icon(onPressed: () => _showLoreEntryEditor(), icon: const Icon(Icons.add), label: const Text('Add Entry')),
            ],
          ),
          const SizedBox(height: 8),
          if (_groupLoreEntries.isEmpty)
            const Text('No group lore entries yet. These take highest priority in prompts.')
          else
            ..._groupLoreEntries.asMap().entries.map((e) {
              final i = e.key;
              final entry = e.value;
              return ListTile(
                title: Text(entry.name.isNotEmpty ? entry.name : entry.key),
                subtitle: Text(entry.content.length > 80 ? '${entry.content.substring(0, 80)}...' : entry.content),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: const Icon(Icons.edit), onPressed: () => _showLoreEntryEditor(existing: entry, index: i)),
                  IconButton(icon: const Icon(Icons.delete), onPressed: () => _deleteLoreEntry(i)),
                ]),
              );
            }),
          const SizedBox(height: 24),
          SwitchListTile(
            title: const Text('Inherit character & world lorebooks'),
            subtitle: const Text('When on, member cards and their attached worlds contribute lore in addition to the group lorebook above.'),
            value: _inheritCharacterLorebooks,
            onChanged: (v) => setState(() => _inheritCharacterLorebooks = v),
          ),
          const SizedBox(height: 16),
          Text('Linked Worlds', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ..._worldIds.map((wid) {
                final w = allWorlds.firstWhere((ww) => ww.name == wid, orElse: () => World(name: wid, lorebook: Lorebook(entries: const [])));
                return Chip(
                  label: Text(w.name),
                  onDeleted: () => _toggleWorld(wid),
                );
              }),
              OutlinedButton.icon(
                onPressed: () async {
                  final chosen = await showDialog<World>(
                    context: context,
                    builder: (ctx) => SimpleDialog(
                      title: const Text('Link a World'),
                      children: allWorlds.map((w) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(ctx, w),
                        child: Text(w.name),
                      )).toList(),
                    ),
                  );
                  if (chosen != null) _toggleWorld(chosen.name);
                },
                icon: const Icon(Icons.public),
                label: const Text('Link World'),
              ),
            ],
          ),

          _buildNavButtons(currentStep: 4),
        ],
      ),
    );
  }

  Widget _buildRealismStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group Chaos — styled nicely like the Realism card (independent of Realism)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.casino, size: 18, color: Color(0xFFFFD166)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Group Chaos (Chance Time)',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Switch(
                      value: _chaosModeEnabled,
                      activeThumbColor: const Color(0xFFFFD166),
                      onChanged: (v) => setState(() => _chaosModeEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Random narrative events during roleplay. Can include NSFW events when enabled.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                if (_chaosModeEnabled) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Include NSFW events', style: TextStyle(fontSize: 13)),
                      const Spacer(),
                      Switch(
                        value: _chaosNsfwEnabled,
                        activeThumbColor: const Color(0xFFFFD166),
                        onChanged: (v) => setState(() => _chaosNsfwEnabled = v),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // === Master Realism Toggle (the only on/off control for the whole group) ===
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
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
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                    Switch(
                      value: _realismEnabled,
                      activeThumbColor: Colors.tealAccent,
                      onChanged: (v) => setState(() => _realismEnabled = v),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Tracks emotions, short/long-term bond, trust, arousal, fixation, and needs simulation for every member. Only takes effect when not in Director Mode.',
                  style: TextStyle(fontSize: 12, color: Colors.white54),
                ),
                if (!_realismEnabled)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'All realism features (bond, trust, emotion, needs, fixation, chaos pressure, etc.) are disabled for this group while the master toggle is off.',
                      style: TextStyle(fontSize: 11, color: Colors.white38, fontStyle: FontStyle.italic),
                    ),
                  ),

                // Needs Simulation gated under Realism
                if (_realismEnabled) ...[
                  const SizedBox(height: 14),
                  Divider(color: Colors.white12, height: 1),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.battery_std, size: 18, color: Colors.tealAccent),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Needs Simulation',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                      ),
                      Switch(
                        value: _needsSimEnabled,
                        activeThumbColor: Colors.tealAccent,
                        onChanged: (v) => setState(() => _needsSimEnabled = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Hunger, bladder, energy, social, fun, hygiene, comfort. Only relevant when Realism is enabled.',
                    style: TextStyle(fontSize: 11, color: Colors.white54),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Global Time & Day (group level, not per-character)
          if (_realismEnabled) ...[
            Row(
              children: [
                Icon(Icons.schedule, color: Colors.amberAccent, size: 18),
                const SizedBox(width: 8),
                Text('Group Time & Day', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.amberAccent)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Time of Day', style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                        const SizedBox(height: 6),
                        DropdownButton<String>(
                          value: _globalTimeOfDay,
                          isExpanded: true,
                          dropdownColor: const Color(0xFF1F2937),
                          onChanged: (v) => setState(() => _globalTimeOfDay = v!),
                          items: const [
                            DropdownMenuItem(value: 'dawn', child: Text('Dawn')),
                            DropdownMenuItem(value: 'morning', child: Text('Morning')),
                            DropdownMenuItem(value: 'late_morning', child: Text('Late Morning')),
                            DropdownMenuItem(value: 'afternoon', child: Text('Afternoon')),
                            DropdownMenuItem(value: 'evening', child: Text('Evening')),
                            DropdownMenuItem(value: 'night', child: Text('Night')),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Day Number', style: TextStyle(fontSize: 12, color: AppColors.textSecondary(context))),
                        const SizedBox(height: 6),
                        TextField(
                          controller: TextEditingController(text: _globalDayCount.toString()),
                          keyboardType: TextInputType.number,
                          onChanged: (v) {
                            final n = int.tryParse(v);
                            if (n != null && n >= 1) setState(() => _globalDayCount = n);
                          },
                          decoration: const InputDecoration(
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // Per-member initial state configuration — only shown when realism is enabled for the group
          if (_realismEnabled) ...[
            Row(
              children: [
                Text('Initial Realism State per Member', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(onPressed: () => _bulkSeedRealism('neutral'), child: const Text('Neutral')),
                TextButton(onPressed: () => _bulkSeedRealism('highBond'), child: const Text('High Bond')),
              ],
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const Text('Add members first to configure their starting realism values.')
            else
              ..._members.map((c) {
                final id = _stableId(c);
                final seed = _memberRealismSeeds[id] ?? _defaultRealismSeedFor(c);
                return Card(
                  key: ValueKey('realism-card-$id'),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    leading: _avatar(c, radius: 18),
                    title: Text(c.name),
                    subtitle: Text('${seed['emotion']} • Bond ${seed['affection']} / Trust ${seed['trust']}'),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: RealismFormSection(
                          key: ValueKey('realism-form-$id'),
                          enabled: true,
                          onEnabledChanged: (_) {}, // controlled by the group master toggle above
                          timeOfDay: (seed['timeOfDay'] as String?) ?? 'morning',
                          onTimeOfDayChanged: (v) => _updateMemberRealism(id, {'timeOfDay': v}),
                          dayCount: (seed['dayCount'] as num?)?.toInt() ?? 1,
                          onDayCountChanged: (v) => _updateMemberRealism(id, {'dayCount': v}),
                          shortTermBond: (seed['affection'] as num?)?.toInt() ?? 35,
                          onShortTermBondChanged: (v) => _updateMemberRealism(id, {'affection': v}),
                          longTermBond: (seed['trust'] as num?)?.toInt() ?? 40,
                          onLongTermBondChanged: (v) => _updateMemberRealism(id, {'trust': v}),
                          trustLevel: (seed['trust'] as num?)?.toInt() ?? 40,
                          onTrustLevelChanged: (v) => _updateMemberRealism(id, {'trust': v}),
                          emotion: (seed['emotion'] as String?) ?? 'neutral',
                          onEmotionChanged: (v) => _updateMemberRealism(id, {'emotion': v}),
                          emotionIntensity: (seed['emotionIntensity'] as String?) ?? 'mild',
                          onEmotionIntensityChanged: (v) => _updateMemberRealism(id, {'emotionIntensity': v}),
                          // These are group-level concepts (we already have the master Chaos toggle at the top of the section).
                          // Forcing them off here prevents duplicate/confusing per-character toggles.
                          nsfwCooldownEnabled: false,
                          onNsfwCooldownChanged: (_) {},
                          chaosModeEnabled: false,
                          onChaosModeChanged: (_) {},
                          needsSimEnabled: _needsSimEnabled,
                          onNeedsSimChanged: (_) {},
                          // When global Needs is on, this lets the widget show "Enjoys low hygiene"
                          // under Optional Features even though we hide the Needs master row itself.
                          // Hide the global-only toggles entirely from per-character optional features.
                          showNsfwCooldownToggle: false,
                          showChaosToggle: false,
                          showNeedsToggle: false,
                          showTimeAndDay: false,
                          showMasterEnabledToggle: false,
                          // Enjoys low hygiene will now naturally appear under Optional Features
                          // when the global Needs Simulation is enabled (because needsSimEnabled is passed above).
                          enjoysLowHygiene: false,
                          onEnjoysLowHygieneChanged: (_) {},
                          currentTask: (seed['currentTask'] as String?) ?? '',
                          onCurrentTaskChanged: (v) => _updateMemberRealism(id, {'currentTask': v}),
                        ),
                      ),

                      TextButton(onPressed: () => _seedRealismFromCard(id), child: const Text('Reset to character defaults')),
                    ],
                  ),
                );
              }),
          ] else ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Realism is disabled for this group. No bond, trust, emotion, needs, or fixation tracking will occur.',
                style: TextStyle(fontSize: 13, color: Colors.white54),
              ),
            ),
          ],

          _buildNavButtons(currentStep: 5),
        ],
      ),
    );
  }

  Widget _buildReviewStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Review', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.cardOf(context), borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_nameController.text.isEmpty ? 'Unnamed Group' : _nameController.text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(spacing: 6, children: _members.map((c) => Chip(label: Text(c.name))).toList()),
                const SizedBox(height: 12),
                Text('${_members.length} members • ${_groupLoreEntries.length} lore entries • ${_worldIds.length} worlds'),
                if (_chaosModeEnabled) const Text('Chaos Mode enabled', style: TextStyle(color: Color(0xFFFFD166))),
                if (_directorMode) const Text('Director Mode', style: TextStyle(color: Colors.amberAccent)),
                Text(
                  _realismEnabled ? 'Realism Engine: Enabled for group' : 'Realism Engine: Disabled for group',
                  style: TextStyle(color: _realismEnabled ? Colors.tealAccent : Colors.white54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createGroup,
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7C3AED), minimumSize: const Size.fromHeight(52)),
            icon: const Icon(Icons.check),
            label: const Text('Create Group & Enter Chat', style: TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _createGroup,
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
            child: const Text('Create Only (don\'t enter chat yet)'),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  STEP INDICATOR (matches Manual Character Creator style)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildStepIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _stepDot(0, 'Members'),
        _stepLine(),
        _stepDot(1, 'Identity'),
        _stepLine(),
        _stepDot(2, 'Opening'),
        _stepLine(),
        _stepDot(3, 'Prompts'),
        _stepLine(),
        _stepDot(4, 'Lore'),
        _stepLine(),
        _stepDot(5, 'Realism'),
        _stepLine(),
        _stepDot(6, 'Review'),
      ],
    );
  }

  Widget _stepDot(int step, String label) {
    final isActive = _currentStep >= step;
    final isCurrent = _currentStep == step;

    final dotColor = isActive
        ? const Color(0xFF7C3AED)
        : AppColors.surfaceContainerOf(context);

    final borderColor = isCurrent
        ? AppColors.textPrimary(context)
        : AppColors.borderOf(context);

    final numberOrCheckColor = isActive
        ? Colors.white
        : AppColors.textTertiary(context);

    final labelColor = isActive
        ? AppColors.textSecondary(context)
        : AppColors.textTertiary(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: dotColor,
            border: isCurrent
                ? Border.all(color: borderColor, width: 2)
                : Border.all(color: AppColors.borderOf(context).withValues(alpha: 0.3)),
          ),
          child: Center(
            child: isActive && !isCurrent
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : Text(
                    '${step + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      color: numberOrCheckColor,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
          ),
        ),
      ],
    );
  }

  Widget _stepLine() {
    return Container(
      width: 24,
      height: 2,
      margin: const EdgeInsets.only(bottom: 14),
      color: AppColors.borderOf(context).withValues(alpha: 0.35),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //  NAVIGATION BUTTONS (matches Manual Character Creator)
  // ═══════════════════════════════════════════════════════════════

  Widget _buildNavButtons({required int currentStep}) {
    final nextLabels = [
      'Identity & Behavior',
      'Opening Scene',
      'Prompt Engineering',
      'Lorebooks & Worlds',
      'Realism & Chaos',
      'Review & Create',
    ];

    final nextText = currentStep < nextLabels.length
        ? 'Next: ${nextLabels[currentStep]}'
        : 'Create Group';

    final canGoNext = _canAdvanceFromStep(currentStep);

    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentStep > 0)
              SizedBox(
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => setState(() => _currentStep = currentStep - 1),
                  icon: const Icon(Icons.arrow_back, size: 18),
                  label: const Text('Back', style: TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textSecondary(context),
                    side: BorderSide(color: AppColors.borderOf(context)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            if (currentStep > 0) const SizedBox(width: 16),
            SizedBox(
              width: 280,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: canGoNext
                    ? () {
                        if (currentStep == 0 && !_canLeaveMembersStep) {
                          _showSnack('A group needs at least 2 characters.');
                          return;
                        }
                        if (currentStep < 6) {
                          setState(() => _currentStep = currentStep + 1);
                        } else {
                          _createGroup();
                        }
                      }
                    : null,
                icon: Icon(
                  currentStep >= 5 ? Icons.check : Icons.arrow_forward,
                  size: 20,
                ),
                label: Text(nextText, style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor: AppColors.borderOf(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _canAdvanceFromStep(int step) {
    if (step == 0) return _canLeaveMembersStep;
    if (step == 6) return _members.length >= 2 && _nameController.text.trim().isNotEmpty;
    return true;
  }

  Widget _tokenBadge() {
    final color = _contentTokenEstimate > 6000 ? Colors.redAccent : _contentTokenEstimate > 3000 ? Colors.orangeAccent : AppColors.textTertiary(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
      child: Text('~$_contentTokenEstimate tokens', style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
