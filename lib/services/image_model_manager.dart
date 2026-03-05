import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/storage_service.dart';

/// A search result from CivitAI representing a Stable Diffusion model.
class CivitAIModel {
  final int id;
  final String name;
  final String? description;  // HTML description (may be null)
  final String type;           // "Checkpoint", "LORA", etc.
  final int downloadCount;
  final double rating;
  final int ratingCount;
  final String? creatorName;
  final List<String> tags;
  final List<CivitAIModelVersion> versions;

  /// The base model of the first (latest) version.
  String get baseModel => versions.isNotEmpty ? versions.first.baseModel : 'Unknown';

  /// Best thumbnail URL from latest version sample images.
  String? get thumbnailUrl {
    for (final version in versions) {
      for (final img in version.images) {
        if (img['nsfw'] != true) return img['url'] as String?;
      }
    }
    // Fallback to first image if all are NSFW
    if (versions.isNotEmpty && versions.first.images.isNotEmpty) {
      return versions.first.images.first['url'] as String?;
    }
    return null;
  }

  const CivitAIModel({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    required this.downloadCount,
    required this.rating,
    required this.ratingCount,
    this.creatorName,
    required this.tags,
    required this.versions,
  });

  factory CivitAIModel.fromJson(Map<String, dynamic> json) {
    final stats = json['stats'] as Map<String, dynamic>? ?? {};
    final creator = json['creator'] as Map<String, dynamic>?;
    final versionsList = json['modelVersions'] as List<dynamic>? ?? [];

    return CivitAIModel(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Unknown',
      description: json['description'] as String?,
      type: json['type'] as String? ?? 'Unknown',
      downloadCount: stats['downloadCount'] as int? ?? 0,
      rating: (stats['rating'] as num?)?.toDouble() ?? 0.0,
      ratingCount: stats['ratingCount'] as int? ?? 0,
      creatorName: creator?['username'] as String?,
      tags: (json['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      versions: versionsList
          .map((v) => CivitAIModelVersion.fromJson(v as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Human-readable size of the primary file in the latest version.
  String get fileSizeLabel {
    if (versions.isEmpty) return '';
    final files = versions.first.files;
    if (files.isEmpty) return '';
    final sizeKB = files.first.sizeKB;
    if (sizeKB > 1024 * 1024) return '${(sizeKB / 1024 / 1024).toStringAsFixed(1)} GB';
    if (sizeKB > 1024) return '${(sizeKB / 1024).toStringAsFixed(1)} MB';
    return '${sizeKB.toStringAsFixed(0)} KB';
  }
}

/// A specific version of a CivitAI model.
class CivitAIModelVersion {
  final int id;
  final String name;
  final String baseModel;     // "SD 1.5", "SDXL 1.0", "Flux.1 D", etc.
  final List<CivitAIFile> files;
  final List<Map<String, dynamic>> images;
  final String downloadUrl;

  const CivitAIModelVersion({
    required this.id,
    required this.name,
    required this.baseModel,
    required this.files,
    required this.images,
    required this.downloadUrl,
  });

  factory CivitAIModelVersion.fromJson(Map<String, dynamic> json) {
    final filesList = json['files'] as List<dynamic>? ?? [];
    final imagesList = json['images'] as List<dynamic>? ?? [];

    return CivitAIModelVersion(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      baseModel: json['baseModel'] as String? ?? 'Unknown',
      files: filesList
          .map((f) => CivitAIFile.fromJson(f as Map<String, dynamic>))
          .toList(),
      images: imagesList.cast<Map<String, dynamic>>(),
      downloadUrl: json['downloadUrl'] as String? ?? '',
    );
  }

  /// Get the best SafeTensor file for download.
  CivitAIFile? get primarySafetensorFile {
    // Prefer SafeTensor format, then fall back to any primary file
    final safetensors = files.where((f) => f.format == 'SafeTensor').toList();
    if (safetensors.isNotEmpty) {
      // Prefer pruned over full (smaller download)
      final pruned = safetensors.where((f) => f.size == 'pruned').toList();
      if (pruned.isNotEmpty) return pruned.first;
      return safetensors.first;
    }
    // Fall back to primary file
    return files.isNotEmpty ? files.first : null;
  }
}

/// A downloadable file within a CivitAI model version.
class CivitAIFile {
  final String name;
  final double sizeKB;
  final String format;     // "SafeTensor", "PickleTensor", "Other"
  final String? size;      // "full", "pruned"
  final String? fp;        // "fp16", "fp32"
  final String downloadUrl;

  const CivitAIFile({
    required this.name,
    required this.sizeKB,
    required this.format,
    this.size,
    this.fp,
    required this.downloadUrl,
  });

  factory CivitAIFile.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] as Map<String, dynamic>? ?? {};
    return CivitAIFile(
      name: json['name'] as String? ?? 'unknown',
      sizeKB: (json['sizeKB'] as num?)?.toDouble() ?? 0.0,
      format: metadata['format'] as String? ?? 'Unknown',
      size: metadata['size'] as String?,
      fp: metadata['fp'] as String?,
      downloadUrl: json['downloadUrl'] as String? ?? '',
    );
  }

  /// Human-readable file size.
  String get fileSizeLabel {
    if (sizeKB > 1024 * 1024) return '${(sizeKB / 1024 / 1024).toStringAsFixed(1)} GB';
    if (sizeKB > 1024) return '${(sizeKB / 1024).toStringAsFixed(1)} MB';
    return '${sizeKB.toStringAsFixed(0)} KB';
  }
}

/// Manages image generation models (Stable Diffusion .safetensors and .gguf).
/// Uses CivitAI as the primary search/download source for SD models.
class ImageModelManager extends ChangeNotifier {
  final StorageService _storageService;
  List<FileSystemEntity> _models = [];
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String? _currentDownload;
  String _statusMessage = '';

  /// Last CivitAI search results.
  List<CivitAIModel> _searchResults = [];

  List<FileSystemEntity> get models => List.unmodifiable(_models);
  bool get isDownloading => _isDownloading;
  double get downloadProgress => _downloadProgress;
  String? get currentDownload => _currentDownload;
  String get statusMessage => _statusMessage;
  String get modelsPath => p.normalize(_storageService.imageModelsDir.path);
  List<CivitAIModel> get searchResults => _searchResults;

  /// The currently selected SD model path from storage.
  String get selectedModelPath => _storageService.imageGenModel;

  ImageModelManager(this._storageService) {
    _init();
    _storageService.addListener(_init);
  }

  @override
  void dispose() {
    _storageService.removeListener(_init);
    super.dispose();
  }

  Future<void> _init() async {
    await refreshModels();
  }

  Future<void> refreshModels() async {
    if (_storageService.rootPath == null) return;
    final modelDir = _storageService.imageModelsDir;

    if (await modelDir.exists()) {
      try {
        _models = _safeRecursiveScan(modelDir);
      } catch (e) {
        _models = [];
      }
    } else {
      // Create the directory on first access
      try {
        await modelDir.create(recursive: true);
      } catch (_) {}
      _models = [];
    }
    notifyListeners();
  }

  /// Recursively scans for .safetensors and .gguf image model files.
  List<FileSystemEntity> _safeRecursiveScan(Directory dir) {
    final results = <FileSystemEntity>[];
    try {
      for (final entity in dir.listSync(followLinks: true)) {
        if (entity is Directory) {
          results.addAll(_safeRecursiveScan(entity));
        } else {
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.safetensors') || lower.endsWith('.gguf')) {
            results.add(entity);
          }
        }
      }
    } catch (e) {
      // Skip inaccessible directories
    }
    return results;
  }

  Future<void> importLocalModel(String filePath) async {
    final sourceFile = File(filePath);
    if (!await sourceFile.exists()) {
      throw Exception('Source file does not exist');
    }

    final lower = filePath.toLowerCase();
    if (!lower.endsWith('.safetensors') && !lower.endsWith('.gguf')) {
      throw Exception('File must be a .safetensors or .gguf model');
    }

    final modelDir = _storageService.imageModelsDir;
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    final fileName = p.basename(filePath);
    final destinationPath = p.join(modelDir.path, fileName);

    _statusMessage = 'Importing $fileName...';
    notifyListeners();

    try {
      await sourceFile.copy(destinationPath);
      _statusMessage = 'Imported $fileName';
      await refreshModels();
    } catch (e) {
      _statusMessage = 'Import failed: $e';
      notifyListeners();
      rethrow;
    }
  }

  // ── CivitAI API ─────────────────────────────────────────────────

  static const _civitaiBaseUrl = 'https://civitai.com/api/v1';

  /// Extract a CivitAI model ID from a URL or raw ID string.
  /// Supports: "https://civitai.com/models/2036738/...", "2036738", etc.
  static int? _extractModelId(String input) {
    // Try direct integer parse
    final directId = int.tryParse(input.trim());
    if (directId != null) return directId;

    // Try URL pattern: civitai.com/models/{id}
    final urlPattern = RegExp(r'civitai\.com/models/(\d+)');
    final match = urlPattern.firstMatch(input);
    if (match != null) return int.tryParse(match.group(1)!);

    return null;
  }

  /// Fetch a single model by its CivitAI ID.
  Future<CivitAIModel?> _fetchModelById(int modelId) async {
    try {
      final url = Uri.parse('$_civitaiBaseUrl/models/$modelId');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
      }).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return CivitAIModel.fromJson(data);
      }
    } catch (e) {
      debugPrint('CivitAI: Direct fetch failed for model $modelId: $e');
    }
    return null;
  }

