import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:window_manager/window_manager.dart';
import 'package:front_porch_ai/services/storage_service.dart';
import 'package:front_porch_ai/services/llm_service.dart';
import 'package:path/path.dart' as path;

class KoboldService extends ChangeNotifier with WidgetsBindingObserver, WindowListener implements LLMService {
  final StorageService _storageService;
  Process? _process;
  bool _isRunning = false;
  final List<String> _logs = [];
  String _modelLoadingStatus = '';
  bool _modelReady = false;
  String? _executablePath;

  bool get isRunning => _isRunning;
  List<String> get logs => List.unmodifiable(_logs);
  String get modelLoadingStatus => _modelLoadingStatus;
  bool get modelReady => _modelReady;
  /// Consume the modelReady flag (resets to false after reading).
  bool consumeModelReady() {
    if (_modelReady) {
      _modelReady = false;
      return true;
    }
    return false;
  }
  String _baseUrl = 'http://127.0.0.1:5001';
  String get baseUrl => _baseUrl;
  http.Client? _activeClient;

  // LLMService interface
  @override
  bool get isReady => _isRunning;
  @override
  String get backendName => 'KoboldCPP';

  KoboldService(this._storageService) {
    _purgeLogs();
    WidgetsBinding.instance.addObserver(this);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    windowManager.removeListener(this);
    stopKobold();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      stopKobold();
    }
  }

  @override
  void onWindowClose() async {
    bool isPreventClose = await windowManager.isPreventClose();
    if (isPreventClose) {
      await stopKobold();
      await windowManager.destroy();
    }
  }

  void setBaseUrl(String url) {
    // Force IPv4 for consistency
    String cleanUrl = url.replaceAll('localhost', '127.0.0.1');
    if (cleanUrl.endsWith('/')) {
      _baseUrl = cleanUrl.substring(0, cleanUrl.length - 1);
    } else {
      _baseUrl = cleanUrl;
    }
    notifyListeners();
  }

  File get _logFile => File(path.join(_storageService.rootPath!, 'characters', 'session_log.txt'));

  void _purgeLogs() {
    try {
      if (_storageService.rootPath != null && _logFile.existsSync()) {
        _logFile.deleteSync();
      }
    } catch (e) {
      print('Error purging logs: $e');
    }
  }

  void _writeToLogFile(String data) {
    try {
      if (_storageService.rootPath != null) {
        _logFile.writeAsStringSync(data, mode: FileMode.append);
      }
    } catch (e) {
      // Don't let logging errors crash the app
    }
  }

  Future<void> startKobold(String executablePath, String modelPath, {
    int port = 5001,
    int gpuLayers = 0,
    int contextSize = 4096,
    bool useVulkan = false,
    bool useCublas = false,
    bool useMetal = false,
    bool useRocm = false,
    String? sdModelPath,
  }) async {
    if (_isRunning) return;

    // Store the executable path for cleanup
    _executablePath = executablePath;

    final args = [
      '--model', modelPath,
      '--port', port.toString(),
      '--contextsize', contextSize.toString(),
      '--gpulayers', gpuLayers.toString(),
    ];

    if (useVulkan) args.add('--usevulkan');
    if (useCublas) args.add('--usecublas');
    if (useRocm) {
      args.add('--usehipblas');
      args.add('--noflashattention');  // Flash attention kernel crashes on many AMD GPUs
    }
    // Note: Metal is used automatically on macOS Apple Silicon, no flag needed

    // Stable Diffusion image model
    if (sdModelPath != null && sdModelPath.isNotEmpty && File(sdModelPath).existsSync()) {
      args.addAll(['--sdmodel', sdModelPath]);
    }

    try {
      print('AG_DEBUG: === STARTING KOBOLDCPP ===');
      print('AG_DEBUG: Executable: $executablePath');
      print('AG_DEBUG: Args: ${args.join(' ')}');
      print('AG_DEBUG: Working dir: ${path.dirname(executablePath)}');
      print('AG_DEBUG: File exists: ${File(executablePath).existsSync()}');
      print('AG_DEBUG: Model exists: ${File(modelPath).existsSync()}');
      
      _process = await Process.start(
        executablePath,
        args,
        workingDirectory: path.dirname(executablePath),
      );
      print('AG_DEBUG: Process started successfully! PID: ${_process!.pid}');
      _isRunning = true;
      _modelLoadingStatus = 'Initializing model...';
      _modelReady = false;
      _addLog('Starting Koboldcpp...');
      _addLog('Command: $executablePath ${args.join(' ')}');
      notifyListeners();

      _process!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        _addLog(data.trim());
        _parseLoadingStatus(data);
      });

      _process!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        // Many backends log everything to stderr even if not an error.
        var cleanData = data.trim();
        if (cleanData.isNotEmpty) {
           // Strip ALL occurrences of ERR: and filter out progress dots
           cleanData = cleanData.replaceAll('ERR: ', '').replaceAll('ERR:', '');
           if (cleanData != '.' && cleanData != '..' && cleanData != '...') {
             _addLog(cleanData);
             _parseLoadingStatus(cleanData);
           }
        }
      });

      _process!.exitCode.then((code) {
        _isRunning = false;
        _process = null;
        _addLog('Process exited with code $code');
        notifyListeners();
      });
    } catch (e, stack) {
      print('AG_DEBUG: === KOBOLDCPP START FAILED ===');
      print('AG_DEBUG: Error: $e');
      print('AG_DEBUG: Stack: $stack');
      _addLog('Failed to start process: $e');
      _isRunning = false;
      notifyListeners();
      rethrow;
    }
  }

  Stream<String> _generateStreamInternal(String prompt, {
    int maxLength = 80,
    int minLength = 0,
    double temp = 0.7,
    double repPenalty = 1.1,
    double topP = 0.9,
    double minP = 0.0,
    int repPenTokens = 64,
    double? dynatempRange,
    double xtcThreshold = 0.1,
    double xtcProbability = 0.5,
    List<String>? stopSequences,
    List<String>? bannedPhrases,
  }) async* {
    final uri = Uri.parse('$_baseUrl/api/extra/generate/stream');
    final Map<String, dynamic> payload = {
      'prompt': prompt,
      'max_length': maxLength,
      'min_length': minLength,
      'temperature': temp,
      'rep_pen': repPenalty,
      'top_p': topP,
      'min_p': minP,
      'rep_pen_range': repPenTokens,
      'singleline': false,
      'trim_stop': true,
      'stream': true,
    };

    if (dynatempRange != null && dynatempRange > 0) {
      payload['dynatemp_range'] = dynatempRange;
    }

    if (xtcThreshold > 0 && xtcProbability > 0) {
      payload['xtc_threshold'] = xtcThreshold;
      payload['xtc_probability'] = xtcProbability;
    }

    if (stopSequences != null && stopSequences.isNotEmpty) {
      payload['stop_sequence'] = stopSequences;
    }

    // Anti-slop phrase banning (KoboldCpp-specific)
    if (bannedPhrases != null && bannedPhrases.isNotEmpty) {
      payload['banned_tokens'] = bannedPhrases;
    }

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(payload);

    final client = http.Client();
    _activeClient = client;
    try {
      final response = await client.send(request).timeout(const Duration(seconds: 60));

      if (response.statusCode != 200) {
        if (response.statusCode == 405) {
          throw Exception('STREAMING_NOT_SUPPORTED: The server returned HTTP 405. Streaming may not be supported by this backend.');
        }
        throw Exception('HTTP ${response.statusCode}');
      }

      await for (final line in response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (line.startsWith('data: ')) {
          final data = line.substring(6);
          try {
            final json = jsonDecode(data);
            yield json['token'] as String? ?? '';
          } catch (e) {
            // Skip malformed
          }
        }
      }
    } finally {
      _activeClient = null;
      client.close();
    }
  }

  /// LLMService interface implementation — delegates to the existing method.
  @override
  Stream<String> generateStream(GenerationParams params) {
    return _generateStreamInternal(
      params.prompt,
      maxLength: params.maxLength,
      minLength: params.minLength,
      temp: params.temperature,
      repPenalty: params.repeatPenalty,
      topP: params.topP,
      minP: params.minP,
      repPenTokens: params.repPenTokens,
      dynatempRange: params.dynatempRange,
      xtcThreshold: params.xtcThreshold,
      xtcProbability: params.xtcProbability,
      stopSequences: params.stopSequences,
      bannedPhrases: params.bannedPhrases,
    );
  }

  @override
  void abortGeneration() {
    _activeClient?.close();
    _activeClient = null;
  }

  Future<String> generate(String prompt, {
    int maxLength = 80,
    int minLength = 0,
    double temp = 0.7,
    double repPenalty = 1.1,
    double topP = 0.9,
    double minP = 0.0,
    int repPenTokens = 64,
    double? dynatempRange,
    double xtcThreshold = 0.1,
    double xtcProbability = 0.5,
    List<String>? stopSequences,
    List<String>? bannedPhrases,
  }) async {
    if (!_isRunning && !Platform.environment.containsKey('FLUTTER_TEST')) {
       _addLog('Warning: internal backend not running, trying to connect anyway...');
    }

    int retryCount = 0;
    while (retryCount < 5) {
      final client = http.Client();
      try {
        final uri = Uri.parse('$_baseUrl/api/v1/generate');
        
        final Map<String, dynamic> payload = {
            'prompt': prompt,
            'max_length': maxLength,
            'min_length': minLength,
            'temperature': temp,
            'rep_pen': repPenalty,
            'top_p': topP,
            'min_p': minP,
            'rep_pen_range': repPenTokens,
            'singleline': false,
            'trim_stop': true,
        };

        if (dynatempRange != null && dynatempRange > 0) {
           payload['dynatemp_range'] = dynatempRange;
        }

        if (xtcThreshold > 0 && xtcProbability > 0) {
          payload['xtc_threshold'] = xtcThreshold;
          payload['xtc_probability'] = xtcProbability;
        }

        if (stopSequences != null && stopSequences.isNotEmpty) {
           payload['stop_sequence'] = stopSequences;
        }

        // Anti-slop phrase banning (KoboldCpp-specific)
        if (bannedPhrases != null && bannedPhrases.isNotEmpty) {
          payload['banned_tokens'] = bannedPhrases;
        }
        
        final body = jsonEncode(payload);
        
        final response = await client.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
          },
          body: body,
        ).timeout(const Duration(seconds: 60));
        
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final text = data['results'][0]['text'] as String;
          return text;
        } else {
          if (response.statusCode == 503) {
             _addLog('Server returned 503 (Busy/Loading), retrying...');
             await Future.delayed(const Duration(seconds: 2));
             throw const SocketException('Service Unavailable'); 
          }
          if (response.statusCode == 405) {
             // 405 won't succeed on retry — break immediately
             throw Exception('The server returned HTTP 405 (Method Not Allowed). Check that your API URL is correct and the backend supports this endpoint.');
          }
          if (response.statusCode == 408) {
             throw Exception('Request timed out (HTTP 408). The model may be too slow for the configured timeout.');
          }
          if (response.statusCode == 422) {
             throw Exception('Invalid request (HTTP 422). The prompt may be too long for the model\'s context window.');
          }
          if (response.statusCode >= 500) {
             _addLog('Server error ${response.statusCode}, retrying...');
             await Future.delayed(const Duration(seconds: 2));
             throw Exception('Server error (HTTP ${response.statusCode})');
          }
          throw Exception('API error: HTTP ${response.statusCode}');
        }
      } catch (e) {
        if (!isProcessAlive && _isRunning) {
           _addLog('Backend process crashed during generation! (Likely OOM)');
           throw Exception('Backend process crashed. This usually happens when the GPU runs out of VRAM.');
        }

        retryCount++;
        
        if (retryCount >= 5) {
           _addLog('Generation error after 5 attempts: $e');
           rethrow;
        }
        
        _addLog('Connection failed ($e), retrying in 2s...');
        await Future.delayed(const Duration(seconds: 2)); 
      } finally {
        client.close();
      }
    }
    throw Exception('Failed to generate after retries');
  }

  /// Parse KoboldCPP process output to determine model loading status.
  void _parseLoadingStatus(String data) {
    final lower = data.toLowerCase();

    // Model is ready when server starts listening
    if (lower.contains('please connect to') ||
        lower.contains('server listening') ||
        lower.contains('starting server')) {
      _modelLoadingStatus = '';
      _modelReady = true;
      notifyListeners();
      return;
    }

    // Track loading phases from KoboldCPP output
    if (lower.contains('loading model')) {
      _modelLoadingStatus = 'Loading model into device memory...';
      notifyListeners();
    } else if (lower.contains('loading hf model') || lower.contains('loading gguf')) {
      _modelLoadingStatus = 'Loading model file...';
      notifyListeners();
    } else if (lower.contains('mapping model') || lower.contains('ggml_backend')) {
      _modelLoadingStatus = 'Mapping model to memory...';
      notifyListeners();
    } else if (lower.contains('warming up')) {
      _modelLoadingStatus = 'Warming up model...';
      notifyListeners();
    }
  }

  void _addLog(String data) {
    if (data.trim().isEmpty) return;
    _logs.add(data);
    _writeToLogFile(data);
    if (_logs.length > 1000) _logs.removeAt(0);
    notifyListeners();
  }

  bool get isProcessAlive => _process != null && _isRunning;

  /// Count tokens using the loaded model's actual tokenizer.
  /// Falls back to chars/4 estimate if the endpoint is unavailable.
  Future<int> countTokens(String text) async {
    if (text.isEmpty) return 0;
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/tokencount');
      final client = http.Client();
      try {
        final response = await client.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'prompt': text}),
        ).timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          return (data['value'] as num?)?.toInt() ?? (text.length / 4).ceil();
        }
      } finally {
        client.close();
      }
    } catch (_) {
      // Endpoint unavailable — fall back to estimate
    }
    return (text.length / 4).ceil();
  }

  /// Unload the LLM model from VRAM to free memory for image generation.
  Future<bool> unloadModel() async {
    try {
      final uri = Uri.parse('$_baseUrl/api/extra/unload');
      final client = http.Client();
      try {
        final response = await client.post(uri).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          debugPrint('AG_DEBUG: LLM model unloaded from VRAM');
          return true;
        }
        debugPrint('AG_DEBUG: Unload returned status ${response.statusCode}');
        return false;
      } finally {
        client.close();
      }
    } catch (e) {
      debugPrint('AG_DEBUG: Failed to unload model: $e');
      return false;
    }
  }

  /// Reload the LLM model back into VRAM after image generation.
  /// This pings the /api/v1/model endpoint until the model responds,
  /// triggering KoboldCpp's automatic reload.
  Future<bool> reloadModel({Duration timeout = const Duration(seconds: 60)}) async {
    final stopwatch = Stopwatch()..start();
    while (stopwatch.elapsed < timeout) {
      try {
        final uri = Uri.parse('$_baseUrl/api/v1/model');
        final client = http.Client();
        try {
          final response = await client.get(uri).timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final result = data['result'] ?? '';
            if (result.toString().isNotEmpty && result.toString() != 'inactive') {
              debugPrint('AG_DEBUG: LLM model reloaded: $result');
              return true;
            }
          }
        } finally {
          client.close();
        }
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 2));
    }
    debugPrint('AG_DEBUG: LLM reload timed out after ${timeout.inSeconds}s');
    return false;
  }

  /// Result class for image generation with detailed status.
  static const String genSuccess = 'success';
  static const String genFailedOom = 'oom';
  static const String genFailedTimeout = 'timeout';
  static const String genFailedNoSd = 'no_sd';
  static const String genFailedUnknown = 'error';

  /// Generate an image using KoboldCpp's built-in Stable Diffusion.
  /// Returns a result map with 'status' and optionally 'image' (base64) or 'error' (message).
  Future<Map<String, String>> generateImage({
    required String prompt,
    String negativePrompt = 'blurry, low quality, watermark, text',
    int width = 512,
    int height = 512,
    int steps = 20,
    double cfgScale = 7.0,
  }) async {
    // 1. Check if SD API is even available
    final sdAvailable = await isImageGenAvailable();
    if (!sdAvailable) {
      return {'status': genFailedNoSd, 'error': 'No Stable Diffusion model is loaded. Please select an image model in Settings and restart the backend.'};
    }

    // 2. Attempt generation
    try {
      final uri = Uri.parse('$_baseUrl/sdapi/v1/txt2img');
      final payload = {
        'prompt': prompt,
        'negative_prompt': negativePrompt,
        'width': width,
        'height': height,
        'steps': steps,
        'cfg_scale': cfgScale,
      };

      final client = http.Client();
      try {
        final response = await client.post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        ).timeout(const Duration(minutes: 10)); // Generous timeout for large models

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final images = data['images'] as List<dynamic>?;
          if (images != null && images.isNotEmpty) {
            return {'status': genSuccess, 'image': images.first as String};
          }
          return {'status': genFailedUnknown, 'error': 'Server returned 200 but no images were generated.'};
        }

        // Classify error by status code and response body
        final body = response.body.toLowerCase();
        if (response.statusCode == 500 || response.statusCode == 507) {
          if (body.contains('memory') || body.contains('oom') || body.contains('alloc') || body.contains('vram') || body.contains('out of')) {
            return {'status': genFailedOom, 'error': 'Out of VRAM! The image model is too large for your GPU. Try:\n• Switch to Quality mode (unloads LLM first)\n• Use a smaller model (SD 1.5 instead of SDXL)\n• Reduce image resolution'};
          }
        }

        return {'status': genFailedUnknown, 'error': 'Image generation failed (HTTP ${response.statusCode}): ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}'};
      } finally {
        client.close();
      }
    } on TimeoutException {
      return {'status': genFailedTimeout, 'error': 'Image generation timed out after 10 minutes. The model may be too large for your hardware, or try reducing steps/resolution.'};
    } catch (e) {
      // Check if error message suggests OOM
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('memory') || errStr.contains('alloc') || errStr.contains('oom')) {
        return {'status': genFailedOom, 'error': 'Out of memory during image generation. Try a smaller model or reduce resolution.'};
      }
      return {'status': genFailedUnknown, 'error': 'Image generation error: $e'};
    }
  }

  /// High-level image generation that handles VRAM mode orchestration.
  /// In 'quality' mode: unloads LLM → generates image → reloads LLM.
  /// In 'quick' mode: generates directly (both models coexist).
  /// Always ensures LLM is restored on failure in quality mode.
  Future<Map<String, String>> safeGenerateImage({
    required String prompt,
    required String vramMode, // 'quick' or 'quality'
    String negativePrompt = 'blurry, low quality, watermark, text',
    int width = 512,
    int height = 512,
    int steps = 20,
    double cfgScale = 7.0,
  }) async {
    if (vramMode == 'quality') {
      // Quality mode: unload LLM first for maximum VRAM
      debugPrint('AG_DEBUG: Quality mode — unloading LLM for image generation');
      final unloaded = await unloadModel();
      if (!unloaded) {
        return {'status': genFailedUnknown, 'error': 'Failed to unload the LLM model. Cannot free VRAM for image generation.'};
      }

      // Wait a moment for VRAM to be freed
      await Future.delayed(const Duration(seconds: 2));

      // Generate the image
      Map<String, String> result;
      try {
        result = await generateImage(
          prompt: prompt,
          negativePrompt: negativePrompt,
          width: width,
          height: height,
          steps: steps,
          cfgScale: cfgScale,
        );
      } catch (e) {
        result = {'status': genFailedUnknown, 'error': 'Unexpected error: $e'};
      }

      // ALWAYS reload the LLM — this is the critical recovery step
      debugPrint('AG_DEBUG: Quality mode — reloading LLM after image generation');
      final reloaded = await reloadModel();
      if (!reloaded) {
        // Append a warning to the result
        final existingError = result['error'] ?? '';
        result['error'] = '${existingError}\n⚠️ Warning: The LLM model failed to reload automatically. You may need to restart the backend from Settings.'.trim();
      }

      return result;
    } else {
      // Quick mode: generate directly, both models in VRAM
      return await generateImage(
        prompt: prompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        steps: steps,
        cfgScale: cfgScale,
      );
    }
  }

  /// Estimate whether the current VRAM can handle an SD model of the given file size.
  /// Returns a warning message if VRAM may be insufficient, or null if OK.
  static String? estimateVramWarning({
    required int modelFileSizeMb,
    required int totalVramMb,
    required String vramMode,
    int llmVramEstimateMb = 2048, // Rough estimate of LLM VRAM usage
  }) {
    if (totalVramMb <= 0) return null; // Can't estimate without VRAM info

    // SD models need roughly 1.5x–2x their file size in VRAM when loaded
    final sdVramEstimate = (modelFileSizeMb * 1.8).round();

    if (vramMode == 'quick') {
      // Both models must fit
      final totalNeeded = sdVramEstimate + llmVramEstimateMb;
      if (totalNeeded > totalVramMb) {
        return 'This image model (~${sdVramEstimate}MB) may not fit alongside your LLM (~${llmVramEstimateMb}MB) in ${totalVramMb}MB VRAM.\n'
               'Consider switching to Quality mode, which unloads the LLM during generation.';
      }
    } else {
      // Quality mode: only SD model needs to fit
      if (sdVramEstimate > totalVramMb) {
        return 'This image model (~${sdVramEstimate}MB) may exceed your ${totalVramMb}MB VRAM even with the LLM unloaded.\n'
               'Try a smaller model (e.g. SD 1.5 at ~2GB) or reduce resolution.';
      }
    }
    return null;
  }

  /// Check if the SD image model is loaded and available.
  Future<bool> isImageGenAvailable() async {
    try {
      final uri = Uri.parse('$_baseUrl/sdapi/v1/options');
      final client = http.Client();
      try {
        final response = await client.get(uri).timeout(const Duration(seconds: 3));
        return response.statusCode == 200;
      } finally {
        client.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<void> stopKobold() async {
    if (_process != null) {
      final pid = _process!.pid;
      _addLog('Stopping Backend (PID: $pid)...');
      
      if (Platform.isWindows) {
        try {
          // Force kill process tree on Windows
          await Process.run('taskkill', ['/F', '/T', '/PID', pid.toString()]);
          _addLog('Force killed process tree.');
        } catch (e) {
          _addLog('Taskkill failed, trying standard kill: $e');
          _process!.kill();
        }
      } else {
        // Linux/macOS: Dart's Process.start() does NOT create a new process group,
        // so the child inherits our PGID. We can't use kill(-pid) reliably.
        // Instead: kill all child processes first, then the parent.
        try {
          // Step 1: Kill all child processes of the koboldcpp parent
          _addLog('Killing child processes of PID $pid...');
          await Process.run('pkill', ['-TERM', '-P', pid.toString()]);

          // Step 2: Kill the parent process itself
          _process?.kill(ProcessSignal.sigterm);
          _addLog('Sent SIGTERM to parent and children.');
          
          // Wait up to 3 seconds for graceful shutdown
          bool exited = false;
          for (int i = 0; i < 6; i++) {
            await Future.delayed(const Duration(milliseconds: 500));
            try {
              final check = await Process.run('kill', ['-0', pid.toString()]);
              if (check.exitCode != 0) {
                exited = true;
                break;
              }
            } catch (_) {
              exited = true;
              break;
            }
          }
          
          if (!exited) {
            // Force kill with SIGKILL — children first, then parent
            _addLog('Process did not exit gracefully, sending SIGKILL...');
            await Process.run('pkill', ['-KILL', '-P', pid.toString()]);
            _process?.kill(ProcessSignal.sigkill);
          }

          // Step 3: Final safety net — kill any remaining processes matching the
          // executable name. This catches deeply nested children or processes
          // that reparented to init (PID 1) after their parent was killed.
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            _addLog('Cleaning up any remaining $exeName processes...');
            await Process.run('pkill', ['-KILL', '-f', exeName]);
          }
        } catch (e) {
          _addLog('Process cleanup failed, using fallback: $e');
          _process?.kill(ProcessSignal.sigkill);
          // Still try the executable-name fallback
          if (_executablePath != null) {
            final exeName = path.basename(_executablePath!);
            try {
              await Process.run('pkill', ['-KILL', '-f', exeName]);
            } catch (_) {}
          }
        }
      }
      
      // Wait briefly for process to fully exit before clearing state
      try {
        await _process?.exitCode.timeout(const Duration(seconds: 2));
      } catch (_) {
        // Timeout is fine — we've already sent kill signals
      }
      
      _process = null;
      _isRunning = false;
      _modelLoadingStatus = '';
      _modelReady = false;
      notifyListeners();
    }
  }
}
