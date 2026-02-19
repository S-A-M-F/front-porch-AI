/// Voice info used across all TTS engines.
class TtsVoiceInfo {
  final String id;
  final String name;
  final String gender;
  final String language;
  final String engine; // 'kokoro', 'openai', 'piper'

  const TtsVoiceInfo({
    required this.id,
    required this.name,
    required this.gender,
    required this.language,
    required this.engine,
  });
}
