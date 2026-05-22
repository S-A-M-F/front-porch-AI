# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Front Porch AI is a Flutter desktop application (Windows/Linux/macOS) for AI-powered character chat using local LLMs via KoboldCpp. It features a "Realism Engine" for emotion/trust/relationship tracking, RAG memory via ONNX embeddings, TTS/STT, cloud sync, and a novel generator.

**License:** AGPL-3.0 (v0.9.0+), GPLv3 (earlier)
**State management:** Provider (migrating to Riverpod for new code)
**Database:** SQLite via Drift ORM

## Key Commands

```bash
# Setup
flutter pub get

# Development
flutter run                          # Debug run
flutter analyze                      # Lint (now at 0 warnings on active rules; CI runs on changed .dart files only for PRs + full scheduled job)
flutter format --set-exit-if-changed .  # Format check

# Tests
flutter test                         # Run all tests
flutter test --coverage              # With coverage
flutter test test/path/to/file.dart  # Single test file
flutter test -n "test name"          # Run specific test by name

# Build embedding server (Rust, required for RAG)
cargo build --release --manifest-path tools/embed_server/Cargo.toml

# Release builds
flutter build linux                  # Linux (then copy embed_server to build/linux/x64/release/bundle/embed_server/)
flutter build windows                # Windows (then copy embed_server.exe to build/windows/x64/runner/Release/)
./scripts/build-macos.sh             # macOS (bundles embed_server automatically)
```

## Architecture

### Directory Structure

```
lib/
├── main.dart                    # Entry point; initializes all services, window config, SIGINT handling
├── app_version.dart             # Version constant + isPreRelease flag
├── database/
│   ├── database.dart            # Drift schema (characters, chats, messages, lorebooks, worlds, etc.)
│   ├── database.g.dart          # Generated Drift code
│   └── data_migration_service.dart
├── models/                      # Data models (character_card.dart, lorebook.dart, world.dart, etc.)
├── providers/
│   └── app_state.dart           # Global app state (ChangeNotifier)
├── services/                    # Business logic (~50 services)
│   ├── chat_service.dart        # Core chat logic, context building, message streaming
│   ├── kobold_service.dart      # KoboldCpp API client
│   ├── llm_provider.dart        # Abstraction over Kobold/OpenRouter/external APIs
│   ├── character_repository.dart # Character CRUD via Drift
│   ├── storage_service.dart     # File system paths, beta/stable data dir isolation
│   ├── embedding_sidecar.dart   # Rust subprocess manager for ONNX embeddings
│   ├── memory_service.dart      # RAG memory extraction and retrieval
│   ├── tts_service.dart         # TTS orchestration (Kokoro, ElevenLabs, OpenAI, Piper)
│   ├── stt_service.dart         # Whisper STT via Python subprocess
│   ├── cloud_sync_service.dart  # Google Drive / WebDAV sync
│   ├── hardware_service.dart    # GPU detection, VRAM estimation
│   ├── backend_manager.dart     # KoboldCpp lifecycle (start/stop/restart)
│   ├── expression_classifier.dart # ONNX/LLM emotion classification
│   └── ...
├── ui/
│   ├── layout/main_layout.dart  # Main shell with sidebar + content area
│   ├── pages/                   # Screen pages (chat_page, home_page, settings_page, etc.)
│   ├── dialogs/                 # Modal dialogs
│   └── widgets/                 # Reusable components (sidebar, chance_time_overlay, etc.)
└── utils/                       # Helpers (emotion_labels, vram_estimator, gguf_parser, etc.)
```

### Critical Services

- **ChatService** (`lib/services/chat_service.dart`): Orchestrates chat sessions, builds context windows, handles message streaming, lorebook injection, Realism Engine evaluation triggers
- **KoboldService** (`lib/services/kobold_service.dart`): HTTP client for KoboldCpp API (`/api/v1/generate`, `/api/extras/abort`, etc.)
- **StorageService** (`lib/services/storage_service.dart`): Manages data directories. Beta builds use `FrontPorchAI-Beta/` with `beta_` prefixed SharedPreferences keys
- **EmbeddingSidecar** (`lib/services/embedding_sidecar.dart`): Manages the Rust `embed_server` subprocess for ONNX-based text embeddings (RAG memory)

