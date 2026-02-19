import 'dart:io';
import 'package:front_porch_ai/services/tts_voice_info.dart';

/// Abstract interface that all TTS engines implement.
///
/// Each engine generates a WAV file from text — the TtsService handles 
/// playback, buffering, progress, and lifecycle.
abstract class TtsEngine {
  /// Human-readable engine name, e.g. 'Kokoro', 'OpenAI TTS', 'Piper'.
  String get engineName;

  /// Unique engine identifier: 'kokoro', 'openai', 'piper'.
  String get engineId;

  /// Check if this engine is ready to generate audio.
  Future<bool> get isAvailable;

  /// Generate a WAV audio file from the given text.
  /// Returns null if generation fails.
  Future<File?> generateAudio(String text, String voice, double speed);

  /// List of voices available for this engine.
  List<TtsVoiceInfo> get availableVoices;

  /// Optional: download required model files (e.g. Kokoro first-run).
  /// Returns true if ready, false if download failed.
  /// [onProgress] reports 0.0–1.0 download progress.
  Future<bool> ensureModelReady({void Function(double)? onProgress}) async => true;
}
