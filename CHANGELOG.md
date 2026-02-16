# Changelog

All notable changes to Front Porch AI will be documented in this file.

## [v0.0.3.4] - 2026-02-16

### ✨ New Features
- **Smooth Output Buffer**: Intelligent token buffering system that delivers AI responses at a consistent, readable pace regardless of hardware speed.
  - Adaptive TPS measurement using a rolling 3-second window — responds to speed fluctuations in real-time.
  - Optimal buffer formula (`maxTokens × (1 - genTps / targetTps)`) starts display as early as mathematically possible without interruptions.
  - Auto-pause & rebuild: if generation speed drops mid-response, display pauses briefly and re-buffers to maintain smooth flow.
  - Real-time tokens-per-second counter shown in the generation bar.
- **Configurable Display Speed**: New settings in Chat Settings dialog:
  - Toggle smooth output buffer on/off (no-buffer mode for raw streaming).
  - Slider to set target display speed (5–60 t/s, default 6 t/s ≈ 250 WPM average human reading speed).
- **Alt Greetings in Character Creator**: Add alternate greeting messages when creating new characters.

### 🐛 Bug Fixes
- Fix `{{char}}` placeholder replacement being inconsistent across cards and chat.
- Fix sidebar title truncation on long character names.
- Fix backend auto-start race condition by awaiting StorageService initialization.

### 📝 Documentation
- Added open source philosophy and community links (Discord, Matrix) to README.
- Added screenshots inline with feature sections.
- Added Smooth Output Buffer feature documentation.

---

## [v0.0.3] - 2026-02-14

### ✨ New Features
- **Virtual Folders**: Organize characters into folders for better collection management.
- **Tag System**: Tag characters and filter your collection.
- **Global Search**: Search across all characters by name, tags, or description.
- **Multiple System Prompts**: Save and switch between multiple system prompt presets. Includes built-in "Immersive Roleplay" default.
- **Intel ARC Support**: Hardware detection now supports Intel ARC and shared memory GPUs.

---

## [v0.0.2] - 2026-02-13

### ✨ New Features
- **macOS Stability**: Native quarantine management and sandbox-free backend execution.
- **Stop Generation**: Halt AI generation mid-stream with one click.
- **Message Editing**: Edit any message (User or AI) in-place.
- **Auto-Import**: Web-to-chat import integration with `aicharactercards.com` and `chub.ai` via internal browser.

---

## [v0.0.1] - 2026-02-12

### 🎉 Initial Release
- V2 character card support (PNG & JSON).
- Import/export character cards.
- Metadata editor for character details and lorebooks.
- KoboldCPP integration with automated download and hardware detection.
- Real-time streaming chat with persistent sessions.
- HuggingFace model hub integration.
- World building with dynamic keyword-based context injection.
- Cross-platform support (Windows, macOS, Linux).
