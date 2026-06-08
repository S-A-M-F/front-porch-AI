# Rawhide — What's New (Nightlies)

These notes feed the in-app "Update Available" dialog for Rawhide / cutting-edge builds.

## Recent improvements

- 🏗️ **Major god-file modularization (Stages 1–7) landed on Rawhide** — the largest "god files" (chat_service.dart, storage_service, key UI pages, etc.) have been decomposed into focused, single-responsibility modules while preserving 100% behavioral parity for chats, groups, Realism Engine (bond/trust/emotion/arousal/fixation/needs), objectives, fact extraction, character evolution, RAG, prompt injection, and all creator flows. The full test suite is now reliably green (+1126 tests) as the new baseline. This was developed on an isolated branch and is being merged via PR (no history rewrite) to keep Rawhide as the primary development line. See [refactoring-guide.md](refactoring-guide.md) and the branch notes for details.

- 🎯 **Autonomous character objectives now reliably get subtasks** — when the AI (via realism evals) proposes a personal goal for a character ("proposed_objective"), it now properly auto-generates 3 concrete sequential tasks the character can work toward. This was previously unreliable (especially in groups) due to character targeting during per-speaker evals and fragile post-set lookup. User-created objectives (typed manually in the UI) correctly do *not* auto-generate tasks — the player remains in control and can use the Generate Tasks button when desired.

- 🧠 **Thinking/reasoning models now have breathing room for objectives & tasks** — Subtask generation (`generateObjectiveTasks`) and objective/task completion checks bumped from 600/1024 to 2000 max tokens. `<think>...</think>` stripping (now using the central robust helper that also handles unclosed tags) happens after the full stream so models can think at length before emitting the final numbered list or YES/NO. This was broken for most thinking models that reason more than a few hundred tokens. Autonomous proposals already had a generous 4000.

- 🔏 **Fixed macOS notarization** — nightly builds now pass Apple's notary service correctly. Python.framework bundles inside the AI sidecars are now signed as proper framework units (instead of file-by-file), resolving "signature of binary is invalid" and "not signed with valid Developer ID" errors.

- 🐛 **Realism, Needs & Group reliability** — Sidebar bond/trust values + chips now stay in sync; group per-speaker needs, scene rewards (fun/social/hygiene from activities), decay, and cards persist and display correctly with proper pre/post snapshots. Zero-delta chips suppressed, duplicate messages on load fixed, no more needs/fixation/relationship bleed on fresh starts, forks, or imports, and better 1:1 vs group parity for all post-gen effects.

- ✨ **Home screen & daily polish** — Refresh button next to multi-select for re-scanning external character imports. Broader packaging/CI wins for distinct Rawhide nightlies (no name collisions with stable) and many small stability/hygiene improvements.

- 🐛 **Fork to Group Chat member population** — Fixed the bug (originally contributed as PR #44 by @MisterLotto) where forking a 1:1 chat into a group would create a GroupChat with zero members in the decoupled `group_members` table. Both the initial fork path and "add character to existing group" now go through shared creation logic for the avatar copy + DB row. This was held during the god-file modularization to avoid divergence and is now landed on current Rawhide.

