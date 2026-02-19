import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:front_porch_ai/services/tts_engine.dart';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// OpenAI TTS engine — cloud-based premium quality TTS.
///
/// Uses the OpenAI Audio API to generate speech.
/// Requires an API key.
class OpenAiTtsEngine implements TtsEngine {
  String apiKey;
  String model;

  OpenAiTtsEngine({this.apiKey = '', this.model = 'tts-1'});
  static int _fileCounter = 0;

  @override
  String get engineName => 'OpenAI TTS';

  @override
  String get engineId => 'openai';

  @override
  Future<bool> get isAvailable async => apiKey.isNotEmpty;

  @override
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async => true;

  @override
  Future<File?> generateAudio(String text, String voice, double speed) async {
    if (apiKey.isEmpty) {
      print('OpenAI TTS: no API key configured');
      return null;
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/audio/speech'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: '{"model":"$model","input":${_jsonEscape(text)},"voice":"$voice","response_format":"wav","speed":$speed}',
      );

      if (response.statusCode != 200) {
        print('OpenAI TTS error: ${response.statusCode} ${response.body}');
        return null;
      }

      // Write response body (WAV audio) to temp file
      final tempDir = Directory.systemTemp;
      _fileCounter++;
      final outputFile = File(p.join(tempDir.path,
          'openai_tts_${DateTime.now().millisecondsSinceEpoch}_$_fileCounter.wav'));
      await outputFile.writeAsBytes(response.bodyBytes);

      return outputFile;
    } catch (e) {
      print('OpenAI TTS error: $e');
      return null;
    }
  }

  /// JSON-escape a string value.
  String _jsonEscape(String text) {
    return '"${text.replaceAll('\\', '\\\\').replaceAll('"', '\\"').replaceAll('\n', '\\n').replaceAll('\r', '\\r')}"';
  }

  @override
  List<TtsVoiceInfo> get availableVoices => _voices;

  static const _voices = [
    TtsVoiceInfo(id: 'alloy', name: 'Alloy', gender: 'Neutral', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'ash', name: 'Ash', gender: 'Male', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'ballad', name: 'Ballad', gender: 'Male', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'coral', name: 'Coral', gender: 'Female', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'echo', name: 'Echo', gender: 'Male', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'fable', name: 'Fable', gender: 'Male', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'onyx', name: 'Onyx', gender: 'Male', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'nova', name: 'Nova', gender: 'Female', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'sage', name: 'Sage', gender: 'Female', language: 'Multilingual', engine: 'openai'),
    TtsVoiceInfo(id: 'shimmer', name: 'Shimmer', gender: 'Female', language: 'Multilingual', engine: 'openai'),
  ];
}
