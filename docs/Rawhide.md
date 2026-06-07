# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## The Big Picture Since Late March 2026

Since the end of March the app has been on a tear:

🎭 **Character Expressions** — portraits now live-react to the tracked emotional state (fast local ONNX or full realism evals, full SillyTavern pack support).

👥 **Group Cards + Clean-Break Group Refactor (v30)** — entire groups (with per-character realism, needs, and system prompts) export/import as portable PNGs. The team did major open-heart surgery: ripped out hidden checkpoints, gave every member proper DB-backed individual state, and enforced full 1:1 parity so the simulation (bond, fixation, objectives, hunger, chaos, the works) doesn't lie when more than one person is in the room.

🧠 **Autonomous Objectives + Needs** — characters propose their own goals and get real subtasks generated (thinking models finally get room). The Sims-style needs layer went atmospheric and personality-driven with proper regen/delete/ group support.

Plus native local image gen (0.9.6), the editor + chaos + time overhaul (0.9.7), beta isolation, .kcpps presets, oMLX, full light mode, and the brutal CI/notarization campaign that turned Mac builds into proper signed, stapled, fancy-DMG production releases.

The linked dispatch below goes full hype on the whole run, including the massive group clean-break refactor and the god-file structural work now starting.

**[Changes Since March 28, 2026 — The Explosion](Newsletter-Since-March-28-2026.md)**

Repo at 39 stars and climbing as people realize their characters are making plans without them.

## Recent improvements

- 🎯 **Autonomous character objectives now reliably get subtasks** — when the AI (via realism evals) proposes a personal goal for a character ("proposed_objective"), it now properly auto-generates 3 concrete sequential tasks the character can work toward. This was previously unreliable (especially in groups) due to character targeting during per-speaker evals and fragile post-set lookup. User-created objectives (typed manually in the UI) correctly do *not* auto-generate tasks — the player remains in control and can use the Generate Tasks button when desired.

- 🧠 **Thinking/reasoning models now have breathing room for objectives & tasks** — Subtask generation (`generateObjectiveTasks`) and objective/task completion checks bumped from 600/1024 to 2000 max tokens. `<think>...</think>` stripping (now using the central robust helper that also handles unclosed tags) happens after the full stream so models can think at length before emitting the final numbered list or YES/NO. This was broken for most thinking models that reason more than a few hundred tokens. Autonomous proposals already had a generous 4000.

- 🔏 **Fixed macOS notarization** — nightly builds now pass Apple's notary service correctly. Python.framework bundles inside the AI sidecars are now signed as proper framework units (instead of file-by-file), resolving "signature of binary is invalid" and "not signed with valid Developer ID" errors.

- 📦 **Switched to `.pkg` Installers on macOS** — the CI pipeline now generates proper, fully signed and stapled `.pkg` installers instead of `.dmg` files. This installs the app cleanly into `/Applications` natively, resolving the remaining Gatekeeper and stapling verification errors from Apple.
