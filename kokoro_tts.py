"""
Kokoro TTS helper script for Front Porch AI.
Reads a JSON request from stdin, generates audio via kokoro-onnx, writes WAV.

Usage: python kokoro_tts.py
  Reads one JSON line from stdin:
  {"text":"Hello","voice":"af_heart","speed":1.0,"lang":"en-us","output":"/tmp/out.wav","model":"path/to/kokoro-v1.0.onnx","voices":"path/to/voices-v1.0.bin"}
"""

import sys
import json

try:
    import soundfile as sf
    from kokoro_onnx import Kokoro
except ImportError as e:
    print(f"Missing dependency: {e}", file=sys.stderr)
    sys.exit(1)

def main():
    line = sys.stdin.readline().strip()
    if not line:
        print("No input", file=sys.stderr)
        sys.exit(1)

    try:
        req = json.loads(line)
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(1)

    text = req.get("text", "")
    voice = req.get("voice", "af_heart")
    speed = req.get("speed", 1.0)
    lang = req.get("lang", "en-us")
    output_path = req.get("output", "output.wav")
    model_path = req.get("model", "kokoro-v1.0.onnx")
    voices_path = req.get("voices", "voices-v1.0.bin")

    kokoro = Kokoro(model_path, voices_path)
    samples, sample_rate = kokoro.create(text, voice=voice, speed=speed, lang=lang)
    sf.write(output_path, samples, sample_rate)
    print("OK")

if __name__ == "__main__":
    main()
