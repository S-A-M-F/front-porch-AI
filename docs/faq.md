# Frequently Asked Questions

---

## Table of Contents

### General
- [Is Front Porch AI free?](#is-front-porch-ai-free)
- [Is my data private?](#is-my-data-private)
- [What platforms are supported?](#what-platforms-are-supported)
- [Do I need an internet connection?](#do-i-need-an-internet-connection)

### AI & Models
- [What AI models can I use?](#what-ai-models-can-i-use)
- [How do I choose a model?](#how-do-i-choose-a-model)
- [Can I use OpenAI / Claude / Google models?](#can-i-use-openai--claude--google-models)
- [Why is the AI slow?](#why-is-the-ai-slow)
- [Why does the AI give repetitive answers?](#why-does-the-ai-give-repetitive-answers)

### Characters
- [Where can I find characters?](#where-can-i-find-characters)
- [How do I import characters from SillyTavern?](#how-do-i-import-characters-from-sillytavern)
- [Why isn't my character acting right?](#why-isnt-my-character-acting-right)

### Voice
- [Why isn't TTS working?](#why-isnt-tts-working)
- [How do I improve voice quality?](#how-do-i-improve-voice-quality)
- [Why does voice call mode keep triggering?](#why-does-voice-call-mode-keep-triggering)

### Realism Engine
- [What is the Realism Engine?](#what-is-the-realism-engine)
- [Does the Realism Engine slow down chat?](#does-the-realism-engine-slow-down-chat)
- [How do I reset a character's bond/trust?](#how-do-i-reset-a-characters-bondtrust)

### Technical
- [How do I back up my data?](#how-do-i-back-up-my-data)
- [Where is my data stored?](#where-is-my-data-stored)
- [How do I fix a corrupted database?](#how-do-i-fix-a-corrupted-database)
- [Can I run Front Porch AI on a server?](#can-i-run-front-porch-ai-on-a-server)

---

## General

### Is Front Porch AI free?

<!-- TODO: Confirm pricing model. Mention AGPL-3.0 license. -->

Yes — Front Porch AI is free and open-source software (AGPL-3.0). Optional cloud services (ElevenLabs, OpenRouter) have their own pricing.

### Is my data private?

<!-- TODO: Privacy model:
- Local models = all processing on your machine
- Cloud APIs = data sent to their servers
- Cloud sync = encrypted to your Google Drive / WebDAV
-->

When using local models, all processing happens on your machine. No chat data is sent to any external server.

### What platforms are supported?

<!-- TODO: Confirm current support matrix.
-->

Windows, macOS (Intel and Apple Silicon), and Linux (via package managers or AppImage).

### Do I need an internet connection?

<!-- TODO: Clarify offline vs online requirements:
- Local mode: no internet needed after setup
- External API mode: requires internet
- Cloud sync: requires internet
- TTS cloud engines: require internet
-->

If using local AI models, no internet is required after initial setup. External APIs and cloud features need connectivity.

---

## AI & Models

### What AI models can I use?

<!-- TODO: Model compatibility:
- GGUF format models via KoboldCpp
- Any model supported by llama.cpp
- Recommended model sizes by VRAM
- External API models via OpenRouter
-->

Placeholder: Any GGUF model that works with KoboldCpp. Recommended: Llama 3, Mistral, Mixtral, Qwen.

### How do I choose a model?

<!-- TODO: Decision guide based on hardware:
- VRAM requirements
- Quality vs speed trade-offs
- Model personality differences
-->

Placeholder: Choose based on your GPU memory and desired quality.

### Can I use OpenAI / Claude / Google models?

<!-- TODO: External API support via OpenRouter.
-->

Yes — via OpenRouter integration in Settings > AI Settings.

### Why is the AI slow?

<!-- TODO: Common causes:
- Model too large for GPU (swapping to RAM)
- CPU-only mode
- Insufficient VRAM
- Background processes
-->

Placeholder: Usually means the model is too large for your GPU. Try a smaller model or quantization.

### Why does the AI give repetitive answers?

<!-- TODO: Fix:
- Increase temperature
- Adjust repetition penalty
- Check system prompt
- Model quality issues
-->

Placeholder: Adjust temperature and repetition penalty settings.

---

## Characters

### Where can I find characters?

<!-- TODO: Character sources:
- Chub.ai
- Character Hub
- Community Discord
- User-created
-->

Placeholder: Chub.ai, the Community Discord, or create your own.

### How do I import characters from SillyTavern?

<!-- TODO: Import process for SillyTavern cards.
-->

Placeholder: SillyTavern V2 cards import directly via drag-and-drop or file picker.

### Why isn't my character acting right?

<!-- TODO: Common causes:
- Poorly written character card
- Model too small for complex characters
- Missing message examples
- System prompt conflicts
- Temperature too high/low
-->

Placeholder: Usually a card quality or model capability issue. Check the character fields and try a larger model.

---

## Voice

### Why isn't TTS working?

<!-- TODO: Common TTS issues:
- Python not installed
- Missing pip packages
- Wrong engine selection
- API key not configured (cloud engines)
-->

Placeholder: Ensure Python is installed and `pip install kokoro-onnx soundfile`.

### How do I improve voice quality?

<!-- TODO: Tips for better TTS:
- Use ElevenLabs for highest quality
- Kokoro settings
- Model selection
-->

Placeholder: ElevenLabs offers the best quality; Kokoro is the best local option.

### Why does voice call mode keep triggering?

<!-- TODO: Silence detection tuning.
-->

Placeholder: Adjust the silence threshold in STT settings.

---

## Realism Engine

### What is the Realism Engine?

See [Realism Engine](realism-engine.md) for the full guide.

### Does the Realism Engine slow down chat?

<!-- TODO: Performance impact explanation.
-->

Placeholder: Yes — it adds one or two extra LLM calls per turn. Use one-shot eval mode to reduce overhead.

### How do I reset a character's bond/trust?

<!-- TODO: How to reset realism state.
-->

Placeholder: Start a new chat session, or look for the reset option in chat settings.

---

## Technical

### How do I back up my data?

<!-- TODO: Backup options:
- Auto-backup (every 10 minutes)
- Manual backup
- Cloud sync
- Data directory location
-->

Placeholder: Front Porch AI auto-backs up every 10 minutes. You can also enable cloud sync.

### Where is my data stored?

<!-- TODO: Platform-specific data directories:
- Windows: %APPDATA%/FrontPorchAI/
- macOS: ~/Library/Application Support/FrontPorchAI/
- Linux: ~/.local/share/FrontPorchAI/
- Beta builds use FrontPorchAI-Beta/
-->

Placeholder: Data is stored in your system's application data directory.

### How do I fix a corrupted database?

<!-- TODO: Database recovery process:
- Auto-detection on launch
- Backup restoration overlay
- Manual repair steps
-->

Placeholder: The app detects corruption on startup and offers to restore from backup.

### Can I run Front Porch AI on a server?

<!-- TODO: Headless operation, web server feature.
-->

Placeholder: Yes — enable the built-in web server for remote access via browser.

