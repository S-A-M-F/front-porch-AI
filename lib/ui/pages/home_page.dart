import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:kobold_character_card_manager/providers/app_state.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_webview_window/desktop_webview_window.dart';
import 'package:path/path.dart' as path; 
import 'package:kobold_character_card_manager/services/character_repository.dart';
import 'package:kobold_character_card_manager/ui/pages/chat_page.dart';
import 'package:kobold_character_card_manager/services/chat_service.dart';
import 'package:kobold_character_card_manager/services/v2_card_service.dart';
import 'package:kobold_character_card_manager/ui/pages/edit_character_page.dart';
import 'package:kobold_character_card_manager/models/character_card.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CharacterRepository>(
      builder: (context, repo, child) {
        if (repo.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (repo.characters.isEmpty) {
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
                      icon: const Icon(Icons.download), // Changed to download/import
                      label: const Text('Import Card'),
                      style: _buttonStyle(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () => _openBrowser(),
                  icon: const Icon(Icons.public, color: Colors.blueAccent),
                  label: const Text('Browse Repository', style: TextStyle(color: Colors.blueAccent)),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
             Padding(
               padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
               child: Row(
                 children: [
                   Text('My Characters', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
                   const Spacer(),
                   IconButton(
                     tooltip: 'Import Card',
                     icon: const Icon(Icons.download), // Changed to download/import
                     onPressed: () => _importCharacter(context),
                   ),
                   const SizedBox(width: 8),
                   ElevatedButton.icon(
                     onPressed: () => _openBrowser(),
                     icon: const Icon(Icons.public),
                     label: const Text('Get Cards'),
                     style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white),
                   ),
                 ],
               ),
             ),
             Expanded(
               child: GridView.builder(
          padding: const EdgeInsets.all(24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 300,
            childAspectRatio: 0.7,
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemCount: repo.characters.length,
          itemBuilder: (context, index) {
            final character = repo.characters[index];
            return Card(
              color: Theme.of(context).cardColor,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1)),
              ),
              child: Stack( // Changed to Stack for positioning Export button
                children: [
                  InkWell(
                    onTap: () async {
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
                                Text(
                                  character.formattedDescription,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
              ),
            ),
          ],
        );
      },
    );
  }

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

  Future<void> _editCharacter(BuildContext context, CharacterCard character) async {
     await Navigator.push(
       context,
       MaterialPageRoute(builder: (context) => EditCharacterPage(character: character)),
     );
     // Refresh repo after edit
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
        await Provider.of<CharacterRepository>(context, listen: false).importCharacter(file);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Character imported successfully!')));
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
         // Use V2CardService to save
         // We need to import it first, but for now assuming it's available via easy access or we inject it
         // Since I cannot easily add imports in this replace block seamlessly without context, 
         // I will assume V2CardService is available or I will add the import in a separate step if missing.
         // Wait, I can't assume. I should have added the import. 
         // I will add the logic here.
         
         // Assuming V2CardService is in services/v2_card_service.dart
         // I'll need to update imports in a separate step if I missed it.
         // For now, let's implement the call.
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

  Future<void> _openBrowser() async {
    final webview = await WebviewWindow.create(
      configuration: CreateConfiguration(
        title: 'Browse Character Cards',
        titleBarTopPadding: Platform.isMacOS ? 20 : 0,
      ),
    );
    webview.launch('https://aicharactercards.com/');
  }
}

