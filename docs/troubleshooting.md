# Troubleshooting

Diagnosis and fixes for common issues.

---

## Table of Contents

### Startup Issues
- [App won't launch](#app-wont-launch)
- [App crashes on startup](#app-crashes-on-startup)
- [Blank / white screen](#blank--white-screen)
- [Setup wizard doesn't appear](#setup-wizard-doesnt-appear)

### AI / Generation Issues
- [KoboldCpp won't start](#koboldcpp-wont-start)
- [Generation is extremely slow](#generation-is-extremely-slow)
- [Empty responses](#empty-responses)
- [Model won't load (OOM error)](#model-wont-load-oom-error)
- [GPU not detected](#gpu-not-detected)

### Chat Issues
- [Messages not saving](#messages-not-saving)
- [Character responses are cut off](#character-responses-are-cut-off)
- [Realism Engine eval fails](#realism-engine-eval-fails)
- [Memory / RAG not working](#memory--rag-not-working)

### Voice Issues
- [TTS not producing sound](#tts-not-producing-sound)
- [STT / microphone not working](#stt--microphone-not-working)
- [Voice call mode unstable](#voice-call-mode-unstable)

### Data Issues
- [Database corruption](#database-corruption)
- [Missing character images](#missing-character-images)
- [Cloud sync failing](#cloud-sync-failing)
- [Beta vs stable data confusion](#beta-vs-stable-data-confusion)

### Platform-Specific
- [Linux: wpewebkit missing](#linux-wpewebkit-missing)
- [Linux: Wayland flickering](#linux-wayland-flickering)
- [macOS: Apple Silicon performance](#macos-apple-silicon-performance)
- [Windows: Antivirus false positive](#windows-antivirus-false-positive)

---

## Startup Issues

### App won't launch

<!-- TODO: Common causes and fixes:
- Missing dependencies (Linux)
- Corrupted installation
- Port conflicts (web server)
- How to check logs
-->

Placeholder: Ensure all system dependencies are installed. See [Installation Guide](install.md).

### App crashes on startup

<!-- TODO: Crash diagnosis:
- Check crash logs
- Database corruption → restore from backup
- GPU driver issues → try CPU mode
-->

Placeholder: Check the console for error messages. Database corruption is a common cause.

### Blank / white screen

<!-- TODO: UI rendering issues:
- GPU compatibility
- Try different display scaling
- Clear cached data
-->

Placeholder: Usually a GPU rendering issue. Try running with different display settings.

### Setup wizard doesn't appear

<!-- TODO: Missing setup overlay troubleshooting.
-->

Placeholder: The setup wizard runs on first launch. If it doesn't appear, check Settings > AI Settings.

---

## AI / Generation Issues

### KoboldCpp won't start

<!-- TODO: Backend startup failures:
- Port already in use
- Missing executable
- Insufficient permissions
- GPU driver issues
-->

Placeholder: Check that the port is available and GPU drivers are installed.

### Generation is extremely slow

<!-- TODO: Performance troubleshooting:
- Model too large for GPU → layers on GPU
- CPU-only mode → enable GPU acceleration
- Swap thrashing → close other apps
- Quantization recommendations
-->

Placeholder: Most common cause: model is larger than your VRAM. Reduce model size or increase GPU layers.

### Empty responses

<!-- TODO: When the model returns nothing:
- Stop sequence triggered immediately
- System prompt conflict
- Context window full
- Model incompatibility
-->

Placeholder: Check stop sequences and system prompt for conflicts.

### Model won't load (OOM error)

<!-- TODO: Out of memory solutions:
- Use smaller model
- Use higher quantization (Q4_K_M vs Q8_0)
- Reduce context size
- Increase swap space
-->

Placeholder: The model is too large for your available memory. Try a Q4 quantization or smaller model.

### GPU not detected

<!-- TODO: GPU detection issues:
- NVIDIA: CUDA drivers
- AMD: ROCm / Vulkan drivers
- Intel: ARC drivers
- macOS: Metal should auto-work
-->

Placeholder: Ensure GPU drivers are installed. Use Settings > Hardware Detection to diagnose.

---

## Chat Issues

### Messages not saving

<!-- TODO: Save failures:
- Disk full
- Database locked
- Permission issues
-->

Placeholder: Check available disk space and ensure the app has write permissions.

### Character responses are cut off

<!-- TODO: Truncation causes:
- Max length too low
- Context window full
- Stop sequence in response
-->

Placeholder: Increase the max length setting or reduce context size.

### Realism Engine eval fails

<!-- TODO: Eval failures:
- GBNF grammar issue with KoboldCPP
- Model doesn't support JSON output
- Timeout
- Workarounds: one-shot mode, remote API
-->

Placeholder: Known issue with KoboldCPP grammar constraints. Try a remote API or one-shot eval mode.

### Memory / RAG not working

<!-- TODO: Memory system failures:
- Embedding sidecar not running
- ONNX model missing
- Python dependencies
-->

Placeholder: Ensure the embedding server is running. Check that Python dependencies are installed.

---

## Voice Issues

### TTS not producing sound

<!-- TODO: TTS troubleshooting:
- Python installed?
- pip packages installed?
- Correct audio output device?
- Engine-specific issues
-->

Placeholder: Run `pip install kokoro-onnx soundfile` and verify Python is in your PATH.

### STT / microphone not working

<!-- TODO: Microphone issues:
- Permission denied
- Wrong input device selected
- Whisper model not downloaded
-->

Placeholder: Check microphone permissions in your OS settings.

### Voice call mode unstable

<!-- TODO: Call mode issues:
- Background noise triggering send
- Network latency (cloud STT)
- Buffer settings
-->

Placeholder: Adjust silence threshold and buffer sentence count in STT settings.

---

## Data Issues

### Database corruption

<!-- TODO: Recovery steps:
- Auto-detection on launch
- Backup restore overlay
- Manual backup location
- Preventing corruption (clean shutdown)
-->

Placeholder: The app auto-detects corruption on startup. Click a backup to restore.

### Missing character images

<!-- TODO: Orphaned PNG cleanup, path resolution issues.
-->

Placeholder: Character images may need to be re-imported if file paths changed.

### Cloud sync failing

<!-- TODO: Sync error diagnosis:
- Connection issues
- Authentication expired
- Schema version mismatch
- Conflict resolution
-->

Placeholder: Check credentials and ensure both devices run the same app version.

### Beta vs stable data confusion

<!-- TODO: Data directory isolation:
- Beta uses FrontPorchAI-Beta/
- Stable uses FrontPorchAI/
- How to migrate between them
-->

Placeholder: Beta and stable builds use separate data directories. Your data is isolated.

---

## Platform-Specific

### Linux: wpewebkit missing

<!-- TODO: Browser component for Chub.ai import.
-->

Placeholder: Install wpewebkit via your package manager, or use the AppImage which bundles it.

### Linux: Wayland flickering

<!-- TODO: Display server compatibility.
-->

Placeholder: Run with `GDK_BACKEND=x11 ./Front_Porch_AI` to use X11 instead of Wayland.

### macOS: Apple Silicon performance

<!-- TODO: Metal acceleration tips for M-series chips.
-->

Placeholder: Ensure Metal is selected as the GPU backend. Native Apple Silicon builds are optimized.

### Windows: Antivirus false positive

<!-- TODO: Common with unsigned binaries.
-->

Placeholder: Front Porch AI may trigger false positives. Add an exception in your antivirus software.

---

## Getting More Help

- [Discord Community](https://discord.gg/e4tET6rpdv) — live help from users and developers
- [GitHub Issues](https://github.com/linux4life1/front-porch-AI/issues) — report bugs
- [FAQ](faq.md) — answers to common questions

