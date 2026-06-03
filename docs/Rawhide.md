# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🎯 **Autonomous character objectives now reliably get subtasks** — when the AI (via realism evals) proposes a personal goal for a character ("proposed_objective"), it now properly auto-generates 3 concrete sequential tasks the character can work toward. This was previously unreliable (especially in groups) due to character targeting during per-speaker evals and fragile post-set lookup. User-created objectives (typed manually in the UI) correctly do *not* auto-generate tasks — the player remains in control and can use the Generate Tasks button when desired.

- 🧠 **Thinking/reasoning models now have breathing room for objectives & tasks** — Subtask generation (`generateObjectiveTasks`) and objective/task completion checks bumped from 600/1024 to 2000 max tokens. `<think>...</think>` stripping (now using the central robust helper that also handles unclosed tags) happens after the full stream so models can think at length before emitting the final numbered list or YES/NO. This was broken for most thinking models that reason more than a few hundred tokens. Autonomous proposals already had a generous 4000.

- 🔏 **Fixed macOS notarization** — nightly builds now pass Apple's notary service correctly. Python.framework bundles inside the AI sidecars are now signed as proper framework units (instead of file-by-file), resolving "signature of binary is invalid" and "not signed with valid Developer ID" errors.

