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

  bool get isRunning => _isRunning;
  List<String> get logs => List.unmodifiable(_logs);
  String _baseUrl = 'http://127.0.0.1:5001';
  String get baseUrl => _baseUrl;

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
      stopKobold();
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
  }) async {
    if (_isRunning) return;

    final args = [
      '--model', modelPath,
      '--port', port.toString(),
      '--contextsize', contextSize.toString(),
      '--gpulayers', gpuLayers.toString(),
    ];

    if (useVulkan) args.add('--usevulkan');
    if (useCublas) args.add('--usecuda');
    // Note: Metal is used automatically on macOS Apple Silicon, no flag needed

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
      _addLog('Starting Koboldcpp...');
      _addLog('Command: $executablePath ${args.join(' ')}');
      notifyListeners();

      _process!.stdout.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        _addLog(data.trim());
      });

      _process!.stderr.transform(const Utf8Decoder(allowMalformed: true)).listen((data) {
        // Many backends log everything to stderr even if not an error.
        var cleanData = data.trim();
        if (cleanData.isNotEmpty) {
           // Strip ALL occurrences of ERR: and filter out progress dots
           cleanData = cleanData.replaceAll('ERR: ', '').replaceAll('ERR:', '');
           if (cleanData != '.' && cleanData != '..' && cleanData != '...') {
             _addLog(cleanData);
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
    List<String>? stopSequences,
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

    if (stopSequences != null && stopSequences.isNotEmpty) {
      payload['stop_sequence'] = stopSequences;
    }

    final request = http.Request('POST', uri);
    request.headers['Content-Type'] = 'application/json';
    request.body = jsonEncode(payload);

    final client = http.Client();
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
      stopSequences: params.stopSequences,
    );
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
    List<String>? stopSequences,
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

        if (stopSequences != null && stopSequences.isNotEmpty) {
           payload['stop_sequence'] = stopSequences;
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

  void _addLog(String data) {
    if (data.trim().isEmpty) return;
    _logs.add(data);
    _writeToLogFile(data);
    if (_logs.length > 1000) _logs.removeAt(0);
    notifyListeners();
  }

  bool get isProcessAlive => _process != null && _isRunning;

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
        _process!.kill();
      }
      
      _process = null;
      _isRunning = false;
      notifyListeners();
    }
  }
}
