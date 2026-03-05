import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:front_porch_ai/services/model_manager.dart';
import 'package:front_porch_ai/services/image_model_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';

class ModelManagerPage extends StatefulWidget {
  const ModelManagerPage({super.key});

  @override
  State<ModelManagerPage> createState() => _ModelManagerPageState();
}

class _ModelManagerPageState extends State<ModelManagerPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _searchResults = [];
  List<CivitAIModel> _civitaiResults = []; // CivitAI results for image mode
  bool _isSearching = false;
  bool _isImageMode = false; // Tracks which kind of model we're searching for
  bool _allowNsfw = false;   // CivitAI NSFW filter toggle
  String? _selectedBaseModel; // CivitAI base model filter (null = All)

  /// Available base model filters for CivitAI search.
  static const _baseModelFilters = <String, String>{
    'All': '',
    'SD 1.5': 'SD 1.5',
    'SDXL': 'SDXL 1.0',
    'Illustrious': 'Illustrious',
    'Pony': 'Pony',
    'Flux': 'Flux.1 D',
    'SD3': 'SD 3',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      // Track if we're on the Image Models tab
      if (mounted) {
        setState(() {
          _isImageMode = _tabController.index == 2;
        });
      }
    });
    // Refresh models on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<ModelManager>(context, listen: false).refreshModels();
      Provider.of<ImageModelManager>(context, listen: false).refreshModels();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    // LLM search requires a query; image mode allows empty (browse popular)
    if (!_isImageMode && _searchController.text.trim().isEmpty) return;
    
    setState(() {
      _isSearching = true;
      _searchResults = [];
      _civitaiResults = [];
    });

    try {
      if (_isImageMode) {
        // Use CivitAI for image models
        final results = await Provider.of<ImageModelManager>(context, listen: false)
            .searchModels(_searchController.text, allowNsfw: _allowNsfw, baseModelFilter: _selectedBaseModel);
        if (mounted) {
          setState(() {
            _civitaiResults = results;
            _isSearching = false;
          });
        }
      } else {
        // Use HuggingFace for LLMs
        final results = await Provider.of<ModelManager>(context, listen: false)
            .searchHFModels(_searchController.text);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _isSearching = false;
          });
        }
      }
    } catch(e) {
      if (mounted) {
         setState(() {
          _searchResults = [];
          _civitaiResults = [];
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Search failed: $e')));
      }
    }
  }

  void _showDownloadDialog(Map<String, dynamic> modelData) async {
    final repoId = modelData['id'] ?? modelData['modelId'] ?? '';
    if (repoId.isEmpty) return;

    // Show loading dialog while fetching file tree
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    // Only HuggingFace uses file tree fetching
    final files = await Provider.of<ModelManager>(context, listen: false).getModelFiles(repoId);
    
    if (!mounted) return;
    Navigator.pop(context); // Close loading

    if (files.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No .gguf files found in this repo.')),
        );
      }
      return;
    }

    if (!mounted) return;
    
    // Show file selection dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Select File to Download', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: 600,
          height: 400,
          child: ListView.builder(
            itemCount: files.length,
            itemBuilder: (context, index) {
              final file = files[index];
              final sizeMb = (double.tryParse(file['size'] ?? '0') ?? 0) / (1024 * 1024);
              final filename = file['filename']!;
              final url = file['url']!;
              
              return ListTile(
                title: Text(filename, style: const TextStyle(color: Colors.white)),
                subtitle: Text('${sizeMb.toStringAsFixed(2)} MB', style: const TextStyle(color: Colors.white70)),
                trailing: IconButton(
                  icon: const Icon(Icons.download, color: Colors.blueAccent),
                  onPressed: () {
                    Navigator.pop(context);
                    _startDownload(url, filename.split('/').last);
                  },
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  /// Show download options for a CivitAI model.
  void _showCivitaiDownloadDialog(CivitAIModel model) {
    if (model.versions.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          title: Text(model.name, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 600,
            height: 400,
            child: ListView.builder(
              itemCount: model.versions.length,
              itemBuilder: (context, index) {
                final version = model.versions[index];
                final safetensorFile = version.primarySafetensorFile;

                return Card(
                  color: Colors.white.withOpacity(0.05),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                version.name,
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.tealAccent.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                version.baseModel,
                                style: const TextStyle(color: Colors.tealAccent, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (safetensorFile != null) ...[
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    safetensorFile.name,
                                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${safetensorFile.fileSizeLabel} • ${safetensorFile.format}${safetensorFile.fp != null ? " • ${safetensorFile.fp}" : ""}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                                  ),
                                ],
                              ),
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _startDownload(safetensorFile.downloadUrl, safetensorFile.name);
                                },
                                icon: const Icon(Icons.download, size: 16),
                                label: const Text('Download'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blueAccent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ] else
                          const Text(
                            'No SafeTensor files available for this version',
                            style: TextStyle(color: Colors.white30, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _startDownload(String url, String filename) {
    if (_isImageMode) {
      Provider.of<ImageModelManager>(context, listen: false).downloadModel(url, filename).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
        }
      });
      // Auto-switch to image models tab to see progress
      _tabController.animateTo(2);
    } else {
      Provider.of<ModelManager>(context, listen: false).downloadModel(url, filename).catchError((e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Download failed: $e')));
        }
      });
    }
  }

  void _confirmDelete(BuildContext context, String path, {bool isImageModel = false}) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Delete Model?', style: TextStyle(color: Colors.white)),
        content: Text('Are you sure you want to delete ${path.split(Platform.pathSeparator).last}?', 
            style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (isImageModel) {
                Provider.of<ImageModelManager>(context, listen: false).deleteModel(path);
              } else {
                Provider.of<ModelManager>(context, listen: false).deleteModel(path);
              }
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  Future<void> _importLocalModel(BuildContext context, {bool isImageModel = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: isImageModel ? ['safetensors', 'gguf'] : ['gguf'],
      dialogTitle: isImageModel ? 'Select an Image Model to Import' : 'Select a GGUF Model to Import',
    );

    if (result != null && result.files.single.path != null) {
      if (!context.mounted) return;
      try {
        if (isImageModel) {
          await Provider.of<ImageModelManager>(context, listen: false).importLocalModel(result.files.single.path!);
        } else {
          await Provider.of<ModelManager>(context, listen: false).importLocalModel(result.files.single.path!);
        }
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             const SnackBar(content: Text('Model imported successfully!'), backgroundColor: Colors.green),
           );
        }
      } catch (e) {
        if (context.mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(content: Text('Import failed: $e'), backgroundColor: Colors.redAccent),
           );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelManager = Provider.of<ModelManager>(context);
    final imageModelManager = Provider.of<ImageModelManager>(context);

    // If downloading, show comprehensive status at bottom
    final isDownloading = modelManager.isDownloading || imageModelManager.isDownloading;
    // Determine which manager is actively downloading
    final isImageDownloading = imageModelManager.isDownloading;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('Model Manager'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.blueAccent),
            onPressed: () {
              Provider.of<ModelManager>(context, listen: false).refreshModels();
              Provider.of<ImageModelManager>(context, listen: false).refreshModels();
            },
            tooltip: 'Scan for new models',
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'My Models'),
            Tab(text: 'Search / Download'),
            Tab(icon: Icon(Icons.image, size: 18), text: 'Image Models'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: My LLM Models
                _buildMyModelsTab(modelManager),

                // Tab 2: Search / Download
                _buildSearchTab(),

                // Tab 3: Image Models
                _buildImageModelsTab(imageModelManager),
              ],
            ),
          ),
          
          if (isDownloading)
            Container(
              color: const Color(0xFF1E293B),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Row(
                     mainAxisAlignment: MainAxisAlignment.spaceBetween,
                     children: [
                       Expanded(
                         child: Text(
                           'Downloading: ${isImageDownloading ? (imageModelManager.currentDownload ?? "Image Model") : (modelManager.currentDownload ?? "LLM Model")}', 
                           style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                       ),
                       Builder(builder: (context) {
                         final progress = isImageDownloading ? imageModelManager.downloadProgress : modelManager.downloadProgress;
                         if (progress >= 0) {
                           return Text('${(progress * 100).toStringAsFixed(1)}%', 
                               style: const TextStyle(color: Colors.white70));
                         }
                         return const SizedBox.shrink();
                       }),
                     ],
                   ),
                   const SizedBox(height: 8),
                   LinearProgressIndicator(
                     value: isImageDownloading ? imageModelManager.downloadProgress : modelManager.downloadProgress,
                   ),
                   const SizedBox(height: 4),
                   Text(
                     isImageDownloading ? imageModelManager.statusMessage : modelManager.statusMessage, 
                     style: const TextStyle(color: Colors.white54, fontSize: 12),
                   ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMyModelsTab(ModelManager modelManager) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.white.withOpacity(0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Models Folder:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_to_drive, size: 16, color: Colors.amberAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Import from Computer',
                        onPressed: () => _importLocalModel(context),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.drive_file_move, size: 16, color: Colors.orangeAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Change Models Folder',
                        onPressed: () async {
                          final picked = await FilePicker.platform.getDirectoryPath(
                            dialogTitle: 'Select Models Folder',
                          );
                          if (picked != null && mounted) {
                            final storage = Provider.of<StorageService>(context, listen: false);
                            await storage.setCustomModelsPath(picked);
                            if (mounted) {
                              Provider.of<ModelManager>(context, listen: false).refreshModels();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Models folder set to: $picked')),
                              );
                            }
                          }
                        },
                      ),
                      if (Provider.of<StorageService>(context).customModelsPath != null) ...[
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.restore, size: 16, color: Colors.redAccent),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Reset to Default Folder',
                          onPressed: () async {
                            final storage = Provider.of<StorageService>(context, listen: false);
                            await storage.setCustomModelsPath(null);
                            if (mounted) {
                              Provider.of<ModelManager>(context, listen: false).refreshModels();
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Models folder reset to default.')),
                              );
                            }
                          },
                        ),
                      ],
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.folder_open, size: 16, color: Colors.blueAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Open Folder in File Manager',
                        onPressed: () {
                          final folderPath = modelManager.modelsPath;
                          if (Platform.isWindows) {
                            final normPath = folderPath.replaceAll('/', '\\');
                            Process.run('explorer.exe', [normPath]);
                          } else if (Platform.isLinux) {
                            Process.run('xdg-open', [folderPath]);
                          } else if (Platform.isMacOS) {
                            Process.run('open', [folderPath]);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      modelManager.modelsPath,
                      style: const TextStyle(color: Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                  ),
                  if (Provider.of<StorageService>(context).customModelsPath != null)
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('Custom', style: TextStyle(color: Colors.orangeAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
              if (modelManager.statusMessage.contains('Import'))
                 Padding(
                   padding: const EdgeInsets.only(top: 8.0),
                   child: Text(modelManager.statusMessage, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                 ),
            ],
          ),
        ),
        Expanded(
          child: modelManager.models.isEmpty
              ? const Center(child: Text('No models discovered in this folder.', style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: modelManager.models.length,
                  itemBuilder: (context, index) {
                    final file = modelManager.models[index];
                    final filename = file.path.split(Platform.pathSeparator).last;
                    double sizeMb = 0;
                    try {
                       sizeMb = file.statSync().size / (1024 * 1024);
                    } catch (_) {}
                    
                    return Card(
                      color: Colors.white.withOpacity(0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: const Icon(Icons.psychology, color: Colors.purpleAccent),
                        title: Text(filename, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('${sizeMb.toStringAsFixed(2)} MB', style: const TextStyle(color: Colors.white54)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent),
                          onPressed: () => _confirmDelete(context, file.path),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Search mode toggle
              Row(
                children: [
                  Expanded(
                    child: _buildSearchModeChip(
                      label: 'LLM Models',
                      icon: Icons.psychology,
                      isSelected: !_isImageMode,
                      onTap: () => setState(() => _isImageMode = false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildSearchModeChip(
                      label: 'Image Models',
                      icon: Icons.image,
                      isSelected: _isImageMode,
                      onTap: () => setState(() => _isImageMode = true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: _isImageMode
                            ? 'Search CivitAI or paste model URL'
                            : 'Search HuggingFace (e.g. "Mistral 7B")',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: Colors.white.withOpacity(0.05),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Colors.blueAccent),
                          onPressed: _performSearch,
                        ),
                      ),
                      onSubmitted: (_) => _performSearch(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // NSFW toggle — only visible in image mode (CivitAI)
        if (_isImageMode)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => setState(() => _allowNsfw = !_allowNsfw),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _allowNsfw ? Colors.redAccent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: _allowNsfw ? Colors.redAccent.withOpacity(0.5) : Colors.white12,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _allowNsfw ? Icons.visibility : Icons.visibility_off,
                          size: 14,
                          color: _allowNsfw ? Colors.redAccent : Colors.white38,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _allowNsfw ? 'NSFW: On' : 'NSFW: Off',
                          style: TextStyle(
                            fontSize: 11,
                            color: _allowNsfw ? Colors.redAccent : Colors.white38,
                            fontWeight: _allowNsfw ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                // API Key indicator/entry
                Builder(
                  builder: (context) {
                    final storage = Provider.of<StorageService>(context);
                    final hasKey = storage.civitaiApiKey.isNotEmpty;
                    return GestureDetector(
                      onTap: () => _showApiKeyDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: hasKey ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: hasKey ? Colors.green.withOpacity(0.3) : Colors.orange.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              hasKey ? Icons.key : Icons.key_off,
                              size: 12,
                              color: hasKey ? Colors.green : Colors.orange,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              hasKey ? 'API Key Set' : 'API Key Required',
                              style: TextStyle(
                                fontSize: 10,
                                color: hasKey ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        // Base model filter chips — only visible in image mode
        if (_isImageMode)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 16, top: 4, bottom: 4),
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _baseModelFilters.entries.map((entry) {
                  final isActive = (entry.value.isEmpty && _selectedBaseModel == null) ||
                      (_selectedBaseModel == entry.value && entry.value.isNotEmpty);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBaseModel = entry.value.isEmpty ? null : entry.value;
                        });
                        // Always search when filter changes
                        _performSearch();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isActive ? Colors.tealAccent.withOpacity(0.15) : Colors.white.withOpacity(0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isActive ? Colors.tealAccent.withOpacity(0.5) : Colors.white12,
                          ),
                        ),
                        child: Text(
                          entry.key,
                          style: TextStyle(
                            fontSize: 12,
                            color: isActive ? Colors.tealAccent : Colors.white38,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        Expanded(
          child: _isSearching
              ? const Center(child: CircularProgressIndicator())
              : _isImageMode
                  // ── CivitAI Results (Image Models) ──
                  ? _civitaiResults.isEmpty
                      ? const Center(child: Text(
                          'Search for Stable Diffusion models on CivitAI',
                          style: TextStyle(color: Colors.white30)))
                      : ListView.builder(
                          itemCount: _civitaiResults.length,
                          itemBuilder: (context, index) {
                            final model = _civitaiResults[index];
                            return Card(
                              color: Colors.white.withOpacity(0.05),
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: ListTile(
                                leading: const Icon(Icons.image, color: Colors.tealAccent, size: 24),
                                title: Text(model.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: Colors.tealAccent.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            model.baseModel,
                                            style: const TextStyle(color: Colors.tealAccent, fontSize: 10, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          model.fileSizeLabel,
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                        const SizedBox(width: 8),
                                        Icon(Icons.download, size: 12, color: Colors.white.withOpacity(0.3)),
                                        const SizedBox(width: 2),
                                        Text(
                                          _formatDownloads(model.downloadCount),
                                          style: const TextStyle(color: Colors.white38, fontSize: 11),
                                        ),
                                        if (model.rating > 0) ...[
                                          const SizedBox(width: 8),
                                          Icon(Icons.star, size: 12, color: Colors.amber.withOpacity(0.6)),
                                          const SizedBox(width: 2),
                                          Text(
                                            '${model.rating.toStringAsFixed(1)} (${model.ratingCount})',
                                            style: const TextStyle(color: Colors.white38, fontSize: 11),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (model.creatorName != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          'by ${model.creatorName}',
                                          style: TextStyle(color: Colors.white.withOpacity(0.25), fontSize: 10),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white30),
                                onTap: () => _showCivitaiDownloadDialog(model),
                              ),
                            );
                          },
                        )
                  // ── HuggingFace Results (LLMs) ──
                  : _searchResults.isEmpty
                      ? const Center(child: Text(
                          'Search for .gguf models on HuggingFace',
                          style: TextStyle(color: Colors.white30)))
                      : ListView.builder(
                          itemCount: _searchResults.length,
                          itemBuilder: (context, index) {
                            final result = _searchResults[index];
                            return ListTile(
                              leading: const Icon(Icons.psychology, color: Colors.purpleAccent, size: 20),
                              title: Text(result['id'] ?? result['modelId'] ?? 'Unknown', style: const TextStyle(color: Colors.white)),
                              subtitle: Text('Downloads: ${result['downloads'] ?? 0}', style: const TextStyle(color: Colors.white54)),
                              trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white30),
                              onTap: () => _showDownloadDialog(result),
                            );
                          },
                        ),
        ),
      ],
    );
  }

  Widget _buildSearchModeChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blueAccent.withOpacity(0.2) : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.blueAccent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.blueAccent : Colors.white54),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.blueAccent : Colors.white54,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showApiKeyDialog(BuildContext context) {
    final storage = Provider.of<StorageService>(context, listen: false);
    final controller = TextEditingController(text: storage.civitaiApiKey);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('CivitAI API Key', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A free API key is required to download models from CivitAI.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () {
                // Open CivitAI API keys page
                if (Platform.isWindows) {
                  Process.run('cmd', ['/c', 'start', 'https://civitai.com/user/account']);
                } else if (Platform.isLinux) {
                  Process.run('xdg-open', ['https://civitai.com/user/account']);
                } else if (Platform.isMacOS) {
                  Process.run('open', ['https://civitai.com/user/account']);
                }
              },
              child: const Text(
                'Get your free key at civitai.com/user/account →',
                style: TextStyle(color: Colors.blueAccent, fontSize: 12, decoration: TextDecoration.underline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Paste your API key here',
                hintStyle: const TextStyle(color: Colors.white30),
                filled: true,
                fillColor: Colors.white.withOpacity(0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          if (storage.civitaiApiKey.isNotEmpty)
            TextButton(
              onPressed: () {
                storage.setCivitaiApiKey('');
                Navigator.pop(context);
              },
              child: const Text('Clear Key', style: TextStyle(color: Colors.redAccent)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              storage.setCivitaiApiKey(controller.text.trim());
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CivitAI API key saved')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  /// Format download count compactly (e.g., "1.2M", "56K").
  String _formatDownloads(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).toStringAsFixed(1)}K';
    return count.toString();
  }

  Widget _buildImageModelsTab(ImageModelManager imageModelManager) {
    final storage = Provider.of<StorageService>(context);
    final selectedPath = storage.imageGenModel;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          color: Colors.white.withOpacity(0.05),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Image Models Folder:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_to_drive, size: 16, color: Colors.amberAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Import Image Model',
                        onPressed: () => _importLocalModel(context, isImageModel: true),
                      ),
                      const SizedBox(width: 12),
                      IconButton(
                        icon: const Icon(Icons.folder_open, size: 16, color: Colors.tealAccent),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        tooltip: 'Open Folder in File Manager',
                        onPressed: () {
                          final folderPath = imageModelManager.modelsPath;
                          if (Platform.isWindows) {
                            final normPath = folderPath.replaceAll('/', '\\');
                            Process.run('explorer.exe', [normPath]);
                          } else if (Platform.isLinux) {
                            Process.run('xdg-open', [folderPath]);
                          } else if (Platform.isMacOS) {
                            Process.run('open', [folderPath]);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 4),
              SelectableText(
                imageModelManager.modelsPath,
                style: const TextStyle(color: Colors.tealAccent, fontSize: 13, fontWeight: FontWeight.bold),
              ),
              if (imageModelManager.statusMessage.contains('Import'))
                Padding(
                  padding: const EdgeInsets.only(top: 8.0),
                  child: Text(imageModelManager.statusMessage, style: const TextStyle(color: Colors.amberAccent, fontSize: 11)),
                ),
            ],
          ),
        ),
        // Active model indicator
        if (selectedPath.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.tealAccent.withOpacity(0.06),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.tealAccent, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Active: ${selectedPath.split(Platform.pathSeparator).last}',
                    style: const TextStyle(color: Colors.tealAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: imageModelManager.models.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.image_not_supported, color: Colors.white24, size: 48),
                      const SizedBox(height: 12),
                      const Text('No image models found.', style: TextStyle(color: Colors.white54)),
                      const SizedBox(height: 8),
                      const Text(
                        'Download a Stable Diffusion model from the\nSearch / Download tab, or import one.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white30, fontSize: 12),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () {
                          setState(() => _isImageMode = true);
                          _tabController.animateTo(1); // Switch to Search tab
                        },
                        icon: const Icon(Icons.search, size: 16),
                        label: const Text('Search for Image Models'),
                        style: TextButton.styleFrom(foregroundColor: Colors.tealAccent),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: imageModelManager.models.length,
                  itemBuilder: (context, index) {
                    final file = imageModelManager.models[index];
                    final filename = file.path.split(Platform.pathSeparator).last;
                    final isSelected = file.path == selectedPath;
                    double sizeMb = 0;
                    try {
                       sizeMb = file.statSync().size / (1024 * 1024);
                    } catch (_) {}
                    
                    return Card(
                      color: isSelected
                          ? Colors.tealAccent.withOpacity(0.08)
                          : Colors.white.withOpacity(0.05),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isSelected
                            ? const BorderSide(color: Colors.tealAccent, width: 1)
                            : BorderSide.none,
                      ),
                      child: ListTile(
                        leading: Icon(
                          isSelected ? Icons.check_circle : Icons.image,
                          color: isSelected ? Colors.tealAccent : Colors.white38,
                        ),
                        title: Text(
                          filename,
                          style: TextStyle(
                            color: isSelected ? Colors.tealAccent : Colors.white,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          '${sizeMb.toStringAsFixed(2)} MB',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isSelected)
                              TextButton(
                                onPressed: () {
                                  imageModelManager.selectModel(file.path);
                                },
                                child: const Text('Select', style: TextStyle(color: Colors.tealAccent)),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete, color: Colors.redAccent),
                              onPressed: () => _confirmDelete(context, file.path, isImageModel: true),
                            ),
                          ],
                        ),
                        onTap: () {
                          imageModelManager.selectModel(file.path);
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