  /// Search CivitAI for Stable Diffusion checkpoint models.
  ///
  /// If the query is a CivitAI URL or model ID, fetches that model directly.
  /// Otherwise uses a triple parallel search strategy:
  ///   1) types=Checkpoint (precise but often returns few results)
  ///   2) Broad search, limit=100 (catches checkpoints buried under LOras)
  ///   3) sort=Newest (surfaces recently-posted models)
  /// Results are merged, deduped, and sorted by download count.
  Future<List<CivitAIModel>> searchModels(String query, {String? baseModelFilter, bool allowNsfw = false}) async {
    final trimmed = query.trim();

    // ── Direct model lookup via URL or ID ──
    final modelId = _extractModelId(trimmed);
    if (modelId != null) {
      debugPrint('CivitAI: Direct lookup for model ID $modelId');
      final model = await _fetchModelById(modelId);
      if (model != null && model.versions.isNotEmpty) {
        _searchResults = [model];
        notifyListeners();
        return _searchResults;
      }
      _searchResults = [];
      notifyListeners();
      return [];
    }

    // ── Search by query ──
    final baseParams = <String, String>{
      'sort': 'Most Downloaded',
      'nsfw': allowNsfw.toString(),
    };

    // Optional filter by base model (e.g., "SD 1.5", "SDXL 1.0")
    if (baseModelFilter != null && baseModelFilter.isNotEmpty) {
      baseParams['baseModels'] = baseModelFilter;
    }

    try {
      List<http.Response> responses;

      if (trimmed.isEmpty) {
        // ── Browse mode: empty query → single fast request ──
        // types=Checkpoint works perfectly without a query string
        debugPrint('CivitAI: Browsing popular checkpoints...');
        final browseParams = Map<String, String>.from(baseParams)
          ..['types'] = 'Checkpoint'
          ..['limit'] = '50';
        final browseUrl = Uri.parse('$_civitaiBaseUrl/models').replace(queryParameters: browseParams);
        final response = await http.get(browseUrl, headers: {
          'Content-Type': 'application/json',
        }).timeout(const Duration(seconds: 15));
        responses = [response];
      } else {
        // ── Query mode: triple parallel search ──
        // CivitAI's types=Checkpoint + query returns almost nothing,
        // so we fire three requests and merge client-side.
        debugPrint('CivitAI: Searching for "$trimmed"...');
        final targetedParams = Map<String, String>.from(baseParams)
          ..['query'] = trimmed
          ..['types'] = 'Checkpoint'
          ..['limit'] = '20';
        final broadParams = Map<String, String>.from(baseParams)
          ..['query'] = trimmed
          ..['limit'] = '100';
        final newestParams = Map<String, String>.from(baseParams)
          ..['query'] = trimmed
          ..['sort'] = 'Newest'
          ..['limit'] = '50';

        final targetedUrl = Uri.parse('$_civitaiBaseUrl/models').replace(queryParameters: targetedParams);
        final broadUrl = Uri.parse('$_civitaiBaseUrl/models').replace(queryParameters: broadParams);
        final newestUrl = Uri.parse('$_civitaiBaseUrl/models').replace(queryParameters: newestParams);

        responses = await Future.wait([
          http.get(targetedUrl, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 15)),
          http.get(broadUrl, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 15)),
          http.get(newestUrl, headers: {'Content-Type': 'application/json'}).timeout(const Duration(seconds: 15)),
        ]);
      }

