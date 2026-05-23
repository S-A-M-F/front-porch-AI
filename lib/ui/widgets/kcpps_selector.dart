// Copyright (C) 2026 Front Porch AI
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:front_porch_ai/services/storage_service.dart';

/// Scans [binDir] for .kcpps files and returns them sorted by filename.
List<File> scanKcppsPresets(Directory binDir) {
  if (!binDir.existsSync()) return [];
  try {
    final files = binDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.kcpps'))
        .toList()
      ..sort((a, b) => p.basename(a.path).toLowerCase().compareTo(
          p.basename(b.path).toLowerCase()));
    return files;
  } catch (_) {
    return [];
  }
}

/// A reusable .kcpps preset selector row.
///
/// Shows a full-path chip with a [X] close button when the active preset
/// is outside the koboldcpp bin directory, or a [DropdownButton] of local
/// presets otherwise. A Browse button opens a file picker.
class KcppsSelector extends StatelessWidget {
  const KcppsSelector({
    super.key,
    required this.storage,
    required this.localPresets,
    required this.hint,
    required this.onChanged,
    required this.onExternalClear,
    required this.onBrowsePicked,
    this.browseLabel,
    this.backgroundColor,
  });

  final StorageService storage;
  final List<File> localPresets;
  final String hint;
  final ValueChanged<String?> onChanged;
  final VoidCallback onExternalClear;
  final ValueChanged<String> onBrowsePicked;
  final String? browseLabel;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final activePath = storage.activeKcppsPath;
    final bgColor = backgroundColor ?? const Color(0xFF374151);
    final isExternal = activePath != null &&
        activePath.isNotEmpty &&
        !localPresets.any((f) => f.path == activePath);

    return Row(
      children: [
        Expanded(
          child: isExternal
              ? _buildExternalChip(activePath!, bgColor)
              : _buildDropdown(bgColor),
        ),
        const SizedBox(width: 8),
        _buildBrowseButton(),
      ],
    );
  }

  Widget _buildExternalChip(String activePath, Color bgColor) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              activePath,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: onExternalClear,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Icon(
                Icons.close,
                size: 16,
                color: Colors.white.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown(Color bgColor) {
    final activePath = storage.activeKcppsPath;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: activePath != null &&
                  localPresets.any((f) => f.path == activePath)
              ? activePath
              : null,
          isExpanded: true,
          hint: Text(hint,
              style: const TextStyle(fontSize: 13, color: Colors.white54)),
          dropdownColor: bgColor,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.white70),
          items: [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('None (Use App Settings)',
                  style: TextStyle(fontSize: 13)),
            ),
            ...localPresets.map((file) {
              return DropdownMenuItem<String>(
                value: file.path,
                child: Text(p.basename(file.path),
                    style: const TextStyle(fontSize: 13)),
              );
            }),
          ],
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBrowseButton() {
    if (browseLabel != null) {
      return ElevatedButton.icon(
        onPressed: _onBrowse,
        icon: const Icon(Icons.folder_open, size: 16),
        label: Text(browseLabel!),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
        ),
      );
    }
    return IconButton(
      onPressed: _onBrowse,
      icon: const Icon(Icons.folder_open, size: 20),
      tooltip: 'Browse',
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xFF374151),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _onBrowse() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['kcpps'],
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      storage.setActiveKcppsPath(path);
      onBrowsePicked(path);
    }
  }
}
