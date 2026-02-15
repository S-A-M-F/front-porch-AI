import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:kobold_character_card_manager/models/character_card.dart';
import 'package:kobold_character_card_manager/services/v2_card_service.dart';

class CharacterRepository extends ChangeNotifier {
  final List<CharacterCard> _characters = [];
  bool _isLoading = false;

  List<CharacterCard> get characters => List.unmodifiable(_characters);
  bool get isLoading => _isLoading;

  CharacterRepository() {
    loadCharacters();
  }

  Future<void> loadCharacters() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final charDir = Directory('${directory.path}/KoboldManager/Characters');
      
      if (await charDir.exists()) {
        _characters.clear();
        final v2Service = V2CardService();
        
        await for (final entity in charDir.list()) {
          if (entity is File && entity.path.toLowerCase().endsWith('.png')) {
            try {
              final card = await v2Service.readCard(entity.path);
              if (card != null) {
                _characters.add(card);
              }
            } catch (e) {
              print('Failed to load card ${entity.path}: $e');
            }
          }
        }
      }
    } catch (e) {
      print('Error loading characters: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addCharacter(CharacterCard character) {
    _characters.add(character);
    notifyListeners();
  }

  void removeCharacter(CharacterCard character) {
    _characters.remove(character);
    notifyListeners();
  }

  Future<void> importCharacter(File file) async {
    _isLoading = true;
    notifyListeners();
    try {
      // Stub implementation for now - just adds a dummy character
      // In real implementation, this would parse the PNG/JSON
      await Future.delayed(const Duration(seconds: 1)); // Simulate work
      
      final newChar = CharacterCard(
        name: 'Imported Character',
        description: 'Imported from ${file.path}',
        imagePath: file.path,
      );
      addCharacter(newChar);
      
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }


  Future<void> updateCharacter(CharacterCard card) async {
    if (card.imagePath == null) return;
    
    _isLoading = true;
    notifyListeners();
    
    try {
      final v2Service = V2CardService();
      // Overwrite the existing file with updated data
      await v2Service.saveCardAsPng(card, card.imagePath!, card.imagePath!);
      
      // Update the list entry if needed (references might be same, but good to notify)
      final index = _characters.indexWhere((c) => c.imagePath == card.imagePath);
      if (index != -1) {
        _characters[index] = card;
      }
      notifyListeners();
      
    } catch (e) {
      print('Error updating character: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