      final seenIds = <int>{};
      final merged = <CivitAIModel>[];

      for (final response in responses) {
        if (response.statusCode == 200) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final items = body['items'] as List<dynamic>? ?? [];
          for (final item in items) {
            final model = CivitAIModel.fromJson(item as Map<String, dynamic>);
            if (model.versions.isNotEmpty &&
                model.type == 'Checkpoint' &&
                !seenIds.contains(model.id)) {
              seenIds.add(model.id);
              merged.add(model);
            }
          }
        }
      }

      // Sort merged results by download count (most popular first)
      merged.sort((a, b) => b.downloadCount.compareTo(a.downloadCount));

      _searchResults = merged;
      debugPrint('CivitAI: Found ${_searchResults.length} checkpoint models');
      notifyListeners();
      return _searchResults;
    } catch (e) {
      debugPrint('CivitAI: Search error: $e');
    }
    _searchResults = [];
    notifyListeners();
    return [];
  }

  /// Download a model file from CivitAI.
  /// Appends API token for authentication if available.
  Future<void> downloadModel(String url, String filename) async {
    if (_isDownloading) return;
    if (_storageService.rootPath == null) return;

    // Append CivitAI API token if available
    final apiKey = _storageService.civitaiApiKey;
    String downloadUrl = url;
    if (apiKey.isNotEmpty) {
      final uri = Uri.parse(url);
      final params = Map<String, String>.from(uri.queryParameters)..['token'] = apiKey;
      downloadUrl = uri.replace(queryParameters: params).toString();
    }

    _isDownloading = true;
    _currentDownload = filename;
    _downloadProgress = 0.0;
    _statusMessage = 'Initializing download...';
    notifyListeners();

    try {
      final modelDir = _storageService.imageModelsDir;
      if (!await modelDir.exists()) {
        await modelDir.create(recursive: true);
      }

      final savePath = p.join(modelDir.path, filename);

      final client = http.Client();
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('Failed to download: HTTP ${response.statusCode}');
      }

      final contentLength = response.contentLength ?? 0;
      int received = 0;
      final file = File(savePath);
      final sink = file.openWrite();

      DateTime lastUpdateTime = DateTime.now();
      int lastBytes = 0;

      _statusMessage = 'Downloading...';
      notifyListeners();

      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;

          final now = DateTime.now();
          if (now.difference(lastUpdateTime).inMilliseconds >= 500) {
            final timeDiff = now.difference(lastUpdateTime).inMilliseconds / 1000.0;
            final bytesDiff = received - lastBytes;
            final speed = bytesDiff / timeDiff;

            String speedStr = _formatSpeed(speed);
            String etaStr = '';

            if (contentLength > 0 && speed > 0) {
              final remainingBytes = contentLength - received;
              final remainingSec = remainingBytes / speed;
              etaStr = ' - ETA: ${_formatDuration(Duration(seconds: remainingSec.round()))}';
            }

            if (contentLength > 0) {
              _downloadProgress = received / contentLength;
              _statusMessage = 'Downloading: ${(_downloadProgress * 100).toStringAsFixed(1)}% ($speedStr)$etaStr';
            } else {
              _statusMessage = 'Downloading: ${(received / 1024 / 1024).toStringAsFixed(1)} MB ($speedStr)';
            }

            notifyListeners();
            lastUpdateTime = now;
            lastBytes = received;
          }
        }
      } finally {
        await sink.flush();
        await sink.close();
        client.close();
      }

      _isDownloading = false;
      _currentDownload = null;
      _statusMessage = 'Download complete';
      await refreshModels();
      notifyListeners();
    } catch (e) {
      _isDownloading = false;
      _currentDownload = null;
      _statusMessage = 'Error: $e';
      notifyListeners();
      rethrow;
    }
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec < 1024) return '${bytesPerSec.toStringAsFixed(1)} B/s';
    if (bytesPerSec < 1024 * 1024) return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds.remainder(60)}s';
    return '${d.inSeconds}s';
  }

  Future<void> deleteModel(String path) async {
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      // If this was the selected model, clear selection
      if (_storageService.imageGenModel == path) {
        await _storageService.setImageGenModel('');
      }
      await refreshModels();
    }
  }

  /// Select a model as the active image generation model.
  Future<void> selectModel(String path) async {
    await _storageService.setImageGenModel(path);
    notifyListeners();
  }
}