### Python Sidecars

TTS and STT use Python subprocesses communicating via JSON over stdin/stdout:
- `kokoro_tts.py` — Kokoro TTS engine
- `whisper_stt.py` — Whisper speech-to-text
- `embed_server.py` — Fallback embedding server (Rust binary preferred)

Protocol: read JSON from stdin → process → write JSON result to stdout → errors to stderr with non-zero exit.

### Database

Drift ORM with SQLite. Schema in `lib/database/database.dart`. Run `dart run build_runner build` after schema changes to regenerate `database.g.dart`.

Key tables: `characters`, `chats`, `chat_messages`, `lorebooks`, `worlds`, `group_chats`, `story_projects`, `learned_facts`, `avatars`

**Important note on external tools**: At least one companion application (Character Card Forge at https://github.com/FrozenKangaroo/Character-Card-Forge) performs direct raw SQL `INSERT`/`UPDATE` operations into the database files (primarily `characters`, `sessions`, `messages`, `avatar_images`, and `sync_meta`). It is the first external tool with deep Front Porch integration, including emotion image export and initial Realism Engine state. Schema changes can break it.

### Realism Engine

A multi-component system spanning chat_service.dart and the LLM provider:
- Emotion tracking with inertia between turns
- Bond/trust relationship scoring (bond clamped to ±300, arousal ±100)
- Deterministic time progression (advances every 6 turns)
- Fixation engine (emotional obsessions)
- Character evolution (trait development)
- Chaos Mode ("Chance Time" random events)
- Escape hatch: `cancelRealismEval()` aborts in-flight evals via `_isCancellingRealismEval` flag + `abortGeneration()`

**Known gotcha**: GBNF grammar constraints cause many KoboldCPP models to return empty eval responses. Evals use stop sequences + regex parsing (no grammar). Remote APIs work fine without grammar.

### Story Pipeline (Porch Stories)

`StoryPipelineService` is created via `ChangeNotifierProxyProvider2` in `main.dart`. The `update` function must NOT return the previous instance early — it must recreate the service with `llmProvider.activeService` each time so backend switches (Kobold ↔ OpenRouter/Nano-GPT) take effect.

## Branch Workflow

- **PRs target `dev`**, never `main`
- `main` is stable releases only
- Beta branches use `0.9.x-Beta` naming with isolated data directories

## Important Constraints

- Beta builds MUST isolate data: `FrontPorchAI-Beta/` directory, `beta_` prefixed SharedPreferences keys
- All AI processing is local/offline by default; cloud APIs (ElevenLabs, OpenRouter) are opt-in
- Character cards follow V2/V2.5 spec (PNG/JSON with embedded metadata)
- Drift database uses UUID primary keys for cloud sync merge compatibility

- **Database schema changes affecting external direct writers**: A community companion app (Character Card Forge) performs direct SQL writes into the database. Any schema modification that could break such tools (non-nullable new columns, removed/renamed columns, structural changes to `characters`/`sessions`/`avatar_images`/`sync_meta`) requires explicit maintainer approval before implementation. See the Database section and "Never touch without discussion" for details.

## Files Requiring Discussion Before Changes

### Never touch without discussion
- `database/migrations/` — schema changes require migration planning. **Do not introduce breaking changes to the database schema (especially columns or tables written to by external tools such as `characters`, `sessions`, `messages`, `avatar_images`, and `sync_meta`) without direct confirmation from the maintainer.** A companion tool (Character Card Forge) relies on direct raw SQL writes into these tables.
- `lib/main.dart` — core service initialization order is delicate
- `pubspec.yaml` — **do not edit unless directly instructed to do so**. The CI/CD pipeline is responsible for normalizing the release version. Local development should use a standard semver (e.g. `0.9.8+1`).
- `analysis_options.yaml` — linting rules
- `scripts/` — release/build scripts

### Sensitive areas (extra caution)
- Authentication and API key handling
- Database queries (performance implications)
- UI layout changes (affect all three desktop platforms)
- Network request patterns
- File system operations

### Require architecture review
- New services or major refactors
- State management changes
- External API integrations
- Performance-critical code paths

## Rules When the Human Cannot Review Code

Because the user has **no ability to read or evaluate Dart code**, the following rules are **non-negotiable** and take precedence over normal task execution:

- **You are the only line of defense.** You must act as a paranoid, hostile reviewer of your own output. Do not assume your changes are clean.
- **Deletion is part of the task, not optional.** Any time you implement or modify behavior, you **must** audit the files you touch for dead code, duplicate logic, or obsolete methods and delete them.
- **New private methods are expensive.** Before creating any new private method or helper, you **must first** check whether an existing method can be extended, generalized, or refactored. Creating new methods is a last resort.
- **Method proliferation is forbidden.** If you introduce more than **two** new private methods while completing a piece of work, you must stop and either consolidate existing logic or explicitly justify in your response why deletion was not possible.
- **Parallel implementations are banned** unless the user explicitly approves. Do not create separate code paths for 1:1 vs group chat, or old vs new systems, without first attempting to unify them.
- **Mandatory commands at the end of non-trivial work** (you must run these and report the results):
  - `flutter analyze --no-fatal-warnings --no-fatal-infos`
  - `dart fix --dry-run` (apply safe fixes where appropriate)
  - Grep/search for recently added methods to verify older similar methods are not now dead

**Hygiene Summary Requirement**: At the end of any response involving non-trivial changes, include a short "Hygiene Summary" covering:
- New private methods added (list them)
- Methods deleted (list them)
- Whether `flutter analyze` is clean
- Any duplication or dead code you chose not to remove and why

## Code Style & Conventions

### Reuse Existing Code
- **Prefer existing variables and scaffolds** — do not add new complexity when not necessary
- **Utilize existing functions whenever possible** — reuse patterns that already work
- **Avoid over-engineering** — simpler solutions are better when they achieve the same goal
- **Leverage shared state** (e.g., `StorageService`) as the single source of truth
- **Consolidate before extending**: When modifying complex areas (especially Realism Engine, Needs simulation, or group chat logic), first attempt to generalize or extend existing methods rather than creating new ones. Creating parallel helpers for similar functionality is not acceptable.

### Verification
- **ALWAYS run `flutter analyze` after making code changes** — the project is now at literal 0 warnings on the active rule set. New code must not introduce any warnings (CI will catch them on changed files in PRs). Never claim changes are "verified" without running it. Variables declared inside `try` blocks are not accessible outside — declare them before the `try` with default values instead.
- **Cross-platform verification is mandatory**. Front Porch AI is a Windows + macOS + Linux desktop app. Every non-trivial change must be checked (or have an explicit plan) to ensure it does not regress on any of the three platforms. This is especially true for file paths, process spawning, Python sidecars, and anything touching `dart:io` or native binaries.
- **Realism & Needs parity is mandatory** (see the dedicated section below). Any change to the Realism Engine or Needs simulation must keep 1:1 and group chat behavior consistent unless explicitly approved otherwise.
- **Because the user cannot review code**, you must treat every change as if it will be accepted without scrutiny. This means you are responsible for leaving the codebase strictly cleaner (or at minimum no worse) than you found it.

### Task Completion Rules
- **No skeleton or partial implementations are allowed.** Never create stub files, placeholder methods containing only TODO comments, incomplete classes, or "skeleton" functionality with the intention of finishing it in a later turn.
- **All tasks must be completed in full during the turn they are started.** If a request (or sub-task) cannot be fully implemented, tested via `flutter analyze`, grepped for dead code, and manually verified as working within a single interaction, do not begin writing the code. Ask the user to clarify scope or break the work into smaller, independently completable pieces instead.
- This rule takes precedence over "getting something started." Partial progress that leaves the codebase in a broken or misleading state is not acceptable.
- Only mark a task complete after it is fully functional and all verification steps (analyze + grep + manual review) have passed.

**Mandatory Cleanup Requirements (especially when the user cannot review code):**
- You **must** delete any code that is no longer reachable or needed as part of completing the task.
- You **must** consolidate duplicate or near-duplicate logic instead of leaving parallel implementations.
- You **must** remove any new private methods that became dead or obsolete during the work.
- "It works" is not sufficient. The codebase must be measurably cleaner (or at least not worse) than when you started the task.

### Realism & Needs System Parity
- The Realism Engine (Bond/Trust/Emotion/Arousal/Fixation) and especially the **Needs/Sims simulation** must maintain full functional parity between single-character (1:1) chats and group chats at all times.
- Any fix, refactor, behavioral change, new feature, or tuning to realism or needs logic **must** be implemented so that both modes receive equivalent treatment, unless the change is explicitly discussed with the user and approved as group-only or 1:1-only.
- Core simulation logic (decay rules, step thresholds, catastrophe text, erotic buffers, etc.) is intentionally shared. When editing these areas, you are responsible for ensuring group per-character behavior does not regress or diverge unintentionally.
- Storage and per-turn orchestration already use branching (`_groupRealism` vs scalar fields, group vs 1:1 paths in `_tickNeedsDecay` and `_getNeedsInjection`). Changes to orchestration are allowed to differ, but the *observable simulation behavior* for a character should feel consistent whether they are in a 1:1 chat or a group.
- When in doubt, default to keeping the two modes in parity. Breaking parity without discussion is considered a regression.

**Anti-Accumulation Rules for Realism/Needs (Critical):**
- Because this area has historically been the largest source of dead code and duplicated helpers, any work touching realism, needs, bond, trust, emotion, fixation, group state, or time progression **requires** an explicit dead code audit of the affected methods in `chat_service.dart`.
- You must actively look for and delete older helper methods (`_getGroup*`, `_loadEvolved*`, `_apply*Decay`, narrative injection variants, etc.) that are made obsolete by new logic.
- Creating new private methods with "Group", "Needs", "Realism", or "Decay" in the name triggers an automatic requirement to review and justify why similar existing methods could not be reused or deleted.

### Cross-Platform Compatibility (Critical)
- **Never hardcode Unix paths** (`/tmp`, `/Users/`, `~/`, etc.). Always use `Directory.systemTemp`, `getApplicationDocumentsDirectory()`, `StorageService.rootPath`, or `path_provider` + `package:path/path.dart` with `p.join()`.
- **Python sidecars** (`kokoro_tts.py`, `whisper_stt.py`, `piper_entry.py`, etc.):
  - Spawning must handle `python` vs `python3` (and ideally `py` launcher on Windows).
  - Use `;` vs `:` for `PYTHONPATH` / `PATH`.
  - Handle `HOME` (Unix) vs `USERPROFILE` (Windows).
  - Prefer PyInstaller one-dir bundles (`.exe` on Windows, executable on Unix) when available; fall back to raw `python + .py` only in dev.
- **Process management**: Use `Process.start(..., includeParentEnvironment: true)` and be prepared for `process.kill()` behavior differences (Unix SIGTERM vs Windows TerminateProcess).
- **Before marking any task "done"**, the responsible agent must either:
  1. Run the affected feature on at least two platforms, or
  2. Explicitly document the platform-specific limitation + mitigation.
- See also the **Task Completion Rules** section above — no skeletons or partial implementations are ever acceptable.

### Dart conventions
- Follow `flutter_lints` rules (see `analysis_options.yaml`)
- camelCase for variables/methods, PascalCase for classes
- Prefix private members with `_`
- Prefer `final` over `var`
- One class per file (except small related classes)
- snake_case for file names

### Import order
1. Dart SDK (`dart:*`)
2. Packages (`package:*`)
3. Local imports (`../`, `./`)

### Riverpod patterns (for new code)
- Use `AsyncNotifier` for async operations
- `ref.watch` for reactive dependencies, `ref.read` for one-time actions
- Proper error handling with `AsyncValue`

### Python sidecar protocol
- Read JSON from stdin → process → write JSON to stdout → errors to stderr with non-zero exit
- Always validate input JSON; catch all exceptions; exit non-zero on failure
- Never write errors to stdout (breaks JSON parsing)

### Error handling
- Never silently swallow errors; always log or surface to user
- Test error conditions explicitly
- Mock external dependencies in unit tests

## Testing Expectations

- Aim for **80%+ coverage** on new code
- Test error conditions and edge cases
- Mock external dependencies
- Test async operations properly

### Reviewing Sub-Agent / AI-Generated Work

When using sub-agents (via `spawn_subagent`) or other AI tooling to produce code changes:

- **Always perform a proper manual code review** of the actual changes before accepting the work.
- Do **not** rely solely on the sub-agent’s self-report or the fact that `flutter analyze` passes.
- Read the modified code, evaluate logic, edge cases, consistency with existing architecture and patterns, and potential regressions or side effects.
- Only mark tasks complete after personal verification of the implementation.
- Sub-agents must **never** produce skeleton code, stub files, or partial implementations. All work returned by a sub-agent must be fully complete and verified per the Task Completion Rules section.

## Commit Messages

Use the conventional commit prefix on the first line (`type(scope): short summary`), but **do not stop there**.

Commit messages must be written for a human who will read the git log months or years later. They should clearly explain:

- What the actual problem was
- Why it mattered (impact on users or developers)
- How it was fixed and why that approach was chosen
- Any important context, gotchas, or trade-offs

**Bad (too terse, unhelpful to humans):**
```
fix(lorebook): correct keyword matching regex to use proper word boundaries
```

**Good (clear and relatable):**
```
fix(lorebook): keyword triggers were completely dead even for single-word keys

The regex in _matchKeyword was written as RegExp(r'\b${key}\b') inside
a Dart raw string. Because raw strings don't interpolate ${}, it was
literally searching for the text "\bkey\b" (with literal backslashes)
instead of using word boundaries.

This meant no keyword-based lorebook entry would ever activate
(isTriggered stayed false), which is why the green dot in the sidebar
never lit up and nothing ever appeared in the Context Viewer — even
when the user typed the exact trigger word like "blorbo" or "ping".

Fixed by using explicit string concatenation instead of ${} inside
a raw string so the regex is actually built correctly.
```

Write like you're explaining the change to a teammate who wasn't in the room when it was made.

## Changelog Tracking

After making any code changes, append an entry to `.claude/changelog.md` with:
- Date (UTC)
- Files changed
- Brief reason for the change
- Commit hash (if committed)

This enables regression tracing — if a bug appears, the changelog shows exactly what changed and why.

## User-Facing Changelog for the Update Dialog (AI Agent Responsibility)

The in-app "Update Available" dialog now renders a non-technical "What's New" section (sourced from the GitHub release body, which the `UpdateService` already fetches). Users who never visit GitHub or Discord rely on this text to discover new features.

**As the AI agent, you are responsible for keeping this text current** (exactly like appending to `.claude/changelog.md`):

- When you complete user-visible work on the active branch (Rawhide, a beta branch, etc.), also update the friendly, non-technical summary.
- Target: short benefit-oriented bullets with emojis (e.g. "🎭 Character Expressions now support sidebar mode — try it in any 1:1 chat").
- Preferred source (strict rule):
  - One file per active branch, named **exactly** the same as the branch (case-sensitive): `docs/<BranchName>.md`
    - On `Rawhide` → edit `docs/Rawhide.md`
    - On the current beta branch (e.g. `0.9.8-Beta`) → edit `docs/0.9.8-Beta.md`
    - On `main` → edit `docs/main.md`
  - This exact naming is required because AI agents hallucinate filenames.
  - Or (alternative): prepare the exact markdown block and post it directly to the GitHub release via tools, or hand the human the precise text to paste.
- Never use raw commit messages, `.claude/changelog.md` contents, or technical PR lists — those are internal.
- `docs/release-notes.md` remains the long-form historical document; the per-branch `docs/<Branch>.md` files are the narrow, dialog-optimized source.
- When you cut or prepare a tagged release, ensure the friendly text for that version is present in the chosen source so it appears immediately in the dialog for users on older builds.

This responsibility is now part of the normal "task complete" checklist for any change that adds or improves end-user features.

## Community

- Discord: https://discord.gg/e4tET6rpdv

## Git Contributions

- You may optionally credit Grok as a co-author for AI-assisted changes using this trailer:
  ```
  Co-authored-by: Grok <grok@x.ai>
  ```
- Never amend or rewrite commits from other authors
- This file (CLAUDE.md) is intended to be committed to the repository so that contributors and their AI agents can follow the project's coding and contribution guidelines.
