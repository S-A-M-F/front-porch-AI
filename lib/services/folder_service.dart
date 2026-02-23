import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class CharacterFolder {
  final String id;
  String name;
  final List<String> characterPaths; // imagePath references

  CharacterFolder({
    required this.id,
    required this.name,
    List<String>? characterPaths,
  }) : characterPaths = characterPaths ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'characterPaths': characterPaths,
  };

  factory CharacterFolder.fromJson(Map<String, dynamic> json) {
    return CharacterFolder(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      characterPaths: List<String>.from(json['characterPaths'] ?? []),
    );
  }
}

class FolderService extends ChangeNotifier {
  final List<CharacterFolder> _folders = [];
  File? _storageFile;

  List<CharacterFolder> get folders => List.unmodifiable(_folders);

  FolderService() {
    _init();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    _storageFile = File('${directory.path}/KoboldManager/character_folders.json');
    await _load();
  }

  Future<void> _load() async {
    if (_storageFile == null || !await _storageFile!.exists()) return;
    try {
      final json = jsonDecode(await _storageFile!.readAsString());
      _folders.clear();
      for (final item in (json['folders'] as List? ?? [])) {
        _folders.add(CharacterFolder.fromJson(item));
      }
      notifyListeners();
    } catch (e) {
      print('Error loading folders: $e');
    }
  }

  Future<void> _save() async {
    if (_storageFile == null) return;
    await _storageFile!.parent.create(recursive: true);
    final json = {
      'folders': _folders.map((f) => f.toJson()).toList(),
    };
    await _storageFile!.writeAsString(jsonEncode(json));
  }

  Future<CharacterFolder> createFolder(String name) async {
    final folder = CharacterFolder(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
    );
    _folders.add(folder);
    await _save();
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    folder.name = newName;
    await _save();
    notifyListeners();
  }

  Future<void> deleteFolder(String folderId) async {
    _folders.removeWhere((f) => f.id == folderId);
    await _save();
    notifyListeners();
  }

  Future<void> addToFolder(String folderId, String characterPath) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    // Store just the basename for portability
    final baseName = p.basename(characterPath);
    final alreadyContains = folder.characterPaths.any(
      (existing) => p.basename(existing).toLowerCase() == baseName.toLowerCase(),
    );
    if (!alreadyContains) {
      folder.characterPaths.add(baseName);
      // Remove from any other folder
      for (final other in _folders) {
        if (other.id != folderId) {
          other.characterPaths.removeWhere(
            (existing) => p.basename(existing).toLowerCase() == baseName.toLowerCase(),
          );
        }
      }
      await _save();
      notifyListeners();
    }
  }

  Future<void> removeFromFolder(String folderId, String characterPath) async {
    final folder = _folders.firstWhere((f) => f.id == folderId);
    final baseName = p.basename(characterPath).toLowerCase();
    folder.characterPaths.removeWhere(
      (existing) => p.basename(existing).toLowerCase() == baseName,
    );
    await _save();
    notifyListeners();
  }

  /// Get the folder a character belongs to (if any)
  CharacterFolder? getFolderForCharacter(String characterPath) {
    final baseName = p.basename(characterPath).toLowerCase();
    for (final folder in _folders) {
      if (folder.characterPaths.any(
        (existing) => p.basename(existing).toLowerCase() == baseName,
      )) {
        return folder;
      }
    }
    return null;
  }

  /// Get characters in a specific folder
  List<String> getCharactersInFolder(String folderId) {
    final folder = _folders.firstWhere(
      (f) => f.id == folderId,
      orElse: () => CharacterFolder(id: '', name: ''),
    );
    return folder.characterPaths;
  }

  /// Get characters not in any folder
  Set<String> getUnfolderedCharacterPaths() {
    final folderedPaths = <String>{};
    for (final folder in _folders) {
      folderedPaths.addAll(folder.characterPaths);
    }
    return folderedPaths;
  }
}
