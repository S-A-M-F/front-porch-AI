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
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/models/character_card.dart';
import 'package:front_porch_ai/models/lorebook.dart';
import 'package:front_porch_ai/services/character_repository.dart';
import 'package:flex_color_picker/flex_color_picker.dart';

class UiSettingsDialog extends StatefulWidget {
  final CharacterCard? character;

  const UiSettingsDialog({super.key, this.character});

  @override
  State<UiSettingsDialog> createState() => _UiSettingsDialogState();
}

class _UiSettingsDialogState extends State<UiSettingsDialog> {
  @override
  Widget build(BuildContext context) {
    final storageService = Provider.of<StorageService>(context);

    final backgrounds = [
      _buildBgThumbnail(storageService, 'none', 'None', null),
      _buildBgThumbnail(storageService, 'cyberpunk_bedroom', 'Cyberpunk', 'assets/backgrounds/cyberpunk_bedroom.png'),
      _buildBgThumbnail(storageService, 'coffee_shop', 'Coffee Shop', 'assets/backgrounds/coffee_shop.png'),
      _buildBgThumbnail(storageService, 'beach', 'Beach', 'assets/backgrounds/beach.png'),
      _buildBgThumbnail(storageService, 'futuristic_city', 'Neon City', 'assets/backgrounds/futuristic_city.png'),
      _buildBgThumbnail(storageService, 'edm_rave', 'EDM Rave', 'assets/backgrounds/edm_rave.png'),
      _buildBgThumbnail(storageService, 'cozy_library', 'Library', 'assets/backgrounds/cozy_library.png'),
      _buildBgThumbnail(storageService, 'rainy_japan', 'Rainy Japan', 'assets/backgrounds/rainy_japan.png'),
      _buildBgThumbnail(storageService, 'space_station', 'Space', 'assets/backgrounds/space_station.png'),
      _buildBgThumbnail(storageService, 'enchanted_forest', 'Forest', 'assets/backgrounds/enchanted_forest.png'),
      _buildBgThumbnail(storageService, 'anime_cherry_blossom', 'Sakura', 'assets/backgrounds/anime_cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop', 'Rooftop', 'assets/backgrounds/anime_rooftop.png'),
      _buildBgThumbnail(storageService, 'anime_rooftop_sunset', 'Sunset', 'assets/backgrounds/anime_rooftop_sunset.png'),
      _buildBgThumbnail(storageService, 'cherry_blossom', 'Blossom', 'assets/backgrounds/cherry_blossom.png'),
      _buildBgThumbnail(storageService, 'beach_waves', 'Waves', 'assets/backgrounds/beach_waves.png'),
      _buildBgThumbnail(storageService, 'waifu_gaming_room', 'Waifu Game', 'assets/backgrounds/waifu_gaming_room.png'),
      _buildBgThumbnail(storageService, 'waifu_beach_bar', 'Waifu Bar', 'assets/backgrounds/waifu_beach_bar.png'),
      _buildBgThumbnail(storageService, 'waifu_garden', 'Waifu Garden', 'assets/backgrounds/waifu_garden.png'),
      _buildBgThumbnail(storageService, 'waifu_neon', 'Waifu Neon', 'assets/backgrounds/waifu_neon.png'),
      _buildBgThumbnail(storageService, 'waifu_beach', 'Waifu Beach', 'assets/backgrounds/waifu_beach.png'),
    ];

    return Dialog(
      backgroundColor: const Color(0xFF1F2937),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        height: 680,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.character != null 
                    ? '${widget.character!.name} - UI Settings'
                    : 'UI Settings',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                IconButton(icon: const Icon(Icons.close, color: Colors.white70), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 20),

            // ── Appearance ──────────────────────────────────────────────
            const Text('Appearance', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            _buildSlider(
              'Bubble Opacity',
              storageService.bubbleOpacity,
              0.1, 1.0,
              (val) => storageService.setBubbleOpacity(val),
              divisions: 18,
            ),
            const SizedBox(height: 4),
            _buildSlider(
              'Chat Text Size',
              storageService.textScale,
              0.5, 2.0,
              (val) => storageService.setTextScale(val),
              divisions: 30,
            ),
            const SizedBox(height: 20),

            // ── Chat Colors ─────────────────────────────────────────────
            const Text('Chat Colors', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            _buildColorRow(
              context,
              'User Bubble',
              widget.character?.frontPorchExtensions?.userBubbleColor ?? storageService.globalUserBubbleColor,
              (color) => _updateUserBubbleColor(context, color),
            ),
            _buildColorRow(
              context,
              'User Text',
              widget.character?.frontPorchExtensions?.userTextColor ?? storageService.globalUserTextColor,
              (color) => _updateUserTextColor(context, color),
            ),
            _buildColorRow(
              context,
              'AI Bubble',
              widget.character?.frontPorchExtensions?.aiBubbleColor ?? storageService.globalAiBubbleColor,
              (color) => _updateAiBubbleColor(context, color),
            ),
            _buildColorRow(
              context,
              'AI Text',
              widget.character?.frontPorchExtensions?.aiTextColor ?? storageService.globalAiTextColor,
              (color) => _updateAiTextColor(context, color),
            ),
            _buildColorRow(
              context,
              'Dialogue (Quoted)',
              widget.character?.frontPorchExtensions?.dialogueColor ?? storageService.globalDialogueColor,
              (color) => _updateDialogueColor(context, color),
            ),
            _buildColorRow(
              context,
              'Actions (*text*)',
              widget.character?.frontPorchExtensions?.actionColor ?? storageService.globalActionColor,
              (color) => _updateActionColor(context, color),
            ),
            const SizedBox(height: 20),

            // ── Chat Background ─────────────────────────────────────────
            const Text('Chat Background', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent)),
            const SizedBox(height: 12),
            Expanded(
              child: GridView.count(
                crossAxisCount: 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.4,
                children: backgrounds,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSlider(String label, double value, double min, double max, ValueChanged<double> onChanged, {int? divisions}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white70)),
            Text(value.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
          activeColor: Colors.blueAccent,
          inactiveColor: Colors.white24,
        ),
      ],
    );
  }

  Widget _buildColorRow(
    BuildContext context,
    String label,
    Color color,
    void Function(Color) onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13)),
          const Spacer(),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: IconButton(
              icon: const Icon(Icons.color_lens, size: 20, color: Colors.white),
              onPressed: () => _showColorPicker(context, color, onChanged),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBgThumbnail(StorageService storageService, String key, String label, String? assetPath) {
    final isSelected = storageService.chatBackground == key;
    return GestureDetector(
      onTap: () => storageService.setChatBackground(key),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white24,
            width: isSelected ? 3 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (assetPath != null)
              Image.asset(assetPath, fit: BoxFit.cover)
            else
              Container(
                color: const Color(0xFF111827),
                child: const Center(child: Icon(Icons.block, color: Colors.white38, size: 28)),
              ),
            Positioned(
              left: 0, right: 0, bottom: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4),
                color: Colors.black54,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showColorPicker(
    BuildContext context,
    Color initialColor,
    void Function(Color) onChanged,
  ) async {
    // Preset colors for quick selection
    const presetColors = [
      Color(0xFF3B82F6), // Blue - User default
      Color(0xFF10B981), // Emerald
      Color(0xFFF59E0B), // Amber
      Color(0xFFEF4444), // Red
      Color(0xFF8B5CF6), // Purple
      Color(0xFFEC4899), // Pink
      Color(0xFF14B8A6), // Teal
      Color(0xFFF97316), // Orange
      Color(0xFF6366F1), // Indigo
      Color(0xFF06B6D4), // Cyan
      Color(0xFF10B981), // Emerald
      Color(0xFF84CC16), // Lime
    ];

    final picked = await showDialog<Color>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Select Color'),
          content: SizedBox(
            width: 380,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Preset colors row
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Quick Select',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presetColors.map((color) => GestureDetector(
                      onTap: () => Navigator.pop(context, color),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: color == initialColor 
                              ? Colors.blueAccent 
                              : Colors.white24,
                            width: 2,
                          ),
                        ),
                        child: color == initialColor
                          ? const Icon(
                              Icons.check,
                              size: 18,
                              color: Colors.white,
                            )
                          : null,
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 12),
                  // Color picker - use wheel picker for full color spectrum
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColorPicker(
                      color: initialColor,
                      onColorChanged: (color) => setState(() {}),
                      wheelDiameter: 160,
                      pickersEnabled: const <ColorPickerType, bool>{
                        ColorPickerType.wheel: true,
                      },
                      showColorCode: true,
                      colorCodeHasColor: true,
                      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
                        copyButton: true,
                        pasteButton: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, initialColor),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (picked != null) {
      onChanged(picked);
    }
  }

  Future<void> _updateUserBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      // Update per-character setting
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        userBubbleColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      // Save to database
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      // Update global setting
      await storage.setGlobalUserBubbleColor(color);
    }
    // Refresh UI
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _updateUserTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        userTextColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      await storage.setGlobalUserTextColor(color);
    }
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _updateAiBubbleColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        aiBubbleColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      await storage.setGlobalAiBubbleColor(color);
    }
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _updateAiTextColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        aiTextColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      await storage.setGlobalAiTextColor(color);
    }
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _updateDialogueColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        dialogueColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      await storage.setGlobalDialogueColor(color);
    }
    if (context.mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _updateActionColor(BuildContext context, Color color) async {
    final storage = Provider.of<StorageService>(context, listen: false);
    final character = widget.character;
    
    if (character != null && character.frontPorchExtensions != null) {
      final updatedExtensions = character.frontPorchExtensions!.copyWith(
        actionColor: color,
      );
      final updatedCharacter = CharacterCard(
        name: character.name,
        description: character.description,
        personality: character.personality,
        scenario: character.scenario,
        firstMessage: character.firstMessage,
        mesExample: character.mesExample,
        systemPrompt: character.systemPrompt,
        postHistoryInstructions: character.postHistoryInstructions,
        alternateGreetings: List.from(character.alternateGreetings),
        tags: List.from(character.tags),
        imagePath: character.imagePath,
        folderId: character.folderId,
        lorebook: character.lorebook != null
            ? Lorebook(entries: List.from(character.lorebook!.entries))
            : null,
        worldNames: List.from(character.worldNames),
        ttsVoice: character.ttsVoice,
        frontPorchExtensions: updatedExtensions,
        rawExtensions: character.rawExtensions != null
            ? Map<String, dynamic>.from(character.rawExtensions!)
            : null,
        avatarImages: character.avatarImages != null
            ? List.from(character.avatarImages!)
            : null,
      );
      final charRepo = Provider.of<CharacterRepository>(context, listen: false);
      await charRepo.updateCharacter(updatedCharacter);
    } else {
      await storage.setGlobalActionColor(color);
    }
    if (context.mounted) {
      Navigator.pop(context);
    }
  }
}
