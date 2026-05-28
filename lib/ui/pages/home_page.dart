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

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:url_launcher/url_launcher.dart';
import 'package:image/image.dart' as img;

import 'package:front_porch_ai/database/database.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:front_porch_ai/ui/theme/app_colors.dart';

// Barrel imports (preferred during major refactor per project guidelines)
import 'package:front_porch_ai/models/models.dart';
import 'package:front_porch_ai/services/services.dart';
import 'package:front_porch_ai/ui/widgets/widgets.dart';

// Specific pages, dialogs, and internal services not in barrels
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/pages/character_creator_page.dart';
import 'package:front_porch_ai/ui/pages/story_home_view.dart';
import 'package:front_porch_ai/ui/dialogs/byaf_import_dialog.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';
import 'package:front_porch_ai/services/byaf_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String? _activeFolderId; // null = top level view
  List<String> _folderStack = []; // navigation breadcrumb for subfolder back
  SearchScope _searchScope = SearchScope.currentFolder;
  final _searchController = TextEditingController();

  // Multi-select for group creation
  bool _isSelecting = false;
  // Multi-select for folder organization
  bool _isOrganizing = false;
  final Set<String> _selectedCharacterIds = {}; // imagePath-based IDs

  // Sorting
  String _sortMode = 'name'; // 'name', 'recent', 'importDate', 'messages'
  final Map<String, DateTime> _lastActivityCache = {};
  final Map<String, int> _messageCountCache = {};

  // Grid scale
  double _gridScale = 300.0;

  // Porch Stories mode toggle
  bool _showStories = false;

  // Scroll controller for the character grid (visible scrollbar)
  final ScrollController _gridScrollController = ScrollController();

  // Keep strong reference to active InAppBrowser instances.
  // The flutter_inappwebview package (especially on macOS/Windows desktop)
  // requires the Dart InAppBrowser subclass to stay alive while the native
  // browser window exists, otherwise closing the window can crash the app.
  CharacterBrowser? _activeBrowser;

  @override
  void initState() {
    super.initState();
    final storage = Provider.of<StorageService>(context, listen: false);
    _sortMode = storage.sortMode;
    _gridScale = storage.gridScale;
    // StorageService._init() is async — settings may not be loaded yet.
    // Wait for init to complete so persisted values are reflected.
    storage.initialized.then((_) {
      if (!mounted) return;
      setState(() {
        _sortMode = storage.sortMode;
        _gridScale = storage.gridScale;
      });
    });
    Future.microtask(() => _refreshLastActivityCache());
  }

  /// Resolve a character [imagePath] (basename or full path) to a [File].
  File _resolveCharImage(String imagePath) {
    final storage = Provider.of<StorageService>(context, listen: false);
    return storage.resolveCharacterImage(imagePath);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen for model-ready events from KoboldService
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      kobold.removeListener(_onKoboldUpdate);
      kobold.addListener(_onKoboldUpdate);
    } catch (_) {
      // KoboldService might not be in the provider tree
    }
    // Listen for CharacterRepository changes to refresh cache after characters load
    try {
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      charRepo.removeListener(_onCharactersChanged);
      charRepo.addListener(_onCharactersChanged);
    } catch (_) {}
  }

  void _onCharactersChanged() {
    if (!mounted) return;
    _refreshLastActivityCache();
  }

  void _onKoboldUpdate() {
    if (!mounted) return;
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      if (kobold.consumeModelReady()) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 20),
                const SizedBox(width: 8),
                const Text('Model loaded and ready!'),
              ],
            ),
            backgroundColor: AppColors.surfaceContainerOf(context),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      setState(() {}); // Rebuild to update status bar
    } catch (_) {}
  }

  /// Query the DB to build caches for last activity time and message count per character.
  Future<void> _refreshLastActivityCache() async {
    try {
      final db = await AppDatabase.instance();
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);

      // Get counts and activity from DB
      final msgCounts = await db.getMessageCountsPerCharacter();
      final lastActivity = await db.getLastActivityPerCharacter();

      // Map from character DB id (UUID) → message count
      final newMsgCount = <String, int>{};
      for (final card in charRepo.characters) {
        if (card.dbId != null && msgCounts.containsKey(card.dbId)) {
          newMsgCount[card.dbId!] = msgCounts[card.dbId!]!;
        }
      }

      // Map from character DB id (UUID) → last activity time
      final newCache = <String, DateTime>{};
      for (final card in charRepo.characters) {
        if (card.dbId != null && lastActivity.containsKey(card.dbId)) {
          newCache[card.dbId!] = lastActivity[card.dbId!]!;
        }
      }

      if (mounted) {
        setState(() {
          _lastActivityCache
            ..clear()
            ..addAll(newCache);
          _messageCountCache
            ..clear()
            ..addAll(newMsgCount);
        });
      }
    } catch (e) {
      debugPrint('Error refreshing activity cache: $e');
      if (mounted) setState(() {});
    }
  }

  String _getCharacterIdFromCard(CharacterCard card) {
    if (card.imagePath != null) {
      return path.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  void _toggleSelectMode() {
    setState(() {
      _isSelecting = !_isSelecting;
      _isOrganizing = false;
      if (!_isSelecting) _selectedCharacterIds.clear();
    });
  }

  void _toggleOrganizeMode() {
    setState(() {
      _isOrganizing = !_isOrganizing;
      _isSelecting = false;
      if (!_isOrganizing) _selectedCharacterIds.clear();
    });
  }

  void _toggleSelect(CharacterCard character) {
    final id = character.imagePath != null
        ? path.basenameWithoutExtension(character.imagePath!)
        : character.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
    setState(() {
      if (_selectedCharacterIds.contains(id)) {
        _selectedCharacterIds.remove(id);
        if (_selectedCharacterIds.isEmpty) {
          _isSelecting = false;
          _isOrganizing = false;
        }
      } else {
        _selectedCharacterIds.add(id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _isOrganizing = false;
      _selectedCharacterIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _gridScrollController.dispose();

    // Close any open character browser to avoid native window leaks / crashes
    // on app exit while the inappwebview window is still visible.
    _activeBrowser?.close();
    _activeBrowser = null;

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<CharacterRepository, FolderService, GroupChatRepository>(
      builder: (context, repo, folderService, groupRepo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (repo.characters.isEmpty && groupRepo.groups.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'Get started by creating a new character!',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.color
                        ?.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Provider.of<AppState>(
                        context,
                        listen: false,
                      ).setIndex(1),
                      icon: const Icon(Icons.add_circle_outline),
                      label: const Text('Create New'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _importCharacter(context),
                      icon: const Icon(Icons.download),
                      label: const Text('Import Card'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CharacterCreatorPage(),
                        ),
                      ),
                      icon: const Icon(Icons.auto_awesome),
                      label: const Text('AI Create'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _folderImportCharacters(context),
                      icon: const Icon(Icons.library_add),
                      label: const Text('Bulk Import'),
                      style: _buttonStyle(),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () => _importByaf(context),
                      icon: const Icon(Icons.archive_outlined),
                      label: const Text('Import BYAF'),
                      style: _buttonStyle(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openBrowser(context),
                      icon: const Icon(Icons.public, color: Colors.blueAccent),
                      label: const Text(
                        'AI Character Cards',
                        style: TextStyle(color: Colors.blueAccent),
                      ),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => _showChubWarning(context),
                      icon: const Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Chub.ai',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // If Porch Stories mode is active, show the stories view
        if (_showStories) {
          return _wrapWithStatusBar(
            context,
            Column(
              children: [
                // Radio toggle
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24.0,
                    vertical: 16.0,
                  ),
                  child: Row(children: [_buildModeToggle(), const Spacer()]),
                ),
                const Expanded(child: StoryHomeView()),
              ],
            ),
          );
        }

        return _wrapWithStatusBar(
          context,
          CharacterCardGrid(
            searchQuery: _searchQuery,
            searchScope: _searchScope,
            activeFolderId: _activeFolderId,
            sortMode: _sortMode,
            lastActivityCache: _lastActivityCache,
            messageCountCache: _messageCountCache,
            gridScale: _gridScale,
            isSelecting: _isSelecting,
            isOrganizing: _isOrganizing,
            selectedCharacterIds: _selectedCharacterIds,
            searchController: _searchController,
            gridScrollController: _gridScrollController,
            repo: repo,
            folderService: folderService,
            groupRepo: groupRepo,
            modeToggle: _buildModeToggle(),
            onTapCharacter: _handleTapCharacter,
            onTapGroup: _handleTapGroup,
            onExportGroup: _exportGroup,
            onExtractCharacters: _extractCharactersFromGroup,
            onToggleSelect: _toggleSelect,
            onToggleSelectMode: _toggleSelectMode,
            onToggleOrganizeMode: _toggleOrganizeMode,
            onContextMenuAction: _handleContextMenuAction,
            onImport: _handleImport,
            onOpenBrowser: _handleOpenBrowser,
            onAcceptFolderDrop: _handleAcceptFolderDrop,
            onFolderDialogAction: _handleFolderDialogAction,
            onFolderTap: _handleFolderTap,
            onFolderNavigateBack: _handleFolderNavigateBack,
            onCancelSelection: _cancelSelection,
            onCreateGroup: _handleCreateGroup,
            onMoveToFolder: _handleMoveToFolder,
            onSortChanged: _handleSortChanged,
            onGridScaleChanged: _handleGridScaleChanged,
            onGridScaleChangeEnd: _handleGridScaleChangeEnd,
            onSearchScopeChanged: _handleSearchScopeChanged,
            onSearchQueryChanged: _handleSearchQueryChanged,
            onResolveCharImage: _resolveCharImage,
            onDeleteGroup: _handleDeleteGroup,
            onAfterNavigateBack: _refreshLastActivityCache,
          ),
        );
      },
    );
  }

  Widget _buildModeToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerOf(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderOf(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _modeButton(
            'Chats',
            Icons.chat_bubble_outline,
            !_showStories,
            () => setState(() => _showStories = false),
          ),
          _modeButton(
            'Porch Stories',
            Icons.auto_stories,
            _showStories,
            () => setState(() => _showStories = true),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(
    String label,
    IconData icon,
    bool isActive,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? AppColors.resolve(
                  context,
                  Colors.amber.shade800.withValues(alpha: 0.25),
                  Colors.amber.withValues(alpha: 0.15),
                )
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isActive
              ? Border.all(
                  color: AppColors.resolve(
                    context,
                    Colors.amber.shade700.withValues(alpha: 0.5),
                    Colors.amber.shade700.withValues(alpha: 0.4),
                  ),
                )
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isActive
                  ? AppColors.resolve(
                      context,
                      Colors.amber.shade400,
                      Colors.amber.shade800,
                    )
                  : AppColors.iconSecondary(context),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: isActive
                    ? AppColors.textPrimary(context)
                    : AppColors.textSecondary(context),
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _wrapWithStatusBar(BuildContext context, Widget content) {
    String status = '';
    try {
      final kobold = Provider.of<KoboldService>(context, listen: false);
      status = kobold.modelLoadingStatus;
    } catch (_) {}

    if (status.isEmpty) return content;

    return Column(
      children: [
        Expanded(child: content),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          decoration: BoxDecoration(
            color: AppColors.surfaceContainerOf(context),
            border: Border(top: BorderSide(color: AppColors.borderOf(context))),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                status,
                style: TextStyle(color: AppColors.textSecondary(context), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 4,
                  backgroundColor: AppColors.resolve(
                    context,
                    const Color(0xFF333333),
                    AppColors.surfaceContainerLight,
                  ),
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  /// Shows a dialog letting the user choose which saved session to resume.
  /// Returns the session ID, '__new__' for a new chat, or null if cancelled.
  Future<String?> _showSessionPickerDialog(
    BuildContext context,
    List<Map<String, dynamic>> sessions,
    String characterName,
  ) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceOf(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.blueAccent, width: 0.5),
        ),
        title: Row(
          children: [
            const Icon(
              Icons.chat_bubble_outline,
              color: Colors.blueAccent,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Continue a chat with $characterName?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary(context),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          height: 350,
          child: Column(
            children: [
              // New chat button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(ctx).pop('__new__'),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Start New Chat'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.greenAccent,
                    side: BorderSide(color: Colors.greenAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(color: AppColors.borderOf(context)),
              const SizedBox(height: 4),
              // Session list
              Expanded(
                child: ListView.builder(
                  itemCount: sessions.length,
                  itemBuilder: (context, index) {
                    final s = sessions[index];
                    final date = s['date'] as DateTime;
                    final dateStr =
                        '${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")} ${date.hour}:${date.minute.toString().padLeft(2, "0")}';
                    final messageCount = s['message_count'] ?? 0;
                    final userMessageCount = s['user_message_count'] ?? 0;
                    final isBranch = s['parent_session'] != null;
                    final description = s['session_description'] as String?;

                    return Card(
                      color: AppColors.cardOf(context),
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: ListTile(
                        leading: isBranch
                            ? const Icon(
                                Icons.call_split,
                                size: 20,
                                color: Colors.blueAccent,
                              )
                            : Icon(
                                Icons.chat,
                                size: 20,
                                color: AppColors.textTertiary(context),
                              ),
                        title: Text(
                          s['preview'],
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textPrimary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary(context),
                              ),
                            ),
                            if (description != null && description.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                description,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary(context),
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3), width: 0.5),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.forum, size: 10, color: AppColors.resolve(context, Colors.blueAccent.shade200, Colors.blueAccent.shade700)),
                                      const SizedBox(width: 4),
                                      Text(
                                        '$messageCount total',
                                        style: TextStyle(fontSize: 10, color: AppColors.resolve(context, Colors.blueAccent.shade200, Colors.blueAccent.shade700), fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                                if (userMessageCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3), width: 0.5),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.person, size: 10, color: AppColors.resolve(context, Colors.greenAccent.shade200, Colors.greenAccent.shade700)),
                                        const SizedBox(width: 4),
                                        Text(
                                          '$userMessageCount user',
                                          style: TextStyle(fontSize: 10, color: AppColors.resolve(context, Colors.greenAccent.shade200, Colors.greenAccent.shade700), fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                            if (isBranch) ...[
                              const SizedBox(height: 4),
                              Text(
                                '↳ Branched at message #${(s['fork_index'] ?? 0) + 1}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary(context),
                                ),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => Navigator.of(ctx).pop(s['id']),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary(context)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── CharacterCardGrid Callback Handlers ────────────────────────

  Future<void> _handleTapCharacter(CharacterCard character) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final charId = character.dbId ?? _getCharacterIdFromCard(character);
    final sessions = await chatService.getSessionsForId(charId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await _showSessionPickerDialog(
        context,
        sessions,
        character.name,
      );
      if (selectedId == null || !context.mounted) return;
      await chatService.setActiveCharacter(character);
      if (selectedId != '__new__') {
        await chatService.loadSession(selectedId);
      }
      if (selectedId == '__new__') {
        await chatService.startNewChat();
      }
    } else {
      await chatService.setActiveCharacter(character);
    }
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
      _refreshLastActivityCache();
    }
  }

  Future<void> _handleTapGroup(GroupChat group) async {
    final chatService = Provider.of<ChatService>(context, listen: false);
    final groupId = 'group_${group.id}';
    final sessions = await chatService.getSessionsForId(groupId);

    if (!context.mounted) return;

    if (sessions.length > 1) {
      final selectedId = await _showSessionPickerDialog(
        context,
        sessions,
        group.name,
      );
      if (selectedId == null || !context.mounted) return;
      await chatService.setActiveGroup(group);
      if (selectedId != '__new__') {
        await chatService.loadSession(selectedId);
      }
      if (selectedId == '__new__') {
        await chatService.startNewChat();
      }
    } else {
      await chatService.setActiveGroup(group);
    }
    if (context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ChatPage()),
      );
      _refreshLastActivityCache();
    }
  }

  void _handleContextMenuAction(String action, CharacterCard character) {
    switch (action) {
      case 'edit':
        _editCharacter(context, character);
        break;
      case 'duplicate':
        _duplicateCharacter(context, character);
        break;
      case 'export':
        _exportCharacter(context, character);
        break;
      case 'remove_folder':
        final folderService = Provider.of<FolderService>(context, listen: false);
        if (_activeFolderId != null && character.imagePath != null) {
          folderService.removeFromFolder(_activeFolderId!, character.imagePath!);
        }
        break;
      case 'delete':
        _confirmDeleteCharacter(context, character);
        break;
    }
  }

  void _handleImport(String source) {
    switch (source) {
      case 'cards':
        _importCharacter(context);
        break;
      case 'folder':
        _folderImportCharacters(context);
        break;
      case 'byaf':
        _importByaf(context);
        break;
    }
  }

  void _handleOpenBrowser(String site) {
    switch (site) {
      case 'aicc':
        _openBrowser(context);
        break;
      case 'chub':
        _showChubWarning(context);
        break;
    }
  }

  Future<void> _handleAcceptFolderDrop(
    CharacterCard character,
    CharacterFolder folder,
  ) async {
    final folderService = Provider.of<FolderService>(context, listen: false);
    if (character.imagePath != null) {
      await folderService.addToFolder(folder.id, character.imagePath!);
    }
  }

  void _handleFolderDialogAction(
    FolderDialogAction action, {
    CharacterFolder? folder,
    String? parentId,
  }) {
    final folderService = Provider.of<FolderService>(context, listen: false);
    switch (action) {
      case FolderDialogAction.create:
        _createFolder(context, folderService, parentId: parentId);
        break;
      case FolderDialogAction.rename:
        if (folder != null) _renameFolder(context, folder, folderService);
        break;
      case FolderDialogAction.delete:
        if (folder != null) _deleteFolder(context, folder, folderService);
        break;
    }
  }

  void _handleFolderTap(CharacterFolder folder) {
    setState(() {
      if (_activeFolderId != null) {
        _folderStack.add(_activeFolderId!);
      }
      _activeFolderId = folder.id;
    });
  }

  void _handleFolderNavigateBack() {
    setState(() {
      if (_folderStack.isNotEmpty) {
        _activeFolderId = _folderStack.removeLast();
      } else {
        _activeFolderId = null;
      }
    });
  }

  // Group chat creation is now exclusively via the dedicated CreateGroupChatPage
  // (persistent sidebar button, first-class menu-driven experience).
  // The old monolithic dialog + bottom-bar selection path has been removed.
  void _handleCreateGroup(Set<String> selectedIds) {
    // No-op.
  }

  void _handleMoveToFolder(Set<String> selectedIds) {
    final repo = Provider.of<CharacterRepository>(context, listen: false);
    final folderService = Provider.of<FolderService>(context, listen: false);
    _showMoveToFolderDialog(context, repo, folderService);
  }

  void _handleSortChanged(String mode) {
    setState(() => _sortMode = mode);
    Provider.of<StorageService>(context, listen: false).setSortMode(mode);
  }

  void _handleGridScaleChanged(double scale) {
    setState(() => _gridScale = scale);
  }

  void _handleGridScaleChangeEnd(double scale) {
    Provider.of<StorageService>(context, listen: false).setGridScale(scale);
  }

  void _handleSearchScopeChanged(SearchScope scope) {
    setState(() => _searchScope = scope);
  }

  void _handleSearchQueryChanged(String query) {
    setState(() => _searchQuery = query);
  }

  void _handleDeleteGroup(GroupChat group) {
    _confirmDeleteGroup(context, group);
  }

  void _confirmDeleteGroup(BuildContext context, GroupChat group) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Text(
          'Delete Group',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete group "${group.name}"?\n\nThe characters themselves will NOT be deleted.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final groupRepo = Provider.of<GroupChatRepository>(
                context,
                listen: false,
              );
              final cloudSyncService = Provider.of<CloudSyncService>(
                context,
                listen: false,
              );
              await groupRepo.delete(group.id, cloudSyncService: cloudSyncService);
              // No post-delete snackbar for groups (character delete shows one via the outer context)
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Group Creation Dialog ──────────────────────────────────────

  void _showMoveToFolderDialog(
    BuildContext context,
    CharacterRepository repo,
    FolderService folderService,
  ) {
    final folders = folderService.folders.toList()
      ..sort((a, b) {
        final pathA = folderService.getFolderPath(a.id).toLowerCase();
        final pathB = folderService.getFolderPath(b.id).toLowerCase();
        return pathA.compareTo(pathB);
      });

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.blueAccent, width: 0.5),
        ),
        title: Row(
          children: [
            const Icon(Icons.drive_file_move, color: Colors.blueAccent),
            const SizedBox(width: 12),
            Text(
              'Move ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (folders.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'No folders yet. Create one below.',
                      style: TextStyle(color: Colors.white54),
                    ),
                  ),
                ...folders.map((folder) {
                  final folderPath = folderService.getFolderPath(folder.id);
                  final isSubfolder = folder.parentId != null;
                  return ListTile(
                    leading: Icon(
                      isSubfolder ? Icons.subdirectory_arrow_right : Icons.folder,
                      color: Colors.amberAccent,
                    ),
                    title: Text(
                      folderPath,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${folder.characterPaths.length} characters',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    hoverColor: Colors.white10,
                    onTap: () async {
                      Navigator.pop(ctx);
                      await _moveSelectedToFolder(
                        context,
                        folder.id,
                        repo,
                        folderService,
                      );
                    },
                  );
                }),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(
                  Icons.create_new_folder,
                  color: Colors.greenAccent,
                ),
                title: const Text(
                  'New Folder',
                  style: TextStyle(color: Colors.greenAccent),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                hoverColor: Colors.white10,
                onTap: () async {
                  Navigator.pop(ctx);
                  final name = await _promptFolderName(context);
                  if (name != null && name.isNotEmpty && context.mounted) {
                    final folder = await folderService.createFolder(name);
                    await _moveSelectedToFolder(
                      context,
                      folder.id,
                      repo,
                      folderService,
                    );
                  }
                },
              ),
            ],
          ),
        ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ],
      ),
    );
  }

  Future<String?> _promptFolderName(BuildContext context) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Folder name'),
          onSubmitted: (val) => Navigator.pop(ctx, val),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveSelectedToFolder(
    BuildContext context,
    String folderId,
    CharacterRepository repo,
    FolderService folderService,
  ) async {
    // Resolve selected IDs back to imagePaths
    for (final id in _selectedCharacterIds) {
      final card = repo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (card?.imagePath != null) {
        await folderService.addToFolder(folderId, card!.imagePath!);
      }
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Moved ${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} to folder',
          ),
        ),
      );
    }
    _cancelSelection();
  }



  // (old group creator dialog variables and body fully removed — 2026 overhaul)

  // ─── Folder Actions ─────────────────────────────────────────────

  void _createFolder(
    BuildContext context,
    FolderService folderService, {
    String? parentId,
  }) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: Text(
          parentId != null ? 'New Subfolder' : 'New Folder',
          style: const TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Folder name...',
            hintStyle: TextStyle(color: Colors.white38),
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              folderService.createFolder(value.trim(), parentId: parentId);
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.createFolder(
                  controller.text.trim(),
                  parentId: parentId,
                );
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _renameFolder(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
  ) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text(
          'Rename Folder',
          style: TextStyle(color: Colors.white),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) {
              folderService.renameFolder(folder.id, value.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.renameFolder(folder.id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber.shade700,
            ),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(
    BuildContext context,
    CharacterFolder folder,
    FolderService folderService,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Text(
          'Delete Folder',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Delete "${folder.name}"?\n\nCharacters inside will NOT be deleted — they\'ll return to the top level.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              folderService.deleteFolder(folder.id);
              Navigator.pop(ctx);
              if (_activeFolderId == folder.id) {
                setState(() {
                  if (_folderStack.isNotEmpty) {
                    _activeFolderId = _folderStack.removeLast();
                  } else {
                    _activeFolderId = null;
                  }
                });
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Character Actions ──────────────────────────────────────────

  ButtonStyle _buttonStyle() {
    return ElevatedButton.styleFrom(
      backgroundColor: AppColors.resolve(
        context,
        Colors.white.withValues(alpha: 0.1),
        Colors.black.withValues(alpha: 0.05),
      ),
      foregroundColor: AppColors.textPrimary(context),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppColors.resolve(context, Colors.white24, Colors.black26)),
      ),
    );
  }

  void _confirmDeleteCharacter(BuildContext context, CharacterCard character) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              'Delete Character',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to delete "${character.name}"?\n\nThis will permanently remove the character card and its image file. This action cannot be undone.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              final repo = Provider.of<CharacterRepository>(
                context,
                listen: false,
              );
              final worldRepo = Provider.of<WorldRepository>(
                context,
                listen: false,
              );
              final storageService = Provider.of<StorageService>(
                context,
                listen: false,
              );
              final cloudSyncService = Provider.of<CloudSyncService>(
                context,
                listen: false,
              );
              await repo.deleteCharacter(
                character,
                worldRepo: worldRepo,
                chatsDir: storageService.chatsDir,
                cloudSyncService: cloudSyncService,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${character.name} has been deleted.'),
                    backgroundColor: Colors.red.shade800,
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

  Future<void> _editCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => EditCharacterPage(character: character),
      ),
    );
    // No loadCharacters() needed here — updateCharacter() already updates the
    // in-memory list and calls notifyListeners(). Calling loadCharacters() was
    // re-reading outdated in-memory extensions from the cache and overwriting
    // the freshly-saved values.
  }

  Future<void> _duplicateCharacter(
    BuildContext context,
    CharacterCard character,
  ) async {
    try {
      await Provider.of<CharacterRepository>(
        context,
        listen: false,
      ).duplicateCharacter(character);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Character duplicated successfully.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to duplicate: $e')));
      }
    }
  }

  Future<void> _importCharacter(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
      allowMultiple: true,
    );

    if (result == null || result.files.isEmpty) return;
    if (!context.mounted) return;

    final files = result.files
        .where((f) => f.path != null)
        .map((f) => File(f.path!))
        .toList();

    if (files.isEmpty) return;

    // Single file: check if this is a Front Porch Group Card first (novel format)
    if (files.length == 1) {
      final file = files.first;
      try {
        final groupService = GroupCardService();
        final groupCard = await groupService.readGroupCard(file.path);

        if (groupCard != null) {
          // This is a Group Card PNG — do the special group import
          await _importGroupCard(context, file, groupCard);
          return;
        }

        // Normal character card
        final worldRepo = Provider.of<WorldRepository>(context, listen: false);
        final repo = Provider.of<CharacterRepository>(context, listen: false);
        final card = await repo.importCharacter(file, worldRepo: worldRepo);
        if (context.mounted && card != null) {
          // Show tag dialog
          final tags = await TagDialog.show(context, card);
          if (tags != null && context.mounted) {
            card.tags = List.from(tags);
            await repo.updateCharacter(card);
          }
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Character imported successfully!')),
            );
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
      return;
    }

    // Multiple files: use bulk import with progress dialog
    _runBulkImport(context, files);
  }

  Future<void> _importByaf(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['byaf'],
      allowMultiple: false,
    );

    if (result == null ||
        result.files.isEmpty ||
        result.files.first.path == null) {
      return;
    }
    if (!context.mounted) return;

    final filePath = result.files.first.path!;
    final byafService = ByafService();

    try {
      // Parse the .byaf archive
      final preview = await byafService.parseByaf(filePath);

      if (!context.mounted) return;

      // Show preview dialog
      final result2 = await showDialog<ByafImportResult>(
        context: context,
        builder: (context) => ByafImportDialog(preview: preview),
      );

      if (result2 == null || !result2.confirmed || !context.mounted) return;

      // Convert to CharacterCard
      final card = byafService.toCharacterCard(preview);

      // Save as PNG (with image if available)
      final storageService = Provider.of<StorageService>(
        context,
        listen: false,
      );
      final pngPath = await byafService.saveCharacterPng(
        card,
        charactersDirPath: storageService.charactersDir.path,
      );

      // Now use V2CardService to embed character data into the PNG
      final v2Service = V2CardService();
      await v2Service.saveCardAsPng(card, pngPath, preview.extractedImagePath);

      // Import via CharacterRepository (reads PNG metadata + inserts into DB)
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final importedCard = await repo.importCharacter(
        File(pngPath),
        worldRepo: worldRepo,
      );

      // Import chat history if requested
      if (result2.importChatHistory &&
          preview.messages.isNotEmpty &&
          importedCard != null) {
        final db = await AppDatabase.instance();
        await byafService.importChatHistory(db, preview, importedCard);
      }

      if (context.mounted && importedCard != null) {
        final chatNote =
            result2.importChatHistory && preview.messages.isNotEmpty
            ? ' with ${preview.messages.length} chat messages'
            : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported "${importedCard.name}" from Backyard AI$chatNote!',
            ),
            backgroundColor: Colors.green.shade700,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to import .byaf: $e')));
      }
    }
  }

  Future<void> _folderImportCharacters(BuildContext context) async {
    final dirPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select folder containing character PNGs',
    );

    if (dirPath == null) return;
    if (!context.mounted) return;

    // Scan the folder for PNG files
    final dir = Directory(dirPath);
    final files = <File>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
        files.add(entity);
      }
    }

    if (files.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No PNG files found in the selected folder.'),
          ),
        );
      }
      return;
    }

    _runBulkImport(context, files);
  }

  /// Shared bulk import with progress dialog — used by both multi-select and folder import.
  void _runBulkImport(BuildContext context, List<File> files) {
    bool cancelled = false;
    int currentCount = 0;
    int totalCount = files.length;
    int importedCount = 0;
    int failedCount = 0;
    String currentName = '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Start the import on first build
            if (currentCount == 0 && !cancelled) {
              final repo = Provider.of<CharacterRepository>(
                context,
                listen: false,
              );
              final worldRepo = Provider.of<WorldRepository>(
                context,
                listen: false,
              );
              repo
                  .importCharacters(
                    files,
                    worldRepo: worldRepo,
                    isCancelled: () => cancelled,
                    onProgress: (current, total, name, error) {
                      if (ctx.mounted) {
                        setDialogState(() {
                          currentCount = current;
                          currentName = name;
                          if (error == null) {
                            importedCount++;
                          } else {
                            failedCount++;
                          }
                        });
                      }
                    },
                  )
                  .then((summary) {
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (context.mounted) {
                      final msg = failedCount > 0
                          ? 'Imported $importedCount character${importedCount == 1 ? '' : 's'} ($failedCount failed)'
                          : 'Imported $importedCount character${importedCount == 1 ? '' : 's'} successfully!';
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(msg)));
                    }
                  });
            }

            final progress = totalCount > 0 ? currentCount / totalCount : 0.0;

            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Colors.blueAccent.withValues(alpha: 0.5),
                ),
              ),
              title: const Row(
                children: [
                  Icon(Icons.library_add, color: Colors.blueAccent),
                  SizedBox(width: 12),
                  Text(
                    'Bulk Import',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 12,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(
                          Colors.blueAccent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status text
                    Text(
                      currentCount == 0
                          ? 'Starting import...'
                          : 'Importing $currentCount of $totalCount...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Current file name
                    if (currentName.isNotEmpty)
                      Text(
                        currentName,
                        style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 16),
                    // Counts row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _bulkStatChip(
                          Icons.check_circle,
                          Colors.green,
                          '$importedCount imported',
                        ),
                        const SizedBox(width: 16),
                        _bulkStatChip(
                          Icons.error,
                          Colors.redAccent,
                          '$failedCount failed',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    cancelled = true;
                  },
                  child: Text(
                    cancelled ? 'Cancelling...' : 'Cancel',
                    style: TextStyle(
                      color: cancelled ? Colors.white38 : Colors.redAccent,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _bulkStatChip(IconData icon, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: color, fontSize: 13)),
      ],
    );
  }

  Future<void> _exportCharacter(BuildContext context, character) async {
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Character Card',
      fileName: '${character.name}.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.png')) {
        outputFile += '.png';
      }

      try {
        final v2Service = V2CardService();
        await v2Service.saveCardAsPng(
          character,
          outputFile,
          character.imagePath,
        );

        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Exported to $outputFile')));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
        }
      }
    }
  }

  /// Import a Group Card PNG (the novel Front Porch format).
  /// Creates all member characters (with full collision handling) + the group.
  Future<void> _importGroupCard(
    BuildContext context,
    File file,
    GroupCard groupCard,
  ) async {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
    final worldRepo = Provider.of<WorldRepository>(context, listen: false);

    final importedMemberIds = <String>[];
    int successCount = 0;
    int failCount = 0;

    // Use the high-fidelity raw member data when available
    final rawMembers = groupCard.rawMemberData.isNotEmpty
        ? groupCard.rawMemberData
        : groupCard.members.map((c) => c.toJson()).toList();

    for (final raw in rawMembers) {
      File? tempPng;
      try {
        // Create a temporary valid character card PNG from the raw portable data
        final memberJson = {
          'spec': 'chara_card_v2',
          'spec_version': '2.0',
          'data': raw,
        };
        final jsonStr = jsonEncode(memberJson);
        final b64 = base64Encode(utf8.encode(jsonStr));

        final tempDir = await Directory.systemTemp.createTemp('fp_group_member_');

        // Check if this member has an embedded avatar from a previous Group Card export
        final avatarBase64 = raw['avatar_base64'] as String? ??
            (raw['data'] as Map?)?['avatar_base64'] as String?;

        if (avatarBase64 != null && avatarBase64.isNotEmpty) {
          // Use the real avatar that was embedded on export
          final avatarBytes = base64Decode(avatarBase64);
          var avatarImg = img.decodePng(avatarBytes) ?? img.decodeImage(avatarBytes);

          if (avatarImg != null) {
            // Embed the character metadata into the real avatar image
            avatarImg.textData ??= {};
            avatarImg.textData!['chara'] = b64;

            tempPng = File(path.join(tempDir.path, 'member_${DateTime.now().millisecondsSinceEpoch}.png'));
            await tempPng.writeAsBytes(img.encodePng(avatarImg));
          }
        }

        // Fallback: create a colored placeholder if no embedded avatar (foreign group cards, or old exports)
        if (tempPng == null) {
          final memberName = (raw['name'] ?? raw['data']?['name'] ?? 'Character').toString();

          // Deterministic pleasant color from the name
          final hash = memberName.codeUnits.fold(0, (a, b) => a + b);
          final r = (80 + (hash % 120)).clamp(60, 200);
          final g = (70 + ((hash * 7) % 130)).clamp(60, 200);
          final b = (90 + ((hash * 13) % 110)).clamp(70, 190);

          final placeholder = img.Image(width: 400, height: 600);
          img.fill(placeholder, color: img.ColorRgb8(r, g, b));

          placeholder.textData ??= {};
          placeholder.textData!['chara'] = b64;

          tempPng = File(path.join(tempDir.path, 'member_${DateTime.now().millisecondsSinceEpoch}.png'));
          await tempPng.writeAsBytes(img.encodePng(placeholder));
        }

        final imported = await charRepo.importCharacter(tempPng, worldRepo: worldRepo);
        if (imported != null && imported.imagePath != null) {
          // Use the *stable* character ID (image basename) that the rest of the
          // app (ChatService, group resolution, etc.) expects. Storing dbId was wrong.
          final stableId = path.basenameWithoutExtension(imported.imagePath!);
          importedMemberIds.add(stableId);
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        debugPrint('Failed to import one group member: $e');
        failCount++;
      } finally {
        // Clean temp (best effort)
        try {
          if (tempPng != null && await tempPng.exists()) {
            await tempPng.delete();
            await tempPng.parent.delete(recursive: true);
          }
        } catch (_) {}
      }
    }

    if (importedMemberIds.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Group import failed — no members could be created.')),
        );
      }
      return;
    }

    // Create the group itself
    // Seed portable group realism/needs defaults from the imported card if present
    // (enables split-to-solo characters to inherit evolved bond/trust/emotion/etc from the group).
    final importedRealism = groupCard.extensions?['realism_state'];

    // Path B compatibility: Prefer the new top-level `character_system_prompts` key in the Group Card.
    // Fall back to promoting from the legacy location inside `realism_state` (for cards exported before this change).
    Map<String, String> importedCharPrompts = groupCard.characterSystemPrompts;
    if (importedCharPrompts.isEmpty && importedRealism is Map) {
      final legacy = importedRealism['characterSystemPrompts'] ?? importedRealism['character_system_prompts'];
      if (legacy is Map) {
        importedCharPrompts = legacy.map((k, v) => MapEntry(k.toString(), (v ?? '').toString()));
      }
    }

    final newGroup = GroupChat(
      id: 'group_${DateTime.now().millisecondsSinceEpoch}',
      name: groupCard.name,
      characterIds: importedMemberIds,
      turnOrder: groupCard.turnOrder == 'random' ? TurnOrder.random : TurnOrder.roundRobin,
      autoAdvance: groupCard.autoAdvance,
      directorMode: groupCard.directorMode,
      firstMessage: groupCard.firstMessage,
      scenario: groupCard.scenario,
      systemPrompt: groupCard.systemPrompt,
      // Full v31/v32 + baseline support: restore exactly what was exported.
      // We deliberately restore the *baseline* seed here (not evolved state).
      groupLorebook: groupCard.groupLorebook ?? '',
      worldIds: groupCard.worldIds,
      inheritCharacterLorebooks: groupCard.inheritCharacterLorebooks,
      chaosModeEnabled: groupCard.chaosModeEnabled,
      chaosNsfwEnabled: groupCard.chaosNsfwEnabled,
      baselineRealismState: groupCard.baselineRealismState.isNotEmpty
          ? groupCard.baselineRealismState
          : '{}',
      characterSystemPrompts: importedCharPrompts,
    );

    // Carry per-char objectives from the imported Group Card for first-load seeding.
    if (groupCard.memberObjectives.isNotEmpty) {
      // Store in the group's state so ChatService can seed the objectives table
      // the first time the imported group is entered (one-time).
      try {
        final currentState = jsonDecode(newGroup.defaultMemberRealismState);
        final mutable = (currentState is Map)
            ? Map<String, dynamic>.from(currentState)
            : <String, dynamic>{};
        mutable['imported_member_objectives'] = groupCard.memberObjectives;
        newGroup.defaultMemberRealismState = jsonEncode(mutable);
      } catch (_) {}
    }

    await groupRepo.save(newGroup);

    if (context.mounted) {
      final msg = failCount > 0
          ? 'Imported group "${groupCard.name}" with $successCount members ($failCount failed).'
          : 'Imported group "${groupCard.name}" with $successCount members!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.purpleAccent.shade700,
        ),
      );
    }
  }

  /// Extract all members of a group as independent standalone characters.
  /// This creates fresh copies so you can use them in 1:1 chats, heavily customize
  /// them, or put them in other groups — without affecting the original group.
  ///
  /// Especially valuable after importing someone else's Group Card.
  Future<void> _extractCharactersFromGroup(GroupChat group) async {
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);

    // Resolve current full CharacterCard objects for the members
    final memberCards = charRepo.characters
        .where((c) => group.characterIds.contains(_getCharacterIdFromCard(c)))
        .toList();

    if (memberCards.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No characters found in this group.')),
        );
      }
      return;
    }

    int extracted = 0;
    for (final member in memberCards) {
      try {
        await charRepo.duplicateCharacter(member);
        extracted++;
      } catch (e) {
        debugPrint('Failed to extract ${member.name}: $e');
      }
    }

    if (context.mounted) {
      final msg = extracted == 1
          ? 'Extracted 1 character as an individual.'
          : 'Extracted $extracted characters as individuals.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          backgroundColor: Colors.teal.shade700,
        ),
      );
    }
  }

  /// Export a group as a single self-contained PNG "Group Card".
  /// This is a Front Porch novel format (fpa_group chunk) that bundles every
  /// member character (full data + lorebooks + extensions) plus group settings.
  Future<void> _exportGroup(GroupChat group) async {
    final context = this.context; // capture from StatefulWidget

    // Resolve full CharacterCard objects for the members (for embedding + collage)
    final charRepo = Provider.of<CharacterRepository>(context, listen: false);
    final memberCards = <CharacterCard>[];
    for (final id in group.characterIds) {
      final match = charRepo.characters
          .where((c) => _getCharacterIdFromCard(c) == id)
          .firstOrNull;
      if (match != null) memberCards.add(match);
    }

    if (memberCards.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot export empty group')),
        );
      }
      return;
    }

    // Embed current avatar images as base64 for perfect roundtrip fidelity
    // (mirrors the logic the import side already uses).
    final rawMembersWithAvatars = <Map<String, dynamic>>[];

    // Snapshot per-character objectives for portable Group Card
    final memberObjectives = <String, List<Map<String, dynamic>>>{};
    try {
      final db = Provider.of<AppDatabase>(context, listen: false);
      for (final card in memberCards) {
        final charId = _getCharacterIdFromCard(card);
        final objs = await db.getObjectivesForCharacter(charId);
        if (objs.isNotEmpty) {
          memberObjectives[charId] = objs.map((o) => {
            'objective': o.objective,
            'tasks': o.tasks,
            'isPrimary': o.isPrimary,
            'active': o.active,
            'checkFrequency': o.checkFrequency,
            'injectionDepth': o.injectionDepth,
          }).toList();
        }
      }
    } catch (_) {
      // Best effort for objectives snapshot
    }

    for (final card in memberCards) {
      final raw = Map<String, dynamic>.from(card.toJson());

      if (card.imagePath != null && card.imagePath!.isNotEmpty) {
        try {
          final imageFile = File(card.imagePath!);
          if (await imageFile.exists()) {
            final bytes = await imageFile.readAsBytes();
            raw['avatar_base64'] = base64Encode(bytes);
          }
        } catch (_) {
          // Best effort — don't fail the whole export over one avatar.
        }
      }

      rawMembersWithAvatars.add(raw);
    }

    final safeName = group.name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    String? outputFile = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Group Card',
      fileName: '$safeName.group.png',
      type: FileType.custom,
      allowedExtensions: ['png'],
    );

    if (outputFile != null) {
      if (!outputFile.endsWith('.png')) {
        outputFile += '.png';
      }

      try {
        // Build the portable GroupCard (full member snapshots)
        // Critical: For the realism snapshot we send the *immutable baseline seed*,
        // not the evolved state from chatting.
        final portable = GroupCard(
          name: group.name,
          members: memberCards,
          rawMemberData: rawMembersWithAvatars, // includes avatar_base64 for fidelity
          turnOrder: group.turnOrder.name,
          autoAdvance: group.autoAdvance,
          directorMode: group.directorMode,
          firstMessage: group.firstMessage,
          scenario: group.scenario,
          systemPrompt: group.systemPrompt,
          characterSystemPrompts: group.characterSystemPrompts,
          chaosModeEnabled: group.chaosModeEnabled,
          chaosNsfwEnabled: group.chaosNsfwEnabled,
          groupLorebook: group.groupLorebook,
          worldIds: group.worldIds,
          inheritCharacterLorebooks: group.inheritCharacterLorebooks,
          baselineRealismState: group.baselineRealismState,
          memberObjectives: memberObjectives,
          extensions: (group.baselineRealismState.isNotEmpty &&
                  group.baselineRealismState != '{}')
              ? {'realism_state': jsonDecode(group.baselineRealismState)}
              : null,
        );

        final service = GroupCardService();
        // No custom source image → auto-collage from member avatars (the magic path)
        await service.saveGroupCardAsPng(portable, outputFile);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Group card exported to $outputFile')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Group export failed: $e')),
          );
        }
      }
    }
  }

  // ─── Browser Integrations ──────────────────────────────────────

  Future<void> _openBrowser(BuildContext context) async {
    // Skip embedded browser on Linux due to WPE WebKit rendering issues
    if (Platform.isLinux) {
      _showBrowserFallbackDialog(
        context,
        'https://aicharactercards.com/',
        'AI Character Cards',
      );
      return;
    }

    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);

      Future<void> handleDownloadUrl(String url) async {
        debugPrint('AG_DEBUG: Download card intercepted: $url');

        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final httpResponse = await request.close();

          final bytes = <int>[];
          await for (final chunk in httpResponse) {
            bytes.addAll(chunk);
          }

          httpClient.close();

          final storageService = Provider.of<StorageService>(
            context,
            listen: false,
          );
          final charDir = storageService.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }

          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty &&
              uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);

          final card = await repo.importCharacter(
            tempFile,
            worldRepo: worldRepo,
          );

          // Show tag dialog after download
          if (card != null && context.mounted) {
            final tags = await TagDialog.show(context, card);
            if (tags != null && context.mounted) {
              card.tags = List.from(tags);
              await repo.updateCharacter(card);
            }
          }

          messenger.showSnackBar(
            SnackBar(
              content: const Text('Character card downloaded and imported!'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        } catch (e) {
          debugPrint('AG_DEBUG: Download error: $e');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Download failed: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      }

      _activeBrowser = CharacterBrowser(
        onDownload: handleDownloadUrl,
        onClosed: () => _activeBrowser = null,
      );

      await _activeBrowser!.openUrlRequest(
        urlRequest: URLRequest(url: WebUri('https://aicharactercards.com/')),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            hideUrlBar: false,
            toolbarTopBackgroundColor: const Color(0xFF1F2937),
          ),
        ),
      );
    } catch (e) {
      debugPrint('AG_DEBUG: Browser failed to launch: $e');
      if (context.mounted) {
        _showBrowserFallbackDialog(
          context,
          'https://aicharactercards.com/',
          'AI Character Cards',
        );
      }
    }
  }

  Future<void> _openChubBrowser(BuildContext context) async {
    // Skip embedded browser on Linux due to WPE WebKit rendering issues
    if (Platform.isLinux) {
      _showBrowserFallbackDialog(context, 'https://chub.ai/', 'Chub.ai');
      return;
    }

    try {
      final repo = Provider.of<CharacterRepository>(context, listen: false);
      final worldRepo = Provider.of<WorldRepository>(context, listen: false);
      final messenger = ScaffoldMessenger.of(context);

      Future<void> handleChubDownload(String url) async {
        debugPrint('AG_DEBUG: Chub download intercepted: $url');

        try {
          final httpClient = HttpClient();
          final request = await httpClient.getUrl(Uri.parse(url));
          final httpResponse = await request.close();

          final bytes = <int>[];
          await for (final chunk in httpResponse) {
            bytes.addAll(chunk);
          }

          httpClient.close();

          final storageService = Provider.of<StorageService>(
            context,
            listen: false,
          );
          final charDir = storageService.charactersDir;
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }

          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty &&
              uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'chub_card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);

          final card = await repo.importCharacter(
            tempFile,
            worldRepo: worldRepo,
          );

          // Show tag dialog — Chub.ai cards likely have tags already
          if (card != null && context.mounted) {
            final tags = await TagDialog.show(context, card);
            if (tags != null && context.mounted) {
              card.tags = List.from(tags);
              await repo.updateCharacter(card);
            }
          }

          messenger.showSnackBar(
            SnackBar(
              content: const Text('Chub character downloaded and imported!'),
              backgroundColor: Colors.green.shade800,
            ),
          );
        } catch (e) {
          debugPrint('AG_DEBUG: Chub download error: $e');
          messenger.showSnackBar(
            SnackBar(
              content: Text('Chub download failed: $e'),
              backgroundColor: Colors.red.shade800,
            ),
          );
        }
      }

      _activeBrowser = CharacterBrowser(
        onDownload: handleChubDownload,
        onClosed: () => _activeBrowser = null,
      );

      await _activeBrowser!.openUrlRequest(
        urlRequest: URLRequest(url: WebUri('https://chub.ai/')),
        settings: InAppBrowserClassSettings(
          browserSettings: InAppBrowserSettings(
            hideUrlBar: false,
            toolbarTopBackgroundColor: const Color(0xFF1F2937),
          ),
        ),
      );
    } catch (e) {
      debugPrint('AG_DEBUG: Chub browser failed to launch: $e');
      if (context.mounted) {
        _showBrowserFallbackDialog(context, 'https://chub.ai/', 'Chub.ai');
      }
    }
  }

  void _showBrowserFallbackDialog(
    BuildContext context,
    String url,
    String siteName,
  ) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text(
              'Browser Rendering Issue',
              style: TextStyle(color: Colors.white),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The embedded browser is having trouble rendering on your system. This is a known issue with certain Linux GPU configurations.',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 16),
            const Text(
              'You can still download characters manually:',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '1. Click "Open in Browser" below\n2. Download character .png files\n3. Use "Import Card" button to add them',
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Open in Browser'),
            onPressed: () async {
              Navigator.pop(dialogContext);
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              } else {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Could not open $siteName'),
                      backgroundColor: Colors.red.shade800,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showChubWarning(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.redAccent,
              size: 28,
            ),
            SizedBox(width: 8),
            Text(
              '⚠️ TRAVELER, BEWARE ⚠️',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  'assets/images/eye_bleach.jpg',
                  height: 200,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'You are about to enter Chub.ai — a land where content '
                'moderation is more of a suggestion than a rule.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You WILL encounter NSFW and potentially NSFL content. '
                'There is no "safe" section. There is no lifeguard on duty. '
                'Eye bleach is strongly advised — and may still not be enough.',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontSize: 13,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Browse at your own discretion. '
                'We are not responsible for what you find... '
                'or what finds you. 👁️',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Nope, I Choose Life',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogContext);
              _openChubBrowser(context);
            },
            child: const Text('I Fear Nothing. Proceed.'),
          ),
        ],
      ),
    );
  }
}

// Custom InAppBrowser for character downloads
class CharacterBrowser extends InAppBrowser {
  final Future<void> Function(String url) onDownload;
  final VoidCallback? onClosed;

  CharacterBrowser({
    required this.onDownload,
    this.onClosed,
  });

  @override
  Future<NavigationActionPolicy>? shouldOverrideUrlLoading(
    NavigationAction navigationAction,
  ) async {
    final url = navigationAction.request.url.toString();

    // Intercept character card downloads
    if (url.endsWith('.png') ||
        url.contains('download_card_image=true') ||
        url.contains('/download') ||
        url.contains('characterhub.org/characters/download')) {
      debugPrint('AG_DEBUG: Intercepted download URL: $url');
      await onDownload(url);
      return NavigationActionPolicy.CANCEL;
    }

    return NavigationActionPolicy.ALLOW;
  }

  @override
  void onLoadError(Uri? url, int code, String message) {
    debugPrint('AG_DEBUG: Browser load error: $message');
  }

  @override
  void onExit() {
    super.onExit(); // Required for proper internal cleanup in flutter_inappwebview
    debugPrint('AG_DEBUG: Browser closed');
    onClosed?.call();
  }
}
