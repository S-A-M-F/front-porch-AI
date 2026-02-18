import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:front_porch_ai/providers/app_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:front_porch_ai/services/world_repository.dart';
import 'package:front_porch_ai/services/folder_service.dart';
import 'package:front_porch_ai/services/group_chat_repository.dart';
import 'package:front_porch_ai/models/group_chat.dart';
import 'package:front_porch_ai/ui/pages/chat_page.dart';
import 'package:front_porch_ai/services/chat_service.dart';
import 'package:front_porch_ai/services/llm_provider.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:front_porch_ai/services/v2_card_service.dart';
import 'package:front_porch_ai/ui/pages/edit_character_page.dart';
import 'package:front_porch_ai/ui/dialogs/tag_dialog.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:url_launcher/url_launcher.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _searchQuery = '';
  String? _activeFolderId; // null = top level view
  final _searchController = TextEditingController();

  // Multi-select for group creation
  bool _isSelecting = false;
  final Set<String> _selectedCharacterIds = {}; // imagePath-based IDs

  String _getCharacterIdFromCard(CharacterCard card) {
    if (card.imagePath != null) {
      return path.basenameWithoutExtension(card.imagePath!);
    }
    return card.name.replaceAll(RegExp(r'[^\w\s]'), '').replaceAll(' ', '_');
  }

  void _toggleSelect(CharacterCard character) {
    final id = _getCharacterIdFromCard(character);
    setState(() {
      if (_selectedCharacterIds.contains(id)) {
        _selectedCharacterIds.remove(id);
        if (_selectedCharacterIds.isEmpty) _isSelecting = false;
      } else {
        _selectedCharacterIds.add(id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _isSelecting = false;
      _selectedCharacterIds.clear();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Provider.of<AppState>(context, listen: false).setIndex(1),
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
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton.icon(
                      onPressed: () => _openBrowser(context),
                      icon: const Icon(Icons.public, color: Colors.blueAccent),
                      label: const Text('AI Character Cards', style: TextStyle(color: Colors.blueAccent)),
                    ),
                    const SizedBox(width: 16),
                    TextButton.icon(
                      onPressed: () => _showChubWarning(context),
                      icon: const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
                      label: const Text('Chub.ai', style: TextStyle(color: Colors.redAccent)),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        // Filter characters based on search and active folder
        final filteredCharacters = _getFilteredCharacters(repo, folderService);

        return Stack(
          children: [
            Column(
              children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                  child: Row(
                    children: [
                      if (_isSelecting) ...[
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel selection',
                          onPressed: _cancelSelection,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${_selectedCharacterIds.length} selected',
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.purpleAccent,
                          ),
                        ),
                      ] else if (_activeFolderId != null) ...[
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          tooltip: 'Back to all characters',
                          onPressed: () => setState(() => _activeFolderId = null),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getActiveFolderName(folderService),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ] else
                        Text('My Characters', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (!_isSelecting) ...[
                        IconButton(
                          tooltip: 'Select characters for group chat',
                          icon: const Icon(Icons.group_add, color: Colors.purpleAccent),
                          onPressed: () => setState(() => _isSelecting = true),
                        ),
                        if (_activeFolderId == null)
                          IconButton(
                            tooltip: 'New Folder',
                            icon: const Icon(Icons.create_new_folder_outlined),
                            onPressed: () => _createFolder(context, folderService),
                          ),
                        IconButton(
                          tooltip: 'Import Card',
                          icon: const Icon(Icons.download),
                          onPressed: () => _importCharacter(context),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _openBrowser(context),
                          icon: const Icon(Icons.public),
                          label: const Text('AI Cards'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: () => _showChubWarning(context),
                          icon: const Icon(Icons.warning_amber_rounded),
                          label: const Text('Chub.ai'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),

                // Search bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search by name or tag...',
                      hintStyle: const TextStyle(color: Colors.white38),
                      prefixIcon: const Icon(Icons.search, color: Colors.white38),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, color: Colors.white38),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFF1E293B),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onChanged: (value) => setState(() => _searchQuery = value),
                  ),
                ),
                const SizedBox(height: 12),

                // Grid with folders, groups, and characters
                Expanded(
                  child: _buildGrid(context, repo, folderService, filteredCharacters, groupRepo),
                ),
              ],
            ),
            // Selection action bar
            if (_isSelecting)
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1F2937),
                    border: const Border(top: BorderSide(color: Colors.white10)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8, offset: const Offset(0, -2)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.group, color: Colors.purpleAccent.withValues(alpha: 0.7)),
                      const SizedBox(width: 12),
                      Text(
                        '${_selectedCharacterIds.length} character${_selectedCharacterIds.length == 1 ? '' : 's'} selected',
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: _cancelSelection,
                        child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: _selectedCharacterIds.length >= 2
                            ? () => _showCreateGroupDialog(context, repo)
                            : null,
                        icon: const Icon(Icons.group_add),
                        label: const Text('Create Group'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purpleAccent,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: Colors.white10,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  List<CharacterCard> _getFilteredCharacters(CharacterRepository repo, FolderService folderService) {
    List<CharacterCard> characters;

    if (_activeFolderId != null) {
      // Show only characters in this folder
      final folderPaths = folderService.getCharactersInFolder(_activeFolderId!);
      characters = repo.characters.where((c) => folderPaths.contains(c.imagePath)).toList();
    } else {
      characters = repo.characters.toList();
    }

    // Apply search filter
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      characters = characters.where((c) {
        if (c.name.toLowerCase().contains(query)) return true;
        if (c.tags.any((t) => t.toLowerCase().contains(query))) return true;
        return false;
      }).toList();
    }

    return characters;
  }

  String _getActiveFolderName(FolderService folderService) {
    if (_activeFolderId == null) return 'My Characters';
    final folder = folderService.folders.where((f) => f.id == _activeFolderId).firstOrNull;
    return folder?.name ?? 'Folder';
  }

  Widget _buildGrid(BuildContext context, CharacterRepository repo, FolderService folderService, List<CharacterCard> filteredCharacters, GroupChatRepository groupRepo) {
    // At top level and not searching, show folder cards + unfoldered characters
    final showFolders = _activeFolderId == null && _searchQuery.isEmpty;
    final folders = showFolders ? folderService.folders : <CharacterFolder>[];

    // Show group cards at top level only
    final groups = (showFolders && !_isSelecting) ? groupRepo.groups : <GroupChat>[];

    // At top level, show unfoldered characters only (unless searching)
    List<CharacterCard> displayCharacters;
    if (showFolders) {
      final folderedPaths = folderService.getUnfolderedCharacterPaths();
      displayCharacters = filteredCharacters.where((c) => !folderedPaths.contains(c.imagePath)).toList();
    } else {
      displayCharacters = filteredCharacters;
    }

    final totalItems = folders.length + groups.length + displayCharacters.length;
    if (totalItems == 0) {
      return Center(
        child: Text(
          _searchQuery.isNotEmpty ? 'No characters match "$_searchQuery"' : 'This folder is empty',
          style: const TextStyle(color: Colors.white38, fontSize: 16),
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.fromLTRB(24, 24, 24, _isSelecting ? 80 : 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 300,
        childAspectRatio: 0.7,
        crossAxisSpacing: 24,
        mainAxisSpacing: 24,
      ),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        // Render folder cards first
        if (index < folders.length) {
          return _buildFolderCard(context, folders[index], folderService, repo);
        }
        // Then group cards
        final groupOffset = index - folders.length;
        if (groupOffset < groups.length) {
          return _buildGroupCard(context, groups[groupOffset], repo);
        }
        // Then character cards
        final character = displayCharacters[groupOffset - groups.length];
        return _buildCharacterCard(context, character, folderService);
      },
    );
  }

  Widget _buildFolderCard(BuildContext context, CharacterFolder folder, FolderService folderService, CharacterRepository repo) {
    final charCount = folder.characterPaths.length;

    return DragTarget<CharacterCard>(
      onAcceptWithDetails: (details) async {
        await folderService.addToFolder(folder.id, details.data.imagePath!);
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Card(
          color: isHovering ? Colors.amber.shade900.withOpacity(0.4) : const Color(0xFF1E293B),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isHovering ? Colors.amber : Colors.white.withOpacity(0.1),
              width: isHovering ? 2 : 1,
            ),
          ),
          child: InkWell(
            onTap: () => setState(() => _activeFolderId = folder.id),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder,
                  size: 72,
                  color: isHovering ? Colors.amber : Colors.amber.shade700,
                ),
                const SizedBox(height: 16),
                Text(
                  folder.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  '$charCount character${charCount == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 16),
                // Folder action buttons
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, color: Colors.white54, size: 18),
                      tooltip: 'Rename',
                      onPressed: () => _renameFolder(context, folder, folderService),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                      tooltip: 'Delete folder',
                      onPressed: () => _deleteFolder(context, folder, folderService),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCharacterCard(BuildContext context, CharacterCard character, FolderService folderService) {
    return LongPressDraggable<CharacterCard>(
      data: character,
      feedback: Material(
        color: Colors.transparent,
        child: SizedBox(
          width: 150,
          height: 200,
          child: Card(
            color: const Color(0xFF1E293B),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: character.imagePath != null
                ? Image.file(File(character.imagePath!), fit: BoxFit.cover)
                : const Icon(Icons.person, size: 64, color: Colors.white24),
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: _buildCharacterCardInner(context, character, folderService),
      ),
      child: _buildCharacterCardInner(context, character, folderService),
    );
  }

  Widget _buildCharacterCardInner(BuildContext context, CharacterCard character, FolderService folderService) {
    final charId = _getCharacterIdFromCard(character);
    final isSelected = _selectedCharacterIds.contains(charId);

    return Card(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSelected ? Colors.purpleAccent : Theme.of(context).dividerColor.withValues(alpha: 0.1),
          width: isSelected ? 2.5 : 1,
        ),
      ),
      child: Stack(
        children: [
          InkWell(
            onTap: () async {
              if (_isSelecting) {
                _toggleSelect(character);
                return;
              }
              final chatService = Provider.of<ChatService>(context, listen: false);
              await chatService.setActiveCharacter(character);
              if (context.mounted) {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChatPage()),
                );
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 3,
                  child: character.imagePath != null
                      ? Image.file(
                          File(character.imagePath!),
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(Icons.person, size: 64, color: Colors.white24),
                        ),
                ),
                Expanded(
                  flex: 1,
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          character.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // Tag chips (show first 3 tags)
                        if (character.tags.isNotEmpty)
                          Flexible(
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 2,
                              children: character.tags.take(3).map((tag) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade900.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(color: Colors.amber.shade300, fontSize: 10),
                                ),
                              )).toList(),
                            ),
                          )
                        else
                          Flexible(
                            child: Text(
                              character.formattedDescription,
                              style: Theme.of(context).textTheme.bodySmall,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Selection checkbox overlay
          if (_isSelecting)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: isSelected ? Colors.purpleAccent : Colors.black54,
                  shape: BoxShape.circle,
                  border: Border.all(color: isSelected ? Colors.purpleAccent : Colors.white38, width: 2),
                ),
                child: isSelected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
            ),
          // Action buttons (hide during selection mode)
          if (!_isSelecting)
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _editCharacter(context, character),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.edit, color: Colors.white, size: 20),
                      ),
                    ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _exportCharacter(context, character),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.upload, color: Colors.white, size: 20),
                      ),
                    ),
                    // Remove from folder button (only when inside a folder)
                    if (_activeFolderId != null)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () async {
                          await folderService.removeFromFolder(_activeFolderId!, character.imagePath!);
                        },
                        child: const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Icon(Icons.folder_off, color: Colors.amber, size: 20),
                        ),
                      ),
                    InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => _confirmDeleteCharacter(context, character),
                      child: const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Icon(Icons.delete, color: Colors.redAccent, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─── Group Card ─────────────────────────────────────────────────

  Widget _buildGroupCard(BuildContext context, GroupChat group, CharacterRepository repo) {
    // Resolve character cards for the group
    final characters = <CharacterCard>[];
    for (final id in group.characterIds) {
      final match = repo.characters.where((c) => _getCharacterIdFromCard(c) == id).firstOrNull;
      if (match != null) characters.add(match);
    }

    return Card(
      color: const Color(0xFF1E293B),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: () async {
          final chatService = Provider.of<ChatService>(context, listen: false);
          await chatService.setActiveGroup(group);
          if (context.mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ChatPage()),
            );
          }
        },
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 16),
                // Stacked avatars
                SizedBox(
                  height: 80,
                  width: double.infinity,
                  child: Center(
                    child: SizedBox(
                      width: 40.0 + (characters.take(4).length - 1) * 30.0,
                      height: 80,
                      child: Stack(
                        children: [
                          for (int i = 0; i < characters.take(4).length; i++)
                            Positioned(
                              left: i * 30.0,
                              child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.purpleAccent, width: 2),
                                  image: characters[i].imagePath != null
                                      ? DecorationImage(
                                          image: FileImage(File(characters[i].imagePath!)),
                                          fit: BoxFit.cover,
                                        )
                                      : null,
                                  color: characters[i].imagePath == null ? Colors.grey.shade700 : null,
                                ),
                                child: characters[i].imagePath == null
                                    ? const Icon(Icons.person, color: Colors.white24, size: 28)
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Group icon badge
                const Icon(Icons.group, color: Colors.purpleAccent, size: 20),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${characters.length} character${characters.length == 1 ? '' : 's'}',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
                const SizedBox(height: 4),
                // Turn order label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purpleAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    group.turnOrder == TurnOrder.roundRobin ? 'Round Robin' : 'Random',
                    style: TextStyle(color: Colors.purpleAccent.withValues(alpha: 0.8), fontSize: 11),
                  ),
                ),
              ],
            ),
            // Delete group button
            Positioned(
              top: 8,
              right: 8,
              child: Material(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _confirmDeleteGroup(context, group),
                  child: const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: Icon(Icons.delete, color: Colors.redAccent, size: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
        title: const Text('Delete Group', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete group "${group.name}"?\n\nThe characters themselves will NOT be deleted.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
              groupRepo.delete(group.id);
              Navigator.pop(ctx);
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  // ─── Group Creation Dialog ──────────────────────────────────────

  void _showCreateGroupDialog(BuildContext context, CharacterRepository repo) {
    // Show pre-alpha warning first
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent),
            SizedBox(width: 8),
            Text('Pre-Alpha Feature', style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Group Chat is a pre-alpha feature. Expect rough edges and results that may vary depending on your model and backend.',
          style: TextStyle(color: Colors.white70, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white38)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showCreateGroupDialogInner(context, repo);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purpleAccent),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showCreateGroupDialogInner(BuildContext context, CharacterRepository repo) {
    final nameController = TextEditingController();
    final firstMessageController = TextEditingController();
    final scenarioController = TextEditingController();
    final systemPromptController = TextEditingController(text: ChatService.defaultGroupSystemPrompt);
    TurnOrder selectedTurnOrder = TurnOrder.roundRobin;
    bool autoAdvance = false;
    bool isGeneratingFirstMessage = false;
    bool isGeneratingScenario = false;

    // Build default name from selected character names
    final selectedChars = <CharacterCard>[];
    for (final id in _selectedCharacterIds) {
      final match = repo.characters.where((c) => _getCharacterIdFromCard(c) == id).firstOrNull;
      if (match != null) selectedChars.add(match);
    }
    nameController.text = selectedChars.map((c) => c.name).join(' & ');

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1F2937),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.group_add, color: Colors.purpleAccent),
              SizedBox(width: 8),
              Text('Create Group Chat', style: TextStyle(color: Colors.white)),
            ],
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Selected characters preview
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: selectedChars.map((c) => Chip(
                    avatar: c.imagePath != null
                        ? CircleAvatar(backgroundImage: FileImage(File(c.imagePath!)))
                        : const CircleAvatar(child: Icon(Icons.person, size: 14)),
                    label: Text(c.name, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    backgroundColor: Colors.purpleAccent.withValues(alpha: 0.2),
                    side: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.4)),
                  )).toList(),
                ),
                const SizedBox(height: 16),
                // Group name
                TextField(
                  controller: nameController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Group Name',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Enter a group name...',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
                const SizedBox(height: 20),
                // Turn order
                const Text('Turn Order', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 8),
                SegmentedButton<TurnOrder>(
                  segments: const [
                    ButtonSegment(value: TurnOrder.roundRobin, label: Text('Round Robin'), icon: Icon(Icons.repeat)),
                    ButtonSegment(value: TurnOrder.random, label: Text('Random'), icon: Icon(Icons.shuffle)),
                  ],
                  selected: {selectedTurnOrder},
                  onSelectionChanged: (val) => setDialogState(() => selectedTurnOrder = val.first),
                  style: ButtonStyle(
                    foregroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected) ? Colors.white : Colors.white54),
                    backgroundColor: WidgetStateProperty.resolveWith((states) =>
                        states.contains(WidgetState.selected) ? Colors.purpleAccent : Colors.transparent),
                  ),
                ),
                const SizedBox(height: 16),
                // Auto-advance toggle
                SwitchListTile(
                  value: autoAdvance,
                  onChanged: (val) => setDialogState(() => autoAdvance = val),
                  title: const Text('Auto-Advance', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: const Text(
                    'Characters respond automatically one after another',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                  activeColor: Colors.purpleAccent,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                // ── Scenario (optional) — with Generate button ──
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Scenario (optional)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isGeneratingScenario ? null : () async {
                        final llmProvider = Provider.of<LLMProvider>(context, listen: false);
                        final service = llmProvider.activeService;
                        if (!service.isReady) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('LLM backend is not ready. Start KoboldCPP or configure your API first.')),
                          );
                          return;
                        }

                        setDialogState(() => isGeneratingScenario = true);

                        final charNames = selectedChars.map((c) => c.name).join(', ');
                        final charBriefs = selectedChars.map((c) {
                          final trait = c.personality.isNotEmpty
                              ? c.personality.split('.').first
                              : (c.description.isNotEmpty ? c.description.split('.').first : c.name);
                          return '${c.name} ($trait)';
                        }).join(', ');

                        final scenarioPrompt =
                            '[Output ONLY the scenario text. No planning, reasoning, or explanation. '
                            'Do NOT use <think> tags.]\n\n'
                            'Write a brief scenario (1-2 sentences max) for a group roleplay with: $charBriefs.\n'
                            'The scenario should describe WHERE the characters are and WHAT is happening.\n'
                            'Use {{user}} to refer to the player. Keep it concise like:\n'
                            '"{{user}} and $charNames are hanging out at a rooftop bar downtown on a Friday night."\n\n'
                            'SCENARIO: ';

                        try {
                          final buffer = StringBuffer();
                          final params = GenerationParams(
                            prompt: scenarioPrompt,
                            maxLength: 150,
                            temperature: 0.9,
                            stopSequences: ['\n\n', 'END', '---'],
                          );
                          await for (final token in service.generateStream(params)) {
                            buffer.write(token);
                          }
                          var result = buffer.toString()
                              .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
                              .replaceAll(RegExp(r'</think>', caseSensitive: false), '')
                              .replaceAll(RegExp(r'^SCENARIO:\s*', caseSensitive: false), '')
                              .replaceAll('"', '')
                              .trim();

                          if (result.isNotEmpty) {
                            scenarioController.text = result;
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Generation failed: $e')),
                            );
                          }
                        } finally {
                          setDialogState(() => isGeneratingScenario = false);
                        }
                      },
                      icon: isGeneratingScenario
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                            )
                          : const Icon(Icons.auto_awesome, size: 16, color: Colors.amberAccent),
                      label: Text(
                        isGeneratingScenario ? 'Generating...' : 'Generate',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: scenarioController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'e.g. {{user}} and friends are at a rooftop bar...',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                // ── First Message (optional) — with Generate button ──
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'First Message (optional)',
                        style: TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isGeneratingFirstMessage ? null : () async {
                        final llmProvider = Provider.of<LLMProvider>(context, listen: false);
                        final service = llmProvider.activeService;
                        if (!service.isReady) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('LLM backend is not ready. Start KoboldCPP or configure your API first.')),
                          );
                          return;
                        }

                        setDialogState(() => isGeneratingFirstMessage = true);

                        // Build a meta-prompt from all selected characters
                        final charDescriptions = selectedChars.map((c) {
                          final persona = c.personality.isNotEmpty ? c.personality : c.description;
                          final scenario = c.scenario.isNotEmpty ? ' Scenario: ${c.scenario}' : '';
                          return '- ${c.name}: $persona$scenario';
                        }).join('\n');

                        final scenarioContext = scenarioController.text.trim().isNotEmpty
                            ? '\nThe group scenario is: ${scenarioController.text.trim()}'
                            : '';

                        final metaPrompt =
                            '[INSTRUCTIONS: Output ONLY the creative scene text. '
                            'Do NOT plan, reason, analyze, or explain what you will write. '
                            'Do NOT list requirements or break down the task. '
                            'Do NOT use <think> tags. Start writing the scene IMMEDIATELY.]\n\n'
                            'Write a vivid, immersive opening scene (4-6 paragraphs, at least 400 words) '
                            'for a group roleplay featuring:\n$charDescriptions\n$scenarioContext\n\n'
                            'CRITICAL REQUIREMENTS:\n'
                            '- {{user}} is PRESENT in the scene. Characters notice, acknowledge, and speak TO {{user}}.\n'
                            '- EACH character MUST have at least 2 lines of spoken dialogue using quotation marks.\n'
                            '- Characters MUST interact with EACH OTHER — they speak to, react to, and acknowledge one another.\n'
                            '- Describe the environment with rich sensory details (sights, sounds, smells, textures).\n'
                            '- Show each character doing physical actions that reveal their personality.\n'
                            '- Use third-person narration with *asterisks* for actions and descriptions.\n'
                            '- Do NOT write any dialogue, thoughts, or actions for {{user}}.\n'
                            '- End with a character directly addressing {{user}}, creating a natural moment for {{user}} to respond.\n'
                            '- When the scene is complete, write "END SCENE" on its own line.\n\n'
                            'BEGIN SCENE:\n';

                        try {
                          final buffer = StringBuffer();
                          final params = GenerationParams(
                            prompt: metaPrompt,
                            maxLength: 2000,
                            temperature: 0.85,
                            stopSequences: ['END SCENE', '---', '[END]'],
                          );
                          await for (final token in service.generateStream(params)) {
                            buffer.write(token);
                          }
                          var result = buffer.toString()
                              .replaceAll(RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false), '')
                              .replaceAll(RegExp(r'</think>', caseSensitive: false), '');

                          final sceneMarker = result.indexOf('BEGIN SCENE:');
                          if (sceneMarker >= 0) {
                            result = result.substring(sceneMarker + 'BEGIN SCENE:'.length);
                          }

                          final lines = result.split('\n');
                          final cleaned = lines.where((line) {
                            final trimmed = line.trimLeft();
                            if (trimmed.startsWith('The user wants') ||
                                trimmed.startsWith('I need to') ||
                                trimmed.startsWith('I will') ||
                                trimmed.startsWith('I should') ||
                                trimmed.startsWith('Let me ') ||
                                trimmed.startsWith('I\'ll ') ||
                                RegExp(r'^\d+\.\s+(Write|Use|Set|Make|Do|Keep|NOT|Create|End|Establish)').hasMatch(trimmed)) {
                              return false;
                            }
                            return true;
                          }).join('\n').trim();

                          if (cleaned.isNotEmpty) {
                            firstMessageController.text = cleaned;
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Generation failed: $e')),
                            );
                          }
                        } finally {
                          setDialogState(() => isGeneratingFirstMessage = false);
                        }
                      },
                      icon: isGeneratingFirstMessage
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amberAccent),
                            )
                          : const Icon(Icons.auto_awesome, size: 16, color: Colors.amberAccent),
                      label: Text(
                        isGeneratingFirstMessage ? 'Generating...' : 'Generate',
                        style: const TextStyle(color: Colors.amberAccent, fontSize: 12),
                      ),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: firstMessageController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Custom greeting or tap Generate ✨ (uses scenario above)',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
                const SizedBox(height: 16),
                // System Prompt (optional)
                TextField(
                  controller: systemPromptController,
                  style: const TextStyle(color: Colors.white),
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'System Prompt (optional)',
                    labelStyle: TextStyle(color: Colors.white54),
                    hintText: 'Override the global system prompt...',
                    hintStyle: TextStyle(color: Colors.white24),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.purpleAccent)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.check),
              label: const Text('Create'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purpleAccent,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;

                final group = GroupChat(
                  id: 'group_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  characterIds: _selectedCharacterIds.toList(),
                  turnOrder: selectedTurnOrder,
                  autoAdvance: autoAdvance,
                  firstMessage: firstMessageController.text.trim(),
                  scenario: scenarioController.text.trim(),
                  systemPrompt: systemPromptController.text.trim(),
                );

                final groupRepo = Provider.of<GroupChatRepository>(context, listen: false);
                groupRepo.save(group);

                Navigator.pop(ctx);
                _cancelSelection();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Group "$name" created!'),
                    backgroundColor: Colors.purpleAccent.shade700,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Folder Actions ─────────────────────────────────────────────

  void _createFolder(BuildContext context, FolderService folderService) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('New Folder', style: TextStyle(color: Colors.white)),
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
              folderService.createFolder(value.trim());
              Navigator.pop(ctx);
            }
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.createFolder(controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _renameFolder(BuildContext context, CharacterFolder folder, FolderService folderService) {
    final controller = TextEditingController(text: folder.name);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Text('Rename Folder', style: TextStyle(color: Colors.white)),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                folderService.renameFolder(folder.id, controller.text.trim());
                Navigator.pop(ctx);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
  }

  void _deleteFolder(BuildContext context, CharacterFolder folder, FolderService folderService) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2D1111),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Colors.redAccent, width: 2),
        ),
        title: const Text('Delete Folder', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
        content: Text(
          'Delete "${folder.name}"?\n\nCharacters inside will NOT be deleted — they\'ll return to the top level.',
          style: const TextStyle(color: Colors.white70, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              folderService.deleteFolder(folder.id);
              Navigator.pop(ctx);
              if (_activeFolderId == folder.id) {
                setState(() => _activeFolderId = null);
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
      backgroundColor: Colors.white.withOpacity(0.1),
      foregroundColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.white24),
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
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              'Delete Character',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.of(context).pop();
              final repo = Provider.of<CharacterRepository>(context, listen: false);
              final worldRepo = Provider.of<WorldRepository>(context, listen: false);
              await repo.deleteCharacter(character, worldRepo: worldRepo);
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

  Future<void> _editCharacter(BuildContext context, CharacterCard character) async {
     await Navigator.push(
       context,
       MaterialPageRoute(builder: (context) => EditCharacterPage(character: character)),
     );
     if (context.mounted) {
       Provider.of<CharacterRepository>(context, listen: false).loadCharacters();
     }
  }

  Future<void> _importCharacter(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'json'],
    );
    
    if (result != null && result.files.single.path != null) {
      if (!context.mounted) return;
      final file = File(result.files.single.path!);
      try {
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
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Character imported successfully!')));
          }
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Import failed: $e')));
        }
      }
    }
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
         final v2Service = Provider.of<V2CardService>(context, listen: false);
         await v2Service.saveCardAsPng(character, outputFile, character.imagePath);

         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported to $outputFile')));
         }
       } catch (e) {
         if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
         }
       }
    }
  }

  // ─── Browser Integrations ──────────────────────────────────────

  Future<void> _openBrowser(BuildContext context) async {
    // Skip embedded browser on Linux due to WPE WebKit rendering issues
    if (Platform.isLinux) {
      _showBrowserFallbackDialog(context, 'https://aicharactercards.com/', 'AI Character Cards');
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
          
          final directory = await getApplicationDocumentsDirectory();
          final charDir = Directory('${directory.path}/KoboldManager/Characters');
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }
          
          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);
          
          final card = await repo.importCharacter(tempFile, worldRepo: worldRepo);
          
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
      
      final browser = CharacterBrowser(onDownload: handleDownloadUrl);
      
      await browser.openUrlRequest(
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
        _showBrowserFallbackDialog(context, 'https://aicharactercards.com/', 'AI Character Cards');
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
          
          final directory = await getApplicationDocumentsDirectory();
          final charDir = Directory('${directory.path}/KoboldManager/Characters');
          if (!await charDir.exists()) {
            await charDir.create(recursive: true);
          }
          
          final uri = Uri.parse(url);
          String fileName;
          if (uri.pathSegments.isNotEmpty && uri.pathSegments.last.endsWith('.png')) {
            fileName = uri.pathSegments.last;
          } else {
            fileName = 'chub_card_${DateTime.now().millisecondsSinceEpoch}.png';
          }
          final tempFile = File('${charDir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);
          
          final card = await repo.importCharacter(tempFile, worldRepo: worldRepo);

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

      final browser = CharacterBrowser(onDownload: handleChubDownload);
      
      await browser.openUrlRequest(
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

  void _showBrowserFallbackDialog(BuildContext context, String url, String siteName) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1F2937),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('Browser Rendering Issue', style: TextStyle(color: Colors.white)),
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
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
            child: const Text('Cancel', style: TextStyle(color: Colors.white70)),
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
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
            SizedBox(width: 8),
            Text(
              '⚠️ TRAVELER, BEWARE ⚠️',
              style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
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
                style: TextStyle(color: Colors.white, fontSize: 14, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'You WILL encounter NSFW and potentially NSFL content. '
                'There is no "safe" section. There is no lifeguard on duty. '
                'Eye bleach is strongly advised — and may still not be enough.',
                style: TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Browse at your own discretion. '
                'We are not responsible for what you find... '
                'or what finds you. 👁️',
                style: TextStyle(color: Colors.white60, fontSize: 12, fontStyle: FontStyle.italic, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Nope, I Choose Life', style: TextStyle(color: Colors.white70)),
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
  
  CharacterBrowser({required this.onDownload});
  
  @override
  Future<NavigationActionPolicy>? shouldOverrideUrlLoading(NavigationAction navigationAction) async {
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
    debugPrint('AG_DEBUG: Browser closed');
  }
}
